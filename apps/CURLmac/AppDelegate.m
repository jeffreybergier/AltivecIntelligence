#import "AppDelegate.h"
#import "DownloadWindowController.h"
#import "MainMenu.h"

@implementation AppDelegate

-(void)applicationWillFinishLaunching:(NSNotification*)aNotification;
{
  [MainMenu setupMenu];
}

-(void)applicationDidFinishLaunching:(NSNotification*)aNotification;
{
  _windowController = [[DownloadWindowController alloc] init];
  [_windowController showWindow:self];
}

-(BOOL)applicationOpenUntitledFile:(NSApplication*)sender;
{
  return NO;
}

-(void)dealloc;
{
  [_windowController release];
  [super dealloc];
}
@end
