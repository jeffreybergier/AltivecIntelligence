// Copyright (c) 2026 Jeffrey Bergier. MIT license; see ../../LICENSE.
#import <Foundation/Foundation.h>
#import <TargetConditionals.h>
#import <Security/Security.h>

#ifndef AI_KEYCHAIN_STORE_H
#define AI_KEYCHAIN_STORE_H

/* Native OSStatus values absent by these names in the 10.5 Security headers. */
enum {
  AIKeychainSuccess = 0,
  AIKeychainErrorInvalidArgument = -50,
  AIKeychainErrorDecode = -26275
};

/* Deliberately limited to the protocols currently used by consumers. */
typedef enum {
  AIKeychainProtocolHTTP = 1,
  AIKeychainProtocolHTTPS
} AIKeychainProtocol;

typedef enum {
  /* Legacy Mac zero / iOS empty value, distinct from explicit Default. */
  AIKeychainAuthenticationUnspecified = 0,
  AIKeychainAuthenticationDefault,
  AIKeychainAuthenticationHTTPBasic,
  AIKeychainAuthenticationHTTPDigest,
  AIKeychainAuthenticationHTMLForm
} AIKeychainAuthentication;

/* Creation policy by default; setUpdatesAccessPolicy: opts updates in.
 * SystemDefault omits the attribute. Other values are supported only on iOS. */
typedef enum {
  AIKeychainAccessibilitySystemDefault = 0,
  AIKeychainAccessibilityWhenUnlocked,
  AIKeychainAccessibilityAfterFirstUnlock,
  AIKeychainAccessibilityWhenUnlockedThisDeviceOnly,
  AIKeychainAccessibilityAfterFirstUnlockThisDeviceOnly
} AIKeychainAccessibility;

/* Apps may inject an in-memory implementation of this narrow protocol. */
@protocol AIKeychainStorage <NSObject>
/* Returns nil on failure, including not-found; empty data is a valid value. */
- (NSData *)dataForKey:(NSString *)key error:(NSError **)error;
/* Inserts or updates without deleting first. nil data is invalid. */
- (BOOL)setData:(NSData *)data forKey:(NSString *)key error:(NSError **)error;
/* Strict deletion: missing items report errSecItemNotFound. */
- (BOOL)removeItemForKey:(NSString *)key error:(NSError **)error;
@end

/* UICKeyChainStore-style scoped store, independently implemented for MRC.
 * Keys are account names. Scope and keys are exact, never wildcard searches.
 * All calls are synchronous; serialize use and configure before sharing.
 * Errors use NSOSStatusErrorDomain and native OSStatus codes, without secrets
 * or account names. Success clears *error. No caches, logs or implicit migration.
 * See /altivec/docs/keychain.md for platform and identity limitations. */
@interface AIKeychainStore : NSObject <AIKeychainStorage> {
@private
  NSDictionary *identity_;
  NSString *accessGroup_;
  AIKeychainAccessibility accessibility_;
  NSString *label_;
  BOOL updatesAccessPolicy_;
#if !TARGET_OS_IPHONE
  SecKeychainRef keychain_;
  SecAccessRef access_;
#endif
}
/* Plain init is unavailable in practice: returns nil. Service is required. */
- (id)init;
/* Generic passwords scoped to a nonempty service; key is the account. */
- (id)initWithService:(NSString *)service;
/* Internet passwords: copies host, explicit port (or 0), path (or empty),
 * protocol, authentication and security domain (nil means empty).
 * No default-port inference, lowercasing, or account-only lookup. Invalid scope
 * returns nil. URL user/password/query/fragment are not stored or matched. */
- (id)initWithServer:(NSURL *)server
       protocolType:(AIKeychainProtocol)protocol
 authenticationType:(AIKeychainAuthentication)authentication
     securityDomain:(NSString *)securityDomain;
/* iOS access group; nil uses entitlement-selected default. Non-nil on Mac
 * fails operations with errSecParam rather than silently ignoring the option. */
- (void)setAccessGroup:(NSString *)accessGroup;
/* Accessibility policy; unsupported values fail operations with errSecParam. */
- (void)setAccessibility:(AIKeychainAccessibility)accessibility;
/* Optional label for newly created items; never changes item identity. */
- (void)setLabel:(NSString *)label;
/* Explicit opt-in for apps whose Save action refreshes existing access policy.
 * On Mac this applies the configured SecAccessRef; on iOS accessibility.
 * Default NO preserves the old policy. No policy is synthesized when unset. */
- (void)setUpdatesAccessPolicy:(BOOL)updatesAccessPolicy;
/* Exact metadata-only existence check. Missing items return NO/not-found. */
- (BOOL)containsKey:(NSString *)key error:(NSError **)error;
/* Legacy migration bridge: discovers the first internet item by account only.
 * No writes. Returned store preserves the native identity and access group or
 * keychain. Not-found is an error. Use only for existing account-only schemas. */
+ (AIKeychainStore *)internetPasswordStoreForKey:(NSString *)key
                                         error:(NSError **)error;
/* Internet scope rendered as scheme://server[:port]/path; nil for generic. */
- (NSString *)serverURLString;
/* Raw bytes; keys must be nonempty strings. */
- (NSData *)dataForKey:(NSString *)key error:(NSError **)error;
/* Empty data is valid. Upsert retries once on a duplicate-add race. */
- (BOOL)setData:(NSData *)data forKey:(NSString *)key error:(NSError **)error;
/* UTF-8 convenience. Invalid UTF-8 returns errSecDecode, not not-found. */
- (NSString *)stringForKey:(NSString *)key error:(NSError **)error;
/* UTF-8 convenience; nil is invalid and never means delete. */
- (BOOL)setString:(NSString *)string forKey:(NSString *)key
           error:(NSError **)error;
/* Deletes only the exact scoped account; missing is an error. */
- (BOOL)removeItemForKey:(NSString *)key error:(NSError **)error;
/* Account names in this exact scope, sorted; empty array when none exist.
 * Enumerates metadata without reading password data. */
- (NSArray *)allKeysWithError:(NSError **)error;
#if !TARGET_OS_IPHONE
/* Same legacy lookup restricted to a selected keychain; NULL means default. */
+ (AIKeychainStore *)internetPasswordStoreForKey:(NSString *)key
                                    inKeychain:(SecKeychainRef)keychain
                                         error:(NSError **)error;
/* Retained explicit keychain, or NULL for the native default search list.
 * Useful for isolated tests; existing credentials are never moved. */
- (void)setKeychain:(SecKeychainRef)keychain;
/* Retained Mac ACL; creation-only unless updates opt in. NULL uses OS default. */
- (void)setAccess:(SecAccessRef)access;
/* Process-wide and permanent until another caller changes the native setting.
 * Call at daemon startup before threads; never toggled around individual calls. */
+ (BOOL)disableUserInteractionWithError:(NSError **)error;
#endif
@end
#endif
