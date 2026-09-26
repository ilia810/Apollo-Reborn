#import "ApolloBotSuspicion.h"
#import "ApolloCommon.h"
#import "ApolloState.h"
#import "ApolloTextureDecls.h"
#import "ApolloThemeRuntime.h"
#import "ApolloUserProfileCache.h"
#import "UIWindow+Apollo.h"
#import "settings/ApolloBotSuspicionViewController.h"
#import <objc/message.h>
#import <objc/runtime.h>

// Native model ivars and layout ABI are documented by the class-dump headers
// for PostInfoNode / CommentCellNode. PostInfoNode is shared by compact/large
// feed posts and the comments header, including posts with hidden author text.
@interface _TtC6Apollo12PostInfoNode : ASDisplayNode
@end
@interface _TtC6Apollo15CommentCellNode : ASDisplayNode
@end
@interface ASDisplayNode (ApolloBotRuntime)
@property(nonatomic, getter=isHidden) BOOL hidden;
@end

@interface ApolloBotBadgeBinding : NSObject
@property(nonatomic, weak) ASDisplayNode *owner;
@property(nonatomic) BOOL comment;
@property(nonatomic) BOOL visible;
@property(nonatomic, copy) NSString *username;
@property(nonatomic, strong) ASTextNode *badgeNode;
// Texture reads only this atomic published node from its layout worker. All
// configuration, profile access, network scheduling and UI writes run on main.
@property(atomic, strong) ASTextNode *layoutBadge;
@property(nonatomic, copy) NSString *explanation;
- (void)refresh;
- (void)showExplanation;
@end

static const void *ApolloBotBindingKey = &ApolloBotBindingKey;
static NSHashTable<ApolloBotBadgeBinding *> *sBindings;
static NSMutableDictionary<NSString *, NSDate *> *sRetryAfter;
static BOOL sLookupInFlight;
static BOOL sPumpScheduled;
static NSDate *sNextLookup;

static void ApolloBotPump(void);

static id ApolloBotObjectIvar(id object, const char *name) {
    if (!object) return nil;
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    // These are known ObjC reference ivars, never Swift String/Array structs.
    return ivar ? object_getIvar(object, ivar) : nil;
}

static NSString *ApolloBotAuthor(ASDisplayNode *owner, BOOL comment) {
    id model = ApolloBotObjectIvar(owner, comment ? "comment" : "link");
    if (![model respondsToSelector:@selector(author)]) return nil;
    id author = ((id (*)(id, SEL))objc_msgSend)(model, @selector(author));
    if (![author isKindOfClass:NSString.class] || [author length] == 0) return nil;
    // Deleted accounts, placeholders and malformed names aren't lookup targets.
    NSCharacterSet *valid = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-"];
    if ([author rangeOfCharacterFromSet:valid.invertedSet].location != NSNotFound) return nil;
    if ([author length] > 64) return nil;
    return [author lowercaseString];
}

static BOOL ApolloBotBindingEnabled(ApolloBotBadgeBinding *binding) {
    return sBotSuspicionEnabled && (binding.comment ? sBotSuspicionComments : sBotSuspicionPosts);
}

static void ApolloBotInvalidate(ASDisplayNode *owner) {
    // Called only after a badge changes, outside layout/row measurement. Native
    // Texture owns row remeasurement; never call UITableView begin/endUpdates.
    __weak ASDisplayNode *weakOwner = owner;
    dispatch_async(dispatch_get_main_queue(), ^{
        ASDisplayNode *node = weakOwner;
        if (!node) return;
        if (ApolloRowMeasureInProgress()) {
            ApolloBotInvalidate(node);
            return;
        }
        Class cellClass = objc_getClass("ASCellNode");
        for (NSUInteger depth = 0; node && depth < 8; depth++) {
            [node invalidateCalculatedLayout];
            [node setNeedsLayout];
            if (cellClass && [node isKindOfClass:cellClass]) break;
            node = [node supernode];
        }
    });
}

@implementation ApolloBotBadgeBinding

- (void)refresh {
    ASDisplayNode *owner = self.owner;
    if (!owner) return;
    self.username = ApolloBotAuthor(owner, self.comment);
    ApolloUserProfileInfo *info = ApolloBotBindingEnabled(self) && self.username.length
        ? [ApolloUserProfileCache.sharedCache cachedInfoForUsername:self.username] : nil;
    ApolloBotScore score = ApolloBotScoreForProfile(info, sBotSuspicionRules);
    BOOL show = ApolloBotBindingEnabled(self) && self.username.length && score.flagged;
    if (!show) {
        if (self.layoutBadge) {
            self.layoutBadge = nil;
            self.badgeNode.hidden = YES;
            self.explanation = nil;
            ApolloBotInvalidate(owner);
        }
        return;
    }

    if (!self.badgeNode) {
        ASTextNode *badge = [objc_getClass("ASTextNode") new];
        if (!badge) return;
        badge.maximumNumberOfLines = 0;
        badge.userInteractionEnabled = YES;
        ApolloMarkTweakUITextNode(badge); // never translate this as post/comment content
        __weak typeof(self) weakSelf = self;
        [badge onDidLoad:^(__kindof ASDisplayNode *node) {
            [node.view addGestureRecognizer:[[UITapGestureRecognizer alloc]
                initWithTarget:weakSelf action:@selector(showExplanation)]];
            node.view.isAccessibilityElement = YES;
            node.view.accessibilityTraits = UIAccessibilityTraitButton;
            node.view.accessibilityHint = @"Show the matching rules and adjust bot suspicion settings";
        }];
        self.badgeNode = badge;
    }
    ASTextNode *badge = self.badgeNode;
    if (badge.supernode != owner) [owner addSubnode:badge];
    UIColor *accent = ApolloThemeAccentColor() ?: owner.view.tintColor ?: UIColor.systemBlueColor;
    accent = [accent resolvedColorWithTraitCollection:owner.view.traitCollection];
    NSString *label = [NSString stringWithFormat:@"Possible bot · %d/100 points ⓘ", score.points];
    NSAttributedString *text = [[NSAttributedString alloc] initWithString:label attributes:@{
        NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1],
        NSForegroundColorAttributeName: accent,
    }];
    BOOL changed = !self.layoutBadge || ![badge.attributedText isEqualToAttributedString:text];
    if (changed) badge.attributedText = text;
    badge.hidden = NO;
    if (badge.isNodeLoaded) badge.view.accessibilityLabel = label;
    double ageDays = (NSDate.date.timeIntervalSince1970 - info.createdUTC) / 86400.0;
    self.explanation = ApolloBotScoreExplanation(score, sBotSuspicionRules, ageDays);
    self.layoutBadge = badge;
    if (changed) ApolloBotInvalidate(owner);
}

- (void)showExplanation {
    [self refresh]; // re-evaluate if a profile or the settings changed meanwhile
    if (!self.layoutBadge || !self.explanation.length) return;
    UIViewController *presenter = [self.owner.view.window visibleViewController];
    if (!presenter || presenter.presentedViewController) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Possible bot"
        message:self.explanation preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Done" style:UIAlertActionStyleCancel handler:nil]];
    __weak UIViewController *weakPresenter = presenter;
    [alert addAction:[UIAlertAction actionWithTitle:@"Adjust Rules" style:UIAlertActionStyleDefault
        handler:^(__unused UIAlertAction *action) {
        UIViewController *vc = weakPresenter;
        if (!vc) return;
        ApolloBotSuspicionViewController *settings = [[ApolloBotSuspicionViewController alloc]
            initWithStyle:UITableViewStyleInsetGrouped];
        if (vc.navigationController) {
            [vc.navigationController pushViewController:settings animated:YES];
        } else {
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settings];
            [vc presentViewController:nav animated:YES completion:nil];
        }
    }]];
    [presenter presentViewController:alert animated:YES completion:nil];
}
@end

static void ApolloBotSchedulePump(NSTimeInterval delay) {
    if (sPumpScheduled) return;
    sPumpScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MAX(0, delay) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        sPumpScheduled = NO;
        ApolloBotPump();
    });
}

static void ApolloBotPump(void) {
    if (!sBotSuspicionEnabled || sLookupInFlight || UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return;
    NSTimeInterval wait = [sNextLookup timeIntervalSinceNow];
    if (wait > 0) {
        ApolloBotSchedulePump(wait);
        return;
    }
    // No unbounded pending queue: every pass selects from weak, currently
    // visible bindings. Scrolling away discards queued work automatically.
    for (ApolloBotBadgeBinding *binding in sBindings.allObjects) {
        if (!binding.owner || !binding.visible || !ApolloBotBindingEnabled(binding)) continue;
        NSString *username = ApolloBotAuthor(binding.owner, binding.comment);
        if (!username.length || [sRetryAfter[username] timeIntervalSinceNow] > 0) continue;
        ApolloUserProfileInfo *cached = [ApolloUserProfileCache.sharedCache cachedInfoForUsername:username];
        if (ApolloBotProfileStatsAreFresh(cached)) continue;
        sLookupInFlight = YES;
        [ApolloUserProfileCache.sharedCache requestAccountStatsForUsername:username completion:^(ApolloUserProfileInfo *info) {
            sLookupInFlight = NO;
            // The cache handles transport retries; this caller backs off from
            // missing/incomplete data instead of refetching on each cell entry.
            if (!ApolloBotProfileStatsAreFresh(info)) {
                sRetryAfter[username] = [NSDate dateWithTimeIntervalSinceNow:15 * 60];
                // Back off the whole feature after a failure as well as the
                // author, so an offline session / 429 doesn't walk every user.
                sNextLookup = [NSDate dateWithTimeIntervalSinceNow:60];
            } else {
                [sRetryAfter removeObjectForKey:username];
                sNextLookup = [NSDate dateWithTimeIntervalSinceNow:2];
            }
            for (NSString *key in sRetryAfter.allKeys) {
                if ([sRetryAfter[key] timeIntervalSinceNow] <= 0) [sRetryAfter removeObjectForKey:key];
            }
            for (ApolloBotBadgeBinding *candidate in sBindings.allObjects) {
                if (candidate.visible || [candidate.username isEqualToString:username]) [candidate refresh];
            }
            ApolloBotSchedulePump(MAX(2, [sNextLookup timeIntervalSinceNow]));
        }];
        break; // at most one additional profile lookup at a time
    }
}

static void ApolloBotSetVisible(ASDisplayNode *owner, BOOL comment, BOOL visible) {
    __weak ASDisplayNode *weakOwner = owner;
    // Texture's state callbacks can be off-main. Their order is preserved;
    // late completions use the current model and never a captured author label.
    dispatch_async(dispatch_get_main_queue(), ^{
        ASDisplayNode *node = weakOwner;
        if (!node) return;
        ApolloBotBadgeBinding *binding = objc_getAssociatedObject(node, ApolloBotBindingKey);
        if (!binding && visible) {
            binding = [ApolloBotBadgeBinding new];
            binding.owner = node;
            binding.comment = comment;
            objc_setAssociatedObject(node, ApolloBotBindingKey, binding, OBJC_ASSOCIATION_RETAIN);
            [sBindings addObject:binding];
        }
        binding.visible = visible;
        if (visible) {
            [binding refresh];
            ApolloBotSchedulePump(0);
        }
    });
}

static id ApolloBotWrapLayout(ASDisplayNode *owner, id nativeSpec, BOOL comment) {
    ApolloBotBadgeBinding *binding = objc_getAssociatedObject(owner, ApolloBotBindingKey);
    ASTextNode *badge = binding.layoutBadge;
    Class stackClass = objc_getClass("ASStackLayoutSpec");
    Class insetClass = objc_getClass("ASInsetLayoutSpec");
    if (!nativeSpec || !badge || !stackClass || !insetClass) return nativeSpec;
    // Layout is pure composition: no network, UIKit views, model mutations or
    // invalidation here. Let Texture measure long labels/Dynamic Type normally.
    id caption = [insetClass insetLayoutSpecWithInsets:
        (comment ? UIEdgeInsetsMake(0, 16, 6, 12) : UIEdgeInsetsMake(0, 0, 2, 0)) child:badge];
    // Verified Texture enum values: vertical 0, justify start 0, stretch 3.
    return [stackClass stackLayoutSpecWithDirection:0 spacing:4 justifyContent:0 alignItems:3
        children:@[nativeSpec, caption]];
}

%hook _TtC6Apollo12PostInfoNode
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    // PostInfoNode has its own native hit tester for its known metadata
    // buttons. Route only our caption explicitly, preserving all other hits.
    ApolloBotBadgeBinding *binding = objc_getAssociatedObject(self, ApolloBotBindingKey);
    ASTextNode *badge = binding.layoutBadge;
    if (badge && badge.isNodeLoaded && !badge.hidden) {
        UIView *view = badge.view;
        CGPoint local = [view convertPoint:point fromView:((ASDisplayNode *)self).view];
        UIView *hit = [view hitTest:local withEvent:event];
        if (hit) return hit;
    }
    return %orig;
}
- (void)didEnterDisplayState {
    %orig;
    ApolloBotSetVisible((ASDisplayNode *)self, NO, YES);
}
- (void)didExitDisplayState {
    %orig;
    ApolloBotSetVisible((ASDisplayNode *)self, NO, NO);
}
- (id)layoutSpecThatFits:(struct ApolloTextureSizeRange)size {
    id spec = %orig;
    return ApolloBotWrapLayout((ASDisplayNode *)self, spec, NO);
}
%end

%hook _TtC6Apollo15CommentCellNode
- (void)didEnterDisplayState {
    %orig;
    ApolloBotSetVisible((ASDisplayNode *)self, YES, YES);
}
- (void)didExitDisplayState {
    %orig;
    ApolloBotSetVisible((ASDisplayNode *)self, YES, NO);
}
- (id)layoutSpecThatFits:(struct ApolloTextureSizeRange)size {
    id spec = %orig;
    return ApolloBotWrapLayout((ASDisplayNode *)self, spec, YES);
}
%end

%ctor {
    sBindings = [NSHashTable weakObjectsHashTable];
    sRetryAfter = [NSMutableDictionary dictionary];
    for (NSString *name in @[ApolloBotSuspicionSettingsChangedNotification,
                             ApolloUserProfileInfoUpdatedNotification,
                             UIApplicationDidBecomeActiveNotification,
                             @"com.christianselig.ApolloSpecificThemeChanged",
                             UIContentSizeCategoryDidChangeNotification]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
            usingBlock:^(__unused NSNotification *notification) {
            for (ApolloBotBadgeBinding *binding in sBindings.allObjects) [binding refresh];
            ApolloBotSchedulePump(0);
        }];
    }
    ApolloLog(@"[BotSuspicion] post/comment badge hooks installed (opt-in)");
}
