#import <AppKit/AppKit.h>

@class DownloadView;
@class DownloadManager;

// The main window controller for the CURLmac application.
// Manages the tabbed interface and coordinates downloads.
@interface DownloadWindowController : NSWindowController {
 @private
  DownloadView *curlView_;
  DownloadView *systemView_;
  
  DownloadManager *curlManager_;
  DownloadManager *systemManager_;
}

@end
