#import "AICoalescedCallback.h"
@implementation AICoalescedCallback
- (id)initWithTarget:(id)target selector:(SEL)selector
          idleDelay:(NSTimeInterval)idle maximumDelay:(NSTimeInterval)maximum;
{
  self=[super init];
  if(self) { target_=target; selector_=selector; idle_=MAX(0,idle); maximum_=MAX(idle_,maximum); }
  return self;
}
- (void)dealloc;
{ [timer_ invalidate]; [timer_ release]; [super dealloc]; }
- (void)cancel;
{ [timer_ invalidate]; [timer_ release]; timer_=nil; deadline_=0; }
- (void)invalidate;
{ [self cancel]; target_=nil; }
- (void)schedule;
{
  NSTimeInterval now, delay;
  if(!target_) return;
  now=[NSDate timeIntervalSinceReferenceDate];
  if(!deadline_) deadline_=now+maximum_;
  delay=MAX(0,MIN(idle_,deadline_-now));
  [timer_ invalidate]; [timer_ release];
  timer_=[[NSTimer scheduledTimerWithTimeInterval:delay target:self
    selector:@selector(fire:) userInfo:nil repeats:NO] retain];
}
- (void)fire:(NSTimer *)timer;
{
  (void)timer;
  [self retain]; [self cancel];
  [target_ performSelector:selector_ withObject:nil];
  [self release];
}
@end
