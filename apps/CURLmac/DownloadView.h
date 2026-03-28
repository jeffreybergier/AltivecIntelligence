#import <Cocoa/Cocoa.h>
#import "CrossPlatform.h"

// A view containing a URL entry field, a download button, 
// and a large image well to display the results.
// Spacing is optimized for an even 8px margin.
@interface DownloadView : NSView {
 @private
  NSTextField *urlField_;
  NSButton *downloadButton_;
  NSImageView *imageView_;
  NSString *identifier_;
}

- (NSTextField *)urlField;
- (NSButton *)downloadButton;
- (NSImageView *)imageView;

- (NSString *)identifier;
- (void)setIdentifier:(NSString *)identifier;

@end
