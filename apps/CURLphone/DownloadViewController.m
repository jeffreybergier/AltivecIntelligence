#import "DownloadViewController.h"
#import <AICURLConnection.h>
#import "CrossPlatform.h"

@implementation DownloadViewController

- (id)initWithConnectionClass:(Class)connectionClass {
  if ((self = [super initWithStyle:UITableViewStyleGrouped])) {
    connectionClass_ = connectionClass;
  }
  return self;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  
  CGRect bounds = [[self view] bounds];
  
  // Initialize UI Components
  urlTextView_ = [[UITextView alloc] initWithFrame:CGRectZero];
  [urlTextView_ setText:@"https://platform.theverge.com/wp-content/uploads/"
                         "sites/2/2026/03/Rank-Apple-Products-Lead-Art-1.jpg?"
                         "quality=90&strip=all&crop=0%2C0%2C100%2C100&w=1440"];
  [urlTextView_ setFont:[UIFont systemFontOfSize:14]];
  [urlTextView_ setBackgroundColor:[UIColor clearColor]];
  [urlTextView_ setKeyboardType:UIKeyboardTypeURL];
  [urlTextView_ setAutocapitalizationType:UITextAutocapitalizationTypeNone];
  [urlTextView_ setAutocorrectionType:UITextAutocorrectionTypeNo];
  [urlTextView_ setDelegate:self];
  [urlTextView_ setAutoresizingMask:UIViewAutoresizingFlexibleWidth | 
                                    UIViewAutoresizingFlexibleHeight];

  downloadButton_ = [UIButton buttonWithType:UIButtonTypeRoundedRect];
  [downloadButton_ setTitle:@"Download" forState:UIControlStateNormal];
  [downloadButton_ addTarget:self 
                      action:@selector(downloadButtonClicked:) 
            forControlEvents:UIControlEventTouchUpInside];
  [downloadButton_ setAutoresizingMask:UIViewAutoresizingFlexibleWidth | 
                                        UIViewAutoresizingFlexibleHeight];

  progressView_ = [[UIProgressView alloc] 
    initWithProgressViewStyle:UIProgressViewStyleDefault];
  [progressView_ setFrame:CGRectMake(10, 32, bounds.size.width - 20, 9)];
  [progressView_ setProgress:1.0];
  [progressView_ setAutoresizingMask:UIViewAutoresizingFlexibleWidth];

  statusLabel_ = [[UILabel alloc] 
    initWithFrame:CGRectMake(10, 8, bounds.size.width - 20, 16)];
  [statusLabel_ setText:@"Ready"];
  [statusLabel_ setFont:[UIFont systemFontOfSize:12]];
  [statusLabel_ setBackgroundColor:[UIColor clearColor]];
  [statusLabel_ setAutoresizingMask:UIViewAutoresizingFlexibleWidth];

  resultImageView_ = [[UIImageView alloc] 
    initWithFrame:CGRectMake(10, 10, bounds.size.width - 20, 200)];
  [resultImageView_ setContentMode:UIViewContentModeScaleAspectFit];
  [resultImageView_ setBackgroundColor:[UIColor clearColor]];
  [resultImageView_ setAutoresizingMask:UIViewAutoresizingFlexibleWidth];
}

- (void)dealloc {
  [urlTextView_ release];
  [downloadButton_ release];
  [progressView_ release];
  [statusLabel_ release];
  [resultImageView_ release];
  [receivedData_ release];
  [super dealloc];
}

#pragma mark - Actions

- (void)downloadButtonClicked:(id)sender {
  [urlTextView_ resignFirstResponder];
  
  NSURL *url = [NSURL URLWithString:[urlTextView_ text]];
  if (!url) {
    [statusLabel_ setText:@"Error: Invalid URL"];
    return;
  }

  [downloadButton_ setEnabled:NO];
  [progressView_ XP_setProgress:0.0 animated:YES];
  [statusLabel_ setText:@"Starting..."];
  [resultImageView_ setImage:nil];

  [receivedData_ release];
  receivedData_ = [[NSMutableData alloc] init];

  NSURLRequest *request = [NSURLRequest requestWithURL:url];
  [connectionClass_ connectionWithRequest:request delegate:self];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { 
  return 3; 
}

- (NSInteger)tableView:(UITableView *)tableView 
    numberOfRowsInSection:(NSInteger)section {
  if (section == 0) return 1;
  if (section == 1) return 1;
  return 2;
}

- (NSString *)tableView:(UITableView *)tableView 
    titleForHeaderInSection:(NSInteger)section {
  if (section == 0) return @"Transfer";
  if (section == 1) return @"";
  if (section == 2) return @"Result";
  return nil;
}

- (CGFloat)tableView:(UITableView *)tableView 
    heightForRowAtIndexPath:(NSIndexPath *)indexPath {
  if ([indexPath section] == 0) return 88;
  if ([indexPath section] == 1) return 44;
  if ([indexPath section] == 2 && [indexPath row] == 0) return 52;
  if ([indexPath section] == 2 && [indexPath row] == 1) return 220;
  return 44;
}

- (UITableViewCell *)tableView:(UITableView *)tableView 
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  NSString *CellIdentifier = [NSString stringWithFormat:@"Cell_%ld_%ld", 
    (long)[indexPath section], (long)[indexPath row]];
  UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
  
  if (cell == nil) {
    cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault 
                                   reuseIdentifier:CellIdentifier] autorelease];
    [cell setSelectionStyle:UITableViewCellSelectionStyleNone];
    
    if ([indexPath section] == 0) {
      [urlTextView_ setFrame:[[cell contentView] bounds]];
      [[cell contentView] addSubview:urlTextView_];
    } else if ([indexPath section] == 1) {
      [cell setBackgroundColor:[UIColor clearColor]];
      UIView *bg = [[[UIView alloc] initWithFrame:CGRectZero] autorelease];
      [cell setBackgroundView:bg];
      [downloadButton_ setFrame:[[cell contentView] bounds]];
      [[cell contentView] addSubview:downloadButton_];
    } else if ([indexPath section] == 2) {
      if ([indexPath row] == 0) {
        [[cell contentView] addSubview:progressView_];
        [[cell contentView] addSubview:statusLabel_];
      } else if ([indexPath row] == 1) {
        [[cell contentView] addSubview:resultImageView_];
      }
    }
  }
  
  return cell;
}

#pragma mark - Table View Delegate

- (BOOL)tableView:(UITableView *)tableView 
    shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath {
  return NO;
}

#pragma mark - NSURLConnectionDelegate

- (void)connection:(id)connection didReceiveResponse:(NSURLResponse *)response {
  if (![response isKindOfClass:[NSHTTPURLResponse class]]) return;
  expectedContentLength_ = [response expectedContentLength];
  NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
  NSInteger code = [httpResponse statusCode];
  [statusLabel_ setText:[NSString stringWithFormat:@"Response: %ld", (long)code]];
  if (code < 200 || code > 299) {
    [connection cancel];
    [self connection:connection didFailWithError:
      [NSError errorWithDomain:@"com.altivecintelligence.example" 
                          code:code 
                      userInfo:nil]];
  }
}

- (void)connection:(id)connection didReceiveData:(NSData *)data {
  [receivedData_ appendData:data];
  if (expectedContentLength_ > 0) {
    float progress = (float)[receivedData_ length] / (float)expectedContentLength_;
    [progressView_ XP_setProgress:progress animated:YES];
  }
  NSString *sizeStr = [NSString XP_stringFromByteCount:[receivedData_ length]];
  [statusLabel_ setText:[NSString stringWithFormat:@"Receiving: %@...", sizeStr]];
}

- (void)connection:(id)connection didFailWithError:(NSError *)error {
  [downloadButton_ setEnabled:YES];
  [progressView_ XP_setProgress:1.0 animated:YES];
  [statusLabel_ setText:[NSString stringWithFormat:@"Failed: %@", 
    [error localizedDescription]]];
  UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Download Error" 
                                                  message:[error localizedDescription] 
                                                 delegate:nil 
                                        cancelButtonTitle:@"OK" 
                                        otherButtonTitles:nil];
  [alert show];
  [alert release];
}

- (void)connectionDidFinishLoading:(id)connection {
  [downloadButton_ setEnabled:YES];
  [progressView_ XP_setProgress:1.0 animated:YES];
  NSString *sizeStr = [NSString XP_stringFromByteCount:[receivedData_ length]];
  [statusLabel_ setText:[NSString stringWithFormat:@"Success! %@", sizeStr]];
  UIImage *image = [[UIImage alloc] initWithData:receivedData_];
  if (image) { [resultImageView_ setImage:image]; [image release]; }
}

#pragma mark - TextView Delegate

- (BOOL)textView:(UITextView *)textView 
    shouldChangeTextInRange:(NSRange)range 
            replacementText:(NSString *)text {
  if ([text isEqualToString:@"\n"]) {
    [textView resignFirstResponder];
    return NO;
  }
  return YES;
}

@end
