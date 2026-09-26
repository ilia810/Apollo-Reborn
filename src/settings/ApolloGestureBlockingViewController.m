#import "ApolloGestureBlockingViewController.h"

#import "ApolloGestureBlockActions.h"
#import "UserDefaultConstants.h"

// Picker option 0 is "Off"; options 1..4 are the four slots, so the option
// index is the slot raw value + 1. Keeping that arithmetic in one place is why
// these two helpers exist rather than inline +1/-1 at each call site.
static NSInteger ApolloGestureBlockingOptionForSlot(ApolloGestureSlot slot) {
    return slot == ApolloGestureSlotNone ? 0 : (NSInteger)slot + 1;
}

static ApolloGestureSlot ApolloGestureBlockingSlotForOption(NSInteger option) {
    return option <= 0 ? ApolloGestureSlotNone : (ApolloGestureSlot)(option - 1);
}

static NSArray<NSString *> *ApolloGestureBlockingOptionTitles(void) {
    NSMutableArray<NSString *> *titles = [@[ @"Off" ] mutableCopy];
    [titles addObjectsFromArray:ApolloGestureSlotNames()];
    return titles;
}

static NSString *ApolloGestureBlockingSlotLabel(ApolloGestureSlot slot) {
    return ApolloGestureBlockingOptionTitles()[ApolloGestureBlockingOptionForSlot(slot)];
}

@implementation ApolloGestureBlockingViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Gesture Blocking";
}

#pragma mark - Slot rows

// Both slot rows are the same control over a different default key, so they
// share one builder. rowID is passed through because the switch row below it
// reloads by identity after a pick changes visibility.
- (ApolloSettingsRow *)slotRowWithID:(NSString *)rowID
                               title:(NSString *)title
                          defaultKey:(NSString *)defaultKey {
    __weak typeof(self) weakSelf = self;
    return [ApolloSettingsRow valueRowWithID:rowID
                                       title:title
                                      detail:^NSString * {
        NSInteger raw = [[NSUserDefaults standardUserDefaults] integerForKey:defaultKey];
        ApolloGestureSlot slot = (raw >= ApolloGestureSlotFirstLeft && raw <= ApolloGestureSlotSecondRight)
            ? (ApolloGestureSlot)raw : ApolloGestureSlotNone;
        return ApolloGestureBlockingSlotLabel(slot);
    }
                                    onSelect:^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;

        NSInteger current = [[NSUserDefaults standardUserDefaults] integerForKey:defaultKey];
        ApolloGestureSlot slot = (current >= ApolloGestureSlotFirstLeft && current <= ApolloGestureSlotSecondRight)
            ? (ApolloGestureSlot)current : ApolloGestureSlotNone;

        ApolloSettingsPresentPicker(strongSelf,
                                    [strongSelf cellForRowID:rowID],
                                    title,
                                    ApolloGestureBlockingOptionTitles(),
                                    ApolloGestureBlockingOptionForSlot(slot),
                                    ^(NSInteger picked) {
            [[NSUserDefaults standardUserDefaults]
                setInteger:ApolloGestureBlockingSlotForOption(picked)
                    forKey:defaultKey];
            [strongSelf reloadRowWithID:rowID];
            [strongSelf visibilityDidChange];
        });
    }];
}

#pragma mark - Form

- (NSArray<ApolloSettingsSection *> *)buildForm {
    ApolloSettingsRow *postSlot = [self slotRowWithID:@"gestureBlock.postSlot"
                                                title:@"Swipe Slot"
                                           defaultKey:UDKeyGestureBlockPostSlot];
    postSlot.iconSystemName = @"hand.raised.slash";
    postSlot.iconTileColor = [UIColor systemRedColor];

    ApolloSettingsRow *includeAuthor =
        [ApolloSettingsRow switchRowWithID:@"gestureBlock.postIncludesAuthor"
                                     title:@"Also Block Author"
                                      isOn:^BOOL {
            return [[NSUserDefaults standardUserDefaults] boolForKey:UDKeyGestureBlockPostIncludesAuthor];
        }
                                  onToggle:^(UISwitch *sender) {
            [[NSUserDefaults standardUserDefaults] setBool:sender.isOn
                                                    forKey:UDKeyGestureBlockPostIncludesAuthor];
        }];
    // Only meaningful once the post slot is actually claimed.
    includeAuthor.visible = ^BOOL { return ApolloGestureBlockPostSlot() != ApolloGestureSlotNone; };

    ApolloSettingsRow *commentSlot = [self slotRowWithID:@"gestureBlock.commentSlot"
                                                   title:@"Swipe Slot"
                                              defaultKey:UDKeyGestureBlockCommentSlot];
    commentSlot.iconSystemName = @"person.crop.circle.badge.xmark";
    commentSlot.iconTileColor = [UIColor systemRedColor];

    ApolloSettingsRow *confirm =
        [ApolloSettingsRow switchRowWithID:@"gestureBlock.confirm"
                                     title:@"Confirm Before Blocking"
                                      isOn:^BOOL {
            return [[NSUserDefaults standardUserDefaults] boolForKey:UDKeyGestureBlockConfirm];
        }
                                  onToggle:^(UISwitch *sender) {
            [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:UDKeyGestureBlockConfirm];
        }];

    return @[
        [ApolloSettingsSection
            sectionWithTitle:@"Posts"
                      footer:@"Blocks the post's subreddit, and its author when Also Block Author is on."
                        rows:@[ postSlot, includeAuthor ]],
        [ApolloSettingsSection
            sectionWithTitle:@"Comments"
                      footer:@"Blocks the account that wrote the comment."
                        rows:@[ commentSlot ]],
        [ApolloSettingsSection
            sectionWithTitle:@"Options"
                      footer:@"Assign the same slot to any action in Settings → Gestures first — "
                              "an unassigned swipe never triggers, so there is nothing to take over. "
                              "Reborn then replaces that action with the block. "
                              "Blocked subreddits and accounts are managed in Settings → Filters & Blocks."
                        rows:@[ confirm ]],
    ];
}

@end
