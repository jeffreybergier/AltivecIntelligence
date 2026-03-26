//
//  AppDelegate.h
//  SingleWindow
//

#import <AppKit/AppKit.h>

/* Cross-Version Protocol Macros */
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 1060
  #define XPApplicationDelegate NSApplicationDelegate
#else
  @protocol XPApplicationDelegate @end
#endif

/* Cross-Version Window Mask Macros */
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 101200
  #define XPWindowStyleMaskTitled         NSWindowStyleMaskTitled
  #define XPWindowStyleMaskClosable       NSWindowStyleMaskClosable
  #define XPWindowStyleMaskResizable      NSWindowStyleMaskResizable
  #define XPWindowStyleMaskMiniaturizable NSWindowStyleMaskMiniaturizable
#else
  #define XPWindowStyleMaskTitled         NSTitledWindowMask
  #define XPWindowStyleMaskClosable       NSClosableWindowMask
  #define XPWindowStyleMaskResizable      NSResizableWindowMask
  #define XPWindowStyleMaskMiniaturizable NSMiniaturizableWindowMask
#endif

@interface AppDelegate : NSObject <XPApplicationDelegate>
{
  NSWindow *_window;
}
-(void)replaceWindow;
@end
