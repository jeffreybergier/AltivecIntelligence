#import "DownloadManager.h"
#import "DownloadView.h"
#import <AICURLConnection.h>

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

#pragma mark - Actions

- (BOOL)acceptsFirstResponder; { return YES; }

- (void)downloadButtonClicked:(id)sender;
{
  NSLog(@"[DownloadManager downloadButtonClicked:] class: %@", 
        NSStringFromClass(connectionClass_));
        
  NSString *urlStr = [[view_ urlField] stringValue];
  NSURL *url = [NSURL URLWithString:urlStr];
  
  if (!url) {
    [self updateStatus:@"Error: Invalid URL"];
    return;
  }

  [[view_ downloadButton] setEnabled:NO];
  [[view_ progressIndicator] startAnimation:nil];
  [[view_ imageView] setImage:nil];

  [receivedData_ release];
  receivedData_ = [[NSMutableData alloc] init];

  NSURLRequest *request = [NSURLRequest requestWithURL:url];
  
  // Use the injected class directly
  [connectionClass_ connectionWithRequest:request delegate:self];
}

#pragma mark - Helpers

- (void)updateStatus:(NSString *)text;
{
  [[view_ statusLabel] setStringValue:text];
}

- (DownloadView *)view; { return view_; }
- (Class)connectionClass; { return connectionClass_; }

#pragma mark - NSURLConnectionDelegate

- (void)connection:(id)connection didReceiveResponse:(NSURLResponse *)response;
{
  if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
    NSInteger code = [(NSHTTPURLResponse *)response statusCode];
    NSString *msg = [AIHTTPURLResponse localizedStringForStatusCode:code];
    [self updateStatus:[NSString stringWithFormat:@"Response: %ld (%@)", 
                        (long)code, msg]];
    
    // Setup progress indicator if length is known
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
      [self connection:connection didFailWithError:
        [NSError errorWithDomain:@"AICDownloadErrorDomain" 
                            code:code 
                        userInfo:nil]];
    }
  }
}

- (void)connection:(id)connection didReceiveData:(NSData *)data;
{
  [receivedData_ appendData:data];
  
  if (![[view_ progressIndicator] isIndeterminate]) {
    [[view_ progressIndicator] incrementBy:(double)[data length]];
  }
  
  [self updateStatus:[NSString stringWithFormat:@"Receiving: %lu bytes...", 
                      (unsigned long)[receivedData_ length]]];
}

- (void)connection:(id)connection didFailWithError:(NSError *)error;
{
  NSLog(@"[DownloadManager connection:didFailWithError:] error: %@", error);
  [[view_ progressIndicator] stopAnimation:nil];
  [[view_ downloadButton] setEnabled:YES];
  
  NSString *msg = [NSString stringWithFormat:@"Failed: %@", 
                   [error localizedDescription]];
  [self updateStatus:msg];
  
  [self.nextResponder presentError:error];
}

- (void)connectionDidFinishLoading:(id)connection;
{
  NSLog(@"[DownloadManager connectionDidFinishLoading:] success!");
  [[view_ progressIndicator] stopAnimation:nil];
  [[view_ downloadButton] setEnabled:YES];
  
  [self updateStatus:[NSString stringWithFormat:@"Success! Total: %lu bytes", 
                      (unsigned long)[receivedData_ length]]];

  NSImage *image = [[NSImage alloc] initWithData:receivedData_];
  if (image) {
    [[view_ imageView] setImage:image];
    [image release];
  } else {
    [self updateStatus:@"Finished, but data is not a valid image."];
  }
}

@end
