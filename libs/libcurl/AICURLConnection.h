#import <Foundation/Foundation.h>

@interface AICURLConnection : NSObject

+ (NSString *)curlVersion;
+ (NSString *)opensslVersion;
+ (NSString *)zlibVersion;
+ (NSString *)aicVersion;

@end
