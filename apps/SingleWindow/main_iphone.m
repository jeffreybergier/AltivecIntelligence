#import <UIKit/UIKit.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
  UIViewController *vc = [[UIViewController alloc] init];
  vc.view.backgroundColor = [UIColor redColor];
  vc.title = @"SingleWindow-iOS";
  
  UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
  nav.toolbarHidden = NO;
  
  self.window.rootViewController = nav;
  [self.window makeKeyAndVisible];
  return YES;
}
@end

int main(int argc, char * argv[]) {
  @autoreleasepool {
    return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
  }
}
