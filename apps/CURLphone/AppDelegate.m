#import "AppDelegate.h"
#include <curl/curl.h>
#include <openssl/ssl.h>
#include <openssl/crypto.h>
#include <zlib.h>

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
  UIViewController *vc = [[UIViewController alloc] init];
  vc.view.backgroundColor = [UIColor whiteColor];
  vc.title = @"CURLphone";
  
  UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, 100, self.window.bounds.size.width - 40, 300)];
  label.numberOfLines = 0;
  label.font = [UIFont fontWithName:@"Courier" size:14.0f];
  label.textColor = [UIColor blackColor];
  
  NSString *curlVer = [NSString stringWithUTF8String:curl_version()];
  NSString *sslVer = [NSString stringWithUTF8String:OpenSSL_version(OPENSSL_VERSION)];
  NSString *cryptoVer = [NSString stringWithUTF8String:OpenSSL_version(OPENSSL_VERSION)]; // Usually same as SSL
  NSString *zlibVer = [NSString stringWithUTF8String:zlibVersion()];
  
  label.text = [NSString stringWithFormat:@"1. Curl:\n%@\n\n2. SSL:\n%@\n\n3. Crypto:\n%@\n\n4. Zlib:\n%@", 
                curlVer, sslVer, cryptoVer, zlibVer];
  
  [vc.view addSubview:label];
  
  UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
  nav.toolbarHidden = NO;
  
  self.window.rootViewController = nav;
  [self.window makeKeyAndVisible];
  return YES;
}

@end
