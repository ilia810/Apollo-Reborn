#import "ApolloAccountCredentials.h"
#import "ApolloCommon.h"
#import "ApolloSwiftRuntime.h"
#import "ApolloTextureDecls.h"
#import "ApolloThemeRuntime.h"
#import "ApolloToast.h"
#import <objc/message.h>

@interface RDKUser : NSObject
@property(nonatomic, copy) NSArray<NSString *> *filteredSubreddits;
@property(nonatomic, copy) NSArray<NSString *> *locallyFilteredSubreddits;
@end
@interface RDKClient : NSObject
@property(nonatomic, strong) RDKUser *currentUser;
- (id)addSubredditToFilteredSubredditsWithName:(NSString *)name completion:(void (^)(NSError *))completion;
@end
@interface ASImageNode : ASDisplayNode
@property(nonatomic, strong) UIImage *image;
@end
@interface ASDisplayNode (ApolloFilterControl)
@property(nonatomic, getter=isHidden) BOOL hidden;
@property(nonatomic, getter=isEnabled) BOOL enabled;
@end
@interface _TtC6Apollo17LargePostCellNode : ASDisplayNode
@end
@interface _TtC6Apollo19CompactPostCellNode : ASDisplayNode
@end
@interface _TtC6Apollo22CommentsHeaderCellNode : ASDisplayNode
@end

static const void *kFilterImage = &kFilterImage;
static NSHashTable<ASDisplayNode *> *sPostOwners;
// Deduplicate quick repeated taps, separately for each live account client.
static NSMapTable<RDKClient *, NSMutableSet<NSString *> *> *sPendingFilters;

static BOOL ApolloFilterListContains(NSArray *list, NSString *name) {
    for (id entry in list) {
        if ([entry isKindOfClass:NSString.class] && [entry caseInsensitiveCompare:name] == NSOrderedSame) return YES;
    }
    return NO;
}

static void ApolloFilterFinished(RDKClient *client, NSString *name, BOOL local) {
    // The native filter menu appends the name to the account's RDKUser after
    // success, then posts KeywordFiltersChanged. Calling only the RedditKit
    // request would leave Apollo's filter list and already-loaded feeds stale.
    // Above Apollo's 98-entry server cutoff it uses locallyFilteredSubreddits.
    RDKUser *user = client.currentUser;
    if (!user) return;
    NSArray *list = (local ? user.locallyFilteredSubreddits : user.filteredSubreddits) ?: @[];
    if (!ApolloFilterListContains(list, name)) {
        NSArray *updated = [list arrayByAddingObject:name];
        if (local) user.locallyFilteredSubreddits = updated;
        else user.filteredSubreddits = updated;
    }
    Class managerClass = objc_getClass("_TtC6Apollo14AccountManager");
    SEL shared = @selector(shared), persist = @selector(persistInformationToDisk);
    if ([managerClass respondsToSelector:shared]) {
        id manager = ((id (*)(id, SEL))objc_msgSend)(managerClass, shared);
        if ([manager respondsToSelector:persist]) ((void (*)(id, SEL))objc_msgSend)(manager, persist);
    }
    [NSNotificationCenter.defaultCenter postNotificationName:@"com.christianselig.KeywordFiltersChanged" object:nil];
    ApolloShowToastWithStyle([NSString stringWithFormat:@"Filtered r/%@", name],
        @"Manage in Settings → Filters & Blocks", ApolloToastStyleSuccess, @"line.3.horizontal.decrease.circle");
    ApolloLog(@"[PostFilterButton] subreddit filter saved (%@)", local ? @"local" : @"server");
}

static void ApolloFilterPostSubreddit(ASDisplayNode *owner) {
    NSCAssert(NSThread.isMainThread, @"Post filter taps must run on main");
    id link = ApolloReadObjectIvar(owner, "link");
    NSString *name = [link respondsToSelector:@selector(subreddit)]
        ? ((id (*)(id, SEL))objc_msgSend)(link, @selector(subreddit)) : nil;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
        @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"];
    if (![name isKindOfClass:NSString.class] || !name.length || name.length > 64 ||
        [name rangeOfCharacterFromSet:allowed.invertedSet].location != NSNotFound) {
        ApolloShowToastWithStyle(@"Could not identify subreddit", nil, ApolloToastStyleError, nil);
        return;
    }
    RDKClient *client = ApolloActiveAccountClient();
    if (![client respondsToSelector:@selector(addSubredditToFilteredSubredditsWithName:completion:)] || !client.currentUser) {
        ApolloShowToastWithStyle(@"Sign in to filter subreddits", nil, ApolloToastStyleError, nil);
        return;
    }
    name = name.lowercaseString;
    if (ApolloFilterListContains(client.currentUser.filteredSubreddits, name) ||
        ApolloFilterListContains(client.currentUser.locallyFilteredSubreddits, name)) {
        ApolloShowToastWithStyle(@"Subreddit already filtered", @"Manage in Settings → Filters & Blocks",
            ApolloToastStyleInfo, @"line.3.horizontal.decrease.circle");
        return;
    }
    NSMutableSet *pending = [sPendingFilters objectForKey:client];
    if (!pending) {
        pending = [NSMutableSet set];
        [sPendingFilters setObject:pending forKey:client];
    }
    if ([pending containsObject:name]) return;
    if (client.currentUser.filteredSubreddits.count >= 98) {
        ApolloFilterFinished(client, name, YES);
        return;
    }
    [pending addObject:name];
    __weak RDKClient *weakClient = client;
    [client addSubredditToFilteredSubredditsWithName:name completion:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [pending removeObject:name];
            RDKClient *completedClient = weakClient;
            // Signing out can release the initiating account while its request
            // finishes. Never apply that completion to a newly selected one.
            if (!completedClient) return;
            if (error) {
                // No account names, post text, URLs or credentials in logs.
                ApolloLog(@"[PostFilterButton] filter request failed (code %ld)", (long)error.code);
                ApolloShowToastWithStyle(@"Could not filter subreddit", @"Please try again",
                    ApolloToastStyleError, nil);
                return;
            }
            ApolloFilterFinished(completedClient, name, NO);
        });
    }];
}

static void ApolloPreparePostFilterButton(ASDisplayNode *owner) {
    if (!NSThread.isMainThread) {
        __weak ASDisplayNode *weakOwner = owner;
        dispatch_async(dispatch_get_main_queue(), ^{ if (weakOwner) ApolloPreparePostFilterButton(weakOwner); });
        return;
    }
    [sPostOwners addObject:owner];
    // Each is a known ObjC reference from Apollo's class-dump. Never treat
    // actionDelegate (a Swift protocol existential) as an ObjC object.
    ASDisplayNode *button = ApolloReadObjectIvar(owner, "downvoteButtonNode");
    if (!button) {
        id bar = ApolloReadObjectIvar(owner, "optionButtonsNode") ?: ApolloReadObjectIvar(owner, "quickBarNode");
        button = ApolloReadObjectIvar(bar, "downvoteButton");
    }
    ASImageNode *icon = ApolloReadObjectIvar(button, "iconNode");
    if (!icon) return;
    UIColor *accent = ApolloThemeAccentColor() ?: owner.view.tintColor ?: UIColor.systemBlueColor;
    accent = [accent resolvedColorWithTraitCollection:owner.view.traitCollection];
    UIImage *image = [[UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightSemibold]]
        imageWithTintColor:accent renderingMode:UIImageRenderingModeAlwaysOriginal];
    if (!image) return;
    objc_setAssociatedObject(icon, kFilterImage, image, OBJC_ASSOCIATION_RETAIN);
    icon.image = image;
    // Archived posts still have a subreddit that can be filtered. This Bool
    // belongs only to this repurposed control; the post's voting state stays put.
    ptrdiff_t archived = ApolloIvarOffset(object_getClass(button), "isArchived");
    if (archived >= 0) *((uint8_t *)(__bridge void *)button + archived) = 0;
    button.enabled = YES;
    ASDisplayNode *background = ApolloReadObjectIvar(button, "backgroundNode");
    background.hidden = YES;
    [button onDidLoad:^(__kindof ASDisplayNode *node) {
        node.view.isAccessibilityElement = YES;
        node.view.accessibilityLabel = @"Filter Subreddit";
        node.view.accessibilityHint = @"Exclude this subreddit from All Posts and Popular";
        node.view.accessibilityTraits = UIAccessibilityTraitButton;
    }];
}

// Native voting/theme updates replace the icon image. Retain our symbol only
// for explicitly tagged post controls, without touching other vote buttons.
%hook ASImageNode
- (void)setImage:(UIImage *)image {
    UIImage *filter = objc_getAssociatedObject(self, kFilterImage);
    %orig(filter ?: image);
}
%end

%hook _TtC6Apollo17LargePostCellNode
- (void)didLoad { %orig; ApolloPreparePostFilterButton((ASDisplayNode *)self); }
- (void)didEnterDisplayState { %orig; ApolloPreparePostFilterButton((ASDisplayNode *)self); }
- (void)downvoteButtonTappedWithSender:(id)sender { ApolloFilterPostSubreddit((ASDisplayNode *)self); }
%end

%hook _TtC6Apollo19CompactPostCellNode
- (void)didLoad { %orig; ApolloPreparePostFilterButton((ASDisplayNode *)self); }
- (void)didEnterDisplayState { %orig; ApolloPreparePostFilterButton((ASDisplayNode *)self); }
- (void)downvoteButtonTappedWithSender:(id)sender { ApolloFilterPostSubreddit((ASDisplayNode *)self); }
%end

%hook _TtC6Apollo22CommentsHeaderCellNode
- (void)didLoad { %orig; ApolloPreparePostFilterButton((ASDisplayNode *)self); }
- (void)didEnterDisplayState { %orig; ApolloPreparePostFilterButton((ASDisplayNode *)self); }
- (void)quickBarDownvoteButtonTappedWithSender:(id)sender { ApolloFilterPostSubreddit((ASDisplayNode *)self); }
%end

%ctor {
    sPostOwners = [NSHashTable weakObjectsHashTable];
    sPendingFilters = [NSMapTable weakToStrongObjectsMapTable];
    [NSNotificationCenter.defaultCenter addObserverForName:@"com.christianselig.ApolloSpecificThemeChanged"
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
        for (ASDisplayNode *owner in sPostOwners.allObjects) ApolloPreparePostFilterButton(owner);
    }];
    ApolloLog(@"[PostFilterButton] post downvote controls now filter subreddits");
}
