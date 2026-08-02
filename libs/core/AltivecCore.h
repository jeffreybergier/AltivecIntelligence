// AltivecCore.h - umbrella header for the AltivecCore framework.
// Apps can #import <AltivecCore/AltivecCore.h> for the full surface.

#ifndef AltivecCore_h
#define AltivecCore_h

#ifdef __cplusplus
extern "C" {
#endif

// Returns an AltivecCore-owned, process-lifetime file-system path to the
// bundled CA certificates file, or NULL if the path cannot be resolved.
// Pass this path to CURLOPT_CAINFO on every new or reset libcurl easy handle.
const char *AltivecCoreCertPath(void);

#ifdef __cplusplus
}  // extern "C"
#endif

#ifdef __OBJC__
#import <Foundation/Foundation.h>

// Root utility class for AltivecCore-wide resources.
@interface AltivecCore : NSObject

// Returns the path to the bundled CA certificates file.
+ (NSString *)certPath;

@end

#import <AltivecCore/AICURLConnection.h>
#endif

#include <AltivecCore/curl/curl.h>

#include <AltivecCore/openssl/ssl.h>
#include <AltivecCore/openssl/crypto.h>
#include <AltivecCore/openssl/evp.h>
#include <AltivecCore/openssl/err.h>
#include <AltivecCore/openssl/pem.h>
#include <AltivecCore/openssl/x509.h>
#include <AltivecCore/openssl/bio.h>

#include <AltivecCore/zlib.h>
#include <AltivecCore/sqlite3.h>
#include <AltivecCore/cJSON.h>
#include <AltivecCore/cJSON_Utils.h>

#endif /* AltivecCore_h */
