#import "AppDelegate.h"
#import "DownloadWindowController.h"
#import "MainMenu.h"

@implementation AppDelegate

-(void)applicationDidFinishLaunching:(NSNotification*)aNotification;
{
  [MainMenu setupMenu];
  if (!_windowController) {
    _windowController = [[DownloadWindowController alloc] init];
  }
  [[_windowController window] center];
  [_windowController showWindow:self];
}

-(BOOL)applicationOpenUntitledFile:(NSApplication*)sender;
{
  if (!_windowController) {
    _windowController = [[DownloadWindowController alloc] init];
  }
  [_windowController showWindow:self];
  return YES;
}

-(void)dealloc;
{
  [_windowController release];
  [super dealloc];
}
@end
