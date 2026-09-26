#import "ApolloSettingsForm.h"

// "Gesture Blocking" sub-screen: claim one of Apollo's four swipe slots for a
// one-shot block action, separately for posts and for comments.
//
// This screen only records WHICH slot Reborn takes over; the slot must still be
// assigned to some native action in Apollo's own Settings -> Gestures, because
// an unassigned slot has no threshold to cross and so never fires. See
// ApolloGestureBlockActions.xm for the interception. Declarative form -- see
// -buildForm.
@interface ApolloGestureBlockingViewController : ApolloSettingsFormViewController
@end
