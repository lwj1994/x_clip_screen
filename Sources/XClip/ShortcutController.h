#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

// 所有方法在主线程调用；修饰键使用 NSEventModifierFlags，不使用 Carbon 位值。
@interface XCShortcutController : NSObject
- (instancetype)initWithHandler:(dispatch_block_t)handler;
@property(nonatomic, readonly) unsigned short keyCode;
@property(nonatomic, readonly) NSEventModifierFlags modifiers;
@property(nonatomic, readonly, getter=isAvailable) BOOL available;
@property(nonatomic, readonly) NSString *displayString;
@property(nonatomic, readonly) NSString *keyEquivalent;
@property(nonatomic, readonly) NSEventModifierFlags keyEquivalentModifierMask;
- (BOOL)registerShortcutWithError:(NSError * _Nullable * _Nullable)error;
- (BOOL)updateKeyCode:(unsigned short)keyCode
            modifiers:(NSEventModifierFlags)modifiers
                error:(NSError * _Nullable * _Nullable)error;
- (BOOL)restoreDefaultWithError:(NSError * _Nullable * _Nullable)error;
@end

// 点击后录制一次组合。Esc、点击其他位置、窗口失去焦点都会取消。
@interface XCShortcutRecorder : NSButton
- (instancetype)initWithController:(XCShortcutController *)controller;
@property(nonatomic, readonly, getter=isRecording) BOOL recording;
// 成功修改时 changed=YES；取消/错误为 NO，message 可直接显示。主线程回调。
@property(nonatomic, copy, nullable) void (^completionHandler)(BOOL changed, NSString *message, NSError * _Nullable error);
- (void)cancelRecording;
- (void)refreshShortcutTitle;
@end

NS_ASSUME_NONNULL_END
