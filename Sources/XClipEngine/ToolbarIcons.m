#import "ToolbarIcons.h"

static NSDictionary<NSString *, NSImage *> *XCQQImages;
static NSCache<NSString *, NSImage *> *XCQQButtonImages;

NSString *XCToolbarIconLabel(XCToolbarIcon icon) {
    switch (icon) {
        case XCToolbarIconRectangle: return @"矩形";
        case XCToolbarIconEllipse: return @"椭圆";
        case XCToolbarIconArrow: return @"箭头";
        case XCToolbarIconPen: return @"画笔";
        case XCToolbarIconMosaic: return @"马赛克";
        case XCToolbarIconText: return @"文字";
        case XCToolbarIconNumber: return @"序号";
        case XCToolbarIconUndo: return @"撤销";
        case XCToolbarIconSave: return @"保存";
        case XCToolbarIconCancel: return @"取消";
        case XCToolbarIconDone: return @"完成";
    }
    return @"";
}

static NSString *XCQQResourceName(XCToolbarIcon icon, XCToolbarIconState state) {
    NSArray<NSString *> *names = @[
        @"JTEditGraphTypeRoundRect", @"JTEditGraphTypeOval", @"JTEditGraphTypeArrow",
        @"JTEditGraphTypeCurve", @"JTEditGraphTypeMosaicPen", @"JTEditGraphTypeText",
        @"JTEditGraphTypeTag", @"JTToolbarFunctionButtonTypeUndo",
        @"JTToolbarFunctionButtonTypeSave", @"JTToolbarFunctionButtonTypeCancel",
        @"JTToolbarFunctionButtonTypeOK"
    ];
    NSString *suffix = @"normal";
    if (state == XCToolbarIconStateHover) suffix = @"hover";
    if (state == XCToolbarIconStateSelected || state == XCToolbarIconStatePressed)
        suffix = icon == XCToolbarIconUndo ? @"pressed" : @"selected";
    if (state == XCToolbarIconStateDisabled && icon == XCToolbarIconUndo) suffix = @"disabled";
    // QQ's theme JSON refers to Undo_selected, but ships Undo_pressed instead.
    return [NSString stringWithFormat:@"%@_%@", names[icon], suffix];
}

BOOL XCLoadQQToolbarIcons(NSURL *directory) {
    NSMutableDictionary<NSString *, NSImage *> *images = [NSMutableDictionary dictionary];
    for (NSUInteger icon = XCToolbarIconRectangle; icon <= XCToolbarIconDone; icon++) {
        for (NSUInteger state = XCToolbarIconStateNormal; state <= XCToolbarIconStateDisabled; state++) {
            NSString *name = XCQQResourceName(icon, state);
            if (images[name]) continue;
            NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(24, 24)];
            for (NSString *scale in @[@"", @"@2x"]) {
                NSString *filename = [NSString stringWithFormat:@"%@%@.png", name, scale];
                NSURL *url = [directory URLByAppendingPathComponent:filename];
                NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithContentsOfFile:url.path];
                if (!rep) return NO;
                rep.size = NSMakeSize(24, 24);
                [image addRepresentation:rep];
            }
            image.template = NO;
            images[name] = image;
        }
    }
    XCQQImages = images.copy;
    XCQQButtonImages = [NSCache new];
    XCQQButtonImages.countLimit = 160;
    return YES;
}

NSImage *XCToolbarIconImage(XCToolbarIcon icon, NSSize size, XCToolbarIconState state) {
    NSString *name = XCQQResourceName(icon, state);
    NSImage *original = XCQQImages[name];
    if (!original) return nil;
    NSString *key = [NSString stringWithFormat:@"%@/%.2f/%.2f", name, size.width, size.height];
    NSImage *cached = [XCQQButtonImages objectForKey:key];
    if (cached) return cached;
    // Preserve QQ's pixels, colors and state artwork at their native 24-point size.
    // The surrounding canvas matches the framework's bounds-based source rectangle.
    NSImage *image = [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect destination) {
        CGFloat side = MIN(24, MIN(NSWidth(destination), NSHeight(destination)));
        NSRect rect = NSMakeRect(NSMidX(destination) - side / 2,
                                 NSMidY(destination) - side / 2, side, side);
        [original drawInRect:rect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver
                   fraction:1 respectFlipped:YES hints:nil];
        return YES;
    }];
    image.template = NO;
    image.accessibilityDescription = XCToolbarIconLabel(icon);
    [XCQQButtonImages setObject:image forKey:key];
    return image;
}
