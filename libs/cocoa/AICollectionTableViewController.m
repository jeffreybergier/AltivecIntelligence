#import "AICollectionTableViewController.h"
#if TARGET_OS_IPHONE
@implementation AICollectionTableViewController
- (AICollectionTableAdapter *)collectionTableAdapter;
{
  if (!collectionTableAdapter_)
    collectionTableAdapter_ = [[AICollectionTableAdapter alloc]
        initWithTableView:[self tableView]];
  return collectionTableAdapter_;
}
- (id)collectionIdentifierForSection:(NSInteger)section;
{ return [NSNumber numberWithInteger:section]; }
- (NSArray *)collectionIdentifiersForSection:(NSInteger)section;
{ (void)section; return nil; }
- (NSArray *)collectionFixedIdentifiersForSection:(NSInteger)section;
{
  NSInteger count = [self tableView:[self tableView]
      numberOfRowsInSection:section];
  if (count > (NSInteger)AICollectionIdentityLimit) return nil;
  NSMutableArray *identifiers = [NSMutableArray array];
  NSInteger row;
  for (row = 0; row < count; ++row)
    [identifiers addObject:[NSNumber numberWithInteger:row]];
  return identifiers;
}
- (NSArray *)collectionSections;
{
  UITableView *table = [self tableView];
  NSInteger count = [self numberOfSectionsInTableView:table], section;
  NSMutableArray *sections = [NSMutableArray array];
  for (section = 0; section < count; ++section) {
    NSMutableDictionary *metadata = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        [self collectionIdentifierForSection:section], @"id",
        [NSNumber numberWithInteger:[self tableView:table
            numberOfRowsInSection:section]], @"count", nil];
    NSString *header = [self respondsToSelector:@selector(tableView:titleForHeaderInSection:)] ?
        [self tableView:table titleForHeaderInSection:section] : nil;
    NSString *footer = [self respondsToSelector:@selector(tableView:titleForFooterInSection:)] ?
        [self tableView:table titleForFooterInSection:section] : nil;
    [metadata setObject:[NSArray arrayWithObjects:header ?: @"",footer ?: @"",nil] forKey:@"title"];
    NSArray *identifiers = [self collectionIdentifiersForSection:section];
    if (identifiers) [metadata setObject:identifiers forKey:@"identifiers"];
    [sections addObject:metadata];
  }
  return sections;
}
- (void)refreshCollection;
{
  AICollectionSnapshot *snapshot = [[AICollectionSnapshot alloc]
      initWithSections:[self collectionSections]];
  [[self collectionTableAdapter] applySnapshot:snapshot];
  [snapshot release];
}
- (void)viewWillAppear:(BOOL)animated;
{ [super viewWillAppear:animated]; [self refreshCollection]; }
- (void)viewDidUnload;
{
  [collectionTableAdapter_ invalidate];
  [collectionTableAdapter_ release]; collectionTableAdapter_ = nil;
  [super viewDidUnload];
}
- (void)dealloc;
{
  [collectionTableAdapter_ invalidate]; [collectionTableAdapter_ release];
  [super dealloc];
}
@end
#endif
