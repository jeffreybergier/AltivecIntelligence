//
//  main.m
//  CURLphone
//

#import <UIKit/UIKit.h>
#import "DownloadViewController.h"
#import "KeyValueTableViewController.h"

// --- AppDelegate Interface ---
@interface AppDelegate : UIResponder <UIApplicationDelegate> {
  UIWindow *_window;
  UITabBarController *_tabBarController;
}
@property (strong, nonatomic) UIWindow *window;
@end

// --- AppDelegate Implementation ---
@implementation AppDelegate

@synthesize window = _window;

- (BOOL)application:(UIApplication *)application 
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions;
{
  self.window = [[[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]] 
                 autorelease];
  
  // 1. CURL Tab (AICURLConnection)
  DownloadViewController *curlVC = [[[DownloadViewController alloc] 
    initWithConnectionClass:NSClassFromString(@"AICURLConnection")] autorelease];
  curlVC.title = @"CURL";
  UINavigationController *curlNav = [[[UINavigationController alloc] 
    initWithRootViewController:curlVC] autorelease];
  
  // 2. System Tab (NSURLConnection)
  DownloadViewController *systemVC = [[[DownloadViewController alloc] 
    initWithConnectionClass:[NSURLConnection class]] autorelease];
  systemVC.title = @"System";
  UINavigationController *systemNav = [[[UINavigationController alloc] 
    initWithRootViewController:systemVC] autorelease];
  
  // 3. Info Tab (Libraries)
  KeyValueTableViewController *infoVC = [[[KeyValueTableViewController alloc] 
    initWithStyle:UITableViewStyleGrouped] autorelease];
  infoVC.title = @"Libraries";
  UINavigationController *infoNav = [[[UINavigationController alloc] 
    initWithRootViewController:infoVC] autorelease];
  
  // Tab Bar Controller
  _tabBarController = [[UITabBarController alloc] init];
  _tabBarController.viewControllers = [NSArray arrayWithObjects:
                                       curlNav, systemNav, infoNav, nil];
  
  self.window.rootViewController = _tabBarController;
  [self.window makeKeyAndVisible];
  
  return YES;
}

- (void)dealloc;
{
  [_window release];
  [_tabBarController release];
  [super dealloc];
}

@end

// --- Main ---
int main(int argc, char * argv[]) {
  @autoreleasepool {
    return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
  }
}
