#import "DownloadViewController.h"
#import <AICURLConnection.h>
#import "CrossPlatform.h"

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
  _urlTextView = [[UITextView alloc] initWithFrame:CGRectZero];
  _urlTextView.text = @"https://platform.theverge.com/wp-content/uploads/sites/2/2026/03/Rank-Apple-Products-Lead-Art-1.jpg?quality=90&strip=all&crop=0%2C0%2C100%2C100&w=1440";
  _urlTextView.font = [UIFont systemFontOfSize:14];
  _urlTextView.backgroundColor = [UIColor clearColor];
  _urlTextView.keyboardType = UIKeyboardTypeURL;
  _urlTextView.autocapitalizationType = UITextAutocapitalizationTypeNone;
  _urlTextView.autocorrectionType = UITextAutocorrectionTypeNo;
  _urlTextView.delegate = self;
  _urlTextView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

  _downloadButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
  [_downloadButton setTitle:@"Download" forState:UIControlStateNormal];
  [_downloadButton addTarget:self action:@selector(downloadButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
  _downloadButton.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

  _progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
  _progressView.frame = CGRectMake(10, 32, self.view.bounds.size.width - 20, 9);
  _progressView.progress = 1.0;
  _progressView.autoresizingMask = UIViewAutoresizingFlexibleWidth;

  _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 8, self.view.bounds.size.width - 20, 16)];
  _statusLabel.text = @"Ready";
  _statusLabel.font = [UIFont systemFontOfSize:12];
  _statusLabel.backgroundColor = [UIColor clearColor];
  _statusLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;

  _resultImageView = [[UIImageView alloc] initWithFrame:CGRectMake(10, 10, self.view.bounds.size.width - 20, 200)];
  _resultImageView.contentMode = UIViewContentModeScaleAspectFit;
  _resultImageView.backgroundColor = [UIColor clearColor];
  _resultImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
}

- (void)dealloc;
{
  [_urlTextView release];
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
  [_urlTextView resignFirstResponder];
  
  NSURL *url = [NSURL URLWithString:_urlTextView.text];
  if (!url) {
    _statusLabel.text = @"Error: Invalid URL";
    return;
  }

  [_downloadButton setEnabled:NO];
  [_progressView XP_setProgress:0.0 animated:YES];
  _statusLabel.text = @"Starting...";
  _resultImageView.image = nil;

  [_receivedData release];
  _receivedData = [[NSMutableData alloc] init];

  NSURLRequest *request = [NSURLRequest requestWithURL:url];
  [_connectionClass connectionWithRequest:request delegate:self];
}

#pragma mark - Table View Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView; { return 3; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section;
{
  if (section == 0) return 1;
  if (section == 1) return 1;
  return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section;
{
  if (section == 0) return @"Transfer";
  if (section == 1) return @"";
  if (section == 2) return @"Result";
  return nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath;
{
  if (indexPath.section == 0) return 88;
  if (indexPath.section == 1) return 44;
  if (indexPath.section == 2 && indexPath.row == 0) return 52;
  if (indexPath.section == 2 && indexPath.row == 1) return 220;
  return 44;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath;
{
  NSString *CellIdentifier = [NSString stringWithFormat:@"Cell_%ld_%ld", (long)indexPath.section, (long)indexPath.row];
  UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
  
  if (cell == nil) {
    cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier] autorelease];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    
    if (indexPath.section == 0) {
      _urlTextView.frame = cell.contentView.bounds;
      [cell.contentView addSubview:_urlTextView];
    } else if (indexPath.section == 1) {
      cell.backgroundColor = [UIColor clearColor];
      cell.backgroundView = [[[UIView alloc] initWithFrame:CGRectZero] autorelease];
      _downloadButton.frame = cell.contentView.bounds;
      [cell.contentView addSubview:_downloadButton];
    } else if (indexPath.section == 2) {
      if (indexPath.row == 0) {
        [cell.contentView addSubview:_progressView];
        [cell.contentView addSubview:_statusLabel];
      } else if (indexPath.row == 1) {
        [cell.contentView addSubview:_resultImageView];
      }
    }
  }
  
  return cell;
}

#pragma mark - Table View Delegate

- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath;
{
  return NO;
}

#pragma mark - NSURLConnectionDelegate

- (void)connection:(id)connection didReceiveResponse:(NSURLResponse *)response;
{
  if (![response isKindOfClass:[NSHTTPURLResponse class]]) return;
  _expectedContentLength = [response expectedContentLength];
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
  if (_expectedContentLength > 0) {
    float progress = (float)[_receivedData length] / (float)_expectedContentLength;
    [_progressView XP_setProgress:progress animated:YES];
  }
  _statusLabel.text = [NSString stringWithFormat:@"Receiving: %@...", 
                       [NSString XP_stringFromByteCount:[_receivedData length]]];
}

- (void)connection:(id)connection didFailWithError:(NSError *)error;
{
  [_downloadButton setEnabled:YES];
  [_progressView XP_setProgress:1.0 animated:YES];
  _statusLabel.text = [NSString stringWithFormat:@"Failed: %@", [error localizedDescription]];
  UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Download Error" message:[error localizedDescription] delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
  [alert show];
  [alert release];
}

- (void)connectionDidFinishLoading:(id)connection;
{
  [_downloadButton setEnabled:YES];
  [_progressView XP_setProgress:1.0 animated:YES];
  _statusLabel.text = [NSString stringWithFormat:@"Success! %@", [NSString XP_stringFromByteCount:[_receivedData length]]];
  UIImage *image = [[UIImage alloc] initWithData:_receivedData];
  if (image) { _resultImageView.image = image; [image release]; }
}

#pragma mark - TextView Delegate

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text;
{
  if ([text isEqualToString:@"\n"]) {
    [textView resignFirstResponder];
    return NO;
  }
  return YES;
}

@end
