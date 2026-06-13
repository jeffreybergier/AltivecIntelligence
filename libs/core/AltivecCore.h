// AltivecCore.h - umbrella header for the AltivecCore framework.
// Apps can #import <AltivecCore/AltivecCore.h> for the full surface.

#ifndef AltivecCore_h
#define AltivecCore_h

#import <Foundation/Foundation.h>

// Root utility class for AltivecCore-wide resources.
@interface AltivecCore : NSObject

// Returns the path to the bundled CA certificates file.
+ (NSString *)certPath;

@end

#import <AltivecCore/AICURLConnection.h>

#import <AltivecCore/curl/curl.h>

#import <AltivecCore/openssl/ssl.h>
#import <AltivecCore/openssl/crypto.h>
#import <AltivecCore/openssl/evp.h>
#import <AltivecCore/openssl/err.h>
#import <AltivecCore/openssl/pem.h>
#import <AltivecCore/openssl/x509.h>
#import <AltivecCore/openssl/bio.h>

#import <AltivecCore/zlib.h>
#import <AltivecCore/sqlite3.h>
#import <AltivecCore/cJSON.h>
#import <AltivecCore/cJSON_Utils.h>

#endif /* AltivecCore_h */
