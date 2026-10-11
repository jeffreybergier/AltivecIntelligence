#import "XPAppKit.h"
#import "../shared/XPFoundation.h"
@interface MainWindow : NSWindowController
@end
@implementation MainWindow
- (id)init;
{
  return [super initWithWindowNibName:@"unused"];
}
- (void)loadWindow;
{
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 240)
    styleMask:XPWindowStyle backing:NSBackingStoreBuffered defer:NO];
  [window setReleasedWhenClosed:NO];
  [window setTitle:@"@ALTIVEC_APP_NAME@"];
  NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 100, 380, 40)];
  [label setStringValue:[XPModel welcome]];
  [label setEditable:NO]; [label setBordered:NO]; [label setDrawsBackground:NO];
  [[window contentView] addSubview:label];
  [label release];
  [window center]; [self setWindow:window]; [window release];
}
@end
@interface AppDelegate : NSObject <XPApplicationDelegate> { MainWindow *controller_; }
@end
@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)note;
{
  (void)note; controller_ = [[MainWindow alloc] init]; [controller_ showWindow:self];
  [NSApp activateIgnoringOtherApps:YES];
}
- (BOOL)applicationShouldHandleReopen:(NSApplication *)app hasVisibleWindows:(BOOL)visible;
{
  (void)app; (void)visible; [controller_ showWindow:self]; return YES;
}
- (void)dealloc;
{
  [controller_ release]; [super dealloc];
}
@end
int main(void) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSApplication *app = [NSApplication sharedApplication];
  AppDelegate *delegate = [[AppDelegate alloc] init];
  NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Main"];
  NSMenuItem *item = [menu addItemWithTitle:@"@ALTIVEC_APP_NAME@" action:NULL keyEquivalent:@""];
  NSMenu *submenu = [[NSMenu alloc] initWithTitle:@"@ALTIVEC_APP_NAME@"];
  [submenu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
  [menu setSubmenu:submenu forItem:item]; [app setMainMenu:menu];
  [submenu release]; [menu release]; [app setDelegate:delegate]; [app run];
  [app setDelegate:nil]; [delegate release]; [pool release]; return 0;
}
