#include "ApolloBotScore.h"
#include <math.h>

ApolloBotRules ApolloBotDefaultRules(void) {
    return (ApolloBotRules){365.0, 10000.0, 100.0, 25, 35, 40, 60};
}

static double bounded(double value, double minimum, double maximum, double fallback) {
    return isfinite(value) ? fmax(minimum, fmin(value, maximum)) : fallback;
}

ApolloBotRules ApolloBotNormalizeRules(ApolloBotRules rules) {
    ApolloBotRules defaults = ApolloBotDefaultRules();
    rules.youngAccountDays = bounded(rules.youngAccountDays, 1, 36500, defaults.youngAccountDays);
    rules.highKarma = bounded(rules.highKarma, 1, 1000000000, defaults.highKarma);
    rules.karmaPerDay = bounded(rules.karmaPerDay, 1, 10000000, defaults.karmaPerDay);
    rules.youngAccountWeight = (int)bounded(rules.youngAccountWeight, 0, 100, defaults.youngAccountWeight);
    rules.highKarmaWeight = (int)bounded(rules.highKarmaWeight, 0, 100, defaults.highKarmaWeight);
    rules.karmaPerDayWeight = (int)bounded(rules.karmaPerDayWeight, 0, 100, defaults.karmaPerDayWeight);
    rules.flagThreshold = (int)bounded(rules.flagThreshold, 1, 100, defaults.flagThreshold);
    return rules;
}

ApolloBotScore ApolloBotEvaluate(ApolloBotRules rules, double ageDays,
                                 double postKarma, double commentKarma) {
    ApolloBotScore score = {0};
    // Missing/future timestamps and nonnumeric karma must never manufacture a
    // suspicious account. Negative karma is real data, including exactly -1.
    if (!isfinite(ageDays) || ageDays < 0 || !isfinite(postKarma) || !isfinite(commentKarma)) return score;
    double total = postKarma + commentKarma;
    if (!isfinite(total)) return score;
    rules = ApolloBotNormalizeRules(rules);
    score.known = true;
    score.totalKarma = fmax(0, total);
    // An account's first few seconds must not create an infinite rate. This is
    // lifetime average NET karma, not observed posting frequency or growth.
    score.karmaPerDay = score.totalKarma / fmax(1, ageDays);
    score.youngAccount = rules.youngAccountWeight > 0 && ageDays < rules.youngAccountDays;
    score.highKarma = rules.highKarmaWeight > 0 && score.totalKarma >= rules.highKarma;
    score.fastKarma = rules.karmaPerDayWeight > 0 && score.karmaPerDay >= rules.karmaPerDay;
    int points = (score.youngAccount ? rules.youngAccountWeight : 0)
        + (score.highKarma ? rules.highKarmaWeight : 0)
        + (score.fastKarma ? rules.karmaPerDayWeight : 0);
    score.points = points > 100 ? 100 : points;
    score.flagged = score.points >= rules.flagThreshold;
    return score;
}
