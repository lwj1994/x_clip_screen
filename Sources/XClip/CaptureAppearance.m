#import "CaptureAppearance.h"
#import <objc/runtime.h>
#import <math.h>

// ABI 和状态机来自 analysis/framework-selection-metadata.txt 与 ARM64 反汇编。
// 用类型明确的 ObjC 消息保留两种 CPU 架构对 CGRect 返回值的正确调用约定。
@protocol XCCaptureAppearanceABI <NSObject>
- (id)captureViewController;
- (id)captureView;
- (id)selectedItem;
- (NSRect)selectedRect;
- (void)setSelectedRect:(NSRect)rect;
- (NSUInteger)selectedItemType;
- (void)setSelectedItemType:(NSUInteger)type;
- (void)setCaptureType:(NSUInteger)type;
- (void)setSelectComfirmed:(BOOL)confirmed;
- (void)setNeedScreenCapture:(BOOL)enabled;
- (void)setNeedDrawControlPoints:(BOOL)enabled;
- (void)setNeedDrawSelectedItem:(BOOL)enabled;
- (void)setPostedSelectBeginNotification:(BOOL)posted;
- (void)setActiveWindowInfo:(nullable id)info;
- (void)setImageCaptured:(nullable NSImage *)image;
- (void)setResponseToReturn:(BOOL)enabled;
- (void)setBorderColor:(NSColor *)color;
- (void)setControlPointStrokeColor:(NSColor *)color;
- (void)configAppearanceAndLayout;
- (void)hideToolbar;
- (void)setToolbarWindowController:(nullable id)controller;
- (id)editViewController;
- (void)setEditViewController:(nullable id)controller;
- (NSView *)sizeInfoView;
- (NSView *)magifierView;
- (BOOL)updateSelectedItemType:(nullable NSUInteger *)type
                   cursorType:(nullable NSUInteger *)cursorType
                   fixedPoint:(nullable NSPoint *)fixedPoint
                 byMousePoint:(NSPoint)point;
@end

NSString * const XCSelectionBorderColorDefaultsKey = @"XCSelectionBorderColor";
static NSColor *(*XCOriginalThemedColor)(id, SEL, NSString *);
static void (*XCOriginalBecomeActive)(id, SEL);
static void (*XCOriginalCaptureMouseDown)(id, SEL, NSEvent *);
static void (*XCOriginalConfirmSelectedItem)(id, SEL);
static NSHashTable<NSWindowController<XCCaptureAppearanceABI> *> *XCCaptureControllers;

NSColor *XCSelectionBorderColor(void) {
    NSString *hex = [NSUserDefaults.standardUserDefaults stringForKey:XCSelectionBorderColorDefaultsKey];
    unsigned int rgb = 0x0099FF;
    if ([hex hasPrefix:@"#"] && hex.length == 7) {
        NSScanner *scanner = [NSScanner scannerWithString:[hex substringFromIndex:1]];
        scanner.charactersToBeSkipped = nil;
        unsigned int value;
        if ([scanner scanHexInt:&value] && scanner.isAtEnd) rgb = value;
    }
    return [NSColor colorWithSRGBRed:((rgb >> 16) & 255) / 255.0
                             green:((rgb >> 8) & 255) / 255.0
                              blue:(rgb & 255) / 255.0 alpha:1];
}

void XCSetSelectionBorderColor(NSColor *color) {
    NSColor *rgb = [color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (!rgb) return;
    unsigned int red = (unsigned int)lround(fmax(0, fmin(1, rgb.redComponent)) * 255);
    unsigned int green = (unsigned int)lround(fmax(0, fmin(1, rgb.greenComponent)) * 255);
    unsigned int blue = (unsigned int)lround(fmax(0, fmin(1, rgb.blueComponent)) * 255);
    [NSUserDefaults.standardUserDefaults setObject:[NSString stringWithFormat:@"#%02X%02X%02X", red, green, blue]
                                          forKey:XCSelectionBorderColorDefaultsKey];
    // 颜色设置通常在截图前使用；也允许活跃选区立即更新。
    for (NSWindowController<XCCaptureAppearanceABI> *controller in XCCaptureControllers.allObjects) {
        NSView<XCCaptureAppearanceABI> *view = [[controller captureViewController] captureView];
        id<XCCaptureAppearanceABI> item = [view selectedItem];
        [item setBorderColor:rgb];
        [item setControlPointStrokeColor:rgb];
        view.needsDisplay = YES;
    }
}

static NSColor *XCThemedColor(id theme, SEL selector, NSString *key) {
    if ([key isEqualToString:@"JTCaptureView_SelectRect_BorderColor"] ||
        [key isEqualToString:@"JTCaptureView_ControlPoint_StrokeColor"])
        return XCSelectionBorderColor();
    return XCOriginalThemedColor(theme, selector, key);
}

static void XCBecomeActive(NSWindowController<XCCaptureAppearanceABI> *controller, SEL selector) {
    controller.window.animationBehavior = NSWindowAnimationBehaviorNone;
    [XCCaptureControllers addObject:controller];
    XCOriginalBecomeActive(controller, selector);
}

static id XCManualWindowInfoAtPosition(id view, SEL selector, NSPoint point) {
    (void)view; (void)selector; (void)point;
    // mouseMoved 和未拖动的 mouseDown 均通过此入口查询窗口。
    // 返回 nil 禁用自动窗口命中，拖拽生成区域的原分支不依赖这个入口。
    return nil;
}

static void XCResetSelection(void) {
    for (NSWindowController<XCCaptureAppearanceABI> *controller in XCCaptureControllers.allObjects) {
        if (!controller.window) continue;
        id<XCCaptureAppearanceABI> viewController = [controller captureViewController];
        NSView<XCCaptureAppearanceABI> *view = [viewController captureView];
        // 先卸下旧的标注和工具栏，再让确认通知建立新的 delegate 关系。
        [viewController hideToolbar];
        [viewController setToolbarWindowController:nil];
        NSViewController *editor = [viewController editViewController];
        [editor.view removeFromSuperview];
        [viewController setEditViewController:nil];
        [viewController setImageCaptured:nil];
        [viewController setNeedScreenCapture:YES];
        [view setNeedScreenCapture:YES];
        [view setSelectComfirmed:NO];
        [view setCaptureType:1];
        [view setActiveWindowInfo:nil];
        [view setSelectedItemType:0];
        [view setNeedDrawControlPoints:NO];
        [view setNeedDrawSelectedItem:YES];
        [view setPostedSelectBeginNotification:NO];
        [[view selectedItem] setSelectedRect:NSZeroRect];
        // 原框架会释放其它屏幕的 selectedItem，重建后必须恢复颜色/线宽。
        [view configAppearanceAndLayout];
        [[viewController sizeInfoView] setHidden:YES];
        [[viewController magifierView] setHidden:YES];
        [(id<XCCaptureAppearanceABI>)controller.window setResponseToReturn:NO];
    }
}

static void XCCaptureMouseDown(NSView<XCCaptureAppearanceABI> *view, SEL selector, NSEvent *event) {
    BOOL hasSelection = NO;
    BOOL belongsToCapture = NO;
    for (NSWindowController<XCCaptureAppearanceABI> *controller in XCCaptureControllers.allObjects) {
        if (!controller.window) continue;
        NSView<XCCaptureAppearanceABI> *candidate = [[controller captureViewController] captureView];
        if (candidate == view) belongsToCapture = YES;
        if ([candidate selectedItemType] != 0 && !NSIsEmptyRect([candidate selectedRect])) hasSelection = YES;
    }
    if (belongsToCapture && hasSelection) {
        NSPoint point = [view convertPoint:event.locationInWindow fromView:nil];
        // 原命中测试包含边缘和控制点，保留拖动/缩放；框外则重新框选。
        NSUInteger itemType = 0, cursorType = 0;
        NSPoint fixedPoint = NSZeroPoint;
        BOOL hitsSelection = !NSIsEmptyRect([view selectedRect]) &&
            [view updateSelectedItemType:&itemType cursorType:&cursorType fixedPoint:&fixedPoint byMousePoint:point];
        if (!hitsSelection) XCResetSelection();
    }
    XCOriginalCaptureMouseDown(view, selector, event);
}

static void XCConfirmSelectedItem(NSView<XCCaptureAppearanceABI> *view, SEL selector) {
    if (NSIsEmptyRect([view selectedRect])) {
        // 原 mouseDown 即使命中窗口为 nil 仍设置 type=1 并请求确认。
        // 单击或零宽/零高拖动回到初始状态，不创建工具栏或锁定编辑。
        XCResetSelection();
        return;
    }
    XCOriginalConfirmSelectedItem(view, selector);
}

void XCPrepareManualCapture(void) {
    XCCaptureControllers = [NSHashTable weakObjectsHashTable];
}

BOOL XCInstallCaptureAppearance(NSError **error) {
    if (XCOriginalThemedColor) return YES;
    if (!NSThread.isMainThread) {
        if (error) *error = [NSError errorWithDomain:@"XClip.Appearance" code:1
                                          userInfo:@{NSLocalizedDescriptionKey:@"截图外观必须在主线程初始化。"}];
        return NO;
    }
    NSArray<NSArray<NSString *> *> *contract = @[
        @[@"JTCaptureThemeManager", @"themedColorWithKey:", @"@24@0:8@16"],
        @[@"JTCaptureWindowController", @"becomeActive", @"v16@0:8"],
        @[@"JTCaptureWindowController", @"captureViewController", @"@16@0:8"],
        @[@"JTCaptureView", @"mouseDown:", @"v24@0:8@16"],
        @[@"JTCaptureView", @"windowInfoAtPosition:", @"@32@0:8{CGPoint=dd}16"],
        @[@"JTCaptureView", @"confirmSelectedItem", @"v16@0:8"],
        @[@"JTCaptureView", @"selectedItem", @"@16@0:8"],
        @[@"JTCaptureView", @"selectedRect", @"{CGRect={CGPoint=dd}{CGSize=dd}}16@0:8"],
        @[@"JTCaptureView", @"selectedItemType", @"Q16@0:8"],
        @[@"JTCaptureView", @"setSelectedItemType:", @"v24@0:8Q16"],
        @[@"JTCaptureView", @"setCaptureType:", @"v24@0:8Q16"],
        @[@"JTCaptureView", @"setSelectComfirmed:", @"v20@0:8B16"],
        @[@"JTCaptureView", @"setNeedScreenCapture:", @"v20@0:8B16"],
        @[@"JTCaptureView", @"setNeedDrawControlPoints:", @"v20@0:8B16"],
        @[@"JTCaptureView", @"setNeedDrawSelectedItem:", @"v20@0:8B16"],
        @[@"JTCaptureView", @"setPostedSelectBeginNotification:", @"v20@0:8B16"],
        @[@"JTCaptureView", @"setActiveWindowInfo:", @"v24@0:8@16"],
        @[@"JTCaptureView", @"configAppearanceAndLayout", @"v16@0:8"],
        @[@"JTCaptureView", @"updateSelectedItemType:cursorType:fixedPoint:byMousePoint:", @"B56@0:8^Q16^Q24^{CGPoint=dd}32{CGPoint=dd}40"],
        @[@"JTCaptureViewSelectedItem", @"setSelectedRect:", @"v48@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16"],
        @[@"JTCaptureViewSelectedItem", @"setBorderColor:", @"v24@0:8@16"],
        @[@"JTCaptureViewSelectedItem", @"setControlPointStrokeColor:", @"v24@0:8@16"],
        @[@"JTCaptureViewController", @"captureView", @"@16@0:8"],
        @[@"JTCaptureViewController", @"setImageCaptured:", @"v24@0:8@16"],
        @[@"JTCaptureViewController", @"setNeedScreenCapture:", @"v20@0:8B16"],
        @[@"JTCaptureViewController", @"hideToolbar", @"v16@0:8"],
        @[@"JTCaptureViewController", @"setToolbarWindowController:", @"v24@0:8@16"],
        @[@"JTCaptureViewController", @"editViewController", @"@16@0:8"],
        @[@"JTCaptureViewController", @"setEditViewController:", @"v24@0:8@16"],
        @[@"JTCaptureViewController", @"sizeInfoView", @"@16@0:8"],
        @[@"JTCaptureViewController", @"magifierView", @"@16@0:8"],
        @[@"JTCaptureWindow", @"setResponseToReturn:", @"v20@0:8B16"]
    ];
    for (NSArray<NSString *> *entry in contract) {
        Method method = class_getInstanceMethod(NSClassFromString(entry[0]), NSSelectorFromString(entry[1]));
        NSString *expected = [entry[2] stringByReplacingOccurrencesOfString:@"B"
                                                               withString:[NSString stringWithUTF8String:@encode(BOOL)]];
        if (!method || strcmp(method_getTypeEncoding(method), expected.UTF8String) != 0) {
            if (error) *error = [NSError errorWithDomain:@"XClip.Appearance" code:2 userInfo:@{
                NSLocalizedDescriptionKey:[NSString stringWithFormat:@"截图外观接口不兼容：%@ %@", entry[0], entry[1]]}];
            return NO;
        }
    }
    XCOriginalThemedColor = (void *)method_setImplementation(class_getInstanceMethod(
        NSClassFromString(@"JTCaptureThemeManager"), NSSelectorFromString(@"themedColorWithKey:")), (IMP)XCThemedColor);
    XCOriginalBecomeActive = (void *)method_setImplementation(class_getInstanceMethod(
        NSClassFromString(@"JTCaptureWindowController"), NSSelectorFromString(@"becomeActive")), (IMP)XCBecomeActive);
    XCOriginalCaptureMouseDown = (void *)method_setImplementation(class_getInstanceMethod(
        NSClassFromString(@"JTCaptureView"), @selector(mouseDown:)), (IMP)XCCaptureMouseDown);
    method_setImplementation(class_getInstanceMethod(NSClassFromString(@"JTCaptureView"),
        NSSelectorFromString(@"windowInfoAtPosition:")), (IMP)XCManualWindowInfoAtPosition);
    XCOriginalConfirmSelectedItem = (void *)method_setImplementation(class_getInstanceMethod(
        NSClassFromString(@"JTCaptureView"), NSSelectorFromString(@"confirmSelectedItem")), (IMP)XCConfirmSelectedItem);
    return YES;
}
