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
  
  NSString *zlibVer = [NSString stringWithUTF8String:zlibVersion()];
  NSString *sslVer = [NSString stringWithUTF8String:OpenSSL_version(OPENSSL_VERSION)];
  NSString *curlVer = [NSString stringWithUTF8String:curl_version()];
  NSString *cryptoVer = [NSString stringWithUTF8String:OpenSSL_version(OPENSSL_VERSION)]; // Usually same as SSL

  label.text = [NSString stringWithFormat:@"1. libz:\n%@\n\n2. libssl:\n%@\n\n3. libcurl:\n%@\n\n4. libcrypto:\n%@",
                zlibVer, sslVer, curlVer, cryptoVer];  
  [vc.view addSubview:label];
  
  UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
  nav.toolbarHidden = NO;
  
  self.window.rootViewController = nav;
  [self.window makeKeyAndVisible];
  return YES;
}

@end
