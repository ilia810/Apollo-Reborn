#include "ApolloBotScore.h"
#include <assert.h>
#include <float.h>
#include <math.h>
#include <stdio.h>

int main(void) {
    ApolloBotRules rules = ApolloBotDefaultRules();
    ApolloBotScore score = ApolloBotEvaluate(rules, 180, 10000, 1000);
    assert(score.known && score.flagged && score.points == 60);
    assert(score.youngAccount && score.highKarma && !score.fastKarma);

    // Age alone and high karma alone must not flag under the default rules.
    score = ApolloBotEvaluate(rules, 180, 5, 20);
    assert(!score.flagged && score.points == 25);
    score = ApolloBotEvaluate(rules, 3650, 50000, 50000);
    assert(!score.flagged && score.points == 35);
    score = ApolloBotEvaluate(rules, 90, 10000, 10000);
    assert(score.flagged && score.points == 100);

    // Strict age boundary, inclusive karma/rate/score boundaries.
    score = ApolloBotEvaluate(rules, 365, 10000, 0);
    assert(!score.youngAccount && score.highKarma && score.points == 35);
    score = ApolloBotEvaluate(rules, 364.999, 9999, 0);
    assert(score.youngAccount && !score.highKarma && score.points == 25);
    score = ApolloBotEvaluate(rules, 100, 9999, 1);
    assert(score.fastKarma && score.karmaPerDay == 100);
    score = ApolloBotEvaluate(rules, 100, 9999, 0);
    assert(!score.fastKarma);

    // The first day has a one-day denominator, including at age exactly 0.
    score = ApolloBotEvaluate(rules, 0, 5, 0);
    assert(score.known && score.karmaPerDay == 5 && !score.flagged);
    score = ApolloBotEvaluate(rules, 0.001, 5, 0);
    assert(score.karmaPerDay == 5 && !score.flagged);

    // Negative karma is data, not a missing-value sentinel. Sum first, then
    // clamp the total at zero so negative comments can offset positive posts.
    score = ApolloBotEvaluate(rules, 180, 10000, -1);
    assert(score.known && score.totalKarma == 9999 && !score.flagged);
    score = ApolloBotEvaluate(rules, 30, 20, -100);
    assert(score.known && score.totalKarma == 0 && score.karmaPerDay == 0);

    assert(!ApolloBotEvaluate(rules, -1, 100000, 100000).known);
    assert(!ApolloBotEvaluate(rules, NAN, 100000, 100000).flagged);
    assert(!ApolloBotEvaluate(rules, INFINITY, 100000, 100000).known);
    assert(!ApolloBotEvaluate(rules, 50, NAN, 100000).known);
    assert(!ApolloBotEvaluate(rules, 50, 100000, INFINITY).known);
    assert(!ApolloBotEvaluate(rules, 50, DBL_MAX, DBL_MAX).known);

    // Controls must change the actual decision, including disabling a rule.
    rules.youngAccountWeight = 0;
    score = ApolloBotEvaluate(rules, 180, 10000, 1000);
    assert(!score.youngAccount && !score.flagged && score.points == 35);
    rules.flagThreshold = 35;
    assert(ApolloBotEvaluate(rules, 180, 10000, 1000).flagged);
    rules.highKarmaWeight = 0;
    rules.karmaPerDayWeight = 0;
    assert(!ApolloBotEvaluate(rules, 1, 1000000, 1000000).flagged);

    rules = ApolloBotDefaultRules();
    rules.youngAccountDays = 90;
    rules.highKarma = 50000;
    rules.karmaPerDay = 500;
    assert(ApolloBotEvaluate(rules, 180, 10000, 1000).points == 0);
    rules.youngAccountWeight = 100;
    rules.highKarmaWeight = 100;
    rules.karmaPerDayWeight = 100;
    assert(ApolloBotEvaluate(rules, 1, 100000, 100000).points == 100);

    // Malformed/restored preferences cannot divide by zero or flag everyone
    // with a negative threshold. All weights/thresholds stay bounded.
    rules = (ApolloBotRules){NAN, -1, INFINITY, -100, 999, 0, -1};
    rules = ApolloBotNormalizeRules(rules);
    assert(rules.youngAccountDays == 365 && rules.highKarma == 1 && rules.karmaPerDay == 100);
    assert(rules.youngAccountWeight == 0 && rules.highKarmaWeight == 100 && rules.flagThreshold == 1);

    // Property checks over realistic account ages/karma. Increasing nonnegative
    // karma cannot reduce this heuristic; invalid or disabled rules stay safe.
    rules = ApolloBotDefaultRules();
    unsigned int cases = 0;
    for (int age = 0; age <= 7300; age += 17) {
        int previous = -1;
        for (int karma = 0; karma <= 1000000; karma += 997) {
            score = ApolloBotEvaluate(rules, age, karma, 0);
            assert(score.known && score.points >= previous && score.points <= 100);
            assert(score.flagged == (score.points >= rules.flagThreshold));
            previous = score.points;
            cases++;
        }
    }
    printf("bot_score_tests: all fixtures and %u monotonicity cases passed\n", cases);
    return 0;
}
