//
//  main.m
//  CURLphone
//

#import <UIKit/UIKit.h>
#import "DownloadViewController.h"
#import "CrossPlatform.h"
#import <AICURLConnection.h>

// --- KeyValueTableViewController Interface ---
// A table view controller that displays the versions of the linked 
// libraries (libcurl, openssl, etc.) in a grouped style.
@interface KeyValueTableViewController : UITableViewController {
 @private
  NSDictionary *versions_;
  NSArray *sortedKeys_;
}
@end

// --- KeyValueTableViewController Implementation ---
@implementation KeyValueTableViewController

- (void)viewDidLoad {
  [super viewDidLoad];
  [[self navigationItem] setTitle:@"Linked Libraries"];
  
  // Fetch versions from AICURLConnection
  versions_ = [[NSDictionary alloc] initWithObjectsAndKeys:
    [AICURLConnection zlibVersion], @"libz",
    [AICURLConnection sslVersion], @"libssl",
    [AICURLConnection curlVersion], @"libcurl",
    [AICURLConnection cryptoVersion], @"libcrypto",
    nil];
  
  sortedKeys_ = [[[versions_ allKeys] 
    sortedArrayUsingSelector:@selector(compare:)] retain];
}

- (void)dealloc {
  [versions_ release];
  [sortedKeys_ release];
  [super dealloc];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
  return 1;
}

- (NSInteger)tableView:(UITableView *)tableView 
    numberOfRowsInSection:(NSInteger)section {
  return [sortedKeys_ count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView 
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  static NSString *CellIdentifier = @"InfoCell";
  UITableViewCell *cell = [tableView 
    dequeueReusableCellWithIdentifier:CellIdentifier];
  if (cell == nil) {
    cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 
                                   reuseIdentifier:CellIdentifier] autorelease];
  }
  
  NSString *key = [sortedKeys_ objectAtIndex:[indexPath row]];
  [[cell textLabel] setText:key];
  [[cell detailTextLabel] setText:[versions_ objectForKey:key]];
  
  return cell;
}

@end

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
