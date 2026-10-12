// Adapted from ENIL and Retro-DLP. Copyright (c) 2026 Jeffrey Bergier.
#import "AILocalNotificationCenter.h"
#import <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <AppKit/AppKit.h>
#endif

/* Typed runtime dispatch keeps newer symbols out of legacy SDK linkage. */
static id AIObject(id target, SEL selector)
{
  if (![target respondsToSelector:selector]) return nil;
  return ((id (*)(id, SEL))[target methodForSelector:selector])(target, selector);
}
static void AISetObject(id target, SEL selector, id value)
{
  if ([target respondsToSelector:selector]) {
    union { IMP generic; void (*typed)(id, SEL, id); } method;
    method.generic = [target methodForSelector:selector];
    method.typed(target, selector, value);
  }
}
#if !TARGET_OS_IPHONE
static void AIVoid(id target, SEL selector)
{
  if ([target respondsToSelector:selector]) {
    union { IMP generic; void (*typed)(id, SEL); } method;
    method.generic = [target methodForSelector:selector];
    method.typed(target, selector);
  }
}

#endif

@interface AINativeLocalNotificationBackend : NSObject
    <AILocalNotificationBackend> {
  AILocalNotificationCenter *owner_;
}
@end

@implementation AINativeLocalNotificationBackend
- (void)setNotificationCenter:(AILocalNotificationCenter *)center;
{
  owner_ = center;
#if !TARGET_OS_IPHONE
  id native = AIObject(NSClassFromString(@"NSUserNotificationCenter"),
      @selector(defaultUserNotificationCenter));
  if (center || AIObject(native, @selector(delegate)) == self)
    AISetObject(native, @selector(setDelegate:), center ? self : nil);
#endif
}
#if TARGET_OS_IPHONE
- (unsigned int)allowedTypes;
{
  UIApplication *app = [UIApplication sharedApplication];
  SEL current = @selector(currentUserNotificationSettings);
  if (![app respondsToSelector:current]) return 7;
  id settings = AIObject(app, current);
  SEL types = @selector(types);
  if (![settings respondsToSelector:types]) return 0;
  union { IMP generic; NSUInteger (*typed)(id, SEL); } method;
  method.generic = [settings methodForSelector:types];
  return (unsigned int)method.typed(settings, types);
}
- (AINotificationAuthorizationStatus)authorizationStatus;
{
  /* No types can mean either unasked or denied on iOS 8. Do not invent a
   * distinction, or prevent the explicit registration request. */
  return [self allowedTypes] ? AINotificationAuthorizationAuthorized :
                              AINotificationAuthorizationUnknown;
}
- (void)requestAuthorization;
{
  UIApplication *app = [UIApplication sharedApplication];
  SEL reg = @selector(registerUserNotificationSettings:);
  Class cls = NSClassFromString(@"UIUserNotificationSettings");
  SEL create = @selector(settingsForTypes:categories:);
  if (![app respondsToSelector:reg] || ![cls respondsToSelector:create]) return;
  id settings = ((id (*)(id, SEL, NSUInteger, id))
      [cls methodForSelector:create])(cls, create, (NSUInteger)7, nil);
  AISetObject(app, reg, settings);
}
- (BOOL)isApplicationInBackground;
{
  return [[UIApplication sharedApplication] applicationState] ==
      UIApplicationStateBackground;
}
- (BOOL)submitTitle:(NSString *)title body:(NSString *)body
          userInfo:(NSDictionary *)userInfo;
{
  UILocalNotification *note = [[[UILocalNotification alloc] init] autorelease];
  [note setSoundName:UILocalNotificationDefaultSoundName];
  if ([title length] && [note respondsToSelector:@selector(setAlertTitle:)]) {
    AISetObject(note, @selector(setAlertTitle:), title);
    [note setAlertBody:body];
  } else {
    [note setAlertBody:[title length] ?
        [NSString stringWithFormat:@"%@: %@", title, body] : body];
  }
  [note setUserInfo:userInfo];
  /* Establish a badge even for apps with no unread-count model (Retro-DLP).
   * Foreground zero then follows the same nonzero-to-zero path as ENIL. */
  UIApplication *app = [UIApplication sharedApplication];
  if ([self allowedTypes] & 1) {
    NSInteger count = [app applicationIconBadgeNumber];
    [note setApplicationIconBadgeNumber:count > 0 ? count : 1];
  }
  [app presentLocalNotificationNow:note];
  return YES;
}
- (void)clearNotifications;
{
  [[UIApplication sharedApplication] cancelAllLocalNotifications];
}
- (void)setBadgeCount:(int)count;
{
  if ([self allowedTypes] & 1)
    [[UIApplication sharedApplication] setApplicationIconBadgeNumber:count];
}
#else
- (id)nativeCenter;
{
  return AIObject(NSClassFromString(@"NSUserNotificationCenter"),
                  @selector(defaultUserNotificationCenter));
}
- (AINotificationAuthorizationStatus)authorizationStatus;
{
  return [self nativeCenter] ? AINotificationAuthorizationUnknown :
                              AINotificationAuthorizationUnsupported;
}
- (void)requestAuthorization;
{
  /* The legacy Mac backend has no explicit permission-request API. */
}
- (BOOL)isApplicationInBackground;
{
  return ![NSApp isActive];
}
- (BOOL)submitTitle:(NSString *)title body:(NSString *)body
          userInfo:(NSDictionary *)userInfo;
{
  id center = [self nativeCenter];
  id note = [[[NSClassFromString(@"NSUserNotification") alloc] init] autorelease];
  if (!center || !note) return NO;
  AISetObject(center, @selector(setDelegate:), self);
  AISetObject(note, @selector(setTitle:), title);
  AISetObject(note, @selector(setInformativeText:), body);
  AISetObject(note, @selector(setUserInfo:), userInfo);
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 1080
  AISetObject(note, @selector(setSoundName:), NSUserNotificationDefaultSoundName);
#endif
  AISetObject(center, @selector(deliverNotification:), note);
  return YES;
}
- (BOOL)userNotificationCenter:(id)center shouldPresentNotification:(id)note;
{
  (void)center; (void)note;
  return ![NSApp isActive];
}
- (void)userNotificationCenter:(id)center didActivateNotification:(id)note;
{
  (void)center;
  [owner_ activateWithUserInfo:AIObject(note, @selector(userInfo))];
}
- (void)clearNotifications;
{
  AIVoid([self nativeCenter], @selector(removeAllDeliveredNotifications));
}
- (void)setBadgeCount:(int)count;
{
  id tile = AIObject(NSApp, @selector(dockTile));
  AISetObject(tile, @selector(setBadgeLabel:), count > 0 ?
      [NSString stringWithFormat:@"%d", count] : @"");
}
- (void)dealloc;
{
  id center = [self nativeCenter];
  if (AIObject(center, @selector(delegate)) == self)
    AISetObject(center, @selector(setDelegate:), nil);
  [super dealloc];
}
#endif
@end

id<AILocalNotificationBackend> AICreateLocalNotificationBackend(void)
{
  return [[AINativeLocalNotificationBackend alloc] init];
}
