#import <Foundation/Foundation.h>
/* Main-thread delivery of committed domain hints. The producer supplies store
 * identity, topics, numeric scope/record mapping, and lifecycle generation.
 * Payloads are copied. The target is borrowed; invalidate on the main thread
 * before releasing the target. Queued deliveries then become no-ops.
 * Batches are bounded: excess scopes become a full-store invalidation. */
@interface AIStoreObserver : NSObject {
@private
  id target_;
  SEL selector_;
  NSString *identity_;
  NSLock *lock_;
  NSMutableDictionary *scopes_;
  unsigned int topics_, globalTopics_;
  unsigned long long generation_;
  BOOL scheduled_, invalid_;
}
- (id)initWithStoreIdentity:(NSString *)identity target:(id)target selector:(SEL)selector;
/* Thread safe. Generation must match the one set on the main thread. */
- (void)publishTopics:(unsigned int)topics scope:(NSNumber *)scope
          generation:(unsigned long long)generation;
/* Main thread: drops queued changes from the previous account/filter. */
- (void)setGeneration:(unsigned long long)generation;
- (void)invalidate;
@end
