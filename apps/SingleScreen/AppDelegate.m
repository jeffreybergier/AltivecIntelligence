#import "AppDelegate.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
  UIViewController *vc = [[UIViewController alloc] init];
  vc.view.backgroundColor = [UIColor redColor];
  vc.title = @"SingleScreen-iOS";
  
  UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
  nav.toolbarHidden = NO;
  
  self.window.rootViewController = nav;
  [self.window makeKeyAndVisible];
  return YES;
}

@end
