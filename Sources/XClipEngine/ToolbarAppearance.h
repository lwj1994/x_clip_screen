#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Install on the main thread after loading the engine and before creating its toolbar.
/// Repeated calls are safe. Returns NO without changing the hook if its ABI is incompatible.
FOUNDATION_EXPORT BOOL XCInstallToolbarAppearance(void);

NS_ASSUME_NONNULL_END
