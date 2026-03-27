#import <AppKit/AppKit.h>

@class DownloadView;

@interface DownloadWindowController : NSWindowController {
    DownloadView *_curlView;
    DownloadView *_systemView;
}

@end
