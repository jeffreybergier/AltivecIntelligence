// ASINetworkQueue.m
// Part of ASICURLRequest — a libcurl-backed drop-in for ASIHTTPRequest.

#import "ASINetworkQueue.h"
#import "ASIHTTPRequest.h"

@interface ASINetworkQueue (Private)
- (void)_drainQueue;
@end

@implementation ASINetworkQueue

- (id)init;
{
  if ((self = [super init]) != nil) {
    pendingRequests_ = [[NSMutableArray alloc] init];
    activeRequests_  = [[NSMutableArray alloc] init];
    lock_ = [[NSLock alloc] init];
    maxConcurrentOperations_ = 4;
    shouldCancelAllOnFailure_ = NO;
    isGoing_ = NO;
  }
  return self;
}

- (void)dealloc;
{
  [pendingRequests_ release];
  [activeRequests_ release];
  [lock_ release];
  [super dealloc];
}

// ---------------------------------------------------------------------------
#pragma mark - Config

- (void)setShouldCancelAllRequestsOnFailure:(BOOL)flag;
{
  shouldCancelAllOnFailure_ = flag;
}

- (void)setDelegate:(id)delegate;
{
  delegate_ = delegate; // weak
}

- (id)delegate;
{
  return delegate_;
}

- (void)setRequestDidFinishSelector:(SEL)sel;
{
  requestDidFinishSelector_ = sel;
}

- (void)setRequestDidStartSelector:(SEL)sel;
{
  requestDidStartSelector_ = sel;
}

- (void)setQueueDidFinishSelector:(SEL)sel;
{
  queueDidFinishSelector_ = sel;
}

- (void)setMaxConcurrentOperationCount:(int)count;
{
  maxConcurrentOperations_ = (count > 0) ? count : 1;
}

// ---------------------------------------------------------------------------
#pragma mark - Queue operations

- (void)addOperation:(ASIHTTPRequest *)request;
{
  [request setQueue:self];
  [lock_ lock];
  [pendingRequests_ addObject:request];
  [lock_ unlock];

  if (isGoing_)
    [self _drainQueue];
}

- (void)go;
{
  isGoing_ = YES;
  [self _drainQueue];
}

- (void)cancelAllOperations;
{
  [lock_ lock];
  NSArray *active  = [[activeRequests_ copy] autorelease];
  NSArray *pending = [[pendingRequests_ copy] autorelease];
  [pendingRequests_ removeAllObjects];
  [lock_ unlock];

  NSEnumerator *e = [active objectEnumerator];
  ASIHTTPRequest *req;
  while ((req = [e nextObject]))
    [req cancel];

  e = [pending objectEnumerator];
  while ((req = [e nextObject]))
    [req cancel];
}

- (NSArray *)operations;
{
  [lock_ lock];
  NSMutableArray *all = [NSMutableArray arrayWithCapacity:
                         [pendingRequests_ count] + [activeRequests_ count]];
  [all addObjectsFromArray:activeRequests_];
  [all addObjectsFromArray:pendingRequests_];
  [lock_ unlock];
  return all;
}

- (int)requestsCount;
{
  [lock_ lock];
  int count = (int)([pendingRequests_ count] + [activeRequests_ count]);
  [lock_ unlock];
  return count;
}

// ---------------------------------------------------------------------------
#pragma mark - Internal drain (called on main thread or from addOperation:)

- (void)_drainQueue;
{
  [lock_ lock];
  while ((int)[activeRequests_ count] < maxConcurrentOperations_
         && [pendingRequests_ count] > 0) {
    ASIHTTPRequest *next = [[[pendingRequests_ objectAtIndex:0] retain] autorelease];
    [pendingRequests_ removeObjectAtIndex:0];
    [activeRequests_ addObject:next];
    [lock_ unlock];
    [next startAsync];
    [lock_ lock];
  }
  [lock_ unlock];
}

// ---------------------------------------------------------------------------
#pragma mark - Callbacks from ASIHTTPRequest (always on main thread)

- (void)_requestStarted:(ASIHTTPRequest *)request;
{
  if (delegate_ && requestDidStartSelector_
      && [delegate_ respondsToSelector:requestDidStartSelector_])
    [delegate_ performSelector:requestDidStartSelector_ withObject:request];
}

- (void)_requestFinished:(ASIHTTPRequest *)request;
{
  [lock_ lock];
  [activeRequests_ removeObject:request];
  NSUInteger remaining = [pendingRequests_ count] + [activeRequests_ count];
  [lock_ unlock];

  if (delegate_ && requestDidFinishSelector_
      && [delegate_ respondsToSelector:requestDidFinishSelector_])
    [delegate_ performSelector:requestDidFinishSelector_ withObject:request];

  if (remaining == 0) {
    isGoing_ = NO;
    if (delegate_ && queueDidFinishSelector_
        && [delegate_ respondsToSelector:queueDidFinishSelector_])
      [delegate_ performSelector:queueDidFinishSelector_ withObject:request];
  } else {
    [self _drainQueue];
  }
}

@end
