#import <Cocoa/Cocoa.h>
#import "CrossPlatform.h"

// A view containing a URL entry field, a download button, a progress 
// indicator, and an image well to display the results.
// Targeted for 10.4+; uses manual accessors to avoid Obj-C 2.0 warnings.
@interface DownloadView : NSView {
 @private
  NSTextField *urlField_;
  NSButton *downloadButton_;
  NSProgressIndicator *progressIndicator_;
  NSImageView *imageView_;
  NSTextField *statusLabel_;
  NSString *identifier_;
}

- (NSTextField *)urlField;
- (NSTextField *)statusLabel;
- (NSButton *)downloadButton;
- (NSProgressIndicator *)progressIndicator;
- (NSImageView *)imageView;

- (NSString *)identifier;
- (void)setIdentifier:(NSString *)identifier;

@end
