// Copyright (c) 2026 Jeffrey Bergier. MIT license; see ../../LICENSE.
#import <Foundation/Foundation.h>

#ifndef AI_LOCAL_NOTIFICATION_CENTER_H
#define AI_LOCAL_NOTIFICATION_CENTER_H

/* Unknown includes legacy systems that cannot distinguish an unasked user
 * from denial. Unsupported means no system notification backend exists. */
typedef enum {
  AINotificationAuthorizationUnknown,
  AINotificationAuthorizationDenied,
  AINotificationAuthorizationAuthorized,
  AINotificationAuthorizationUnsupported
} AINotificationAuthorizationStatus;

typedef enum {
  AINotificationSubmitted,
  AINotificationSuppressed,
  AINotificationDenied,
  AINotificationUnsupported,
  AINotificationFailed
} AINotificationResult;

@class AILocalNotificationCenter;
/* Optional app routing. The delegate is borrowed; clear it before teardown. */
@protocol AILocalNotificationCenterDelegate <NSObject>
- (void)localNotificationCenter:(AILocalNotificationCenter *)center
          activatedWithUserInfo:(NSDictionary *)userInfo;
@end

/* Injection seam for offline recorders. All calls are on the main thread.
 * Submission means handed to the OS, not confirmed banner presentation. */
@protocol AILocalNotificationBackend <NSObject>
- (AINotificationAuthorizationStatus)authorizationStatus;
- (void)requestAuthorization;
- (BOOL)isApplicationInBackground;
- (BOOL)submitTitle:(NSString *)title body:(NSString *)body
          userInfo:(NSDictionary *)userInfo;
- (void)clearNotifications;
- (void)setBadgeCount:(int)count;
@optional
/* Borrowed owner for native activation; nil detaches on invalidation. */
- (void)setNotificationCenter:(AILocalNotificationCenter *)center;
@end

/* Identical Foundation API on Mac and iOS. All methods require the main
 * thread. Immediate local alerts only; no remote push or scheduling.
 * Initialize at launch. Lifecycle observation suppresses foreground alerts,
 * clears alerts/badges on activation (including cold launch), and resets the
 * badge on background entry, matching ENIL. Positive badges are background-only.
 * The native backend owns the legacy Mac notification-center delegate. */
@interface AILocalNotificationCenter : NSObject {
@private
  id<AILocalNotificationBackend> backend_;
  id<AILocalNotificationCenterDelegate> delegate_;
  BOOL background_;
  BOOL invalidated_;
}
/* Process-wide native center; initialize at app launch, not first message. */
+ (AILocalNotificationCenter *)defaultCenter;
/* Creates a native center. Prefer defaultCenter in production. */
- (id)init;
/* Retains backend. Also observes native lifecycle notifications. */
- (id)initWithBackend:(id<AILocalNotificationBackend>)backend;
/* Reports what the backend can determine; never triggers a prompt. */
- (AINotificationAuthorizationStatus)authorizationStatus;
/* Explicit prompt request; a no-op on legacy systems without prompts. */
- (void)requestAuthorization;
/* Sends only in the background. Content and routing remain app-owned.
 * userInfo must contain small property-list values; the backend copies it. */
- (AINotificationResult)postNotificationWithTitle:(NSString *)title
                                           body:(NSString *)body
                                       userInfo:(NSDictionary *)userInfo;
/* Sets a nonnegative background badge; foreground writes become zero. */
- (void)setBadgeCount:(int)count;
/* Clears app-wide alerts and badge. iOS preserves ENIL's cancel-then-zero
 * sequence; delivered-tray removal depends on the legacy OS/badge permission. */
- (void)clearNotifications;
/* Assigns the borrowed routing delegate. */
- (void)setDelegate:(id<AILocalNotificationCenterDelegate>)delegate;
/* iOS app delegates forward userInfo from cold-launch local notifications and
 * inactive didReceiveLocalNotification callbacks here. Mac forwards internally.
 * Foreground receipt is not activation. Call once per OS activation callback. */
- (void)activateWithUserInfo:(NSDictionary *)userInfo;
/* Removes observers and drops the delegate; subsequent calls have no effects. */
- (void)invalidate;
@end
#endif
