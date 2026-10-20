// Runs the production iOS branch on a Mac with a deterministic SecItem recorder.
// This tests query construction and races, not iOS Keychain/entitlement behavior.
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <TargetConditionals.h>
#include <assert.h>
#include <stdio.h>

static NSMutableDictionary *items;
static NSDictionary *lastQuery;
static NSDictionary *lastAddition;
static NSDictionary *lastUpdate;
static OSStatus forcedStatus;
static BOOL duplicateRace;
static int updates, additions, deletions;

static NSDictionary *Identity(NSDictionary *query)
{
  NSMutableDictionary *identity = [[query mutableCopy] autorelease];
  [identity removeObjectForKey:(id)kSecReturnData];
  [identity removeObjectForKey:(id)kSecReturnAttributes];
  [identity removeObjectForKey:(id)kSecReturnPersistentRef];
  [identity removeObjectForKey:(id)kSecMatchLimit];
  [identity removeObjectForKey:(id)kSecValueData];
  [identity removeObjectForKey:(id)kSecAttrAccessible];
  [identity removeObjectForKey:(id)kSecAttrLabel];
  return identity;
}

static OSStatus TestCopy(CFDictionaryRef raw, CFTypeRef *result)
{
  NSDictionary *query = (NSDictionary *)raw;
  NSDictionary *identity = Identity(query);
  [lastQuery release]; lastQuery = [query copy];
  if (forcedStatus) return forcedStatus;
  {
    NSMutableArray *rows = [NSMutableArray array];
    NSEnumerator *enumerator = [items keyEnumerator];
    NSDictionary *item;
    while ((item = [enumerator nextObject])) {
      NSEnumerator *fields = [identity keyEnumerator];
      id field;
      BOOL matches = YES;
      while ((field = [fields nextObject])) {
        if (![[identity objectForKey:field] isEqual:[item objectForKey:field]]) {
          matches = NO; break;
        }
      }
      if (matches) [rows addObject:item];
    }
    if (![rows count]) return errSecItemNotFound;
    if (result) {
      if ([[query objectForKey:(id)kSecMatchLimit] isEqual:(id)kSecMatchLimitAll])
        *result = (CFTypeRef)[rows copy];
      else if ([query objectForKey:(id)kSecReturnAttributes])
        *result = (CFTypeRef)[[rows objectAtIndex:0] copy];
      else *result = (CFTypeRef)[[items objectForKey:[rows objectAtIndex:0]] copy];
    }
  }
  return errSecSuccess;
}

static OSStatus TestUpdate(CFDictionaryRef raw, CFDictionaryRef changes)
{
  NSDictionary *identity = Identity((NSDictionary *)raw);
  updates++;
  [lastUpdate release]; lastUpdate = [(NSDictionary *)changes copy];
  assert([(NSDictionary *)changes objectForKey:(id)kSecValueData]);
  if (forcedStatus) return forcedStatus;
  if (![items objectForKey:identity]) return errSecItemNotFound;
  [items setObject:[(NSDictionary *)changes objectForKey:(id)kSecValueData]
           forKey:identity];
  return errSecSuccess;
}

static OSStatus TestAdd(CFDictionaryRef raw, CFTypeRef *result)
{
  NSDictionary *query = (NSDictionary *)raw;
  NSDictionary *identity = Identity(query);
  (void)result;
  additions++;
  [lastAddition release]; lastAddition = [query copy];
  if (forcedStatus) return forcedStatus;
  if (duplicateRace) {
    duplicateRace = NO;
    [items setObject:[NSData data] forKey:identity];
    return errSecDuplicateItem;
  }
  if ([items objectForKey:identity]) return errSecDuplicateItem;
  [items setObject:[query objectForKey:(id)kSecValueData] forKey:identity];
  return errSecSuccess;
}

static OSStatus TestDelete(CFDictionaryRef raw)
{
  NSDictionary *identity = Identity((NSDictionary *)raw);
  deletions++;
  if (forcedStatus) return forcedStatus;
  if (![items objectForKey:identity]) return errSecItemNotFound;
  [items removeObjectForKey:identity];
  return errSecSuccess;
}

#undef TARGET_OS_IPHONE
#define TARGET_OS_IPHONE 1
#define SecItemCopyMatching TestCopy
#define SecItemUpdate TestUpdate
#define SecItemAdd TestAdd
#define SecItemDelete TestDelete
#import "../AIKeychainStore.m"

int main(void)
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSError *error = nil;
  AIKeychainStore *store = [[AIKeychainStore alloc] initWithService:@"service"];
  AIKeychainStore *internet;
  AIKeychainStore *unsupported;
  NSData *binary = [NSData dataWithBytes:"\0\xff" length:2];
  items = [[NSMutableDictionary alloc] init];
  assert([store dataForKey:@"account" error:&error] == nil);
  assert([error code] == errSecItemNotFound);
  assert([[store allKeysWithError:&error] count] == 0 && error == nil);
  [store setAccessGroup:@"fixture.group"];
  [store setAccessibility:AIKeychainAccessibilityAfterFirstUnlock];
  duplicateRace = YES;
  assert([store setData:binary forKey:@"account" error:&error]);
  assert(updates == 2 && additions == 1 && deletions == 0 && error == nil);
  assert([lastUpdate count] == 1);
  assert([[lastAddition objectForKey:(id)kSecAttrAccessible]
      isEqual:(id)kSecAttrAccessibleAfterFirstUnlock]);
  assert([[lastAddition objectForKey:(id)kSecAttrAccessGroup]
      isEqual:@"fixture.group"]);
  assert([[store dataForKey:@"account" error:&error] isEqual:binary]);
  assert([store stringForKey:@"account" error:&error] == nil);
  assert([error code] == errSecDecode);
  assert([store setString:@"日本語\000tail" forKey:@"account" error:&error]);
  assert(additions == 1 && deletions == 0);
  assert([[store stringForKey:@"account" error:&error] isEqual:@"日本語\000tail"]);
  assert([store setString:@"" forKey:@"empty" error:&error]);
  assert([[store dataForKey:@"empty" error:&error] length] == 0 && error == nil);
  assert([[store allKeysWithError:&error] count] == 2);
  assert([lastQuery objectForKey:(id)kSecReturnData] == nil);
  assert(![store setData:nil forKey:@"account" error:&error]);
  assert([error code] == errSecParam);
  assert(![store removeItemForKey:nil error:&error]);
  assert([error code] == errSecParam);
  forcedStatus = errSecInteractionNotAllowed;
  assert(![store setString:@"blocked" forKey:@"account" error:&error]);
  assert([error code] == errSecInteractionNotAllowed);
  assert([[error domain] isEqual:NSOSStatusErrorDomain]);
  assert([store allKeysWithError:&error] == nil);
  assert([error code] == errSecInteractionNotAllowed);
  forcedStatus = 0;
  assert([[store stringForKey:@"account" error:&error] isEqual:@"日本語\000tail"]);
  assert([store removeItemForKey:@"account" error:&error]);
  assert(![store removeItemForKey:@"account" error:&error]);
  assert([error code] == errSecItemNotFound);
  [store setAccessGroup:@"other.group"];
  assert([store dataForKey:@"empty" error:&error] == nil);
  assert([error code] == errSecItemNotFound);
  internet = [[AIKeychainStore alloc] initWithServer:
      [NSURL URLWithString:@"https://example.invalid:443/path"]
      protocolType:AIKeychainProtocolHTTPS
      authenticationType:AIKeychainAuthenticationHTTPBasic securityDomain:@"realm"];
  assert([internet setString:@"secret" forKey:@"same" error:&error]);
  assert([[lastAddition objectForKey:(id)kSecAttrServer] isEqual:@"example.invalid"]);
  assert([[lastAddition objectForKey:(id)kSecAttrPath] isEqual:@"/path"]);
  assert([[lastAddition objectForKey:(id)kSecAttrPort] intValue] == 443);
  assert([[lastAddition objectForKey:(id)kSecAttrProtocol]
      isEqual:(id)kSecAttrProtocolHTTPS]);
  assert([[lastAddition objectForKey:(id)kSecAttrAuthenticationType]
      isEqual:(id)kSecAttrAuthenticationTypeHTTPBasic]);
  assert([[lastAddition objectForKey:(id)kSecAttrSecurityDomain] isEqual:@"realm"]);
  assert([lastAddition objectForKey:(id)kSecAttrAccessible] == nil);
  unsupported = [[AIKeychainStore alloc] initWithServer:
      [NSURL URLWithString:@"https://example.invalid/path"]
      protocolType:AIKeychainProtocolHTTPS
      authenticationType:AIKeychainAuthenticationUnspecified securityDomain:nil];
  assert([unsupported setString:@"secret" forKey:@"legacy" error:&error]);
  assert([[lastAddition objectForKey:(id)kSecAttrAuthenticationType] isEqual:@""]);
  assert([[unsupported stringForKey:@"legacy" error:&error] isEqual:@"secret"]);
  assert([unsupported removeItemForKey:@"legacy" error:&error]);
  assert([internet containsKey:@"same" error:&error]);
  {
    AIKeychainStore *discovered = [AIKeychainStore
        internetPasswordStoreForKey:@"same" error:&error];
    assert([[discovered serverURLString] isEqual:@"https://example.invalid:443/path"]);
    assert([[discovered stringForKey:@"same" error:&error] isEqual:@"secret"]);
  }
  [store setAccessGroup:@"fixture.group"];
  [store setUpdatesAccessPolicy:YES];
  [store setAccessibility:AIKeychainAccessibilityWhenUnlockedThisDeviceOnly];
  assert([store setString:@"policy update" forKey:@"empty" error:&error]);
  assert([[lastUpdate objectForKey:(id)kSecAttrAccessible]
      isEqual:(id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly]);
  assert([lastUpdate count] == 2);
  [lastUpdate release];
  [store release]; [internet release]; [unsupported release];
  [items release]; [lastQuery release]; [lastAddition release];
  puts("PASS: iOS SecItem recorder, scope, access policy and duplicate-add race");
  [pool drain];
  return 0;
}
