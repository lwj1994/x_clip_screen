#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Install after loading the capture framework, before creating any toolbar.
/// Main-thread only; returns NO without changing the framework on ABI mismatch.
FOUNDATION_EXPORT BOOL XCInstallToolbarLayout(void);

NS_ASSUME_NONNULL_END
