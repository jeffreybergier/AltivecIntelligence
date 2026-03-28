#import <AppKit/AppKit.h>

@class DownloadView;

// The main window controller for the CURLmac application.
// Manages the tabbed interface and coordinates downloads between 
// AICURLConnection and NSURLConnection.
// Features a persistent window-level status bar at the bottom.
@interface DownloadWindowController : NSWindowController {
 @private
  DownloadView *curlView_;
  DownloadView *systemView_;
  
  NSTextField *statusLabel_;
  NSProgressIndicator *progressIndicator_;
}

@end
