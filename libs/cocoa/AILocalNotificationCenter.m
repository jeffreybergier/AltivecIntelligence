#import "AILocalNotificationCenter.h"
#import <TargetConditionals.h>
#include <pthread.h>

id<AILocalNotificationBackend> AICreateLocalNotificationBackend(void);

@implementation AILocalNotificationCenter
+ (AILocalNotificationCenter *)defaultCenter;
{
  NSAssert(pthread_main_np(), @"Notifications require the main thread");
  static AILocalNotificationCenter *center = nil;
  if (!center) center = [[self alloc] init];
  return center;
}
- (id)init;
{
  id<AILocalNotificationBackend> backend = AICreateLocalNotificationBackend();
  self = [self initWithBackend:backend];
  [backend release];
  return self;
}
- (id)initWithBackend:(id<AILocalNotificationBackend>)backend;
{
  NSAssert(pthread_main_np(), @"Notifications require the main thread");
  self = [super init];
  if (self) {
    backend_ = [backend retain];
    background_ = [backend_ isApplicationInBackground];
    if ([backend_ respondsToSelector:@selector(setNotificationCenter:)])
      [backend_ setNotificationCenter:self];
    NSNotificationCenter *events = [NSNotificationCenter defaultCenter];
#if TARGET_OS_IPHONE
    NSString *active = @"UIApplicationDidBecomeActiveNotification";
    NSString *background = @"UIApplicationDidEnterBackgroundNotification";
    [events addObserver:self selector:@selector(willEnterForeground:)
        name:@"UIApplicationWillEnterForegroundNotification" object:nil];
#else
    NSString *active = @"NSApplicationDidBecomeActiveNotification";
    NSString *background = @"NSApplicationDidResignActiveNotification";
#endif
    [events addObserver:self selector:@selector(didBecomeActive:)
        name:active object:nil];
    [events addObserver:self selector:@selector(didEnterBackground:)
        name:background object:nil];
  }
  return self;
}
- (void)willEnterForeground:(NSNotification *)note;
{
  (void)note;
  background_ = NO;
}
- (void)didBecomeActive:(NSNotification *)note;
{
  (void)note;
  background_ = NO;
  [self clearNotifications];
}
- (void)didEnterBackground:(NSNotification *)note;
{
  (void)note;
  background_ = YES;
  [self setBadgeCount:0];
}
- (AINotificationAuthorizationStatus)authorizationStatus;
{
  NSAssert(pthread_main_np(), @"Notifications require the main thread");
  return invalidated_ ? AINotificationAuthorizationUnsupported :
      [backend_ authorizationStatus];
}
- (void)requestAuthorization;
{
  NSAssert(pthread_main_np(), @"Notifications require the main thread");
  if (!invalidated_) [backend_ requestAuthorization];
}
- (AINotificationResult)postNotificationWithTitle:(NSString *)title
                                           body:(NSString *)body
                                       userInfo:(NSDictionary *)userInfo;
{
  NSAssert(pthread_main_np(), @"Notifications require the main thread");
  if (invalidated_ || !background_) return AINotificationSuppressed;
  AINotificationAuthorizationStatus status = [self authorizationStatus];
  if (status == AINotificationAuthorizationUnsupported)
    return AINotificationUnsupported;
  if (status == AINotificationAuthorizationDenied) return AINotificationDenied;
  if (!body) return AINotificationFailed;
  @try {
    return [backend_ submitTitle:(title ? title : @"") body:body
                       userInfo:userInfo] ? AINotificationSubmitted :
                                            AINotificationFailed;
  } @catch (NSException *exception) {
    (void)exception;
  }
  return AINotificationFailed;
}
- (void)setBadgeCount:(int)count;
{
  NSAssert(pthread_main_np(), @"Notifications require the main thread");
  if (!invalidated_)
    [backend_ setBadgeCount:(background_ && count > 0) ? count : 0];
}
- (void)clearNotifications;
{
  NSAssert(pthread_main_np(), @"Notifications require the main thread");
  if (invalidated_) return;
  [backend_ clearNotifications];
  [backend_ setBadgeCount:0];
}
- (void)setDelegate:(id<AILocalNotificationCenterDelegate>)delegate;
{
  NSAssert(pthread_main_np(), @"Notifications require the main thread");
  if (!invalidated_) delegate_ = delegate;
}
- (void)activateWithUserInfo:(NSDictionary *)userInfo;
{
  NSAssert(pthread_main_np(), @"Notifications require the main thread");
  if (!invalidated_ && userInfo) {
    NSDictionary *payload = [userInfo copy];
    [delegate_ localNotificationCenter:self activatedWithUserInfo:payload];
    [payload release];
  }
}
- (void)invalidate;
{
  NSAssert(pthread_main_np(), @"Notifications require the main thread");
  invalidated_ = YES;
  delegate_ = nil;
  if ([backend_ respondsToSelector:@selector(setNotificationCenter:)])
    [backend_ setNotificationCenter:nil];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}
- (void)dealloc;
{
  [self invalidate];
  [backend_ release];
  [super dealloc];
}
@end
