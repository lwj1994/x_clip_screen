import Foundation

/// 按数字段比较版本号，忽略 v 前缀和非数字后缀；缺失段视为 0。
struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    let rawValue: String
    let components: [Int]

    init(_ rawValue: String) {
        self.rawValue = rawValue
        components = rawValue.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    }

    static var current: AppVersion {
        AppVersion(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0")
    }

    var description: String { rawValue.hasPrefix("v") ? String(rawValue.dropFirst()) : rawValue }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool { !(lhs < rhs) && !(rhs < lhs) }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.components.count, rhs.components.count) {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}

struct Release: Equatable, Sendable {
    let version: AppVersion
    let pageURL: URL
    /// `XScreenCapture-<版本>.app.zip`；缺失时只能打开发布页面手动下载。
    let archiveURL: URL?

    static func == (lhs: Release, rhs: Release) -> Bool {
        lhs.version.rawValue == rhs.version.rawValue && lhs.pageURL == rhs.pageURL && lhs.archiveURL == rhs.archiveURL
    }
}

struct UpdateError: LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }
}

/// 匿名读取 GitHub 最新 Release。
struct GitHubReleaseClient: Sendable {
    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/lwj1994/x_clip_screen/releases/latest")!

    let endpoint: URL

    init(endpoint: URL? = nil) {
        // XCLIP_UPDATE_API 仅用于本地验证更新流程。
        let override = ProcessInfo.processInfo.environment["XCLIP_UPDATE_API"].flatMap(URL.init(string:))
        self.endpoint = endpoint ?? override ?? Self.latestReleaseAPI
    }

    func latestRelease() async throws -> Release {
        var request = URLRequest(url: endpoint, timeoutInterval: 30)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("XScreenCapture/\(AppVersion.current)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw UpdateError(message: "GitHub 返回 HTTP \(status)。") }
        return try Self.parse(data)
    }

    static func parse(_ data: Data) throws -> Release {
        struct Payload: Decodable {
            struct Asset: Decodable {
                let name: String
                let browser_download_url: URL
            }
            let tag_name: String
            let html_url: URL
            let assets: [Asset]
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              !AppVersion(payload.tag_name).components.isEmpty else {
            throw UpdateError(message: "GitHub 返回的发布信息无法识别。")
        }
        let archive = payload.assets.first {
            let name = $0.name.lowercased()
            return name.hasPrefix("xscreencapture") && name.hasSuffix(".app.zip")
        }
        return Release(version: AppVersion(payload.tag_name), pageURL: payload.html_url,
                       archiveURL: archive?.browser_download_url)
    }
}
