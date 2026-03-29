#import <UIKit/UIKit.h>

// A view controller that manages the download interface on iPhone.
// Uses a grouped UITableView to organize the URL input, action, progress, and result.
@interface DownloadViewController : UITableViewController <NSURLConnectionDelegate, UITextViewDelegate> {
 @private
  Class _connectionClass;
  NSMutableData *_receivedData;
  long long _expectedContentLength;
  
  // UI Components (Managed within the table)
  UITextView *_urlTextView;
  UIButton *_downloadButton;
  UIProgressView *_progressView;
  UILabel *_statusLabel;
  UIImageView *_resultImageView;
}

- (id)initWithConnectionClass:(Class)connectionClass;

@end
