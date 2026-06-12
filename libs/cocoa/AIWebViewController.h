#import <TargetConditionals.h>

#if !TARGET_OS_IPHONE

#import "AIViewController.h"

/* AIWebViewController — forced-style base for view controllers that own a
 * WebView. Subclass and override THREE methods. Do not touch -loadView or
 * the underlying WebView class. The base class guarantees:
 *
 *   1. The WebView fills the controller's bounds 100% (autoresize, no
 *      frame math in subclasses). Subclasses that need to reserve room
 *      for sibling chrome resize -webView's frame in their own
 *      -viewDidLayout — see MessageListViewController for the canonical
 *      sibling-bar pattern.
 *   2. Top/titlebar inset is whatever AppKit + WKWebView do automatically.
 *      WKWebView's _automaticallyAdjustsContentInsets defaults to YES on
 *      10.10+, which keeps page content from flowing under the toolbar on
 *      Middle/Modern. The Legacy WebKit1 path has no such concern (pre-
 *      10.11 windows don't extend content under the toolbar).
 *   3. -reloadContent re-loads whatever -contentURL points at.
 *   4. -pushJavaScript: pushes a snippet for incremental DOM updates
 *      (the appendMessage / updateMessage / prependMessages idiom in
 *      MessageListViewController).
 *   5. URLs whose scheme matches +handledURLSchemes are intercepted and
 *      delivered to -handleActionURL: instead of being navigated.
 *
 * Content contract (file:// rendered HTML):
 *   The subclass owns the rendered file. -contentURL must return a file://
 *   URL that lives **inside** baseURL_'s directory tree — WKWebView's
 *   -loadFileURL:allowingReadAccessToURL: requires the loaded file to sit
 *   under the read-access subtree (and granting that subtree is the whole
 *   point: it bypasses the opaque-origin SOP block that breaks file://
 *   image fetches under -loadHTMLString:baseURL:). Non-file URLs are
 *   loaded via -loadRequest: instead (no read-access scope applies).
 *
 * Tier policy:
 *   AICCTierLegacy        : Legacy WebKit1 WebView (the NSView from
 *                           WebKit.framework that has shipped since 10.2).
 *                           Branches on AICCCurrentTier() and dispatches
 *                           through the legacy WebPolicyDelegate hook (URL
 *                           interception) and
 *                           -stringByEvaluatingJavaScriptFromString: (JS
 *                           pushes). Content loads via -[WebFrame loadRequest:]
 *                           — the legacy WebView gives file:// pages a real
 *                           file:// origin so no read-access scoping is
 *                           needed. -reloadContent also re-applies a one-
 *                           shot hit-test fix (zero out the inner scroll
 *                           view's auto-adjusted contentInsets) because
 *                           10.10+ NSScrollView auto-inset behaviour and
 *                           WebKit1's hit-testing don't agree, mapping
 *                           mouse coords ~30 px above the rendered content
 *                           otherwise.
 *   AICCTierMiddle/Modern : WKWebView (runtime-dispatched for Tiger-SDK
 *                           compatibility). The top inset is whatever
 *                           WKWebView's built-in
 *                           _automaticallyAdjustsContentInsets does —
 *                           we don't override it. */
@interface AIWebViewController : AIViewController {
 @private
  id     webView_;          /* WKWebView * on Middle/Modern, WebView * on
                               Legacy. Typed loosely because (a) the Tiger
                               SDK lacks the WKWebView declaration and
                               (b) the legacy WebView * type carries a
                               deprecation diagnostic on modern SDKs. The
                               .m branches on AICCCurrentTier() and either
                               casts to (WebView *) under the file-level
                               -Wdeprecated-declarations pragma or routes
                               through objc_msgSend. */
  NSURL *baseURL_;
  id     navAdapter_;       /* AIWebViewNavAdapter. Serves as the
                               WKNavigationDelegate on Middle/Modern and as
                               the legacy WebPolicyDelegate on Legacy —
                               Cocoa dispatches by selector, so a single
                               adapter answers both wire formats. */
  BOOL   drawsBackground_;  /* applied to webView_ via KVC; YES by default
                               (matches WKWebView). Cached so subclasses
                               calling -setDrawsBackground: from -init…
                               (before webView_ exists) work correctly. */
  id     HACK_inspectorBackdrop_; /* NSVisualEffectView *. nil unless a slot
                                owner called
                                -HACK_installInspectorToolbarBackdrop;
                                see the installer-hooks block below for
                                why this isn't always on. Typed id so the
                                Tiger SDK (no NSVisualEffectView decl)
                                compiles cleanly. */
}

/* Designated initialiser. baseURL is required: on Middle/Modern it scopes
 * the read-access subtree handed to WKWebView's
 * -loadFileURL:allowingReadAccessToURL: so relative <img src> file paths
 * inside the loaded HTML (sticker images, message media) resolve against
 * it. On Legacy the same URL is retained for symmetry but the WebKit1
 * WebView resolves relative paths against the loaded document's own
 * location, so the value is effectively informational on that tier. */
- (id)initWithBaseURL:(NSURL *)baseURL;

/* === Subclass overrides ================================================== */

/* Custom URL schemes that should be intercepted as actions instead of
 * navigated. Return an NSArray of NSString. Default returns @[] (no
 * interception — pure read-only HTML view). Called once per navigation
 * action; cache-friendly because it's a class method. */
+ (NSArray *)handledURLSchemes;

/* The URL that -reloadContent will load. Called every time -reloadContent
 * fires. File URLs must sit inside baseURL_'s directory tree (see the
 * content contract in the class doc-comment). Default raises — every
 * subclass MUST override. */
- (NSURL *)contentURL;

/* Called for each tap (or scripted location change) whose URL's scheme is
 * listed in +handledURLSchemes. The navigation has already been cancelled
 * by the base class; the subclass typically dispatches to a delegate or
 * forwards up the responder chain via tryToPerform:. Default is a no-op. */
- (void)handleActionURL:(NSURL *)url;

/* === Base-class API the subclass *calls* ================================ */

/* Re-load from scratch: invokes -contentURL and dispatches to
 * -loadFileURL:allowingReadAccessToURL: (file URLs, scoped to baseURL_) or
 * -loadRequest: (everything else). */
- (void)reloadContent;

/* Push: evaluates a JS snippet against the current document. Fire-and-forget
 * (return value of the JS is discarded; ordering between sequential pushes
 * is preserved by WKWebView's serial web-content process). */
- (void)pushJavaScript:(NSString *)js;

/* Controls whether the underlying WKWebView paints its default opaque
 * background (the white-paper look). Defaults to YES — the standard
 * WKWebView behavior. Subclasses that want the page to inherit their
 * parent view's background colour (sheet inspector panes, chat panes
 * with a tinted background) call -setDrawsBackground:NO, typically
 * from -init…. Safe to call before -viewDidLoad — the value is cached
 * and applied to the WebView at creation time. Implemented via KVC on
 * WKWebView's `drawsBackground` key (long-standing, stable selector
 * exposed by WebKit's KVC layer; not a public property but not a
 * private SPI invocation either). */
- (BOOL)drawsBackground;
- (void)setDrawsBackground:(BOOL)drawsBackground;

/* The underlying WebView, typed `id` because it's a WKWebView on
 * Middle/Modern and a (deprecation-tagged) WebView on Legacy. Subclasses
 * that need to reserve room for sibling chrome (e.g. an in-pane bottom
 * bar) resize this view's frame in their own -viewDidLayout — its
 * autoresizing mask is widthSizable | heightSizable, so setting an
 * initial frame with a fixed bottom margin keeps that margin across
 * container resizes. nil before -viewDidLoad. */
- (id)webView;

/* === Installer hooks (called by the slot owner, not the subclass) ====== */

/* Compensates for AppKit's missing automatic toolbar vibrancy when an
 * NSSplitViewItem.inspector pane's content isn't NSScrollView-rooted —
 * which a WKWebView never is on macOS, because its scrolling lives in
 * the web content process and no NSScrollView exists in the host view
 * tree for AppKit's adjacency detector to find (the detector is the
 * one Chris Dreessen describes in WWDC14 #220 — "if your scroll view
 * isn't adjacent to the title bar, we're going to ignore it"). Installs
 * an NSVisualEffectView strip along the top of the controller's view,
 * sized to safeAreaInsets.top, that re-tracks layout on every
 * -viewDidLayout. Modern only; no-op on Middle/Legacy where the bug
 * doesn't exist (Middle's inspector uses the opaque split-item factory,
 * Legacy windows don't extend content under the toolbar). The slot
 * owner — currently AICookieCutterWindowController.accAddItemTo:vc:
 * kind: in the kind==2 && tier_==AICCTierModern branch — is the only
 * thing that knows whether the WebView is being installed into an
 * inspector slot vs a content pane vs a sheet, so it owns this call;
 * subclassers MUST NOT call this themselves (a sheet- or content-pane-
 * hosted WebView calling it would paint a phantom strip across the top
 * of its host). */
- (void)HACK_installInspectorToolbarBackdrop;

@end

#endif /* !TARGET_OS_IPHONE */
