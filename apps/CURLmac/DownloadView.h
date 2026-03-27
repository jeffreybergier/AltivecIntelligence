#import <Cocoa/Cocoa.h>
#import "CrossPlatform.h"

@interface DownloadView : NSView {
  NSTextField *_urlField;
  NSButton *_downloadButton;
  NSButton *_resetButton;
  NSImageView *_imageView;
  NSTextView *_statusView;
  NSString *_identifier;
}

- (NSTextField *)urlField;
- (NSTextView *)statusView;
- (NSButton *)downloadButton;
- (NSButton *)resetButton;
- (NSImageView *)imageView;

- (NSString *)identifier;
- (void)setIdentifier:(NSString *)identifier;

@end
