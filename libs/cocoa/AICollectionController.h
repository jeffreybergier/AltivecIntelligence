#ifndef AICOLLECTIONCONTROLLER_H
#define AICOLLECTIONCONTROLLER_H
// Copyright (c) 2026 Jeffrey Bergier. MIT license; see ../../LICENSE.
#import <Foundation/Foundation.h>
@class AICollectionSnapshot;

/* request: runs builders on a serialized worker. Direct buildResultForRequest:
 * uses the calling thread. Requests contain immutable model inputs, never UI
 * objects. Asynchronous results are delivered on the main thread. */
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
  id pending_;
  unsigned long generation_;
  BOOL working_, invalid_, scheduled_;
}
/* selector receives one builder result. Construction/lifecycle are main-only. */
- (id)initWithTarget:(id)target selector:(SEL)selector builder:(Class)builder;
/* Coalesces requests in this run-loop turn; copies the request dictionary. */
- (void)request:(NSDictionary *)request;
/* Call in the main-thread result selector BEFORE publishing the new model.
 * Maps result snapshot keys to the adapter's currently applied snapshots
 * (NSNull for no previous snapshot). YES defers publication: this controller
 * computes only the diffs on its worker, then redelivers the same result.
 * NO means prepared or initial; publish the model and apply snapshots together.
 * New requests/cancel/invalidate also supersede pending diff work. */
- (BOOL)prepareResult:(NSDictionary *)result
   previousSnapshots:(NSDictionary *)previous;
/* Convenience for a result containing one collection snapshot. */
- (BOOL)prepareResult:(NSDictionary *)result
         snapshotKey:(NSString *)key
    previousSnapshot:(AICollectionSnapshot *)previous;
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
/* Builds directly on the calling thread; also used for synchronous initial
 * loading. Subclasses may translate domain errors. Does not deliver a result. */
- (id)buildResultForRequest:(NSDictionary *)request;
@end

#endif
