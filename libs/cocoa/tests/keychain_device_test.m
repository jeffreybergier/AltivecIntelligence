// Native iOS Keychain checks with unique services and isolated test identities.
#import "../AIKeychainStore.h"
#include <stdio.h>
#include <string.h>
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
  BOOL missingAuthentication = NO;
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
  missingAuthentication = discover &&
      ![(NSDictionary *)result objectForKey:(id)kSecAttrAuthenticationType];
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
  if (missingAuthentication) {
    CHECK(![store setString:@"wrong account" forKey:@"other" error:&error]);
    CHECK([error code] == errSecParam);
    [store setAccessGroup:@"other.group"];
    CHECK([store dataForKey:key error:&error] == nil);
    CHECK([error code] == errSecParam);
    [store setAccessGroup:@"org.altivec.keychain-test"];
  }
  CHECK([store removeItemForKey:key error:&error]);
  if (missingAuthentication) {
    CHECK(![store setString:@"do not recreate" forKey:key error:&error]);
    CHECK([error code] == errSecItemNotFound);
  }
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

/* Two invocations verify that an updated legacy item survives process exit.
 * The caller supplies a unique fixture name; only that test identity is used. */
static int CheckPersistentLegacy(NSString *key, BOOL seed)
{
  NSError *error = nil;
  int failures = 0;
  AIKeychainStore *store = nil;
  AIKeychainStore *other = [[[AIKeychainStore alloc] initWithServer:
      [NSURL URLWithString:@"https://keychain-test.invalid"]
      protocolType:AIKeychainProtocolHTTPS
      authenticationType:AIKeychainAuthenticationDefault
      securityDomain:nil] autorelease];
  NSMutableDictionary *identity = [NSMutableDictionary dictionaryWithObjectsAndKeys:
      (id)kSecClassInternetPassword, (id)kSecClass,
      @"org.altivec.keychain-test", (id)kSecAttrAccessGroup,
      @"keychain-test.invalid", (id)kSecAttrServer,
      (id)kSecAttrProtocolHTTPS, (id)kSecAttrProtocol,
      key, (id)kSecAttrAccount, nil];
  if (![key hasPrefix:@"org.altivec.keychain-test.persistence."]) return 1;
  [other setAccessGroup:@"org.altivec.keychain-test"];
  if (seed) {
    NSMutableDictionary *addition = [[identity mutableCopy] autorelease];
    [addition setObject:[@"old" dataUsingEncoding:NSUTF8StringEncoding]
                forKey:(id)kSecValueData];
    CHECK(SecItemAdd((CFDictionaryRef)addition, NULL) == errSecSuccess);
  }
  store = [AIKeychainStore internetPasswordStoreForKey:key error:&error];
  CHECK(store != nil);
  CHECK([[store stringForKey:key error:&error]
      isEqual:seed ? @"old" : @"updated"]);
  if (seed) {
    CHECK([store setString:@"updated" forKey:key error:&error]);
    printf("PASS: legacy update saved for second process\n");
    return 0;
  }
  /* Create the neighbor after discovery so account-only selection is unique. */
  CHECK([other setString:@"default neighbor" forKey:key error:&error]);
  CHECK([[store stringForKey:key error:&error] isEqual:@"updated"]);
  CHECK([store removeItemForKey:key error:&error]);
  CHECK([[other stringForKey:key error:&error] isEqual:@"default neighbor"]);
  printf("PASS: legacy persistence and distinct Default identity\n");
cleanup:
  SecItemDelete((CFDictionaryRef)identity);
  return failures;
}

int main(int argc, char **argv)
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  if (argc == 3) {
    int result = CheckPersistentLegacy([NSString stringWithUTF8String:argv[2]],
        strcmp(argv[1], "seed") == 0);
    [pool drain];
    return result;
  }
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
    /* Older ENIL/Strappy writes omitted authentication. iOS persists an empty
     * string, which must remain distinct from the explicit Default identity. */
    NSMutableDictionary *omitted = [[internetIdentity mutableCopy] autorelease];
    [omitted removeObjectForKey:(id)kSecAttrAuthenticationType];
    failures += CheckLegacyItem(omitted, internet, legacyKey, YES);
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
