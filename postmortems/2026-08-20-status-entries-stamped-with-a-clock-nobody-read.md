---
type: postmortem
date: 2026-08-20
failure-type: wrong-assumption
severity: medium
---

# Three STATUS entries carried a clock time nobody had read (20.08)

## What happened
Three entries appended to the shared ledger on 20.08 were stamped with times the
assistant estimated rather than read:

| written | actual clock | drift |
|---|---|---|
| 17:10 | 16:36 | +34 min |
| 18:00 | 16:57 | +63 min |
| 17:05 | 20:13 | −188 min |

Each was corrected within the same session, twice because a later `date` call
happened to run and contradicted the stamp. The third mattered most: it drifted
three hours the other way, in the one record of when the work actually happened.

## Root cause (whys)
1. Why were the times wrong? They were inferred from how much work had happened
   since the last clock reading, not read from the clock.
2. Why does inference fail here? Elapsed time between two `date` calls is not
   observable from inside the session. Subagent rounds are the worst case: three
   judge rounds moved the clock by three hours and left no trace in the
   transcript that a session can count.
3. Why did nothing catch it? An earlier entry in the private log covers this
   exact class; it is not published here. Its guardrail is a SessionStart hook
   counting commits authored between midnight and 05:00; it speaks only after
   midnight or at a weekly threshold. Every daytime stamp passes through no gate
   at all.
4. Why was that guardrail scoped to nights? The earlier harm was a false claim
   about when work had happened, asserted after midnight, so the fix was built
   around that harm rather than around the class: a time asserted without being
   read.
5. Why three times in one day? Nothing in the write path requires a clock read,
   and the ledger accepts any string. The rule "read the clock" lived in a
   postmortem, which is prose one layer up from where the writing happens.

## Guardrail
Hook layer: `guardrails/status-timestamp-guard.sh`, wired as the plans
repo's `pre-commit`. It reads the staged diff of STATUS.md, extracts every added
`**DD.MM (day, HH:MM)` header dated today, and refuses the commit if the stamp
is more than five minutes ahead of the clock. Repro set
`tests/status-timestamp-guard.sh`, 10 cases; cases 1 and 2 are the two
forward-drifting entries above with their real clocks pinned. Verified against a
real commit, not only the harness: staging a 23:59 entry at 20:16 was refused.

Honest limit, and it is the larger half: the guard only catches stamps in the
future. A stamp hours behind the clock is indistinguishable from an entry that
back-records something that happened earlier in the day, which is normal and
frequent here. The third row above, 17:05 written at 20:13, still gets through.
Closing that would need the session to read the clock, which is the thing that
failed.

## The lesson this repeats
That earlier entry ends on the assistant's own claims being an output that can
be wrong and was never modelled as one. That was right, and the fix still went
to the narrow harm rather than the class. A guardrail written from the
incident's story covers the story; a guardrail written from the class covers the
next instance. Same shape as the push-guard entry in this log, one layer up
again.
