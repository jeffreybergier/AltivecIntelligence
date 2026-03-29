#import "DownloadWindowController.h"
#import <AICURLConnection.h>

#pragma mark - Cross-Platform Implementations

@implementation NSWindow (CrossPlatform)

- (void)XP_setContentBorderThickness:(float)thickness forEdge:(NSRectEdge)edge;
{
  SEL selector = @selector(setContentBorderThickness:forEdge:);
  if ([self respondsToSelector:selector]) {
    typedef void (*MethodPtr)(id, SEL, float, NSRectEdge);
    MethodPtr method = (MethodPtr)[self methodForSelector:selector];
    method(self, selector, thickness, edge);
  }
}

- (void)XP_setAutorecalculatesContentBorderThickness:(BOOL)flag forEdge:(NSRectEdge)edge;
{
  SEL selector = @selector(setAutorecalculatesContentBorderThickness:forEdge:);
  if ([self respondsToSelector:selector]) {
    typedef void (*MethodPtr)(id, SEL, BOOL, NSRectEdge);
    MethodPtr method = (MethodPtr)[self methodForSelector:selector];
    method(self, selector, flag, edge);
  }
}

@end

@implementation NSString (XPByteCount)

+ (NSString *)XP_stringFromByteCount:(long long)bytes;
{
  if (bytes < 1024) return [NSString stringWithFormat:@"%lld B", bytes];
  double count = (double)bytes;
  NSArray *units = [NSArray arrayWithObjects:@"B", @"KB", @"MB", @"GB", @"TB", nil];
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

- (id)initWithFrame:(NSRect)frame {
  self = [super initWithFrame:frame];
  if (self) {
    [self setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    _scrollView = [[NSScrollView alloc] initWithFrame:[self bounds]];
    [_scrollView setHasVerticalScroller:YES];
    [_scrollView setHasHorizontalScroller:YES];
    [_scrollView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [_scrollView setBorderType:NSBezelBorder];
    _tableView = [[NSTableView alloc] initWithFrame:[[_scrollView contentView] bounds]];
    NSTableColumn *keyCol = [[NSTableColumn alloc] initWithIdentifier:@"Key"];
    [[keyCol headerCell] setStringValue:@"Key"];
    [keyCol setWidth:152.0];
    [keyCol setEditable:NO];
    [_tableView addTableColumn:keyCol];
    [keyCol release];
    NSTableColumn *valCol = [[NSTableColumn alloc] initWithIdentifier:@"Value"];
    [[valCol headerCell] setStringValue:@"Value"];
    [valCol setWidth:252.0];
    [valCol setEditable:NO];
    [valCol setResizingMask:NSTableColumnAutoresizingMask];
    [_tableView addTableColumn:valCol];
    [valCol release];
    [_tableView setDataSource:self];
    [_tableView setDelegate:self];
    [_tableView setUsesAlternatingRowBackgroundColors:YES];
    [_tableView setAutoresizingMask:NSViewWidthSizable];
    [_scrollView setDocumentView:_tableView];
    [self addSubview:_scrollView];
  }
  return self;
}

- (void)setData:(NSDictionary *)data {
  if (_data != data) {
    [_data release];
    _data = [data retain];
    [_sortedKeys release];
    _sortedKeys = [[[_data allKeys] sortedArrayUsingSelector:@selector(compare:)] retain];
    [_tableView reloadData];
  }
}

- (NSDictionary *)data { return _data; }

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return (NSInteger)[_sortedKeys count]; }

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
  NSString *key = [_sortedKeys objectAtIndex:row];
  if ([[tableColumn identifier] isEqualToString:@"Key"]) return key;
  return [_data objectForKey:key];
}

- (void)dealloc {
  [_scrollView release];
  [_tableView release];
  [_data release];
  [_sortedKeys release];
  [super dealloc];
}

@end

#pragma mark - DownloadView Implementation

@implementation DownloadView

- (id)initWithFrame:(NSRect)frame;
{
  if ((self = [super initWithFrame:frame])) {
    [self setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    CGFloat height = frame.size.height;
    CGFloat width = frame.size.width;
    CGFloat padding = 8;
    CGFloat buttonWidth = 90;
    urlField_ = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, height - 32, width - 110, 24)];
    [urlField_ setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [[urlField_ cell] setPlaceholderString:@"Enter URL here..."];
    [urlField_ setStringValue:@"https://platform.theverge.com/wp-content/uploads/sites/2/2026/03/Rank-Apple-Products-Lead-Art-1.jpg?quality=90&strip=all&crop=0%2C0%2C100%2C100&w=1440"];
    [[urlField_ cell] setScrollable:YES];
    [self addSubview:urlField_];
    downloadButton_ = [[NSButton alloc] initWithFrame:NSMakeRect(width - buttonWidth - padding, height - 36, buttonWidth, 32)];
    [downloadButton_ setTitle:@"Download"];
    [downloadButton_ setBezelStyle:XPBezelStyleRounded];
    [downloadButton_ setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    [downloadButton_ setTarget:self];
    [downloadButton_ setAction:@selector(downloadButtonClicked:)];
    [self addSubview:downloadButton_];
    progressIndicator_ = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(padding, height - 56, width - (padding * 2), 16)];
    [progressIndicator_ setStyle:XPProgressIndicatorStyleBar];
    [progressIndicator_ setIndeterminate:NO];
    [progressIndicator_ setMinValue:0.0];
    [progressIndicator_ setMaxValue:1.0];
    [progressIndicator_ setDoubleValue:1.0];
    [progressIndicator_ setDisplayedWhenStopped:YES];
    [progressIndicator_ setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [self addSubview:progressIndicator_];
    statusLabel_ = [[NSTextField alloc] initWithFrame:NSMakeRect(padding, 4, width - (padding * 2), 16)];
    [statusLabel_ setStringValue:@"Ready"];
    [statusLabel_ setBezeled:NO];
    [statusLabel_ setDrawsBackground:NO];
    [statusLabel_ setEditable:NO];
    [statusLabel_ setSelectable:NO];
    [statusLabel_ setFont:[NSFont systemFontOfSize:11]];
    [statusLabel_ setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    [self addSubview:statusLabel_];
    imageView_ = [[NSImageView alloc] initWithFrame:NSMakeRect(padding, 24, width - (padding * 2), height - 84)];
    [imageView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [imageView_ setImageFrameStyle:NSImageFrameGrayBezel];
    [imageView_ setImageScaling:NSImageScaleProportionallyUpOrDown];
    [self addSubview:imageView_];
  }
  return self;
}

- (void)dealloc;
{
  [urlField_ release];
  [downloadButton_ release];
  [progressIndicator_ release];
  [statusLabel_ release];
  [imageView_ release];
  [identifier_ release];
  [manager_ release];
  [super dealloc];
}

- (void)downloadButtonClicked:(id)sender { if (manager_) [manager_ downloadButtonClicked:sender]; }
- (NSTextField *)urlField { return urlField_; }
- (NSButton *)downloadButton { return downloadButton_; }
- (NSProgressIndicator *)progressIndicator { return progressIndicator_; }
- (NSImageView *)imageView { return imageView_; }
- (NSTextField *)statusLabel { return statusLabel_; }
- (NSString *)identifier { return identifier_; }
- (void)setIdentifier:(NSString *)i { [identifier_ autorelease]; identifier_ = [i copy]; }
- (DownloadManager *)manager { return manager_; }
- (void)setManager:(DownloadManager *)m { if (manager_ != m) { [manager_ release]; manager_ = [m retain]; } }

@end

#pragma mark - DownloadManager Implementation

@interface DownloadManager (Private)
- (void)updateStatus:(NSString *)text;
@end

@implementation DownloadManager

- (id)initWithView:(DownloadView *)view 
   connectionClass:(Class)connectionClass;
{
  if ((self = [super init])) {
    view_ = [view retain];
    connectionClass_ = connectionClass;
  }
  return self;
}

- (void)dealloc;
{
  [view_ release];
  [receivedData_ release];
  [super dealloc];
}

- (BOOL)acceptsFirstResponder; { return YES; }

- (void)downloadButtonClicked:(id)sender;
{
  NSLog(@"[DownloadManager downloadButtonClicked:] class: %@", NSStringFromClass(connectionClass_));
  NSString *urlStr = [[view_ urlField] stringValue];
  NSURL *url = [NSURL URLWithString:urlStr];
  if (!url) { [self updateStatus:@"Error: Invalid URL"]; return; }
  [[view_ downloadButton] setEnabled:NO];
  [[view_ progressIndicator] startAnimation:nil];
  [[view_ imageView] setImage:nil];
  [receivedData_ release];
  receivedData_ = [[NSMutableData alloc] init];
  NSURLRequest *request = [NSURLRequest requestWithURL:url];
  [connectionClass_ connectionWithRequest:request delegate:self];
}

- (void)updateStatus:(NSString *)text { [[view_ statusLabel] setStringValue:text]; }
- (DownloadView *)view { return view_; }
- (Class)connectionClass { return connectionClass_; }

- (void)connection:(id)connection didReceiveResponse:(NSURLResponse *)response;
{
  if (![response isKindOfClass:[NSHTTPURLResponse class]]) return;
  NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
  NSInteger code = [httpResponse statusCode];
  NSString *msg = [AIHTTPURLResponse localizedStringForStatusCode:code];
  [self updateStatus:[NSString stringWithFormat:@"Response: %ld (%@)", (long)code, msg]];
  long long length = [response expectedContentLength];
  if (length > 0) {
    [[view_ progressIndicator] setIndeterminate:NO];
    [[view_ progressIndicator] setMaxValue:(double)length];
    [[view_ progressIndicator] setDoubleValue:0.0];
  } else {
    [[view_ progressIndicator] setIndeterminate:YES];
  }
  if (code < 200 || code > 299) {
    [connection cancel];
    NSString *statusText = [AIHTTPURLResponse localizedStringForStatusCode:code];
    NSString *fullError = [NSString stringWithFormat:@"Failed: %ld (%@)", (long)code, statusText];
    NSDictionary *userInfo = [NSDictionary dictionaryWithObject:fullError forKey:NSLocalizedDescriptionKey];
    [self connection:connection didFailWithError:[NSError errorWithDomain:@"com.altivecintelligence.example" code:code userInfo:userInfo]];
  }
}

- (void)connection:(id)connection didReceiveData:(NSData *)data;
{
  [receivedData_ appendData:data];
  if (![[view_ progressIndicator] isIndeterminate]) {
    [[view_ progressIndicator] incrementBy:(double)[data length]];
  }
  NSString *received = [NSString XP_stringFromByteCount:[receivedData_ length]];
  if (![[view_ progressIndicator] isIndeterminate]) {
    long long expected = (long long)[[view_ progressIndicator] maxValue];
    NSString *total = [NSString XP_stringFromByteCount:expected];
    [self updateStatus:[NSString stringWithFormat:@"Receiving: %@ / %@", received, total]];
  } else {
    [self updateStatus:[NSString stringWithFormat:@"Receiving: %@...", received]];
  }
}

- (void)connection:(id)connection didFailWithError:(NSError *)error;
{
  NSLog(@"[DownloadManager connection:didFailWithError:] error: %@", error);
  [[view_ progressIndicator] stopAnimation:nil];
  [[view_ progressIndicator] setIndeterminate:NO];
  [[view_ progressIndicator] setMaxValue:1.0];
  [[view_ progressIndicator] setDoubleValue:1.0];
  [[view_ downloadButton] setEnabled:YES];
  [self updateStatus:[NSString stringWithFormat:@"Failed: %@", [error localizedDescription]]];
  [self.nextResponder presentError:error];
}

- (void)connectionDidFinishLoading:(id)connection;
{
  NSLog(@"[DownloadManager connectionDidFinishLoading:] success!");
  [[view_ progressIndicator] stopAnimation:nil];
  [[view_ downloadButton] setEnabled:YES];
  NSString *total = [NSString XP_stringFromByteCount:[receivedData_ length]];
  [self updateStatus:[NSString stringWithFormat:@"Success! Total: %@", total]];
  NSImage *image = [[NSImage alloc] initWithData:receivedData_];
  if (image) { [[view_ imageView] setImage:image]; [image release]; }
  else { [self updateStatus:@"Finished, but data is not a valid image."]; }
}

@end

#pragma mark - DownloadWindowController Implementation

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
  NSTabView *tabView = [[NSTabView alloc] initWithFrame:NSMakeRect(padding, padding, width - (padding * 2), height - (padding * 2))];
  [tabView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  NSTabViewItem *curlItem = [[NSTabViewItem alloc] initWithIdentifier:@"CURL"];
  [curlItem setLabel:@"AICURLConnection"];
  curlView_ = [[DownloadView alloc] initWithFrame:[tabView contentRect]];
  [curlView_ setIdentifier:@"CURL"];
  curlManager_ = [[DownloadManager alloc] initWithView:curlView_ connectionClass:[AICURLConnection class]];
  [curlView_ setManager:curlManager_];
  [curlManager_ setNextResponder:self];
  [curlItem setView:curlView_];
  [tabView addTabViewItem:curlItem];
  [curlItem release];
  NSTabViewItem *systemItem = [[NSTabViewItem alloc] initWithIdentifier:@"System"];
  [systemItem setLabel:@"NSURLConnection"];
  systemView_ = [[DownloadView alloc] initWithFrame:[tabView contentRect]];
  [systemView_ setIdentifier:@"System"];
  systemManager_ = [[DownloadManager alloc] initWithView:systemView_ connectionClass:[NSURLConnection class]];
  [systemView_ setManager:systemManager_];
  [systemManager_ setNextResponder:self];
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

- (BOOL)presentError:(NSError *)error;
{
  [self presentError:error modalForWindow:[self window] delegate:nil didPresentSelector:NULL contextInfo:NULL];
  return YES;
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
