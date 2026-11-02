#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, XCToolbarIcon) {
    XCToolbarIconRectangle,
    XCToolbarIconEllipse,
    XCToolbarIconArrow,
    XCToolbarIconPen,
    XCToolbarIconMosaic,
    XCToolbarIconText,
    XCToolbarIconNumber,
    XCToolbarIconUndo,
    XCToolbarIconSave,
    XCToolbarIconCancel,
    XCToolbarIconDone,
};

typedef NS_ENUM(NSUInteger, XCToolbarIconState) {
    XCToolbarIconStateNormal,
    XCToolbarIconStateHover,
    XCToolbarIconStateSelected,
    XCToolbarIconStatePressed,
    XCToolbarIconStateDisabled,
};

/// Load unmodified 1x/2x toolbar artwork from the extracted QQ-theme directory.
FOUNDATION_EXPORT BOOL XCLoadQQToolbarIcons(NSURL *directory);

/// Center the native 24-point QQ image in the framework button canvas.
FOUNDATION_EXPORT NSImage * _Nullable XCToolbarIconImage(XCToolbarIcon icon, NSSize size, XCToolbarIconState state);
FOUNDATION_EXPORT NSString *XCToolbarIconLabel(XCToolbarIcon icon);

NS_ASSUME_NONNULL_END
