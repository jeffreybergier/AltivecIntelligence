#import "AppDelegate.h"

#import "UI/MainViewController.h"

@implementation AppDelegate

@synthesize window = window_;

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  UIWindow *window;
  MainViewController *controller;

  (void)application;
  (void)launchOptions;

  window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
  [self setWindow:window];

  controller = [[MainViewController alloc] init];
  [[self window] setRootViewController:controller];
  [[self window] makeKeyAndVisible];

  return YES;
}

@end
