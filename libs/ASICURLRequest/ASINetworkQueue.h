// ASINetworkQueue.h
// Part of ASICURLRequest — a libcurl-backed drop-in for ASIHTTPRequest.
// Tiger-compatible: uses NSMutableArray + NSLock instead of NSOperationQueue.

#import <Foundation/Foundation.h>

@class ASIHTTPRequest;

@interface ASINetworkQueue : NSObject {
@private
  NSMutableArray *pendingRequests_;
  NSMutableArray *activeRequests_;
  NSLock *lock_;
  int maxConcurrentOperations_;
  BOOL shouldCancelAllOnFailure_;
  BOOL isGoing_;

  // Queue-level delegate (weak)
  id delegate_;
  SEL requestDidFinishSelector_;
  SEL requestDidStartSelector_;
  SEL queueDidFinishSelector_;
}

- (void)setShouldCancelAllRequestsOnFailure:(BOOL)flag;

- (void)setDelegate:(id)delegate;
- (id)delegate;
- (void)setRequestDidFinishSelector:(SEL)sel;
- (void)setRequestDidStartSelector:(SEL)sel;
- (void)setQueueDidFinishSelector:(SEL)sel;

- (void)setMaxConcurrentOperationCount:(int)count;

- (void)addOperation:(ASIHTTPRequest *)request;
- (void)go;
- (void)cancelAllOperations;

// Returns all pending + active requests as a snapshot array.
- (NSArray *)operations;
- (int)requestsCount;

// Internal — called by ASIHTTPRequest on main thread
- (void)_requestStarted:(ASIHTTPRequest *)request;
- (void)_requestFinished:(ASIHTTPRequest *)request;

@end
