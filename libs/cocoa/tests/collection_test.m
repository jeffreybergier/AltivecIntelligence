#import "AICollectionController.h"
#import "AICollectionTableAdapter.h"
#import "AIPagedRows.h"
#import <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
#if MAC_OS_X_VERSION_MAX_ALLOWED < 1070
typedef NSUInteger NSTableViewAnimationOptions;
@interface NSTableView (CollectionTestCompatibility)
- (void)reloadDataForRowIndexes:(NSIndexSet *)rows columnIndexes:(NSIndexSet *)columns;
- (void)insertRowsAtIndexes:(NSIndexSet *)rows withAnimation:(NSTableViewAnimationOptions)animation;
- (void)removeRowsAtIndexes:(NSIndexSet *)rows withAnimation:(NSTableViewAnimationOptions)animation;
@end
#endif
#endif
#include <assert.h>
#include <pthread.h>
#include <unistd.h>
#include <stdio.h>

static void spin(double seconds)
{
  NSDate *end=[NSDate dateWithTimeIntervalSinceNow:seconds];
  while ([end timeIntervalSinceNow]>0)
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
}
static AICollectionSnapshot *snapshot(NSArray *ids)
{
  return [[[AICollectionSnapshot alloc] initWithSections:[NSArray arrayWithObject:
    [NSDictionary dictionaryWithObjectsAndKeys:@"items",@"id",ids,@"rows",ids,@"identifiers",nil]]] autorelease];
}
@interface Recipient : NSObject { @public NSMutableArray *results; }
@end
@implementation Recipient
- (id)init; { self=[super init]; if(self) results=[[NSMutableArray alloc] init]; return self; }
- (void)loaded:(id)result; { assert(pthread_main_np()); [results addObject:result]; }
- (void)dealloc; { [results release]; [super dealloc]; }
@end
static NSConditionLock *gate;
static BOOL cancelled;
@interface Builder : NSObject <AICollectionBuilder>
@end
@implementation Builder
+ (id)buildList:(NSDictionary *)request;
{
  assert(!pthread_main_np());
  if([[request objectForKey:@"wait"] boolValue]) {
    [gate lock]; [gate unlockWithCondition:1];
    [gate lockWhenCondition:2]; [gate unlock];
    cancelled=[[AICollectionController currentController] isCancelled];
  }
  if ([request objectForKey:@"throw"]) [NSException raise:@"Test" format:@"Expected builder failure"];
  return [request objectForKey:@"id"];
}
@end

#if !TARGET_OS_IPHONE
@interface Table : NSTableView { @public NSUInteger full, partial, inserted, removed; }
@end
@implementation Table
- (void)reloadData; { ++full; [super reloadData]; }
/* New methods are only exercised on systems advertising them. */
- (void)reloadDataForRowIndexes:(NSIndexSet *)rows columnIndexes:(NSIndexSet *)columns;
{ ++partial; [super reloadDataForRowIndexes:rows columnIndexes:columns]; }
- (void)insertRowsAtIndexes:(NSIndexSet *)rows withAnimation:(NSTableViewAnimationOptions)animation;
{ inserted+=[rows count]; [super insertRowsAtIndexes:rows withAnimation:animation]; }
- (void)removeRowsAtIndexes:(NSIndexSet *)rows withAnimation:(NSTableViewAnimationOptions)animation;
{ removed+=[rows count]; [super removeRowsAtIndexes:rows withAnimation:animation]; }
- (BOOL)respondsToSelector:(SEL)selector;
{
  if(selector==@selector(beginUpdates) || selector==@selector(endUpdates) ||
     selector==@selector(insertRowsAtIndexes:withAnimation:) || selector==@selector(removeRowsAtIndexes:withAnimation:) ||
     selector==@selector(reloadDataForRowIndexes:columnIndexes:))
    return [NSTableView instancesRespondToSelector:selector];
  return [super respondsToSelector:selector];
}
@end
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 1060
@interface Source : NSObject <NSTableViewDataSource> {
#else
@interface Source : NSObject {
#endif
@public NSArray *rows; }
@end
@implementation Source
- (NSInteger)numberOfRowsInTableView:(NSTableView *)table; { (void)table; return [rows count]; }
- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row;
{ (void)table; (void)column; return [rows objectAtIndex:row]; }
@end
static void tableTest(void)
{
  [NSApplication sharedApplication];
  Table *table=[[Table alloc] initWithFrame:NSMakeRect(0,0,300,200)];
  NSScrollView *scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,300,200)];
  [scroll setDocumentView:table];
  NSTableColumn *column=[[NSTableColumn alloc] initWithIdentifier:@"value"];
  [table addTableColumn:column]; [column release];
  Source *source=[[Source alloc] init]; [table setDataSource:source];
  AICollectionTableAdapter *adapter=[[AICollectionTableAdapter alloc] initWithTableView:table];
  source->rows=[NSArray arrayWithObjects:@"a",@"b",@"c",nil];
  [adapter applySnapshot:snapshot(source->rows)]; spin(0.03);
  [table selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
  NSUInteger before=table->full;
  source->rows=[NSArray arrayWithObjects:@"x",@"a",@"b",@"d",nil];
  [adapter applySnapshot:snapshot(source->rows)]; spin(0.03);
  assert([table numberOfRows]==4 && [table selectedRow]==2);
  if([NSTableView instancesRespondToSelector:@selector(beginUpdates)])
    assert(table->full==before && table->inserted==2 && table->removed==1);
  else assert(table->full==before+1);
  before=table->full;
  [[NSNotificationCenter defaultCenter] postNotificationName:AIPagedRowsDidLoadNotification
    object:source->rows userInfo:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:0] forKey:@"offset"]];
  spin(0.03); assert(table->full==before && [table selectedRow]==2);
  [adapter invalidate]; [adapter release];
  [table setDataSource:nil]; [source release]; [table release]; [scroll release];
}
#endif
int main(void)
{
  NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
  /* Random permutations/additions/deletions reconstruct exactly from the diff. */
  NSUInteger iteration,i;
  srand(42);
  for(iteration=0;iteration<500;++iteration) {
    NSMutableArray *old=[NSMutableArray array], *next=[NSMutableArray array];
    for(i=0;i<40;++i) {
      NSNumber *key=[NSNumber numberWithUnsignedLong:i];
      if(rand()%2) [old addObject:key];
      if(rand()%2) [next insertObject:key atIndex:[next count]?rand()%([next count]+1):0];
    }
    NSDictionary *delta=[snapshot(next) changesFromSnapshot:snapshot(old)];
    assert(![[delta objectForKey:@"reload"] boolValue]);
    NSMutableArray *actual=[[old mutableCopy] autorelease];
    NSArray *deleted=[delta objectForKey:@"deletedRows"], *inserted=[delta objectForKey:@"insertedRows"];
    for(i=[deleted count];i>0;--i) [actual removeObjectAtIndex:[[deleted objectAtIndex:i-1] indexAtPosition:1]];
    for(i=0;i<[inserted count];++i) {
      NSUInteger row=[[inserted objectAtIndex:i] indexAtPosition:1];
      [actual insertObject:[next objectAtIndex:row] atIndex:row];
    }
    assert([actual isEqual:next]);
  }
  NSArray *duplicate=[NSArray arrayWithObjects:@"a",@"a",nil];
  assert(![snapshot(duplicate) hasCompleteIdentities]);
  NSMutableArray *large=[NSMutableArray array];
  for(i=0;i<AICollectionIdentityLimit+1;++i) [large addObject:[NSNumber numberWithUnsignedLong:i]];
  assert(![snapshot(large) hasCompleteIdentities]);
  Recipient *recipient=[[Recipient alloc] init];
  AICollectionController *loader=[[AICollectionController alloc] initWithTarget:recipient
    selector:@selector(loaded:) builder:[Builder class]];
  [loader request:[NSDictionary dictionaryWithObject:@"obsolete" forKey:@"id"]];
  [loader request:[NSDictionary dictionaryWithObject:@"latest" forKey:@"id"]];
  for(i=0;i<200 && [loader isLoading];++i) spin(0.01);
  assert([recipient->results count]==1 && [[recipient->results lastObject] isEqual:@"latest"]);
  gate=[[NSConditionLock alloc] initWithCondition:0];
  [loader request:[NSDictionary dictionaryWithObjectsAndKeys:@"stale",@"id",[NSNumber numberWithBool:YES],@"wait",nil]];
  spin(0.03); [gate lockWhenCondition:1];
  [loader request:[NSDictionary dictionaryWithObject:@"new" forKey:@"id"]];
  [gate unlockWithCondition:2];
  for(i=0;i<200 && [loader isLoading];++i) spin(0.01);
  assert(cancelled && [recipient->results count]==2 && [[recipient->results lastObject] isEqual:@"new"]);
  [loader request:[NSDictionary dictionaryWithObject:@"yes" forKey:@"throw"]];
  for(i=0;i<200 && [loader isLoading];++i) spin(0.01);
  assert([[[recipient->results lastObject] objectForKey:@"error"] isKindOfClass:[NSError class]]);
  [gate release]; gate=[[NSConditionLock alloc] initWithCondition:0];
  [loader request:[NSDictionary dictionaryWithObjectsAndKeys:@"disposed",@"id",[NSNumber numberWithBool:YES],@"wait",nil]];
  spin(0.03); [gate lockWhenCondition:1];
  [loader invalidate]; [recipient release];
  [gate unlockWithCondition:2];
  for(i=0;i<200 && [loader isLoading];++i) spin(0.01);
  [loader release]; [gate release];
#if !TARGET_OS_IPHONE
  tableTest();
#endif
#if TARGET_OS_IPHONE
  puts("PASS: collection diffs, bounds, cancellation, latest delivery, errors, active teardown");
#else
  puts("PASS: collection diffs, bounds, cancellation, latest delivery, errors, active teardown, native table");
#endif
  [pool release]; return 0;
}
