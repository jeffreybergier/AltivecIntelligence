#import "AILocalNotificationCenter.h"
#import <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
#endif
#include <assert.h>
#include <pthread.h>
#include <stdio.h>

@interface Recorder : NSObject <AILocalNotificationBackend,
    AILocalNotificationCenterDelegate> {
@public
  NSMutableArray *events;
  NSDictionary *payload;
  NSString *body;
  AINotificationAuthorizationStatus status;
  BOOL background, fail, throws;
  unsigned int activations;
}
@end
@implementation Recorder
- (id)init;
{
  self = [super init];
  if (self) {
    events = [[NSMutableArray alloc] init];
    status = AINotificationAuthorizationAuthorized;
  }
  return self;
}
- (AINotificationAuthorizationStatus)authorizationStatus; { return status; }
- (void)requestAuthorization; { [events addObject:@"request"]; }
- (BOOL)isApplicationInBackground; { return background; }
- (BOOL)submitTitle:(NSString *)title body:(NSString *)text
          userInfo:(NSDictionary *)info;
{
  assert(pthread_main_np());
  assert(title != nil);
  if (throws) [NSException raise:@"test" format:@"injected failure"];
  [events addObject:@"submit"];
  [body release]; body = [text copy];
  [payload release]; payload = [info copy];
  return !fail;
}
- (void)clearNotifications; { [events addObject:@"clear"]; }
- (void)setBadgeCount:(int)count;
{ [events addObject:[NSNumber numberWithInt:count]]; }
- (void)localNotificationCenter:(AILocalNotificationCenter *)center
          activatedWithUserInfo:(NSDictionary *)info;
{
  (void)center;
  assert(pthread_main_np());
  ++activations;
  [payload release]; payload = [info copy];
}
- (void)dealloc;
{ [events release]; [payload release]; [body release]; [super dealloc]; }
@end

static void event(NSString *name)
{
  [[NSNotificationCenter defaultCenter] postNotificationName:name object:nil];
}
int main(void)
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
#if TARGET_OS_IPHONE
  NSString *active = UIApplicationDidBecomeActiveNotification;
  NSString *background = UIApplicationDidEnterBackgroundNotification;
#else
  NSString *active = NSApplicationDidBecomeActiveNotification;
  NSString *background = NSApplicationDidResignActiveNotification;
#endif
  Recorder *recorder = [[Recorder alloc] init];
  AILocalNotificationCenter *center = [[AILocalNotificationCenter alloc]
      initWithBackend:recorder];
  NSDictionary *info = [NSDictionary dictionaryWithObject:@"account/chat"
                                                   forKey:@"route"];
  assert([center postNotificationWithTitle:nil body:@"foreground" userInfo:info]
      == AINotificationSuppressed);
  assert([recorder->events count] == 0);
  [center requestAuthorization];
  assert([[recorder->events lastObject] isEqual:@"request"]);
  event(background);
  assert([[recorder->events lastObject] intValue] == 0);
  assert([center postNotificationWithTitle:@"Alice" body:@"日本語"
      userInfo:info] == AINotificationSubmitted);
  assert([recorder->body isEqual:@"日本語"]);
  assert([recorder->payload isEqual:info]);
  [center setBadgeCount:7];
  assert([[recorder->events lastObject] intValue] == 7);
  [center setBadgeCount:-3];
  assert([[recorder->events lastObject] intValue] == 0);
  recorder->status = AINotificationAuthorizationDenied;
  NSUInteger before = [recorder->events count];
  assert([center postNotificationWithTitle:nil body:@"denied" userInfo:nil]
      == AINotificationDenied);
  assert([recorder->events count] == before);
  recorder->status = AINotificationAuthorizationUnsupported;
  assert([center postNotificationWithTitle:nil body:@"unsupported" userInfo:nil]
      == AINotificationUnsupported);
  recorder->status = AINotificationAuthorizationUnknown;
  assert([center postNotificationWithTitle:nil body:@"unknown" userInfo:nil]
      == AINotificationSubmitted);
  recorder->fail = YES;
  assert([center postNotificationWithTitle:nil body:@"failure" userInfo:nil]
      == AINotificationFailed);
  recorder->throws = YES;
  assert([center postNotificationWithTitle:nil body:@"exception" userInfo:nil]
      == AINotificationFailed);
  recorder->fail = recorder->throws = NO;
  [center setDelegate:recorder];
  [center activateWithUserInfo:info];
  assert(recorder->activations == 1 && [recorder->payload isEqual:info]);
  [recorder->events removeAllObjects];
  event(active);
  assert([recorder->events count] == 2);
  assert([[recorder->events objectAtIndex:0] isEqual:@"clear"]);
  assert([[recorder->events objectAtIndex:1] intValue] == 0);
  [center setBadgeCount:9];
  assert([[recorder->events lastObject] intValue] == 0);
  assert([center postNotificationWithTitle:nil body:@"active" userInfo:nil]
      == AINotificationSuppressed);
#if TARGET_OS_IPHONE
  event(background);
  event(UIApplicationWillEnterForegroundNotification);
  assert([center postNotificationWithTitle:nil body:@"transition" userInfo:nil]
      == AINotificationSuppressed);
#endif
  [center invalidate];
  before = [recorder->events count];
  event(background); event(active);
  [center requestAuthorization]; [center clearNotifications];
  [center setBadgeCount:4]; [center activateWithUserInfo:info];
  assert([recorder->events count] == before && recorder->activations == 1);
  [center release];
  /* Initial background relaunch and cold-launch activation/cleanup. */
  recorder->background = YES;
  center = [[AILocalNotificationCenter alloc] initWithBackend:recorder];
  assert([center postNotificationWithTitle:nil body:@"relaunch" userInfo:nil]
      == AINotificationSubmitted);
  [center setDelegate:recorder]; [center activateWithUserInfo:info];
  event(active);
  assert(recorder->activations == 2);
  [center release]; [recorder release];
  puts("PASS: notification lifecycle, permissions, payloads, errors, teardown");
  [pool release];
  return 0;
}
