#import "ShortcutController.h"
#import <Carbon/Carbon.h>

static NSString *const XCShortcutKeyCodeKey = @"XCShortcutKeyCode";
static NSString *const XCShortcutModifiersKey = @"XCShortcutModifiers";
static const NSEventModifierFlags XCShortcutAllowedModifiers = NSEventModifierFlagCommand |
    NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagShift;
static const NSEventModifierFlags XCShortcutDefaultModifiers = NSEventModifierFlagCommand | NSEventModifierFlagShift;

static NSError *XCShortcutError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"milu.qqjietu.Shortcut" code:code
                          userInfo:@{NSLocalizedDescriptionKey: message}];
}

static BOOL XCShortcutIsValid(unsigned short keyCode, NSEventModifierFlags modifiers) {
    if (!(modifiers & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption))) return NO;
    if (keyCode >= 128) return NO;
    switch (keyCode) {
        case kVK_Escape: case kVK_Command: case kVK_RightCommand:
        case kVK_Shift: case kVK_RightShift: case kVK_Option: case kVK_RightOption:
        case kVK_Control: case kVK_RightControl: case kVK_CapsLock: case kVK_Function:
            return NO;
        default: return YES;
    }
}

static UInt32 XCCarbonModifiers(NSEventModifierFlags flags) {
    UInt32 result = 0;
    if (flags & NSEventModifierFlagCommand) result |= cmdKey;
    if (flags & NSEventModifierFlagControl) result |= controlKey;
    if (flags & NSEventModifierFlagOption) result |= optionKey;
    if (flags & NSEventModifierFlagShift) result |= shiftKey;
    return result;
}

static NSString *XCKeyCharacter(unsigned short keyCode) {
    switch (keyCode) {
        case kVK_Return: return @"\r";
        case kVK_Tab: return @"\t";
        case kVK_Space: return @" ";
        case kVK_Delete: return @"\b";
        case kVK_ANSI_KeypadEnter: return [NSString stringWithFormat:@"%C", (unichar)NSEnterCharacter];
        case kVK_ForwardDelete: return [NSString stringWithFormat:@"%C", (unichar)NSDeleteFunctionKey];
        case kVK_LeftArrow: return [NSString stringWithFormat:@"%C", (unichar)NSLeftArrowFunctionKey];
        case kVK_RightArrow: return [NSString stringWithFormat:@"%C", (unichar)NSRightArrowFunctionKey];
        case kVK_UpArrow: return [NSString stringWithFormat:@"%C", (unichar)NSUpArrowFunctionKey];
        case kVK_DownArrow: return [NSString stringWithFormat:@"%C", (unichar)NSDownArrowFunctionKey];
        case kVK_Home: return [NSString stringWithFormat:@"%C", (unichar)NSHomeFunctionKey];
        case kVK_End: return [NSString stringWithFormat:@"%C", (unichar)NSEndFunctionKey];
        case kVK_PageUp: return [NSString stringWithFormat:@"%C", (unichar)NSPageUpFunctionKey];
        case kVK_PageDown: return [NSString stringWithFormat:@"%C", (unichar)NSPageDownFunctionKey];
        case kVK_ANSI_KeypadClear: return [NSString stringWithFormat:@"%C", (unichar)NSClearLineFunctionKey];
        default: break;
    }
    const unsigned short functionKeys[] = {kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
        kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15,
        kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20};
    for (NSUInteger i = 0; i < sizeof(functionKeys) / sizeof(functionKeys[0]); i++) {
        if (keyCode == functionKeys[i]) return [NSString stringWithFormat:@"%C", (unichar)(NSF1FunctionKey + i)];
    }
    TISInputSourceRef source = TISCopyCurrentKeyboardLayoutInputSource();
    CFDataRef layoutData = source ? TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) : NULL;
    if (!layoutData) {
        if (source) CFRelease(source);
        source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource();
        layoutData = source ? TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) : NULL;
    }
    NSString *result = @"";
    if (layoutData) {
        const UCKeyboardLayout *layout = (const UCKeyboardLayout *)CFDataGetBytePtr(layoutData);
        UInt32 deadKeyState = 0;
        UniChar characters[8];
        UniCharCount length = 0;
        if (UCKeyTranslate(layout, keyCode, kUCKeyActionDisplay, 0, LMGetKbdType(),
                           kUCKeyTranslateNoDeadKeysBit, &deadKeyState, 8, &length, characters) == noErr && length) {
            result = [[NSString stringWithCharacters:characters length:length] lowercaseString];
        }
    }
    if (source) CFRelease(source);
    return result;
}

static NSString *XCKeyDisplay(unsigned short keyCode) {
    NSDictionary<NSNumber *, NSString *> *special = @{
        @(kVK_Return): @"↩", @(kVK_Tab): @"⇥", @(kVK_Space): @"空格",
        @(kVK_Delete): @"⌫", @(kVK_ForwardDelete): @"⌦", @(kVK_ANSI_KeypadEnter): @"⌤",
        @(kVK_LeftArrow): @"←", @(kVK_RightArrow): @"→", @(kVK_UpArrow): @"↑", @(kVK_DownArrow): @"↓",
        @(kVK_Home): @"↖", @(kVK_End): @"↘", @(kVK_PageUp): @"⇞", @(kVK_PageDown): @"⇟",
        @(kVK_ANSI_KeypadClear): @"清除"
    };
    NSString *label = special[@(keyCode)];
    if (label) return label;
    NSString *character = XCKeyCharacter(keyCode);
    if (character.length == 1 && [character characterAtIndex:0] >= NSF1FunctionKey && [character characterAtIndex:0] <= NSF20FunctionKey) {
        return [NSString stringWithFormat:@"F%u", (unsigned)([character characterAtIndex:0] - NSF1FunctionKey + 1)];
    }
    return character.length ? character.uppercaseString : [NSString stringWithFormat:@"键 %u", keyCode];
}

@interface XCShortcutController ()
@property(nonatomic, readwrite) unsigned short keyCode;
@property(nonatomic, readwrite) NSEventModifierFlags modifiers;
@property(nonatomic) EventHotKeyRef hotKey;
@property(nonatomic) EventHandlerRef eventHandler;
@property(nonatomic) UInt32 hotKeyIdentifier;
@property(nonatomic) BOOL paused;
@property(nonatomic, copy) dispatch_block_t handler;
- (void)pauseRegistration;
- (BOOL)handleHotKeyEvent:(EventRef)event;
@end

static OSStatus XCShortcutHandleEvent(EventHandlerCallRef next, EventRef event, void *context) {
    (void)next;
    return [(__bridge XCShortcutController *)context handleHotKeyEvent:event] ? noErr : eventNotHandledErr;
}

@implementation XCShortcutController
- (instancetype)initWithHandler:(dispatch_block_t)handler {
    self = [super init];
    if (self) {
        _handler = [handler copy];
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        [defaults registerDefaults:@{XCShortcutKeyCodeKey: @(kVK_ANSI_2), XCShortcutModifiersKey: @(XCShortcutDefaultModifiers)}];
        NSInteger storedCode = [defaults integerForKey:XCShortcutKeyCodeKey];
        NSEventModifierFlags storedFlags = (NSEventModifierFlags)[defaults integerForKey:XCShortcutModifiersKey] & XCShortcutAllowedModifiers;
        if (storedCode >= 0 && storedCode < 128 && XCShortcutIsValid((unsigned short)storedCode, storedFlags)) {
            _keyCode = (unsigned short)storedCode;
            _modifiers = storedFlags;
        } else {
            _keyCode = kVK_ANSI_2;
            _modifiers = XCShortcutDefaultModifiers;
        }
    }
    return self;
}

- (BOOL)isAvailable { return self.hotKey != NULL && !self.paused; }
- (NSString *)keyEquivalent { return XCKeyCharacter(self.keyCode); }
- (NSEventModifierFlags)keyEquivalentModifierMask { return self.modifiers; }
- (NSString *)displayString {
    NSMutableString *text = [NSMutableString string];
    if (self.modifiers & NSEventModifierFlagControl) [text appendString:@"⌃"];
    if (self.modifiers & NSEventModifierFlagOption) [text appendString:@"⌥"];
    if (self.modifiers & NSEventModifierFlagCommand) [text appendString:@"⌘"];
    if (self.modifiers & NSEventModifierFlagShift) [text appendString:@"⇧"];
    [text appendString:XCKeyDisplay(self.keyCode)];
    return text;
}

- (BOOL)ensureEventHandler:(NSError **)error {
    if (self.eventHandler) return YES;
    EventTypeSpec type = {kEventClassKeyboard, kEventHotKeyPressed};
    EventHandlerRef handler = NULL;
    OSStatus status = InstallApplicationEventHandler(XCShortcutHandleEvent, 1, &type, (__bridge void *)self, &handler);
    if (status != noErr) {
        if (error) *error = XCShortcutError(status, @"无法安装快捷键监听，请重新打开应用。");
        return NO;
    }
    self.eventHandler = handler;
    return YES;
}

- (BOOL)registerShortcutWithError:(NSError **)error {
    NSAssert(NSThread.isMainThread, @"快捷键必须在主线程操作");
    self.paused = NO;
    return [self updateKeyCode:self.keyCode modifiers:self.modifiers error:error];
}

- (BOOL)updateKeyCode:(unsigned short)keyCode modifiers:(NSEventModifierFlags)modifiers error:(NSError **)error {
    NSAssert(NSThread.isMainThread, @"快捷键必须在主线程操作");
    modifiers &= XCShortcutAllowedModifiers;
    if (!XCShortcutIsValid(keyCode, modifiers)) {
        if (error) *error = XCShortcutError(-1, @"请同时按住 ⌘、⌃ 或 ⌥ 中至少一个修饰键，再按一个按键。");
        return NO;
    }
    if (self.paused) {
        if (error) *error = XCShortcutError(-2, @"请先结束快捷键录制。");
        return NO;
    }
    if (self.hotKey && keyCode == self.keyCode && modifiers == self.modifiers) return YES;
    if (![self ensureEventHandler:error]) return NO;
    EventHotKeyRef replacement = NULL;
    UInt32 identifier = self.hotKeyIdentifier + 1;
    OSStatus status = RegisterEventHotKey(keyCode, XCCarbonModifiers(modifiers),
        (EventHotKeyID){'XSCp', identifier}, GetApplicationEventTarget(), 0, &replacement);
    if (status != noErr) {
        if (error) *error = XCShortcutError(status, @"该组合可能已被系统或其他应用占用，未更改原快捷键。");
        return NO;
    }
    // 新组合注册成功后才撤销旧注册，并写入设置。
    EventHotKeyRef previous = self.hotKey;
    self.hotKey = replacement;
    self.hotKeyIdentifier = identifier;
    self.keyCode = keyCode;
    self.modifiers = modifiers;
    if (previous) UnregisterEventHotKey(previous);
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setInteger:keyCode forKey:XCShortcutKeyCodeKey];
    [defaults setInteger:(NSInteger)modifiers forKey:XCShortcutModifiersKey];
    return YES;
}

- (BOOL)restoreDefaultWithError:(NSError **)error {
    return [self updateKeyCode:kVK_ANSI_2 modifiers:XCShortcutDefaultModifiers error:error];
}

- (void)pauseRegistration {
    NSAssert(NSThread.isMainThread, @"快捷键必须在主线程操作");
    self.paused = YES;
    if (self.hotKey) { UnregisterEventHotKey(self.hotKey); self.hotKey = NULL; }
}

- (BOOL)handleHotKeyEvent:(EventRef)event {
    EventHotKeyID identifier = {0, 0};
    if (GetEventParameter(event, kEventParamDirectObject, typeEventHotKeyID, NULL, sizeof(identifier), NULL, &identifier) != noErr) return NO;
    if (identifier.signature != 'XSCp' || identifier.id != self.hotKeyIdentifier || !self.isAvailable) return NO;
    if (self.handler) self.handler();
    return YES;
}

- (void)dealloc {
    if (_hotKey) UnregisterEventHotKey(_hotKey);
    if (_eventHandler) RemoveEventHandler(_eventHandler);
}
@end

@interface XCShortcutRecorder ()
@property(nonatomic, strong) XCShortcutController *controller;
@property(nonatomic, readwrite, getter=isRecording) BOOL recording;
@property(nonatomic, strong) id eventMonitor;
@end

@implementation XCShortcutRecorder
- (instancetype)initWithController:(XCShortcutController *)controller {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _controller = controller;
        self.bezelStyle = NSBezelStyleRounded;
        self.buttonType = NSButtonTypeMomentaryPushIn;
        self.target = self;
        self.action = @selector(beginRecording:);
        self.toolTip = @"点击后按下新组合；Esc 或点击其他位置取消。";
        [self refreshShortcutTitle];
    }
    return self;
}

- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)resignFirstResponder {
    [self cancelRecording];
    return [super resignFirstResponder];
}

- (void)refreshShortcutTitle {
    if (!self.recording) self.title = self.controller.displayString;
}

- (void)reportChanged:(BOOL)changed message:(NSString *)message error:(NSError *)error {
    NSAssert(NSThread.isMainThread, @"快捷键提示必须在主线程更新");
    if (self.completionHandler) self.completionHandler(changed, message, error);
}

- (void)beginRecording:(id)sender {
    (void)sender;
    if (self.recording) { [self cancelRecording]; return; }
    if (!self.window) return;
    [NSApp activateIgnoringOtherApps:YES];
    [self.window makeKeyAndOrderFront:nil];
    if (![self.window makeFirstResponder:self]) return;
    self.recording = YES;
    self.title = @"请按快捷键…";
    [self.controller pauseRegistration];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(cancelForNotification:)
        name:NSWindowDidResignKeyNotification object:self.window];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(cancelForNotification:)
        name:NSApplicationDidResignActiveNotification object:NSApp];
    __weak typeof(self) weakSelf = self;
    self.eventMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown | NSEventMaskLeftMouseDown |
        NSEventMaskRightMouseDown | NSEventMaskOtherMouseDown handler:^NSEvent *(NSEvent *event) {
        XCShortcutRecorder *recorder = weakSelf;
        if (!recorder || !recorder.recording) return event;
        if (event.type == NSEventTypeKeyDown) {
            if (event.keyCode == kVK_Escape) [recorder cancelRecording];
            else if (!event.isARepeat) [recorder finishKeyCode:event.keyCode modifiers:event.modifierFlags];
            return nil;
        }
        BOOL clickedRecorder = event.window == recorder.window &&
            NSPointInRect([recorder convertPoint:event.locationInWindow fromView:nil], recorder.bounds);
        [recorder cancelRecording];
        return clickedRecorder ? nil : event;
    }];
    [self reportChanged:NO message:@"按下新组合（需含 ⌘、⌃ 或 ⌥）；Esc 取消。" error:nil];
}

- (void)removeRecordingObservers {
    self.recording = NO;
    if (self.eventMonitor) { [NSEvent removeMonitor:self.eventMonitor]; self.eventMonitor = nil; }
    [NSNotificationCenter.defaultCenter removeObserver:self name:NSWindowDidResignKeyNotification object:nil];
    [NSNotificationCenter.defaultCenter removeObserver:self name:NSApplicationDidResignActiveNotification object:nil];
}

- (void)finishKeyCode:(unsigned short)keyCode modifiers:(NSEventModifierFlags)modifiers {
    [self removeRecordingObservers];
    NSError *restoreError = nil;
    // 先恢复旧注册，随后用控制器的事务式替换，失败时旧组合继续生效。
    [self.controller registerShortcutWithError:&restoreError];
    NSError *error = nil;
    BOOL success = [self.controller updateKeyCode:keyCode modifiers:modifiers error:&error];
    [self refreshShortcutTitle];
    if (success) {
        [self reportChanged:YES message:[NSString stringWithFormat:@"截图快捷键已设为 %@。", self.controller.displayString] error:nil];
    } else {
        NSString *message = error.localizedDescription ?: @"未能设置快捷键。";
        if (restoreError && !self.controller.isAvailable) message = [message stringByAppendingString:@" 原组合也暂时无法注册，请从菜单栏截图。"];
        [self reportChanged:NO message:message error:error ?: restoreError];
    }
}

- (void)cancelForNotification:(NSNotification *)notification {
    (void)notification;
    [self cancelRecording];
}

- (void)cancelRecording {
    if (!self.recording) return;
    [self removeRecordingObservers];
    NSError *error = nil;
    [self.controller registerShortcutWithError:&error];
    [self refreshShortcutTitle];
    [self reportChanged:NO message:error ? @"已取消录制，但原快捷键暂时无法注册，请从菜单栏截图。" : @"已取消快捷键录制。" error:error];
}

- (void)viewWillMoveToWindow:(NSWindow *)newWindow {
    if (newWindow != self.window) [self cancelRecording];
    [super viewWillMoveToWindow:newWindow];
}

- (void)dealloc {
    if (_eventMonitor) [NSEvent removeMonitor:_eventMonitor];
    [NSNotificationCenter.defaultCenter removeObserver:self];
    if (_recording) [_controller registerShortcutWithError:NULL];
}
@end
