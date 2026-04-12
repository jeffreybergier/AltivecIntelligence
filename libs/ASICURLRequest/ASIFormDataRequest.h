// ASIFormDataRequest.h
// Part of ASICURLRequest — a libcurl-backed drop-in for ASIHTTPRequest.

#import "ASIHTTPRequest.h"

@interface ASIFormDataRequest : ASIHTTPRequest {
@private
  NSMutableDictionary *postValues_;
}

+ (id)requestWithURL:(NSURL *)url;

- (void)setPostValue:(NSString *)value forKey:(NSString *)key;

@end
