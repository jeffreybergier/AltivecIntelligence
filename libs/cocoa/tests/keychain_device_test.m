// Native iOS Keychain checks with unique services and isolated test identities.
#import "../AIKeychainStore.h"
#include <stdio.h>
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "FAIL %d status=%ld\n", \
  __LINE__, (long)[error code]); failures++; goto cleanup; } } while (0)
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
cleanup:
  [store removeItemForKey:@"fixture" error:NULL];
  [store removeItemForKey:@"empty" error:NULL];
  [internet removeItemForKey:@"fixture" error:NULL];
  [store release]; [internet release];
  printf("%s: native iOS isolated Keychain CRUD\n", failures ? "FAIL" : "PASS");
  [pool drain];
  return failures ? 1 : 0;
}
