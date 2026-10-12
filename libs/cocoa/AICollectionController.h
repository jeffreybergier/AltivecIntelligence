#ifndef AICOLLECTIONCONTROLLER_H
#define AICOLLECTIONCONTROLLER_H
// Copyright (c) 2026 Jeffrey Bergier. MIT license; see ../../LICENSE.
#import <Foundation/Foundation.h>

/* Builders run on a serialized worker. Requests must contain immutable model
 * inputs, never UI objects. Results are delivered on the main thread. */
@protocol AICollectionBuilder
+ (id)buildList:(NSDictionary *)request;
@end

/* Latest-request collection loading. The target is borrowed; invalidate before
 * destroying it. The builder class is process-lived. At most one active build,
 * one pending request, and one queued delivery exist. No UI-thread joins. */
@interface AICollectionController : NSObject {
@protected
  Class builder_;
@private
  id target_;
  SEL selector_;
  NSLock *lock_;
  NSDictionary *pending_;
  unsigned long generation_;
  BOOL working_, invalid_, scheduled_;
}
/* selector receives one builder result. Construction/lifecycle are main-only. */
- (id)initWithTarget:(id)target selector:(SEL)selector builder:(Class)builder;
/* Coalesces requests in this run-loop turn; copies the request dictionary. */
- (void)request:(NSDictionary *)request;
/* Cancels pending work/delivery without waiting; the controller is reusable. */
- (void)cancel;
/* Permanently detaches the borrowed target and cancels pending work. */
- (void)invalidate;
/* Worker-safe cooperative cancellation, also true after a newer request. */
- (BOOL)isCancelled;
/* Main/worker-safe; includes queued delivery. */
- (BOOL)isLoading;
/* Current worker controller, or nil outside a collection build. */
+ (AICollectionController *)currentController;
/* Subclasses may translate domain errors; called on the worker only. */
- (id)buildResultForRequest:(NSDictionary *)request;
@end

#endif
