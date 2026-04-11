#import "AICURLConnection.h"
#import <curl/curl.h>
#import <openssl/opensslv.h>
#import <openssl/crypto.h>
#import <zlib.h>
#import <objc/runtime.h>

@implementation AIHTTPURLResponse

- (id)initWithURL:(NSURL *)url
       statusCode:(NSInteger)statusCode
     headerFields:(NSDictionary *)headerFields
expectedContentLength:(long long)expectedContentLength;
{
  NSString *mimeType = [headerFields objectForKey:@"Content-Type"];
  
  // We call the base NSURLResponse initializer to stay safe on Tiger.
  if ((self = [super initWithURL:url 
                        MIMEType:mimeType 
           expectedContentLength:(NSInteger)expectedContentLength 
                textEncodingName:nil])) {
    statusCode_ = statusCode;
    headerFields_ = [headerFields retain];
    expectedContentLength_ = expectedContentLength;
  }
  return self;
}

+ (NSString *)localizedStringForStatusCode:(NSInteger)statusCode;
{
  return [NSHTTPURLResponse localizedStringForStatusCode:statusCode];
}

- (void)dealloc;
{
  [headerFields_ release];
  [super dealloc];
}

- (NSInteger)statusCode;
{
  return statusCode_;
}

- (NSDictionary *)allHeaderFields;
{
  return headerFields_;
}

- (long long)expectedContentLength;
{
  return expectedContentLength_;
}

@end

#pragma mark - CURL Callbacks (Internal)

static size_t AISyncWriteCallback(void *contents, 
                                  size_t size, 
                                  size_t nmemb, 
                                  void *userp) {
  size_t realsize = size * nmemb;
  NSMutableData *data = (NSMutableData *)userp;
  [data appendBytes:contents length:realsize];
  return realsize;
}

static size_t AIWriteCallback(void *contents, 
                              size_t size, 
                              size_t nmemb, 
                              void *userp) {
  size_t realsize = size * nmemb;
  AICURLConnection *connection = (AICURLConnection *)userp;
  NSData *data = [NSData dataWithBytes:contents length:realsize];
  
  [connection performSelectorOnMainThread:@selector(__didReceiveData:) 
                               withObject:data 
                            waitUntilDone:NO];
                
  return realsize;
}

static size_t AIHeaderCallback(void *contents, 
                               size_t size, 
                               size_t nmemb, 
                               void *userp) {
  size_t realsize = size * nmemb;
  AICURLConnection *connection = (AICURLConnection *)userp;
  NSString *headerLine = [[[NSString alloc] initWithBytes:contents 
                                                   length:realsize 
                                                 encoding:NSUTF8StringEncoding] autorelease];
  
  if (headerLine) {
    [connection performSelectorOnMainThread:@selector(__didReceiveHeaderLine:) 
                                 withObject:headerLine 
                              waitUntilDone:NO];
  }
                
  return realsize;
}

@interface AICURLConnection (Private)
- (void)__workerThread:(id)unused;
- (void)__didReceiveData:(NSData *)data;
- (void)__didReceiveHeaderLine:(NSString *)headerLine;
- (void)__didFailWithError:(NSError *)error;
- (void)__didFinishLoading;
@end

@implementation AICURLConnection

#pragma mark - Class Properties

+ (AICURLConnection *)connectionWithRequest:(NSURLRequest *)request 
                                   delegate:(id)delegate;
{
  return [[[AICURLConnection alloc] initWithRequest:request 
                                           delegate:delegate] autorelease];
}

+ (BOOL)canHandleRequest:(NSURLRequest *)request;
{
  NSString *scheme = [[[request URL] scheme] lowercaseString];
  return [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"];
}

+ (NSString *)zlibVersion;
{
    const char *ver = zlibVersion();
    return [NSString stringWithUTF8String:ver];
}

+ (NSString *)sslVersion;
{
    const char *ver = OpenSSL_version(OPENSSL_VERSION);
    return [NSString stringWithUTF8String:ver];
}

+ (NSString *)curlVersion;
{
    const char *ver = curl_version();
    return [NSString stringWithUTF8String:ver];
}

+ (NSString *)certPath;
{
  NSString *certPath = [[NSBundle mainBundle] pathForResource:@"cacert" 
                                                       ofType:@"pem"];
  NSParameterAssert(certPath);
  return certPath;
}

#pragma mark - Initializers

+ (void)initialize;
{
  if (self == [AICURLConnection class]) {
    curl_global_init(CURL_GLOBAL_ALL);
    // Ensure cert path exists early to catch bundling errors
    [self certPath];
  }
}

- (id)initWithRequest:(NSURLRequest *)request
             delegate:(id)delegate;
{
  return [self initWithRequest:request delegate:delegate startImmediately:YES];
}

- (id)initWithRequest:(NSURLRequest *)request
             delegate:(id)delegate
     startImmediately:(BOOL)startImmediately;
{
  if ((self = [super init])) {
    request_ = [request retain];
    delegate_ = [delegate retain];
    responseHeaders_ = [[NSMutableDictionary alloc] init];
    curl_ = curl_easy_init();
    totalExpectedLength_ = -1;
    
    if (!curl_) {
      [self release];
      return nil;
    }
    
    [self __newCURLHandle:curl_];
    
    if (startImmediately) {
      [self start];
    }
  }
  return self;
}

- (void)dealloc;
{
  [request_ release];
  [delegate_ release];
  [responseHeaders_ release];
  [pendingResponse_ release];
  if (curl_) {
    [self __releaseCURLHandle:curl_];
    curl_ = NULL;
  }
  [super dealloc];
}

#pragma mark - Lifecycle

- (void)start;
{
  if (!delegate_) {
    [NSException raise:NSInvalidArgumentException 
                format:@"[AICURLConnection start] Cannot start an asynchronous "
                       @"request without a delegate."];
  }
  if (thread_ || cancelled_) return;
  
  [self retain];
  [NSThread detachNewThreadSelector:@selector(__workerThread:) 
                           toTarget:self 
                         withObject:nil];
}

- (void)cancel;
{
  cancelled_ = YES;
}

#pragma mark - Shared Request (Sync)

+ (NSData *)sendSynchronousRequest:(NSURLRequest *)request
                 returningResponse:(NSURLResponse **)response
                             error:(NSError **)error;
{
  CURL *curl = curl_easy_init();
  if (!curl) {
    if (error) {
      *error = [NSError errorWithDomain:@"AICURLConnectionErrorDomain" 
                                   code:0 
                               userInfo:nil];
    }
    return nil;
  }

  curl_easy_setopt(curl, CURLOPT_URL, [[[request URL] absoluteString] UTF8String]);
  NSString *certPath = [self certPath];
  curl_easy_setopt(curl, CURLOPT_CAINFO, [certPath UTF8String]);
  curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);

  // Set HTTP method and body from the NSURLRequest
  NSData *body = [request HTTPBody];
  if (body && [body length] > 0) {
    curl_easy_setopt(curl, CURLOPT_POST, 1L);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, [body bytes]);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, (long)[body length]);
  }

  // Forward request headers
  struct curl_slist *headers = NULL;
  NSDictionary *reqHeaders = [request allHTTPHeaderFields];
  NSEnumerator *keyEnum = [reqHeaders keyEnumerator];
  NSString *key;
  while ((key = [keyEnum nextObject])) {
    NSString *line = [NSString stringWithFormat:@"%@: %@", key, [reqHeaders objectForKey:key]];
    headers = curl_slist_append(headers, [line UTF8String]);
  }
  if (headers)
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);

  NSMutableData *receivedData = [NSMutableData data];
  curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, AISyncWriteCallback);
  curl_easy_setopt(curl, CURLOPT_WRITEDATA, (void *)receivedData);

  CURLcode res = curl_easy_perform(curl);
  if (headers)
    curl_slist_free_all(headers);
  
  if (res != CURLE_OK) {
    if (error) {
      NSString *errorMsg = [NSString stringWithUTF8String:curl_easy_strerror(res)];
      NSDictionary *userInfo = [NSDictionary dictionaryWithObject:errorMsg 
                                                           forKey:NSLocalizedDescriptionKey];
      *error = [NSError errorWithDomain:@"AICURLConnectionErrorDomain" 
                                   code:res 
                               userInfo:userInfo];
    }
    curl_easy_cleanup(curl);
    return nil;
  }

  if (response) {
    long responseCode;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &responseCode);
    *response = [[[AIHTTPURLResponse alloc] initWithURL:[request URL]
                                             statusCode:responseCode
                                           headerFields:nil
                                  expectedContentLength:-1] autorelease];
  }

  curl_easy_cleanup(curl);
  return receivedData;
}

#pragma mark - Private Internal Methods

- (void)__workerThread:(id)unused;
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSLog(@"[AICURLConnection __workerThread:] Starting transfer for: %@", 
        [request_ URL]);

  curl_easy_setopt(curl_, CURLOPT_URL, [[[request_ URL] absoluteString] UTF8String]);
  curl_easy_setopt(curl_, CURLOPT_WRITEFUNCTION, AIWriteCallback);
  curl_easy_setopt(curl_, CURLOPT_WRITEDATA, self);
  curl_easy_setopt(curl_, CURLOPT_HEADERFUNCTION, AIHeaderCallback);
  curl_easy_setopt(curl_, CURLOPT_HEADERDATA, self);
  curl_easy_setopt(curl_, CURLOPT_NOSIGNAL, 1L);
  
  CURLcode res = curl_easy_perform(curl_);
  
  NSLog(@"[AICURLConnection __workerThread:] Transfer finished with code: %d", res);

  if (!cancelled_) {
    if (res != CURLE_OK) {
      NSString *errorMsg = [NSString stringWithUTF8String:curl_easy_strerror(res)];
      NSDictionary *userInfo = [NSDictionary dictionaryWithObject:errorMsg 
                                                           forKey:NSLocalizedDescriptionKey];
      NSError *error = [NSError errorWithDomain:@"AICURLConnectionErrorDomain" 
                                           code:res 
                                       userInfo:userInfo];
      [self performSelectorOnMainThread:@selector(__didFailWithError:) 
                             withObject:error 
                          waitUntilDone:NO];
    } else {
      [self performSelectorOnMainThread:@selector(__didFinishLoading) 
                             withObject:nil 
                          waitUntilDone:NO];
    }
  }
  
  [self autorelease];
  [pool release];
}

- (void)__didReceiveHeaderLine:(NSString *)headerLine;
{
  if ([headerLine length] >= 12 && 
      ([headerLine hasPrefix:@"HTTP/1.1 "] || [headerLine hasPrefix:@"HTTP/1.0 "])) {
    int code = [[headerLine substringWithRange:NSMakeRange(9, 3)] intValue];
    pendingResponse_ = [[AIHTTPURLResponse alloc] initWithURL:[request_ URL] 
                                                   statusCode:code 
                                                 headerFields:nil
                                        expectedContentLength:-1];
    return;
  }
  
  if ([headerLine isEqualToString:@"\r\n"] || [headerLine isEqualToString:@"\n"]) {
    if (pendingResponse_ && [delegate_ respondsToSelector:@selector(connection:didReceiveResponse:)]) {
      AIHTTPURLResponse *finalResp = [[[AIHTTPURLResponse alloc] initWithURL:[pendingResponse_ URL] 
                                                                  statusCode:[pendingResponse_ statusCode] 
                                                                headerFields:responseHeaders_
                                                       expectedContentLength:totalExpectedLength_] autorelease];
      [delegate_ connection:(id)self didReceiveResponse:finalResp];
      [pendingResponse_ release];
      pendingResponse_ = nil;
    }
    return;
  }
  
  NSRange colonRange = [headerLine rangeOfString:@":"];
  if (colonRange.location != NSNotFound) {
    NSString *key = [headerLine substringToIndex:colonRange.location];
    NSString *value = [headerLine substringFromIndex:colonRange.location + 1];
    key = [key stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    if ([[key lowercaseString] isEqualToString:@"content-length"]) {
      totalExpectedLength_ = atoll([value UTF8String]);
    }
    
    [responseHeaders_ setObject:value forKey:key];
  }
}

- (void)__didReceiveData:(NSData *)data;
{
  if (!cancelled_ && [delegate_ respondsToSelector:@selector(connection:didReceiveData:)]) {
    [delegate_ connection:(id)self didReceiveData:data];
  }
}

- (void)__didFailWithError:(NSError *)error;
{
  if (!cancelled_ && [delegate_ respondsToSelector:@selector(connection:didFailWithError:)]) {
    [delegate_ connection:(id)self didFailWithError:error];
  }
}

- (void)__didFinishLoading;
{
  if (!cancelled_ && [delegate_ respondsToSelector:@selector(connectionDidFinishLoading:)]) {
    [delegate_ connectionDidFinishLoading:(id)self];
  }
}

- (void)__newCURLHandle:(void *)handle;
{
  CURL *curl = (CURL *)handle;
  NSString *certPath = [[self class] certPath];
  curl_easy_setopt(curl, CURLOPT_CAINFO, [certPath UTF8String]);
}

- (void)__releaseCURLHandle:(void *)handle;
{
  CURL *curl = (id)handle;
  curl_easy_cleanup(curl);
}

@end
