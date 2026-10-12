#import <Foundation/Foundation.h>
/* Main-thread bounded debounce for already-committed UI work. Payload/domain
 * ordering stays with the caller. Target is borrowed; invalidate before its
 * destruction. The timer retains this adapter, never the target. */
@interface AICoalescedCallback : NSObject {
@private
  id target_;
  SEL selector_;
  NSTimer *timer_;
  NSTimeInterval idle_, maximum_, deadline_;
}
- (id)initWithTarget:(id)target selector:(SEL)selector
          idleDelay:(NSTimeInterval)idle maximumDelay:(NSTimeInterval)maximum;
- (void)schedule;
- (void)cancel;
- (void)invalidate;
@end
