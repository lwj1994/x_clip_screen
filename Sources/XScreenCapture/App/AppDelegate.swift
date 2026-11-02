import AppKit
import AppleViewModel

/// 应用根：持有各模块的生命周期，并把 ViewModel 发出的提示呈现为弹窗。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var capture: CaptureViewModel { viewModelBinding.read(captureSpec) }
    private var shortcut: ShortcutViewModel { viewModelBinding.read(shortcutSpec) }
    private var permission: PermissionViewModel { viewModelBinding.read(permissionSpec) }
    private var status: StatusViewModel { viewModelBinding.read(statusSpec) }
    private var update: UpdateViewModel { viewModelBinding.read(updateSpec) }

    private var menuController: StatusMenuController?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 先注册偏好缺省值，截图引擎启动时直接读取。
        _ = viewModelBinding.read(settingsSpec)
        do {
            try capture.load()
        } catch {
            presentAlert(error.localizedDescription)
            NSApp.terminate(nil)
            return
        }
        do { try shortcut.register() } catch { status.post(error.localizedDescription) }

        // 弹窗会进入模态 run loop，推迟到状态通知派发结束之后。
        viewModelBinding.listenStateSelect(statusSpec, selector: { $0.alert }) { [weak self] _, alert in
            guard alert != nil else { return }
            Task { @MainActor in self?.presentStatusAlert() }
        }
        viewModelBinding.listenStateSelect(updateSpec, selector: { $0.prompt }) { [weak self] _, prompt in
            guard prompt != nil else { return }
            Task { @MainActor in self?.presentUpdatePrompt() }
        }

        menuController = StatusMenuController(showSettings: { [weak self] in self?.showSettings() })
        showSettings()
        update.startAutomaticChecks()
    }

    func showSettings() {
        guard !capture.isCapturing else { return }
        if settingsWindow == nil { settingsWindow = SettingsWindowController() }
        settingsWindow?.present()
    }

    func applicationDidBecomeActive(_ notification: Notification) { permission.refresh() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        settingsWindow?.cancelShortcutRecording()
        capture.cancel()
    }

    private func presentStatusAlert() {
        guard let message = status.state.alert else { return }
        status.dismissAlert()
        presentAlert(message)
    }

    private func presentUpdatePrompt() {
        guard let prompt = update.state.prompt else { return }
        update.dismissPrompt()
        switch prompt {
        case .upToDate(let version):
            _ = runAlert("已是最新版本", "当前版本 \(version)。", buttons: ["好"])
        case .checkFailed(let message):
            _ = runAlert("检查更新失败", message, buttons: ["好"])
        case .available(let release):
            let primary = release.archiveURL == nil ? "前往下载" : "安装并重新打开"
            let response = runAlert("XScreenCapture \(release.version) 可用",
                                    "当前版本 \(AppVersion.current)。安装后会自动重新打开，屏幕录制授权保持不变。",
                                    buttons: [primary, "查看发布说明", "稍后"])
            if response == .alertFirstButtonReturn, release.archiveURL != nil {
                update.install(release)
            } else if response == .alertFirstButtonReturn || response == .alertSecondButtonReturn {
                NSWorkspace.shared.open(release.pageURL)
            }
        case .installFailed(let message, let page):
            if runAlert("无法安装更新", message, buttons: ["查看发布页面", "好"]) == .alertFirstButtonReturn {
                NSWorkspace.shared.open(page)
            }
        }
    }

    private func presentAlert(_ message: String) {
        _ = runAlert("XScreenCapture", message, buttons: ["好"])
    }

    private func runAlert(_ title: String, _ message: String, buttons: [String]) -> NSApplication.ModalResponse {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        buttons.forEach { alert.addButton(withTitle: $0) }
        return alert.runModal()
    }
}
