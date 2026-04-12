// ASIHTTPRequest.m
// Part of ASICURLRequest — a libcurl-backed drop-in for ASIHTTPRequest.

#import "ASIHTTPRequest.h"
#import "ASINetworkQueue.h"
#import <curl/curl.h>

NSString * const ASIHTTPRequestErrorDomain = @"ASIHTTPRequestErrorDomain";

// ---------------------------------------------------------------------------
#pragma mark - curl write callbacks (called on worker thread)

static size_t asi_body_callback(void *ptr, size_t size, size_t nmemb, void *userp)
{
  size_t bytes = size * nmemb;
  NSMutableData *data = (NSMutableData *)userp;
  [data appendBytes:ptr length:bytes];
  return bytes;
}

static size_t asi_header_callback(void *ptr, size_t size, size_t nmemb, void *userp)
{
  size_t bytes = size * nmemb;
  NSMutableDictionary *headers = (NSMutableDictionary *)userp;
  NSString *line = [[[NSString alloc] initWithBytes:ptr
                                             length:bytes
                                           encoding:NSUTF8StringEncoding] autorelease];
  if (!line)
    return bytes;
  NSRange colon = [line rangeOfString:@":"];
  if (colon.location == NSNotFound)
    return bytes;
  NSString *key = [[line substringToIndex:colon.location]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
  NSString *val = [[line substringFromIndex:colon.location + 1]
      stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if ([key length])
    [headers setObject:val forKey:key];
  return bytes;
}

// ---------------------------------------------------------------------------
#pragma mark - Private interface

@interface ASIHTTPRequest (Private)
- (void)_performRequest:(id)unused;
- (void)_notifyFinished;
- (void)_notifyFailed;
@end

// ---------------------------------------------------------------------------
#pragma mark - Implementation

@implementation ASIHTTPRequest

+ (id)requestWithURL:(NSURL *)url;
{
  return [[[self alloc] initWithURL:url] autorelease];
}

- (id)initWithURL:(NSURL *)url;
{
  if ((self = [super init]) != nil) {
    url_ = [url retain];
    originalURL_ = [url retain];
    requestHeaders_ = [[NSMutableDictionary alloc] init];
    timeoutSeconds_ = 60;
    useCookiePersistence_ = NO;
    cancelled_ = NO;
    isExecuting_ = NO;
  }
  return self;
}

- (void)dealloc;
{
  [url_ release];
  [originalURL_ release];
  [requestHeaders_ release];
  [userInfo_ release];
  [responseData_ release];
  [responseHeaders_ release];
  [error_ release];
  [postBody_ release];
  [super dealloc];
}

// ---------------------------------------------------------------------------
#pragma mark - Request headers

- (void)addRequestHeader:(NSString *)header value:(NSString *)value;
{
  if (header && value)
    [requestHeaders_ setObject:value forKey:header];
}

- (NSMutableDictionary *)requestHeaders;
{
  return requestHeaders_;
}

- (void)setRequestHeaders:(NSMutableDictionary *)headers;
{
  [requestHeaders_ release];
  requestHeaders_ = [headers retain];
}

// ---------------------------------------------------------------------------
#pragma mark - Config

- (void)setUseCookiePersistence:(BOOL)use;
{
  useCookiePersistence_ = use;
}

- (void)setTimeOutSeconds:(int)seconds;
{
  timeoutSeconds_ = seconds;
}

// ---------------------------------------------------------------------------
#pragma mark - Delegate & selectors

- (void)setDelegate:(id)delegate;
{
  delegate_ = delegate; // weak — never retained
}

- (id)delegate;
{
  return delegate_;
}

- (void)setDidFinishSelector:(SEL)sel;
{
  didFinishSelector_ = sel;
}

- (void)setDidFailSelector:(SEL)sel;
{
  didFailSelector_ = sel;
}

// ---------------------------------------------------------------------------
#pragma mark - User info

- (void)setUserInfo:(NSDictionary *)info;
{
  [userInfo_ release];
  userInfo_ = [info retain];
}

- (NSDictionary *)userInfo;
{
  return userInfo_;
}

// ---------------------------------------------------------------------------
#pragma mark - Queue back-reference

- (void)setQueue:(ASINetworkQueue *)queue;
{
  queue_ = queue; // weak
}

- (ASINetworkQueue *)queue;
{
  return queue_;
}

// ---------------------------------------------------------------------------
#pragma mark - Core curl execution (runs on any thread)

- (void)_runCurl;
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

  [responseData_ release];
  responseData_ = [[NSMutableData alloc] init];
  [responseHeaders_ release];
  responseHeaders_ = [[NSMutableDictionary alloc] init];
  responseStatusCode_ = 0;
  [error_ release];
  error_ = nil;

  CURL *curl = curl_easy_init();
  if (!curl) {
    error_ = [[NSError errorWithDomain:ASIHTTPRequestErrorDomain
                                  code:ASIUnableToCreateRequestError
                              userInfo:nil] retain];
    [pool drain];
    return;
  }

  NSString *urlString = [url_ absoluteString];
  curl_easy_setopt(curl, CURLOPT_URL, [urlString UTF8String]);
  curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
  curl_easy_setopt(curl, CURLOPT_MAXREDIRS, 10L);
  curl_easy_setopt(curl, CURLOPT_TIMEOUT, (long)timeoutSeconds_);
  curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);

  // CA bundle — same path used by AICURLConnection
  NSString *certPath = [[NSBundle mainBundle] pathForResource:@"cacert" ofType:@"pem"];
  if (certPath)
    curl_easy_setopt(curl, CURLOPT_CAINFO, [certPath UTF8String]);

  // Body accumulator
  curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, asi_body_callback);
  curl_easy_setopt(curl, CURLOPT_WRITEDATA, responseData_);

  // Header accumulator
  curl_easy_setopt(curl, CURLOPT_HEADERFUNCTION, asi_header_callback);
  curl_easy_setopt(curl, CURLOPT_HEADERDATA, responseHeaders_);

  // POST body
  if (postBody_ && [postBody_ length] > 0) {
    curl_easy_setopt(curl, CURLOPT_POST, 1L);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, [postBody_ bytes]);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, (long)[postBody_ length]);
  }

  // Request headers
  struct curl_slist *curlHeaders = NULL;
  NSEnumerator *keyEnum = [requestHeaders_ keyEnumerator];
  NSString *key;
  while ((key = [keyEnum nextObject])) {
    NSString *line = [NSString stringWithFormat:@"%@: %@",
                      key, [requestHeaders_ objectForKey:key]];
    curlHeaders = curl_slist_append(curlHeaders, [line UTF8String]);
  }
  if (curlHeaders)
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, curlHeaders);

  CURLcode res = CURLE_OK;
  if (!cancelled_)
    res = curl_easy_perform(curl);

  if (curlHeaders)
    curl_slist_free_all(curlHeaders);

  if (cancelled_) {
    error_ = [[NSError errorWithDomain:ASIHTTPRequestErrorDomain
                                  code:ASIRequestCancelledErrorType
                              userInfo:nil] retain];
  } else if (res != CURLE_OK) {
    int code = (res == CURLE_OPERATION_TIMEDOUT) ? ASIRequestTimedOutErrorType
                                                 : ASIConnectionFailureErrorType;
    NSString *msg = [NSString stringWithUTF8String:curl_easy_strerror(res)];
    NSDictionary *info = [NSDictionary dictionaryWithObject:msg
                                                     forKey:NSLocalizedDescriptionKey];
    error_ = [[NSError errorWithDomain:ASIHTTPRequestErrorDomain
                                  code:code
                              userInfo:info] retain];
  } else {
    long httpCode = 0;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &httpCode);
    responseStatusCode_ = (int)httpCode;

    // Check for HTTP 401
    if (httpCode == 401) {
      NSDictionary *info = [NSDictionary dictionaryWithObject:@"Authentication required"
                                                       forKey:NSLocalizedDescriptionKey];
      error_ = [[NSError errorWithDomain:ASIHTTPRequestErrorDomain
                                    code:ASIAuthenticationErrorType
                                userInfo:info] retain];
    }

    // Follow redirect URL
    char *effectiveURL = NULL;
    curl_easy_getinfo(curl, CURLINFO_EFFECTIVE_URL, &effectiveURL);
    if (effectiveURL) {
      [url_ release];
      url_ = [[NSURL URLWithString:[NSString stringWithUTF8String:effectiveURL]] retain];
    }
  }

  curl_easy_cleanup(curl);
  [pool drain];
}

// ---------------------------------------------------------------------------
#pragma mark - Execution

- (void)startSynchronous;
{
  [self _runCurl];
}

- (void)_performRequest:(id)unused;
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  isExecuting_ = YES;

  if (queue_)
    [queue_ performSelectorOnMainThread:@selector(_requestStarted:)
                             withObject:self
                          waitUntilDone:NO];

  [self _runCurl];
  isExecuting_ = NO;

  if (error_)
    [self performSelectorOnMainThread:@selector(_notifyFailed)
                           withObject:nil
                        waitUntilDone:NO];
  else
    [self performSelectorOnMainThread:@selector(_notifyFinished)
                           withObject:nil
                        waitUntilDone:NO];

  [pool drain];
}

- (void)startAsync;
{
  [NSThread detachNewThreadSelector:@selector(_performRequest:)
                           toTarget:self
                         withObject:nil];
}

- (void)clearDelegatesAndCancel;
{
  delegate_ = nil;
  didFinishSelector_ = NULL;
  didFailSelector_ = NULL;
  cancelled_ = YES;
}

- (void)cancel;
{
  cancelled_ = YES;
}

// ---------------------------------------------------------------------------
#pragma mark - Main-thread callbacks

- (void)_notifyFinished;
{
  if (delegate_) {
    SEL sel = didFinishSelector_ ? didFinishSelector_ : @selector(requestFinished:);
    if ([delegate_ respondsToSelector:sel])
      [delegate_ performSelector:sel withObject:self];
  }
  if (queue_)
    [queue_ _requestFinished:self];
}

- (void)_notifyFailed;
{
  if (delegate_) {
    SEL sel = didFailSelector_ ? didFailSelector_ : @selector(requestFailed:);
    if ([delegate_ respondsToSelector:sel])
      [delegate_ performSelector:sel withObject:self];
  }
  if (queue_)
    [queue_ _requestFinished:self];
}

// ---------------------------------------------------------------------------
#pragma mark - Response accessors

- (int)responseStatusCode;
{
  return responseStatusCode_;
}

- (NSData *)responseData;
{
  return responseData_;
}

- (NSString *)responseString;
{
  if (!responseData_)
    return nil;
  return [[[NSString alloc] initWithData:responseData_
                                encoding:NSUTF8StringEncoding] autorelease];
}

- (NSDictionary *)responseHeaders;
{
  return responseHeaders_;
}

- (NSURL *)url;
{
  return url_;
}

- (NSURL *)originalURL;
{
  return originalURL_;
}

- (NSError *)error;
{
  return error_;
}

- (NSData *)postBody;
{
  return postBody_;
}

@end
