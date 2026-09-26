#pragma once

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// A transparent heuristic, NOT a probability or a trained bot classifier.
// Each matching rule adds its weight; the displayed score is capped at 100.
typedef struct {
    double youngAccountDays;
    double highKarma;
    double karmaPerDay;
    int youngAccountWeight;
    int highKarmaWeight;
    int karmaPerDayWeight;
    int flagThreshold;
} ApolloBotRules;

typedef struct {
    bool known;
    bool youngAccount;
    bool highKarma;
    bool fastKarma;
    bool flagged;
    int points;
    double totalKarma;
    double karmaPerDay;
} ApolloBotScore;

ApolloBotRules ApolloBotDefaultRules(void);
ApolloBotRules ApolloBotNormalizeRules(ApolloBotRules rules);
ApolloBotScore ApolloBotEvaluate(ApolloBotRules rules, double ageDays,
                                 double postKarma, double commentKarma);

#ifdef __cplusplus
}
#endif
