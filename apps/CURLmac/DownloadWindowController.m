#import "DownloadWindowController.h"
#import "CrossPlatform.h"
#import <AICURLConnection.h>

@interface DownloadWindowController (Private)
- (void)setupUI;
- (NSBox *)versionBoxWithTitle:(NSString *)title version:(NSString *)version yOffset:(CGFloat)yOffset;
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
  NSView *curlView = [[NSView alloc] initWithFrame:[tabView contentRect]];
  
  // URL Field
  _urlField = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 230, 320, 24)];
  [[_urlField cell] setPlaceholderString:@"https://www.google.com"];
  [_urlField setStringValue:@"https://www.google.com"];
  [curlView addSubview:_urlField];
  
  // Download Button
  _downloadButton = [[NSButton alloc] initWithFrame:NSMakeRect(340, 225, 90, 32)];
  [_downloadButton setTitle:@"Download"];
  [_downloadButton setBezelStyle:XPBezelStyleRounded];
  [_downloadButton setTarget:self];
  [_downloadButton setAction:@selector(downloadClicked:)];
  [curlView addSubview:_downloadButton];
  
  // Status View
  NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(10, 10, 420, 205)];
  [scrollView setHasVerticalScroller:YES];
  [scrollView setBorderType:NSBezelBorder];
  [scrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  
  NSSize contentSize = [scrollView contentSize];
  _statusView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
  [_statusView setEditable:NO];
  [_statusView setAutoresizingMask:NSViewWidthSizable];
  
  [scrollView setDocumentView:_statusView];
  [curlView addSubview:scrollView];
  [scrollView release];
  
  [curlItem setView:curlView];
  [tabView addTabViewItem:curlItem];
  [curlView release];
  [curlItem release];
  
  // --- Tab 1: System ---
  NSTabViewItem *systemItem = [[NSTabViewItem alloc] initWithIdentifier:@"System"];
  [systemItem setLabel:@"System"];
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

- (void)downloadClicked:(id)sender {
  NSLog(@"[DownloadWindowController downloadClicked:] URL: %@", [_urlField stringValue]);
  [_statusView setString:@"Starting download...\n"];
}

- (void)dealloc {
  [_urlField release];
  [_downloadButton release];
  [_statusView release];
  [super dealloc];
}

@end
