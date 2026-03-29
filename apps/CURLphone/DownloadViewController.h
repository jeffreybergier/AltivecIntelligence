#import <UIKit/UIKit.h>

// A view controller that manages the download interface on iPhone.
// Named DownloadViewController to follow standard iOS naming conventions.
@interface DownloadViewController : UITableViewController <NSURLConnectionDelegate, UITextFieldDelegate> {
 @private
  Class _connectionClass;
  NSMutableData *_receivedData;
  
  // UI Components (Managed within the table)
  UITextField *_urlField;
  UIButton *_downloadButton;
  UIProgressView *_progressView;
  UILabel *_statusLabel;
  UIImageView *_resultImageView;
}

- (id)initWithConnectionClass:(Class)connectionClass;

@end
