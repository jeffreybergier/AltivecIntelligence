#import "KeyValueTableViewController.h"
#import "CrossPlatform.h"
#import <AICURLConnection.h>

@implementation KeyValueTableViewController

- (void)viewDidLoad;
{
  [super viewDidLoad];
  self.navigationItem.title = @"Linked Libraries";
  
  // Fetch versions from AICURLConnection
  _versions = [[NSDictionary alloc] initWithObjectsAndKeys:
    [AICURLConnection zlibVersion], @"libz",
    [AICURLConnection sslVersion], @"libssl",
    [AICURLConnection curlVersion], @"libcurl",
    [AICURLConnection cryptoVersion], @"libcrypto",
    nil];
  
  _sortedKeys = [[[_versions allKeys] sortedArrayUsingSelector:@selector(compare:)] 
                 retain];
}

- (void)dealloc;
{
  [_versions release];
  [_sortedKeys release];
  [super dealloc];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView;
{
  return 1;
}

- (NSInteger)tableView:(UITableView *)tableView 
    numberOfRowsInSection:(NSInteger)section;
{
  return [_sortedKeys count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView 
         cellForRowAtIndexPath:(NSIndexPath *)indexPath;
{
  static NSString *CellIdentifier = @"InfoCell";
  UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
  if (cell == nil) {
    cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 
                                   reuseIdentifier:CellIdentifier] autorelease];
  }
  
  NSString *key = [_sortedKeys objectAtIndex:indexPath.row];
  cell.textLabel.text = key;
  cell.detailTextLabel.text = [_versions objectForKey:key];
  
  return cell;
}

@end
