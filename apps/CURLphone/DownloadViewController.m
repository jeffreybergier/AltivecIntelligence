#import "DownloadViewController.h"
#import <AICURLConnection.h>

#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 60000
  #define XPTextAlignmentCenter (NSInteger)NSTextAlignmentCenter
#else
  #define XPTextAlignmentCenter (NSInteger)UITextAlignmentCenter
#endif

@implementation DownloadViewController

- (id)initWithConnectionClass:(Class)connectionClass;
{
  if ((self = [super initWithStyle:UITableViewStyleGrouped])) {
    _connectionClass = connectionClass;
  }
  return self;
}

- (void)viewDidLoad;
{
  [super viewDidLoad];
  
  // Initialize UI Components
  _urlField = [[UITextField alloc] initWithFrame:CGRectMake(10, 10, self.view.bounds.size.width - 40, 24)];
  _urlField.placeholder = @"Enter URL here...";
  _urlField.text = @"https://platform.theverge.com/wp-content/uploads/sites/2/2026/03/Rank-Apple-Products-Lead-Art-1.jpg?quality=90&strip=all&crop=0%2C0%2C100%2C100&w=1440";
  _urlField.clearButtonMode = UITextFieldViewModeWhileEditing;
  _urlField.keyboardType = UIKeyboardTypeURL;
  _urlField.autocapitalizationType = UITextAutocapitalizationTypeNone;
  _urlField.delegate = self;
  _urlField.autoresizingMask = UIViewAutoresizingFlexibleWidth;

  _downloadButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
  [_downloadButton setTitle:@"Download" forState:UIControlStateNormal];
  [_downloadButton addTarget:self action:@selector(downloadButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
  _downloadButton.frame = CGRectMake(10, 7, self.view.bounds.size.width - 40, 30);
  _downloadButton.autoresizingMask = UIViewAutoresizingFlexibleWidth;

  _progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
  _progressView.frame = CGRectMake(10, 10, self.view.bounds.size.width - 40, 9);
  _progressView.progress = 1.0;
  _progressView.autoresizingMask = UIViewAutoresizingFlexibleWidth;

  _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 24, self.view.bounds.size.width - 40, 16)];
  _statusLabel.text = @"Ready";
  _statusLabel.font = [UIFont systemFontOfSize:12];
  _statusLabel.textAlignment = XPTextAlignmentCenter;
  _statusLabel.backgroundColor = [UIColor clearColor];
  _statusLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;

  _resultImageView = [[UIImageView alloc] initWithFrame:CGRectMake(10, 10, self.view.bounds.size.width - 40, 200)];
  _resultImageView.contentMode = UIViewContentModeScaleAspectFit;
  _resultImageView.backgroundColor = [UIColor lightGrayColor];
  _resultImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
}

- (void)dealloc;
{
  [_urlField release];
  [_downloadButton release];
  [_progressView release];
  [_statusLabel release];
  [_resultImageView release];
  [_receivedData release];
  [super dealloc];
}

#pragma mark - Actions

- (void)downloadButtonClicked:(id)sender;
{
  [_urlField resignFirstResponder];
  
  NSURL *url = [NSURL URLWithString:_urlField.text];
  if (!url) {
    _statusLabel.text = @"Error: Invalid URL";
    return;
  }

  [_downloadButton setEnabled:NO];
  _progressView.progress = 0.0;
  _statusLabel.text = @"Starting...";
  _resultImageView.image = nil;

  [_receivedData release];
  _receivedData = [[NSMutableData alloc] init];

  NSURLRequest *request = [NSURLRequest requestWithURL:url];
  [_connectionClass connectionWithRequest:request delegate:self];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView; { return 2; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section;
{
  if (section == 0) return 3; // 0: URL, 1: Button, 2: Progress
  return 1; // 0: Result Image
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section;
{
  if (section == 0) return @"Transfer";
  if (section == 1) return @"Result";
  return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath;
{
  if (indexPath.section == 0 && indexPath.row == 2) return 44; // Progress row needs room for label
  if (indexPath.section == 1) return 220; // Result image
  return 44;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
{
  static NSString *CellIdentifier = @"Cell";
  UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
  if (cell == nil) {
    cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier] autorelease];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
  }
  
  for (UIView *subview in cell.contentView.subviews) [subview removeFromSuperview];

  if (indexPath.section == 0) {
    if (indexPath.row == 0) [cell.contentView addSubview:_urlField];
    else if (indexPath.row == 1) [cell.contentView addSubview:_downloadButton];
    else if (indexPath.row == 2) {
      [cell.contentView addSubview:_progressView];
      [cell.contentView addSubview:_statusLabel];
    }
  } else if (indexPath.section == 1) {
    [cell.contentView addSubview:_resultImageView];
  }
  
  return cell;
}

#pragma mark - NSURLConnectionDelegate

- (void)connection:(id)connection didReceiveResponse:(NSURLResponse *)response;
{
  if (![response isKindOfClass:[NSHTTPURLResponse class]]) return;
  
  NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
  NSInteger code = [httpResponse statusCode];
  _statusLabel.text = [NSString stringWithFormat:@"Response: %ld", (long)code];
  
  if (code < 200 || code > 299) {
    [connection cancel];
    [self connection:connection didFailWithError:[NSError errorWithDomain:@"com.altivecintelligence.example" code:code userInfo:nil]];
  }
}

- (void)connection:(id)connection didReceiveData:(NSData *)data;
{
  [_receivedData appendData:data];
  long long expected = [connection respondsToSelector:@selector(expectedContentLength)] ? [(id)connection expectedContentLength] : -1;
  
  if (expected > 0) {
    float progress = (float)[_receivedData length] / (float)expected;
    _progressView.progress = progress;
  }
  
  _statusLabel.text = [NSString stringWithFormat:@"Receiving: %lu bytes...", (unsigned long)[_receivedData length]];
}

- (void)connection:(id)connection didFailWithError:(NSError *)error;
{
  [_downloadButton setEnabled:YES];
  _progressView.progress = 1.0;
  _statusLabel.text = [NSString stringWithFormat:@"Failed: %@", [error localizedDescription]];
  
  UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Download Error" 
                                                  message:[error localizedDescription] 
                                                 delegate:nil 
                                        cancelButtonTitle:@"OK" 
                                        otherButtonTitles:nil];
  [alert show];
  [alert release];
}

- (void)connectionDidFinishLoading:(id)connection;
{
  [_downloadButton setEnabled:YES];
  _progressView.progress = 1.0;
  _statusLabel.text = [NSString stringWithFormat:@"Success! %lu bytes", (unsigned long)[_receivedData length]];
  
  UIImage *image = [[UIImage alloc] initWithData:_receivedData];
  if (image) {
    _resultImageView.image = image;
    [image release];
  }
}

#pragma mark - TextField Delegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField;
{
  [textField resignFirstResponder];
  return YES;
}

@end
