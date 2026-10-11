#import <AppKit/AppKit.h>
/* ABI values are available on Tiger; modern SDK spellings are not. */
#define XPWindowStyle ((NSUInteger)(1 | 2 | 4 | 8))
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 1060
#define XPApplicationDelegate NSApplicationDelegate
#else
@protocol XPApplicationDelegate
@end
#endif
