#ifndef CROSS_PLATFORM_H
#define CROSS_PLATFORM_H

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

/* Cross-Version Bezel Style Macros */
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 101400
  #define XPBezelStyleRounded             NSBezelStyleRounded
#else
  #define XPBezelStyleRounded             NSRoundedBezelStyle
#endif

/* Cross-Version Progress Indicator Macros */
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 101400
  #define XPProgressIndicatorStyleBar     NSProgressIndicatorStyleBar
#else
  #define XPProgressIndicatorStyleBar     NSProgressIndicatorBarStyle
#endif

/* Cross-Version Event Modifier Macros */
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 101200
  #define XPEventModifierFlagCommand      NSEventModifierFlagCommand
  #define XPEventModifierFlagOption       NSEventModifierFlagOption
#else
  #define XPEventModifierFlagCommand      NSCommandKeyMask
  #define XPEventModifierFlagOption       NSAlternateKeyMask
#endif

/* Cross-Version NSWindow category for Content Border (10.5+) */
@interface NSWindow (CrossPlatform)
- (void)XP_setContentBorderThickness:(float)thickness forEdge:(NSRectEdge)edge;
- (void)XP_setAutorecalculatesContentBorderThickness:(BOOL)flag forEdge:(NSRectEdge)edge;
@end

#endif /* CROSS_PLATFORM_H */
