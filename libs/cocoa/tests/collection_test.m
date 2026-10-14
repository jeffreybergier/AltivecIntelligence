#import "AICollectionController.h"
#import "AICollectionTableAdapter.h"
#import "AICollectionOutlineAdapter.h"
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
/* Count equality work instead of asserting machine-dependent wall times. */
static NSUInteger identityComparisons;
@interface IdentityKey : NSObject <NSCopying> { NSUInteger value_; }
- (id)initWithValue:(NSUInteger)value;
@end
@implementation IdentityKey
- (id)initWithValue:(NSUInteger)value;
{ self=[super init]; if(self) value_=value; return self; }
- (NSUInteger)hash; { return value_; }
- (BOOL)isEqual:(id)other;
{ ++identityComparisons; return [other isKindOfClass:[IdentityKey class]] && value_==((IdentityKey *)other)->value_; }
- (id)copyWithZone:(NSZone *)zone; { (void)zone; return [self retain]; }
@end
static void identityMapTest(void)
{
  NSMutableArray *ids=[NSMutableArray array];
  NSUInteger i, count=1000;
  for(i=0;i<count;++i)
    [ids addObject:[[[IdentityKey alloc] initWithValue:i] autorelease]];
  identityComparisons=0;
  AICollectionSnapshot *list=snapshot(ids);
  for(i=0;i<count;++i) {
    IdentityKey *equal=[[[IdentityKey alloc] initWithValue:i] autorelease];
    NSIndexPath *path=[list indexPathForIdentity:
      [NSArray arrayWithObjects:@"items",equal,nil]];
    assert([path length]==2 && [path indexAtPosition:1]==i);
  }
  assert(identityComparisons<count*20);
  NSDictionary *unchanged=[list changesFromSnapshot:list];
  assert(![[unchanged objectForKey:@"reload"] boolValue] &&
      [[unchanged objectForKey:@"deletedRows"] count]==0 &&
      [[unchanged objectForKey:@"insertedRows"] count]==0);
  AICollectionSnapshot *reverse=snapshot([[ids reverseObjectEnumerator] allObjects]);
  assert([[[reverse changesFromSnapshot:list] objectForKey:@"reload"] boolValue]);
  NSArray *shared=[NSArray arrayWithObject:@"same-row-id"];
  NSDictionary *a=[NSDictionary dictionaryWithObjectsAndKeys:@"a",@"id",shared,@"rows",shared,@"identifiers",nil];
  NSDictionary *b=[NSDictionary dictionaryWithObjectsAndKeys:@"b",@"id",shared,@"rows",shared,@"identifiers",nil];
  list=[[[AICollectionSnapshot alloc] initWithSections:[NSArray arrayWithObjects:a,b,nil]] autorelease];
  assert([list hasCompleteIdentities]);
  for(i=0;i<2;++i) {
    NSIndexPath *path=[list indexPathForRow:i];
    assert([[list indexPathForIdentity:[list identityAtIndexPath:path]] isEqual:path]);
  }
  assert((![list indexPathForIdentity:[NSArray arrayWithObjects:@"missing",@"same-row-id",nil]]));
  assert((![list indexPathForIdentity:[NSArray arrayWithObjects:@"a",@"missing",nil]]));
  list=[[[AICollectionSnapshot alloc] initWithSections:[NSArray arrayWithObjects:a,a,nil]] autorelease];
  assert(![list hasCompleteIdentities]);
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

/* The first receipt and publication are main-thread; only comparison leaves it. */
static NSConditionLock *diffGate;
static NSUInteger workerDiffs;
@interface WorkerSnapshot : AICollectionSnapshot { @public BOOL pause, fail; }
@end
@implementation WorkerSnapshot
- (NSDictionary *)changesFromSnapshot:(AICollectionSnapshot *)previous;
{
  assert(!pthread_main_np()); ++workerDiffs;
  if (pause) {
    [diffGate lock]; [diffGate unlockWithCondition:1];
    [diffGate lockWhenCondition:2]; [diffGate unlock];
  }
  if (fail) [NSException raise:@"DiffFailure" format:@"Expected diff failure"];
  return [super changesFromSnapshot:previous];
}
@end
static WorkerSnapshot *workerSnapshot(NSArray *ids)
{
  return [[[WorkerSnapshot alloc] initWithSections:[snapshot(ids) sections]] autorelease];
}
@interface DiffBuilder : NSObject <AICollectionBuilder>
@end
@implementation DiffBuilder
+ (id)buildList:(NSDictionary *)request;
{ assert(!pthread_main_np()); return request; }
@end
@interface DiffRecipient : NSObject {
@public AICollectionController *loader; AICollectionSnapshot *current;
  NSUInteger publications, receipts, errors;
}
- (void)receive:(NSDictionary *)result;
@end
@implementation DiffRecipient
- (id)init;
{
  self=[super init];
  if(self) loader=[[AICollectionController alloc] initWithTarget:self
      selector:@selector(receive:) builder:[DiffBuilder class]];
  return self;
}
- (void)receive:(NSDictionary *)result;
{
  assert(pthread_main_np()); ++receipts;
  if([result objectForKey:@"error"]) { ++errors; return; }
  if([loader prepareResult:result snapshotKey:@"snapshot" previousSnapshot:current]) return;
  AICollectionSnapshot *next=[result objectForKey:@"snapshot"];
  if(current) assert([next preparedChangesFromSnapshot:current]);
  [current release]; current=[next retain]; ++publications;
}
- (void)dealloc;
{ [loader invalidate]; [loader release]; [current release]; [super dealloc]; }
@end
static NSDictionary *diffResult(AICollectionSnapshot *value)
{ return [NSDictionary dictionaryWithObject:value forKey:@"snapshot"]; }
static void awaitDiff(AICollectionController *loader)
{
  NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:5];
  while([loader isLoading] && [deadline timeIntervalSinceNow]>0) spin(0.005);
  assert(![loader isLoading]);
}
#if !TARGET_OS_IPHONE
static void prepare(AICollectionSnapshot *next, AICollectionSnapshot *previous)
{
  DiffRecipient *recipient=[[DiffRecipient alloc] init];
  recipient->current=[previous retain];
  [recipient receive:diffResult(next)]; awaitDiff(recipient->loader);
  assert(recipient->publications==1); [recipient release];
}
#endif
static void diffPipelineTest(void)
{
  DiffRecipient *recipient=[[DiffRecipient alloc] init];
  AICollectionSnapshot *initial=snapshot([NSArray arrayWithObject:@"a"]);
  [recipient receive:diffResult(initial)]; assert(recipient->publications==1);
  WorkerSnapshot *slow=workerSnapshot([NSArray arrayWithObject:@"old"]);
  slow->pause=YES; diffGate=[[NSConditionLock alloc] initWithCondition:0];
  [recipient receive:diffResult(slow)]; spin(0.02);
  assert([diffGate lockWhenCondition:1 beforeDate:[NSDate dateWithTimeIntervalSinceNow:5]]);
  assert(recipient->current==initial && recipient->publications==1);
  /* A later receipt supersedes the in-flight comparison without publishing it. */
  WorkerSnapshot *latest=workerSnapshot([NSArray arrayWithObjects:@"a",@"new",nil]);
  [recipient->loader request:diffResult(latest)];
  [diffGate unlockWithCondition:2]; awaitDiff(recipient->loader);
  assert(recipient->current==latest && recipient->publications==2);
  assert([latest preparedChangesFromSnapshot:initial]);
  assert(![latest preparedChangesFromSnapshot:snapshot([NSArray arrayWithObject:@"a"])]);
  [diffGate release];
  /* A baseline changed during comparison must be compared again, never applied. */
  diffGate=[[NSConditionLock alloc] initWithCondition:0];
  WorkerSnapshot *rebased=workerSnapshot([NSArray arrayWithObject:@"rebase"]);
  rebased->pause=YES; [recipient receive:diffResult(rebased)]; spin(0.02);
  assert([diffGate lockWhenCondition:1 beforeDate:[NSDate dateWithTimeIntervalSinceNow:5]]);
  AICollectionSnapshot *replacement=snapshot([NSArray arrayWithObject:@"replacement"]);
  [recipient->current release]; recipient->current=[replacement retain];
  rebased->pause=NO; [diffGate unlockWithCondition:2]; awaitDiff(recipient->loader);
  assert([rebased preparedChangesFromSnapshot:replacement]);
  assert(recipient->current==rebased && recipient->publications==3);
  [diffGate release];
  WorkerSnapshot *bad=workerSnapshot([NSArray arrayWithObject:@"error"]); bad->fail=YES;
  [recipient receive:diffResult(bad)]; awaitDiff(recipient->loader);
  assert(recipient->errors==1 && recipient->current==rebased);
  /* Teardown detaches the borrowed target while comparison is still blocked. */
  diffGate=[[NSConditionLock alloc] initWithCondition:0];
  WorkerSnapshot *disposed=workerSnapshot([NSArray arrayWithObject:@"disposed"]); disposed->pause=YES;
  [recipient receive:diffResult(disposed)]; spin(0.02);
  assert([diffGate lockWhenCondition:1 beforeDate:[NSDate dateWithTimeIntervalSinceNow:5]]);
  AICollectionController *loader=[recipient->loader retain];
  [recipient release]; [diffGate unlockWithCondition:2]; awaitDiff(loader);
  [loader release]; [diffGate release]; diffGate=nil;
  assert(workerDiffs>=6);
}

#if !TARGET_OS_IPHONE
@interface Table : NSTableView { @public NSUInteger full, partial, inserted, removed; }
@end
@implementation Table
- (void)reloadData; { assert(pthread_main_np()); ++full; [super reloadData]; }
/* New methods are only exercised on systems advertising them. */
- (void)reloadDataForRowIndexes:(NSIndexSet *)rows columnIndexes:(NSIndexSet *)columns;
{ ++partial; [super reloadDataForRowIndexes:rows columnIndexes:columns]; }
- (void)insertRowsAtIndexes:(NSIndexSet *)rows withAnimation:(NSTableViewAnimationOptions)animation;
{ assert(pthread_main_np()); inserted+=[rows count]; [super insertRowsAtIndexes:rows withAnimation:animation]; }
- (void)removeRowsAtIndexes:(NSIndexSet *)rows withAnimation:(NSTableViewAnimationOptions)animation;
{ assert(pthread_main_np()); removed+=[rows count]; [super removeRowsAtIndexes:rows withAnimation:animation]; }
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
  NSArray *nextRows = [NSArray arrayWithObjects:@"a",@"b",@"c",nil];
  AICollectionSnapshot *next = snapshot(nextRows);
  prepare(next,[adapter snapshot]); source->rows = nextRows;
  [adapter applySnapshot:next]; spin(0.03);
  assert(table->partial==0); /* Initial reload must not enqueue a second redraw. */
  [table selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];
  NSUInteger before=table->full;
  nextRows = [NSArray arrayWithObjects:@"x",@"a",@"b",@"d",nil];
  next = snapshot(nextRows);
  prepare(next,[adapter snapshot]); source->rows = nextRows;
  [adapter applySnapshot:next]; spin(0.03);
  assert([table numberOfRows]==4 && [table selectedRow]==2);
  if([NSTableView instancesRespondToSelector:@selector(beginUpdates)])
    assert(table->full==before && table->inserted==2 && table->removed==1);
  else assert(table->full==before+1);
  before=table->full;
  [[NSNotificationCenter defaultCenter] postNotificationName:AIPagedRowsDidLoadNotification
    object:source->rows userInfo:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:0] forKey:@"offset"]];
  spin(0.03); assert(table->full==before && [table selectedRow]==2);
  /* An immediate caller or a mismatched baseline reloads without computing. */
  nextRows = [NSArray arrayWithObject:@"fallback"];
  WorkerSnapshot *unprepared = workerSnapshot(nextRows);
  before=table->full; source->rows=nextRows;
  [adapter applySnapshot:unprepared];
  assert(table->full==before+1 && [table numberOfRows]==1);
  WorkerSnapshot *mismatch = workerSnapshot([NSArray arrayWithObject:@"mismatch"]);
  prepare(mismatch,snapshot([NSArray arrayWithObject:@"unrelated"]));
  before=table->full; source->rows=[NSArray arrayWithObject:@"mismatch"];
  [adapter applySnapshot:mismatch];
  assert(table->full==before+1 && [table numberOfRows]==1);
  [adapter invalidate]; [adapter release];
  [table setDataSource:nil]; [source release]; [table release]; [scroll release];
}

#if MAC_OS_X_VERSION_MAX_ALLOWED >= 1060
@interface OutlineSource : NSObject <NSOutlineViewDataSource> {
#else
@interface OutlineSource : NSObject {
#endif
@public NSArray *rows;
}
@end
@implementation OutlineSource
- (NSInteger)outlineView:(NSOutlineView *)view numberOfChildrenOfItem:(id)item;
{ (void)view; return item ? ([item isEqual:@"items"] ? [rows count] : 0) : 1; }
- (id)outlineView:(NSOutlineView *)view child:(NSInteger)index ofItem:(id)item;
{ (void)view; return item ? [rows objectAtIndex:(NSUInteger)index] : @"items"; }
- (BOOL)outlineView:(NSOutlineView *)view isItemExpandable:(id)item;
{ (void)view; return [item isEqual:@"items"]; }
- (id)outlineView:(NSOutlineView *)view objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item;
{ (void)view; (void)column; return item; }
@end
static void outlineTest(void)
{
  NSOutlineView *view = [[NSOutlineView alloc] initWithFrame:NSMakeRect(0,0,300,200)];
  NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"value"];
  [view addTableColumn:column]; [view setOutlineTableColumn:column]; [column release];
  NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0,0,300,200)];
  [scroll setDocumentView:view];
  OutlineSource *source = [[OutlineSource alloc] init]; [view setDataSource:source];
  AICollectionOutlineAdapter *adapter = [[AICollectionOutlineAdapter alloc] initWithOutlineView:view];
  NSArray *nextRows = [NSArray arrayWithObjects:@"a",@"b",@"c",nil];
  AICollectionSnapshot *next = snapshot(nextRows);
  prepare(next,[adapter snapshot]); source->rows = nextRows;
  [adapter applySnapshot:next]; [view expandItem:@"items"];
  [view selectRowIndexes:[NSIndexSet indexSetWithIndex:2] byExtendingSelection:NO];
  nextRows = [NSArray arrayWithObjects:@"x",@"a",@"b",@"d",nil];
  next = snapshot(nextRows);
  prepare(next,[adapter snapshot]); source->rows = nextRows;
  [adapter applySnapshot:next];
  assert([view isItemExpanded:@"items"] && [view numberOfRows] == 5);
  assert([[view itemAtRow:[view selectedRow]] isEqual:@"b"]);
  [view collapseItem:@"items"];
  nextRows = [NSArray arrayWithObjects:@"b",@"x",nil];
  next = snapshot(nextRows);
  prepare(next,[adapter snapshot]); source->rows = nextRows;
  [adapter applySnapshot:next];
  assert(![view isItemExpanded:@"items"] && [view numberOfRows] == 1);
  [view expandItem:@"items"]; assert([view numberOfRows] == 3);
  nextRows = [NSArray array];
  next = snapshot(nextRows);
  prepare(next,[adapter snapshot]); source->rows = nextRows;
  [adapter applySnapshot:next];
  assert([view numberOfRows] == 1);
  [adapter invalidate]; [adapter release]; [view setDataSource:nil];
  [source release]; [view release]; [scroll release];
}
#endif
int main(void)
{
  NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
  identityMapTest(); diffPipelineTest();
  AICollectionSnapshot *form = [[[AICollectionSnapshot alloc] initWithSections:
      [NSArray arrayWithObject:[NSDictionary dictionaryWithObjectsAndKeys:
          @"form",@"id",[NSNumber numberWithInt:2],@"count",
          [NSArray arrayWithObjects:@"name",@"password",nil],@"identifiers",nil]]] autorelease];
  assert([form count] == 2 && [form hasCompleteIdentities]);
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
  tableTest(); outlineTest();
#endif
#if TARGET_OS_IPHONE
  puts("PASS: collection diffs, bounds, cancellation, latest delivery, errors, active teardown");
#else
  puts("PASS: collection diffs, bounds, cancellation, latest delivery, errors, active teardown, native table");
#endif
  [pool release]; return 0;
}
