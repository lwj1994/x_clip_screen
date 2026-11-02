import AppKit
import AppleViewModel
import ObjectiveC

/// 屏幕录制授权状态与 PermissionFlow 引导。
@MainActor
final class PermissionViewModel: ViewModel {
    private var status: StatusViewModel { viewModelBinding.read(statusSpec) }

    var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// 系统设置中授权后回到前台时调用，让观察者重新读取状态。
    func refresh() { notifyListeners() }

    /// rect 使用 AppKit 屏幕坐标，作为引导动画的起点。
    func showGuide(from rect: NSRect) {
        if Self.showPermissionFlow(from: rect) {
            status.post("授权后如仍未就绪，请退出并重新打开 XScreenCapture。")
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            // 资源/桥接加载失败时仍保留系统入口，不阻塞授权。
            NSWorkspace.shared.open(url)
        }
    }

    /// 桥接 dylib 与其资源 bundle 一同随 App 搬移，按需 dlopen，不直接链接 PermissionFlow。
    private static func showPermissionFlow(from rect: NSRect) -> Bool {
        guard let frameworks = Bundle.main.privateFrameworksURL,
              dlopen(frameworks.appendingPathComponent("libXClipPermissionBridge.dylib").path, RTLD_NOW | RTLD_GLOBAL) != nil,
              let guide = NSClassFromString("XCPermissionGuide") else { return false }
        let selector = NSSelectorFromString("showFromRect:")
        guard let method = class_getClassMethod(guide, selector) else { return false }
        typealias Show = @convention(c) (AnyClass, Selector, NSRect) -> Void
        unsafeBitCast(method_getImplementation(method), to: Show.self)(guide, selector, rect)
        return true
    }
}
