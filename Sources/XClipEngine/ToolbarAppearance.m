#import "ToolbarAppearance.h"
#import "ToolbarIcons.h"
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <math.h>

// ABI verified against analysis/framework-toolbar-metadata.txt.
@protocol XCToolbarAppearanceABI <NSObject>
- (NSInteger)type;
- (void)setNormalImage:(NSImage *)image;
- (void)setHoverImage:(NSImage *)image;
- (void)setSelectedImage:(NSImage *)image;
- (void)setPressedImage:(NSImage *)image;
- (void)setDisabledImage:(NSImage *)image;
@end

static void (*XCOriginalButtonConfiguration)(id, SEL);
static Class XCGraphButtonClass;
static Class XCFunctionButtonClass;

static BOOL XCIconForButton(NSButton<XCToolbarAppearanceABI> *button, XCToolbarIcon *icon) {
    if ([button isKindOfClass:XCGraphButtonClass]) {
        switch (button.type) {
            case 1: *icon = XCToolbarIconRectangle; return YES;
            case 2: *icon = XCToolbarIconEllipse; return YES;
            case 3: *icon = XCToolbarIconArrow; return YES;
            case 4: *icon = XCToolbarIconText; return YES;
            case 5: *icon = XCToolbarIconPen; return YES;
            case 6: *icon = XCToolbarIconMosaic; return YES;
            case 7: *icon = XCToolbarIconNumber; return YES;
            default: return NO;
        }
    }
    if ([button isKindOfClass:XCFunctionButtonClass]) {
        switch (button.type) {
            case 1: *icon = XCToolbarIconUndo; return YES;
            case 3: *icon = XCToolbarIconSave; return YES;
            case 4: *icon = XCToolbarIconCancel; return YES;
            case 5: *icon = XCToolbarIconDone; return YES;
            default: return NO;
        }
    }
    return NO;
}

static void XCConfigureToolbarButton(id object, SEL selector) {
    XCOriginalButtonConfiguration(object, selector);
    NSButton<XCToolbarAppearanceABI> *button = object;
    XCToolbarIcon icon;
    if (!XCIconForButton(button, &icon)) return;
    NSSize size = button.bounds.size;
    if (!isfinite(size.width) || !isfinite(size.height) || size.width < 12 || size.height < 12) return;

    [button setNormalImage:XCToolbarIconImage(icon, size, XCToolbarIconStateNormal)];
    [button setHoverImage:XCToolbarIconImage(icon, size, XCToolbarIconStateHover)];
    [button setSelectedImage:XCToolbarIconImage(icon, size, XCToolbarIconStateSelected)];
    [button setPressedImage:XCToolbarIconImage(icon, size, XCToolbarIconStatePressed)];
    [button setDisabledImage:XCToolbarIconImage(icon, size, XCToolbarIconStateDisabled)];
    button.toolTip = XCToolbarIconLabel(icon);
    button.accessibilityLabel = XCToolbarIconLabel(icon);
    [button setNeedsDisplay:YES];
}

BOOL XCInstallToolbarAppearance(void) {
    if (XCOriginalButtonConfiguration) return YES;
    if (!NSThread.isMainThread) return NO;
    Class buttonClass = NSClassFromString(@"JTToolbarButton");
    Class graphClass = NSClassFromString(@"JTToolbarGraphButton");
    Class functionClass = NSClassFromString(@"JTToolbarFunctionButton");
    if (!buttonClass || !graphClass || !functionClass
        || ![buttonClass isSubclassOfClass:NSButton.class]
        || ![graphClass isSubclassOfClass:buttonClass]
        || ![functionClass isSubclassOfClass:buttonClass]) return NO;

    NSDictionary<NSString *, NSString *> *contract = @{
        @"configAppearanceAndLayout": @"v16@0:8",
        @"type": @"q16@0:8",
        @"setNormalImage:": @"v24@0:8@16",
        @"setHoverImage:": @"v24@0:8@16",
        @"setSelectedImage:": @"v24@0:8@16",
        @"setPressedImage:": @"v24@0:8@16",
        @"setDisabledImage:": @"v24@0:8@16",
    };
    for (NSString *name in contract) {
        Method method = class_getInstanceMethod(buttonClass, NSSelectorFromString(name));
        if (!method || strcmp(method_getTypeEncoding(method), contract[name].UTF8String)) return NO;
    }
    SEL selector = NSSelectorFromString(@"configAppearanceAndLayout");
    Method method = class_getInstanceMethod(buttonClass, selector);
    // Both subclasses inherit this method; reject future framework overrides.
    if (class_getInstanceMethod(graphClass, selector) != method
        || class_getInstanceMethod(functionClass, selector) != method) return NO;
    NSBundle *framework = [NSBundle bundleForClass:buttonClass];
    NSURL *directory = [framework.resourceURL URLByAppendingPathComponent:@"ThemeResources/QQ-theme"];
    if (!XCLoadQQToolbarIcons(directory)) return NO;
    XCGraphButtonClass = graphClass;
    XCFunctionButtonClass = functionClass;
    XCOriginalButtonConfiguration = (void (*)(id, SEL))method_setImplementation(method, (IMP)XCConfigureToolbarButton);
    return YES;
}
