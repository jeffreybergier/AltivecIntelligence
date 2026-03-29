#import <UIKit/UIKit.h>

// A table view controller that displays the versions of the linked 
// libraries (libcurl, openssl, etc.) in a grouped style.
@interface KeyValueTableViewController : UITableViewController {
 @private
  NSDictionary *versions_;
  NSArray *sortedKeys_;
}

@end
