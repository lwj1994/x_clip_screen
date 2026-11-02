#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 使用 sRGB 的 #RRGGBB 字符串保存选框颜色；缺省值为 #0099FF。
FOUNDATION_EXPORT NSString * const XCSelectionBorderColorDefaultsKey;
FOUNDATION_EXPORT NSColor *XCSelectionBorderColor(void);
/// 偏好写入后调用，让正在显示的选区立即使用新颜色。
FOUNDATION_EXPORT void XCRefreshSelectionBorderColor(void);

/// 在 framework 加载后、创建截图管理器之前从主线程调用；重复调用安全。
FOUNDATION_EXPORT BOOL XCInstallCaptureAppearance(NSError * _Nullable * _Nullable error);

/// 每次 JTStartCapture 之前从主线程调用，开始新的框选会话。
/// 鼠标悬停高亮所在窗口，单击确认该窗口；也可拖动框选任意区域。
FOUNDATION_EXPORT void XCPrepareManualCapture(void);

NS_ASSUME_NONNULL_END
