#import <AppKit/AppKit.h>

/* --- Cross-Platform Compatibility Macros --- */

/* 10.6 Snow Leopard (Formal Protocols) */
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 1060
  #define XPApplicationDelegate   NSApplicationDelegate
  #define XPTableViewDataSource   NSTableViewDataSource
  #define XPTableViewDelegate     NSTableViewDelegate
#else
  @protocol XPApplicationDelegate @end
  @protocol XPTableViewDataSource @end
  @protocol XPTableViewDelegate   @end
#endif

/* 10.12 Sierra (Window Masks, Events, Text Alignment) */
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

/* 10.14 Mojave (Bezel and Progress Styles) */
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 101400
  #define XPBezelStyleRounded             NSBezelStyleRounded
  #define XPProgressIndicatorStyleBar     NSProgressIndicatorStyleBar
#else
  #define XPBezelStyleRounded             NSRoundedBezelStyle
  #define XPProgressIndicatorStyleBar     NSProgressIndicatorBarStyle
#endif

/* NSWindow category for Content Border (10.5+) */
@interface NSWindow (CrossPlatform)
- (void)XP_setContentBorderThickness:(float)thickness forEdge:(NSRectEdge)edge;
- (void)XP_setAutorecalculatesContentBorderThickness:(BOOL)flag forEdge:(NSRectEdge)edge;
@end

/* String Helpers for Human-Readable sizes */
@interface NSString (XPByteCount)
+ (NSString *)XP_stringFromByteCount:(long long)bytes;
@end

// --- Classes ---

@class DownloadManager;

// --- KeyValueTableView Interface ---
@interface KeyValueTableView : NSView <XPTableViewDataSource, XPTableViewDelegate> {
 @private
  NSScrollView *_scrollView;
  NSTableView *_tableView;
  NSDictionary *_data;
  NSArray *_sortedKeys;
}
- (void)setData:(NSDictionary *)data;
- (NSDictionary *)data;
@end

// --- DownloadView Interface ---
@interface DownloadView : NSView {
 @private
  NSTextField *urlField_;
  NSButton *downloadButton_;
  NSProgressIndicator *progressIndicator_;
  NSImageView *imageView_;
  NSTextField *statusLabel_;
  NSString *identifier_;
  DownloadManager *manager_;
}
- (NSTextField *)urlField;
- (NSButton *)downloadButton;
- (NSProgressIndicator *)progressIndicator;
- (NSImageView *)imageView;
- (NSTextField *)statusLabel;
- (NSString *)identifier;
- (void)setIdentifier:(NSString *)identifier;
- (DownloadManager *)manager;
- (void)setManager:(DownloadManager *)manager;
@end

// --- DownloadManager Interface ---
@interface DownloadManager : NSResponder {
 @private
  DownloadView *view_;
  NSMutableData *receivedData_;
  Class connectionClass_;
}
- (id)initWithView:(DownloadView *)view connectionClass:(Class)connectionClass;
- (void)downloadButtonClicked:(id)sender;
- (DownloadView *)view;
- (Class)connectionClass;
@end

// --- DownloadWindowController Interface ---
@interface DownloadWindowController : NSWindowController {
 @private
  DownloadView *curlView_;
  DownloadView *systemView_;
  DownloadManager *curlManager_;
  DownloadManager *systemManager_;
}
@end
