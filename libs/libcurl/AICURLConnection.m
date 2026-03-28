#import "AICURLConnection.h"
#import <curl/curl.h>
#import <openssl/opensslv.h>
#import <openssl/crypto.h>
#import <zlib.h>

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
  
  [connection performSelector:@selector(__didReceiveData:) 
                     onThread:[connection __originThread] 
                   withObject:data 
                waitUntilDone:YES];
                
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
  
  [connection performSelector:@selector(__didReceiveHeaderLine:) 
                     onThread:[connection __originThread] 
                   withObject:headerLine 
                waitUntilDone:YES];
                
  return realsize;
}

@interface AICURLConnection (Private)
- (void)__workerThread:(id)unused;
- (void)__didReceiveData:(NSData *)data;
- (void)__didReceiveHeaderLine:(NSString *)headerLine;
- (NSThread *)__originThread;
@end

@implementation AICURLConnection

#pragma mark - Class Properties

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
    originThread_ = [[NSThread currentThread] retain];
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
  [originThread_ release];
  if (thread_) {
    [thread_ cancel];
    [thread_ release];
  }
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
  
  thread_ = [[NSThread alloc] initWithTarget:self 
                                    selector:@selector(__workerThread:) 
                                      object:nil];
  [thread_ start];
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

- (NSThread *)__originThread; { return originThread_; }

- (void)__workerThread:(id)unused;
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  curl_easy_setopt(curl_, CURLOPT_URL, [[[request_ URL] absoluteString] UTF8String]);
  curl_easy_setopt(curl_, CURLOPT_WRITEFUNCTION, AIWriteCallback);
  curl_easy_setopt(curl_, CURLOPT_WRITEDATA, self);
  curl_easy_setopt(curl_, CURLOPT_HEADERFUNCTION, AIHeaderCallback);
  curl_easy_setopt(curl_, CURLOPT_HEADERDATA, self);
  
  CURLcode res = curl_easy_perform(curl_);
  
  if (!cancelled_) {
    if (res != CURLE_OK) {
      NSError *error = [NSError errorWithDomain:@"AICURLConnectionErrorDomain" 
                                           code:res 
                                       userInfo:nil];
      [self performSelector:@selector(__didFailWithError:) 
                   onThread:originThread_ 
                 withObject:error 
              waitUntilDone:YES];
    } else {
      [self performSelector:@selector(__didFinishLoading) 
                   onThread:originThread_ 
                 withObject:nil 
              waitUntilDone:YES];
    }
  }
  
  [pool release];
}

- (void)__didReceiveHeaderLine:(NSString *)headerLine;
{
  if ([headerLine hasPrefix:@"HTTP/1.1 "] || [headerLine hasPrefix:@"HTTP/1.0 "]) {
    int code = [[headerLine substringWithRange:NSMakeRange(9, 3)] intValue];
    AIHTTPURLResponse *resp = [[[AIHTTPURLResponse alloc] initWithURL:[request_ URL] 
                                                           statusCode:code 
                                                         headerFields:nil] autorelease];
    if ([delegate_ respondsToSelector:@selector(connection:didReceiveResponse:)]) {
      [delegate_ connection:(id)self didReceiveResponse:resp];
    }
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
  CURL *curl = (CURL *)handle;
  curl_easy_cleanup(curl);
}

@end
