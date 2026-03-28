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

- (id)init {
  unsigned int mask = XPWindowStyleMaskTitled 
                    | XPWindowStyleMaskClosable 
                    | XPWindowStyleMaskMiniaturizable 
                    | XPWindowStyleMaskResizable;
  
  NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 800, 600)
                                                 styleMask:mask
                                                   backing:NSBackingStoreBuffered
                                                     defer:YES];
  [window setTitle:@"CURLmac Downloader"];
  [window setReleasedWhenClosed:NO];
  [window setMinSize:NSMakeSize(800, 600)];
  
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
  
  NSTabView *tabView = [[NSTabView alloc] initWithFrame:NSMakeRect(8, 8, 784, 584)];
  [tabView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  
  // --- Tab 0: CURL ---
  NSTabViewItem *curlItem = [[NSTabViewItem alloc] initWithIdentifier:@"CURL"];
  [curlItem setLabel:@"AICURLConnection"];
  _curlView = [[DownloadView alloc] initWithFrame:[tabView contentRect]];
  [_curlView setIdentifier:@"CURL"];
  [curlItem setView:_curlView];
  [tabView addTabViewItem:curlItem];
  [curlItem release];
  
  // --- Tab 1: System ---
  NSTabViewItem *systemItem = [[NSTabViewItem alloc] initWithIdentifier:@"System"];
  [systemItem setLabel:@"NSURLConnection"];
  _systemView = [[DownloadView alloc] initWithFrame:[tabView contentRect]];
  [_systemView setIdentifier:@"System"];
  [systemItem setView:_systemView];
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

- (void)downloadButtonClicked:(id)sender {
  NSButton *button = (NSButton *)sender;
  DownloadView *view = (DownloadView *)[button superview];
  NSString *identifier = [view identifier];
  NSString *urlStr = [[view urlField] stringValue];
  NSTextField *status = [view statusLabel];
  NSProgressIndicator *progress = [view progressIndicator];

  NSURL *url = [NSURL URLWithString:urlStr];
  if (!url) {
    [status setStringValue:@"Error: Invalid URL"];
    return;
  }

  [button setEnabled:NO];
  [progress startAnimation:nil];
  [status setStringValue:@""]; // Clear text while progress bar is on top
  [[view imageView] setImage:nil]; // Clear old image data

  NSURLRequest *request = [NSURLRequest requestWithURL:url];
  NSURLResponse *response = nil;
  NSError *error = nil;
  NSData *data = nil;

  if ([identifier isEqualToString:@"CURL"]) {
    data = [AICURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
  } else if ([identifier isEqualToString:@"System"]) {
    data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&error];
  }

  [progress stopAnimation:nil];
  [button setEnabled:YES];

  if (error) {
    [status setStringValue:[NSString stringWithFormat:@"Failed: %@", [error localizedDescription]]];
    // Present error as a sheet
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
      NSString *errorMsg = [NSString stringWithFormat:@"Server returned status code: %ld", (long)statusCode];
      NSDictionary *userInfo = [NSDictionary dictionaryWithObject:errorMsg forKey:NSLocalizedDescriptionKey];
      NSError *statusError = [NSError errorWithDomain:@"AICDownloadErrorDomain" code:statusCode userInfo:userInfo];
      
      [status setStringValue:[NSString stringWithFormat:@"Failed: %ld", (long)statusCode]];
      [self presentError:statusError 
          modalForWindow:[self window] 
                delegate:nil 
      didPresentSelector:NULL 
             contextInfo:NULL];
      return;
    }

    [status setStringValue:[NSString stringWithFormat:@"Status: %ld | Size: %lu bytes", 
                            (long)statusCode, (unsigned long)[data length]]];

    // Populate the well (Image View)
    NSImage *image = [[NSImage alloc] initWithData:data];
    if (image) {
      [[view imageView] setImage:image];
      [image release];
    } else {
      [status setStringValue:@"Data received is not a valid image."];
    }
  } else {
    [status setStringValue:@"Finished with no data."];
  }
}

- (void)dealloc {
  [_curlView release];
  [_systemView release];
  [super dealloc];
}

@end
