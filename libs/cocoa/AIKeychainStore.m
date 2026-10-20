// Copyright (c) 2026 Jeffrey Bergier. MIT license; see ../../LICENSE.
#import "AIKeychainStore.h"
#include <limits.h>
#include <string.h>

static BOOL AIKCResult(OSStatus status, NSError **error)
{
  if (error) *error = status == AIKeychainSuccess ? nil :
      [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
  return status == AIKeychainSuccess;
}

static BOOL AIKCString(NSString *value)
{
  return [value isKindOfClass:[NSString class]] && [value length] > 0 &&
      [value dataUsingEncoding:NSUTF8StringEncoding] != nil &&
      [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= UINT_MAX;
}

#if TARGET_OS_IPHONE
static id AIKCProtocol(int value)
{
  return (id)(value == AIKeychainProtocolHTTP ?
      kSecAttrProtocolHTTP : kSecAttrProtocolHTTPS);
}

static id AIKCAuthentication(int value)
{
  switch (value) {
    case AIKeychainAuthenticationUnspecified:
      return @"";
    case AIKeychainAuthenticationDefault:
      return (id)kSecAttrAuthenticationTypeDefault;
    case AIKeychainAuthenticationHTTPBasic:
      return (id)kSecAttrAuthenticationTypeHTTPBasic;
    case AIKeychainAuthenticationHTTPDigest:
      return (id)kSecAttrAuthenticationTypeHTTPDigest;
    case AIKeychainAuthenticationHTMLForm:
      return (id)kSecAttrAuthenticationTypeHTMLForm;
    default: return nil;
  }
}
#else
/* Search and create use the same explicit attributes, including empty strings
 * and zero port, instead of Find* APIs whose NULL/zero inputs are wildcards. */
typedef struct {
  SecKeychainAttribute values[8];
  SecKeychainAttributeList list;
  UInt32 port;
  SecProtocolType protocol;
  SecAuthenticationType authentication;
} AIKCAttributes;

static void AIKCAttribute(AIKCAttributes *attrs, UInt32 tag,
                          const void *bytes, UInt32 length)
{
  SecKeychainAttribute *attribute = &attrs->values[attrs->list.count++];
  attribute->tag = tag;
  attribute->data = (void *)bytes;
  attribute->length = length;
}

static void AIKCText(AIKCAttributes *attrs, UInt32 tag, NSString *value)
{
  const char *bytes = [value UTF8String];
  AIKCAttribute(attrs, tag, bytes,
                (UInt32)[value lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
}

static void AIKCBuildAttributes(NSDictionary *identity, NSString *key,
                                AIKCAttributes *attrs)
{
  memset(attrs, 0, sizeof(*attrs));
  attrs->list.attr = attrs->values;
  if (key) AIKCText(attrs, kSecAccountItemAttr, key);
  if ([identity objectForKey:@"service"]) {
    AIKCText(attrs, kSecServiceItemAttr, [identity objectForKey:@"service"]);
  } else {
    AIKCText(attrs, kSecServerItemAttr, [identity objectForKey:@"server"]);
    AIKCText(attrs, kSecPathItemAttr, [identity objectForKey:@"path"]);
    AIKCText(attrs, kSecSecurityDomainItemAttr,
             [identity objectForKey:@"domain"]);
    attrs->port = [[identity objectForKey:@"port"] unsignedIntValue];
    attrs->protocol = [[identity objectForKey:@"protocol"] intValue] ==
        AIKeychainProtocolHTTP ? kSecProtocolTypeHTTP : kSecProtocolTypeHTTPS;
    switch ([[identity objectForKey:@"authentication"] intValue]) {
      case AIKeychainAuthenticationDefault:
        attrs->authentication = kSecAuthenticationTypeDefault; break;
      case AIKeychainAuthenticationHTTPBasic:
        attrs->authentication = kSecAuthenticationTypeHTTPBasic; break;
      case AIKeychainAuthenticationHTTPDigest:
        attrs->authentication = kSecAuthenticationTypeHTTPDigest; break;
      case AIKeychainAuthenticationHTMLForm:
        attrs->authentication = kSecAuthenticationTypeHTMLForm; break;
      default: attrs->authentication = 0; break;
    }
    AIKCAttribute(attrs, kSecPortItemAttr, &attrs->port, sizeof(attrs->port));
    AIKCAttribute(attrs, kSecProtocolItemAttr, &attrs->protocol,
                  sizeof(attrs->protocol));
    AIKCAttribute(attrs, kSecAuthenticationTypeItemAttr, &attrs->authentication,
                  sizeof(attrs->authentication));
  }
}
#endif

@interface AIKeychainStore (Private)
- (BOOL)validateKey:(NSString *)key error:(NSError **)error;
#if TARGET_OS_IPHONE
- (NSMutableDictionary *)queryForKey:(NSString *)key;
#else
- (OSStatus)searchForKey:(NSString *)key search:(SecKeychainSearchRef *)search;
- (OSStatus)findKey:(NSString *)key item:(SecKeychainItemRef *)item;
#endif
@end

@implementation AIKeychainStore
- (id)init;
{
  [self release];
  return nil;
}

- (id)initWithService:(NSString *)service;
{
  self = [super init];
  if (self) {
    if (!AIKCString(service)) { [self release]; return nil; }
    identity_ = [[NSDictionary alloc] initWithObjectsAndKeys:
        [[service copy] autorelease], @"service", nil];
  }
  return self;
}

- (id)initWithServer:(NSURL *)server
       protocolType:(AIKeychainProtocol)protocol
 authenticationType:(AIKeychainAuthentication)authentication
     securityDomain:(NSString *)securityDomain;
{
  self = [super init];
  if (self) {
    if (![server isKindOfClass:[NSURL class]] || !AIKCString([server host]) ||
        (protocol != AIKeychainProtocolHTTP &&
         protocol != AIKeychainProtocolHTTPS) ||
        (int)authentication < AIKeychainAuthenticationUnspecified ||
        authentication > AIKeychainAuthenticationHTMLForm ||
        (securityDomain && (![securityDomain isKindOfClass:[NSString class]] ||
          ![securityDomain dataUsingEncoding:NSUTF8StringEncoding] ||
          [securityDomain lengthOfBytesUsingEncoding:NSUTF8StringEncoding] >
              UINT_MAX)) ||
        [[server port] intValue] < 0 || [[server port] intValue] > 65535) {
      [self release]; return nil;
    }
    identity_ = [[NSDictionary alloc] initWithObjectsAndKeys:
        [server host], @"server", [server path] ? [server path] : @"", @"path",
        [server port] ? [server port] : [NSNumber numberWithInt:0], @"port",
        [NSNumber numberWithInt:protocol], @"protocol",
        [NSNumber numberWithInt:authentication], @"authentication",
        securityDomain ? [[securityDomain copy] autorelease] : @"", @"domain",
        nil];
  }
  return self;
}

- (void)dealloc;
{
  [identity_ release];
  [label_ release];
  [accessGroup_ release];
#if !TARGET_OS_IPHONE
  if (keychain_) CFRelease(keychain_);
  if (access_) CFRelease(access_);
#endif
  [super dealloc];
}

- (void)setAccessGroup:(NSString *)accessGroup;
{
  id copy = [accessGroup copy];
  [accessGroup_ release];
  accessGroup_ = copy;
}

- (void)setAccessibility:(AIKeychainAccessibility)accessibility;
{
  accessibility_ = accessibility;
}

- (void)setLabel:(NSString *)label;
{
  id copy = [label copy];
  [label_ release];
  label_ = copy;
}

- (void)setUpdatesAccessPolicy:(BOOL)updatesAccessPolicy;
{
  updatesAccessPolicy_ = updatesAccessPolicy;
}

- (NSString *)serverURLString;
{
  NSString *server = [identity_ objectForKey:@"server"];
  NSMutableString *url;
  if (!server) return nil;
  url = [NSMutableString stringWithFormat:@"%@://%@",
      [[identity_ objectForKey:@"protocol"] intValue] == AIKeychainProtocolHTTP ?
      @"http" : @"https", server];
  if ([[identity_ objectForKey:@"port"] intValue] > 0)
    [url appendFormat:@":%d", [[identity_ objectForKey:@"port"] intValue]];
  [url appendString:[identity_ objectForKey:@"path"]];
  return url;
}

- (BOOL)containsKey:(NSString *)key error:(NSError **)error;
{
  OSStatus status;
  if (!key) return AIKCResult(AIKeychainErrorInvalidArgument, error);
  if (![self validateKey:key error:error]) return NO;
#if TARGET_OS_IPHONE
  status = SecItemCopyMatching((CFDictionaryRef)[self queryForKey:key], NULL);
#else
  SecKeychainItemRef item = NULL;
  status = [self findKey:key item:&item];
  if (item) CFRelease(item);
#endif
  return AIKCResult(status, error);
}

+ (AIKeychainStore *)internetPasswordStoreForKey:(NSString *)key
                                         error:(NSError **)error;
{
#if !TARGET_OS_IPHONE
  return [self internetPasswordStoreForKey:key inKeychain:NULL error:error];
}

+ (AIKeychainStore *)internetPasswordStoreForKey:(NSString *)key
                                    inKeychain:(SecKeychainRef)searchKeychain
                                         error:(NSError **)error;
{
#endif
  AIKeychainStore *store = nil;
  NSMutableDictionary *identity = [NSMutableDictionary dictionary];
  OSStatus status = AIKeychainSuccess;
  if (!AIKCString(key)) {
    AIKCResult(AIKeychainErrorInvalidArgument, error); return nil;
  }
#if TARGET_OS_IPHONE
  NSDictionary *query = [NSDictionary dictionaryWithObjectsAndKeys:
      (id)kSecClassInternetPassword, (id)kSecClass, key, (id)kSecAttrAccount,
      (id)kSecMatchLimitOne, (id)kSecMatchLimit,
      (id)kCFBooleanTrue, (id)kSecReturnAttributes, nil];
  CFTypeRef result = NULL;
  status = SecItemCopyMatching((CFDictionaryRef)query, &result);
  if (status == AIKeychainSuccess &&
      (!result || CFGetTypeID(result) != CFDictionaryGetTypeID()))
    status = AIKeychainErrorDecode;
  if (status == AIKeychainSuccess) {
    NSDictionary *row = (NSDictionary *)result;
    id protocol = [row objectForKey:(id)kSecAttrProtocol];
    id auth = [row objectForKey:(id)kSecAttrAuthenticationType];
    int authentication = AIKeychainAuthenticationDefault;
    if (!auth || [auth isEqual:@""])
      authentication = AIKeychainAuthenticationUnspecified;
    else if ([auth isEqual:(id)kSecAttrAuthenticationTypeHTTPBasic])
      authentication = AIKeychainAuthenticationHTTPBasic;
    else if ([auth isEqual:(id)kSecAttrAuthenticationTypeHTTPDigest])
      authentication = AIKeychainAuthenticationHTTPDigest;
    else if ([auth isEqual:(id)kSecAttrAuthenticationTypeHTMLForm])
      authentication = AIKeychainAuthenticationHTMLForm;
    else if (auth && ![auth isEqual:(id)kSecAttrAuthenticationTypeDefault])
      status = AIKeychainErrorInvalidArgument;
    if (![protocol isEqual:(id)kSecAttrProtocolHTTP] &&
        ![protocol isEqual:(id)kSecAttrProtocolHTTPS])
      status = AIKeychainErrorInvalidArgument;
    [identity setObject:[NSNumber numberWithInt:
        [protocol isEqual:(id)kSecAttrProtocolHTTP] ? AIKeychainProtocolHTTP :
        AIKeychainProtocolHTTPS] forKey:@"protocol"];
    [identity setObject:[NSNumber numberWithInt:authentication]
                 forKey:@"authentication"];
    [identity setObject:([row objectForKey:(id)kSecAttrServer] ?
        [row objectForKey:(id)kSecAttrServer] : @"") forKey:@"server"];
    [identity setObject:([row objectForKey:(id)kSecAttrPath] ?
        [row objectForKey:(id)kSecAttrPath] : @"") forKey:@"path"];
    [identity setObject:([row objectForKey:(id)kSecAttrSecurityDomain] ?
        [row objectForKey:(id)kSecAttrSecurityDomain] : @"") forKey:@"domain"];
    [identity setObject:([row objectForKey:(id)kSecAttrPort] ?
        [row objectForKey:(id)kSecAttrPort] : [NSNumber numberWithInt:0])
                 forKey:@"port"];
    if (status == AIKeychainSuccess) {
      store = [[[self alloc] initWithService:@"discovery"] autorelease];
      [store setAccessGroup:[row objectForKey:(id)kSecAttrAccessGroup]];
    }
  }
  if (result) CFRelease(result);
#else
  SecKeychainItemRef item = NULL;
  SecKeychainRef keychain = NULL;
  SecKeychainAttributeList *attrs = NULL;
  UInt32 tags[] = { kSecServerItemAttr, kSecPathItemAttr,
      kSecSecurityDomainItemAttr, kSecPortItemAttr, kSecProtocolItemAttr,
      kSecAuthenticationTypeItemAttr };
  UInt32 formats[] = { CSSM_DB_ATTRIBUTE_FORMAT_STRING,
      CSSM_DB_ATTRIBUTE_FORMAT_STRING, CSSM_DB_ATTRIBUTE_FORMAT_STRING,
      CSSM_DB_ATTRIBUTE_FORMAT_UINT32, CSSM_DB_ATTRIBUTE_FORMAT_UINT32,
      CSSM_DB_ATTRIBUTE_FORMAT_UINT32 };
  SecKeychainAttributeInfo info = { 6, tags, formats };
  status = SecKeychainFindInternetPassword(searchKeychain, 0, NULL, 0, NULL,
      (UInt32)[key lengthOfBytesUsingEncoding:NSUTF8StringEncoding],
      [key UTF8String], 0, NULL, 0, 0, 0, NULL, NULL, &item);
  if (status == AIKeychainSuccess)
    status = SecKeychainItemCopyAttributesAndData(item, &info, NULL, &attrs,
                                                 NULL, NULL);
  if (status == AIKeychainSuccess) {
    UInt32 index;
    for (index = 0; index < attrs->count; index++) {
      SecKeychainAttribute *attr = &attrs->attr[index];
      if (attr->tag == kSecServerItemAttr || attr->tag == kSecPathItemAttr ||
          attr->tag == kSecSecurityDomainItemAttr) {
        NSString *value = [[[NSString alloc] initWithBytes:attr->data
            length:attr->length encoding:NSUTF8StringEncoding] autorelease];
        NSString *name = attr->tag == kSecServerItemAttr ? @"server" :
            attr->tag == kSecPathItemAttr ? @"path" : @"domain";
        if (!value) { status = AIKeychainErrorDecode; break; }
        [identity setObject:value forKey:name];
      } else {
        UInt32 value;
        if (attr->length != sizeof(value)) {
          status = AIKeychainErrorDecode; break;
        }
        memcpy(&value, attr->data, sizeof(value));
        if (attr->tag == kSecProtocolItemAttr) {
          if (value == kSecProtocolTypeHTTP) value = AIKeychainProtocolHTTP;
          else if (value == kSecProtocolTypeHTTPS) value = AIKeychainProtocolHTTPS;
          else { status = AIKeychainErrorInvalidArgument; break; }
          [identity setObject:[NSNumber numberWithUnsignedInt:value]
                       forKey:@"protocol"];
        } else if (attr->tag == kSecAuthenticationTypeItemAttr) {
          if (value == kSecAuthenticationTypeDefault)
            value = AIKeychainAuthenticationDefault;
          else if (value == kSecAuthenticationTypeHTTPBasic)
            value = AIKeychainAuthenticationHTTPBasic;
          else if (value == kSecAuthenticationTypeHTTPDigest)
            value = AIKeychainAuthenticationHTTPDigest;
          else if (value == kSecAuthenticationTypeHTMLForm)
            value = AIKeychainAuthenticationHTMLForm;
          else if (value != 0) { status = AIKeychainErrorInvalidArgument; break; }
          [identity setObject:[NSNumber numberWithUnsignedInt:value]
                       forKey:@"authentication"];
        } else [identity setObject:[NSNumber numberWithUnsignedInt:value]
                            forKey:@"port"];
      }
    }
    if ([identity count] != 6) status = AIKeychainErrorDecode;
  }
  if (status == AIKeychainSuccess)
    status = SecKeychainItemCopyKeychain(item, &keychain);
  if (status == AIKeychainSuccess) {
    store = [[[self alloc] initWithService:@"discovery"] autorelease];
    [store setKeychain:keychain];
  }
  if (keychain) CFRelease(keychain);
  if (attrs) SecKeychainItemFreeAttributesAndData(attrs, NULL);
  if (item) CFRelease(item);
#endif
  if (store) {
    [store->identity_ release];
    store->identity_ = [identity copy];
  }
  return AIKCResult(status, error) ? store : nil;
}

- (BOOL)validateKey:(NSString *)key error:(NSError **)error;
{
  BOOL valid = identity_ != nil && (!key || AIKCString(key));
  valid = valid && (int)accessibility_ >= AIKeychainAccessibilitySystemDefault &&
      accessibility_ <= AIKeychainAccessibilityAfterFirstUnlockThisDeviceOnly;
#if TARGET_OS_IPHONE
  valid = valid && (!accessGroup_ || AIKCString(accessGroup_));
#else
  valid = valid && !accessGroup_ &&
      accessibility_ == AIKeychainAccessibilitySystemDefault;
#endif
  return AIKCResult(valid ? AIKeychainSuccess : AIKeychainErrorInvalidArgument, error);
}

#if TARGET_OS_IPHONE
- (NSMutableDictionary *)queryForKey:(NSString *)key;
{
  NSMutableDictionary *query = [NSMutableDictionary dictionary];
  NSString *service = [identity_ objectForKey:@"service"];
  [query setObject:(id)(service ? kSecClassGenericPassword :
      kSecClassInternetPassword) forKey:(id)kSecClass];
  if (key) [query setObject:key forKey:(id)kSecAttrAccount];
  if (accessGroup_) [query setObject:accessGroup_ forKey:(id)kSecAttrAccessGroup];
  if (service) [query setObject:service forKey:(id)kSecAttrService];
  else {
    id authentication = AIKCAuthentication(
        [[identity_ objectForKey:@"authentication"] intValue]);
    [query setObject:[identity_ objectForKey:@"server"]
              forKey:(id)kSecAttrServer];
    [query setObject:[identity_ objectForKey:@"path"] forKey:(id)kSecAttrPath];
    [query setObject:[identity_ objectForKey:@"domain"]
              forKey:(id)kSecAttrSecurityDomain];
    [query setObject:[identity_ objectForKey:@"port"] forKey:(id)kSecAttrPort];
    [query setObject:AIKCProtocol([[identity_ objectForKey:@"protocol"] intValue])
              forKey:(id)kSecAttrProtocol];
    /* Legacy SecItemAdd calls with no authentication persist an empty value.
     * Match it explicitly: omitting it here would also match Default items. */
    if (authentication) [query setObject:authentication
                                  forKey:(id)kSecAttrAuthenticationType];
  }
  return query;
}
#else
- (void)setKeychain:(SecKeychainRef)keychain;
{
  if (keychain) CFRetain(keychain);
  if (keychain_) CFRelease(keychain_);
  keychain_ = keychain;
}

- (void)setAccess:(SecAccessRef)access;
{
  if (access) CFRetain(access);
  if (access_) CFRelease(access_);
  access_ = access;
}

+ (BOOL)disableUserInteractionWithError:(NSError **)error;
{
  return AIKCResult(SecKeychainSetUserInteractionAllowed(false), error);
}

- (OSStatus)searchForKey:(NSString *)key search:(SecKeychainSearchRef *)search;
{
  AIKCAttributes attrs;
  AIKCBuildAttributes(identity_, key, &attrs);
  return SecKeychainSearchCreateFromAttributes(keychain_,
      [identity_ objectForKey:@"service"] ? kSecGenericPasswordItemClass :
      kSecInternetPasswordItemClass, &attrs.list, search);
}

- (OSStatus)findKey:(NSString *)key item:(SecKeychainItemRef *)item;
{
  SecKeychainSearchRef search = NULL;
  OSStatus status = [self searchForKey:key search:&search];
  if (status == AIKeychainSuccess) status = SecKeychainSearchCopyNext(search, item);
  if (search) CFRelease(search);
  return status;
}
#endif

- (NSData *)dataForKey:(NSString *)key error:(NSError **)error;
{
  OSStatus status;
  NSData *data = nil;
  if (!key) { AIKCResult(AIKeychainErrorInvalidArgument, error); return nil; }
  if (![self validateKey:key error:error]) return nil;
#if TARGET_OS_IPHONE
  NSMutableDictionary *query = [self queryForKey:key];
  CFTypeRef result = NULL;
  [query setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnData];
  [query setObject:(id)kSecMatchLimitOne forKey:(id)kSecMatchLimit];
  status = SecItemCopyMatching((CFDictionaryRef)query, &result);
  if (status == AIKeychainSuccess) {
    if (result && CFGetTypeID(result) == CFDataGetTypeID())
      data = [[(NSData *)result copy] autorelease];
    else status = AIKeychainErrorDecode;
  }
  if (result) CFRelease(result);
#else
  SecKeychainItemRef item = NULL;
  void *bytes = NULL;
  UInt32 length = 0;
  status = [self findKey:key item:&item];
  if (status == AIKeychainSuccess)
    status = SecKeychainItemCopyAttributesAndData(item, NULL, NULL, NULL,
                                                 &length, &bytes);
  if (status == AIKeychainSuccess) data = [NSData dataWithBytes:bytes length:length];
  if (bytes) SecKeychainItemFreeAttributesAndData(NULL, bytes);
  if (item) CFRelease(item);
#endif
  return AIKCResult(status, error) ? data : nil;
}

- (BOOL)setData:(NSData *)data forKey:(NSString *)key error:(NSError **)error;
{
  OSStatus status;
  if (!key || ![data isKindOfClass:[NSData class]] || [data length] > UINT_MAX)
    return AIKCResult(AIKeychainErrorInvalidArgument, error);
  if (![self validateKey:key error:error]) return NO;
#if TARGET_OS_IPHONE
  NSMutableDictionary *query = [self queryForKey:key];
  NSMutableDictionary *update = [NSMutableDictionary dictionaryWithObject:data
                                                     forKey:(id)kSecValueData];
  id accessibility = nil;
  switch (accessibility_) {
    case AIKeychainAccessibilityWhenUnlocked:
      accessibility = (id)kSecAttrAccessibleWhenUnlocked; break;
    case AIKeychainAccessibilityAfterFirstUnlock:
      accessibility = (id)kSecAttrAccessibleAfterFirstUnlock; break;
    case AIKeychainAccessibilityWhenUnlockedThisDeviceOnly:
      accessibility = (id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly; break;
    case AIKeychainAccessibilityAfterFirstUnlockThisDeviceOnly:
      accessibility = (id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
      break;
    default: break;
  }
  if (updatesAccessPolicy_ && accessibility)
    [update setObject:accessibility forKey:(id)kSecAttrAccessible];
  status = SecItemUpdate((CFDictionaryRef)query, (CFDictionaryRef)update);
  if (status == errSecItemNotFound) {
    NSMutableDictionary *addition = [[query mutableCopy] autorelease];
    if (label_) [addition setObject:label_ forKey:(id)kSecAttrLabel];
    [addition addEntriesFromDictionary:update];
    if (accessibility) [addition setObject:accessibility
                                   forKey:(id)kSecAttrAccessible];
    status = SecItemAdd((CFDictionaryRef)addition, NULL);
    if (status == errSecDuplicateItem)
      status = SecItemUpdate((CFDictionaryRef)query, (CFDictionaryRef)update);
  }
#else
  SecKeychainItemRef item = NULL;
  status = [self findKey:key item:&item];
  if (status == errSecItemNotFound) {
    AIKCAttributes attrs;
    AIKCBuildAttributes(identity_, key, &attrs);
    if (label_) AIKCText(&attrs, kSecLabelItemAttr, label_);
    status = SecKeychainItemCreateFromContent(
        [identity_ objectForKey:@"service"] ? kSecGenericPasswordItemClass :
        kSecInternetPasswordItemClass, &attrs.list, (UInt32)[data length],
        [data length] ? [data bytes] : "", keychain_, access_, NULL);
    if (status == errSecDuplicateItem) status = [self findKey:key item:&item];
  }
  if (status == AIKeychainSuccess && item && updatesAccessPolicy_ && access_)
    status = SecKeychainItemSetAccess(item, access_);
  if (status == AIKeychainSuccess && item)
    status = SecKeychainItemModifyAttributesAndData(item, NULL,
        (UInt32)[data length], [data length] ? [data bytes] : "");
  if (item) CFRelease(item);
#endif
  return AIKCResult(status, error);
}

- (NSString *)stringForKey:(NSString *)key error:(NSError **)error;
{
  NSData *data = [self dataForKey:key error:error];
  NSString *string;
  if (!data) return nil;
  string = [[[NSString alloc] initWithData:data
                                encoding:NSUTF8StringEncoding] autorelease];
  if (!string) AIKCResult(AIKeychainErrorDecode, error);
  return string;
}

- (BOOL)setString:(NSString *)string forKey:(NSString *)key
           error:(NSError **)error;
{
  if (![string isKindOfClass:[NSString class]])
    return AIKCResult(AIKeychainErrorInvalidArgument, error);
  return [self setData:[string dataUsingEncoding:NSUTF8StringEncoding]
                forKey:key error:error];
}

- (BOOL)removeItemForKey:(NSString *)key error:(NSError **)error;
{
  OSStatus status;
  if (!key) return AIKCResult(AIKeychainErrorInvalidArgument, error);
  if (![self validateKey:key error:error]) return NO;
#if TARGET_OS_IPHONE
  status = SecItemDelete((CFDictionaryRef)[self queryForKey:key]);
#else
  SecKeychainItemRef item = NULL;
  status = [self findKey:key item:&item];
  if (status == AIKeychainSuccess) status = SecKeychainItemDelete(item);
  if (item) CFRelease(item);
#endif
  return AIKCResult(status, error);
}

- (NSArray *)allKeysWithError:(NSError **)error;
{
  OSStatus status;
  NSMutableArray *keys = [NSMutableArray array];
  if (![self validateKey:nil error:error]) return nil;
#if TARGET_OS_IPHONE
  NSMutableDictionary *query = [self queryForKey:nil];
  CFTypeRef result = NULL;
  [query setObject:(id)kCFBooleanTrue forKey:(id)kSecReturnAttributes];
  [query setObject:(id)kSecMatchLimitAll forKey:(id)kSecMatchLimit];
  status = SecItemCopyMatching((CFDictionaryRef)query, &result);
  if (status == AIKeychainSuccess) {
    if (!result || CFGetTypeID(result) != CFArrayGetTypeID()) status = AIKeychainErrorDecode;
    else {
      NSEnumerator *enumerator = [(NSArray *)result objectEnumerator];
      NSDictionary *row;
      while ((row = [enumerator nextObject])) {
        id key = [row objectForKey:(id)kSecAttrAccount];
        if (![key isKindOfClass:[NSString class]]) { status = AIKeychainErrorDecode; break; }
        [keys addObject:key];
      }
    }
  }
  if (result) CFRelease(result);
#else
  SecKeychainSearchRef search = NULL;
  status = [self searchForKey:nil search:&search];
  while (status == AIKeychainSuccess) {
    SecKeychainItemRef item = NULL;
    SecKeychainAttributeList *attrs = NULL;
    UInt32 tag = kSecAccountItemAttr, format = CSSM_DB_ATTRIBUTE_FORMAT_STRING;
    SecKeychainAttributeInfo info = { 1, &tag, &format };
    status = SecKeychainSearchCopyNext(search, &item);
    if (status != AIKeychainSuccess) break;
    status = SecKeychainItemCopyAttributesAndData(item, &info, NULL, &attrs,
                                                 NULL, NULL);
    if (status == AIKeychainSuccess) {
      NSString *key = nil;
      if (attrs && attrs->count == 1)
        key = [[[NSString alloc] initWithBytes:attrs->attr[0].data
            length:attrs->attr[0].length encoding:NSUTF8StringEncoding] autorelease];
      if (key) [keys addObject:key];
      else status = AIKeychainErrorDecode;
    }
    if (attrs) SecKeychainItemFreeAttributesAndData(attrs, NULL);
    CFRelease(item);
  }
  if (search) CFRelease(search);
#endif
  if (status == errSecItemNotFound) status = AIKeychainSuccess;
  return AIKCResult(status, error) ? [keys sortedArrayUsingSelector:
      @selector(compare:)] : nil;
}
@end
