#pragma once
#import <Foundation/Foundation.h>
#import "ApolloBotScore.h"

@class ApolloUserProfileInfo;

__BEGIN_DECLS
extern NSString * const ApolloBotSuspicionSettingsChangedNotification;
// Called at launch and after an in-app edit, on the main thread. Display hooks
// consume these settings off the layout path and publish an atomic badge node.
void ApolloBotSuspicionLoadSettings(void);
void ApolloBotSuspicionSettingsDidChange(void);
NSDictionary<NSString *, NSNumber *> *ApolloBotSuspicionDefaults(void);
ApolloBotScore ApolloBotScoreForProfile(ApolloUserProfileInfo *info, ApolloBotRules rules);
NSString *ApolloBotScoreExplanation(ApolloBotScore score, ApolloBotRules rules, double ageDays);
BOOL ApolloBotProfileStatsAreFresh(ApolloUserProfileInfo *info);
__END_DECLS
