#import "AICURLConnection.h"
#import <curl/curl.h>
#import <openssl/opensslv.h>
#import <openssl/crypto.h>
#import <zlib.h>

@implementation AICURLConnection

+ (NSString *)curlVersion {
    const char *ver = curl_version();
    return [NSString stringWithUTF8String:ver];
}

+ (NSString *)opensslVersion {
    // OpenSSL_version is available in 1.1.0+
    const char *ver = OpenSSL_version(OPENSSL_VERSION);
    return [NSString stringWithUTF8String:ver];
}

+ (NSString *)zlibVersion {
    const char *ver = zlibVersion();
    return [NSString stringWithUTF8String:ver];
}

+ (NSString *)aicVersion {
    return @"1.0.0-altivec";
}

@end
