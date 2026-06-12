#import <TargetConditionals.h>

#if !TARGET_OS_IPHONE

#import "AIWebViewController.h"
#import "AICookieCutterWindowController.h"
#import <objc/message.h>

/* Legacy WebKit1 surface. WebView / WebFrame / WebPolicyDelegate carry the
 * 10.14-era deprecation diagnostic on modern SDKs, so the entire @implementation
 * below is wrapped in a clang -Wdeprecated-declarations push/pop. */
#ifdef __clang__
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
#import <WebKit/WebKit.h>
#ifdef __clang__
#pragma clang diagnostic pop
#endif

/* WKNavigationActionPolicy values are stable since 10.10. Hard-code them so
 * we don't need the WebKit header (the Tiger SDK lacks WKNavigationDelegate
 * entirely, and importing <WebKit/WebKit.h> wouldn't surface the modern
 * declarations anyway). */
enum {
  AIWKPolicyCancel = 0,
  AIWKPolicyAllow  = 1
};

/* Stable Block ABI layout (Apple "Block ABI Apple Version"). The same struct
 * gives the correct invoke-pointer offset on every arch we ship:
 *   32-bit (PPC, x86):  isa=0  flags=4  reserved=8   invoke=12
 *   64-bit (x86_64, arm64): isa=0  flags=8  reserved=12  invoke=16
 * because (a) C aligns each scalar to its natural boundary, and (b) the
 * function pointer follows the two ints which together pad to the pointer
 * alignment. This lets us call the WKNavigationDelegate's decisionHandler
 * block without ever writing a `^{ ... }` literal — the Tiger PPC toolchain
 * doesn't support blocks in source, only the runtime ABI to invoke one. */
struct AIBlockLayout {
  void *isa;
  int   flags;
  int   reserved;
  void (*invoke)(void *, ...);
};

static void aiInvokeDecisionHandler(id handler, NSInteger policy) {
  struct AIBlockLayout *b;
  if (!handler) return;
  b = (struct AIBlockLayout *)handler;
  if (!b->invoke) return;
  ((void (*)(id, NSInteger))b->invoke)(handler, policy);
}

/* Ad-hoc WKNavigationDelegate. Not declared as conforming to
 * WKNavigationDelegate because that protocol is absent from the Tiger SDK;
 * the runtime dispatches by selector regardless. owner_ is a weak back-edge
 * — AIWebViewController retains us, never the other way around. */
@interface AIWebViewNavAdapter : NSObject {
 @private
  AIWebViewController *owner_;
}
- (id)initWithOwner:(AIWebViewController *)owner;
- (void)aiClearOwner;
@end

/* Forward declarations for the per-tier helpers below. The Tiger-era GCC PPC
 * slice walks @implementation top-down and warns "may not respond to ..." when
 * a call site precedes the method definition (clang scans the whole body, so
 * this is purely a GCC 4.x concern). Listing the helpers here keeps the
 * helpers themselves private to the .m. */
@interface AIWebViewController ()
- (void)aiCreateLegacyWebView;
- (void)aiCreateModernWebView;
- (void)HACK_layoutInspectorBackdrop;
- (void)aiDisableLegacyAutoContentInsets;
@end

#ifdef __clang__
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif

@implementation AIWebViewController

- (id)initWithBaseURL:(NSURL *)baseURL;
{
  if (!baseURL) {
    [self release];
    [NSException raise:NSInvalidArgumentException
                format:@"[AIWebViewController.init] baseURL is required"];
    return nil;
  }
  if ((self = [super init])) {
    baseURL_         = [baseURL retain];
    drawsBackground_ = YES;   /* WKWebView's default; flipped via the
                                 -setDrawsBackground: accessor. */
  }
  return self;
}

/* Container view + WKWebView subview, mirroring MessageListVC / StickerVC.
 * Keeping the WebView as a subview (rather than as -view itself) lets AppKit
 * wire the responder chain through the container — which AIViewController's
 * -setView: already prepares — without us having to second-guess what
 * setNavigationDelegate: does to the responder hookup. */
- (void)loadView;
{
  NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 400)];
  [root setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [self setView:root];
  [root release];
}

- (void)viewDidLoad;
{
  [super viewDidLoad];
  if (AICCCurrentTier() == AICCTierLegacy) [self aiCreateLegacyWebView];
  else                                     [self aiCreateModernWebView];
  /* Autoresizing keeps the WebView pinned to its superview's bounds.
   * Subclasses that overlay sibling chrome (see MessageListViewController)
   * reset the WebView's frame in their own -viewDidLayout — the
   * widthSizable | heightSizable mask preserves whatever fixed margins
   * they leave on the bottom (or any other edge) across container resizes.
   * Cast to NSView * so the compiler picks NSView's autoresizingMask
   * (NSAutoresizingMaskOptions) over the same-named CALayer selector — id
   * leaves both visible and the modern SDK warns under
   * -Wobjc-multiple-method-names. WKWebView and the legacy WebView are
   * both NSViews on macOS, so the cast is sound on either tier. */
  [(NSView *)webView_ setAutoresizingMask:
      NSViewWidthSizable | NSViewHeightSizable];
  [[self view] addSubview:webView_];
}

/* Legacy WebKit1 WebView. Available since 10.2. Policy decisions route
 * through the legacy WebPolicyDelegate hook on the same AIWebViewNavAdapter
 * that handles WKNavigationDelegate on the modern path. */
- (void)aiCreateLegacyWebView;
{
  WebView *wv = [[WebView alloc] initWithFrame:[[self view] bounds]
                                     frameName:nil
                                     groupName:nil];
  webView_ = wv;
  navAdapter_ = [[AIWebViewNavAdapter alloc] initWithOwner:self];
  [wv setPolicyDelegate:(id)navAdapter_];
  if ([wv respondsToSelector:@selector(setDrawsBackground:)])
    [wv setDrawsBackground:drawsBackground_];
}

/* Modern WKWebView, runtime-dispatched: the Tiger SDK doesn't declare
 * WKWebView or its selectors, so we look the class up by name and route
 * every message through objc_msgSend. */
- (void)aiCreateModernWebView;
{
  Class wkCls = NSClassFromString(@"WKWebView");
  if (!wkCls)
    [NSException raise:NSInternalInconsistencyException
                format:@"[AIWebViewController.viewDidLoad] WKWebView class "
                       @"missing at runtime on non-Legacy tier (=%d). Init "
                       @"guard should have caught this.",
                       (int)AICCCurrentTier()];
  webView_ = [[wkCls alloc] initWithFrame:[[self view] bounds]];
  navAdapter_ = [[AIWebViewNavAdapter alloc] initWithOwner:self];
  /* -setNavigationDelegate: is a WKWebView selector; route via objc_msgSend
   * so the Tiger SDK (which doesn't declare it) compiles cleanly. */
  ((void (*)(id, SEL, id))objc_msgSend)(
      webView_, @selector(setNavigationDelegate:), navAdapter_);
  /* Apply the cached drawsBackground state — defaults to YES, so this is a
   * no-op for the common case, but a subclass that called
   * -setDrawsBackground:NO before -viewDidLoad fired needs us to push the
   * setting through now that webView_ exists. */
  [(NSView *)webView_ setValue:[NSNumber numberWithBool:drawsBackground_]
                        forKey:@"drawsBackground"];
}

/* Inspector backdrop tracks the safe-area-top strip; no-op when nothing
 * was installed. */
- (void)viewDidLayout;
{
  [super viewDidLayout];
  if (![[self view] window]) return;
  [self HACK_layoutInspectorBackdrop];
}

/* Sizes the inspector toolbar-backdrop strip to (0, top, width,
 * safeAreaInsets.top) of the controller's view. safeAreaInsets is
 * 11.0+; we already gate the only caller on AICCTierModern, but probe
 * defensively for the selector so misuse doesn't crash. NSInvocation
 * because the return is an NSEdgeInsets struct (four CGFloats packed)
 * that objc_msgSend can't safely cast to across PPC/x86/arm64. */
- (void)HACK_layoutInspectorBackdrop;
{
  SEL       sel;
  NSMethodSignature *sig;
  NSInvocation *inv;
  struct { CGFloat top, left, bottom, right; } insets;
  NSView   *view;
  NSRect    bounds;
  NSRect    frame;
  if (!HACK_inspectorBackdrop_) return;
  view = [self view];
  if (!view) return;
  insets.top = 0.0; insets.left = 0.0;
  insets.bottom = 0.0; insets.right = 0.0;
  sel = @selector(safeAreaInsets);
  if ([view respondsToSelector:sel]) {
    sig = [view methodSignatureForSelector:sel];
    if (sig) {
      inv = [NSInvocation invocationWithMethodSignature:sig];
      [inv setTarget:view];
      [inv setSelector:sel];
      [inv invoke];
      [inv getReturnValue:&insets];
    }
  }
  bounds = [view bounds];
  frame.origin.x    = bounds.origin.x;
  frame.origin.y    = bounds.origin.y + bounds.size.height - insets.top;
  frame.size.width  = bounds.size.width;
  frame.size.height = insets.top;
  if (frame.size.height < 0.0) frame.size.height = 0.0;
  [(NSView *)HACK_inspectorBackdrop_ setFrame:frame];
}

- (void)HACK_installInspectorToolbarBackdrop;
{
  Class veC;
  id    ve;
  if (AICCCurrentTier() != AICCTierModern) return;
  if (HACK_inspectorBackdrop_) return;   /* idempotent */
  veC = NSClassFromString(@"NSVisualEffectView");
  if (!veC) return;
  ve = [[veC alloc] initWithFrame:NSZeroRect];
  /* Numeric literals because the Tiger SDK doesn't carry these enums:
   *   NSVisualEffectMaterialTitlebar            = 3
   *   NSVisualEffectBlendingModeWithinWindow    = 1
   *   NSVisualEffectStateFollowsWindowActiveState = 0
   * Titlebar material matches what AppKit's automatic auto-vibrancy
   * would have rendered for an NSScrollView-rooted inspector;
   * within-window blending keeps it from punching through to the
   * desktop; follows-window-active-state matches the toolbar's own
   * deactivation behaviour so the strip dims together with the rest
   * of the chrome when the window loses focus. */
  ((void (*)(id, SEL, NSInteger))objc_msgSend)(
      ve, @selector(setMaterial:), (NSInteger)3);
  ((void (*)(id, SEL, NSInteger))objc_msgSend)(
      ve, @selector(setBlendingMode:), (NSInteger)1);
  ((void (*)(id, SEL, NSInteger))objc_msgSend)(
      ve, @selector(setState:), (NSInteger)0);
  [(NSView *)ve setAutoresizingMask:
      NSViewWidthSizable | NSViewMinYMargin];
  HACK_inspectorBackdrop_ = ve;   /* +1 from alloc, owned by ivar */
  /* The slot owner has already triggered viewDidLoad via [vc view],
   * so webView_ is a subview by now. Add the strip last so it sits on
   * top — the WebView fills the bounds including the top safe-area
   * region, and without an over-strip the rendered page would show
   * through the unfrosted toolbar. */
  if ([self view]) {
    [[self view] addSubview:(NSView *)ve];
    [self HACK_layoutInspectorBackdrop];
  }
}

- (void)reloadContent;
{
  NSURL *url = [self contentURL];
  if (!url) return;

  if (AICCCurrentTier() == AICCTierLegacy) {
    /* Legacy WebKit1 has no opaque-origin SOP block — a file:// page can
     * fetch sibling file:// resources directly, so loadRequest: handles
     * both file and http(s) URLs uniformly. */
    WebView *wv = (WebView *)webView_;
    [[wv mainFrame] loadRequest:[NSURLRequest requestWithURL:url]];
    [self aiDisableLegacyAutoContentInsets];
    return;
  }

  /* loadFileURL:allowingReadAccessToURL: is the *only* WKWebView load entry
   * point that gives the page a real file:// origin — loadHTMLString:baseURL:
   * always assigns an opaque origin, even with a file:// baseURL, which
   * silently blocks every <img src> fetch as cross-origin. Anything that
   * lives on disk under baseURL_ should come through here. Non-file URLs
   * (http/https) go through loadRequest:, where SOP behaves normally. */
  if ([url isFileURL]) {
    ((void (*)(id, SEL, id, id))objc_msgSend)(
        webView_, @selector(loadFileURL:allowingReadAccessToURL:),
        url, baseURL_);
    return;
  }
  ((void (*)(id, SEL, id))objc_msgSend)(
      webView_, @selector(loadRequest:),
      [NSURLRequest requestWithURL:url]);
}

/* On 10.10+ NSScrollView auto-adjusts contentInsets for the safe area, but
 * the legacy WebView's hit-testing doesn't account for that, mapping mouse
 * coords ~30 px above the rendered content. Disabling auto-adjust + zeroing
 * the insets keeps render and hit-test in lock-step. Re-applied after every
 * load because WebView recreates the inner scroll view on navigation and the
 * defaults flip back. respondsToSelector: gates the call so pre-10.10 builds
 * skip it (the selectors don't exist there). */
- (void)aiDisableLegacyAutoContentInsets;
{
  WebView *wv = (WebView *)webView_;
  id frameView, docView, scroll;
  SEL setAuto, setIns;
  frameView = [[wv mainFrame] frameView];
  if (!frameView) return;
  docView = [frameView performSelector:@selector(documentView)];
  if (!docView) return;
  scroll = [docView performSelector:@selector(enclosingScrollView)];
  if (!scroll) return;
  setAuto = @selector(setAutomaticallyAdjustsContentInsets:);
  if ([scroll respondsToSelector:setAuto])
    ((void (*)(id, SEL, BOOL))objc_msgSend)(scroll, setAuto, (BOOL)NO);
  setIns = @selector(setContentInsets:);
  if ([scroll respondsToSelector:setIns]) {
    struct { CGFloat top, left, bottom, right; } zero = {0.0, 0.0, 0.0, 0.0};
    NSMethodSignature *sig = [scroll methodSignatureForSelector:setIns];
    NSInvocation *inv;
    if (!sig) return;
    inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:scroll];
    [inv setSelector:setIns];
    [inv setArgument:&zero atIndex:2];
    [inv invoke];
  }
}

/* Fire-and-forget. On Middle/Modern, passing nil for the completion handler
 * keeps this file block-free in source so the Tiger PPC slice compiles —
 * WKWebView treats a nil handler as "discard the result," which is what
 * every appendMessage / updateMessage call site wants anyway. On Legacy,
 * the WebKit1 synchronous JS bridge serves the same fire-and-forget role:
 * the returned NSString is ignored. */
- (void)pushJavaScript:(NSString *)js;
{
  if (![js length]) return;
  if (AICCCurrentTier() == AICCTierLegacy) {
    [(WebView *)webView_ stringByEvaluatingJavaScriptFromString:js];
    return;
  }
  ((void (*)(id, SEL, id, id))objc_msgSend)(
      webView_, @selector(evaluateJavaScript:completionHandler:),
      js, (id)nil);
}

- (BOOL)drawsBackground;
{
  return drawsBackground_;
}

/* Caches the new value AND pushes it to webView_ when one already exists.
 * Calling this before -viewDidLoad fires is supported — webView_ is nil at
 * that point, the cached value gets applied in -viewDidLoad's create-helper.
 * Legacy WebView exposes -setDrawsBackground: directly (public since 10.0);
 * WKWebView only exposes it via KVC. */
- (void)setDrawsBackground:(BOOL)drawsBackground;
{
  drawsBackground_ = drawsBackground ? YES : NO;
  if (!webView_) return;
  if (AICCCurrentTier() == AICCTierLegacy) {
    WebView *wv = (WebView *)webView_;
    if ([wv respondsToSelector:@selector(setDrawsBackground:)])
      [wv setDrawsBackground:drawsBackground_];
    return;
  }
  [(NSView *)webView_ setValue:[NSNumber numberWithBool:drawsBackground_]
                        forKey:@"drawsBackground"];
}

- (id)webView;
{
  return webView_;
}

+ (NSArray *)handledURLSchemes;
{
  return [NSArray array];
}

- (NSURL *)contentURL;
{
  [NSException raise:NSInternalInconsistencyException
              format:@"[AIWebViewController.contentURL] subclass %@ must "
                     @"override -contentURL", [self class]];
  return nil;
}

- (void)handleActionURL:(NSURL *)url;
{
  (void)url;
}

- (void)dealloc;
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  /* Tear the delegate edge BEFORE releasing the WebView: an in-flight nav
   * decision firing during -release could reach a half-dead adapter. */
  if (webView_) {
    if (AICCCurrentTier() == AICCTierLegacy) {
      [(WebView *)webView_ setPolicyDelegate:nil];
    } else {
      ((void (*)(id, SEL, id))objc_msgSend)(
          webView_, @selector(setNavigationDelegate:), (id)nil);
    }
  }
  [navAdapter_ aiClearOwner];
  [navAdapter_ release];
  [webView_ release];
  [baseURL_ release];
  [HACK_inspectorBackdrop_ release];
  [super dealloc];
}

@end

#pragma mark - AIWebViewNavAdapter

@implementation AIWebViewNavAdapter

- (id)initWithOwner:(AIWebViewController *)owner;
{
  if (!owner) {
    [self release];
    [NSException raise:NSInvalidArgumentException
                format:@"[AIWebViewNavAdapter.init] owner is required"];
    return nil;
  }
  if ((self = [super init])) {
    owner_ = owner;   /* weak */
  }
  return self;
}

- (void)aiClearOwner;
{
  owner_ = nil;
}

/* WKNavigationDelegate's decidePolicyForNavigationAction:decisionHandler:.
 * Implemented with an `id` for the decisionHandler so the source has no block
 * literal — see the AIBlockLayout doc-comment for the runtime invocation
 * trick. Allows everything except URLs whose scheme is in
 * +[owner_.class handledURLSchemes], which are cancelled and dispatched to
 * -handleActionURL: instead. */
- (void)webView:(id)webView
    decidePolicyForNavigationAction:(id)action
                    decisionHandler:(id)handler;
{
  NSURL *url;
  NSURLRequest *req;
  NSArray *schemes;
  NSUInteger i, n;
  NSInteger policy = AIWKPolicyAllow;
  (void)webView;

  if (!owner_) {
    aiInvokeDecisionHandler(handler, policy);
    return;
  }

  req = (NSURLRequest *)[action performSelector:@selector(request)];
  url = [req URL];
  if (!url) {
    aiInvokeDecisionHandler(handler, policy);
    return;
  }

  schemes = [[owner_ class] handledURLSchemes];
  n = [schemes count];
  for (i = 0; i < n; i++) {
    NSString *s = [schemes objectAtIndex:i];
    if ([[url scheme] isEqualToString:s]) {
      policy = AIWKPolicyCancel;
      [owner_ handleActionURL:url];
      break;
    }
  }
  aiInvokeDecisionHandler(handler, policy);
}

/* Legacy WebPolicyDelegate's
 *   webView:decidePolicyForNavigationAction:request:frame:decisionListener:
 * The same adapter answers both this and the modern WKNavigationDelegate
 * selector — Cocoa dispatches by selector, so the WebView class on the wire
 * picks the right entry point at runtime. The listener takes -use / -ignore
 * / -download (see <WebKit/WebPolicyDelegate.h>); we never download. */
- (void)webView:(id)webView
    decidePolicyForNavigationAction:(NSDictionary *)actionInformation
                            request:(NSURLRequest *)request
                              frame:(id)frame
                   decisionListener:(id)listener;
{
  NSURL *url;
  NSArray *schemes;
  NSUInteger i, n;
  (void)webView; (void)actionInformation; (void)frame;

  if (!listener) return;
  if (!owner_) { [listener performSelector:@selector(use)]; return; }
  url = [request URL];
  if (!url)    { [listener performSelector:@selector(use)]; return; }

  schemes = [[owner_ class] handledURLSchemes];
  n = [schemes count];
  for (i = 0; i < n; i++) {
    NSString *s = [schemes objectAtIndex:i];
    if ([[url scheme] isEqualToString:s]) {
      [listener performSelector:@selector(ignore)];
      [owner_ handleActionURL:url];
      return;
    }
  }
  [listener performSelector:@selector(use)];
}

@end

#ifdef __clang__
#pragma clang diagnostic pop
#endif

#endif /* !TARGET_OS_IPHONE */
