#import <AppKit/AppKit.h>
#import "CrossPlatform.h"

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

- (id)initWithView:(DownloadView *)view 
   connectionClass:(Class)connectionClass;

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
