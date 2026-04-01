#import "DownloadWindowController.h"
#import <AICURLConnection.h>

#pragma mark - Cross-Platform Implementations

@implementation NSString (CrossPlatform)

+ (NSString *)XP_stringFromByteCount:(long long)bytes;
{
  if (bytes < 1024) return [NSString stringWithFormat:@"%lld B", bytes];
  double count = (double)bytes;
  NSArray *units = [NSArray arrayWithObjects:@"B", @"KB", @"MB", @"GB", nil];
  int i = 0;
  while (count >= 1024 && i < [units count] - 1) {
    count /= 1024.0;
    i++;
  }
  return [NSString stringWithFormat:@"%.2f %@", count, [units objectAtIndex:i]];
}

@end

#pragma mark - KeyValueTableView Implementation

@implementation KeyValueTableView

- (id)initWithFrame:(NSRect)frame;
{
  if ((self = [super initWithFrame:frame])) {
    [self setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    scrollView_ = [[NSScrollView alloc] initWithFrame:[self bounds]];
    [scrollView_ setHasVerticalScroller:YES];
    [scrollView_ setHasHorizontalScroller:YES];
    [scrollView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [scrollView_ setBorderType:NSBezelBorder];
    
    tableView_ = [[NSTableView alloc] 
      initWithFrame:[[scrollView_ contentView] bounds]];
    
    NSTableColumn *keyCol = [[[NSTableColumn alloc] initWithIdentifier:@"Key"] autorelease];
    [[keyCol headerCell] setStringValue:@"Key"];
    [keyCol setWidth:152.0];
    [tableView_ addTableColumn:keyCol];

    NSTableColumn *valCol = [[[NSTableColumn alloc] initWithIdentifier:@"Value"] autorelease];
    [[valCol headerCell] setStringValue:@"Value"];
    [valCol setWidth:252.0];
    [tableView_ addTableColumn:valCol];

    [tableView_ setDataSource:self];
    [tableView_ setDelegate:self];
    [tableView_ setUsesAlternatingRowBackgroundColors:YES];
    [tableView_ setAutoresizingMask:NSViewWidthSizable];

    [scrollView_ setDocumentView:tableView_];
    [self addSubview:scrollView_];
  }
  return self;
}

- (void)setData:(NSDictionary *)data;
{
  [data_ autorelease];
  data_ = [data retain];
  [sortedKeys_ autorelease];
  sortedKeys_ = [[[data_ allKeys] 
    sortedArrayUsingSelector:@selector(compare:)] retain];
  [tableView_ reloadData];
}

- (NSDictionary *)data { return data_; }

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView;
{ 
  return (NSInteger)[sortedKeys_ count]; 
}

- (id)tableView:(NSTableView *)tableView 
    objectValueForTableColumn:(NSTableColumn *)tableColumn 
                          row:(NSInteger)row;
{
  NSString *key = [sortedKeys_ objectAtIndex:row];
  if ([[tableColumn identifier] isEqualToString:@"Key"]) return key;
  return [data_ objectForKey:key];
}

- (void)dealloc;
{
  [scrollView_ release];
  [tableView_ release];
  [data_ release];
  [sortedKeys_ release];
  [super dealloc];
}

@end

#pragma mark - DownloadViewController Implementation

@implementation DownloadViewController

- (id)initWithConnectionClass:(Class)connectionClass frame:(NSRect)frame;
{
  if ((self = [super init])) {
    connectionClass_ = connectionClass;
    
    // Create container view
    view_ = [[NSView alloc] initWithFrame:frame];
    [view_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    
    CGFloat height = frame.size.height;
    CGFloat width = frame.size.width;
    CGFloat padding = 8;
    
    urlField_ = [[NSTextField alloc] 
      initWithFrame:NSMakeRect(padding, height - 32, width - 110, 24)];
    [urlField_ setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [[urlField_ cell] setPlaceholderString:@"Enter URL here..."];
    [urlField_ setStringValue:@"https://platform.theverge.com/wp-content/"
                               "uploads/sites/2/2026/03/Rank-Apple-Products-"
                               "Lead-Art-1.jpg?quality=90&strip=all&crop=0%2C"
                               "0%2C100%2C100&w=1440"];
    [[urlField_ cell] setScrollable:YES];
    [view_ addSubview:urlField_];
    
    downloadButton_ = [[NSButton alloc] 
      initWithFrame:NSMakeRect(width - 98, height - 36, 90, 32)];
    [downloadButton_ setTitle:@"Download"];
    [downloadButton_ setBezelStyle:XPBezelStyleRounded];
    [downloadButton_ setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    [downloadButton_ setTarget:self];
    [downloadButton_ setAction:@selector(downloadButtonClicked:)];
    [view_ addSubview:downloadButton_];

    progressIndicator_ = [[NSProgressIndicator alloc] 
      initWithFrame:NSMakeRect(padding, height - 56, width - (padding * 2), 16)];
    [progressIndicator_ setStyle:XPProgressIndicatorStyleBar];
    [progressIndicator_ setIndeterminate:NO];
    [progressIndicator_ setMaxValue:1.0];
    [progressIndicator_ setDoubleValue:1.0];
    [progressIndicator_ setDisplayedWhenStopped:YES];
    [progressIndicator_ setAutoresizingMask:NSViewWidthSizable | 
                                            NSViewMinYMargin];
    [view_ addSubview:progressIndicator_];

    statusLabel_ = [[NSTextField alloc] 
      initWithFrame:NSMakeRect(padding, 4, width - (padding * 2), 16)];
    [statusLabel_ setStringValue:@"Ready"];
    [statusLabel_ setBezeled:NO];
    [statusLabel_ setDrawsBackground:NO];
    [statusLabel_ setEditable:NO];
    [statusLabel_ setSelectable:NO];
    [statusLabel_ setFont:[NSFont systemFontOfSize:11]];
    [statusLabel_ setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    [view_ addSubview:statusLabel_];

    imageView_ = [[NSImageView alloc] 
      initWithFrame:NSMakeRect(padding, 24, width - (padding * 2), height - 84)];
    [imageView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [imageView_ setImageFrameStyle:NSImageFrameGrayBezel];
    [imageView_ setImageScaling:NSImageScaleProportionallyUpOrDown];
    [view_ addSubview:imageView_];
  }
  return self;
}

- (void)dealloc;
{
  [view_ release];
  [urlField_ release];
  [downloadButton_ release];
  [progressIndicator_ release];
  [statusLabel_ release];
  [imageView_ release];
  [receivedData_ release];
  [super dealloc];
}

- (void)downloadButtonClicked:(id)sender;
{
  NSString *urlStr = [urlField_ stringValue];
  NSURL *url = [NSURL URLWithString:urlStr];
  if (!url) return;

  [downloadButton_ setEnabled:NO];
  [progressIndicator_ setDoubleValue:0.0];
  [imageView_ setImage:nil];

  [receivedData_ release];
  receivedData_ = [[NSMutableData alloc] init];

  NSURLRequest *request = [NSURLRequest requestWithURL:url];
  [connectionClass_ connectionWithRequest:request delegate:self];
}

- (NSView *)view { return view_; }

#pragma mark - NSURLConnectionDelegate

- (void)connection:(id)connection didReceiveResponse:(NSURLResponse *)response;
{
  if (![response isKindOfClass:[NSHTTPURLResponse class]]) return;
  NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
  NSInteger code = [httpResponse statusCode];
  long long length = [response expectedContentLength];
  
  if (length > 0) {
    [progressIndicator_ setIndeterminate:NO];
    [progressIndicator_ setMaxValue:(double)length];
    [progressIndicator_ setDoubleValue:0.0];
  } else {
    [progressIndicator_ setIndeterminate:YES];
  }

  if (code < 200 || code > 299) {
    [connection cancel];
    NSString *statusText = [AIHTTPURLResponse localizedStringForStatusCode:code];
    NSString *fullError = [NSString stringWithFormat:@"Failed: %ld (%@)", 
                           (long)code, statusText];
    NSDictionary *ui = [NSDictionary dictionaryWithObject:fullError 
                                                   forKey:NSLocalizedDescriptionKey];
    [self connection:connection didFailWithError:
      [NSError errorWithDomain:@"com.altivec" code:code userInfo:ui]];
  }
}

- (void)connection:(id)connection didReceiveData:(NSData *)data;
{
  [receivedData_ appendData:data];
  if (![progressIndicator_ isIndeterminate]) {
    [progressIndicator_ incrementBy:(double)[data length]];
  }
  NSString *size = [NSString XP_stringFromByteCount:[receivedData_ length]];
  [statusLabel_ setStringValue:[NSString stringWithFormat:@"Recv: %@", size]];
}

- (void)connection:(id)connection didFailWithError:(NSError *)error;
{
  [progressIndicator_ setIndeterminate:NO];
  [progressIndicator_ setMaxValue:1.0];
  [progressIndicator_ setDoubleValue:1.0];
  [downloadButton_ setEnabled:YES];
  [statusLabel_ setStringValue:[error localizedDescription]];
  [self presentError:error];
}

- (void)connectionDidFinishLoading:(id)connection;
{
  [progressIndicator_ setDoubleValue:[progressIndicator_ maxValue]];
  [downloadButton_ setEnabled:YES];
  NSImage *img = [[[NSImage alloc] initWithData:receivedData_] autorelease];
  if (img) { [imageView_ setImage:img]; }
}

@end

#pragma mark - DownloadWindowController Implementation

@implementation DownloadWindowController

- (id)init { return [super initWithWindowNibName:@"ignored"]; }

- (void)loadWindow;
{
  XPWindowStyleMask mask = XPWindowStyleMaskTitled 
                         | XPWindowStyleMaskMiniaturizable
                         | XPWindowStyleMaskResizable;
  NSWindow *window = [[[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 600)
                                                  styleMask:mask
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO] autorelease];
  [window setTitle:@"CURLmac"];
  [window setReleasedWhenClosed:NO];
  [window setMinSize:NSMakeSize(800, 600)];
  [window center];
  [self setWindow:window];
}

- (void)windowDidLoad;
{
  [super windowDidLoad];
  NSView *contentView = [[self window] contentView];
  NSRect tabFrame = NSInsetRect([contentView bounds], 8, 8);
  NSTabView *tabView = [[[NSTabView alloc] initWithFrame:tabFrame] autorelease];
  [tabView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  
  NSRect subFrame = [tabView contentRect];
  
  // CURL
  curlController_ = [[DownloadViewController alloc] 
    initWithConnectionClass:[AICURLConnection class] frame:subFrame];
  [curlController_ setNextResponder:self];
  NSTabViewItem *curlItem = [[[NSTabViewItem alloc] initWithIdentifier:@"C"] autorelease];
  [curlItem setLabel:@"CURL"];
  [curlItem setView:[curlController_ view]];
  [tabView addTabViewItem:curlItem];

  // System
  systemController_ = [[DownloadViewController alloc] 
    initWithConnectionClass:[NSURLConnection class] frame:subFrame];
  [systemController_ setNextResponder:self];
  NSTabViewItem *systemItem = [[[NSTabViewItem alloc] initWithIdentifier:@"S"] autorelease];
  [systemItem setLabel:@"System"];
  [systemItem setView:[systemController_ view]];
  [tabView addTabViewItem:systemItem];

  // Info
  NSTabViewItem *infoItem = [[[NSTabViewItem alloc] initWithIdentifier:@"I"] autorelease];
  [infoItem setLabel:@"Libraries"];
  KeyValueTableView *kv = [[[KeyValueTableView alloc] initWithFrame:subFrame] autorelease];
  NSDictionary *v = [NSDictionary dictionaryWithObjectsAndKeys:
    [AICURLConnection zlibVersion], @"libz",
    [AICURLConnection sslVersion], @"libssl",
    [AICURLConnection curlVersion], @"libcurl", nil];
  [kv setData:v];
  [infoItem setView:kv];
  [tabView addTabViewItem:infoItem];

  [contentView addSubview:tabView];
}

- (BOOL)presentError:(NSError *)error;
{
  [self presentError:error modalForWindow:[self window] delegate:nil 
    didPresentSelector:NULL contextInfo:NULL];
  return YES;
}

- (void)dealloc;
{
  [curlController_ release];
  [systemController_ release];
  [super dealloc];
}

@end
