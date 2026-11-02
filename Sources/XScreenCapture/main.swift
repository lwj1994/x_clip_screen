import AppKit
import XClipEngine

// --self-test 只加载截图框架并核对接口，不截图、不请求权限。
if CommandLine.arguments.dropFirst().elementsEqual(["--self-test"]) {
    let engine = XCCaptureEngine()
    var report: [String: Any]
    var success = true
    do {
        try engine.load()
        report = Dictionary(uniqueKeysWithValues: engine.diagnostics().map { ("\($0.key)", $0.value) })
    } catch {
        report = ["error": error.localizedDescription]
        success = false
    }
    let json = (try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    print(String(decoding: json, as: UTF8.self))
    exit(success ? 0 : 1)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
