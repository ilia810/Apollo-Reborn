#import "ApolloGestureBlockActions.h"

#import "ApolloAccountCredentials.h"
#import "ApolloCommon.h"
#import "ApolloSwiftRuntime.h"
#import "ApolloToast.h"
#import "UIWindow+Apollo.h"
#import "UserDefaultConstants.h"

#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

// Optional<SlideGesturePoint> is a 4-case payload-free enum, so Swift stores it
// in one byte using a spare tag: 0-3 are the cases, 4 is Optional.none. We only
// ever WRITE none, and treat anything outside 0-3 as "no point crossed".
static const uint8_t kApolloGesturePointNone = 4;

#pragma mark - RedditKit surface
//
// Forward declarations only: these classes always exist in Apollo, and
// declaring them keeps our call sites type-checked without pulling the
// generated headers (which name Swift types ObjC cannot parse) into the build.

@interface RDKUser : NSObject
@property (copy, nonatomic) NSString *fullName;
@end

@interface RDKLink : NSObject
@property (copy, nonatomic) NSString *author;
@property (copy, nonatomic) NSString *subreddit;
@end

@interface RDKComment : NSObject
@property (copy, nonatomic) NSString *author;
@property (copy, nonatomic) NSString *authorFullName;
@property (copy, nonatomic) NSString *subreddit;
@end

@interface RDKClient : NSObject
- (id)blockUserWithFullname:(id)fullname completion:(id)completion;
- (id)addSubredditToFilteredSubredditsWithName:(id)name completion:(id)completion;
- (id)userWithUsername:(id)username completion:(id)completion;
@end

#pragma mark - Settings

NSArray<NSString *> *ApolloGestureSlotNames(void) {
    static NSArray<NSString *> *names = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        names = @[ @"Short Left Swipe", @"Long Left Swipe",
                   @"Short Right Swipe", @"Long Right Swipe" ];
    });
    return names;
}

static ApolloGestureSlot ApolloGestureSlotForKey(NSString *key) {
    NSInteger raw = [[NSUserDefaults standardUserDefaults] integerForKey:key];
    return (raw >= ApolloGestureSlotFirstLeft && raw <= ApolloGestureSlotSecondRight)
        ? (ApolloGestureSlot)raw : ApolloGestureSlotNone;
}

ApolloGestureSlot ApolloGestureBlockPostSlot(void) {
    return ApolloGestureSlotForKey(UDKeyGestureBlockPostSlot);
}

ApolloGestureSlot ApolloGestureBlockCommentSlot(void) {
    return ApolloGestureSlotForKey(UDKeyGestureBlockCommentSlot);
}

#pragma mark - Block primitives

// The client for the account the user is browsing as. nil when signed out, in
// which case there is nothing to block against and we bail loudly.
static RDKClient *ApolloGestureBlockClient(void) {
    id client = ApolloActiveAccountClient();
    return [client isKindOfClass:objc_getClass("RDKClient")] ? (RDKClient *)client : nil;
}

// Subreddit blocking is Reddit's "filtered subreddits" list -- the same list
// Apollo's Filters & Blocks -> Subreddits section shows.
static void ApolloGestureBlockSubreddit(NSString *subreddit, void (^done)(BOOL ok)) {
    RDKClient *client = ApolloGestureBlockClient();
    if (!client || subreddit.length == 0) { if (done) done(NO); return; }

    [client addSubredditToFilteredSubredditsWithName:subreddit
                                          completion:^(NSError *error) {
        if (error) ApolloLog(@"[GestureBlock] filter r/%@ failed: %@", subreddit, error);
        if (done) dispatch_async(dispatch_get_main_queue(), ^{ done(error == nil); });
    }];
}

// Account blocking needs a t2_ fullname. Comments carry authorFullName already;
// posts do not expose one, so we resolve the username first. The lookup is one
// extra request and only happens on the post path.
static void ApolloGestureBlockAccount(NSString *fullname, NSString *username,
                                      void (^done)(BOOL ok)) {
    RDKClient *client = ApolloGestureBlockClient();
    if (!client) { if (done) done(NO); return; }

    void (^block)(NSString *) = ^(NSString *resolved) {
        if (resolved.length == 0) {
            ApolloLog(@"[GestureBlock] no fullname for u/%@; cannot block", username);
            if (done) dispatch_async(dispatch_get_main_queue(), ^{ done(NO); });
            return;
        }
        [client blockUserWithFullname:resolved completion:^(NSError *error) {
            if (error) ApolloLog(@"[GestureBlock] block u/%@ failed: %@", username, error);
            if (done) dispatch_async(dispatch_get_main_queue(), ^{ done(error == nil); });
        }];
    };

    if (fullname.length > 0) { block(fullname); return; }
    if (username.length == 0) { if (done) done(NO); return; }

    [client userWithUsername:username completion:^(RDKUser *user, NSError *error) {
        if (error) ApolloLog(@"[GestureBlock] lookup u/%@ failed: %@", username, error);
        block([user isKindOfClass:objc_getClass("RDKUser")] ? user.fullName : nil);
    }];
}

#pragma mark - Composite actions

static void ApolloGestureBlockToast(BOOL ok, NSString *message) {
    ApolloShowToastWithStyle(message, nil,
                             ok ? ApolloToastStyleSuccess : ApolloToastStyleError,
                             ok ? @"nosign" : @"exclamationmark.triangle");
}

// Post slot: filter the subreddit and (by default) block the author too. The
// two calls are independent, so a failure on one still reports the other.
static void ApolloGestureBlockPerformForPost(NSString *subreddit, NSString *author) {
    BOOL alsoAuthor = [[NSUserDefaults standardUserDefaults] boolForKey:UDKeyGestureBlockPostIncludesAuthor]
        && author.length > 0;

    ApolloGestureBlockSubreddit(subreddit, ^(BOOL subOK) {
        if (!alsoAuthor) {
            ApolloGestureBlockToast(subOK, subOK
                ? [NSString stringWithFormat:@"Blocked r/%@", subreddit]
                : @"Could not block subreddit");
            return;
        }
        ApolloGestureBlockAccount(nil, author, ^(BOOL userOK) {
            NSString *message;
            if (subOK && userOK) {
                message = [NSString stringWithFormat:@"Blocked r/%@ and u/%@", subreddit, author];
            } else if (subOK) {
                message = [NSString stringWithFormat:@"Blocked r/%@ -- u/%@ failed", subreddit, author];
            } else if (userOK) {
                message = [NSString stringWithFormat:@"Blocked u/%@ -- r/%@ failed", author, subreddit];
            } else {
                message = @"Block failed";
            }
            ApolloGestureBlockToast(subOK && userOK, message);
        });
    });
}

// Comment slot: block the commenter.
static void ApolloGestureBlockPerformForComment(NSString *fullname, NSString *author) {
    ApolloGestureBlockAccount(fullname, author, ^(BOOL ok) {
        ApolloGestureBlockToast(ok, ok
            ? [NSString stringWithFormat:@"Blocked u/%@", author]
            : @"Could not block account");
    });
}

// A block is remote and easy to trigger by accident on a long swipe, so the
// default is to confirm.
static void ApolloGestureBlockConfirmThen(UIView *anchorView, NSString *message,
                                          void (^perform)(void)) {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:UDKeyGestureBlockConfirm]) {
        perform();
        return;
    }

    UIViewController *presenter = [anchorView.window visibleViewController];
    if (!presenter) { perform(); return; }

    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:@"Block"
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Block"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction *action) { perform(); }]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Builder introspection

// The builder delegate is the section controller that owns the swiped cell.
// SlideGestureDelegate is class-constrained, so the existential FIRST word is
// the instance pointer -- which is what ApolloReadObjectIvar hands back. We
// compare the isa directly instead of -isKindOfClass: so a nil/garbage slot
// never turns into a message send.
static id ApolloGestureBlockControllerOfClass(id builder, Class expected) {
    if (!expected) return nil;
    id delegate = ApolloReadObjectIvar(builder, "delegate");
    if (!delegate) return nil;
    return object_getClass(delegate) == expected ? delegate : nil;
}

static ApolloGestureArea ApolloGestureBlockAreaOf(id builder) {
    ptrdiff_t offset = ApolloIvarOffset(object_getClass(builder), "area");
    if (offset < 0) return (ApolloGestureArea)NSNotFound;
    return (ApolloGestureArea)(*(uint8_t *)((uint8_t *)(__bridge void *)builder + offset));
}

// Reads the byte and, when clear is set, writes Optional.none back so the
// native handler finds no activated point and performs nothing.
static ApolloGestureSlot ApolloGestureBlockTakeSlot(id builder, BOOL clear) {
    ptrdiff_t offset = ApolloIvarOffset(object_getClass(builder), "activatedSlideGesturePoint");
    if (offset < 0) return ApolloGestureSlotNone;

    uint8_t *slot = (uint8_t *)(__bridge void *)builder + offset;
    uint8_t raw = *slot;
    if (raw >= kApolloGesturePointNone) return ApolloGestureSlotNone;
    if (clear) *slot = kApolloGesturePointNone;
    return (ApolloGestureSlot)raw;
}

#pragma mark - Hook

%hook _TtC6Apollo19SlideGestureBuilder

// The pan target-action. Everything below only engages on the ENDED state and
// only when the crossed slot is the one the user claimed; every other pan (and
// every unconfigured install) falls straight through to %orig.
- (void)slidingViewPannedWithGestureRecognizer:(UIPanGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateEnded) { %orig; return; }

    ApolloGestureSlot postSlot = ApolloGestureBlockPostSlot();
    ApolloGestureSlot commentSlot = ApolloGestureBlockCommentSlot();
    if (postSlot == ApolloGestureSlotNone && commentSlot == ApolloGestureSlotNone) { %orig; return; }

    ApolloGestureSlot fired = ApolloGestureBlockTakeSlot(self, NO);
    if (fired == ApolloGestureSlotNone) { %orig; return; }

    ApolloGestureArea area = ApolloGestureBlockAreaOf(self);
    BOOL postArea = (area == ApolloGestureAreaPosts || area == ApolloGestureAreaProfilePosts);
    BOOL commentArea = (area == ApolloGestureAreaComments || area == ApolloGestureAreaProfileComments);

    UIView *anchor = recognizer.view;

    if (postArea && fired == postSlot) {
        id controller = ApolloGestureBlockControllerOfClass(
            self, objc_getClass("_TtC6Apollo21PostSectionController"));
        id link = controller ? ApolloReadObjectIvar(controller, "link") : nil;
        BOOL valid = [link isKindOfClass:objc_getClass("RDKLink")];
        NSString *subreddit = valid ? ((RDKLink *)link).subreddit : nil;
        NSString *author = valid ? ((RDKLink *)link).author : nil;

        if (subreddit.length > 0) {
            ApolloGestureBlockTakeSlot(self, YES);  // suppress the native action
            %orig;                                  // ...but keep the snap-back
            BOOL alsoAuthor = [[NSUserDefaults standardUserDefaults]
                                  boolForKey:UDKeyGestureBlockPostIncludesAuthor] && author.length > 0;
            NSString *message = alsoAuthor
                ? [NSString stringWithFormat:@"Block r/%@ and u/%@?", subreddit, author]
                : [NSString stringWithFormat:@"Block r/%@?", subreddit];
            ApolloGestureBlockConfirmThen(anchor, message, ^{
                ApolloGestureBlockPerformForPost(subreddit, author);
            });
            return;
        }
        ApolloLog(@"[GestureBlock] post slot fired but no RDKLink reachable");
    } else if (commentArea && fired == commentSlot) {
        id controller = ApolloGestureBlockControllerOfClass(
            self, objc_getClass("_TtC6Apollo24CommentSectionController"));
        id comment = controller ? ApolloReadObjectIvar(controller, "comment") : nil;
        BOOL valid = [comment isKindOfClass:objc_getClass("RDKComment")];
        NSString *author = valid ? ((RDKComment *)comment).author : nil;
        NSString *fullname = valid ? ((RDKComment *)comment).authorFullName : nil;

        if (author.length > 0) {
            ApolloGestureBlockTakeSlot(self, YES);
            %orig;
            ApolloGestureBlockConfirmThen(anchor,
                                          [NSString stringWithFormat:@"Block u/%@?", author], ^{
                ApolloGestureBlockPerformForComment(fullname, author);
            });
            return;
        }
        ApolloLog(@"[GestureBlock] comment slot fired but no RDKComment reachable");
    }

    %orig;
}

%end

%ctor {
    // Nothing to gate on: the hook is inert until a slot is claimed, and the
    // class always exists in Apollo.
    %init;
    ApolloLog(@"[GestureBlock] module loaded");
}
