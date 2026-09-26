#import "ApolloBotSuspicion.h"
#import "ApolloState.h"
#import "ApolloUserProfileCache.h"
#import "UserDefaultConstants.h"
#include <math.h>

NSString * const ApolloBotSuspicionSettingsChangedNotification = @"ApolloBotSuspicionSettingsChanged";

NSDictionary<NSString *, NSNumber *> *ApolloBotSuspicionDefaults(void) {
    ApolloBotRules rules = ApolloBotDefaultRules();
    return @{
        UDKeyBotSuspicionEnabled: @NO,
        UDKeyBotSuspicionPosts: @YES,
        UDKeyBotSuspicionComments: @YES,
        UDKeyBotSuspicionAgeDays: @(rules.youngAccountDays),
        UDKeyBotSuspicionKarma: @(rules.highKarma),
        UDKeyBotSuspicionKarmaPerDay: @(rules.karmaPerDay),
        UDKeyBotSuspicionAgeWeight: @(rules.youngAccountWeight),
        UDKeyBotSuspicionKarmaWeight: @(rules.highKarmaWeight),
        UDKeyBotSuspicionRateWeight: @(rules.karmaPerDayWeight),
        UDKeyBotSuspicionThreshold: @(rules.flagThreshold),
    };
}

void ApolloBotSuspicionLoadSettings(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    sBotSuspicionEnabled = [defaults boolForKey:UDKeyBotSuspicionEnabled];
    sBotSuspicionPosts = [defaults boolForKey:UDKeyBotSuspicionPosts];
    sBotSuspicionComments = [defaults boolForKey:UDKeyBotSuspicionComments];
    ApolloBotRules rules = {
        [defaults doubleForKey:UDKeyBotSuspicionAgeDays],
        [defaults doubleForKey:UDKeyBotSuspicionKarma],
        [defaults doubleForKey:UDKeyBotSuspicionKarmaPerDay],
        (int)MIN(100, MAX(0, [defaults integerForKey:UDKeyBotSuspicionAgeWeight])),
        (int)MIN(100, MAX(0, [defaults integerForKey:UDKeyBotSuspicionKarmaWeight])),
        (int)MIN(100, MAX(0, [defaults integerForKey:UDKeyBotSuspicionRateWeight])),
        (int)MIN(100, MAX(1, [defaults integerForKey:UDKeyBotSuspicionThreshold])),
    };
    sBotSuspicionRules = ApolloBotNormalizeRules(rules);
}

void ApolloBotSuspicionSettingsDidChange(void) {
    ApolloBotSuspicionLoadSettings();
    [NSNotificationCenter.defaultCenter postNotificationName:ApolloBotSuspicionSettingsChangedNotification object:nil];
}

BOOL ApolloBotProfileStatsAreFresh(ApolloUserProfileInfo *info) {
    NSTimeInterval age = -[info.fetchedAt timeIntervalSinceNow];
    return info && info.accountStatsKnown && !info.isSuspended && info.fetchedAt
        && isfinite(age) && age >= 0 && age < 24 * 60 * 60;
}

ApolloBotScore ApolloBotScoreForProfile(ApolloUserProfileInfo *info, ApolloBotRules rules) {
    if (!ApolloBotProfileStatsAreFresh(info) || !isfinite(info.createdUTC) || info.createdUTC <= 0) {
        return (ApolloBotScore){0};
    }
    double ageDays = (NSDate.date.timeIntervalSince1970 - info.createdUTC) / 86400.0;
    return ApolloBotEvaluate(rules, ageDays, (double)info.linkKarma, (double)info.commentKarma);
}

NSString *ApolloBotScoreExplanation(ApolloBotScore score, ApolloBotRules rules, double ageDays) {
    if (!score.known) return @"Account statistics are unavailable. No label is applied.";
    return [NSString stringWithFormat:
        @"%@ · %d/100 points (label at %d)\n\n"
         "Age: %.1f days\nPost + comment karma: %.0f\nLifetime average: %.1f karma/day\n\n"
         "Age under %.0f days: +%d\nKarma at least %.0f: +%d\nKarma/day at least %.0f: +%d\n\n"
         "Matching rules add points, capped at 100. A weight of 0 disables a rule. "
         "These signals can also describe active human accounts; the score is not a probability or proof of automation.",
        score.flagged ? @"Possible bot" : @"Below threshold", score.points, rules.flagThreshold,
        ageDays, score.totalKarma, score.karmaPerDay,
        rules.youngAccountDays, score.youngAccount ? rules.youngAccountWeight : 0,
        rules.highKarma, score.highKarma ? rules.highKarmaWeight : 0,
        rules.karmaPerDay, score.fastKarma ? rules.karmaPerDayWeight : 0];
}
