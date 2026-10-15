// Exercises actual app facades against an isolated Mac Keychain. Swizzling only
// redirects default keychain selection; storage and facade logic remain native.
#import "../AIKeychainStore.h"
#import <objc/runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#if defined(AI_TEST_RCLOUD)
#include "RCICloudCredentials.h"
/* Native ACL edits may require user authorization even in an owned keychain.
 * Record only this call for unattended tests; all item storage remains native. */
static OSStatus aclStatus = errSecInteractionNotAllowed;
static unsigned int aclUpdates;
OSStatus SecKeychainItemSetAccess(SecKeychainItemRef item, SecAccessRef access)
{
  if (!item || !access) return -50;
  aclUpdates++;
  return aclStatus;
}
#elif defined(AI_TEST_ENIL)
#import "XPFoundation.h"
#else
#import "XPKeychain.h"
#endif

static IMP TestGetImplementation(Method method)
{
#if defined(__OBJC2__) && __OBJC2__
  return method_getImplementation(method);
#else
  return method->method_imp;
#endif
}
static void TestSetImplementation(Method method, IMP implementation)
{
#if defined(__OBJC2__) && __OBJC2__
  method_setImplementation(method, implementation);
#else
  method->method_imp = implementation;
#endif
}
static SecKeychainRef fixture;
static IMP serviceInit, internetInit;
static id InitService(id self, SEL selector, NSString *service)
{
  id result = ((id (*)(id, SEL, NSString *))serviceInit)(self, selector, service);
  [result setKeychain:fixture];
  return result;
}
static id InitInternet(id self, SEL selector, NSURL *url,
                       AIKeychainProtocol protocol,
                       AIKeychainAuthentication authentication, NSString *domain)
{
  id result = ((id (*)(id, SEL, NSURL *, AIKeychainProtocol,
      AIKeychainAuthentication, NSString *))internetInit)(self, selector, url,
      protocol, authentication, domain);
  [result setKeychain:fixture];
  return result;
}
static id Discover(id self, SEL selector, NSString *key, NSError **error)
{
  (void)selector;
  return [self internetPasswordStoreForKey:key inKeychain:fixture error:error];
}
#define CHECK(x) do { if (!(x)) { fprintf(stderr, "FAIL line %d: %s\n", \
  __LINE__, #x); failed = 1; goto cleanup; } } while (0)

int main(int argc, char **argv)
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSString *base = argc > 1 ? [NSString stringWithUTF8String:argv[1]] :
      NSTemporaryDirectory();
  NSString *directory = [base stringByAppendingPathComponent:
      [[NSProcessInfo processInfo] globallyUniqueString]];
  NSString *path = [directory stringByAppendingPathComponent:@"fixture.keychain"];
  Method method;
  int failed = 0;
  alarm(30);
  CHECK([[NSFileManager defaultManager] createDirectoryAtPath:directory
      attributes:[NSDictionary dictionary]]);
  CHECK([AIKeychainStore disableUserInteractionWithError:NULL]);
  CHECK(SecKeychainCreate([path fileSystemRepresentation], 7, "fixture",
      false, NULL, &fixture) == 0);
  method = class_getInstanceMethod([AIKeychainStore class],
      @selector(initWithService:));
  serviceInit = TestGetImplementation(method);
  TestSetImplementation(method, (IMP)InitService);
  method = class_getInstanceMethod([AIKeychainStore class],
      @selector(initWithServer:protocolType:authenticationType:securityDomain:));
  internetInit = TestGetImplementation(method);
  TestSetImplementation(method, (IMP)InitInternet);
  TestSetImplementation(class_getClassMethod([AIKeychainStore class],
      @selector(internetPasswordStoreForKey:error:)), (IMP)Discover);
#if defined(AI_TEST_RCLOUD)
  {
    RCError error;
    char *password = NULL, *account = NULL;
    size_t length = 0;
    /* Actual old native identity, before the facade sees it. */
    CHECK(SecKeychainAddGenericPassword(fixture, 37,
        "com.altivecintelligence.rcloud.icloud", 7, "fixture", 3, "old", NULL) == 0);
    CHECK(RCICloudCredentialsCopyPassword("fixture", &password, &length, &error));
    CHECK(length == 3 && memcmp(password, "old", 3) == 0);
    RCICloudCredentialsClearPassword(password, length);
    CHECK(!RCICloudCredentialsSave("fixture", "new", 3, argv[0], &error));
    CHECK(error.code == errSecInteractionNotAllowed && aclUpdates == 1);
    CHECK(RCICloudCredentialsCopyPassword("fixture", &password, &length, &error));
    CHECK(length == 3 && memcmp(password, "old", 3) == 0);
    RCICloudCredentialsClearPassword(password, length);
    aclStatus = 0;
    CHECK(RCICloudCredentialsSave("fixture", "new", 3, argv[0], &error));
    CHECK(aclUpdates == 2);
    CHECK(RCICloudCredentialsSave("fresh", "created", 7, argv[0], &error));
    CHECK(aclUpdates == 2);
    CHECK(RCICloudCredentialsRemove("fresh", &error));
    CHECK(RCICloudCredentialsCopyPassword("fixture", &password, &length, &error));
    CHECK(length == 3 && memcmp(password, "new", 3) == 0);
    RCICloudCredentialsClearPassword(password, length);
    CHECK(RCICloudCredentialsCopyUsername("fixture", &account, &error));
    CHECK(strcmp(account, "fixture") == 0); free(account);
    CHECK(RCICloudCredentialsRemove("fixture", &error));
    CHECK(RCICloudCredentialsRemove("fixture", &error));
  }
#else
  {
    NSString *url = nil, *password = nil;
    CHECK(![XPKeychain setInternetPasswordForAccount:@"fixture"
        URL:nil password:@"invalid"]);
    CHECK(SecKeychainAddInternetPassword(fixture, 15, "example.invalid",
        0, NULL, 7, "fixture", 4, "/old", 0, kSecProtocolTypeHTTPS, 0,
        3, "old", NULL) == 0);
    CHECK([XPKeychain findInternetPasswordForAccount:@"fixture"
        outURL:&url outPassword:&password]);
    CHECK([url isEqual:@"https://example.invalid/old"] && [password isEqual:@"old"]);
    CHECK([XPKeychain setInternetPasswordForAccount:@"fixture"
        URL:@"https://example.invalid/old" password:@"same identity"]);
    CHECK([XPKeychain setInternetPasswordForAccount:@"fixture"
        URL:@"http://example.invalid:8080/new" password:@"changed URL"]);
    CHECK([XPKeychain findInternetPasswordForAccount:@"fixture"
        outURL:&url outPassword:&password]);
    CHECK([url isEqual:@"http://example.invalid:8080/new"] &&
          [password isEqual:@"changed URL"]);
    CHECK([XPKeychain deleteInternetPasswordForAccount:@"fixture"]);
    CHECK([XPKeychain deleteInternetPasswordForAccount:@"fixture"]);
    CHECK(![XPKeychain findInternetPasswordForAccount:@"fixture"
        outURL:&url outPassword:&password]);
#ifndef AI_TEST_ENIL
    CHECK([XPKeychain setGenericPasswordData:[NSData dataWithBytes:"\0\xff" length:2]
        service:@"fixture.service" account:@"account"]);
    {
      NSData *data = nil;
      CHECK([XPKeychain findGenericPasswordDataForService:@"fixture.service"
          account:@"account" outData:&data] && [data length] == 2);
      CHECK([[XPKeychain genericPasswordAccountsForService:@"fixture.service"] count] == 1);
      CHECK([XPKeychain deleteGenericPasswordForService:@"fixture.service" account:@"account"]);
      CHECK([XPKeychain deleteGenericPasswordForService:@"fixture.service" account:@"account"]);
    }
#endif
  }
#endif
cleanup:
  if (fixture) { if (SecKeychainDelete(fixture) != 0) failed = 1; CFRelease(fixture); }
  [[NSFileManager defaultManager] removeFileAtPath:directory handler:nil];
  puts(failed ? "FAIL: consumer facade" : "PASS: consumer facade and stored identity");
  [pool drain];
  return failed;
}
