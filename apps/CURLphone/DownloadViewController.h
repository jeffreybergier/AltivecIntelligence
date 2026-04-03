#import <UIKit/UIKit.h>

// A view controller that manages the download interface on iPhone.
// Uses a grouped UITableView to organize the URL input, action, progress, 
// and result.
@interface DownloadViewController : UITableViewController <NSURLConnectionDelegate, 
                                                           UITextViewDelegate> {
 @private
  Class connectionClass_;
  NSMutableData *receivedData_;
  long long expectedContentLength_;
  
  // UI Components (Managed within the table)
  UITextView *urlTextView_;
  UIButton *downloadButton_;
  UIProgressView *progressView_;
  UILabel *statusLabel_;
  UIImageView *resultImageView_;
}

- (id)initWithConnectionClass:(Class)connectionClass;

@end
