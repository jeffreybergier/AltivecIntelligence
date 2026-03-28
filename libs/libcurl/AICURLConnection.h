#import <Foundation/Foundation.h>

// A wrapper for libcurl providing synchronous and asynchronous network 
// request capabilities. Designed for compatibility with legacy systems 
// from Tiger (10.4) through modern macOS.
@interface AICURLConnection : NSObject {
 @private
  void *curl_;
  NSURLRequest *request_;
  id delegate_;
}

#pragma mark - Class Properties

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

#pragma mark - NSHTTPURLResponse (CrossPlatform)

// Category to provide cross-version initialization for NSHTTPURLResponse.
@interface NSHTTPURLResponse (CrossPlatform)

- (id)XP_initWithURL:(NSURL *)url
          statusCode:(NSInteger)statusCode
         HTTPVersion:(NSString *)HTTPVersion
        headerFields:(NSDictionary *)headerFields;

@end
