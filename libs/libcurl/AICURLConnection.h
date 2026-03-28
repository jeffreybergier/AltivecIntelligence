#import <Foundation/Foundation.h>

@interface AICURLConnection: NSObject {
  void *_curl;
  NSURLRequest *_request;
  id _delegate;
}

#pragma mark - Class Properties

+ (NSString *)zlibVersion;
+ (NSString *)sslVersion;
+ (NSString *)curlVersion;
+ (NSString *)cryptoVersion;
+ (NSString *)certPath;

#pragma mark - Initializers

- (id)initWithRequest:(NSURLRequest *)request
             delegate:(id)delegate;

- (id)initWithRequest:(NSURLRequest *)request
             delegate:(id)delegate
     startImmediately:(BOOL)startImmediately;

#pragma mark - Shared Request

+ (NSData *)sendSynchronousRequest:(NSURLRequest *)request
                 returningResponse:(NSURLResponse **)response
                             error:(NSError **)error;

#pragma mark - Private Methods

- (void)__newCURLHandle:(void *)handle;
- (void)__releaseCURLHandle:(void *)handle;

@end

#pragma mark - NSHTTPURLResponse (CrossPlatform)

@interface NSHTTPURLResponse (CrossPlatform)

- (id)XP_initWithURL:(NSURL *)url
          statusCode:(NSInteger)statusCode
         HTTPVersion:(NSString *)HTTPVersion
        headerFields:(NSDictionary *)headerFields;

@end
