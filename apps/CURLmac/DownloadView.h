#import <Cocoa/Cocoa.h>
#import "CrossPlatform.h"

@class DownloadManager;

// A view containing a URL entry field, a download button, a progress 
// indicator, and an image well to display the results.
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
