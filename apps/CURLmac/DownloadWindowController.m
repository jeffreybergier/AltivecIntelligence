#import "DownloadWindowController.h"
#import "CrossPlatform.h"
#import <AICURLConnection.h>
#import "DownloadView.h"

@interface DownloadWindowController (Private)
- (void)setupUI;
- (NSBox *)versionBoxWithTitle:(NSString *)title version:(NSString *)version yOffset:(CGFloat)yOffset;
- (void)downloadButtonClicked:(id)sender;
@end

@implementation DownloadWindowController

- (id)init {
  unsigned int mask = XPWindowStyleMaskTitled 
                    | XPWindowStyleMaskClosable 
                    | XPWindowStyleMaskMiniaturizable 
                    | XPWindowStyleMaskResizable;
  
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 480, 320)
                                                 styleMask:mask
                                                   backing:NSBackingStoreBuffered
                                                     defer:YES];
  [window setTitle:@"CURLmac Downloader"];
  [window setReleasedWhenClosed:NO];
  
  self = [super initWithWindow:window];
  if (self) {
    [self setupUI];
  }
  [window release];
  return self;
}

- (void)setupUI {
  NSWindow *window = [self window];
  NSView *contentView = [window contentView];
  
  NSTabView *tabView = [[NSTabView alloc] initWithFrame:NSMakeRect(10, 10, 460, 300)];
  [tabView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  
  // --- Tab 0: CURL ---
  NSTabViewItem *curlItem = [[NSTabViewItem alloc] initWithIdentifier:@"CURL"];
  [curlItem setLabel:@"CURL"];
  _curlView = [[DownloadView alloc] initWithFrame:[tabView contentRect]];
  [_curlView setIdentifier:@"CURL"];
  [curlItem setView:_curlView];
  [tabView addTabViewItem:curlItem];
  [curlItem release];
  
  // --- Tab 1: System ---
  NSTabViewItem *systemItem = [[NSTabViewItem alloc] initWithIdentifier:@"System"];
  [systemItem setLabel:@"System"];
  _systemView = [[DownloadView alloc] initWithFrame:[tabView contentRect]];
  [_systemView setIdentifier:@"System"];
  [systemItem setView:_systemView];
  [tabView addTabViewItem:systemItem];
  [systemItem release];
  
  // --- Tab 2: Info ---
  NSTabViewItem *infoItem = [[NSTabViewItem alloc] initWithIdentifier:@"Info"];
  [infoItem setLabel:@"Info"];
  NSRect infoFrame = [tabView contentRect];
  NSView *infoView = [[NSView alloc] initWithFrame:infoFrame];
  [infoView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  
  CGFloat boxHeight = 60;
  CGFloat padding = 8;
  // Start from the top: height - padding - boxHeight
  CGFloat currentY = infoFrame.size.height - padding - boxHeight;
  
  [infoView addSubview:[self versionBoxWithTitle:@"libz" version:[AICURLConnection zlibVersion] yOffset:currentY]];
  currentY -= (boxHeight + padding);
  [infoView addSubview:[self versionBoxWithTitle:@"libssl" version:[AICURLConnection sslVersion] yOffset:currentY]];
  currentY -= (boxHeight + padding);
  [infoView addSubview:[self versionBoxWithTitle:@"libcurl" version:[AICURLConnection curlVersion] yOffset:currentY]];
  currentY -= (boxHeight + padding);
  [infoView addSubview:[self versionBoxWithTitle:@"libcrypto" version:[AICURLConnection cryptoVersion] yOffset:currentY]];
  
  [infoItem setView:infoView];
  [tabView addTabViewItem:infoItem];
  [infoView release];
  [infoItem release];
  
  [contentView addSubview:tabView];
  [tabView release];
}

- (NSBox *)versionBoxWithTitle:(NSString *)title version:(NSString *)version yOffset:(CGFloat)yOffset {
  // NSViewMinYMargin keeps the box top-aligned
  NSBox *box = [[NSBox alloc] initWithFrame:NSMakeRect(8, yOffset, 424, 60)];
  [box setTitle:title];
  [box setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
  
  // Lower the label (y=4) to move it further from the title
  NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 4, 400, 24)];
  [label setStringValue:version];
  [label setBezeled:NO];
  [label setDrawsBackground:NO];
  [label setEditable:NO];
  [label setSelectable:YES];
  [label setAutoresizingMask:NSViewWidthSizable];
  
  [[box contentView] addSubview:label];
  [label release];
  
  return [box autorelease];
}

- (void)downloadButtonClicked:(id)sender {
  NSButton *button = (NSButton *)sender;
  DownloadView *view = (DownloadView *)[button superview];
  NSString *identifier = [view identifier];
  NSString *urlStr = [[view urlField] stringValue];
  NSTextView *status = [view statusView];

  NSURL *url = [NSURL URLWithString:urlStr];
  if (!url) {
    [status setString:@"Error: Invalid URL\n"];
    return;
  }

  NSURLRequest *request = [NSURLRequest requestWithURL:url];
  NSURLResponse *response = nil;
  NSError *error = nil;
  NSData *data = nil;

  if ([identifier isEqualToString:@"CURL"]) {
    [status setString:[NSString stringWithFormat:@"Starting AIC (CURL) download: %@\n", urlStr]];
    data = [AICURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
  } else if ([identifier isEqualToString:@"System"]) {
    [status setString:[NSString stringWithFormat:@"Starting System (Cocoa) download: %@\n", urlStr]];
    data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
  }

  if (error) {
    [status setString:[NSString stringWithFormat:@"Download failed!\nError: %@\n", [error localizedDescription]]];
  } else if (data) {
    long statusCode = 0;
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
      statusCode = [(NSHTTPURLResponse *)response statusCode];
    }
    
    NSString *result = [NSString stringWithFormat:@"Download successful!\nStatus Code: %ld\nData received: %lu bytes\n", 
                        statusCode, (unsigned long)[data length]];
    [status setString:result];

    // Populate the well (Image View)
    NSImage *image = [[NSImage alloc] initWithData:data];
    if (image) {
      [[view imageView] setImage:image];
      [image release];
    } else {
      NSString *msg = @"Data received is not a valid image.\n";
      [[status textStorage] appendAttributedString:[[[NSAttributedString alloc] initWithString:msg] autorelease]];
    }
  } else {
    [status setString:@"Download finished with no data and no error.\n"];
  }
}

- (void)resetButtonClicked:(id)sender {
  NSButton *button = (NSButton *)sender;
  DownloadView *view = (DownloadView *)[button superview];
  [[view urlField] setStringValue:@""];
  [[view statusView] setString:@""];
  [[view imageView] setImage:nil];
  NSLog(@"[DownloadWindowController resetButtonClicked:] UI Reset");
}

- (void)dealloc {
  [_curlView release];
  [_systemView release];
  [super dealloc];
}

@end
