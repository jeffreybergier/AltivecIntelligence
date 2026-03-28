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
  // We call the base NSURLResponse initializer to stay safe on Tiger.
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

static size_t AIWriteCallback(void *contents, 
                              size_t size, 
                              size_t nmemb, 
                              void *userp) {
  size_t realsize = size * nmemb;
  NSMutableData *data = (NSMutableData *)userp;
  [data appendBytes:contents length:realsize];
  return realsize;
}

@implementation AICURLConnection

#pragma mark - Class Properties

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

#pragma mark - Properties
// None (Manual MRC Accessors for 10.4 compatibility)

#pragma mark - Initializers

+ (void)initialize;
{
  if (self == [AICURLConnection class]) {
    // Check that ca certificates file can be found
    [self certPath];
    // Initialize libcurl globally
    curl_global_init(CURL_GLOBAL_ALL);
  }
}

- (id)init;
{
  return [self initWithRequest:nil delegate:nil startImmediately:YES];
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
    curl_ = curl_easy_init();
    if (!curl_) {
      [self release];
      return nil;
    }
    [self __newCURLHandle:curl_];
    NSLog(@"[AICURLConnection initWithRequest:...] initialized with request: %@", 
          request);
  }
  return self;
}

- (void)dealloc;
{
  [request_ release];
  [delegate_ release];
  if (curl_) {
    [self __releaseCURLHandle:curl_];
    curl_ = NULL;
  }
  [super dealloc];
}

#pragma mark - Shared Request

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

  // Setup basic options
  curl_easy_setopt(curl, CURLOPT_URL, [[[request URL] absoluteString] UTF8String]);
  
  // CA Certs
  NSString *certPath = [self certPath];
  curl_easy_setopt(curl, CURLOPT_CAINFO, [certPath UTF8String]);

  // Response Data Buffer
  NSMutableData *receivedData = [NSMutableData data];
  curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, AIWriteCallback);
  curl_easy_setopt(curl, CURLOPT_WRITEDATA, (void *)receivedData);

  // Perform the request
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

  // Handle Response
  if (response) {
    long responseCode;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &responseCode);
    
    // Use our custom subclass to guarantee status code storage on Tiger.
    *response = [[[AIHTTPURLResponse alloc] initWithURL:[request URL]
                                             statusCode:responseCode
                                           headerFields:nil] autorelease];
  }

  curl_easy_cleanup(curl);
  return receivedData;
}

#pragma mark - Private Methods

- (void)__newCURLHandle:(void *)handle;
{
  CURL *curl = (CURL *)handle;
  NSParameterAssert(curl);
  NSString *certPath = [[self class] certPath];
  curl_easy_setopt(curl, CURLOPT_CAINFO, [certPath UTF8String]);
}

- (void)__releaseCURLHandle:(void *)handle;
{
  CURL *curl = (CURL *)handle;
  NSParameterAssert(curl);
  curl_easy_cleanup(curl);
}

@end
