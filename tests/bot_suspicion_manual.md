# Bot Suspicion validation

Enable in **Settings → Apollo Reborn → Bot Suspicion** (off by default).
This heuristic labels authors, not the content of an individual post/comment.
It does not block, report, hide, or send scores anywhere.

Default score: age under 365 days adds 25; combined post/comment karma at
least 10,000 adds 35; lifetime net karma divided by age (minimum one day)
at least 100/day adds 40. Cap the sum at 100; show a label at 60 or above.
Weights of zero disable a rule. These are configurable rules, not calibrated
probabilities. The playground uses the same C scoring function as live labels.

Portable scoring checks (no iOS SDK required):

```sh
cc -std=c11 -Wall -Wextra -Werror -Isrc src/ApolloBotScore.c tests/bot_score_tests.c -lm -o /tmp/bot_score_tests
/tmp/bot_score_tests
```

Simulator/device checks still required before shipping:

1. Open `scripts/run-in-sim.sh --drive` on a Mac, or build a test IPA. Confirm
   the `[BotSuspicion] post/comment badge hooks installed` log. The previously
   downloaded IPA does not contain these source changes.
2. With the master switch off, scroll compact/large feeds, a post detail and
   a long comment thread. Confirm no labels and no new profile lookups from
   this feature. Enable with those screens already created; no restart needed.
3. For reliable label testing, set young-account points to 100, age to 36,500,
   other weights to 0 and threshold to 60. Check compact and large posts,
   self/media posts, the comments header, nested and collapsed comments,
   search/profile comment listings, long names and Dynamic Type.
   On posts the filled, bold banner must appear ABOVE the title/media, not
   inside the metadata row. Check contrasting text in light/dark and custom
   themes. Filtered/hidden posts must stay collapsed, with no stray banner.
4. Tap labels: check score breakdown and Adjust Rules navigation, including
   on iPad and presented comment panes. Native author taps, votes, swipes,
   collapse, translation, avatars and deleted-comment treatment still work.
5. Change each cutoff, weight and threshold and compare the playground.
   Disable one surface at a time, then the master; previously visible labels
   must disappear. Return to the feed, rotate, switch theme and scroll quickly;
   labels must not duplicate or stick to a different author.
6. Check invalid/empty/overflow numeric input is rejected, and Reset Rules
   preserves display switches. Relaunch and backup/restore preserve real rules;
   sample values reset. Search settings for Bot Suspicion and individual rules.
7. Test an offline load, deleted/suspended author, missing stats and stale
   avatar-only entries: no invented zero-age/high-karma flags. Complete stats
   are cached for 24 hours; old cache entries are upgraded. Exactly -1 comment
   karma remains valid. Switching off mid-fetch never installs late badges.
8. Observe profile traffic while fast-scrolling: one feature lookup at a time,
   at least two seconds between successful lookups, 60 seconds after a failure,
   15 minutes before retrying the same failed author; queued off-screen authors
   are skipped. Existing avatar/profile requests coalesce with these lookups.
   Repeated authors and warm profiles should not multiply requests.

The Windows-only check covers the real scoring engine. Logos preprocessing
does not substitute for an iOS compile, runtime check or visual verification.

## Filter Subreddit post button

- In compact feeds, large feeds and opened posts, check that the old downvote
  control shows a filter symbol and VoiceOver announces “Filter Subreddit”.
- Tap it in All Posts/Popular: verify the subreddit appears in native
  Settings → Filters & Blocks, its posts disappear after refresh, and its
  vote state/score stay unchanged. The filter has native scope: opening the
  subreddit directly still shows its posts. Remove it from Filters & Blocks.
- Check an already-filtered subreddit, fast repeated taps, an archived post,
  signed-out state, network failure and switching accounts during the request.
  A failed request must not modify the filter list; a completed request must
  update only the account that initiated it. Relaunch to verify persistence.
- With 98 or more server filters, verify new entries use Apollo's local filter
  list and can still be removed from the native settings screen.
- Switch themes and upvote an already-downvoted post: the filter symbol must
  stay a filter. Check comment downvotes, post upvotes, menu voting, configured
  swipes, rotation and reuse after fast scrolling still work independently.
