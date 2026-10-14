#import "AICollectionController.h"
#import "AICollectionSnapshot.h"
/* Private work item; domain request dictionaries cannot collide with it. */
@interface AICollectionDiffRequest : NSObject {
@public
  NSDictionary *result, *previous;
}
@end
@implementation AICollectionDiffRequest
- (void)dealloc;
{ [result release]; [previous release]; [super dealloc]; }
@end
#include <pthread.h>
static NSString * const kAICollectionWorker = @"Altivec.CollectionWorker";
@implementation AICollectionController
- (id)initWithTarget:(id)target selector:(SEL)selector builder:(Class)builder;
{
  NSAssert(pthread_main_np(), @"Collection lifecycle requires main thread");
  self = [super init];
  if (self) {
    target_ = target; selector_ = selector; builder_ = builder;
    lock_ = [[NSLock alloc] init];
  }
  return self;
}
+ (AICollectionController *)currentController;
{ return [[[NSThread currentThread] threadDictionary] objectForKey:kAICollectionWorker]; }
- (void)enqueue:(id)request;
{
  NSAssert(pthread_main_np(), @"Collection lifecycle requires main thread");
  [lock_ lock];
  if (!invalid_) {
    ++generation_; [pending_ release]; pending_ = [request retain];
    if (!working_ && !scheduled_) {
      scheduled_ = YES;
      [self performSelector:@selector(start:) withObject:nil afterDelay:0];
    }
  }
  [lock_ unlock];
}
- (void)request:(NSDictionary *)request;
{ [self enqueue:[[request copy] autorelease]]; }
- (BOOL)prepareResult:(NSDictionary *)result
         snapshotKey:(NSString *)key
    previousSnapshot:(AICollectionSnapshot *)previous;
{
  return [self prepareResult:result previousSnapshots:
      [NSDictionary dictionaryWithObject:previous ?: (id)[NSNull null] forKey:key]];
}
- (BOOL)prepareResult:(NSDictionary *)result
   previousSnapshots:(NSDictionary *)previous;
{
  NSAssert(pthread_main_np(), @"Receive collection snapshots on main thread");
  NSMutableDictionary *needed = [NSMutableDictionary dictionary];
  NSEnumerator *keys = [previous keyEnumerator]; NSString *key;
  while ((key = [keys nextObject])) {
    AICollectionSnapshot *before = [previous objectForKey:key];
    AICollectionSnapshot *after = [result objectForKey:key];
    if ([before isKindOfClass:[AICollectionSnapshot class]] &&
        [after isKindOfClass:[AICollectionSnapshot class]] &&
        ![after preparedChangesFromSnapshot:before])
      [needed setObject:before forKey:key];
  }
  if (![needed count]) return NO;
  AICollectionDiffRequest *work = [[AICollectionDiffRequest alloc] init];
  work->result = [result copy]; work->previous = [needed copy];
  [self enqueue:work]; [work release]; return YES;
}
- (void)start:(id)ignored;
{
  (void)ignored;
  [lock_ lock]; scheduled_ = NO;
  BOOL start = !invalid_ && !working_ && pending_ != nil;
  if (start) working_ = YES;
  [lock_ unlock];
  if (start) [NSThread detachNewThreadSelector:@selector(work:)
                                    toTarget:self withObject:nil];
}
- (void)cancel;
{
  NSAssert(pthread_main_np(), @"Collection lifecycle requires main thread");
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
  [lock_ lock]; ++generation_; scheduled_ = NO;
  [pending_ release]; pending_ = nil; [lock_ unlock];
}
- (void)invalidate;
{
  [self cancel];
  [lock_ lock]; invalid_ = YES; target_ = nil; [lock_ unlock];
}
- (BOOL)isCancelled;
{
  NSNumber *active = [[[NSThread currentThread] threadDictionary]
      objectForKey:@"Altivec.CollectionGeneration"];
  [lock_ lock];
  BOOL cancelled = invalid_ || (active && [active unsignedLongValue] != generation_);
  [lock_ unlock]; return cancelled;
}
- (BOOL)isLoading;
{
  [lock_ lock]; BOOL loading = working_ || scheduled_ || pending_ != nil;
  [lock_ unlock]; return loading;
}
- (id)buildResultForRequest:(NSDictionary *)request;
{ return [(Class<AICollectionBuilder>)builder_ buildList:request]; }
- (void)work:(id)ignored;
{
  (void)ignored;
  for (;;) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [lock_ lock];
    id input = pending_; pending_ = nil;
    unsigned long generation = generation_;
    if (!input || invalid_) {
      working_ = NO; [lock_ unlock]; [input release]; [pool release]; return;
    }
    [lock_ unlock];
    NSMutableDictionary *thread = [[NSThread currentThread] threadDictionary];
    [thread setObject:self forKey:kAICollectionWorker];
    [thread setObject:[NSNumber numberWithUnsignedLong:generation]
              forKey:@"Altivec.CollectionGeneration"];
    id output = nil;
    @try {
      if ([input isKindOfClass:[AICollectionDiffRequest class]]) {
        AICollectionDiffRequest *diff = input;
        NSEnumerator *keys = [diff->previous keyEnumerator]; NSString *key;
        while (![self isCancelled] && (key = [keys nextObject]))
          [[diff->result objectForKey:key] prepareChangesFromSnapshot:
              [diff->previous objectForKey:key]];
        output = diff->result;
      } else output = [self buildResultForRequest:input];
    }
    @catch (NSException *exception) {
      NSError *error = [NSError errorWithDomain:@"Altivec.Collection" code:1
          userInfo:[NSDictionary dictionaryWithObject:([exception reason] ?: @"Collection build failed")
              forKey:NSLocalizedDescriptionKey]];
      output = [NSDictionary dictionaryWithObject:error forKey:@"error"];
    }
    NSDictionary *delivery = [NSDictionary dictionaryWithObjectsAndKeys:
        output ? output : (id)[NSNull null], @"result",
        [NSNumber numberWithUnsignedLong:generation], @"generation", nil];
    [self performSelectorOnMainThread:@selector(deliver:)
                          withObject:delivery waitUntilDone:YES];
    [thread removeObjectForKey:kAICollectionWorker];
    [thread removeObjectForKey:@"Altivec.CollectionGeneration"];
    [input release]; [pool release];
  }
}
- (void)deliver:(NSDictionary *)delivery;
{
  [lock_ lock];
  BOOL current = !invalid_ && generation_ ==
      [[delivery objectForKey:@"generation"] unsignedLongValue];
  id target = target_; [lock_ unlock];
  id result = [delivery objectForKey:@"result"];
  if (current) [target performSelector:selector_
      withObject:result == [NSNull null] ? nil : result];
}
- (void)dealloc;
{
  /* An active worker retains self; invalidation never waits for that worker. */
  [lock_ release]; [pending_ release]; [super dealloc];
}
@end
