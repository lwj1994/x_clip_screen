#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 使用 sRGB 的 #RRGGBB 字符串保存选框颜色；缺省值为 #0099FF。
FOUNDATION_EXPORT NSString * const XCSelectionBorderColorDefaultsKey;
FOUNDATION_EXPORT NSColor *XCSelectionBorderColor(void);
FOUNDATION_EXPORT void XCSetSelectionBorderColor(NSColor *color);

/// 在 framework 加载后、创建截图管理器之前从主线程调用；重复调用安全。
FOUNDATION_EXPORT BOOL XCInstallCaptureAppearance(NSError * _Nullable * _Nullable error);

/// 每次 JTStartCapture 之前从主线程调用，开始新的手动拖拽框选会话。
/// 初始只有遮罩；鼠标移动和单击不选择窗口，拖动松开后才确认选区。
FOUNDATION_EXPORT void XCPrepareManualCapture(void);

NS_ASSUME_NONNULL_END
