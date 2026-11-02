import Foundation
import Security

/// 已下载并校验、等待替换的更新。
struct PreparedUpdate: Sendable {
    let script: URL
    let downloadedApp: URL
    let currentApp: URL
    let workRoot: URL

    /// 启动替换脚本；调用方随后退出应用，脚本等进程结束再替换并重新打开。
    func launch() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [script.path, downloadedApp.path, currentApp.path,
                             String(ProcessInfo.processInfo.processIdentifier), workRoot.path]
        try process.run()
    }
}

/// 下载 `.app.zip`，要求解出的 App 满足当前 App 的 designated requirement
/// （同 Bundle ID、同签名团队）。屏幕录制授权使用同一份签名要求，替换后保持有效。
struct UpdateInstaller: Sendable {
    func prepare(_ release: Release, currentVersion: AppVersion) async throws -> PreparedUpdate {
        guard let archiveURL = release.archiveURL else { throw UpdateError(message: "该版本没有可自动安装的更新包。") }
        let currentApp = Bundle.main.bundleURL
        guard currentApp.pathExtension == "app" else { throw UpdateError(message: "当前程序不在 .app 包内运行。") }
        guard Self.signingTeam() != nil else {
            throw UpdateError(message: "当前 App 未使用开发者证书签名，无法校验更新，请手动下载安装。")
        }
        guard FileManager.default.isWritableFile(atPath: currentApp.deletingLastPathComponent().path) else {
            throw UpdateError(message: "没有权限替换 \(currentApp.path)，请手动安装。")
        }

        let fileManager = FileManager.default
        let workRoot = fileManager.temporaryDirectory.appendingPathComponent("XScreenCaptureUpdate-\(UUID().uuidString)", isDirectory: true)
        let extracted = workRoot.appendingPathComponent("Extracted", isDirectory: true)
        do {
            try fileManager.createDirectory(at: extracted, withIntermediateDirectories: true)
            var request = URLRequest(url: archiveURL)
            request.setValue("XScreenCapture/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (download, response) = try await URLSession.shared.download(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else { throw UpdateError(message: "下载失败：HTTP \(status)。") }
            let archive = workRoot.appendingPathComponent("update.app.zip")
            try fileManager.moveItem(at: download, to: archive)
            try Task.checkCancellation()

            let output = try Self.run("/usr/bin/ditto", ["-x", "-k", archive.path, extracted.path])
            guard output.status == 0 else { throw UpdateError(message: "无法解压更新包：\(output.text)") }
            guard let app = Self.findApp(in: extracted) else { throw UpdateError(message: "更新包中没有 XScreenCapture.app。") }
            try Self.validate(app, release: release, currentVersion: currentVersion)

            let script = workRoot.appendingPathComponent("install-update.sh")
            try Self.installerScript.write(to: script, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
            return PreparedUpdate(script: script, downloadedApp: app, currentApp: currentApp, workRoot: workRoot)
        } catch {
            try? fileManager.removeItem(at: workRoot)
            throw error
        }
    }

    private static func findApp(in directory: URL) -> URL? {
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil,
                                                        options: .skipsHiddenFiles)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension.lowercased() == "app" else { continue }
            enumerator?.skipDescendants()
            if Bundle(url: url)?.bundleIdentifier == Bundle.main.bundleIdentifier { return url }
        }
        return nil
    }

    private static func validate(_ app: URL, release: Release, currentVersion: AppVersion) throws {
        let raw = Bundle(url: app)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let version = AppVersion(raw ?? "")
        guard raw != nil, version >= release.version, version > currentVersion else {
            throw UpdateError(message: "下载的 App 版本（\(raw ?? "未知")）不比当前版本新。")
        }
        var selfCode: SecCode?
        var selfStatic: SecStaticCode?
        var requirement: SecRequirement?
        var downloaded: SecStaticCode?
        var status = SecCodeCopySelf([], &selfCode)
        if status == errSecSuccess, let selfCode { status = SecCodeCopyStaticCode(selfCode, [], &selfStatic) }
        if status == errSecSuccess, let selfStatic { status = SecCodeCopyDesignatedRequirement(selfStatic, [], &requirement) }
        if status == errSecSuccess { status = SecStaticCodeCreateWithPath(app as CFURL, [], &downloaded) }
        var validationError: Unmanaged<CFError>?
        if status == errSecSuccess, let downloaded {
            // 校验全部嵌套代码，并要求与当前 App 相同的签名身份。
            let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
            status = SecStaticCodeCheckValidityWithErrors(downloaded, flags, requirement, &validationError)
        }
        guard status == errSecSuccess else {
            let reason = validationError?.takeRetainedValue().localizedDescription ?? "OSStatus \(status)"
            throw UpdateError(message: "下载的 App 签名与当前 App 不一致：\(reason)")
        }
    }

    static func signingTeam() -> String? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
        else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private static func run(_ path: String, _ arguments: [String]) throws -> (status: Int32, text: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return (process.terminationStatus, text)
    }

    // 等待当前进程退出后替换 App；复制失败时恢复旧版本。
    private static let installerScript = """
        #!/bin/zsh
        set -euo pipefail
        source_app="$1"
        target_app="$2"
        app_pid="$3"
        work_root="$4"
        backup_app="${target_app}.previous-update"
        while /bin/kill -0 "$app_pid" 2>/dev/null; do /bin/sleep 0.2; done
        /bin/rm -rf "$backup_app"
        [ -d "$target_app" ] && /bin/mv "$target_app" "$backup_app"
        if /usr/bin/ditto "$source_app" "$target_app"; then
          /usr/bin/xattr -dr com.apple.quarantine "$target_app" 2>/dev/null || true
          /usr/bin/open "$target_app"
          /bin/rm -rf "$backup_app" "$work_root"
        else
          /bin/rm -rf "$target_app"
          [ -d "$backup_app" ] && /bin/mv "$backup_app" "$target_app" && /usr/bin/open "$target_app"
          exit 1
        fi

        """
}
