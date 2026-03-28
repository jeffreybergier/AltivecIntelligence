#import "DownloadWindowController.h"
#import "CrossPlatform.h"
#import <AICURLConnection.h>
#import "DownloadView.h"
#import "KeyValueTableView.h"

@interface DownloadWindowController (Private)
- (DownloadView *)currentView;
- (void)updateStatus:(NSString *)text;
@end

@implementation DownloadWindowController

- (id)init;
{
  return [super initWithWindowNibName:@"ignored"];
}

- (void)loadWindow;
{
  // 2. Create the window programmatically with defer:NO
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
  [window XP_setContentBorderThickness:24.0 forEdge:NSMinYEdge];
  [window XP_setAutorecalculatesContentBorderThickness:NO forEdge:NSMinYEdge];
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
  CGFloat statusBarHeight = 24;

  // 1. Status Bar
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

  // 2. Tab View
  NSTabView *tabView = [[NSTabView alloc] initWithFrame:NSMakeRect(padding, 
                                                                   statusBarHeight + 4, 
                                                                   width - (padding * 2), 
                                                                   height - statusBarHeight - padding - 4)];
  [tabView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  
  NSTabViewItem *curlItem = [[NSTabViewItem alloc] initWithIdentifier:@"CURL"];
  [curlItem setLabel:@"AICURLConnection"];
  curlView_ = [[DownloadView alloc] initWithFrame:[tabView contentRect]];
  [curlView_ setIdentifier:@"CURL"];
  [curlItem setView:curlView_];
  [tabView addTabViewItem:curlItem];
  [curlItem release];
  
  NSTabViewItem *systemItem = [[NSTabViewItem alloc] initWithIdentifier:@"System"];
  [systemItem setLabel:@"NSURLConnection"];
  systemView_ = [[DownloadView alloc] initWithFrame:[tabView contentRect]];
  [systemView_ setIdentifier:@"System"];
  [systemItem setView:systemView_];
  [tabView addTabViewItem:systemItem];
  [systemItem release];
  
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

- (DownloadView *)currentView;
{
  NSArray *subviews = [[[self window] contentView] subviews];
  unsigned int i;
  for (i = 0; i < [subviews count]; i++) {
    if ([[subviews objectAtIndex:i] isKindOfClass:[NSTabView class]]) {
      NSTabView *tabView = (NSTabView *)[subviews objectAtIndex:i];
      NSTabViewItem *item = [tabView selectedTabViewItem];
      return (DownloadView *)[item view];
    }
  }
  return curlView_; 
}

- (void)updateStatus:(NSString *)text;
{
  [statusLabel_ setStringValue:text];
}

- (void)downloadButtonClicked:(id)sender;
{
  NSButton *button = (NSButton *)sender;
  DownloadView *view = (DownloadView *)[button superview];
  NSString *identifier = [view identifier];
  NSString *urlStr = [[view urlField] stringValue];

  NSURL *url = [NSURL URLWithString:urlStr];
  if (!url) {
    [self updateStatus:@"Error: Invalid URL"];
    return;
  }

  [button setEnabled:NO];
  [progressIndicator_ startAnimation:nil];
  [self updateStatus:@""]; 
  [[view imageView] setImage:nil];

  [receivedData_ release];
  receivedData_ = [[NSMutableData alloc] init];

  NSURLRequest *request = [NSURLRequest requestWithURL:url];
  if ([identifier isEqualToString:@"CURL"]) {
    [[[AICURLConnection alloc] initWithRequest:request 
                                      delegate:self] autorelease];
  } else {
    [[[NSURLConnection alloc] initWithRequest:request 
                                     delegate:self] autorelease];
  }
}

#pragma mark - NSURLConnectionDelegate

- (void)connection:(id)connection didReceiveResponse:(NSURLResponse *)response;
{
  if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
    NSInteger code = [(NSHTTPURLResponse *)response statusCode];
    NSString *msg = [AIHTTPURLResponse localizedStringForStatusCode:code];
    [self updateStatus:[NSString stringWithFormat:@"Response: %ld (%@)", 
                        (long)code, msg]];
    
    if (code < 200 || code > 299) {
      [connection cancel];
      [self connection:connection didFailWithError:
        [NSError errorWithDomain:@"AICDownloadErrorDomain" code:code userInfo:nil]];
    }
  }
}

- (void)connection:(id)connection didReceiveData:(NSData *)data;
{
  [receivedData_ appendData:data];
  [self updateStatus:[NSString stringWithFormat:@"Receiving: %lu bytes...", 
                      (unsigned long)[receivedData_ length]]];
}

- (void)connection:(id)connection didFailWithError:(NSError *)error;
{
  [progressIndicator_ stopAnimation:nil];
  [[self currentView].downloadButton setEnabled:YES];
  
  NSString *msg = [NSString stringWithFormat:@"Failed: %@", [error localizedDescription]];
  [self updateStatus:msg];
  [self presentError:error modalForWindow:[self window] delegate:nil 
    didPresentSelector:NULL contextInfo:NULL];
}

- (void)connectionDidFinishLoading:(id)connection;
{
  [progressIndicator_ stopAnimation:nil];
  [[self currentView].downloadButton setEnabled:YES];
  
  [self updateStatus:[NSString stringWithFormat:@"Success! Total: %lu bytes", 
                      (unsigned long)[receivedData_ length]]];

  NSImage *image = [[NSImage alloc] initWithData:receivedData_];
  if (image) {
    [[self currentView].imageView setImage:image];
    [image release];
  } else {
    [self updateStatus:@"Finished, but data is not a valid image."];
  }
}

- (void)dealloc;
{
  [curlView_ release];
  [systemView_ release];
  [statusLabel_ release];
  [progressIndicator_ release];
  [receivedData_ release];
  [super dealloc];
}

@end
