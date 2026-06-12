#import <TargetConditionals.h>

#if !TARGET_OS_IPHONE

#import <AppKit/AppKit.h>

/* AIViewController
 *
 * An ordinary compiled view-controller base, rooted at NSResponder on every
 * OS. It lazily loads its view, owns the represented object, and drives the
 * lifecycle selectors itself. Because it has a real @implementation it has a
 * real class symbol, so subclassing is plain Objective-C and links on every
 * arch:
 *
 *   @interface ChatListVC : AIViewController @end
 *   @implementation ChatListVC { NSTableView *table_; }   // real ivars, safe
 *   - (void)viewDidLoad    { [super viewDidLoad];    ... }
 *   - (void)viewWillAppear { [super viewWillAppear]; ... }
 *   @end
 *
 * Subclassers override loadView / viewDidLoad / viewWillAppear /
 * viewDidAppear / viewDidLayout and call super. All five are guaranteed to
 * fire on every OS:
 *   - loadView once, then viewDidLoad then viewDidLayout, on first -view.
 *   - viewDidLayout: on the legacy path it re-fires from the view's own
 *     NSViewFrameDidChangeNotification. On the modern path that self-
 *     notification is DISABLED (AIVCAdapterNew marks the controller
 *     externally-driven) and every subsequent viewDidLayout comes solely
 *     from AppKit through the adapter — it never double-fires nor re-enters
 *     via a frame mutation inside viewDidLayout.
 *   - viewWillAppear / viewDidAppear: on the modern split path AppKit drives
 *     them through a private NSViewController adapter (see the .m); on the
 *     legacy path AICookieCutterWindowController fires the pair once when the
 *     window is first shown (an approximation — they do not re-fire on every
 *     show/hide below 10.10).
 *
 * Add subclass ivars in the subclass's own @interface braces. On the fragile
 * PPC ABI a layout change here forces subclasses to recompile (whole project
 * rebuilds together, so this is fine); the modern archs relocate offsets.
 *
 * Instantiate the bare base with plain [[AIViewController alloc] init].
 *
 * RESPONDER CHAIN (99%-case helper, not a full Cocoa-compatible substitute):
 * On Middle/Modern, AppKit owns the chain through views — the AIViewController
 * itself is invisible to AppKit (sits *next to* the chain, not in it). To
 * keep subclass code idiomatic, -[AIViewController nextResponder] is
 * overridden to forward to view_.nextResponder on Middle/Modern, so the
 * canonical Cocoa pattern
 *
 *     [[self nextResponder] tryToPerform:@selector(myAction:) with:payload];
 *
 * lands on AppKit's wired chain (parent's view / adapter → split view →
 * window → window controller). Forwarding to the view (not to adapter_) is
 * deliberate: adapter_ exists for every AIVC but is only spliced into the
 * chain for top-level split-view panes; child VCs added via
 * AI_addChildViewController: have a registered-but-unwired adapter, and only
 * the view participates uniformly on both paths.
 *
 * The Cocoa contract is therefore relaxed: -setNextResponder: on Middle/
 * Modern stores into the ivar but is silently ignored by the getter —
 * meaning you cannot insert custom objects into the chain ahead of an
 * AIViewController on those OS tiers. Likewise, [item setTarget:[self
 * nextResponder]] for an NSMenuItem will end up targeting an AppKit
 * implementation-detail wrapper rather than a stable receiver; use
 * [item setTarget:nil] for chain-walked menu items.
 *
 * Manual responder-chain configuration is therefore an edge case this
 * cookie cutter does NOT cover. The cookie cutter + AIViewController are
 * the 99% case — a standard three-pane window where subclasses talk to
 * their window controller via tryToPerform:. If you need to splice custom
 * responders into the chain, fall back to a plain NSResponder /
 * NSViewController / NSWindowController stack instead of this base.
 */
@interface AIViewController : NSResponder {
 @private
  NSView *view_;
  id      repObj_;
  BOOL    didLoad_;
  BOOL    externallyDriven_;   /* modern: adapter owns the lifecycle */
  NSMutableArray *children_;   /* AIViewController * children, retained */
  AIViewController *parent_;   /* weak — parent retains us via children_ */
  id      adapter_;            /* weak AIVCAdapter (Middle/Modern only).
                                  Adapter retains self; AppKit (or the cookie
                                  cutter's NSSplitViewItem) retains adapter.
                                  When the parent chain releases, adapter
                                  releases self — so a non-nil adapter_ is
                                  guaranteed valid for the lifetime of self. */
}
- (NSView *)view;
- (void)setView:(NSView *)view;
- (void)loadView;
- (void)viewDidLoad;
- (void)viewWillAppear;
- (void)viewDidAppear;
- (void)viewDidLayout;
- (id)representedObject;
- (void)setRepresentedObject:(id)object;

/* Hand-rolled child-VC containment that mirrors NSViewController's API.
 *
 *   Legacy:        wires [child setNextResponder:self] and stores `child` in
 *                  a private retained children_ array. The caller is still
 *                  responsible for the geometry — i.e. adding child.view as a
 *                  subview of self.view (or wherever it belongs).
 *   Middle/Modern: builds an NSViewController-rooted AIVCAdapter for `child`
 *                  (and self, if one doesn't already exist) and forwards to
 *                  AppKit's -[NSViewController addChildViewController:].
 *                  AppKit then wires the responder chain through views, and
 *                  the adapter's forwardingTargetForSelector: makes the
 *                  AIViewController's action methods reachable from that
 *                  chain. Caller still owns geometry.
 *
 * Adding a child that already has a parent first removes it from its current
 * parent. Passing nil raises NSInvalidArgumentException.
 *
 * Calling AI_addChildViewController: on a parent whose adapter isn't yet in
 * AppKit's hierarchy (i.e. not a split-view pane and not itself an added
 * child) on Middle/Modern raises NSInternalInconsistencyException — that
 * adapter would have no retainer and would dealloc the moment we returned.
 * In practice every AIViewController in this app is either a split-view
 * pane (adapter retained by NSSplitViewItem) or added as a child (adapter
 * retained by AppKit's childViewControllers array), so this is reachable
 * only by an out-of-order misuse. */
- (void)AI_addChildViewController:(AIViewController *)child;
- (void)AI_removeFromParentViewController;
- (NSArray *)AI_childViewControllers;
- (AIViewController *)AI_parentViewController;
@end

#endif /* !TARGET_OS_IPHONE */
