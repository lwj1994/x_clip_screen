#import "ToolbarLayout.h"
#import <AppKit/AppKit.h>
#import <objc/runtime.h>

// Recovered interfaces are documented in analysis/framework-*-metadata.txt.
@protocol XCToolbarLayoutButtonABI <NSObject>
- (NSInteger)type;
- (NSTrackingArea *)trackingArea;
- (void)setTrackingArea:(NSTrackingArea *)area;
- (void)configAppearanceAndLayout;
@end

@protocol XCToolbarLayoutViewABI <NSObject>
- (NSArray<NSButton<XCToolbarLayoutButtonABI> *> *)graphButtonArray;
- (NSArray<NSButton<XCToolbarLayoutButtonABI> *> *)functionButtonArray;
- (NSImageView *)seperateImageView;
- (NSImageView *)seperateImageView2;
- (NSVisualEffectView *)gaussEffectView;
@end

static const CGFloat XCToolbarButtonSide = 32;
static const CGFloat XCToolbarPadding = 8;
static const CGFloat XCToolbarGap = 4;
static const CGFloat XCToolbarGroupGap = 16;
static const NSSize XCToolbarSize = {432, 48};
static char XCToolbarLayoutAppliedKey;
static void (*XCOriginalToolbarConfiguration)(id, SEL);
static void (*XCOriginalToolbarMovedToWindow)(id, SEL);
static void (*XCOriginalToolbarDrawing)(id, SEL, NSRect);

static NSButton<XCToolbarLayoutButtonABI> *XCButtonOfType(
    NSArray<NSButton<XCToolbarLayoutButtonABI> *> *buttons, NSInteger type) {
    for (NSButton<XCToolbarLayoutButtonABI> *button in buttons) {
        if (button.type == type) return button;
    }
    return nil;
}

static BOOL XCValidateToolbarButtons(NSArray<NSButton<XCToolbarLayoutButtonABI> *> *buttons,
                                    NSArray<NSNumber *> *expected) {
    if (buttons.count != expected.count) return NO;
    NSMutableSet<NSNumber *> *types = [NSMutableSet setWithCapacity:buttons.count];
    for (NSButton<XCToolbarLayoutButtonABI> *button in buttons) {
        if (![button isKindOfClass:NSButton.class]) return NO;
        NSNumber *type = @(button.type);
        if (![expected containsObject:type] || [types containsObject:type]) return NO;
        [types addObject:type];
    }
    return YES;
}

static void XCPositionToolbarButton(NSButton<XCToolbarLayoutButtonABI> *button, CGFloat x) {
    NSRect frame = NSMakeRect(x, XCToolbarPadding, XCToolbarButtonSide, XCToolbarButtonSide);
    BOOL sizeChanged = !NSEqualSizes(button.bounds.size, frame.size);
    button.frame = frame;
    if (sizeChanged) {
        // The framework creates a fixed tracking rectangle in initWithFrame:.
        // Preserve its options and owner while matching the larger hit target.
        NSTrackingArea *previous = button.trackingArea;
        if (previous) [button removeTrackingArea:previous];
        NSTrackingAreaOptions options = previous ? previous.options
            : (NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways);
        NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect:button.bounds
                                                        options:options
                                                          owner:button
                                                       userInfo:previous.userInfo];
        [button setTrackingArea:area];
        [button addTrackingArea:area];
        // Both source and destination rectangles in drawRect: equal bounds.
        // Regenerate all five image states at the new logical image size.
        [button configAppearanceAndLayout];
    }
}

static void XCApplyToolbarLayout(NSView<XCToolbarLayoutViewABI> *view) {
    NSArray<NSButton<XCToolbarLayoutButtonABI> *> *graphs = view.graphButtonArray;
    NSArray<NSButton<XCToolbarLayoutButtonABI> *> *functions = view.functionButtonArray;
    NSArray<NSNumber *> *graphOrder = @[@1, @2, @3, @5, @6, @4, @7];
    if (!XCValidateToolbarButtons(graphs, graphOrder)
        || !XCValidateToolbarButtons(functions, @[@0, @1, @2, @3, @4, @5])) return;

    CGFloat x = XCToolbarPadding;
    for (NSNumber *type in graphOrder) {
        XCPositionToolbarButton(XCButtonOfType(graphs, type.integerValue), x);
        x += XCToolbarButtonSide + XCToolbarGap;
    }
    x += XCToolbarGroupGap - XCToolbarGap;
    XCPositionToolbarButton(XCButtonOfType(functions, 1), x);
    x += XCToolbarButtonSide + XCToolbarGroupGap;
    for (NSNumber *type in @[@3, @4, @5]) {
        XCPositionToolbarButton(XCButtonOfType(functions, type.integerValue), x);
        x += XCToolbarButtonSide + XCToolbarGap;
    }
    for (NSNumber *type in @[@0, @2]) {
        NSButton *button = XCButtonOfType(functions, type.integerValue);
        button.hidden = YES;
        button.enabled = NO;
    }

    // Original separator coordinates belong to the wider QQ layout.
    // Draw separators with the surface instead; retain the original views.
    view.seperateImageView.hidden = YES;
    view.seperateImageView2.hidden = YES;
    view.gaussEffectView.hidden = YES;
    view.frame = NSMakeRect(0, 0, XCToolbarSize.width, XCToolbarSize.height);
    objc_setAssociatedObject(view, &XCToolbarLayoutAppliedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    NSWindow *window = view.window;
    if (window) {
        // The original position/popover methods use these actual frames.
        // Keep the toolbar at content origin so their coordinate mapping holds.
        window.opaque = NO;
        window.backgroundColor = NSColor.clearColor;
        window.hasShadow = YES;
        window.animationBehavior = NSWindowAnimationBehaviorNone;
        if (!NSEqualSizes(window.contentView.bounds.size, XCToolbarSize)) {
            [window setContentSize:XCToolbarSize];
        }
        view.frame = NSMakeRect(0, 0, XCToolbarSize.width, XCToolbarSize.height);
        [window invalidateShadow];
    }
    [view setNeedsDisplay:YES];
}

static void XCConfigureToolbarLayout(id object, SEL selector) {
    XCOriginalToolbarConfiguration(object, selector);
    XCApplyToolbarLayout(object);
}

static void XCToolbarMovedToWindow(id object, SEL selector) {
    XCOriginalToolbarMovedToWindow(object, selector);
    if ([(NSView *)object window]) XCApplyToolbarLayout(object);
}

static void XCDrawToolbarSurface(id object, SEL selector, NSRect dirtyRect) {
    NSView *view = object;
    if (!objc_getAssociatedObject(view, &XCToolbarLayoutAppliedKey)) {
        XCOriginalToolbarDrawing(object, selector, dirtyRect);
        return;
    }
    [NSGraphicsContext saveGraphicsState];
    NSRectFillUsingOperation(view.bounds, NSCompositingOperationClear);
    NSBezierPath *surface = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(view.bounds, 0.5, 0.5)
                                                          xRadius:11.5 yRadius:11.5];
    [NSColor.whiteColor setFill];
    [surface fill];
    [[NSColor colorWithSRGBRed:0.84 green:0.87 blue:0.91 alpha:1] setStroke];
    surface.lineWidth = 1;
    [surface stroke];

    NSBezierPath *separators = [NSBezierPath bezierPath];
    for (NSNumber *x in @[@263.5, @311.5]) {
        [separators moveToPoint:NSMakePoint(x.doubleValue, 14)];
        [separators lineToPoint:NSMakePoint(x.doubleValue, 34)];
    }
    separators.lineWidth = 1;
    [[NSColor colorWithSRGBRed:0.88 green:0.90 blue:0.93 alpha:1] setStroke];
    [separators stroke];
    [NSGraphicsContext restoreGraphicsState];
}

BOOL XCInstallToolbarLayout(void) {
    if (XCOriginalToolbarConfiguration) return YES;
    if (!NSThread.isMainThread) return NO;
    Class viewClass = NSClassFromString(@"JTToolbarView");
    Class buttonClass = NSClassFromString(@"JTToolbarButton");
    if (!viewClass || ![viewClass isSubclassOfClass:NSView.class]
        || !buttonClass || ![buttonClass isSubclassOfClass:NSButton.class]) return NO;

    NSDictionary<NSString *, NSString *> *viewContract = @{
        @"configAppearanceAndLayout": @"v16@0:8",
        @"drawRect:": @"v48@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16",
        @"viewDidMoveToWindow": @"v16@0:8",
        @"graphButtonArray": @"@16@0:8",
        @"functionButtonArray": @"@16@0:8",
        @"seperateImageView": @"@16@0:8",
        @"seperateImageView2": @"@16@0:8",
        @"gaussEffectView": @"@16@0:8",
    };
    NSDictionary<NSString *, NSString *> *buttonContract = @{
        @"type": @"q16@0:8",
        @"trackingArea": @"@16@0:8",
        @"setTrackingArea:": @"v24@0:8@16",
        @"configAppearanceAndLayout": @"v16@0:8",
    };
    for (NSString *name in viewContract) {
        Method method = class_getInstanceMethod(viewClass, NSSelectorFromString(name));
        if (!method || strcmp(method_getTypeEncoding(method), viewContract[name].UTF8String)) return NO;
    }
    for (NSString *name in buttonContract) {
        Method method = class_getInstanceMethod(buttonClass, NSSelectorFromString(name));
        if (!method || strcmp(method_getTypeEncoding(method), buttonContract[name].UTF8String)) return NO;
    }

    // Add an override only to JTToolbarView, leaving NSView's implementation intact.
    // This framework version inherits viewDidMoveToWindow; reject a future override.
    SEL movedSelector = @selector(viewDidMoveToWindow);
    Method moved = class_getInstanceMethod(viewClass, movedSelector);
    if (moved != class_getInstanceMethod(class_getSuperclass(viewClass), movedSelector)) return NO;
    XCOriginalToolbarMovedToWindow = (void (*)(id, SEL))method_getImplementation(moved);
    if (!class_addMethod(viewClass, movedSelector, (IMP)XCToolbarMovedToWindow,
                         method_getTypeEncoding(moved))) return NO;
    Method configuration = class_getInstanceMethod(viewClass, NSSelectorFromString(@"configAppearanceAndLayout"));
    Method drawing = class_getInstanceMethod(viewClass, @selector(drawRect:));
    XCOriginalToolbarDrawing = (void (*)(id, SEL, NSRect))method_setImplementation(drawing, (IMP)XCDrawToolbarSurface);
    XCOriginalToolbarConfiguration = (void (*)(id, SEL))method_setImplementation(configuration, (IMP)XCConfigureToolbarLayout);
    return YES;
}
