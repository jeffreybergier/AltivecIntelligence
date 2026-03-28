#import "AICURLConnection.h"
#import <curl/curl.h>
#import <openssl/opensslv.h>
#import <openssl/crypto.h>
#import <zlib.h>
#import <objc/runtime.h>

@implementation AIHTTPURLResponse

- (id)initWithURL:(NSURL *)url
       statusCode:(NSInteger)statusCode
     headerFields:(NSDictionary *)headerFields;
{
  if ((self = [super initWithURL:url 
                        MIMEType:nil 
           expectedContentLength:-1 
                textEncodingName:nil])) {
    statusCode_ = statusCode;
    headerFields_ = [headerFields retain];
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

+ (NSString *)cryptoVersion;
{
    const char *ver = OpenSSL_version(OPENSSL_VERSION);
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
  if (cancelled_) return;
  
  // Use Tiger-compatible thread creation (10.0+)
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

  NSMutableData *receivedData = [NSMutableData data];
  curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, AISyncWriteCallback);
  curl_easy_setopt(curl, CURLOPT_WRITEDATA, (void *)receivedData);

  CURLcode res = curl_easy_perform(curl);
  
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
                                           headerFields:nil] autorelease];
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
  
  [pool release];
  // Match the retain in -start
  [self autorelease];
}

- (void)__didReceiveHeaderLine:(NSString *)headerLine;
{
  // 1. Status Line (e.g. HTTP/1.1 200 OK)
  if ([headerLine length] >= 12 && 
      ([headerLine hasPrefix:@"HTTP/1.1 "] || [headerLine hasPrefix:@"HTTP/1.0 "])) {
    int code = [[headerLine substringWithRange:NSMakeRange(9, 3)] intValue];
    pendingResponse_ = [[AIHTTPURLResponse alloc] initWithURL:[request_ URL] 
                                                   statusCode:code 
                                                 headerFields:nil];
    return;
  }
  
  // 2. Empty Line (End of Headers)
  if ([headerLine isEqualToString:@"\r\n"] || [headerLine isEqualToString:@"\n"]) {
    if (pendingResponse_ && [delegate_ respondsToSelector:@selector(connection:didReceiveResponse:)]) {
      // Create final response with accumulated headers
      AIHTTPURLResponse *finalResp = [[[AIHTTPURLResponse alloc] initWithURL:[pendingResponse_ URL] 
                                                                  statusCode:[pendingResponse_ statusCode] 
                                                                headerFields:responseHeaders_] autorelease];
      [delegate_ connection:(id)self didReceiveResponse:finalResp];
      [pendingResponse_ release];
      pendingResponse_ = nil;
    }
    return;
  }
  
  // 3. Header Fields (e.g. Content-Type: image/jpeg)
  NSRange colonRange = [headerLine rangeOfString:@":"];
  if (colonRange.location != NSNotFound) {
    NSString *key = [headerLine substringToIndex:colonRange.location];
    NSString *value = [headerLine substringFromIndex:colonRange.location + 1];
    
    // Trim whitespace
    key = [key stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
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
