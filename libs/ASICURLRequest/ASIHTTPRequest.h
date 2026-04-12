// ASIHTTPRequest.h
// Part of ASICURLRequest — a libcurl-backed drop-in for ASIHTTPRequest.
// Tiger-compatible (10.4+). No GCD, no blocks, no NSOperationQueue.

#import <Foundation/Foundation.h>
#import "ASIHTTPRequestConfig.h"
#import "ASIHTTPRequestDelegate.h"

@class ASINetworkQueue;

@interface ASIHTTPRequest : NSObject {
@protected
  NSURL *url_;
  NSURL *originalURL_;
  id delegate_;                   // weak
  SEL didFinishSelector_;
  SEL didFailSelector_;
  NSMutableDictionary *requestHeaders_;
  NSDictionary *userInfo_;

  // Response
  NSMutableData *responseData_;
  NSMutableDictionary *responseHeaders_;
  int responseStatusCode_;
  NSError *error_;

  // POST (set by ASIFormDataRequest subclass)
  NSData *postBody_;

  // Config
  int timeoutSeconds_;
  BOOL useCookiePersistence_;
  BOOL cancelled_;
  BOOL isExecuting_;

  // Back-reference to owning queue (weak)
  ASINetworkQueue *queue_;
}

// Factory / init
+ (id)requestWithURL:(NSURL *)url;
- (id)initWithURL:(NSURL *)url;

// Subclass hook — override to modify request before curl runs
- (void)_runCurl;

// Request headers
- (void)addRequestHeader:(NSString *)header value:(NSString *)value;
- (NSMutableDictionary *)requestHeaders;
- (void)setRequestHeaders:(NSMutableDictionary *)headers;

// Config
- (void)setUseCookiePersistence:(BOOL)use;
- (void)setTimeOutSeconds:(int)seconds;

// Delegate & selectors
- (void)setDelegate:(id)delegate;
- (id)delegate;
- (void)setDidFinishSelector:(SEL)sel;
- (void)setDidFailSelector:(SEL)sel;

// User info
- (void)setUserInfo:(NSDictionary *)info;
- (NSDictionary *)userInfo;

// Execution
- (void)startSynchronous;
- (void)startAsync;
- (void)clearDelegatesAndCancel;
- (void)cancel;

// Response accessors
- (int)responseStatusCode;
- (NSData *)responseData;
- (NSString *)responseString;
- (NSDictionary *)responseHeaders;
- (NSURL *)url;
- (NSURL *)originalURL;
- (NSError *)error;
- (NSData *)postBody;

// Internal — used by ASINetworkQueue
- (void)setQueue:(ASINetworkQueue *)queue;
- (ASINetworkQueue *)queue;

@end
