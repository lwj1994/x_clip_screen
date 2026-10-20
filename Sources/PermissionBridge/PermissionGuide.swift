import AppKit
import PermissionFlow

/// AppKit 宿主通过 dlopen 和 Objective-C runtime 调用，避免直接链接 Swift 模块。
@MainActor
@objc(XCPermissionGuide)
public final class XCPermissionGuide: NSObject {
    // 静态持有 controller，让切换到系统设置后的悬浮引导与动画保持活跃。
    private static let controller = PermissionFlow.makeController(
        configuration: PermissionFlowConfiguration(
            requiredAppURLs: [Bundle.main.bundleURL],
            promptForAccessibilityTrust: false,
            localeIdentifier: "zh-Hans"
        )
    )

    /// 必须在主线程调用；rect 使用 AppKit 屏幕坐标。
    @objc(showFromRect:)
    public static func show(fromRect rect: NSRect) {
        controller.authorize(
            pane: .screenRecording,
            sourceFrameInScreen: rect
        )
    }

    /// 供宿主自检定位实际资源 bundle，不打开设置、不请求任何权限。
    @objc(resourceBundlePath)
    public static func resourceBundlePath() -> String? {
        PermissionFlowResources.packageBundle?.bundleURL.path
    }
}
