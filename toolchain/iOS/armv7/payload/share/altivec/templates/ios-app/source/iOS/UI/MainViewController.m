#import "MainViewController.h"

// NSTextAlignmentCenter is marked iOS 6+, but center has ABI value 1 on iOS.
#define XPTextAlignmentCenter ((NSInteger)1)

@implementation MainViewController

- (void)viewDidLoad {
  UILabel *welcomeLabel;

  [super viewDidLoad];
  [[self view] setBackgroundColor:[UIColor whiteColor]];

  welcomeLabel = [[UILabel alloc] initWithFrame:[[self view] bounds]];
  [welcomeLabel setAutoresizingMask:(UIViewAutoresizingFlexibleWidth |
                                     UIViewAutoresizingFlexibleHeight)];
  [welcomeLabel setBackgroundColor:[UIColor clearColor]];
  [welcomeLabel setText:NSLocalizedString(@"Welcome", nil)];
  [welcomeLabel setTextAlignment:XPTextAlignmentCenter];
  [[self view] addSubview:welcomeLabel];
}

@end
