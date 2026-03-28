#import <AppKit/AppKit.h>

@class DownloadView;

// The main window controller for the CURLmac application.
// Manages the tabbed interface and coordinates downloads between 
// AICURLConnection and NSURLConnection.
@interface DownloadWindowController : NSWindowController {
 @private
  DownloadView *curlView_;
  DownloadView *systemView_;
}

@end
