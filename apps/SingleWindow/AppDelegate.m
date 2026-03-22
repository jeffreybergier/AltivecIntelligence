//
//  AppDelegate.m
//  SingleWindow
//

#import "AppDelegate.h"

@interface RedView: NSView
@end

@implementation RedView
-(void)drawRect:(NSRect)dirtyRect;
{
  [[NSColor redColor] set];
  NSRectFill(dirtyRect);
  [super drawRect:dirtyRect];
}
@end

@implementation AppDelegate

-(void)applicationDidFinishLaunching:(NSNotification*)aNotification;
{
  NSLog(@"applicationDidFinishLaunching:");
}

-(BOOL)applicationOpenUntitledFile:(NSApplication*)sender;
{
  NSLog(@"applicationOpenUntitledFile:");
  [self replaceWindow];
  return YES;
}

-(void)replaceWindow;
{
  [_window release];
  _window = nil;
  
  unsigned int mask = XPWindowStyleMaskTitled
    | XPWindowStyleMaskClosable
    | XPWindowStyleMaskResizable
    | XPWindowStyleMaskMiniaturizable;
    
  NSRect contentRect = NSMakeRect(0,0,512,512);
  NSWindow *window = [[NSWindow alloc] initWithContentRect:contentRect
                                                 styleMask:mask
                                                   backing:NSBackingStoreBuffered
                                                     defer:YES];
  [window setReleasedWhenClosed:NO];
  [window setContentView:[[[RedView alloc] initWithFrame:contentRect] autorelease]];
  [window center];
  [window makeKeyAndOrderFront:self];
  _window = window;
}

-(void)dealloc;
{
  [_window release];
  [super dealloc];
}
@end
