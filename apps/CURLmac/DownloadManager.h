#import <Cocoa/Cocoa.h>

@class DownloadView;

// A manager that handles the download logic for a specific DownloadView.
// Inherits from NSResponder to sit in the responder chain and handle actions.
@interface DownloadManager : NSResponder {
 @private
  DownloadView *view_;
  NSMutableData *receivedData_;
  Class connectionClass_;
}

- (id)initWithView:(DownloadView *)view 
   connectionClass:(Class)connectionClass;

- (void)downloadButtonClicked:(id)sender;

- (DownloadView *)view;
- (Class)connectionClass;

@end
