//
//  main.m
//  Example
//
//  Created by Me on 3/12/26.
//  Copyright __MyCompanyName__ 2026. All rights reserved.
//

#import <AppKit/AppKit.h>

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

@interface AppDelegate: NSObject <NSApplicationDelegate>
{
  NSWindow *_window;
}
-(void)replaceWindow;
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
  int mask = NSTitledWindowMask
    | NSClosableWindowMask
    | NSResizableWindowMask
    | NSMiniaturizableWindowMask;
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

int main(int argc, char *argv[])
{
  // Instantiate
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSApplication *app = [NSApplication sharedApplication];
  AppDelegate *appDelegate = [[[AppDelegate alloc] init] autorelease];
  
  // Configure and Run
  [app setDelegate:appDelegate];
  [app run];
  
  // Close
  [pool release];
  return 0;
}
