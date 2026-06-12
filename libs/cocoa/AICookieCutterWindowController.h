#import <TargetConditionals.h>

#if !TARGET_OS_IPHONE

#import <AppKit/AppKit.h>
#import "AIViewController.h"

/* ─────────────────────────────────────────────────────────────────────────
 * SDK-compatibility shims (compile-time only)
 *
 * Everything in this block exists so the .{h,m} pair can compile against
 * any macOS SDK from 10.4 (Tiger) through 11+ without dragging in the host
 * a host project's compatibility layer. They are *symbol-name* shims — they
 * choose between
 * the modern and legacy spellings of the same underlying constant, type,
 * or formal protocol at the SDK level. Runtime OS-version capability is a
 * separate concern, handled inside the .m via NSAppKitVersionNumber tiers
 * + NSInvocation/performSelector dispatch.
 *
 * Naming: each shim is prefixed AI so this file shares no namespace with
 * a host project's own shims. The namespaces are
 * intentionally allowed to coexist in the same target. */

/* Window style mask names were renamed in the 10.12 SDK
 * (NSTitledWindowMask → NSWindowStyleMaskTitled, etc.). The numeric values
 * are unchanged; only the spellings differ.
 *
 * AIWindowStyleMaskFullSizeContentView is the 1<<15 bit introduced in
 * 10.10 (NSFullSizeContentViewWindowMask → NSWindowStyleMaskFullSizeContentView
 * in 10.12). The pre-10.12 branch uses the raw value because the bit value
 * itself is stable, the Tiger SDK we build against has no symbol for it,
 * and NSWindow has always silently ignored unknown style-mask bits on OS
 * versions that predate the symbol. */
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 101200
  #define AIWindowStyleMask                    NSWindowStyleMask
  #define AIWindowStyleMaskTitled              NSWindowStyleMaskTitled
  #define AIWindowStyleMaskClosable            NSWindowStyleMaskClosable
  #define AIWindowStyleMaskResizable           NSWindowStyleMaskResizable
  #define AIWindowStyleMaskMiniaturizable      NSWindowStyleMaskMiniaturizable
  #define AIWindowStyleMaskFullSizeContentView NSWindowStyleMaskFullSizeContentView
#else
  #define AIWindowStyleMask                    NSUInteger
  #define AIWindowStyleMaskTitled              NSTitledWindowMask
  #define AIWindowStyleMaskClosable            NSClosableWindowMask
  #define AIWindowStyleMaskResizable           NSResizableWindowMask
  #define AIWindowStyleMaskMiniaturizable      NSMiniaturizableWindowMask
  #define AIWindowStyleMaskFullSizeContentView ((NSUInteger)(1 << 15))
#endif

/* The green-button "make this window full-screen capable" capability is
 * NOT a style-mask bit (NSFullScreenWindowMask is an AppKit-managed
 * read-only indicator) — it's a collectionBehavior bit on NSWindow that
 * arrived in 10.7 Lion. The raw value (1 << 7) is stable. Pre-10.7 SDKs
 * lack the symbol, so the legacy branch uses the literal; OS versions
 * that don't recognise the bit simply ignore it in their collection-
 * behavior processing. */
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 1070
  #define AIWindowCollectionBehaviorFullScreenPrimary NSWindowCollectionBehaviorFullScreenPrimary
#else
  #define AIWindowCollectionBehaviorFullScreenPrimary ((NSUInteger)(1 << 7))
#endif

/* The NSSplitViewDelegate formal protocol appeared in the 10.6 SDK. On older
 * SDKs (Tiger / early Leopard) it is not a symbol at all, so the conformance
 * list won't parse unless we stand in an empty protocol of the same name.
 * Toolbar customization is left to subclassers — this class no longer
 * conforms to NSToolbarDelegate. */
#if MAC_OS_X_VERSION_MAX_ALLOWED >= 1060
  #define AISplitViewDelegate  NSSplitViewDelegate
#else
  @protocol AISplitViewDelegate @end
#endif

/* +[NSColor windowFrameColor] was deprecated in macOS 11 in favour of
 * +windowBackgroundColor. The deprecation only fires when the deployment
 * target is >= 11.0 (Apple's API_DEPRECATED machinery is deployment-
 * sensitive), so the host's 10.9 / 10.4 builds happily use the old name
 * without a warning, while the arm64-with-min-11 build picks the new one. */
#if MAC_OS_X_VERSION_MIN_REQUIRED >= 110000
  #define AIColorWindowFrame [NSColor windowBackgroundColor]
#else
  #define AIColorWindowFrame [NSColor windowFrameColor]
#endif

/* ─────────────────────────────────────────────────────────────────────────
 * Runtime OS tier
 *
 * Three coarse buckets the cookie cutter dispatches on. Each
 * tier is the *existence proof* for the AppKit features it advertises, so
 * call sites can drop the per-selector -respondsToSelector: guard and gate
 * on the tier directly.
 *
 *   AICCTierLegacy  (<10.11):  raw NSSplitView, no modern AppKit additions.
 *                              10.10 is folded into Legacy because key
 *                              factories (sidebar/inspector) don't ship
 *                              until 10.11.
 *   AICCTierMiddle  (10.11–10.15): NSSplitViewController + 10.5–10.10 era
 *                              setters are all known-good.
 *   AICCTierModern  (11.0+):   inspector factory, toggleInspector:,
 *                              NSTrackingSeparatorToolbarItem, unified
 *                              toolbar style, SF Symbols.
 *
 * The thresholds (1404 / 2022) are NSAppKitVersionNumber values for 10.11
 * El Capitan and 11.0 Big Sur. We use literals because the matching named
 * constants don't exist in the Tiger-vintage SDK we build against.
 *
 * Inline so every translation unit sees one tiny constexpr-ish function —
 * NSAppKitVersionNumber is loaded once per process. */
typedef enum {
  AICCTierLegacy = 0,
  AICCTierMiddle = 1,
  AICCTierModern = 2
} AICCTier;

static inline AICCTier AICCCurrentTier(void) {
  double v = NSAppKitVersionNumber;
  if (v >= 2022.0) return AICCTierModern;
  if (v >= 1404.0) return AICCTierMiddle;
  return AICCTierLegacy;
}

/* A floating-point [min, mid, max] width band. Foundation has no equivalent
 * (NSRange is integer location/length), so the panes carry this instead.
 * `mid` is the preferred starting width — used as the pane's default size
 * instead of being computed from min/max, so callers can pick a value that
 * isn't the geometric midpoint. */
typedef struct { CGFloat min; CGFloat mid; CGFloat max; } AIMinMidMax;
static inline AIMinMidMax AIMinMidMaxMake(CGFloat lo, CGFloat md, CGFloat hi) {
  AIMinMidMax r; r.min = lo; r.mid = md; r.max = hi; return r;
}

/* Forward declaration: the legacy split path uses a private NSSplitView
 * subclass defined inside the .m. The .h only needs the pointer type. */
@class AISplitView;

@interface AICookieCutterWindowController : NSWindowController
    <AISplitViewDelegate> {
 @private
  NSString        *autosaveName_;
  NSString        *windowTitle_;
  AIViewController *sidebarVC_;
  AIViewController *detailVC_;
  AIViewController *inspectorVC_;
  id               splitViewController_;   /* NSSplitViewController (modern) */
  id               sidebarItem_;            /* NSSplitViewItem    (modern)  */
  id               inspectorItem_;          /* NSSplitViewItem    (modern)  */
  AISplitView     *splitView_;              /* legacy path */
  CGFloat          sidebarW_;               /* legacy: user-adjustable */
  CGFloat          inspectorW_;             /* legacy: user-adjustable */
  AIMinMidMax      sidebarLimits_;          /* allowed sidebar width band */
  AIMinMidMax      inspectorLimits_;        /* allowed inspector width band */
  BOOL             sidebarCollapsed_;
  BOOL             inspectorCollapsed_;
  /* OS-version tier (AICCTier{Legacy,Middle,Modern}, declared above).
   * Computed once in -windowDidLoad from AICCCurrentTier() and used to
   * pick build paths and dispatch sites — replaces the older modern_ flag
   * plus per-factory realSidebarItem_ / realInspectorItem_ flags. */
  AICCTier         tier_;
  NSString        *splitAutosaveName_;       /* nil = no divider autosave */
}
- (id)initWithTitle:(NSString *)title autosaveName:(NSString *)autosaveName;

- (AIViewController *)sidebarViewController;
- (AIViewController *)detailViewController;
- (AIViewController *)inspectorViewController;

/* The live NSSplitView for the cookie cutter's three-pane layout.
 *
 *   Legacy:        the private AISplitView (typed up to NSSplitView*).
 *   Middle/Modern: NSSplitViewController.splitView — the same underlying
 *                  NSSplitView the modern path's NSSplitViewItems sit in.
 *   nil before -windowDidLoad has fired (the split view doesn't exist yet).
 *
 * Subview/divider ordering is identical on both paths because the cookie
 * cutter always installs the three panes sidebar→detail→inspector:
 *   - dividerIndex 0 separates sidebar from detail.
 *   - dividerIndex 1 separates detail from inspector. */
- (NSSplitView *)AI_splitView;

/* The three panes are consumed once, by buildModern/buildLegacy inside
 * -windowDidLoad. These setters MUST be called before the window loads
 * (i.e. before -showWindow: / -window). Calling one after the window has
 * loaded raises NSInvalidArgumentException rather than silently no-opping. */
- (void)setSidebarViewController:(AIViewController *)vc;
- (void)setDetailViewController:(AIViewController *)vc;
- (void)setInspectorViewController:(AIViewController *)vc;

/* Signatures match NSSplitViewController's IBActions (toggleSidebar: 10.11+,
 * toggleInspector: 11.0+). On the modern path these forward to the genuine
 * NSSplitViewController implementation when present (real animation +
 * NSUserInterfaceValidations); otherwise they collapse the stored item. */
- (void)toggleSidebar:(id)sender;
- (void)toggleInspector:(id)sender;
- (BOOL)isSidebarCollapsed;
- (BOOL)isInspectorCollapsed;

/* Per-pane width band, honoured on BOTH paths: modern via the split item's
 * minimum/maximumThickness, legacy via manual layout + drag constraints.
 * `mid` is the pane's preferred starting width. Like the pane-VC setters
 * these MUST be set before the window loads; calling a setter afterward
 * raises NSInvalidArgumentException, as does passing a band that doesn't
 * satisfy 0 <= min <= mid <= max. */
- (AIMinMidMax)sidebarWidthLimits;
- (void)setSidebarWidthLimits:(AIMinMidMax)limits;
- (AIMinMidMax)inspectorWidthLimits;
- (void)setInspectorWidthLimits:(AIMinMidMax)limits;

/* Persist divider positions to NSUserDefaults keyed by `name`. Works on both
 * tiers: Legacy sets the NSSplitView's autosaveName directly; Middle/Modern
 * reach NSSplitViewController.splitView (the underlying NSSplitView — same
 * autosaveName mechanism added in 10.5 Leopard). One name covers BOTH
 * dividers; there is exactly one NSSplitView and AppKit only supports one
 * autosaveName per split view. On 10.4 Tiger the selector doesn't exist
 * and the call is a silent no-op (divider positions are not persisted).
 *
 * NSSplitView restores the saved divider positions immediately when
 * setAutosaveName: is called, so this is safe to invoke before or after
 * windowDidLoad. Before: stored and applied during the split build. After:
 * applied at once. Pass nil to clear.
 *
 * Caveat: on Middle/Modern, NSSplitViewItem.collapsed is NOT autosaved by
 * NSSplitView (AppKit limitation). The cookie cutter's "inspector starts
 * collapsed" rule wins on every launch; the restored divider position only
 * becomes visible once the inspector is uncollapsed. */
- (void)setSplitViewAutosaveName:(NSString *)name;

/* Subclasser helpers — OS-version-shim conveniences for toolbar setup.
 *
 * AICookieCutterWindowController does not install a toolbar of its own;
 * subclassers attach one in their own -windowDidLoad (after calling super).
 * The helpers below paper over AppKit symbols that don't exist on every
 * SDK / OS we target, so a subclasser can write portable toolbar code
 * without re-deriving the NSInvocation / NSAppKitVersionNumber dance.
 *
 * Each helper is a no-op when the underlying API isn't available on the
 * running OS, so callers don't need their own version checks. */

/* Sets the host window's toolbar style to NSWindowToolbarStyleUnified
 * (the single-row, items-in-titlebar look introduced in Big Sur). No-op
 * below macOS 11. Order-independent with respect to -setToolbar:: AppKit
 * stores the style on the window, so calling this before OR after the
 * toolbar attachment both work. */
- (void)aiSetUnifiedToolbarStyle;
@end

#endif /* !TARGET_OS_IPHONE */
