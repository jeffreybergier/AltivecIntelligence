#import "AppDelegate.h"
#include <curl/curl.h>
#include <openssl/ssl.h>
#include <openssl/crypto.h>
#include <zlib.h>

@implementation AppDelegate

-(void)applicationDidFinishLaunching:(NSNotification*)aNotification;
{
  [self replaceWindow];
}

-(BOOL)applicationOpenUntitledFile:(NSApplication*)sender;
{
  [self replaceWindow];
  return YES;
}

-(void)replaceWindow;
{
  [_window release];
  _window = nil;
  
  unsigned int mask = XPWindowStyleMaskTitled
    | XPWindowStyleMaskClosable
    | XPWindowStyleMaskResizable
    | XPWindowStyleMaskMiniaturizable;
    
  NSRect contentRect = NSMakeRect(0,0,512,512);
  NSWindow *window = [[NSWindow alloc] initWithContentRect:contentRect
                                                 styleMask:mask
                                                   backing:NSBackingStoreBuffered
                                                     defer:YES];
  [window setReleasedWhenClosed:NO];
  [window setTitle:@"CURLmac"];
  
  NSView *contentView = [[[NSView alloc] initWithFrame:contentRect] autorelease];
  
  NSTextField *label = [[[NSTextField alloc] initWithFrame:NSMakeRect(20, 20, 472, 472)] autorelease];
  [label setEditable:NO];
  [label setSelectable:YES];
  [label setBordered:NO];
  [label setDrawsBackground:NO];
  [label setFont:[NSFont fontWithName:@"Courier" size:14.0f]];
  
  NSString *curlVer = [NSString stringWithUTF8String:curl_version()];
  NSString *sslVer = [NSString stringWithUTF8String:OpenSSL_version(OPENSSL_VERSION)];
  NSString *cryptoVer = [NSString stringWithUTF8String:OpenSSL_version(OPENSSL_VERSION)];
  NSString *zlibVer = [NSString stringWithUTF8String:zlibVersion()];
  
  NSString *info = [NSString stringWithFormat:@"1. Curl:\n%@\n\n2. SSL:\n%@\n\n3. Crypto:\n%@\n\n4. Zlib:\n%@", 
                    curlVer, sslVer, cryptoVer, zlibVer];
  
  [label setStringValue:info];
  [contentView addSubview:label];
  
  [window setContentView:contentView];
  [window center];
  [window makeKeyAndOrderFront:self];
  _window = window;
}

-(void)dealloc;
{
  [_window release];
  [super dealloc];
}
@end
