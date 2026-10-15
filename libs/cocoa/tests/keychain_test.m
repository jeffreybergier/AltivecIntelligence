// Isolated native Mac tests. Never uses or changes the login keychain.
#import "../AIKeychainStore.h"
#include <stdio.h>
#include <stdlib.h>

#define CHECK(x) do { if (!(x)) { \
  fprintf(stderr, "FAIL line %d: %s (status %ld)\n", __LINE__, #x, \
          (long)[error code]); failures++; goto cleanup; } } while (0)

int main(int argc, char **argv)
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSError *error = nil;
  int failures = 0;
  SecKeychainRef keychain = NULL;
  NSString *base = argc > 1 ? [NSString stringWithUTF8String:argv[1]] :
      NSTemporaryDirectory();
  NSString *directory = [base stringByAppendingPathComponent:
      [[NSProcessInfo processInfo] globallyUniqueString]];
  NSString *path = [directory stringByAppendingPathComponent:@"test.keychain"];
  AIKeychainStore *store = nil, *other = nil, *internet = nil, *different = nil;
  const unsigned char bytes[] = { 0, 0xff, 0x80, 0x61 };
  NSData *binary = [NSData dataWithBytes:bytes length:sizeof(bytes)];
  OSStatus status;
  CHECK([[NSFileManager defaultManager] createDirectoryAtPath:directory
      attributes:[NSDictionary dictionary]]);
  CHECK([AIKeychainStore disableUserInteractionWithError:&error]);
  status = SecKeychainCreate([path fileSystemRepresentation], 12,
      "fixture-only", false, NULL, &keychain);
  CHECK(status == AIKeychainSuccess);
  store = [[AIKeychainStore alloc] initWithService:@"altivec.test"];
  other = [[AIKeychainStore alloc] initWithService:@"altivec.other"];
  [store setKeychain:keychain];
  [other setKeychain:keychain];
  CHECK([store dataForKey:@"account" error:&error] == nil);
  CHECK([error code] == errSecItemNotFound);
  CHECK([[store allKeysWithError:&error] count] == 0 && error == nil);
  CHECK([store setData:binary forKey:@"account" error:&error] && error == nil);
  CHECK([[store dataForKey:@"account" error:&error] isEqual:binary]);
  CHECK([store stringForKey:@"account" error:&error] == nil);
  CHECK([error code] == AIKeychainErrorDecode);
  CHECK([other dataForKey:@"account" error:&error] == nil);
  CHECK([error code] == errSecItemNotFound);
  CHECK([store setString:@"日本語\000tail" forKey:@"account" error:&error]);
  CHECK([[store stringForKey:@"account" error:&error] isEqual:@"日本語\000tail"]);
  CHECK([store setString:@"" forKey:@"empty" error:&error]);
  CHECK([[store dataForKey:@"empty" error:&error] length] == 0 && error == nil);
  CHECK(([[store allKeysWithError:&error] isEqual:
      [NSArray arrayWithObjects:@"account", @"empty", nil]]));
  CHECK(![store setData:nil forKey:@"account" error:&error]);
  CHECK([error code] == AIKeychainErrorInvalidArgument);
  CHECK(![store removeItemForKey:nil error:&error]);
  CHECK([error code] == AIKeychainErrorInvalidArgument);
  [store setAccessGroup:@"unsupported"];
  CHECK([store dataForKey:@"account" error:&error] == nil);
  CHECK([error code] == AIKeychainErrorInvalidArgument);
  [store setAccessGroup:nil];
  [store setAccessibility:AIKeychainAccessibilityAfterFirstUnlock];
  CHECK(![store setData:binary forKey:@"account" error:&error]);
  CHECK([error code] == AIKeychainErrorInvalidArgument);
  [store setAccessibility:AIKeychainAccessibilitySystemDefault];
  CHECK([store removeItemForKey:@"account" error:&error]);
  CHECK(![store removeItemForKey:@"account" error:&error]);
  CHECK([error code] == errSecItemNotFound);

  internet = [[AIKeychainStore alloc] initWithServer:
      [NSURL URLWithString:@"https://example.invalid:443/path"]
      protocolType:AIKeychainProtocolHTTPS
      authenticationType:AIKeychainAuthenticationDefault securityDomain:@"realm"];
  different = [[AIKeychainStore alloc] initWithServer:
      [NSURL URLWithString:@"https://example.invalid/path"]
      protocolType:AIKeychainProtocolHTTPS
      authenticationType:AIKeychainAuthenticationDefault securityDomain:@"realm"];
  [internet setKeychain:keychain];
  [different setKeychain:keychain];
  CHECK([internet setString:@"first" forKey:@"same" error:&error]);
  CHECK([different dataForKey:@"same" error:&error] == nil);
  CHECK([different setString:@"other port" forKey:@"same" error:&error]);
  CHECK([internet setString:@"updated" forKey:@"same" error:&error]);
  CHECK([[different stringForKey:@"same" error:&error] isEqual:@"other port"]);
  CHECK([[internet stringForKey:@"same" error:&error] isEqual:@"updated"]);
  CHECK([internet removeItemForKey:@"same" error:&error]);
  CHECK([[different allKeysWithError:&error] count] == 1);
  /* Native API can read an item written through our store. */
  {
    UInt32 length = 0;
    void *password = NULL;
    status = SecKeychainFindInternetPassword(keychain, 15, "example.invalid",
        5, "realm", 4, "same", 5, "/path", 0, kSecProtocolTypeHTTPS,
        kSecAuthenticationTypeDefault, &length, &password, NULL);
    CHECK(status == AIKeychainSuccess && length == 10);
    SecKeychainItemFreeContent(NULL, password);
  }
  /* Read an item created directly with the old API, then update in place. */
  status = SecKeychainAddGenericPassword(keychain, 12, "altivec.test",
      6, "legacy", 3, "old", NULL);
  CHECK(status == AIKeychainSuccess);
  CHECK([[store stringForKey:@"legacy" error:&error] isEqual:@"old"]);
  CHECK([store setString:@"new" forKey:@"legacy" error:&error]);
  CHECK([[store stringForKey:@"legacy" error:&error] isEqual:@"new"]);
  {
    AIKeychainStore *legacyInternet = [[[AIKeychainStore alloc] initWithServer:
        [NSURL URLWithString:@"https://legacy.invalid"]
        protocolType:AIKeychainProtocolHTTPS
        authenticationType:AIKeychainAuthenticationUnspecified
        securityDomain:nil] autorelease];
    NSString *legacyKey = [[NSProcessInfo processInfo] globallyUniqueString];
    AIKeychainStore *discovered;
    [legacyInternet setKeychain:keychain];
    status = SecKeychainAddInternetPassword(keychain, 14, "legacy.invalid",
        0, NULL, (UInt32)[legacyKey length], [legacyKey UTF8String],
        0, NULL, 0, kSecProtocolTypeHTTPS, 0,
        3, "old", NULL);
    CHECK(status == AIKeychainSuccess);
    CHECK([[legacyInternet stringForKey:legacyKey error:&error] isEqual:@"old"]);
    CHECK([legacyInternet setString:@"updated" forKey:legacyKey error:&error]);
    discovered = [AIKeychainStore internetPasswordStoreForKey:legacyKey
                                              inKeychain:keychain
                                                       error:&error];
    CHECK(discovered != nil);
    CHECK([[discovered serverURLString] isEqual:@"https://legacy.invalid"]);
    CHECK([[discovered stringForKey:legacyKey error:&error] isEqual:@"updated"]);
    CHECK([discovered containsKey:legacyKey error:&error]);
  }
  CHECK(SecKeychainLock(keychain) == AIKeychainSuccess);
  CHECK([store dataForKey:@"legacy" error:&error] == nil);
  CHECK([error code] == errSecInteractionNotAllowed ||
        [error code] == errSecAuthFailed);
  CHECK(SecKeychainUnlock(keychain, 12, "fixture-only", true) == AIKeychainSuccess);
  CHECK([[store stringForKey:@"legacy" error:&error] isEqual:@"new"]);
cleanup:
  [store release]; [other release]; [internet release]; [different release];
  if (keychain) {
    if (SecKeychainDelete(keychain) != AIKeychainSuccess) failures++;
    CFRelease(keychain);
  }
  [[NSFileManager defaultManager] removeFileAtPath:directory handler:nil];
  printf("%s: isolated native Mac Keychain CRUD and identity tests\n",
         failures ? "FAIL" : "PASS");
  [pool drain];
  return failures ? 1 : 0;
}
