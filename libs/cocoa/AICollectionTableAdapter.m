#import "AICollectionTableAdapter.h"
#import "AIPagedRows.h"
#import <TargetConditionals.h>
#include <pthread.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
static BOOL AICollectionContainsFirstResponder(UIView *view)
{
  if ([view isFirstResponder]) return YES;
  NSEnumerator *enumerator = [[view subviews] objectEnumerator]; UIView *child;
  while ((child = [enumerator nextObject]))
    if (AICollectionContainsFirstResponder(child)) return YES;
  return NO;
}
#else
#import <AppKit/AppKit.h>
/* These signatures are ABI-compatible on legacy SDKs without naming newer
 * enum/framework symbols. Runtime dispatch is confined to this adapter. */
static void AITableVoid(id table, SEL selector)
{
  union { IMP generic; void (*typed)(id,SEL); } method;
  method.generic = [table methodForSelector:selector];
  method.typed(table,selector);
}
static void AITableIndexes(id table, SEL selector, NSIndexSet *indexes)
{
  union { IMP generic; void (*typed)(id,SEL,id,NSUInteger); } method;
  method.generic = [table methodForSelector:selector];
  method.typed(table,selector,indexes,0);
}
#endif
NSString * const AICollectionReadFailedNotification = @"AICollectionReadFailedNotification";
@implementation AICollectionTableAdapter
- (id)initWithTableView:(id)table;
{
  NSAssert(pthread_main_np(), @"Table adapters require main thread");
  self = [super init];
  if (self) {
    table_ = table; pendingRows_ = [[NSMutableSet alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(pageLoaded:) name:AIPagedRowsDidLoadNotification object:nil];
  }
  return self;
}
- (void)applyRowCount:(NSUInteger)count identifiers:(NSArray *)identifiers;
{
  NSMutableDictionary *section = [NSMutableDictionary dictionaryWithObjectsAndKeys:
      @"rows", @"id", [NSNumber numberWithUnsignedLong:count], @"count", nil];
  if (identifiers) [section setObject:identifiers forKey:@"identifiers"];
  AICollectionSnapshot *snapshot = [[AICollectionSnapshot alloc]
      initWithSections:[NSArray arrayWithObject:section]];
  [self applySnapshot:snapshot]; [snapshot release];
}
- (AICollectionSnapshot *)snapshot; { return snapshot_; }
- (NSArray *)visiblePaths;
{
#if TARGET_OS_IPHONE
  return [table_ indexPathsForVisibleRows];
#else
  NSMutableArray *paths = [NSMutableArray array];
  NSRange range = [table_ rowsInRect:[table_ visibleRect]];
  NSUInteger row;
  if (range.location != NSNotFound)
    for (row = range.location; row < NSMaxRange(range) && row < [snapshot_ count]; ++row) {
      NSIndexPath *path = [snapshot_ indexPathForRow:row];
      if (path) [paths addObject:path];
    }
  return paths;
#endif
}
- (NSArray *)selectedPaths;
{
#if TARGET_OS_IPHONE
  return [table_ indexPathsForSelectedRows];
#else
  NSMutableArray *paths = [NSMutableArray array];
  NSIndexSet *indexes = [table_ selectedRowIndexes];
  NSUInteger row = [indexes firstIndex];
  while (row != NSNotFound) {
    NSIndexPath *path = [snapshot_ indexPathForRow:row];
    if (path) [paths addObject:path];
    row = [indexes indexGreaterThanIndex:row];
  }
  return paths;
#endif
}
- (double)offsetFromPath:(NSIndexPath *)path;
{
#if TARGET_OS_IPHONE
  return [table_ contentOffset].y - [table_ rectForRowAtIndexPath:path].origin.y;
#else
  NSUInteger row = [snapshot_ rowForIndexPath:path];
  return [table_ visibleRect].origin.y - [table_ rectOfRow:(NSInteger)row].origin.y;
#endif
}
- (void)restoreAnchor:(NSIndexPath *)path delta:(double)delta;
{
#if TARGET_OS_IPHONE
  [table_ layoutIfNeeded];
  CGPoint point = [table_ contentOffset];
  point.y = [table_ rectForRowAtIndexPath:path].origin.y + delta;
  UIEdgeInsets inset = [table_ contentInset];
  CGFloat maximum = MAX(-inset.top,[table_ contentSize].height -
      [table_ bounds].size.height + inset.bottom);
  point.y = MAX(-inset.top,MIN(maximum,point.y));
  [table_ setContentOffset:point animated:NO];
#else
  NSClipView *clip = [[table_ enclosingScrollView] contentView];
  NSPoint point = [clip bounds].origin;
  point.y = [table_ rectOfRow:(NSInteger)[snapshot_ rowForIndexPath:path]].origin.y + delta;
  [clip scrollToPoint:[clip constrainScrollPoint:point]];
  [[table_ enclosingScrollView] reflectScrolledClipView:clip];
#endif
}
- (BOOL)matchesOldCounts;
{
#if TARGET_OS_IPHONE
  if ((NSUInteger)[table_ numberOfSections] != [[snapshot_ sections] count]) return NO;
  NSUInteger s;
  for (s = 0; s < [[snapshot_ sections] count]; ++s)
    if ((NSUInteger)[table_ numberOfRowsInSection:(NSInteger)s] != [snapshot_ countInSection:s]) return NO;
  return YES;
#else
  return (NSUInteger)[table_ numberOfRows] == [snapshot_ count];
#endif
}
- (void)applySnapshot:(AICollectionSnapshot *)snapshot;
{
  NSAssert(pthread_main_np(), @"Table adapters require main thread");
  if (invalid_ || applying_) return;
  NSParameterAssert(snapshot != nil);
#if TARGET_OS_IPHONE
  CGPoint originalOffset = [table_ contentOffset];
#endif
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
  [pendingRows_ removeAllObjects];
  NSMutableArray *selection = [NSMutableArray array];
  NSEnumerator *enumerator = [[self selectedPaths] objectEnumerator];
  NSIndexPath *path;
  while ((path = [enumerator nextObject])) {
    id identity = [snapshot_ identityAtIndexPath:path];
    if (identity) [selection addObject:identity];
  }
  NSArray *visible = [self visiblePaths];
  NSIndexPath *top = [visible count] ? [visible objectAtIndex:0] : nil;
  id anchor = [[snapshot_ identityAtIndexPath:top] retain];
  double delta = top ? [self offsetFromPath:top] : 0;
  NSDictionary *changes = [snapshot preparedChangesFromSnapshot:snapshot_];
  BOOL reload = !changes || !snapshot_ || [[changes objectForKey:@"reload"] boolValue] || ![self matchesOldCounts];
  BOOL structural = [[changes objectForKey:@"deletedSections"] count] ||
      [[changes objectForKey:@"insertedSections"] count] ||
      [[changes objectForKey:@"deletedRows"] count] || [[changes objectForKey:@"insertedRows"] count];
  AICollectionSnapshot *old = snapshot_;
  snapshot_ = [snapshot retain]; applying_ = YES;
#if TARGET_OS_IPHONE
  if (reload) [table_ reloadData];
  else if (structural) {
    [table_ beginUpdates];
    [table_ deleteSections:[changes objectForKey:@"deletedSections"] withRowAnimation:UITableViewRowAnimationNone];
    [table_ insertSections:[changes objectForKey:@"insertedSections"] withRowAnimation:UITableViewRowAnimationNone];
    [table_ deleteRowsAtIndexPaths:[changes objectForKey:@"deletedRows"] withRowAnimation:UITableViewRowAnimationNone];
    [table_ insertRowsAtIndexPaths:[changes objectForKey:@"insertedRows"] withRowAnimation:UITableViewRowAnimationNone];
    [table_ endUpdates];
  }
#else
  BOOL native = [table_ respondsToSelector:@selector(beginUpdates)] &&
      [table_ respondsToSelector:@selector(endUpdates)] &&
      [table_ respondsToSelector:@selector(insertRowsAtIndexes:withAnimation:)] &&
      [table_ respondsToSelector:@selector(removeRowsAtIndexes:withAnimation:)];
  NSMutableIndexSet *deletes = [NSMutableIndexSet indexSet], *inserts = [NSMutableIndexSet indexSet];
  if (!reload) {
    NSUInteger s, r;
    NSIndexSet *sections = [changes objectForKey:@"deletedSections"];
    for (s = [sections firstIndex]; s != NSNotFound; s = [sections indexGreaterThanIndex:s])
      for (r = 0; r < [old countInSection:s]; ++r) {
        NSUInteger pair[2]; pair[0] = s; pair[1] = r;
        [deletes addIndex:[old rowForIndexPath:[NSIndexPath indexPathWithIndexes:pair length:2]]];
      }
    sections = [changes objectForKey:@"insertedSections"];
    for (s = [sections firstIndex]; s != NSNotFound; s = [sections indexGreaterThanIndex:s])
      for (r = 0; r < [snapshot countInSection:s]; ++r) {
        NSUInteger pair[2]; pair[0] = s; pair[1] = r;
        [inserts addIndex:[snapshot rowForIndexPath:[NSIndexPath indexPathWithIndexes:pair length:2]]];
      }
    enumerator = [[changes objectForKey:@"deletedRows"] objectEnumerator];
    while ((path = [enumerator nextObject])) [deletes addIndex:[old rowForIndexPath:path]];
    enumerator = [[changes objectForKey:@"insertedRows"] objectEnumerator];
    while ((path = [enumerator nextObject])) [inserts addIndex:[snapshot rowForIndexPath:path]];
  }
  reload = reload || (!native && ([deletes count] || [inserts count]));
  if (reload) [table_ reloadData];
  else if ([deletes count] || [inserts count]) {
    AITableVoid(table_,@selector(beginUpdates));
    AITableIndexes(table_,@selector(removeRowsAtIndexes:withAnimation:),deletes);
    AITableIndexes(table_,@selector(insertRowsAtIndexes:withAnimation:),inserts);
    AITableVoid(table_,@selector(endUpdates));
  }
#endif
  /* Reload content AFTER structural changes: coordinates are now unambiguous.
   * This also updates rows whose IDs survived but whose display fields changed. */
  applying_ = NO;
  if (!reload) [self refreshVisibleRows];
#if TARGET_OS_IPHONE
  enumerator = [[self selectedPaths] objectEnumerator];
  while ((path = [enumerator nextObject])) [table_ deselectRowAtIndexPath:path animated:NO];
  enumerator = [selection objectEnumerator]; id identity;
  while ((identity = [enumerator nextObject])) {
    path = [snapshot indexPathForIdentity:identity];
    if (path) [table_ selectRowAtIndexPath:path animated:NO scrollPosition:UITableViewScrollPositionNone];
  }
#else
  NSMutableIndexSet *selected = [NSMutableIndexSet indexSet];
  enumerator = [selection objectEnumerator]; id identity;
  while ((identity = [enumerator nextObject])) {
    path = [snapshot indexPathForIdentity:identity];
    if (path) [selected addIndex:[snapshot rowForIndexPath:path]];
  }
  [table_ selectRowIndexes:selected byExtendingSelection:NO];
#endif
  path = [snapshot indexPathForIdentity:anchor];
#if TARGET_OS_IPHONE
  if (!reload && !structural) [table_ setContentOffset:originalOffset animated:NO];
  else if (path) [self restoreAnchor:path delta:delta];
#else
  (void)structural;
  if (path) [self restoreAnchor:path delta:delta];
#endif
  [anchor release]; [old release];
}
- (void)pageLoaded:(NSNotification *)note;
{
  if (invalid_) return;
  NSUInteger s, offset = [[[note userInfo] objectForKey:@"offset"] unsignedLongValue];
  NSArray *sections = [snapshot_ sections];
  BOOL relevant = NO;
  for (s = 0; s < [sections count]; ++s) {
    NSDictionary *section = [sections objectAtIndex:s];
    id source = [section objectForKey:@"pageSource"];
    if (!source) source = [section objectForKey:@"rows"];
    if (source != [note object]) continue;
    relevant = YES;
    NSUInteger start = [[section objectForKey:@"pageOffset"] unsignedLongValue];
    if (![section objectForKey:@"pageOffset"]) start = [[section objectForKey:@"offset"] unsignedLongValue];
    NSRange range = NSIntersectionRange(NSMakeRange(start,[snapshot_ countInSection:s]),NSMakeRange(offset,32));
    NSUInteger r;
    for (r = range.location; range.length && r < NSMaxRange(range); ++r) {
      NSUInteger pair[2]; pair[0] = s; pair[1] = r - start;
      [pendingRows_ addObject:[NSIndexPath indexPathWithIndexes:pair length:2]];
    }
  }
  if (!relevant) return;
  id error = [[note userInfo] objectForKey:@"error"];
  if (error && error != [NSNull null])
    [[NSNotificationCenter defaultCenter] postNotificationName:AICollectionReadFailedNotification
        object:self userInfo:[note userInfo]];
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(flush:) object:nil];
  [self performSelector:@selector(flush:) withObject:nil afterDelay:0];
}
- (void)refreshVisibleRows;
{
  NSAssert(pthread_main_np(), @"Table adapters require main thread");
  if (invalid_) return;
  [pendingRows_ addObjectsFromArray:[self visiblePaths] ?: [NSArray array]];
  [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(flush:) object:nil];
  [self performSelector:@selector(flush:) withObject:nil afterDelay:0];
}
- (void)flush:(id)ignored;
{
  (void)ignored;
  if (invalid_ || applying_) return;
  NSMutableArray *paths = [NSMutableArray array];
  NSEnumerator *e = [[self visiblePaths] objectEnumerator]; NSIndexPath *path;
  while ((path = [e nextObject])) if ([pendingRows_ containsObject:path]) [paths addObject:path];
  [pendingRows_ removeAllObjects];
  if (![paths count]) return;
#if TARGET_OS_IPHONE
  /* Do not replace an actively edited form cell on a background status/page
   * refresh. Its controller already owns the current field/control values. */
  NSInteger index;
  for (index = (NSInteger)[paths count] - 1; index >= 0; --index)
    if (AICollectionContainsFirstResponder([table_ cellForRowAtIndexPath:[paths objectAtIndex:(NSUInteger)index]]))
      [paths removeObjectAtIndex:(NSUInteger)index];
  if (![paths count]) return;
  NSArray *selected = [[self selectedPaths] copy];
  NSArray *visible = [self visiblePaths];
  NSIndexPath *top = [visible count] ? [visible objectAtIndex:0] : nil;
  double delta = top ? [self offsetFromPath:top] : 0;
  [table_ reloadRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationNone];
  e = [selected objectEnumerator];
  while ((path = [e nextObject]))
    [table_ selectRowAtIndexPath:path animated:NO scrollPosition:UITableViewScrollPositionNone];
  if (top) {
    /* Content-only updates must preserve deliberate offsets, including a
     * short table positioned beyond its resting inset. Structural applies
     * clamp anchors separately after insertions/deletions. */
    CGPoint point = [table_ contentOffset];
    point.y = [table_ rectForRowAtIndexPath:top].origin.y + delta;
    [table_ setContentOffset:point animated:NO];
  }
  [selected release];
#else
  NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
  e = [paths objectEnumerator];
  while ((path = [e nextObject])) [indexes addIndex:[snapshot_ rowForIndexPath:path]];
  NSArray *visible = [self visiblePaths];
  NSIndexPath *top = [visible count] ? [visible objectAtIndex:0] : nil;
  double delta = top ? [self offsetFromPath:top] : 0;
  SEL heights = @selector(noteHeightOfRowsWithIndexesChanged:);
  if ([table_ respondsToSelector:heights]) {
    union { IMP generic; void (*typed)(id,SEL,id); } method;
    method.generic = [table_ methodForSelector:heights];
    method.typed(table_,heights,indexes);
  }
  SEL reload = @selector(reloadDataForRowIndexes:columnIndexes:);
  if ([table_ respondsToSelector:reload]) {
    union { IMP generic; void (*typed)(id,SEL,id,id); } method;
    method.generic = [table_ methodForSelector:reload];
    method.typed(table_,reload,indexes,[NSIndexSet indexSetWithIndexesInRange:
        NSMakeRange(0,[[table_ tableColumns] count])]);
  } else {
    /* Tiger cell-based tables read cells during drawing. Invalidate just the
     * affected row rectangles; no structural reload or selection reset. */
    NSUInteger row;
    for (row = [indexes firstIndex]; row != NSNotFound; row = [indexes indexGreaterThanIndex:row])
      [table_ setNeedsDisplayInRect:[table_ rectOfRow:(NSInteger)row]];
  }
  if (top) [self restoreAnchor:top delta:delta];
#endif
}
- (void)invalidate;
{
  NSAssert(pthread_main_np(), @"Table adapters require main thread");
  invalid_ = YES; table_ = nil;
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [pendingRows_ removeAllObjects]; [snapshot_ release]; snapshot_ = nil;
}
- (void)dealloc;
{ [self invalidate]; [pendingRows_ release]; [super dealloc]; }
@end
