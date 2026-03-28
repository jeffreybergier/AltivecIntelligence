#import <Cocoa/Cocoa.h>
#import "CrossPlatform.h"

@interface DownloadView : NSView {
  NSTextField *_urlField;
  NSButton *_downloadButton;
  NSProgressIndicator *_progressIndicator;
  NSImageView *_imageView;
  NSTextField *_statusLabel;
  NSString *_identifier;
}

- (NSTextField *)urlField;
- (NSTextField *)statusLabel;
- (NSButton *)downloadButton;
- (NSProgressIndicator *)progressIndicator;
- (NSImageView *)imageView;

- (NSString *)identifier;
- (void)setIdentifier:(NSString *)identifier;

@end
