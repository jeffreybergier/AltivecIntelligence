#import "AIStoreObserver.h"
@implementation AIStoreObserver
- (id)initWithStoreIdentity:(NSString *)identity target:(id)target selector:(SEL)selector;
{
  self = [super init];
  if (self) {
    identity_ = [identity copy]; target_ = target; selector_ = selector;
    lock_ = [[NSLock alloc] init]; scopes_ = [[NSMutableDictionary alloc] init];
  }
  return self;
}
- (void)dealloc;
{
  [identity_ release]; [lock_ release]; [scopes_ release]; [super dealloc];
}
- (void)setGeneration:(unsigned long long)generation;
{
  [lock_ lock]; generation_ = generation;
  topics_ = globalTopics_ = 0; [scopes_ removeAllObjects]; [lock_ unlock];
}
- (void)invalidate;
{
  [lock_ lock]; invalid_ = YES; target_ = nil;
  topics_ = globalTopics_ = 0; [scopes_ removeAllObjects]; [lock_ unlock];
}
- (void)publishTopics:(unsigned int)topics scope:(NSNumber *)scope
          generation:(unsigned long long)generation;
{
  BOOL schedule = NO;
  [lock_ lock];
  if (!invalid_ && generation == generation_ && topics) {
    topics_ |= topics;
    if (!scope || ![scope longLongValue]) globalTopics_ |= topics;
    else if ([scopes_ count] >= 256) {
      globalTopics_ |= topics_; [scopes_ removeAllObjects];
    } else [scopes_ setObject:[NSNumber numberWithUnsignedInt:
      topics | [[scopes_ objectForKey:scope] unsignedIntValue]] forKey:scope];
    if (!scheduled_) { scheduled_ = YES; schedule = YES; }
  }
  [lock_ unlock];
  if (schedule) [self performSelectorOnMainThread:@selector(deliver:)
    withObject:nil waitUntilDone:NO];
}
- (void)deliver:(id)ignored;
{
  NSDictionary *payload = nil; id target; SEL selector;
  (void)ignored;
  [lock_ lock]; scheduled_ = NO; target = target_; selector = selector_;
  if (!invalid_ && topics_) payload = [[NSDictionary alloc] initWithObjectsAndKeys:
    identity_, @"store", [NSNumber numberWithUnsignedInt:topics_], @"topics",
    [NSNumber numberWithUnsignedInt:globalTopics_], @"globalTopics",
    [[scopes_ copy] autorelease], @"scopes",
    [NSNumber numberWithUnsignedLongLong:generation_], @"generation", nil];
  topics_ = globalTopics_ = 0; [scopes_ removeAllObjects]; [lock_ unlock];
  if (payload) [target performSelector:selector withObject:payload];
  [payload release];
}
@end
