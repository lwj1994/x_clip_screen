#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import "ShortcutController.h"

// 放入独立临时 .app 后直接运行 executable；不会打开窗口或合成按键。
// CFBundleIdentifier 必须为 milu.qqjietu.shortcut-tests.<唯一值>，退出时移除测试偏好。
static void XCRequire(BOOL condition, NSString *message, NSMutableArray<NSString *> *checks) {
    if (!condition) @throw [NSException exceptionWithName:@"XCShortcutTestFailure" reason:message userInfo:nil];
    [checks addObject:message];
}

int main(void) {
    @autoreleasepool {
        NSMutableArray<NSString *> *checks = [NSMutableArray array];
        NSString *failure = nil;
        NSString *domain = NSBundle.mainBundle.bundleIdentifier;
        BOOL isolatedDomain = [domain hasPrefix:@"milu.qqjietu.shortcut-tests."];
        NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
        XCShortcutController *controller = nil;
        XCShortcutController *restored = nil;
        EventHotKeyRef blocker = NULL;
        EventHotKeyRef releasedKeyProbe = NULL;
        EventHotKeyRef deallocProbe = NULL;
        __block NSUInteger invocationCount = 0;
        const NSEventModifierFlags flags = NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagCommand;
        const UInt32 carbonFlags = controlKey | optionKey | cmdKey;
        @try {
            XCRequire(isolatedDomain, @"独立测试 bundle ID，禁止写入正式应用偏好", checks);
            [defaults removePersistentDomainForName:domain];
            controller = [[XCShortcutController alloc] initWithHandler:^{ invocationCount++; }];
            XCRequire(controller.keyCode == kVK_ANSI_2 && controller.modifiers == (NSEventModifierFlagCommand | NSEventModifierFlagShift),
                @"无偏好时默认为 ⌘⇧2", checks);
            NSError *error = nil;
            BOOL success = [controller updateKeyCode:kVK_F18 modifiers:flags error:&error];
            XCRequire(success && error == nil && controller.isAvailable,
                [NSString stringWithFormat:@"注册 ⌃⌥⌘F18 成功（错误：%@）", error.localizedDescription ?: @"无"], checks);
            XCRequire([controller.displayString isEqualToString:@"⌃⌥⌘F18"] &&
                controller.keyEquivalent.length == 1 && [controller.keyEquivalent characterAtIndex:0] == NSF18FunctionKey &&
                controller.keyEquivalentModifierMask == flags, @"显示文本与菜单等价键匹配实际组合", checks);
            NSDictionary *saved = [defaults persistentDomainForName:domain];
            XCRequire([saved[@"XCShortcutKeyCode"] unsignedShortValue] == kVK_F18 &&
                [saved[@"XCShortcutModifiers"] unsignedIntegerValue] == flags,
                @"成功注册写入独立 domain 的两个持久化键", checks);

            OSStatus status = RegisterEventHotKey(kVK_F19, carbonFlags, (EventHotKeyID){'XSTt', 1},
                GetApplicationEventTarget(), 0, &blocker);
            XCRequire(status == noErr && blocker != NULL,
                [NSString stringWithFormat:@"建立 ⌃⌥⌘F19 冲突注册（状态 %d）", (int)status], checks);
            error = nil;
            success = [controller updateKeyCode:kVK_F19 modifiers:flags error:&error];
            XCRequire(!success && error != nil, @"被占用组合更新失败并返回错误", checks);
            XCRequire(controller.isAvailable && controller.keyCode == kVK_F18 && controller.modifiers == flags,
                @"更新失败后旧快捷键仍可用且字段不变", checks);
            XCRequire([[defaults persistentDomainForName:domain] isEqualToDictionary:saved],
                @"冲突失败不改变持久化设置", checks);

            error = nil;
            success = [controller updateKeyCode:kVK_ANSI_A modifiers:NSEventModifierFlagShift error:&error];
            XCRequire(!success && error != nil && controller.isAvailable && controller.keyCode == kVK_F18 &&
                controller.modifiers == flags && [[defaults persistentDomainForName:domain] isEqualToDictionary:saved],
                @"仅 Shift 的无效组合不改变原注册或持久化设置", checks);
            error = nil;
            success = [controller updateKeyCode:kVK_Escape modifiers:flags error:&error];
            XCRequire(!success && error != nil && controller.keyCode == kVK_F18 && controller.isAvailable,
                @"Esc 保留为取消键，不能覆盖旧注册", checks);

            error = nil;
            success = [controller updateKeyCode:kVK_F20 modifiers:flags error:&error];
            XCRequire(success && error == nil && controller.isAvailable && controller.keyCode == kVK_F20,
                @"切换到空闲 ⌃⌥⌘F20 成功", checks);
            status = RegisterEventHotKey(kVK_F18, carbonFlags, (EventHotKeyID){'XSTt', 2},
                GetApplicationEventTarget(), 0, &releasedKeyProbe);
            XCRequire(status == noErr, @"成功替换后旧 F18 注册已释放", checks);
            [defaults synchronize];

            __weak XCShortcutController *weakController = controller;
            controller = nil;
            XCRequire(weakController == nil, @"控制器无事件处理器持有循环并已析构", checks);
            restored = [[XCShortcutController alloc] initWithHandler:^{ invocationCount++; }];
            XCRequire(restored.keyCode == kVK_F20 && restored.modifiers == flags,
                @"重建控制器读取保存的 F20 组合", checks);
            error = nil;
            success = [restored registerShortcutWithError:&error];
            XCRequire(success && error == nil && restored.isAvailable,
                @"旧实例析构后新实例可重新注册同一组合", checks);
            __weak XCShortcutController *weakRestored = restored;
            restored = nil;
            XCRequire(weakRestored == nil, @"重建实例也正常析构", checks);
            status = RegisterEventHotKey(kVK_F20, carbonFlags, (EventHotKeyID){'XSTt', 3},
                GetApplicationEventTarget(), 0, &deallocProbe);
            XCRequire(status == noErr, @"析构后外部 Carbon 注册可重新占用同一组合", checks);
            XCRequire(invocationCount == 0, @"测试未触发截图处理器", checks);
        } @catch (NSException *exception) {
            failure = exception.reason ?: exception.name;
        } @finally {
            controller = nil;
            restored = nil;
            if (blocker) UnregisterEventHotKey(blocker);
            if (releasedKeyProbe) UnregisterEventHotKey(releasedKeyProbe);
            if (deallocProbe) UnregisterEventHotKey(deallocProbe);
            if (isolatedDomain) {
                [defaults removePersistentDomainForName:domain];
                [defaults synchronize];
            }
        }
        NSDictionary *result = @{
            @"all_checks_passed": @(failure == nil),
            @"checks": checks,
            @"failure": failure ?: NSNull.null,
            @"preference_domain": domain ?: @"未识别",
            @"preference_domain_removed": @(isolatedDomain && [defaults persistentDomainForName:domain].count == 0),
            @"scope": @"独立进程真实 Carbon 注册测试；无窗口、无合成按键；不覆盖录制按钮交互"
        };
        NSData *json = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingPrettyPrinted error:NULL];
        fwrite(json.bytes, 1, json.length, stdout);
        fputc('\n', stdout);
        return failure ? 1 : 0;
    }
}
