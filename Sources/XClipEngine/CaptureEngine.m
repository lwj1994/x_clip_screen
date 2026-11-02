#import "CaptureEngine.h"
#import "CaptureAppearance.h"
#import "ToolbarAppearance.h"
#import "ToolbarLayout.h"
#import <objc/runtime.h>
#import <dlfcn.h>

@interface XCCaptureEngine () {
    BOOL (*_startCapture)(id);
    BOOL (*_isCapturing)(void);
    BOOL (*_cancelCapture)(void);
}
@property(nonatomic) BOOL loaded;
@property(nonatomic, strong) id activeRequest;
@end

static void XCNoReporting(id object, SEL selector) {
    // 独立截图宿主不启用原框架的崩溃/统计上传启动器。
    (void)object; (void)selector;
}

static void (*XCOriginalSetupButtons)(id, SEL);
static void XCSetupButtons(id toolbar, SEL selector) {
    XCOriginalSetupButtons(toolbar, selector);
    for (NSButton *button in [(id<XClipRecoveredCaptureABI>)toolbar functionButtonArray]) {
        NSInteger type = [(id<XClipRecoveredCaptureABI>)button type];
        // OCR 的原路径依赖 QQ App Group；长截图尚未完成独立验证。
        if (type == 0 || type == 2) { button.hidden = YES; button.enabled = NO; }
    }
}

@implementation XCCaptureEngine
- (BOOL)fail:(NSString *)message error:(NSError **)error {
    if (error) *error = [NSError errorWithDomain:@"XClip.Engine" code:1
                                      userInfo:@{NSLocalizedDescriptionKey: message}];
    return NO;
}

- (BOOL)loadWithError:(NSError **)error {
    if (self.loaded) return YES;
    NSURL *frameworks = NSBundle.mainBundle.privateFrameworksURL;
    for (NSString *name in @[@"CocoaLumberjack", @"AFNetworking", @"JietuFramework"]) {
        NSString *relative = [NSString stringWithFormat:@"%@.framework/Versions/A/%@", name, name];
        NSString *path = [[frameworks URLByAppendingPathComponent:relative] path];
        if (!dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL)) {
            const char *reason = dlerror();
            return [self fail:[NSString stringWithFormat:@"无法加载 %@：%s", name, reason ?: "未知错误"] error:error];
        }
    }
    // 在创建管理器前核对 ABI，QQ 升级后不带着错误签名调用私有接口。
    NSArray *contract = @[
        @[@"JTCaptureRequest", @"setDelegate:", @"v24@0:8@16"],
        @[@"JTCaptureRequest", @"setShowSwitch:", @"v20@0:8B16"],
        @[@"JTCaptureRequest", @"setNeedSelectSavePath:", @"v20@0:8B16"],
        @[@"JTCaptureRequest", @"setNeedAddCustomView:", @"v20@0:8B16"],
        @[@"JTCaptureManager", @"startCaptureByRequest:", @"B24@0:8@16"],
        @[@"JTCaptureSetting", @"setRunAlone:", @"v20@0:8B16"],
        @[@"JTCaptureSetting", @"setThemeName:", @"v24@0:8@16"],
        @[@"JTCaptureSetting", @"setFileNamePrefix:", @"v24@0:8@16"],
        @[@"JTCaptureSetting", @"setHighResolution:", @"v20@0:8B16"],
        @[@"JTCaptureSetting", @"setPlaySound:", @"v20@0:8B16"],
        @[@"JTCaptureSetting", @"setFileType:", @"v24@0:8Q16"],
        @[@"JTCaptureThemeManager", @"changeThemeTo:", @"B24@0:8@16"],
        @[@"JTToolbarView", @"setupFunctionButtons", @"v16@0:8"],
        @[@"JTToolbarView", @"functionButtonArray", @"@16@0:8"],
        @[@"JTToolbarButton", @"type", @"q16@0:8"]
    ];
    for (NSArray *entry in contract) {
        Method method = class_getInstanceMethod(NSClassFromString(entry[0]), NSSelectorFromString(entry[1]));
        NSString *expected = [entry[2] stringByReplacingOccurrencesOfString:@"B" withString:@(@encode(BOOL))];
        if (!method || strcmp(method_getTypeEncoding(method), expected.UTF8String))
            return [self fail:[NSString stringWithFormat:@"截图接口不兼容：%@ %@，请重新检查当前 QQ 版本。", entry[0], entry[1]] error:error];
    }
    Method shared = class_getClassMethod(NSClassFromString(@"JTCaptureSetting"), @selector(sharedInstance));
    if (!shared || strcmp(method_getTypeEncoding(shared), "@16@0:8"))
        return [self fail:@"截图配置接口不兼容。" error:error];

    // 这些签名已由静态反汇编及 runtime metadata 交叉确认。
    Method crash = class_getClassMethod(NSClassFromString(@"JTCrashRqdManager"), NSSelectorFromString(@"startCrashReport"));
    Method stats = class_getInstanceMethod(NSClassFromString(@"MttWupManager"), NSSelectorFromString(@"startStat"));
    if (!crash || !stats || strcmp(method_getTypeEncoding(crash), "v16@0:8") || strcmp(method_getTypeEncoding(stats), "v16@0:8"))
        return [self fail:@"无法确认统计启动器接口，已停止加载截图引擎。" error:error];
    method_setImplementation(crash, (IMP)XCNoReporting);
    method_setImplementation(stats, (IMP)XCNoReporting);
    if (!XCOriginalSetupButtons) {
        Method setup = class_getInstanceMethod(NSClassFromString(@"JTToolbarView"), NSSelectorFromString(@"setupFunctionButtons"));
        XCOriginalSetupButtons = (void (*)(id, SEL))method_setImplementation(setup, (IMP)XCSetupButtons);
    }
    if (!XCInstallCaptureAppearance(error)) return NO;
    if (!XCInstallToolbarAppearance()) return [self fail:@"截图工具栏外观接口不兼容，请重新检查当前 QQ 版本。" error:error];
    if (!XCInstallToolbarLayout()) return [self fail:@"截图工具栏布局接口不兼容，请重新检查当前 QQ 版本。" error:error];

    _startCapture = (BOOL (*)(id))dlsym(RTLD_DEFAULT, "JTStartCapture");
    _isCapturing = (BOOL (*)(void))dlsym(RTLD_DEFAULT, "JTIsCapturing");
    _cancelCapture = (BOOL (*)(void))dlsym(RTLD_DEFAULT, "JTCancelCapture");
    if (!_startCapture || !_isCapturing || !_cancelCapture)
        return [self fail:@"截图引擎缺少必需的 C 入口。" error:error];

    NSBundle *bundle = [NSBundle bundleForClass:NSClassFromString(@"JTCaptureRequest")];
    NSString *theme = [bundle.resourcePath stringByAppendingPathComponent:@"ThemeResources/Jietu-theme/themeConfigue.json"];
    if (![NSFileManager.defaultManager fileExistsAtPath:theme])
        return [self fail:@"缺少截图工具栏主题资源，请重新构建。" error:error];
    self.loaded = YES;
    return YES;
}

- (BOOL)capturing { return self.loaded && _isCapturing(); }

- (BOOL)startWithDelegate:(id)delegate error:(NSError **)error {
    @try {
        if ([self startWithDelegate:delegate]) return YES;
        return [self fail:@"截图未能启动，请稍后重试。" error:error];
    } @catch (NSException *exception) {
        [self cancel];
        return [self fail:[NSString stringWithFormat:@"截图引擎异常：%@", exception.reason] error:error];
    }
}

- (BOOL)startWithDelegate:(id)delegate {
    if (!self.loaded || self.capturing) return NO;
    id<XClipRecoveredCaptureABI> setting = [(Class<XClipRecoveredCaptureABI>)NSClassFromString(@"JTCaptureSetting") sharedInstance];
    [setting setRunAlone:YES];
    [setting setThemeName:@"Jietu-theme"];
    [setting setFileNamePrefix:@"XScreenCapture"];
    [setting setHighResolution:[NSUserDefaults.standardUserDefaults boolForKey:@"XCHighResolution"]];
    [setting setPlaySound:[NSUserDefaults.standardUserDefaults boolForKey:@"XCPlaySound"]];
    [setting setFileType:NSBitmapImageFileTypePNG];
    // 管理器初始化会重置主题，必须随后再设置；clean 会释放单例，每次重新获取。
    [(Class<XClipRecoveredCaptureABI>)NSClassFromString(@"JTCaptureManager") sharedInstance];
    id<XClipRecoveredCaptureABI> themeManager = [(Class<XClipRecoveredCaptureABI>)NSClassFromString(@"JTCaptureThemeManager") sharedInstance];
    if (![themeManager changeThemeTo:@"Jietu-theme"]) return NO;
    id<XClipRecoveredCaptureABI> request = [NSClassFromString(@"JTCaptureRequest") new];
    [request setDelegate:delegate];
    [request setShowSwitch:NO];
    [request setNeedSelectSavePath:YES];
    [request setNeedAddCustomView:NO];
    self.activeRequest = request;
    XCPrepareManualCapture();
    BOOL started = _startCapture(request);
    if (started && getenv("XCLIP_UI_TEST")) {
        // UI 自动化工具会临时切换前台应用；仅测试模式保留浮层以便检查。
        id manager = [(Class<XClipRecoveredCaptureABI>)NSClassFromString(@"JTCaptureManager") sharedInstance];
        [NSNotificationCenter.defaultCenter removeObserver:manager name:NSApplicationWillResignActiveNotification object:nil];
    }
    return started;
}

- (void)cancel { if (self.capturing) _cancelCapture(); self.activeRequest = nil; }

- (NSDictionary *)diagnostics {
    return @{@"engineLoaded": @(self.loaded), @"entrypointsAvailable": @(_startCapture && _isCapturing && _cancelCapture),
             @"requestClass": NSStringFromClass(NSClassFromString(@"JTCaptureRequest")) ?: @"missing",
             @"theme": @"Jietu-theme", @"qqProcessRequired": @NO,
             @"frameworkBundle": [NSBundle bundleForClass:NSClassFromString(@"JTCaptureRequest")].bundlePath ?: @"missing"};
}
@end
