#import <TargetConditionals.h>

#if !TARGET_OS_IPHONE

#import "AIViewController.h"
#import "AICookieCutterWindowController.h"
#import <objc/runtime.h>
#import <pthread.h>

/* Ordinary compiled class (see header). Rooted at NSResponder on every OS so
 * `@interface Foo : AIViewController` links and may declare real ivars. The
 * modern NSViewController-only split API is satisfied by a *private* runtime
 * adapter further down, never visible to subclassers. */

/* Forward declaration so AI_addChildViewController: (defined inside
 * AIViewController's @implementation) can reach the adapter factory that
 * lives further down the file. External linkage so the cookie cutter's
 * accAddItemTo: in AICookieCutterWindowController.m can also call it. */
id AIVCAdapterNew(AIViewController *content);

@interface AIViewController ()
/* Set once by AIVCAdapterNew on the Middle/Modern path: AppKit's
 * NSViewController adapter becomes the sole driver of the appear/layout
 * lifecycle, so the controller must NOT also self-deliver viewDidLayout
 * from NSViewFrameDidChangeNotification (that double-fired layout and
 * re-entered on any frame mutation inside viewDidLayout). */
- (void)aiMarkExternallyDriven;

/* Internal-use adapter accessors. PPC's GCC enforces @private for plain
 * C functions, so adp_dealloc and AIVCAdapterNew can't poke the ivar
 * directly without warnings — these methods are the sanctioned hop. They
 * are NOT part of the public AIViewController contract; subclassers should
 * never call them. */
- (id)aiAdapter;
- (void)aiSetAdapter:(id)adapter;
@end

@implementation AIViewController

- (void)loadView;
{
  NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 200)];
  [self setView:v];
  [v release];
}

/* Default lifecycle bodies are no-ops so [super ...] is always safe. */
- (void)viewDidLoad;
{
}
- (void)viewWillAppear;
{
}
- (void)viewDidAppear;
{
}
- (void)viewDidLayout;
{
}
- (NSView *)view;
{
  if (!view_) [self loadView];
  if (!didLoad_) {
    didLoad_ = YES;            /* set before callbacks: re-entrant -view safe */
    [self viewDidLoad];
    [self viewDidLayout];
  }
  return view_;
}

- (void)setView:(NSView *)view;
{
  if (view_ == view) return;
  NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
  if (view_) {
    [nc removeObserver:self
                  name:NSViewFrameDidChangeNotification
                object:view_];
    [view_ release];
  }
  view_ = [view retain];
  if (!view_) return;
  [view_ setNextResponder:self];
  /* Middle/Modern path: the NSViewController adapter is the only layout
   * driver. Do not also observe the view's frame — that double-fired
   * viewDidLayout and re-entered whenever a subclass mutated the frame
   * inside it. */
  if (externallyDriven_) return;
  [view_ setPostsFrameChangedNotifications:YES];
  [nc addObserver:self
         selector:@selector(aiFrameChanged:)
             name:NSViewFrameDidChangeNotification
           object:view_];
}

/* Legacy path only — the Middle/Modern path never registers this observer
 * (see setView:). A frame change must never drive viewDidLayout before
 * viewDidLoad: until -view has run the load sequence didLoad_ is NO and
 * the notification is dropped; the first layout is delivered by -view
 * itself, in order. The externallyDriven_ guard is belt-and-suspenders. */
- (void)aiFrameChanged:(NSNotification *)note;
{
  (void)note;
  if (externallyDriven_) return;
  if (didLoad_) [self viewDidLayout];
}

/* Called once by AIVCAdapterNew before -view is first forced, so the
 * observer in setView: is never installed on the Middle/Modern path.
 * Idempotent; also tears down an already-registered observer defensively. */
- (void)aiMarkExternallyDriven;
{
  externallyDriven_ = YES;
  if (view_)
    [[NSNotificationCenter defaultCenter]
        removeObserver:self
                  name:NSViewFrameDidChangeNotification
                object:view_];
}

- (id)aiAdapter;
{
  return adapter_;
}

- (void)aiSetAdapter:(id)a;
{
  adapter_ = a;   /* weak */
}

/* On Middle/Modern, AppKit owns the chain through views and self is invisible
 * to it (stored nextResponder is nil). Forward to the view's nextResponder
 * so the canonical
 *
 *     [[self nextResponder] tryToPerform:sel with:obj]
 *
 * lands on AppKit's wired chain. Why view_.nextResponder and not
 * adapter_.nextResponder: adapter_ is only in AppKit's chain when it was
 * installed via NSSplitViewItem.splitViewItemWithViewController: (top-level
 * panes). Child adapters added via [parent.adapter addChildViewController:]
 * never get setView: called by AppKit — their view is handed to the parent's
 * view hierarchy directly — so they register the parent/child relationship
 * but never get spliced into the responder chain. view_.nextResponder works
 * uniformly: it's adapter_ for top-level panes, parent.view for child VCs,
 * and the walk reaches the WC either way.
 *
 * On Legacy adapter_ is nil and the stored ivar (set by accPanelFor: /
 * AI_addChildViewController:) is honoured via [super nextResponder]. See the
 * class doc-comment in the header for the relaxed setNextResponder: contract. */
- (NSResponder *)nextResponder;
{
  if (adapter_ && view_) return [view_ nextResponder];
  return [super nextResponder];
}

- (id)representedObject;
{
  return repObj_;
}

- (void)setRepresentedObject:(id)object;
{
  if (repObj_ == object) return;
  [repObj_ release];
  repObj_ = [object retain];
}

- (void)dealloc;
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  /* Children are owned by children_; releasing the array releases each
   * child. Each child's parent_ back-pointer dangles for the duration of
   * its own dealloc, which is fine because dealloc never reads it. The
   * adapter (if any) is released through the AppKit hierarchy that holds
   * it, not from here. */
  [children_ release];
  [view_ release];
  [repObj_ release];
  [super dealloc];
}

#pragma mark Child VC containment

- (NSArray *)AI_childViewControllers;
{
  return children_ ? [[children_ copy] autorelease] : [NSArray array];
}

- (AIViewController *)AI_parentViewController;
{
  return parent_;
}

- (void)AI_removeFromParentViewController;
{
  AIViewController *p = parent_;
  if (!p) return;
  /* The retain bracket protects self from dealloc-during-removal: removing
   * from p->children_ drops our last retain when self is no longer otherwise
   * held, and the rest of this method would deref a dead self. */
  [[self retain] autorelease];
  parent_ = nil;
  if (adapter_) {
    [adapter_ performSelector:@selector(removeFromParentViewController)];
    /* AppKit drops its retain on the adapter; if nothing else held it (it
     * shouldn't), adp_dealloc runs and clears self->adapter_. */
  } else {
    /* Legacy path — clear the responder chain we wired in addChild. */
    [self setNextResponder:nil];
  }
  [p->children_ removeObjectIdenticalTo:self];
}

- (void)AI_addChildViewController:(AIViewController *)child;
{
  if (!child)
    [NSException raise:NSInvalidArgumentException
                format:@"[AIViewController AI_addChildViewController:] "
                       @"nil child"];
  if (child == self)
    [NSException raise:NSInvalidArgumentException
                format:@"[AIViewController AI_addChildViewController:] "
                       @"cannot add self as child"];
  if (child->parent_) [child AI_removeFromParentViewController];

  if (!children_) children_ = [[NSMutableArray alloc] init];
  [children_ addObject:child];
  child->parent_ = self;

  if (AICCCurrentTier() == AICCTierLegacy) {
    /* Manual responder chain: child → self. Caller still adds child.view as
     * a subview wherever it belongs; AppKit's view-side chain (view →
     * superview → …) reaches self through the view hierarchy, but our
     * AIViewController is rooted at NSResponder and not a view, so the
     * explicit nextResponder hop is what carries actions out of child. */
    [child setNextResponder:self];
    return;
  }

  /* Middle/Modern: route through AppKit's NSViewController parent/child.
   * Parent must already be in AppKit's hierarchy — otherwise its adapter
   * has no retainer and would die before we returned. */
  if (!adapter_)
    [NSException raise:NSInternalInconsistencyException
                format:@"[AIViewController AI_addChildViewController:] "
                       @"parent %@ has no adapter; only split-view panes "
                       @"and already-added children may host children on "
                       @"Middle/Modern.", self];

  id childAdapter = AIVCAdapterNew(child);
  [adapter_ performSelector:@selector(addChildViewController:)
                 withObject:childAdapter];
  [childAdapter release];   /* AppKit's childViewControllers array retains */
}

@end

#pragma mark - Private modern NSViewController adapter

/* Bridges an AIViewController into the NSViewController-only modern split
 * API (+[NSSplitViewItem splitViewItemWithViewController:], 10.10+). Built
 * at runtime so this file never links NSViewController (the Tiger SDK has
 * no such class); only ever instantiated on Middle/Modern. It is a single
 * internal class that is never subclassed, so indexed-ivar storage is safe
 * here (the hazard that ruled it out for the public base does not apply).
 *
 * AppKit drives this adapter's lifecycle; we forward viewWillAppear /
 * viewDidAppear / viewDidLayout into the wrapped controller. viewDidLoad
 * is NOT forwarded — it already fires via the lazy -view inside -loadView. */
typedef struct { id content; } AIVCAdapterCtx;

static Class g_adpClass = Nil;

static AIVCAdapterCtx *adp_ctx(id self) {
  return (AIVCAdapterCtx *)object_getIndexedIvars(self);
}

static void adp_callSuper(id self, SEL _cmd) {
  Class sup = class_getSuperclass(g_adpClass);
  IMP   imp = class_getMethodImplementation(sup, _cmd);
  ((void (*)(id, SEL))imp)(self, _cmd);
}

static void adp_loadView(id self, SEL _cmd) {
  (void)_cmd;
  id content = adp_ctx(self)->content;
  id v = [content performSelector:@selector(view)];
  [self performSelector:@selector(setView:) withObject:v];
}

static void adp_viewWillAppear(id self, SEL _cmd) {
  adp_callSuper(self, _cmd);
  [adp_ctx(self)->content performSelector:@selector(viewWillAppear)];
}

static void adp_viewDidAppear(id self, SEL _cmd) {
  adp_callSuper(self, _cmd);
  [adp_ctx(self)->content performSelector:@selector(viewDidAppear)];
}

static void adp_viewDidLayout(id self, SEL _cmd) {
  adp_callSuper(self, _cmd);
  [adp_ctx(self)->content performSelector:@selector(viewDidLayout)];
}

static void adp_dealloc(id self, SEL _cmd) {
  AIViewController *content = adp_ctx(self)->content;
  /* The adapter is the AIVC's only weak-pointer holder; clear the back-edge
   * before releasing so any teardown code on content can't dereference a
   * half-dead adapter. Routed through -aiSetAdapter: because adapter_ is
   * @private (PPC's GCC enforces it for plain C functions). */
  if (content) [content aiSetAdapter:nil];
  [content release];
  adp_callSuper(self, _cmd);
}

/* Make the wrapped AIViewController's action methods reachable through the
 * responder chain. AppKit dispatches messages to the adapter (the
 * NSViewController it knows about); without these two overrides every
 * subclass selector (sendMessage:, toggleInspector:, ...) would die at
 * the adapter with "does not recognize selector".
 *
 * respondsToSelector: is needed because NSResponder.tryToPerform:with: gates
 * dispatch on respondsToSelector: — forwardingTargetForSelector: alone
 * wouldn't be consulted. The two together make the adapter a transparent
 * proxy for the AIViewController's subclass-defined selectors.
 *
 * Only selectors implemented in content's class chain BELOW NSResponder are
 * forwarded. Common responder methods like cut:/copy:/paste:/selectAll: are
 * inherited from NSResponder by both the adapter and content; forwarding
 * those would spuriously short-circuit tryToPerform: into content's no-op
 * inherited implementation instead of letting AppKit's chain walk continue. */
static BOOL adp_contentDefinesSelector(id content, SEL aSelector) {
  if (!content || !aSelector) return NO;
  Class responderCls = [NSResponder class];
  Class c = object_getClass(content);
  while (c && c != responderCls) {
    if (class_getInstanceMethod(c, aSelector) != NULL) return YES;
    c = class_getSuperclass(c);
  }
  return NO;
}

static BOOL adp_respondsToSelector(id self, SEL _cmd, SEL aSelector) {
  (void)_cmd;
  if (class_respondsToSelector(object_getClass(self), aSelector)) return YES;
  return adp_contentDefinesSelector(adp_ctx(self)->content, aSelector);
}

static id adp_forwardingTargetForSelector(id self, SEL _cmd, SEL aSelector) {
  (void)_cmd;
  id content = adp_ctx(self)->content;
  if (adp_contentDefinesSelector(content, aSelector)) return content;
  return nil;
}

static void adp_build(void) {
  Class sup = objc_getClass("NSViewController");
  if (!sup) { NSLog(@"[AIVCAdapter.build] no NSViewController"); return; }
  Class c = objc_allocateClassPair(sup, "AIVCAdapter",
                                   sizeof(AIVCAdapterCtx));
  if (!c) {
    g_adpClass = objc_getClass("AIVCAdapter");
    NSLog(@"[AIVCAdapter.build] reusing existing class");
    return;
  }
  class_addMethod(c, @selector(loadView),       (IMP)adp_loadView,       "v@:");
  class_addMethod(c, @selector(viewWillAppear), (IMP)adp_viewWillAppear, "v@:");
  class_addMethod(c, @selector(viewDidAppear),  (IMP)adp_viewDidAppear,  "v@:");
  class_addMethod(c, @selector(viewDidLayout),  (IMP)adp_viewDidLayout,  "v@:");
  class_addMethod(c, @selector(dealloc),        (IMP)adp_dealloc,        "v@:");
  class_addMethod(c, @selector(respondsToSelector:),
                  (IMP)adp_respondsToSelector, "c@::");
  class_addMethod(c, @selector(forwardingTargetForSelector:),
                  (IMP)adp_forwardingTargetForSelector, "@@::");
  objc_registerClassPair(c);
  g_adpClass = c;
  NSLog(@"[AIVCAdapter.build] registered");
}

static pthread_once_t g_adpOnce = PTHREAD_ONCE_INIT;

/* Returns a +1 NSViewController-rooted adapter wrapping (and retaining)
 * `content`. The NSSplitViewItem (or NSViewController.childViewControllers)
 * it is handed to retains it; the caller releases its own +1 after that.
 *
 * The adapter is also stored weakly on content->adapter_ so subsequent
 * AI_addChildViewController: calls can find the parent's existing adapter
 * without a hashtable lookup. The back-edge is cleared in adp_dealloc. */
id AIVCAdapterNew(AIViewController *content) {
  pthread_once(&g_adpOnce, adp_build);
  if (!g_adpClass) return nil;
  if (content && [content aiAdapter]) {
    /* An AIViewController has at most one adapter; reusing would double-mark
     * externallyDriven and double-retain content. Callers that need an
     * already-wrapped VC should reach for -aiAdapter directly. */
    [NSException raise:NSInternalInconsistencyException
                format:@"[AIVCAdapterNew] %@ already has an adapter; "
                       @"a single AIViewController cannot be wrapped twice.",
                       content];
  }
  id a = [[g_adpClass alloc] init];
  if (a) {
    [content aiMarkExternallyDriven];   /* AppKit now owns the lifecycle */
    adp_ctx(a)->content = [content retain];
    [content aiSetAdapter:a];           /* weak */
  }
  return a;
}

#endif /* !TARGET_OS_IPHONE */
