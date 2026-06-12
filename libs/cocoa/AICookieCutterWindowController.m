#import <TargetConditionals.h>

#if !TARGET_OS_IPHONE

#import "AICookieCutterWindowController.h"
#import "AIWebViewController.h"
#import <objc/runtime.h>

static const AIMinMidMax kDefaultPaneLimits = { 200.0, 250.0, 300.0 };

#pragma mark - OS tier detection

/* Tier enum + AICCCurrentTier() live in AICookieCutterWindowController.h so
 * XPAppKit (and any other macOS-side caller) can share the same existence
 * proof. The header has the full doc comment on what each tier means. */

/* Sub-Legacy gate: NSAppKitVersionNumber10_5 = 949 — i.e. "10.5+ Leopard or
 * later". Used by AISplitView for the 10.4-vs-10.5 setDividerStyle: gap,
 * which sits below our coarse-grained Legacy floor and so doesn't deserve
 * its own enum slot. */
#define AI_kAppKitVersion10_5  949.0

/* Above-Modern gate: 14.0 Sonoma = 2487. Toggle-Inspector and the inspector
 * tracking separator ship in the toolbar with macOS 14, well after our Modern
 * floor (11.0). One fine-grained check is cheaper than another tier slot. */
#define AI_kAppKitVersion14_0  2487.0

#pragma mark - NSInvocation / performSelector dispatch helpers

/* The tier check at every call site is the existence proof — no
 * respondsToSelector: guard is needed. NSInvocation is the dispatch
 * mechanism for non-(id) signatures: the Tiger SDK never declares these
 * AppKit symbols, so the compiler cannot type-check an objc_msgSend cast.
 * For (id)->(id) shapes performSelector:withObject: is shorter and equally
 * warning-free. */

static void accInvokeArg1(id target, SEL sel, void *arg) {
  NSMethodSignature *sig = [target methodSignatureForSelector:sel];
  NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
  [inv setTarget:target];
  [inv setSelector:sel];
  [inv setArgument:arg atIndex:2];
  [inv invoke];
}

static void accSetBOOL(id t, SEL s, BOOL v)           { accInvokeArg1(t, s, &v); }
static void accSetCGFloat(id t, SEL s, CGFloat v)     { accInvokeArg1(t, s, &v); }
static void accSetInteger(id t, SEL s, NSInteger v)   { accInvokeArg1(t, s, &v); }
static void accSetUInteger(id t, SEL s, NSUInteger v) { accInvokeArg1(t, s, &v); }

static BOOL accGetBOOL(id target, SEL sel) {
  NSMethodSignature *sig = [target methodSignatureForSelector:sel];
  NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
  [inv setTarget:target];
  [inv setSelector:sel];
  [inv invoke];
  BOOL r = NO;
  [inv getReturnValue:&r];
  return r;
}

#pragma mark - Tier-gated AppKit shims

static CGFloat accClamp(CGFloat v, CGFloat lo, CGFloat hi) {
  if (v < lo) return lo;
  if (v > hi) return hi;
  return v;
}

/* Preferred starting width for a pane is the caller-supplied `mid`. */
static CGFloat accPreferredWidth(AIMinMidMax l) {
  return l.mid;
}

#pragma mark - AISplitView (thin-divider NSSplitView for the Legacy path)

/* Private NSSplitView subclass used by the Legacy tier (raw split view, no
 * NSSplitViewController). On 10.5 Leopard and later, AppKit supports a
 * thin-divider style via -setDividerStyle: and draws / measures the divider
 * itself. On 10.4 Tiger that selector is absent entirely, so we fake a
 * 1-pt divider by overriding -dividerThickness and -drawDividerInRect:.
 *
 * Runtime gate uses NSAppKitVersionNumber rather than our AICCTier enum:
 * the 10.4-vs-10.5 boundary sits below Legacy's floor (≥ 10.11 is Middle),
 * and one local gate is cheaper than promoting a fourth tier. */

@interface AISplitView : NSSplitView
@end

@implementation AISplitView

- (id)initWithFrame:(NSRect)frame;
{
  if ((self = [super initWithFrame:frame])) {
    if (NSAppKitVersionNumber >= AI_kAppKitVersion10_5) {
      /* NSSplitViewDividerStyleThin = 2. The selector itself only exists
       * on 10.5+, so guard the call. */
      accSetInteger(self, @selector(setDividerStyle:), 2);
    }
  }
  return self;
}

- (CGFloat)dividerThickness;
{
  if (NSAppKitVersionNumber >= AI_kAppKitVersion10_5) return [super dividerThickness];
  return 1.0;
}

- (void)drawDividerInRect:(NSRect)rect;
{
  if (NSAppKitVersionNumber >= AI_kAppKitVersion10_5) {
    [super drawDividerInRect:rect];
    return;
  }
  [AIColorWindowFrame set];
  NSRectFill(rect);
}

@end

/* AIViewController and its private NSViewController adapter live in
 * AIViewController.{h,m}. AIVCAdapterNew is defined there with external
 * linkage so this file's accAddItemTo: can wrap a pane VC for the modern
 * NSSplitViewItem factory. */
id AIVCAdapterNew(AIViewController *content);

#pragma mark - AICookieCutterWindowController

@interface AICookieCutterWindowController ()
- (void)accAssertPanesMutable:(SEL)setter;
- (void)accCheckLimits:(AIMinMidMax)l setter:(SEL)setter;
/* One-time construction step (see implementation) — not a reusable query. */
- (id)accAddItemTo:(id)svc vc:(AIViewController *)vc kind:(int)kind;
- (void)accApplyModernLayoutToItem:(id)item view:(NSView *)pv kind:(int)kind;
- (NSView *)accPanelFor:(AIViewController *)vc limits:(AIMinMidMax)lim;
- (void)accLayoutLegacy;
- (void)accCollapseInspectorLegacy:(BOOL)collapse;
- (void)accCollapseSidebarLegacy:(BOOL)collapse;
- (void)buildSplitVC;
- (void)buildLegacy;
- (void)aiLegacyFireWillAppear;
- (void)aiLegacyFireDidAppear;
- (void)accApplySplitAutosaveName;
@end

@implementation AICookieCutterWindowController

- (id)initWithTitle:(NSString *)title autosaveName:(NSString *)autosaveName;
{
  /* Nib name is intentionally bogus and never loaded: -loadWindow is fully
   * overridden and never calls super, so NSWindowController's nib-resolving
   * default impl (the only thing that reads this name) never runs. */
  if ((self = [super initWithWindowNibName:@"ignored"])) {
    windowTitle_        = [title copy];
    autosaveName_       = [autosaveName copy];
    sidebarLimits_      = kDefaultPaneLimits;
    inspectorLimits_    = kDefaultPaneLimits;
    sidebarW_           = accPreferredWidth(sidebarLimits_);
    inspectorW_         = accPreferredWidth(inspectorLimits_);
    inspectorCollapsed_ = YES;
  }
  return self;
}

- (void)dealloc;
{
  [NSObject cancelPreviousPerformRequestsWithTarget:self];
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [windowTitle_ release];
  [autosaveName_ release];
  [splitAutosaveName_ release];
  [sidebarVC_ release];
  [detailVC_ release];
  [inspectorVC_ release];
  [splitViewController_ release];
  [sidebarItem_ release];
  [inspectorItem_ release];
  [splitView_ release];
  [super dealloc];
}

#pragma mark Accessors

- (AIViewController *)sidebarViewController;
{
  return sidebarVC_;
}

- (AIViewController *)detailViewController;
{
  return detailVC_;
}

- (AIViewController *)inspectorViewController;
{
  return inspectorVC_;
}

/* Single source of truth for "where does the live NSSplitView live this
 * tier?". Everything that needs to touch the split view from outside the
 * build phase routes through here: -accApplySplitAutosaveName, and any
 * subclasser that needs to address a divider by index.
 *
 * The Middle/Modern branch dispatches through performSelector: because
 * splitViewController_ is typed `id` (Tiger SDK has no NSSplitViewController
 * symbol); using -splitView directly would silently bind to whatever
 * -splitView is in scope. */
- (NSSplitView *)AI_splitView;
{
  if (splitView_) return splitView_;
  if (splitViewController_) {
    return (NSSplitView *)[splitViewController_
        performSelector:@selector(splitView)];
  }
  return nil;
}
/* On Middle/Modern AppKit owns collapse state and mutates it through paths
 * we never see (NSToolbarToggleSidebarItem, divider drags), so the cached
 * ivar is unreliable — query the live NSSplitViewItem instead. The ivars
 * remain the source of truth only on Legacy, where splitViewDidResize-
 * Subviews: keeps them honest. */
- (BOOL)isSidebarCollapsed;
{
  if (tier_ >= AICCTierMiddle)
    return accGetBOOL(sidebarItem_, @selector(isCollapsed));
  return sidebarCollapsed_;
}

- (BOOL)isInspectorCollapsed;
{
  if (tier_ >= AICCTierMiddle)
    return accGetBOOL(inspectorItem_, @selector(isCollapsed));
  return inspectorCollapsed_;
}

- (AIMinMidMax)sidebarWidthLimits;
{
  return sidebarLimits_;
}

- (AIMinMidMax)inspectorWidthLimits;
{
  return inspectorLimits_;
}

/* Loud on misuse, mirroring accAssertPanesMutable:: a band that breaks
 * 0 <= min <= mid <= max would silently corrupt every layout calculation. */
- (void)accCheckLimits:(AIMinMidMax)l setter:(SEL)setter;
{
  if (l.min >= 0.0 && l.mid >= l.min && l.max >= l.mid) return;
  [NSException raise:NSInvalidArgumentException
              format:@"[AICookieCutterWindowController %@] invalid width "
                     @"band {min=%g, mid=%g, max=%g}; require "
                     @"0 <= min <= mid <= max.",
                     NSStringFromSelector(setter), l.min, l.mid, l.max];
}

- (void)setSidebarWidthLimits:(AIMinMidMax)limits;
{
  [self accAssertPanesMutable:_cmd];
  [self accCheckLimits:limits setter:_cmd];
  sidebarLimits_ = limits;
}

- (void)setInspectorWidthLimits:(AIMinMidMax)limits;
{
  [self accAssertPanesMutable:_cmd];
  [self accCheckLimits:limits setter:_cmd];
  inspectorLimits_ = limits;
}

/* Settable any time (unlike the pane / width setters that raise post-load).
 * Pre-load: stored and applied during buildLegacy/buildSplitVC. Post-load:
 * applied immediately, which triggers NSSplitView's built-in restore-from-
 * defaults path. nil clears. */
- (void)setSplitViewAutosaveName:(NSString *)name;
{
  if (splitAutosaveName_ == name) return;
  [splitAutosaveName_ release];
  splitAutosaveName_ = [name copy];
  [self accApplySplitAutosaveName];
}

/* Routes the stored name to whichever NSSplitView the active tier built.
 * No-op before the split view exists (called again from build*). Also a
 * no-op on 10.4 Tiger: -[NSSplitView setAutosaveName:] was introduced in
 * 10.5 Leopard, so on Tiger we silently skip divider-position persistence
 * rather than raising "selector not recognized". The selector is gated by
 * -respondsToSelector: rather than the file's usual NSAppKitVersionNumber
 * tier check because the receiver here may be the AISplitView subclass
 * *or* NSSplitViewController's underlying split view, and asking the
 * receiver itself is the most direct existence proof. */
- (void)accApplySplitAutosaveName;
{
  NSSplitView *sv = [self AI_splitView];
  SEL sel = @selector(setAutosaveName:);
  if (!sv) return;
  if (![sv respondsToSelector:sel]) return;
  [sv performSelector:sel withObject:splitAutosaveName_];
}

/* The panes are baked into the split view in -windowDidLoad and never
 * re-read. Mutating one afterward would no-op invisibly, so make it loud. */
- (void)accAssertPanesMutable:(SEL)setter;
{
  if (![self isWindowLoaded]) return;
  [NSException raise:NSInvalidArgumentException
              format:@"[AICookieCutterWindowController %@] called after the "
                     @"window loaded; set all pane view controllers before "
                     @"-showWindow:/-window.",
                     NSStringFromSelector(setter)];
}

- (void)setSidebarViewController:(AIViewController *)vc;
{
  [self accAssertPanesMutable:_cmd];
  if (vc == sidebarVC_) return;
  [sidebarVC_ release];
  sidebarVC_ = [vc retain];
}

- (void)setDetailViewController:(AIViewController *)vc;
{
  [self accAssertPanesMutable:_cmd];
  if (vc == detailVC_) return;
  [detailVC_ release];
  detailVC_ = [vc retain];
}

- (void)setInspectorViewController:(AIViewController *)vc;
{
  [self accAssertPanesMutable:_cmd];
  if (vc == inspectorVC_) return;
  [inspectorVC_ release];
  inspectorVC_ = [vc retain];
}

#pragma mark Window

/* Frame-autosave key for this window, or nil when the controller was created
 * without an autosaveName_. Single source of truth for the "AICCWindow-"
 * prefix: -loadWindow uses it for the initial setFrameAutosaveName:/
 * setFrameUsingName:, and -buildSplitVC re-applies it after
 * -setContentViewController: resizes the window (see the note there). */
- (NSString *)accFrameAutosaveName;
{
  return autosaveName_
    ? [@"AICCWindow-" stringByAppendingString:autosaveName_]
    : nil;
}

- (void)loadWindow;
{
  AIWindowStyleMask mask = AIWindowStyleMaskTitled
                         | AIWindowStyleMaskClosable
                         | AIWindowStyleMaskMiniaturizable
                         | AIWindowStyleMaskResizable;
  /* Lift the content view under the titlebar so a subclass-installed
   * toolbar can sit seamlessly above the split view. The 1<<15 bit is
   * meaningful on 10.10+ and silently ignored below; the runtime gate
   * keeps Yosemite (where the bit first took effect) on the legacy
   * presentation, in line with tier_ < Middle policy elsewhere. */
  if (AICCCurrentTier() >= AICCTierMiddle)
    mask |= AIWindowStyleMaskFullSizeContentView;

  NSWindow *window = [[[NSWindow alloc]
      initWithContentRect:NSMakeRect(0, 0, 800, 600)
                styleMask:mask
                  backing:NSBackingStoreBuffered
                    defer:NO] autorelease];
  [window setTitle:(windowTitle_ ? windowTitle_ : @"")];
  [window setReleasedWhenClosed:NO];
  /* Opt into the green-button full-screen action. NOT a style-mask bit:
   * NSWindowStyleMaskFullScreen is an AppKit-managed read-only indicator,
   * whereas NSWindowCollectionBehaviorFullScreenPrimary (= 1 << 7) is
   * the actual opt-in. setCollectionBehavior: is 10.5+; the runtime tier
   * gate keeps us well above that floor, and accSetUInteger does the
   * signature lookup via NSInvocation so the Tiger SDK (which doesn't
   * declare the selector) still compiles clean. */
  if (AICCCurrentTier() >= AICCTierMiddle)
    accSetUInteger(window, @selector(setCollectionBehavior:),
                   AIWindowCollectionBehaviorFullScreenPrimary);
  /* 640x480 floor: even with both side panes pinned to their minimum
   * thickness this leaves a usable content column plus dividers.
   * Subclassers may override. */
  [window setMinSize:NSMakeSize(640.0, 480.0)];
  NSString *frameName = [self accFrameAutosaveName];
  if (frameName) {
    /* Restore the saved frame. setFrameUsingName: reads the named default
     * directly, so it does not depend on the window's frameAutosaveName being
     * set first — which is just as well, because the controller clobbers that
     * (see the autosave-enable block after -setWindow: below). */
    BOOL restored = [window setFrameUsingName:frameName];
    NSLog(@"[AICookieCutterWindowController.loadWindow] setFrameUsingName:%@ -> %@",
          frameName, restored ? @"YES (restored)" : @"NO (no saved frame; centering)");
    if (!restored) [window center];
  } else {
    NSLog(@"[AICookieCutterWindowController.loadWindow] no autosaveName_; centering");
    [window center];
  }

  [self setWindow:window];

  /* Enable frame AUTOSAVING through the controller, not the window. An
   * NSWindowController owns its own windowFrameAutosaveName (default @"") and
   * pushes it onto the window during setup, silently clearing any name set
   * with -[NSWindow setFrameAutosaveName:]. With no live autosave name the
   * window never writes its frame back on resize/move — so the first saved
   * frame is the only one that ever sticks, which is the bug. Owning the name
   * at the controller level makes it survive; turning off cascading keeps the
   * restored position from being nudged when the window (or a sibling
   * account's window) is shown. Must run AFTER -setWindow: so the controller
   * has a window to apply it to. */
  if (frameName) {
    [self setShouldCascadeWindows:NO];
    [self setWindowFrameAutosaveName:frameName];
  }
}

- (void)windowDidLoad;
{
  [super windowDidLoad];
  if (!sidebarVC_)   sidebarVC_   = [[AIViewController alloc] init];
  if (!detailVC_)    detailVC_    = [[AIViewController alloc] init];
  if (!inspectorVC_) inspectorVC_ = [[AIViewController alloc] init];

  tier_ = AICCCurrentTier();
  NSLog(@"[AICookieCutterWindowController.windowDidLoad] tier=%d", (int)tier_);
  switch (tier_) {
    case AICCTierLegacy:
      /* Raw NSSplitView path — no NSSplitViewController on this tier. */
      [self buildLegacy];
      break;
    case AICCTierMiddle:
    case AICCTierModern:
      [self buildSplitVC];
      /* Modern AppKit force-promotes WebView and other AV/CoreAnimation
       * controls to layer-backed. Mixed layer-backed and non-layered siblings
       * always composite — and hit-test — the layered ones on top, regardless
       * of subview Z-order. Opting the window's contentView in propagates
       * layer-backing to every VC view this window will ever host, so the
       * addSubview: ordering rule for hit testing works again (e.g. a
       * segmented control overlaid on a WebView remains clickable). */
      [[[self window] contentView] setWantsLayer:YES];
      break;
  }

  /* Toolbar setup is intentionally not done here; subclassers install their
   * own NSToolbar (typically in -windowDidLoad after calling super) using
   * the AI* / AIUnavailable* toolbar item identifiers declared in the
   * header to pick the right item for the running OS. */
}

#pragma mark Split-VC path (Middle + Modern)

- (void)buildSplitVC;
{
  Class svcC = NSClassFromString(@"NSSplitViewController");
  id svc = [[svcC alloc] init];
  id sv  = [svc performSelector:@selector(splitView)];
  accSetBOOL(sv, @selector(setVertical:), YES);

  /* Phase 1 — INSERTION. Wraps each pane VC in an AIVCAdapter, hands the
   * adapter to the matching NSSplitViewItem factory, and adds the item to
   * the controller. No layout policy is applied here; that belongs to
   * Phase 2 below and lives entirely inside one method so it can be
   * swapped without touching insertion or AIVCAdapter wiring. */
  id contentItem;
  sidebarItem_   = [[self accAddItemTo:svc vc:sidebarVC_   kind:0] retain];
  contentItem    =  [self accAddItemTo:svc vc:detailVC_    kind:1];
  inspectorItem_ = [[self accAddItemTo:svc vc:inspectorVC_ kind:2] retain];

  /* Phase 2 — LAYOUT. Replaceable independently of Phase 1. */
  [self accApplyModernLayoutToItem:sidebarItem_
                              view:[sidebarVC_   view] kind:0];
  [self accApplyModernLayoutToItem:contentItem
                              view:[detailVC_    view] kind:1];
  [self accApplyModernLayoutToItem:inspectorItem_
                              view:[inspectorVC_ view] kind:2];

  accSetBOOL(inspectorItem_, @selector(setCollapsed:), YES);
  inspectorCollapsed_ = YES;

  splitViewController_ = svc; /* +1 from alloc, owned by ivar */

  /* -setContentViewController: resizes the window to the split VC view's
   * current size (documented AppKit behaviour), throwing away the frame
   * -loadWindow restored — and, because the autosave name is now live, that
   * involuntary resize writes the wrong size straight back to defaults.
   * Re-reading defaults here is therefore useless (already clobbered), so
   * capture the window's pre-resize frame in a local and re-apply it
   * directly; the re-apply also re-saves the correct frame. The Legacy path
   * adds the split as a contentView subview and never resizes the window, so
   * it has no equivalent. */
  NSRect preContentFrame = [[self window] frame];
  [[self window] performSelector:@selector(setContentViewController:)
                      withObject:svc];
  [[self window] setFrame:preContentFrame display:NO];
  /* NSSplitViewItem.collapsed is not part of what NSSplitView autosaves on
   * Middle/Modern, so the forced "inspector starts collapsed" rule above
   * survives this. nil-safe when no autosave name was ever set. */
  [self accApplySplitAutosaveName];
}

/* Construction step, NOT a reusable query. Invoked exactly three times
 * (once per pane, kind 0/1/2) from -buildSplitVC during a single
 * -windowDidLoad. The factory is chosen purely by tier_:
 *
 *   kind=0 (sidebar):   sidebarWithVC:        on Middle and Modern.
 *   kind=2 (inspector): inspectorWithVC:      on Modern only.
 *                       splitViewItemWithVC:  on Middle.
 *   kind=1 (content):   splitViewItemWithVC:  on both.
 *
 * No respondsToSelector: — the tier check above is the existence proof. */
- (id)accAddItemTo:(id)svc vc:(AIViewController *)vc kind:(int)kind;
{
  Class sviC = NSClassFromString(@"NSSplitViewItem");
  SEL sel;
  if (kind == 0) {
    sel = @selector(sidebarWithViewController:);
  } else if (kind == 2 && tier_ == AICCTierModern) {
    sel = @selector(inspectorWithViewController:);
  } else {
    sel = @selector(splitViewItemWithViewController:);
  }

  /* The modern split API only accepts an NSViewController; hand it the
   * private adapter, not the AIViewController itself. */
  id adapter = AIVCAdapterNew(vc);
  id item = [sviC performSelector:sel withObject:adapter];
  /* Inspector-slot toolbar-backdrop compensation (Modern only). The
   * .inspector NSSplitViewItem style does not auto-wrap its pane in an
   * NSVisualEffectView the way .sidebar does, and AppKit's "find an
   * adjacent NSScrollView to drive the toolbar's vibrancy" detector
   * (WWDC14 #220) finds nothing inside a WKWebView host-side — so an
   * AIWebViewController dropped here renders with a fully unfrosted
   * toolbar that the page bleeds through. Gate on the conjunction of
   * "this is the inspector slot," "we're on Modern," and "the VC
   * builds on our WebView base"; anyone else putting custom content
   * in the inspector slot solves their own backdrop problem. */
  if (kind == 2 && tier_ == AICCTierModern &&
      [vc isKindOfClass:[AIWebViewController class]]) {
    [(AIWebViewController *)vc HACK_installInspectorToolbarBackdrop];
  }
  [svc performSelector:@selector(addSplitViewItem:) withObject:item];
  [adapter release];   /* the item retains its viewController */
  return item;
}

/* Modern split-pane LAYOUT policy. Two responsibilities:
 *
 *   1. autoresizingMask = widthSizable | heightSizable on the pane view,
 *      mirroring what -accPanelFor: applies on the Legacy path. The pane's
 *      translatesAutoresizingMaskIntoConstraints stays at its default YES,
 *      so AppKit synthesizes "stretch with parent" constraints from the
 *      mask. Without this, ChatListViewController's pane would inherit
 *      AIViewController.loadView's 200x200 frame with NSViewNotSizable and
 *      become a required width=200,height=200 constraint that conflicts
 *      with NSSplitView the moment the divider moves.
 *
 *   2. NSSplitViewItem.minimumThickness/maximumThickness (10.10+) bound
 *      the pane's drag range. kind==1 (content) has no fixed band; it
 *      absorbs whatever the sidebar and inspector don't take.
 *
 * Earlier this seam also set translatesAutoresizingMaskIntoConstraints=NO,
 * a soft-priority width NSLayoutConstraint, and preferredThicknessFraction.
 * That stack misbehaved on Big Sur — the fraction won the initial layout
 * but the panes would not honor subsequent user drags. Reverting to the
 * Tiger-shape autoresizing approach + NSSplitViewItem's own thickness
 * bounds is the current experiment. */
- (void)accApplyModernLayoutToItem:(id)item
                              view:(NSView *)pv
                              kind:(int)kind;
{
  [pv setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  if (kind == 1) return;
  AIMinMidMax lim = (kind == 0) ? sidebarLimits_ : inspectorLimits_;
  accSetCGFloat(item, @selector(setMinimumThickness:), lim.min);
  accSetCGFloat(item, @selector(setMaximumThickness:), lim.max);
}

#pragma mark Legacy path (AISplitView + collapsible inspector)

- (NSView *)accPanelFor:(AIViewController *)vc limits:(AIMinMidMax)lim;
{
  /* Placeholder frame — accLayoutLegacy resizes immediately after. */
  NSView *panel = [[[NSView alloc]
      initWithFrame:NSMakeRect(0, 0, lim.mid, 100)] autorelease];
  NSView *pv = [vc view];
  [pv setFrame:[panel bounds]];
  [pv setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [vc setNextResponder:self];
  [panel addSubview:pv];
  return panel;
}

- (void)buildLegacy;
{
  /* Re-seed the live width ivars from the final band's mid. -init pre-seeds
   * them from kDefaultPaneLimits, but setSidebar/setInspectorWidthLimits:
   * only updates the limits struct — without this catch-up the subclass's
   * mid never reaches accLayoutLegacy on the first build. */
  sidebarW_   = sidebarLimits_.mid;
  inspectorW_ = inspectorLimits_.mid;

  NSView *cv = [[self window] contentView];
  splitView_ = [[AISplitView alloc] initWithFrame:[cv bounds]];
  [splitView_ setVertical:YES];
  [splitView_ setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
  [splitView_ setDelegate:self];
  [splitView_ addSubview:[self accPanelFor:sidebarVC_   limits:sidebarLimits_]];
  [splitView_ addSubview:[self accPanelFor:detailVC_    limits:kDefaultPaneLimits]];
  [splitView_ addSubview:[self accPanelFor:inspectorVC_ limits:inspectorLimits_]];
  [cv addSubview:splitView_];
  [self accCollapseInspectorLegacy:YES];
  /* Apply autosave AFTER the default-collapsed inspector. On first launch
   * there is no saved data and the collapsed state stands; on subsequent
   * launches NSSplitView's restore reads the saved divider positions (and,
   * on Legacy, the subview hidden state) and overrides — so the user's last
   * layout wins. nil clears; no-op when never set. */
  [self accApplySplitAutosaveName];

  /* #1 (legacy): drive the appear pair ourselves. windowDidLoad runs inside
   * -showWindow: before the window is ordered front, so viewWillAppear is
   * genuinely pre-visible; viewDidAppear fires next runloop, on-screen.
   * accPanelFor: already forced -view (loadView/viewDidLoad) for each. */
  [self aiLegacyFireWillAppear];
  [self performSelector:@selector(aiLegacyFireDidAppear)
             withObject:nil
             afterDelay:0.0];
}

- (void)aiLegacyFireWillAppear;
{
  [sidebarVC_   viewWillAppear];
  [detailVC_    viewWillAppear];
  [inspectorVC_ viewWillAppear];
}

- (void)aiLegacyFireDidAppear;
{
  [sidebarVC_   viewDidAppear];
  [detailVC_    viewDidAppear];
  [inspectorVC_ viewDidAppear];
}

- (void)accLayoutLegacy;
{
  NSArray *s = [splitView_ subviews];
  if ([s count] < 3) return;
  CGFloat W = [splitView_ bounds].size.width;
  CGFloat H = [splitView_ bounds].size.height;
  CGFloat d = [splitView_ dividerThickness];
  CGFloat sw = sidebarCollapsed_   ? 0.0
                 : accClamp(sidebarW_,
                            sidebarLimits_.min, sidebarLimits_.max);
  CGFloat iw = inspectorCollapsed_ ? 0.0
                 : accClamp(inspectorW_,
                            inspectorLimits_.min, inspectorLimits_.max);
  CGFloat divs = (sw > 0.0 ? d : 0.0) + (iw > 0.0 ? d : 0.0);
  CGFloat cw = W - sw - iw - divs;
  if (cw < 0.0) cw = 0.0;   /* defensive: negative widths are UB on Tiger */
  CGFloat cx = (sw > 0.0) ? (sw + d) : 0.0;
  [[s objectAtIndex:0] setFrame:NSMakeRect(0, 0, sw, H)];
  [[s objectAtIndex:1] setFrame:NSMakeRect(cx, 0, cw, H)];
  [[s objectAtIndex:2] setFrame:NSMakeRect(W - iw, 0, iw, H)];
}

- (void)accCollapseInspectorLegacy:(BOOL)collapse;
{
  NSArray *s = [splitView_ subviews];
  if ([s count] < 3) return;
  [[s objectAtIndex:2] setHidden:collapse];
  inspectorCollapsed_ = collapse;
  [self accLayoutLegacy];
  [splitView_ setNeedsDisplay:YES];
}

- (void)accCollapseSidebarLegacy:(BOOL)collapse;
{
  NSArray *s = [splitView_ subviews];
  if ([s count] < 3) return;
  [[s objectAtIndex:0] setHidden:collapse];
  sidebarCollapsed_ = collapse;
  [self accLayoutLegacy];
  [splitView_ setNeedsDisplay:YES];
}

#pragma mark NSSplitView delegate (legacy)

- (BOOL)splitView:(NSSplitView *)splitView
    canCollapseSubview:(NSView *)subview;
{
  (void)splitView;
  NSArray *s = [splitView_ subviews];
  if ([s count] < 3) return NO;
  return (subview == [s objectAtIndex:0] || subview == [s objectAtIndex:2]);
}

/* Bound interactive drags. offset is the divider index (== index of the
 * subview on its leading side): 0 = sidebar|content, 1 = content|inspector.
 * The coordinate is the divider's x in the split view's flipped space. */
- (CGFloat)splitView:(NSSplitView *)sv
   constrainMinCoordinate:(CGFloat)proposedMin
              ofSubviewAt:(NSInteger)offset;
{
  (void)sv; (void)proposedMin;
  if (offset == 0) return sidebarLimits_.min;             /* sidebar >= min */
  /* offset == 1 (content|inspector): cap how far left the divider goes so
   * inspector cannot grow past its max. Window minSize guarantees content
   * still has room at the defaults. */
  CGFloat W = [splitView_ bounds].size.width;
  CGFloat d = [splitView_ dividerThickness];
  return W - d - inspectorLimits_.max;
}

- (CGFloat)splitView:(NSSplitView *)sv
   constrainMaxCoordinate:(CGFloat)proposedMax
              ofSubviewAt:(NSInteger)offset;
{
  (void)sv; (void)proposedMax;
  CGFloat W = [splitView_ bounds].size.width;
  CGFloat d = [splitView_ dividerThickness];
  if (offset == 0) {
    CGFloat iw  = inspectorCollapsed_ ? 0.0
                  : accClamp(inspectorW_,
                             inspectorLimits_.min, inspectorLimits_.max);
    CGFloat rsv = (iw > 0.0 ? iw + d : 0.0) + d;
    CGFloat cap = W - rsv;                            /* leave room for inspector */
    CGFloat mx  = sidebarLimits_.max;
    return cap < mx ? cap : mx;                       /* sidebar <= max */
  }
  return W - d - inspectorLimits_.min;                /* inspector >= min */
}

/* Window (split view) resize only — divider drags don't route here. Keep
 * sidebar/inspector at their stored widths; content absorbs the slack. */
- (void)splitView:(NSSplitView *)sv
   resizeSubviewsWithOldSize:(NSSize)oldSize;
{
  (void)sv; (void)oldSize;
  [self accLayoutLegacy];
}

/* Persist only — never re-impose a frame here (that snap-back was the
 * un-resizable bug, and re-setting frames would also loop the notification). */
- (void)splitViewDidResizeSubviews:(NSNotification *)note;
{
  (void)note;
  NSArray *s = [splitView_ subviews];
  if ([s count] < 3) return;
  CGFloat sw = [[s objectAtIndex:0] frame].size.width;
  CGFloat iw = [[s objectAtIndex:2] frame].size.width;
  sidebarCollapsed_   = (sw < 1.0);
  inspectorCollapsed_ = (iw < 1.0);
  if (!sidebarCollapsed_)
    sidebarW_   = accClamp(sw, sidebarLimits_.min, sidebarLimits_.max);
  if (!inspectorCollapsed_)
    inspectorW_ = accClamp(iw, inspectorLimits_.min, inspectorLimits_.max);
}

#pragma mark Public toggles

- (void)toggleSidebar:(id)sender;
{
  if (tier_ == AICCTierLegacy) {
    [self accCollapseSidebarLegacy:!sidebarCollapsed_];
    return;
  }
  /* Middle and Modern both have NSSplitViewController -toggleSidebar:
   * (10.11+), bound to the sidebar item built via sidebarWithVC:. */
  [splitViewController_ performSelector:@selector(toggleSidebar:)
                             withObject:sender];
  sidebarCollapsed_ = accGetBOOL(sidebarItem_, @selector(isCollapsed));
}

- (void)toggleInspector:(id)sender;
{
  if (tier_ == AICCTierLegacy) {
    [self accCollapseInspectorLegacy:!inspectorCollapsed_];
    return;
  }
  if (tier_ == AICCTierModern) {
    /* Modern: AppKit's toggleInspector: animates + flips state. */
    [splitViewController_ performSelector:@selector(toggleInspector:)
                               withObject:sender];
  } else {
    /* Middle: no toggleInspector: action exists (it's 11+) and the
     * inspector item is generic, so flip its collapsed property by hand. */
    BOOL c = accGetBOOL(inspectorItem_, @selector(isCollapsed));
    accSetBOOL(inspectorItem_, @selector(setCollapsed:), !c);
  }
  inspectorCollapsed_ = accGetBOOL(inspectorItem_, @selector(isCollapsed));
}

#pragma mark Subclasser helpers (toolbar setup)

/* Reaches into the host window's -setToolbarStyle: with the raw integer
 * value 3 (= NSWindowToolbarStyleUnified). The selector and the enum both
 * arrived in 10.16/11.0; the Tiger SDK we build against declares neither,
 * so we go through NSInvocation rather than reference either symbol by
 * name. Anything below Modern is a no-op — the older non-unified toolbar
 * already is the only thing AppKit can render. */
- (void)aiSetUnifiedToolbarStyle;
{
  if (AICCCurrentTier() < AICCTierModern) return;
  accSetInteger([self window], @selector(setToolbarStyle:), 3);
}

@end

#endif /* !TARGET_OS_IPHONE */
