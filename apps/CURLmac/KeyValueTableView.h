#import <Cocoa/Cocoa.h>

#if MAC_OS_X_VERSION_MAX_ALLOWED >= 1060
@interface KeyValueTableView : NSView <NSTableViewDataSource, NSTableViewDelegate> {
#else
@interface KeyValueTableView : NSView {
#endif
  NSScrollView *_scrollView;
  NSTableView *_tableView;
  NSDictionary *_data;
  NSArray *_sortedKeys;
}

- (void)setData:(NSDictionary *)data;
- (NSDictionary *)data;

@end
