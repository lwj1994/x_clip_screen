#import <AppKit/AppKit.h>
#import "../Sources/XClip/ToolbarIcons.h"

static void Text(NSString *text, NSPoint point, CGFloat size, NSColor *color, BOOL bold) {
    [text drawAtPoint:point withAttributes:@{
        NSFontAttributeName: [NSFont systemFontOfSize:size weight:bold ? NSFontWeightSemibold : NSFontWeightRegular],
        NSForegroundColorAttributeName: color
    }];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 3) return 2;
        if (!XCLoadQQToolbarIcons([NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[2]]])) return 1;
        NSSize canvas = NSMakeSize(640, 376);
        NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc]
            initWithBitmapDataPlanes:NULL pixelsWide:1280 pixelsHigh:752 bitsPerSample:8
            samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace
            bytesPerRow:0 bitsPerPixel:0];
        bitmap.size = canvas;
        [NSGraphicsContext saveGraphicsState];
        NSGraphicsContext *context = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
        [NSGraphicsContext setCurrentContext:context];
        [[NSColor colorWithSRGBRed:0.96 green:0.97 blue:0.98 alpha:1] setFill];
        NSRectFill(NSMakeRect(0, 0, canvas.width, canvas.height));
        Text(@"XScreenCapture", NSMakePoint(26, 335), 18, NSColor.blackColor, YES);
        Text(@"Original QQ screenshot toolbar artwork", NSMakePoint(26, 313), 12, NSColor.secondaryLabelColor, NO);

        NSString *states[] = {@"Default", @"Hover", @"Selected", @"Pressed", @"Disabled"};
        for (NSUInteger row = 0; row < 5; row++) {
            CGFloat y = 250 - row * 46;
            Text(states[row], NSMakePoint(26, y + 9), 11, NSColor.darkGrayColor, NO);
            [NSColor.whiteColor setFill];
            [[NSBezierPath bezierPathWithRoundedRect:NSMakeRect(103, y - 3, 511, 38) xRadius:10 yRadius:10] fill];
            for (NSUInteger column = 0; column < 11; column++) {
                NSImage *image = XCToolbarIconImage((XCToolbarIcon)column, NSMakeSize(32, 32), (XCToolbarIconState)row);
                [image drawInRect:NSMakeRect(110 + column * 45, y, 32, 32)];
            }
        }
        Text(@"QQ-theme  ·  Original colors and states  ·  Native 24 pt  ·  1x / 2x",
             NSMakePoint(26, 22), 11, NSColor.darkGrayColor, NO);
        [NSGraphicsContext restoreGraphicsState];
        NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        return [png writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES] ? 0 : 1;
    }
}
