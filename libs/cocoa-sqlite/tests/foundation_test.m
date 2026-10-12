#import <Foundation/Foundation.h>
#import "AIStoreObserver.h"
#import "AIPagedRows.h"
#import "AICoalescedCallback.h"
#include <assert.h>
#include <stdio.h>
#include <pthread.h>
@interface FixtureRows : AIPagedRows { @public unsigned int reads; }
@end
@implementation FixtureRows
- (NSUInteger)count; { return 100000; }
- (NSArray *)pageAtOffset:(NSUInteger)offset error:(NSError **)error;
{
  NSMutableArray *page=[NSMutableArray array]; NSUInteger i;
  (void)error; ++reads;
  for(i=offset;i<offset+32 && i<[self count];++i)
    [page addObject:[NSNumber numberWithUnsignedLong:i]];
  return page;
}
@end
@interface Receiver : NSObject { @public unsigned int calls; NSDictionary *last; }
- (void)received:(NSDictionary *)value;
@end
@implementation Receiver
- (void)received:(NSDictionary *)value;
{ assert(pthread_main_np()); ++calls; [last release]; last=[value copy]; }
- (void)dealloc; { [last release]; [super dealloc]; }
@end
static void pump(void) {
  NSDate *end=[NSDate dateWithTimeIntervalSinceNow:0.2];
  while([end timeIntervalSinceNow]>0)
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}
int main(void) {
  NSAutoreleasePool *pool=[[NSAutoreleasePool alloc] init];
  FixtureRows *rows=[[FixtureRows alloc] init]; unsigned int i;
  Receiver *receiver=[[Receiver alloc] init];
  AIStoreObserver *observer=[[AIStoreObserver alloc] initWithStoreIdentity:@"account-A"
    target:receiver selector:@selector(received:)];
  AICoalescedCallback *callback;
  for(i=0;i<128;++i) assert([[rows objectAtIndex:i] unsignedIntValue]==i);
  assert(rows->reads==4);
  assert([[rows objectAtIndex:99999] unsignedIntValue]==99999);
  assert([rows cachedObjectAtIndex:0]==nil);
  [rows invalidatePages];
  assert([rows requestObjectAtIndex:456 placeholder:nil]==nil); pump();
  assert([[rows cachedObjectAtIndex:456] unsignedIntValue]==456);
  [rows requestObjectAtIndex:32000 placeholder:nil]; [rows invalidatePages];
  pump(); assert([rows cachedObjectAtIndex:32000]==nil);
  [observer publishTopics:1 scope:[NSNumber numberWithInt:5] generation:0];
  [observer publishTopics:2 scope:[NSNumber numberWithInt:5] generation:0];
  pump(); assert(receiver->calls==1);
  assert([[[receiver->last objectForKey:@"scopes"] objectForKey:[NSNumber numberWithInt:5]] unsignedIntValue]==3);
  [observer setGeneration:2];
  [observer publishTopics:1 scope:nil generation:0]; pump(); assert(receiver->calls==1);
  [observer publishTopics:1 scope:nil generation:2]; [observer invalidate];
  pump(); assert(receiver->calls==1);
  callback=[[AICoalescedCallback alloc] initWithTarget:receiver selector:@selector(received:)
    idleDelay:0.01 maximumDelay:0.05];
  [callback schedule]; [callback schedule]; pump(); assert(receiver->calls==2);
  [callback schedule]; [callback invalidate]; pump(); assert(receiver->calls==2);
  [callback release]; [observer release]; [receiver release]; [rows release];
  puts("PASS: paged cache/random access/async loading/stale generation/observer disposal/debounce");
  [pool release]; return 0;
}
