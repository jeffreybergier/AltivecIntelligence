//
//  main.m
//  CURLphone
//

#import <UIKit/UIKit.h>
#import "DownloadViewController.h"
#import "KeyValueTableViewController.h"

// --- AppDelegate Interface ---
@interface AppDelegate : UIResponder <UIApplicationDelegate> {
 @private
  UIWindow *window_;
  UITabBarController *tabBarController_;
}
@property (strong, nonatomic) UIWindow *window;
@end

// --- AppDelegate Implementation ---
@implementation AppDelegate

@synthesize window = window_;

- (BOOL)application:(UIApplication *)application 
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  CGRect screenBounds = [[UIScreen mainScreen] bounds];
  [self setWindow:[[[UIWindow alloc] initWithFrame:screenBounds] autorelease]];
  
  // 1. CURL Tab (AICURLConnection)
  DownloadViewController *curlVC = [[[DownloadViewController alloc] 
    initWithConnectionClass:NSClassFromString(@"AICURLConnection")] autorelease];
  [curlVC setTitle:@"CURL"];
  UINavigationController *curlNav = [[[UINavigationController alloc] 
    initWithRootViewController:curlVC] autorelease];
  
  // 2. System Tab (NSURLConnection)
  DownloadViewController *systemVC = [[[DownloadViewController alloc] 
    initWithConnectionClass:[NSURLConnection class]] autorelease];
  [systemVC setTitle:@"System"];
  UINavigationController *systemNav = [[[UINavigationController alloc] 
    initWithRootViewController:systemVC] autorelease];
  
  // 3. Info Tab (Libraries)
  KeyValueTableViewController *infoVC = [[[KeyValueTableViewController alloc] 
    initWithStyle:UITableViewStyleGrouped] autorelease];
  [infoVC setTitle:@"Libraries"];
  UINavigationController *infoNav = [[[UINavigationController alloc] 
    initWithRootViewController:infoVC] autorelease];
  
  // Tab Bar Controller
  tabBarController_ = [[UITabBarController alloc] init];
  NSArray *vcs = [NSArray arrayWithObjects:curlNav, systemNav, infoNav, nil];
  [tabBarController_ setViewControllers:vcs];
  
  [[self window] setRootViewController:tabBarController_];
  [[self window] makeKeyAndVisible];
  
  return YES;
}

- (void)dealloc {
  [window_ release];
  [tabBarController_ release];
  [super dealloc];
}

@end

// --- Main ---
int main(int argc, char * argv[]) {
  @autoreleasepool {
    const char *appDelegateClass = [NSStringFromClass([AppDelegate class]) 
      UTF8String];
    return UIApplicationMain(argc, argv, nil, 
      [NSString stringWithUTF8String:appDelegateClass]);
  }
}
