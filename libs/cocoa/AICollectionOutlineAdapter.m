#import "AICollectionOutlineAdapter.h"
#if !TARGET_OS_IPHONE
#include <pthread.h>
static void AIOutlineVoid(id view, SEL selector)
{
  union { IMP generic; void (*typed)(id,SEL); } method;
  method.generic = [view methodForSelector:selector]; method.typed(view,selector);
}
static void AIOutlineChange(id view, SEL selector, NSIndexSet *indexes, id parent)
{
  union { IMP generic; void (*typed)(id,SEL,id,id,NSUInteger); } method;
  method.generic = [view methodForSelector:selector];
  method.typed(view,selector,indexes,parent,0);
}
@implementation AICollectionOutlineAdapter
- (id)initWithOutlineView:(NSOutlineView *)outline;
{ self = [super init]; if (self) outline_ = outline; return self; }
- (void)applySnapshot:(AICollectionSnapshot *)snapshot;
{
  NSAssert(pthread_main_np(), @"Outline adapters require main thread");
  if (!outline_) return;
  NSMutableArray *selected = [NSMutableArray array], *expanded = [NSMutableArray array];
  NSIndexSet *selection = [outline_ selectedRowIndexes]; NSUInteger row;
  for (row = [selection firstIndex]; row != NSNotFound; row = [selection indexGreaterThanIndex:row]) {
    id item = [outline_ itemAtRow:(NSInteger)row]; if (item) [selected addObject:item];
  }
  NSEnumerator *enumerator = [[snapshot_ sections] objectEnumerator]; NSDictionary *section;
  while ((section = [enumerator nextObject])) {
    id item = [section objectForKey:@"id"];
    if ([outline_ isItemExpanded:item]) [expanded addObject:item];
  }
  NSRange visible = [outline_ rowsInRect:[outline_ visibleRect]];
  id anchor = visible.length ? [[outline_ itemAtRow:(NSInteger)visible.location] retain] : nil;
  CGFloat delta = anchor ? [outline_ visibleRect].origin.y - [outline_ rectOfRow:(NSInteger)visible.location].origin.y : 0;
  NSDictionary *changes = [snapshot changesFromSnapshot:snapshot_];
  BOOL reload = !snapshot_ || [[changes objectForKey:@"reload"] boolValue] ||
      [[changes objectForKey:@"deletedSections"] count] || [[changes objectForKey:@"insertedSections"] count];
  BOOL native = [outline_ respondsToSelector:@selector(beginUpdates)] &&
      [outline_ respondsToSelector:@selector(endUpdates)] &&
      [outline_ respondsToSelector:@selector(removeItemsAtIndexes:inParent:withAnimation:)] &&
      [outline_ respondsToSelector:@selector(insertItemsAtIndexes:inParent:withAnimation:)];
  BOOL structural = [[changes objectForKey:@"deletedRows"] count] || [[changes objectForKey:@"insertedRows"] count];
  if (reload || (structural && !native)) [outline_ reloadData];
  else if (structural) {
    AIOutlineVoid(outline_,@selector(beginUpdates));
    NSUInteger index;
    for (index = 0; index < [[snapshot sections] count]; ++index) {
      NSMutableIndexSet *deletes = [NSMutableIndexSet indexSet], *inserts = [NSMutableIndexSet indexSet];
      NSIndexPath *path;
      enumerator = [[changes objectForKey:@"deletedRows"] objectEnumerator];
      while ((path = [enumerator nextObject])) if ([path indexAtPosition:0] == index) [deletes addIndex:[path indexAtPosition:1]];
      enumerator = [[changes objectForKey:@"insertedRows"] objectEnumerator];
      while ((path = [enumerator nextObject])) if ([path indexAtPosition:0] == index) [inserts addIndex:[path indexAtPosition:1]];
      id parent = [[[snapshot sections] objectAtIndex:index] objectForKey:@"id"];
      if ([deletes count]) AIOutlineChange(outline_,@selector(removeItemsAtIndexes:inParent:withAnimation:),deletes,parent);
      if ([inserts count]) AIOutlineChange(outline_,@selector(insertItemsAtIndexes:inParent:withAnimation:),inserts,parent);
    }
    AIOutlineVoid(outline_,@selector(endUpdates));
  }
  [snapshot_ release]; snapshot_ = [snapshot retain];
  enumerator = [expanded objectEnumerator]; id item;
  while ((item = [enumerator nextObject])) if ([outline_ rowForItem:item] >= 0) [outline_ expandItem:item];
  NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
  enumerator = [selected objectEnumerator];
  while ((item = [enumerator nextObject])) { NSInteger index = [outline_ rowForItem:item]; if (index >= 0) [indexes addIndex:(NSUInteger)index]; }
  [outline_ selectRowIndexes:indexes byExtendingSelection:NO];
  NSInteger top = anchor ? [outline_ rowForItem:anchor] : -1;
  if (top >= 0) {
    NSClipView *clip = [[outline_ enclosingScrollView] contentView]; NSPoint point = [clip bounds].origin;
    point.y = [outline_ rectOfRow:top].origin.y + delta;
    [clip scrollToPoint:[clip constrainScrollPoint:point]];
    [[outline_ enclosingScrollView] reflectScrolledClipView:clip];
  }
  [anchor release];
  if (!reload && !(structural && !native)) [self refreshVisibleRows];
}
- (void)refreshVisibleRows;
{
  NSRange range = [outline_ rowsInRect:[outline_ visibleRect]]; NSUInteger row;
  if (!outline_ || range.location == NSNotFound) return;
  for (row = range.location; row < NSMaxRange(range); ++row)
    [outline_ reloadItem:[outline_ itemAtRow:(NSInteger)row]];
}
- (void)invalidate;
{ outline_ = nil; [snapshot_ release]; snapshot_ = nil; }
- (void)dealloc;
{ [self invalidate]; [super dealloc]; }
@end
#endif
