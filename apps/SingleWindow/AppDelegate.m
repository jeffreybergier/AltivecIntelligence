//
//  AppDelegate.m
//  SingleWindow
//

#import "AppDelegate.h"
#import "DownloadWindowController.h"

@implementation AppDelegate

-(void)applicationDidFinishLaunching:(NSNotification*)aNotification;
{
  NSLog(@"applicationDidFinishLaunching:");
  if (!_windowController) {
    _windowController = [[DownloadWindowController alloc] init];
  }
  [[_windowController window] center];
  [_windowController showWindow:self];
}

-(BOOL)applicationOpenUntitledFile:(NSApplication*)sender;
{
  NSLog(@"applicationOpenUntitledFile:");
  return YES;
}

-(void)dealloc;
{
  [_windowController release];
  [super dealloc];
}
@end
