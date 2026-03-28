#import <Foundation/Foundation.h>

// A subclass of NSHTTPURLResponse that provides a reliable way to 
// initialize and store HTTP metadata on legacy systems like Tiger (10.4).
@interface AIHTTPURLResponse : NSHTTPURLResponse {
 @private
  NSInteger statusCode_;
  NSDictionary *headerFields_;
}

- (id)initWithURL:(NSURL *)url
       statusCode:(NSInteger)statusCode
     headerFields:(NSDictionary *)headerFields;

+ (NSString *)localizedStringForStatusCode:(NSInteger)statusCode;

- (NSInteger)statusCode;
- (NSDictionary *)allHeaderFields;

@end

// A wrapper for libcurl providing synchronous and asynchronous network 
// request capabilities. Designed for compatibility with legacy systems 
// from Tiger (10.4) through modern macOS.
@interface AICURLConnection : NSObject {
 @private
  void *curl_;
  NSURLRequest *request_;
  id delegate_;

  // Async Support
  NSThread *thread_;
  NSThread *originThread_;
  BOOL cancelled_;
}

#pragma mark - Class Properties

// Returns YES if the library can handle the scheme in the request (http/https).
+ (BOOL)canHandleRequest:(NSURLRequest *)request;

// Returns the version string for the linked zlib library.
+ (NSString *)zlibVersion;

// Returns the version string for the linked OpenSSL library.
+ (NSString *)sslVersion;

// Returns the version string for the linked curl library.
+ (NSString *)curlVersion;

// Returns the version string for the crypto component of OpenSSL.
+ (NSString *)cryptoVersion;

// Returns the path to the bundled CA certificates file.
+ (NSString *)certPath;

#pragma mark - Initializers

- (id)initWithRequest:(NSURLRequest *)request
             delegate:(id)delegate;

- (id)initWithRequest:(NSURLRequest *)request
             delegate:(id)delegate
     startImmediately:(BOOL)startImmediately;

#pragma mark - Lifecycle

- (void)start;
- (void)cancel;

#pragma mark - Shared Request

// Performs a synchronous request and returns the received data.
// Maps to the 10.4-era NSURLConnection API.
+ (NSData *)sendSynchronousRequest:(NSURLRequest *)request
                 returningResponse:(NSURLResponse **)response
                             error:(NSError **)error;

#pragma mark - Private Methods

- (void)__newCURLHandle:(void *)handle;
- (void)__releaseCURLHandle:(void *)handle;

@end
