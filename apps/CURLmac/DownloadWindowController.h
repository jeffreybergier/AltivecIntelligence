#import <AppKit/AppKit.h>

@interface DownloadWindowController : NSWindowController {
    NSTextField *_urlField;
    NSButton *_downloadButton;
    NSTextView *_statusView;
}

@end
