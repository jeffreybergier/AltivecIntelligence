//
//  AppDelegate.m
//  SingleWindow
//

#import "AppDelegate.h"

#pragma mark - MainMenu Implementation

@interface MainMenu (Private)
+ (void)buildAppMenu:(NSMenu *)mainMenu;
+ (void)buildEditMenu:(NSMenu *)mainMenu;
+ (void)buildWindowMenu:(NSMenu *)mainMenu;
@end

@implementation MainMenu

+ (void)setupMenu {
  NSApplication *app = [NSApplication sharedApplication];
  NSMenu *mainMenu = [[[NSMenu alloc] initWithTitle:@"MainMenu"] autorelease];
  
  [self buildAppMenu:mainMenu];
  [self buildEditMenu:mainMenu];
  [self buildWindowMenu:mainMenu];
  
  [app setMainMenu:mainMenu];
}

+ (void)buildAppMenu:(NSMenu *)mainMenu {
  NSApplication *app = [NSApplication sharedApplication];
  NSMenuItem *appMenuItem = [mainMenu addItemWithTitle:@"" 
                                                action:NULL 
                                         keyEquivalent:@""];
  NSMenu *appMenu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
  [mainMenu setSubmenu:appMenu forItem:appMenuItem];
  
  if ([app respondsToSelector:@selector(setAppleMenu:)]) {
    [app performSelector:@selector(setAppleMenu:) withObject:appMenu];
  }
  
  [appMenu addItemWithTitle:@"About SingleWindow" 
                     action:@selector(orderFrontStandardAboutPanel:) 
              keyEquivalent:@""];
  [appMenu addItem:[NSMenuItem separatorItem]];
  
  [appMenu addItemWithTitle:@"Hide SingleWindow" 
                     action:@selector(hide:) 
              keyEquivalent:@"h"];
  NSMenuItem *hideOthers = [appMenu addItemWithTitle:@"Hide Others" 
                                              action:@selector(hideOtherApplications:) 
                                       keyEquivalent:@"h"];
  [hideOthers setKeyEquivalentModifierMask:(XPEventModifierFlagCommand | 
                                             XPEventModifierFlagOption)];
  [appMenu addItemWithTitle:@"Show All" 
                     action:@selector(unhideAllApplications:) 
              keyEquivalent:@""];
  [appMenu addItem:[NSMenuItem separatorItem]];
  
  [appMenu addItemWithTitle:@"Quit SingleWindow" 
                     action:@selector(terminate:) 
              keyEquivalent:@"q"];
}

+ (void)buildEditMenu:(NSMenu *)mainMenu {
  NSMenuItem *editMenuItem = [mainMenu addItemWithTitle:@"Edit" 
                                                 action:NULL 
                                          keyEquivalent:@""];
  NSMenu *editMenu = [[[NSMenu alloc] initWithTitle:@"Edit"] autorelease];
  [mainMenu setSubmenu:editMenu forItem:editMenuItem];
  
  [editMenu addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
  [editMenu addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"Z"];
  [editMenu addItem:[NSMenuItem separatorItem]];
  [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
  [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
  [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
  [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
}

+ (void)buildWindowMenu:(NSMenu *)mainMenu {
  NSApplication *app = [NSApplication sharedApplication];
  NSMenuItem *windowMenuItem = [mainMenu addItemWithTitle:@"Window" 
                                                   action:NULL 
                                            keyEquivalent:@""];
  NSMenu *windowMenu = [[[NSMenu alloc] initWithTitle:@"Window"] autorelease];
  [mainMenu setSubmenu:windowMenu forItem:windowMenuItem];
  [app setWindowsMenu:windowMenu];
  
  [windowMenu addItemWithTitle:@"Minimize" 
                        action:@selector(performMiniaturize:) 
                 keyEquivalent:@"m"];
  [windowMenu addItemWithTitle:@"Zoom" 
                        action:@selector(performZoom:) 
                 keyEquivalent:@""];
  [windowMenu addItem:[NSMenuItem separatorItem]];
  [windowMenu addItemWithTitle:@"Bring All to Front" 
                        action:@selector(arrangeInFront:) 
                 keyEquivalent:@""];
}

@end

#pragma mark - AppDelegate Implementation

@implementation AppDelegate

- (void)applicationWillFinishLaunching:(NSNotification *)aNotification {
  [MainMenu setupMenu];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
  NSRect frame = NSMakeRect(0, 0, 400, 400);
  XPWindowStyleMask styleMask = XPWindowStyleMaskTitled 
                              | XPWindowStyleMaskMiniaturizable 
                              | XPWindowStyleMaskResizable;
  
  window_ = [[NSWindow alloc] initWithContentRect:frame
                                         styleMask:styleMask
                                           backing:NSBackingStoreBuffered
                                             defer:NO];
  
  [window_ setTitle:@"SingleWindow (Red)"];
  [window_ setBackgroundColor:[NSColor redColor]];
  [window_ center];
  [window_ makeKeyAndOrderFront:self];
}

- (void)dealloc {
  [window_ release];
  [super dealloc];
}

@end
