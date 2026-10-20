#import <Cocoa/Cocoa.h>

// 从本机 QQ 6.9.86 的 Objective-C 元数据与 ARM64 调用点恢复的 ABI。
// 只声明本宿主使用的接口；不代表原始源码或稳定的公开 SDK。
@protocol XClipRecoveredCaptureABI <NSObject>
+ (instancetype)sharedInstance;
- (void)setDelegate:(id)delegate;
- (void)setShowSwitch:(BOOL)value;
- (void)setNeedSelectSavePath:(BOOL)value;
- (void)setNeedAddCustomView:(BOOL)value;
- (void)setRunAlone:(BOOL)value;
- (void)setThemeName:(NSString *)value;
- (void)setFileNamePrefix:(NSString *)value;
- (void)setHighResolution:(BOOL)value;
- (void)setPlaySound:(BOOL)value;
- (void)setFileType:(NSUInteger)value;
- (BOOL)changeThemeTo:(NSString *)value;
- (NSArray *)functionButtonArray;
- (NSInteger)type;
@end

@interface XCCaptureEngine : NSObject
@property(nonatomic, readonly) BOOL capturing;
- (BOOL)loadWithError:(NSError **)error;
- (BOOL)startWithDelegate:(id)delegate;
- (void)cancel;
- (NSDictionary *)diagnostics;
@end
