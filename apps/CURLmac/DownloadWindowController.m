#import "DownloadWindowController.h"
#import "CrossPlatform.h"
#import <AICURLConnection.h>
#import "DownloadView.h"
#import "DownloadManager.h"
#import "KeyValueTableView.h"

@interface DownloadWindowController (Private)
@end

@implementation DownloadWindowController

- (id)init;
{
  return [super initWithWindowNibName:@"ignored"];
}

- (void)loadWindow;
{
  XPWindowStyleMask mask = XPWindowStyleMaskTitled 
                         | XPWindowStyleMaskMiniaturizable
                         | XPWindowStyleMaskResizable;
  
  NSWindow *window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 600)
                                                  styleMask:mask
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO] autorelease];
  [window setTitle:@"CURLmac Downloader"];
  [window setReleasedWhenClosed:NO];
  [window setMinSize:NSMakeSize(800, 600)];
  [window center];
  [self setWindow:window];
}

- (void)windowDidLoad;
{
  [super windowDidLoad];

  NSWindow *window = [self window];
  NSView *contentView = [window contentView];
  
  CGFloat width = [contentView bounds].size.width;
  CGFloat height = [contentView bounds].size.height;
  CGFloat padding = 8;

  // Tab View
  NSTabView *tabView = [[NSTabView alloc] initWithFrame:NSMakeRect(padding, 
                                                                   padding, 
                                                                   width - (padding * 2), 
                                                                   height - (padding * 2))];
  [tabView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  
  // --- Tab 0: CURL ---
  NSTabViewItem *curlItem = [[NSTabViewItem alloc] initWithIdentifier:@"CURL"];
  [curlItem setLabel:@"AICURLConnection"];
  curlView_ = [[DownloadView alloc] initWithFrame:[tabView contentRect]];
  [curlView_ setIdentifier:@"CURL"];
  
  // Setup Manager for CURL - Inject AICURLConnection class
  curlManager_ = [[DownloadManager alloc] initWithView:curlView_ 
                                       connectionClass:[AICURLConnection class]];
  [curlView_ setManager:curlManager_];
  
  [curlItem setView:curlView_];
  [tabView addTabViewItem:curlItem];
  [curlItem release];
  
  // --- Tab 1: System ---
  NSTabViewItem *systemItem = [[NSTabViewItem alloc] initWithIdentifier:@"System"];
  [systemItem setLabel:@"NSURLConnection"];
  systemView_ = [[DownloadView alloc] initWithFrame:[tabView contentRect]];
  [systemView_ setIdentifier:@"System"];
  
  // Setup Manager for System - Inject NSURLConnection class
  systemManager_ = [[DownloadManager alloc] initWithView:systemView_ 
                                          connectionClass:[NSURLConnection class]];
  [systemView_ setManager:systemManager_];
  
  [systemItem setView:systemView_];
  [tabView addTabViewItem:systemItem];
  [systemItem release];
  
  // --- Tab 2: Info ---
  NSTabViewItem *infoItem = [[NSTabViewItem alloc] initWithIdentifier:@"Info"];
  [infoItem setLabel:@"Libraries"];
  KeyValueTableView *infoView = [[KeyValueTableView alloc] initWithFrame:[tabView contentRect]];
  NSDictionary *versions = [NSDictionary dictionaryWithObjectsAndKeys:
    [AICURLConnection zlibVersion], @"libz",
    [AICURLConnection sslVersion], @"libssl",
    [AICURLConnection curlVersion], @"libcurl",
    [AICURLConnection cryptoVersion], @"libcrypto",
    nil];
  [infoView setData:versions];
  [infoItem setView:infoView];
  [tabView addTabViewItem:infoItem];
  [infoView release];
  [infoItem release];
  
  [contentView addSubview:tabView];
  [tabView release];
}

- (void)dealloc;
{
  [curlView_ release];
  [systemView_ release];
  [curlManager_ release];
  [systemManager_ release];
  [super dealloc];
}

@end
