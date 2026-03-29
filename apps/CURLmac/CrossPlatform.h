#ifndef CROSS_PLATFORM_H
#define CROSS_PLATFORM_H

#import <AppKit/AppKit.h>

/* group by MacOS X version for cleaner consolidation */

/* --- 10.6 Snow Leopard (Formal Protocols) --- */
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 1060
  #define XPApplicationDelegate   NSApplicationDelegate
  #define XPTableViewDataSource   NSTableViewDataSource
  #define XPTableViewDelegate     NSTableViewDelegate
#else
  @protocol XPApplicationDelegate @end
  @protocol XPTableViewDataSource @end
  @protocol XPTableViewDelegate   @end
#endif

/* --- 10.12 Sierra (Window Masks, Events, Text Alignment) --- */
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 101200
  #define XPWindowStyleMask               NSWindowStyleMask
  #define XPWindowStyleMaskTitled         NSWindowStyleMaskTitled
  #define XPWindowStyleMaskClosable       NSWindowStyleMaskClosable
  #define XPWindowStyleMaskResizable      NSWindowStyleMaskResizable
  #define XPWindowStyleMaskMiniaturizable NSWindowStyleMaskMiniaturizable
  #define XPEventModifierFlagCommand      NSEventModifierFlagCommand
  #define XPEventModifierFlagOption       NSEventModifierFlagOption
  #define XPTextAlignmentCenter           NSTextAlignmentCenter
#else
  #define XPWindowStyleMask               NSUInteger
  #define XPWindowStyleMaskTitled         NSTitledWindowMask
  #define XPWindowStyleMaskClosable       NSClosableWindowMask
  #define XPWindowStyleMaskResizable      NSResizableWindowMask
  #define XPWindowStyleMaskMiniaturizable NSMiniaturizableWindowMask
  #define XPEventModifierFlagCommand      NSCommandKeyMask
  #define XPEventModifierFlagOption       NSAlternateKeyMask
  #define XPTextAlignmentCenter           NSCenterTextAlignment
#endif

/* --- 10.14 Mojave (Bezel and Progress Styles) --- */
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 101400
  #define XPBezelStyleRounded             NSBezelStyleRounded
  #define XPProgressIndicatorStyleBar     NSProgressIndicatorStyleBar
#else
  #define XPBezelStyleRounded             NSRoundedBezelStyle
  #define XPProgressIndicatorStyleBar     NSProgressIndicatorBarStyle
#endif

/* --- Cross-Version NSWindow category for Content Border (10.5+) --- */
@interface NSWindow (CrossPlatform)
- (void)XP_setContentBorderThickness:(float)thickness forEdge:(NSRectEdge)edge;
- (void)XP_setAutorecalculatesContentBorderThickness:(BOOL)flag forEdge:(NSRectEdge)edge;
@end

/* --- Cross-Version String Helpers --- */
@interface NSString (XPByteCount)
+ (NSString *)XP_stringFromByteCount:(long long)bytes;
@end

#endif /* CROSS_PLATFORM_H */
