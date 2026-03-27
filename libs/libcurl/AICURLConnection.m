#import "AICURLConnection.h"
#import <curl/curl.h>
#import <openssl/opensslv.h>
#import <openssl/crypto.h>
#import <zlib.h>


static size_t AICWriteCallback(void *contents, size_t size, size_t nmemb, void *userp) {
  size_t realsize = size * nmemb;
  NSMutableData *data = (NSMutableData *)userp;
  [data appendBytes:contents length:realsize];
  return realsize;
}

@implementation AICURLConnection

#pragma mark - Class Properties

+ (NSString *)zlibVersion {
    const char *ver = zlibVersion();
    return [NSString stringWithUTF8String:ver];
}

+ (NSString *)sslVersion {
    const char *ver = OpenSSL_version(OPENSSL_VERSION);
    return [NSString stringWithUTF8String:ver];
}

+ (NSString *)curlVersion {
    const char *ver = curl_version();
    return [NSString stringWithUTF8String:ver];
}

+ (NSString *)cryptoVersion {
    const char *ver = OpenSSL_version(OPENSSL_VERSION);
    return [NSString stringWithUTF8String:ver];
}

+ (NSString *)certPath;
{
  NSString *certPath = [[NSBundle mainBundle] pathForResource:@"cacert" ofType:@"pem"];
  NSParameterAssert(certPath);
  return certPath;
}

#pragma mark - Properties
// None yet

#pragma mark - Initializers

+ (void)initialize {
  if (self == [AICURLConnection class]) {
    // Check that ca certificates file can be found
    [self certPath];
    // Initialize libcurl globally
    curl_global_init(CURL_GLOBAL_ALL);
  }
}

- (id)init {
  return [self initWithRequest:nil delegate:nil startImmediately:YES];
}

- (id)initWithRequest:(NSURLRequest *)request delegate:(id)delegate {
  return [self initWithRequest:request delegate:delegate startImmediately:YES];
}

- (id)initWithRequest:(NSURLRequest *)request delegate:(id)delegate startImmediately:(BOOL)startImmediately {
  self = [super init];
  if (self) {
    _request = [request retain];
    _delegate = [delegate retain];
    _curl = curl_easy_init();
    if (!_curl) {
      [self release];
      return nil;
    }
    [self __newCURLHandle:_curl];
    NSLog(@"[AICURLConnection initWithRequest:delegate:startImmediately:] initialized with request: %@", request);
    // TODO: Handle startImmediately
  }
  return self;
}

- (void)dealloc {
  [_request release];
  [_delegate release];
  if (_curl) {
    [self __releaseCURLHandle:_curl];
    _curl = NULL;
  }
  [super dealloc];
}

#pragma mark - Shared Request

+ (NSData *)sendSynchronousRequest:(NSURLRequest *)request returningResponse:(NSURLResponse **)response error:(NSError **)error {
  CURL *curl = curl_easy_init();
  if (!curl) {
    if (error) {
      *error = [NSError errorWithDomain:@"AICURLConnectionErrorDomain" code:0 userInfo:nil];
    }
    return nil;
  }

  // Setup basic options
  curl_easy_setopt(curl, CURLOPT_URL, [[[request URL] absoluteString] UTF8String]);
  
  // CA Certs (we have our helper for this)
  NSString *certPath = [self certPath];
  curl_easy_setopt(curl, CURLOPT_CAINFO, [certPath UTF8String]);

  // Response Data Buffer
  NSMutableData *receivedData = [NSMutableData data];
  curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, AICWriteCallback);
  curl_easy_setopt(curl, CURLOPT_WRITEDATA, (void *)receivedData);

  // Perform the request
  CURLcode res = curl_easy_perform(curl);
  
  if (res != CURLE_OK) {
    if (error) {
      NSString *errorMsg = [NSString stringWithUTF8String:curl_easy_strerror(res)];
      NSDictionary *userInfo = [NSDictionary dictionaryWithObject:errorMsg forKey:NSLocalizedDescriptionKey];
      *error = [NSError errorWithDomain:@"AICURLConnectionErrorDomain" code:res userInfo:userInfo];
    }
    curl_easy_cleanup(curl);
    return nil;
  }

  // Handle Response (Basic for now)
  if (response) {
    long responseCode;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &responseCode);
    
    // In a real implementation, we'd extract headers too
    // For now, we'll return a basic NSURLResponse or NSHTTPURLResponse
    *response = [[[NSHTTPURLResponse alloc] initWithURL:[request URL]
                                              statusCode:responseCode
                                             HTTPVersion:@"HTTP/1.1"
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
