#import "AppDelegate.h"

@implementation AppDelegate

@synthesize window = window_;

- (BOOL)application:(UIApplication *)application 
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  CGRect screenBounds = [[UIScreen mainScreen] bounds];
  [self setWindow:[[[UIWindow alloc] initWithFrame:screenBounds] autorelease]];
  
  UIViewController *vc = [[[UIViewController alloc] init] autorelease];
  [[vc view] setBackgroundColor:[UIColor redColor]];
  [vc setTitle:@"SingleScreen-iOS"];
  
  UINavigationController *nav = [[[UINavigationController alloc] 
    initWithRootViewController:vc] autorelease];
  [nav setToolbarHidden:NO];
  
  [[self window] setRootViewController:nav];
  [[self window] makeKeyAndVisible];
  
  return YES;
}

- (void)dealloc {
  [window_ release];
  [super dealloc];
}

@end
