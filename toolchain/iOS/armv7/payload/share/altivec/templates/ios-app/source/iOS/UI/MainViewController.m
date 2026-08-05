#import "MainViewController.h"

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
  [welcomeLabel setTextAlignment:NSTextAlignmentCenter];
  [[self view] addSubview:welcomeLabel];
}

@end
