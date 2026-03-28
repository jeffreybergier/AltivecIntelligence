#import "MainMenu.h"
#import "CrossPlatform.h"

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
    NSMenuItem *appMenuItem = [mainMenu addItemWithTitle:@"" action:NULL keyEquivalent:@""];
    NSMenu *appMenu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
    [mainMenu setSubmenu:appMenu forItem:appMenuItem];
    
    // Apple Menu Hack for Tiger/Leopard compatibility
    if ([app respondsToSelector:@selector(setAppleMenu:)]) {
        [app performSelector:@selector(setAppleMenu:) withObject:appMenu];
    }
    
    [appMenu addItemWithTitle:@"About CURLmac" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    
    [appMenu addItemWithTitle:@"Hide CURLmac" action:@selector(hide:) keyEquivalent:@"h"];
    NSMenuItem *hideOthers = [appMenu addItemWithTitle:@"Hide Others" action:@selector(hideOtherApplications:) keyEquivalent:@"h"];
    [hideOthers setKeyEquivalentModifierMask:(XPEventModifierFlagCommand | XPEventModifierFlagOption)];
    [appMenu addItemWithTitle:@"Show All" action:@selector(unhideAllApplications:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    
    [appMenu addItemWithTitle:@"Quit CURLmac" action:@selector(terminate:) keyEquivalent:@"q"];
}

+ (void)buildEditMenu:(NSMenu *)mainMenu {
    NSMenuItem *editMenuItem = [mainMenu addItemWithTitle:@"Edit" action:NULL keyEquivalent:@""];
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
    NSMenuItem *windowMenuItem = [mainMenu addItemWithTitle:@"Window" action:NULL keyEquivalent:@""];
    NSMenu *windowMenu = [[[NSMenu alloc] initWithTitle:@"Window"] autorelease];
    [mainMenu setSubmenu:windowMenu forItem:windowMenuItem];
    [app setWindowsMenu:windowMenu];
    
    [windowMenu addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    [windowMenu addItemWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];
    [windowMenu addItem:[NSMenuItem separatorItem]];
    [windowMenu addItemWithTitle:@"Bring All to Front" action:@selector(arrangeInFront:) keyEquivalent:@""];
}

@end
