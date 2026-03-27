#import <Foundation/Foundation.h>

@interface AICURLConnection: NSObject

+ (NSString *)curlVersion;
+ (NSString *)opensslVersion;
+ (NSString *)zlibVersion;
+ (NSString *)aicVersion;
+ (NSString *)certPath;

- (void)__newCURLHandle:(void *)handle;
- (void)__releaseCURLHandle:(void *)handle;

@end
