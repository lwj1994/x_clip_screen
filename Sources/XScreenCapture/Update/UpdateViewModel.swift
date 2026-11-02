import AppKit
import AppleViewModel

/// 需要用户回应的更新结果；AppDelegate 弹窗后调用 `dismissPrompt()`。
enum UpdatePrompt: Equatable {
    case upToDate(AppVersion)
    case checkFailed(String)
    case available(Release)
    case installFailed(String, page: URL)

    static func == (lhs: UpdatePrompt, rhs: UpdatePrompt) -> Bool {
        switch (lhs, rhs) {
        case let (.upToDate(a), .upToDate(b)): a.rawValue == b.rawValue
        case let (.checkFailed(a), .checkFailed(b)): a == b
        case let (.available(a), .available(b)): a == b
        case let (.installFailed(a, pageA), .installFailed(b, pageB)): a == b && pageA == pageB
        default: false
        }
    }
}

struct UpdateState: Equatable {
    enum Phase: Equatable { case idle, checking, installing }
    var phase: Phase = .idle
    var prompt: UpdatePrompt?
}

/// 从 GitHub Release 检查并安装更新，自动检查间隔 24 小时。
@MainActor
final class UpdateViewModel: StateViewModel<UpdateState> {
    static let automaticInterval: TimeInterval = 24 * 60 * 60

    private let defaults: UserDefaults
    private let client: GitHubReleaseClient
    private let installer: UpdateInstaller
    private let currentVersion: AppVersion
    private var automaticChecksStarted = false

    private var settings: SettingsViewModel { viewModelBinding.read(settingsSpec) }
    private var capture: CaptureViewModel { viewModelBinding.read(captureSpec) }

    init(defaults: UserDefaults, client: GitHubReleaseClient, installer: UpdateInstaller,
         currentVersion: AppVersion = .current) {
        self.defaults = defaults
        self.client = client
        self.installer = installer
        self.currentVersion = currentVersion
        super.init(state: UpdateState(), equals: { $0 == $1 })
    }

    var isBusy: Bool { state.phase != .idle }

    /// 启动后 3 秒检查一次，之后每小时判断是否已满 24 小时。
    func startAutomaticChecks() {
        guard !automaticChecksStarted else { return }
        automaticChecksStarted = true
        taskScope.task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            while !Task.isCancelled {
                self?.checkIfDue()
                try? await Task.sleep(for: .seconds(60 * 60))
            }
        }
    }

    func checkForUpdates() { check(userInitiated: true) }

    func install(_ release: Release) {
        guard !isBusy else { return }
        mutate { $0.phase = .installing; $0.prompt = nil }
        let installer = installer
        let currentVersion = currentVersion
        // 下载、解压与签名校验在后台执行。
        let worker = taskScope.io { () async -> Result<PreparedUpdate, any Error> in
            do { return .success(try await installer.prepare(release, currentVersion: currentVersion)) }
            catch { return .failure(error) }
        }
        taskScope.task { [weak self] in
            let result = await worker.value
            guard let self, !Task.isCancelled else { return }
            do {
                try result.get().launch()
                NSApp.terminate(nil)
            } catch {
                if case .success(let prepared) = result { try? FileManager.default.removeItem(at: prepared.workRoot) }
                self.mutate { $0.phase = .idle; $0.prompt = .installFailed(error.localizedDescription, page: release.pageURL) }
            }
        }
    }

    func dismissPrompt() {
        guard state.prompt != nil else { return }
        mutate { $0.prompt = nil }
    }

    private func checkIfDue() {
        guard settings.state.automaticUpdateCheck else { return }
        if let last = defaults.object(forKey: DefaultsKey.lastUpdateCheck) as? Date,
           -last.timeIntervalSinceNow < Self.automaticInterval { return }
        check(userInitiated: false)
    }

    private func check(userInitiated: Bool) {
        guard !isBusy else { return }
        mutate { $0.phase = .checking }
        let client = client
        taskScope.task { [weak self] in
            let result: Result<Release, any Error>
            do { result = .success(try await client.latestRelease()) } catch { result = .failure(error) }
            guard let self, !Task.isCancelled else { return }
            self.finishCheck(result, userInitiated: userInitiated)
        }
    }

    private func finishCheck(_ result: Result<Release, any Error>, userInitiated: Bool) {
        mutate { $0.phase = .idle }
        let release = try? result.get()
        let newer = release.map { $0.version > currentVersion } ?? false
        // 截图中不弹窗，也不记录检查时间，下一轮再提示。
        if !userInitiated, newer, capture.isBusy { return }
        defaults.set(Date(), forKey: DefaultsKey.lastUpdateCheck)
        let prompt: UpdatePrompt?
        switch (result, newer) {
        case (.failure(let error), _): prompt = userInitiated ? .checkFailed(error.localizedDescription) : nil
        case (.success(let release), true): prompt = .available(release)
        case (.success, false): prompt = userInitiated ? .upToDate(currentVersion) : nil
        }
        if let prompt { mutate { $0.prompt = prompt } }
    }

    private func mutate(_ change: (inout UpdateState) -> Void) {
        var next = state
        change(&next)
        setState(next)
    }
}
