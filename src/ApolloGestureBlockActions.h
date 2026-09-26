// ApolloGestureBlockActions — turns a swipe gesture slot into a one-shot
// "block" action.
//
// Apollo's gesture actions are cases of a STRIPPED Swift enum
// (Apollo.SlideGestureAction, 21 cases: upvote/save/hide/moreOptions/...).
// A case cannot be added to an enum inside a compiled binary, so we do not try
// to extend the native picker. Instead the user assigns a slot to any native
// action in Apollo's own Settings → Gestures, then tells Reborn to CLAIM that
// slot (Settings → Apollo Reborn → Posts & Feeds → Gesture Blocking). When a
// claimed slot fires we suppress the native action and run ours instead.
//
// The interception seam is -[SlideGestureBuilder
// slidingViewPannedWithGestureRecognizer:], which IS @objc-visible (it is the
// pan target-action), so this needs no offset-based patching. Suppression
// works by writing Optional.none into the builder's `activatedSlideGesturePoint`
// ivar before %orig on the ENDED state: the native handler then believes no
// point was crossed and performs nothing, while still running its snap-back
// animation. Ivar offsets are resolved by NAME at runtime via
// ApolloSwiftRuntime.h, never hardcoded.
//
// Actions themselves need no reverse engineering — RedditKit exposes both as
// plain ObjC on RDKClient:
//   • block subreddit -> -addSubredditToFilteredSubredditsWithName:completion:
//   • block account   -> -blockUserWithFullname:completion:
// Requests go through ApolloActiveAccountClient() so they hit the account the
// user is actually browsing as.

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Which slot a swipe crossed. Raw values match Apollo.SlideGesturePoint's case
// order, which is also its in-memory byte value.
typedef NS_ENUM(NSInteger, ApolloGestureSlot) {
    ApolloGestureSlotNone      = -1,  // "off" in our settings
    ApolloGestureSlotFirstLeft  = 0,  // short left swipe
    ApolloGestureSlotSecondLeft = 1,  // long left swipe
    ApolloGestureSlotFirstRight = 2,  // short right swipe
    ApolloGestureSlotSecondRight = 3, // long right swipe
};

// Apollo.SlideGestureArea case order (also its byte value).
typedef NS_ENUM(NSInteger, ApolloGestureArea) {
    ApolloGestureAreaPosts           = 0,
    ApolloGestureAreaComments        = 1,
    ApolloGestureAreaInbox           = 2,
    ApolloGestureAreaProfilePosts    = 3,
    ApolloGestureAreaProfileComments = 4,
};

// This module is Logos/ObjC++ but the settings screen that reads it is plain
// ObjC, so the accessors below need C linkage to resolve at link time.
__BEGIN_DECLS

// User-facing slot names, indexed by ApolloGestureSlot (0-3). Shared with the
// settings picker so the two never drift.
NSArray<NSString *> *ApolloGestureSlotNames(void);

// The slot currently claimed for each action, or ApolloGestureSlotNone.
ApolloGestureSlot ApolloGestureBlockPostSlot(void);
ApolloGestureSlot ApolloGestureBlockCommentSlot(void);

__END_DECLS

NS_ASSUME_NONNULL_END
