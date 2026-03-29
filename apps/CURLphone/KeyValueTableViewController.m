#import "KeyValueTableViewController.h"
#import "CrossPlatform.h"
#import <AICURLConnection.h>

@implementation KeyValueTableViewController

- (void)viewDidLoad {
  [super viewDidLoad];
  [[self navigationItem] setTitle:@"Linked Libraries"];
  
  // Fetch versions from AICURLConnection
  versions_ = [[NSDictionary alloc] initWithObjectsAndKeys:
    [AICURLConnection zlibVersion], @"libz",
    [AICURLConnection sslVersion], @"libssl",
    [AICURLConnection curlVersion], @"libcurl",
    [AICURLConnection cryptoVersion], @"libcrypto",
    nil];
  
  sortedKeys_ = [[[versions_ allKeys] 
    sortedArrayUsingSelector:@selector(compare:)] retain];
}

- (void)dealloc {
  [versions_ release];
  [sortedKeys_ release];
  [super dealloc];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
  return 1;
}

- (NSInteger)tableView:(UITableView *)tableView 
    numberOfRowsInSection:(NSInteger)section {
  return [sortedKeys_ count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView 
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  static NSString *CellIdentifier = @"InfoCell";
  UITableViewCell *cell = [tableView 
    dequeueReusableCellWithIdentifier:CellIdentifier];
  if (cell == nil) {
    cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 
                                   reuseIdentifier:CellIdentifier] autorelease];
  }
  
  NSString *key = [sortedKeys_ objectAtIndex:[indexPath row]];
  [[cell textLabel] setText:key];
  [[cell detailTextLabel] setText:[versions_ objectForKey:key]];
  
  return cell;
}

@end
