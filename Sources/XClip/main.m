#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "CaptureEngine.h"
#import "ShortcutController.h"
#import "CaptureAppearance.h"
#import <dlfcn.h>
#import <math.h>

@protocol XCPermissionGuideAPI <NSObject>
+ (void)showFromRect:(NSRect)rect;
@end

@interface XCAppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate>
@property(nonatomic, strong) XCCaptureEngine *engine;
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSTextField *permissionLabel;
@property(nonatomic, strong) NSTextField *resultLabel;
@property(nonatomic, strong) NSButton *captureButton;
@property(nonatomic, strong) NSData *lastImage;
@property(nonatomic, strong) XCShortcutController *shortcut;
@property(nonatomic, strong) XCShortcutRecorder *shortcutRecorder;
@property(nonatomic, strong) NSMutableArray<NSMenuItem *> *captureMenuItems;
@property(nonatomic, strong) NSButton *borderColorButton;
@property(nonatomic, strong) NSTextField *borderColorLabel;
@property(nonatomic) BOOL capturePending;
- (void)startCapture:(id)sender;
@end

static NSTextField *XCLabel(NSString *text, CGFloat size, NSFontWeight weight) {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.alignment = NSTextAlignmentCenter;
    return label;
}

@implementation XCAppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [NSUserDefaults.standardUserDefaults registerDefaults:@{@"XCHighResolution": @YES, @"XCPlaySound": @NO,
                                                          @"XCSelectionBorderColor": @"#0099FF"}];
    self.engine = [XCCaptureEngine new];
    NSError *error = nil;
    if (![self.engine loadWithError:&error]) {
        [self showError:error.localizedDescription];
        [NSApp terminate:nil];
        return;
    }
    __weak typeof(self) weakSelf = self;
    self.shortcut = [[XCShortcutController alloc] initWithHandler:^{ [weakSelf startCapture:nil]; }];
    NSError *shortcutError = nil;
    [self.shortcut registerShortcutWithError:&shortcutError];
    [self setupMenu];
    [self showWindow:nil];
    if (shortcutError) self.resultLabel.stringValue = shortcutError.localizedDescription;
}

- (NSMenuItem *)item:(NSString *)title action:(SEL)action key:(NSString *)key menu:(NSMenu *)menu {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
    item.target = self;
    [menu addItem:item];
    return item;
}

- (void)setupMenu {
    self.captureMenuItems = [NSMutableArray array];
    NSMenu *appMenu = [NSMenu new];
    NSMenuItem *start = [self item:@"开始截图" action:@selector(startCapture:) key:self.shortcut.keyEquivalent menu:appMenu];
    start.keyEquivalentModifierMask = self.shortcut.keyEquivalentModifierMask;
    [self.captureMenuItems addObject:start];
    [self item:@"设置…" action:@selector(showWindow:) key:@"," menu:appMenu];
    [self item:@"退出 XScreenCapture" action:@selector(quit:) key:@"q" menu:appMenu];
    NSMenu *mainMenu = [NSMenu new];
    NSMenuItem *root = [NSMenuItem new];
    root.submenu = appMenu;
    [mainMenu addItem:root];
    // 截图工具里的文字标注和保存面板需要标准编辑命令。
    NSMenu *edit = [[NSMenu alloc] initWithTitle:@"编辑"];
    NSArray *titles = @[@"撤销", @"剪切", @"复制", @"粘贴", @"全选"];
    NSArray *actions = @[@"undo:", @"cut:", @"copy:", @"paste:", @"selectAll:"];
    NSArray *keys = @[@"z", @"x", @"c", @"v", @"a"];
    for (NSUInteger i = 0; i < titles.count; i++) {
        [edit addItemWithTitle:titles[i] action:NSSelectorFromString(actions[i]) keyEquivalent:keys[i]];
    }
    NSMenuItem *editRoot = [NSMenuItem new]; editRoot.submenu = edit; [mainMenu addItem:editRoot];
    NSApp.mainMenu = mainMenu;

    self.statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    NSImage *icon = [NSImage imageWithSystemSymbolName:@"viewfinder" accessibilityDescription:@"XScreenCapture 截图"];
    icon.template = YES; self.statusItem.button.image = icon; self.statusItem.button.toolTip = @"XScreenCapture · ⌘⇧2 截图";
    NSMenu *menu = [NSMenu new]; menu.delegate = self;
    NSMenuItem *capture = [self item:@"开始截图" action:@selector(startCapture:) key:self.shortcut.keyEquivalent menu:menu];
    capture.keyEquivalentModifierMask = self.shortcut.keyEquivalentModifierMask;
    [self.captureMenuItems addObject:capture];
    [self item:@"再次复制上一张" action:@selector(copyLast:) key:@"" menu:menu];
    [self item:@"保存上一张…" action:@selector(saveLast:) key:@"" menu:menu];
    [menu addItem:NSMenuItem.separatorItem];
    [self item:@"设置…" action:@selector(showWindow:) key:@"," menu:menu];
    [self item:@"屏幕录制权限…" action:@selector(openPrivacy:) key:@"" menu:menu];
    [menu addItem:NSMenuItem.separatorItem];
    [self item:@"退出 XScreenCapture" action:@selector(quit:) key:@"q" menu:menu];
    self.statusItem.menu = menu;
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (item.action == @selector(copyLast:) || item.action == @selector(saveLast:)) return self.lastImage != nil;
    if (item.action == @selector(startCapture:)) return !self.capturePending && !self.engine.capturing;
    return YES;
}

- (void)showWindow:(id)sender {
    if (self.engine.capturing) return;
    if (!self.window) {
        self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 480, 620)
            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable
            backing:NSBackingStoreBuffered defer:NO];
        self.window.title = @"XScreenCapture"; self.window.releasedWhenClosed = NO;
        self.window.animationBehavior = NSWindowAnimationBehaviorNone;
        self.window.delegate = self; self.window.titlebarAppearsTransparent = YES;
        NSView *content = self.window.contentView;
        NSImageView *symbol = [[NSImageView alloc] initWithFrame:NSMakeRect(201, 486, 78, 78)];
        symbol.image = [NSImage imageWithSystemSymbolName:@"viewfinder" accessibilityDescription:@"截图"];
        symbol.contentTintColor = NSColor.systemTealColor;
        [symbol setSymbolConfiguration:[NSImageSymbolConfiguration configurationWithPointSize:58 weight:NSFontWeightLight]];
        [content addSubview:symbol];
        NSTextField *title = XCLabel(@"XScreenCapture", 34, NSFontWeightSemibold); title.frame = NSMakeRect(40, 435, 400, 48); [content addSubview:title];
        NSTextField *subtitle = XCLabel(@"框选、标注，然后分享。", 16, NSFontWeightRegular);
        subtitle.textColor = NSColor.secondaryLabelColor; subtitle.frame = NSMakeRect(30, 402, 420, 26); [content addSubview:subtitle];
        self.captureButton = [NSButton buttonWithTitle:@"开始截图" target:self action:@selector(startCapture:)];
        self.captureButton.bezelStyle = NSBezelStyleRounded; self.captureButton.controlSize = NSControlSizeLarge;
        self.captureButton.bezelColor = NSColor.systemTealColor; self.captureButton.frame = NSMakeRect(85, 340, 310, 44);
        self.captureButton.keyEquivalent = @"\r"; [content addSubview:self.captureButton];
        self.permissionLabel = XCLabel(@"", 12, NSFontWeightRegular);
        self.permissionLabel.frame = NSMakeRect(20, 308, 440, 24); [content addSubview:self.permissionLabel];
        NSTextField *shortcutLabel = XCLabel(@"截图快捷键", 13, NSFontWeightMedium);
        shortcutLabel.alignment = NSTextAlignmentLeft; shortcutLabel.frame = NSMakeRect(65, 254, 120, 24); [content addSubview:shortcutLabel];
        self.shortcutRecorder = [[XCShortcutRecorder alloc] initWithController:self.shortcut];
        self.shortcutRecorder.frame = NSMakeRect(193, 249, 142, 32);
        self.shortcutRecorder.toolTip = @"点击后按下新的快捷键，Esc 取消";
        __weak typeof(self) weakSelf = self;
        self.shortcutRecorder.completionHandler = ^(BOOL changed, NSString *message, NSError *error) {
            (void)changed;
            [weakSelf refreshShortcut];
            if (message.length || error) weakSelf.resultLabel.stringValue = error.localizedDescription ?: message;
        };
        [content addSubview:self.shortcutRecorder];
        NSButton *resetShortcut = [NSButton buttonWithTitle:@"恢复默认" target:self action:@selector(resetShortcut:)];
        resetShortcut.bezelStyle = NSBezelStyleRounded; resetShortcut.frame = NSMakeRect(341, 249, 83, 32); [content addSubview:resetShortcut];
        NSTextField *borderLabel = XCLabel(@"选框边框颜色", 13, NSFontWeightMedium);
        borderLabel.alignment = NSTextAlignmentLeft; borderLabel.frame = NSMakeRect(65, 208, 120, 24); [content addSubview:borderLabel];
        self.borderColorButton = [NSButton buttonWithTitle:@"选择颜色" target:self action:@selector(chooseBorderColor:)];
        self.borderColorButton.frame = NSMakeRect(194, 203, 46, 32);
        self.borderColorButton.bezelStyle = NSBezelStyleRounded;
        self.borderColorButton.imagePosition = NSImageOnly;
        self.borderColorButton.accessibilityLabel = @"选框边框颜色";
        NSColorPanel.sharedColorPanel.showsAlpha = NO;
        [content addSubview:self.borderColorButton];
        self.borderColorLabel = XCLabel(@"", 12, NSFontWeightRegular);
        self.borderColorLabel.alignment = NSTextAlignmentLeft; self.borderColorLabel.textColor = NSColor.secondaryLabelColor;
        self.borderColorLabel.frame = NSMakeRect(251, 208, 92, 24); [content addSubview:self.borderColorLabel];
        NSButton *resetColor = [NSButton buttonWithTitle:@"恢复默认" target:self action:@selector(resetBorderColor:)];
        resetColor.bezelStyle = NSBezelStyleRounded; resetColor.frame = NSMakeRect(341, 203, 83, 32); [content addSubview:resetColor];
        [self refreshBorderColor];
        NSButton *resolution = [NSButton checkboxWithTitle:@"保存时保留 Retina 分辨率" target:self action:@selector(toggleResolution:)];
        resolution.state = [NSUserDefaults.standardUserDefaults boolForKey:@"XCHighResolution"];
        resolution.frame = NSMakeRect(65, 143, 230, 24); [content addSubview:resolution];
        NSButton *sound = [NSButton checkboxWithTitle:@"截图提示音" target:self action:@selector(toggleSound:)];
        sound.state = [NSUserDefaults.standardUserDefaults boolForKey:@"XCPlaySound"];
        sound.frame = NSMakeRect(299, 143, 120, 24); [content addSubview:sound];
        NSTextField *tip = XCLabel(@"拖动框选 · 双击完成 · Esc 取消", 12, NSFontWeightRegular);
        tip.textColor = NSColor.secondaryLabelColor; tip.frame = NSMakeRect(20, 98, 440, 24); [content addSubview:tip];
        self.resultLabel = XCLabel(@"关闭此窗口后，仍可从菜单栏或快捷键截图。", 11, NSFontWeightRegular);
        self.resultLabel.textColor = NSColor.tertiaryLabelColor; self.resultLabel.frame = NSMakeRect(20, 48, 440, 32);
        self.resultLabel.maximumNumberOfLines = 2; [content addSubview:self.resultLabel];
        [self.window center];
    }
    [self refreshShortcut];
    [self refreshPermission];
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
}

- (void)refreshShortcut {
    self.captureButton.title = [NSString stringWithFormat:@"开始截图   %@", self.shortcut.displayString];
    self.statusItem.button.toolTip = [NSString stringWithFormat:@"XScreenCapture · %@ 截图", self.shortcut.displayString];
    for (NSMenuItem *item in self.captureMenuItems) {
        item.keyEquivalent = self.shortcut.available ? self.shortcut.keyEquivalent : @"";
        item.keyEquivalentModifierMask = self.shortcut.keyEquivalentModifierMask;
    }
    [self.shortcutRecorder refreshShortcutTitle];
}

- (void)resetShortcut:(id)sender {
    [self.shortcutRecorder cancelRecording];
    NSError *error = nil;
    if ([self.shortcut restoreDefaultWithError:&error]) self.resultLabel.stringValue = @"已恢复默认快捷键。";
    else self.resultLabel.stringValue = error.localizedDescription;
    [self refreshShortcut];
}

- (void)refreshBorderColor {
    NSString *hex = [NSUserDefaults.standardUserDefaults stringForKey:@"XCSelectionBorderColor"] ?: @"#0099FF";
    NSColor *color = XCSelectionBorderColor();
    self.borderColorButton.image = [NSImage imageWithSize:NSMakeSize(26, 14) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [color setFill];
        [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:4 yRadius:4] fill];
        return YES;
    }];
    self.borderColorLabel.stringValue = hex;
}

- (void)chooseBorderColor:(id)sender {
    [self.shortcutRecorder cancelRecording];
    [NSApp activateIgnoringOtherApps:YES];
    NSColorPanel *panel = NSColorPanel.sharedColorPanel;
    panel.color = XCSelectionBorderColor();
    panel.target = self; panel.action = @selector(changeBorderColor:); panel.continuous = YES;
    [panel makeKeyAndOrderFront:nil];
}

- (void)changeBorderColor:(NSColorPanel *)sender {
    NSColor *color = [sender.color colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (!color) return;
    XCSetSelectionBorderColor(color);
    [self refreshBorderColor];
    self.resultLabel.stringValue = @"选框颜色已保存，下次截图生效。";
}

- (void)resetBorderColor:(id)sender {
    [NSUserDefaults.standardUserDefaults setObject:@"#0099FF" forKey:@"XCSelectionBorderColor"];
    [self refreshBorderColor];
    self.resultLabel.stringValue = @"已恢复默认选框颜色。";
}

- (void)refreshPermission {
    BOOL allowed = CGPreflightScreenCaptureAccess();
    self.permissionLabel.stringValue = allowed ? @"截图已就绪" : @"首次截图需要允许屏幕录制权限";
    self.permissionLabel.textColor = allowed ? NSColor.secondaryLabelColor : NSColor.systemOrangeColor;
}
- (void)applicationDidBecomeActive:(NSNotification *)notification { [self refreshPermission]; }
- (BOOL)applicationShouldHandleReopen:(NSApplication *)application hasVisibleWindows:(BOOL)visible { [self showWindow:nil]; return YES; }
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return NO; }
- (void)toggleResolution:(NSButton *)sender { [NSUserDefaults.standardUserDefaults setBool:sender.state == NSControlStateValueOn forKey:@"XCHighResolution"]; }
- (void)toggleSound:(NSButton *)sender { [NSUserDefaults.standardUserDefaults setBool:sender.state == NSControlStateValueOn forKey:@"XCPlaySound"]; }

- (void)startCapture:(id)sender {
    if (self.capturePending || self.engine.capturing) return;
    if (self.shortcutRecorder.recording) return;
    if (!CGPreflightScreenCaptureAccess()) {
        [self openPrivacy:sender];
        return;
    }
    self.capturePending = YES;
    [NSColorPanel.sharedColorPanel orderOut:nil];
    [self.window orderOut:nil];
    // 下一次事件循环让菜单退出跟踪，不做固定延迟或窗口过渡动画。
    dispatch_async(dispatch_get_main_queue(), ^{
        self.capturePending = NO;
        [NSApp activateIgnoringOtherApps:YES];
        @try {
            BOOL started = [self.engine startWithDelegate:self];
            if (getenv("XCLIP_TRACE")) NSLog(@"XScreenCapture capture started=%d windows=%lu", started, (unsigned long)NSApp.windows.count);
            if (!started) [self showError:@"截图未能启动，请稍后重试。"];
        } @catch (NSException *exception) {
            [self.engine cancel];
            [self showError:[NSString stringWithFormat:@"截图引擎异常：%@", exception.reason]];
        }
    });
}

// delegate 方法签名来自 QQ 自身调用点；引擎已负责写入剪贴板及保存文件。
- (void)captureRequestDidCancel:(id)request {
    if (getenv("XCLIP_TRACE")) NSLog(@"XScreenCapture capture cancelled: %@", NSThread.callStackSymbols);
    self.resultLabel.stringValue = @"已取消截图。";
}
- (void)captureRequestDidChange:(id)request { [self.engine cancel]; }
- (void)captureRequest:(id)request didFinishWithImageData:(NSData *)data saveToPath:(NSString *)path error:(NSError *)error {
    if (error) { [self showError:error.localizedDescription]; return; }
    if (!data.length || ![[NSBitmapImageRep alloc] initWithData:data]) {
        [self showError:@"没有收到有效截图，请检查屏幕录制权限后重试。"];
        return;
    }
    self.lastImage = data;
    // 原框架保存失败也可能返回 error=nil，必须核对磁盘结果。
    if (path.length) {
        NSData *saved = [NSData dataWithContentsOfFile:path];
        if (!saved.length || ![[NSBitmapImageRep alloc] initWithData:saved]) {
            [self showError:@"无法确认图片已保存。请从菜单栏选择“保存上一张…”重试。"];
            return;
        }
    }
    self.resultLabel.stringValue = path.length ? [@"已保存：" stringByAppendingString:path.lastPathComponent] : @"已复制到剪贴板，可直接粘贴。";
}
- (void)copyLast:(id)sender {
    if (!self.lastImage) return;
    [NSPasteboard.generalPasteboard clearContents];
    [NSPasteboard.generalPasteboard setData:self.lastImage forType:NSPasteboardTypePNG];
}
- (void)saveLast:(id)sender {
    if (!self.lastImage) return;
    [NSApp activateIgnoringOtherApps:YES];
    NSSavePanel *panel = [NSSavePanel savePanel]; panel.allowedContentTypes = @[UTTypePNG];
    NSDateFormatter *formatter = [NSDateFormatter new]; formatter.dateFormat = @"yyyy-MM-dd HH.mm.ss";
    panel.nameFieldStringValue = [NSString stringWithFormat:@"XScreenCapture %@.png", [formatter stringFromDate:NSDate.date]];
    if ([panel runModal] == NSModalResponseOK) {
        NSError *error; if (![self.lastImage writeToURL:panel.URL options:NSDataWritingAtomic error:&error]) [self showError:error.localizedDescription];
    }
}
- (void)openPrivacy:(id)sender {
    NSURL *url = [NSBundle.mainBundle.privateFrameworksURL URLByAppendingPathComponent:@"libXClipPermissionBridge.dylib"];
    void *bridge = dlopen(url.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
    Class<XCPermissionGuideAPI> guide = NSClassFromString(@"XCPermissionGuide");
    if (bridge && [guide respondsToSelector:@selector(showFromRect:)]) {
        NSRect source = NSMakeRect(NSEvent.mouseLocation.x - 16, NSEvent.mouseLocation.y - 16, 32, 32);
        if ([sender isKindOfClass:NSView.class] && [(NSView *)sender window]) {
            NSView *view = sender;
            source = [view.window convertRectToScreen:[view convertRect:view.bounds toView:nil]];
        }
        [guide showFromRect:source];
        self.resultLabel.stringValue = @"授权后如仍未就绪，请退出并重新打开 XScreenCapture。";
    } else {
        // 资源/桥接加载失败时仍保留系统入口，不阻塞授权。
        [NSWorkspace.sharedWorkspace openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"]];
    }
}
- (void)showError:(NSString *)message {
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [NSAlert new]; alert.messageText = @"XScreenCapture"; alert.informativeText = message;
    [alert addButtonWithTitle:@"好"]; [alert runModal];
}
- (void)quit:(id)sender { [NSApp terminate:nil]; }
- (void)applicationWillTerminate:(NSNotification *)notification {
    [self.engine cancel];
    [self.shortcutRecorder cancelRecording];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    self.shortcut = nil;
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc == 2 && strcmp(argv[1], "--self-test") == 0) {
            XCCaptureEngine *engine = [XCCaptureEngine new]; NSError *error;
            BOOL success = [engine loadWithError:&error];
            NSDictionary *report = success ? [engine diagnostics] : @{@"error": error.localizedDescription ?: @"未知错误"};
            NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
            puts([[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding].UTF8String);
            return success ? 0 : 1;
        }
        NSApplication *app = NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        XCAppDelegate *delegate = [XCAppDelegate new]; app.delegate = delegate;
        [app run];
    }
    return 0;
}
