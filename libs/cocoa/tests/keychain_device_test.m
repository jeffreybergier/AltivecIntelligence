// Native iOS Keychain checks with unique services and isolated test identities.
#import "../AIKeychainStore.h"
#include <stdio.h>
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "FAIL %d status=%ld\n", \
  __LINE__, (long)[error code]); failures++; goto cleanup; } } while (0)
/* Seed through SecItem, then consume through the shared API. Every identity
 * includes this run's unique scope/account; no real credentials are queried. */
static int CheckLegacyItem(NSDictionary *identity, AIKeychainStore *store,
                          NSString *key, BOOL discover)
{
  NSError *error = nil;
  int failures = 0;
  CFTypeRef result = NULL;
  OSStatus status;
  NSMutableDictionary *creation = [NSMutableDictionary dictionaryWithDictionary:
      identity];
  NSMutableDictionary *query = [NSMutableDictionary dictionaryWithDictionary:
      identity];
  NSData *oldData = [@"old fixture" dataUsingEncoding:NSUTF8StringEncoding];
  NSData *newData = [@"new fixture" dataUsingEncoding:NSUTF8StringEncoding];
  [creation setObject:oldData forKey:(id)kSecValueData];
  [creation setObject:(id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly
              forKey:(id)kSecAttrAccessible];
  [query setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnAttributes];
  [query setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnData];
  CHECK(SecItemAdd((CFDictionaryRef)creation, NULL) == errSecSuccess);
  if (discover) {
    store = [AIKeychainStore internetPasswordStoreForKey:key error:&error];
    CHECK(store != nil);
    CHECK([[store serverURLString]
        isEqual:@"https://keychain-test.invalid:443/test"]);
  }
  CHECK([[store dataForKey:key error:&error] isEqual:oldData]);
  [store setAccessibility:AIKeychainAccessibilityAfterFirstUnlockThisDeviceOnly];
  CHECK([store setData:newData forKey:key error:&error]);
  CHECK(SecItemCopyMatching((CFDictionaryRef)query, &result) == errSecSuccess);
  CHECK([[(NSDictionary *)result objectForKey:(id)kSecValueData]
      isEqual:newData]);
  CHECK([[(NSDictionary *)result objectForKey:(id)kSecAttrAccessible]
      isEqual:(id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly]);
  CFRelease(result); result = NULL;
  /* rCloud explicitly opts in to refreshing an existing item's policy. */
  [store setUpdatesAccessPolicy:YES];
  CHECK([store setData:oldData forKey:key error:&error]);
  CHECK(SecItemCopyMatching((CFDictionaryRef)query, &result) == errSecSuccess);
  CHECK([[(NSDictionary *)result objectForKey:(id)kSecValueData]
      isEqual:oldData]);
  CHECK([[(NSDictionary *)result objectForKey:(id)kSecAttrAccessible]
      isEqual:(id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]);
  CFRelease(result); result = NULL;
  CHECK([store removeItemForKey:key error:&error]);
  CHECK(SecItemCopyMatching((CFDictionaryRef)query, &result) == errSecItemNotFound);
cleanup:
  if (result) CFRelease(result);
  status = SecItemDelete((CFDictionaryRef)identity);
  if (status != errSecSuccess && status != errSecItemNotFound) {
    fprintf(stderr, "FAIL legacy fixture cleanup status=%ld\n", (long)status);
    failures++;
  }
  return failures;
}

int main(void)
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSError *error = nil;
  int failures = 0;
  NSString *service = [@"org.altivec.keychain-test." stringByAppendingString:
      [[NSProcessInfo processInfo] globallyUniqueString]];
  AIKeychainStore *store = [[AIKeychainStore alloc] initWithService:service];
  AIKeychainStore *internet = [[AIKeychainStore alloc] initWithServer:
      [NSURL URLWithString:@"https://keychain-test.invalid:443/test"]
      protocolType:AIKeychainProtocolHTTPS
      authenticationType:AIKeychainAuthenticationDefault securityDomain:service];
  const unsigned char bytes[] = { 0, 255, 42 };
  NSData *data = [NSData dataWithBytes:bytes length:sizeof(bytes)];
  [store setAccessGroup:@"org.altivec.keychain-test"];
  [internet setAccessGroup:@"org.altivec.keychain-test"];
  [store setAccessibility:AIKeychainAccessibilityAfterFirstUnlockThisDeviceOnly];
  CHECK([store dataForKey:@"fixture" error:&error] == nil);
  CHECK([error code] == errSecItemNotFound);
  CHECK([store setData:data forKey:@"fixture" error:&error]);
  CHECK([[store dataForKey:@"fixture" error:&error] isEqual:data]);
  CHECK([store setString:@"日本語" forKey:@"fixture" error:&error]);
  CHECK([[store stringForKey:@"fixture" error:&error] isEqual:@"日本語"]);
  CHECK([store setString:@"" forKey:@"empty" error:&error]);
  CHECK([[store dataForKey:@"empty" error:&error] length] == 0 && !error);
  CHECK([[store allKeysWithError:&error] count] == 2);
  CHECK([internet setData:data forKey:@"fixture" error:&error]);
  CHECK([[internet dataForKey:@"fixture" error:&error] isEqual:data]);
  CHECK([internet removeItemForKey:@"fixture" error:&error]);
  CHECK([store removeItemForKey:@"fixture" error:&error]);
  CHECK(![store removeItemForKey:@"fixture" error:&error]);
  CHECK([error code] == errSecItemNotFound);
  {
    NSString *legacyKey = [service stringByAppendingString:@".legacy"];
    NSDictionary *genericIdentity = [NSDictionary dictionaryWithObjectsAndKeys:
        (id)kSecClassGenericPassword, (id)kSecClass,
        @"org.altivec.keychain-test", (id)kSecAttrAccessGroup,
        service, (id)kSecAttrService, legacyKey, (id)kSecAttrAccount, nil];
    NSDictionary *internetIdentity = [NSDictionary dictionaryWithObjectsAndKeys:
        (id)kSecClassInternetPassword, (id)kSecClass,
        @"org.altivec.keychain-test", (id)kSecAttrAccessGroup,
        @"keychain-test.invalid", (id)kSecAttrServer,
        @"/test", (id)kSecAttrPath, service, (id)kSecAttrSecurityDomain,
        [NSNumber numberWithInt:443], (id)kSecAttrPort,
        (id)kSecAttrProtocolHTTPS, (id)kSecAttrProtocol,
        (id)kSecAttrAuthenticationTypeDefault, (id)kSecAttrAuthenticationType,
        legacyKey, (id)kSecAttrAccount, nil];
    failures += CheckLegacyItem(genericIdentity, store, legacyKey, NO);
    failures += CheckLegacyItem(internetIdentity, internet, legacyKey, YES);
  }
cleanup:
  [store removeItemForKey:@"fixture" error:NULL];
  [store removeItemForKey:@"empty" error:NULL];
  [internet removeItemForKey:@"fixture" error:NULL];
  [store release]; [internet release];
  printf("%s: native iOS isolated Keychain CRUD and legacy-item/policy compatibility\n", failures ? "FAIL" : "PASS");
  [pool drain];
  return failures ? 1 : 0;
}
