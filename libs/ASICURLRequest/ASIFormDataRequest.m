// ASIFormDataRequest.m
// Part of ASICURLRequest — a libcurl-backed drop-in for ASIHTTPRequest.

#import "ASIFormDataRequest.h"

// URL-encode a string using CFURLCreateStringByAddingPercentEscapes (Tiger-compatible).
static NSString *ASIURLEncode(NSString *str)
{
  if (!str)
    return @"";
  CFStringRef encoded = CFURLCreateStringByAddingPercentEscapes(
      kCFAllocatorDefault,
      (CFStringRef)str,
      NULL,
      CFSTR("!*'();:@&=+$,/?#[]% "),
      kCFStringEncodingUTF8);
  return [(NSString *)encoded autorelease];
}

@implementation ASIFormDataRequest

+ (id)requestWithURL:(NSURL *)url;
{
  return [[[self alloc] initWithURL:url] autorelease];
}

- (id)initWithURL:(NSURL *)url;
{
  if ((self = [super initWithURL:url]) != nil) {
    postValues_ = [[NSMutableDictionary alloc] init];
  }
  return self;
}

- (void)dealloc;
{
  [postValues_ release];
  [super dealloc];
}

- (void)setPostValue:(NSString *)value forKey:(NSString *)key;
{
  if (key && value)
    [postValues_ setObject:value forKey:key];
}

// Override _runCurl to build postBody_ from postValues_ before executing.
- (void)_runCurl;
{
  // Build URL-encoded body from postValues_
  NSMutableArray *parts = [NSMutableArray arrayWithCapacity:[postValues_ count]];
  NSEnumerator *keyEnum = [postValues_ keyEnumerator];
  NSString *key;
  while ((key = [keyEnum nextObject])) {
    NSString *val = [postValues_ objectForKey:key];
    NSString *part = [NSString stringWithFormat:@"%@=%@",
                      ASIURLEncode(key), ASIURLEncode(val)];
    [parts addObject:part];
  }
  NSString *bodyString = [parts componentsJoinedByString:@"&"];
  [postBody_ release];
  postBody_ = [[bodyString dataUsingEncoding:NSUTF8StringEncoding] retain];

  // Ensure content-type header is set
  if (![requestHeaders_ objectForKey:@"Content-Type"])
    [requestHeaders_ setObject:@"application/x-www-form-urlencoded"
                        forKey:@"Content-Type"];

  [super _runCurl];
}

@end
