#import "DownloadWindowController.h"
#import "CrossPlatform.h"
#import <AICURLConnection.h>
#import "DownloadView.h"
#import "KeyValueTableView.h"

@interface DownloadWindowController (Private)
- (void)setupUI;
- (void)downloadButtonClicked:(id)sender;
@end

@implementation DownloadWindowController

- (id)init;
{
  unsigned int mask = XPWindowStyleMaskTitled 
                    | XPWindowStyleMaskClosable 
                    | XPWindowStyleMaskMiniaturizable 
                    | XPWindowStyleMaskResizable;
  
  NSWindow *window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 600)
                                                  styleMask:mask
                                                    backing:NSBackingStoreBuffered
                                                      defer:YES] autorelease];
  [window setTitle:@"CURLmac Downloader"];
  [window setReleasedWhenClosed:NO];
  [window setMinSize:NSMakeSize(800, 600)];
  [window XP_setContentBorderThickness:24.0 forEdge:NSMinYEdge];
  [window XP_setAutorecalculatesContentBorderThickness:NO forEdge:NSMinYEdge];
  
  if ((self = [super initWithWindow:window])) {
    [self setupUI];
  }
  return self;
}

- (void)setupUI;
{
  NSWindow *window = [self window];
  NSView *contentView = [window contentView];
  
  CGFloat width = [contentView bounds].size.width;
  CGFloat height = [contentView bounds].size.height;
  CGFloat padding = 8;
  CGFloat statusBarHeight = 24;

  // 1. Status Bar at the very bottom
  statusLabel_ = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, 
                                                                2, 
                                                                width - (padding * 2), 
                                                                20)];
  [statusLabel_ setStringValue:@"Ready"];
  [statusLabel_ setBezeled:NO];
  [statusLabel_ setDrawsBackground:NO];
  [statusLabel_ setEditable:NO];
  [statusLabel_ setSelectable:YES];
  [statusLabel_ setFont:[NSFont systemFontOfSize:11]];
  [statusLabel_ setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
  [contentView addSubview:statusLabel_];

  progressIndicator_ = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(padding, 
                                                                             2, 
                                                                             width - (padding * 2), 
                                                                             20)];
  [progressIndicator_ setStyle:XPProgressIndicatorStyleBar];
  [progressIndicator_ setIndeterminate:YES];
  [progressIndicator_ setDisplayedWhenStopped:NO];
  [progressIndicator_ setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
  [contentView addSubview:progressIndicator_];

  // 2. Tab View: Fills the rest, leaving room for status bar
  NSTabView *tabView = [[NSTabView alloc] initWithFrame:NSMakeRect(padding, 
                                                                   statusBarHeight + 4, 
                                                                   width - (padding * 2), 
                                                                   height - statusBarHeight - padding - 4)];
  [tabView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  
  // --- Tab 0: CURL ---
  NSTabViewItem *curlItem = [[NSTabViewItem alloc] initWithIdentifier:@"CURL"];
  [curlItem setLabel:@"AICURLConnection"];
  curlView_ = [[DownloadView alloc] initWithFrame:[tabView contentRect]];
  [curlView_ setIdentifier:@"CURL"];
  [curlItem setView:curlView_];
  [tabView addTabViewItem:curlItem];
  [curlItem release];
  
  // --- Tab 1: System ---
  NSTabViewItem *systemItem = [[NSTabViewItem alloc] initWithIdentifier:@"System"];
  [systemItem setLabel:@"NSURLConnection"];
  systemView_ = [[DownloadView alloc] initWithFrame:[tabView contentRect]];
  [systemView_ setIdentifier:@"System"];
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

- (void)downloadButtonClicked:(id)sender;
{
  NSButton *button = (NSButton *)sender;
  DownloadView *view = (DownloadView *)[button superview];
  NSString *identifier = [view identifier];
  NSString *urlStr = [[view urlField] stringValue];

  NSURL *url = [NSURL URLWithString:urlStr];
  if (!url) {
    [statusLabel_ setStringValue:@"Error: Invalid URL"];
    return;
  }

  [button setEnabled:NO];
  [progressIndicator_ startAnimation:nil];
  [statusLabel_ setStringValue:@""]; 
  [[view imageView] setImage:nil];

  NSURLRequest *request = [NSURLRequest requestWithURL:url];
  NSURLResponse *response = nil;
  NSError *error = nil;
  NSData *data = nil;

  if ([identifier isEqualToString:@"CURL"]) {
    data = [AICURLConnection sendSynchronousRequest:request 
                                  returningResponse:&response 
                                              error:&error];
  } else if ([identifier isEqualToString:@"System"]) {
    data = [NSURLConnection sendSynchronousRequest:request 
                                 returningResponse:&response 
                                             error:&error];
  }

  [progressIndicator_ stopAnimation:nil];
  [button setEnabled:YES];

  if (error) {
    [statusLabel_ setStringValue:[NSString stringWithFormat:@"Failed: %@", 
                                  [error localizedDescription]]];
    [self presentError:error 
        modalForWindow:[self window] 
              delegate:nil 
    didPresentSelector:NULL 
           contextInfo:NULL];
  } else if (data) {
    NSInteger statusCode = 0;
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
      statusCode = [(NSHTTPURLResponse *)response statusCode];
    }
    // Check for success status codes (200-299)
    if (statusCode < 200 || statusCode > 299) {
      NSString *statusText = [AIHTTPURLResponse localizedStringForStatusCode:statusCode];
      NSString *fullError = [NSString stringWithFormat:@"Failed: %ld (%@)", 
                             (long)statusCode, statusText];

      NSDictionary *userInfo = [NSDictionary dictionaryWithObject:fullError 
                                                           forKey:NSLocalizedDescriptionKey];
      NSError *statusError = [NSError errorWithDomain:@"AICDownloadErrorDomain" 
                                                 code:statusCode 
                                             userInfo:userInfo];

      [statusLabel_ setStringValue:fullError];
      [self presentError:statusError 
          modalForWindow:[self window] 
                delegate:nil 
      didPresentSelector:NULL 
             contextInfo:NULL];
      return;
    }
    NSString *statusText = [AIHTTPURLResponse localizedStringForStatusCode:statusCode];
    [statusLabel_ setStringValue:[NSString stringWithFormat:@"Status: %ld (%@) | Size: %lu bytes", 
                                  (long)statusCode, statusText, (unsigned long)[data length]]];

    NSImage *image = [[NSImage alloc] initWithData:data];
    if (image) {
      [[view imageView] setImage:image];
      [image release];
    } else {
      [statusLabel_ setStringValue:@"Data received is not a valid image."];
    }
  } else {
    [statusLabel_ setStringValue:@"Finished with no data."];
  }
}

- (void)dealloc;
{
  [curlView_ release];
  [systemView_ release];
  [statusLabel_ release];
  [progressIndicator_ release];
  [super dealloc];
}

@end
