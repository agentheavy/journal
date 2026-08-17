---
type: postmortem
date: 2026-08-15
failure-type: verification-skip
severity: medium
---

# The push guard passed the incident it was written for (15.08)

## What happened
The workspace has a pre-push guard, and a copy of it has been shipped as an
agentscar template since 02.08 (`cf151a2`). Both were written after a 6 July
incident: a CI job with write access regenerated a file and pushed it as a bot;
a stale local clone then pulled with a conflict, resolved it `checkout --ours`,
and pushed — a legitimate fast-forward that silently replaced the bot's file with
the old one on the remote.

On 15.08, while demonstrating the guard against a scratch remote, the same
sequence went through it: bare remote, a bot clone pushing a regenerated file, a
work clone resolving the conflict keep-ours and pushing. The guard exited 0. The
remote ended up holding the pre-bot content. Reproduced, not inferred; no real
data was involved this time.

## Root cause (whys)
1. Why did the guard pass it? It checked ancestry — "is the remote tip in my
   history?" — and after a merge it always is. The bot's commit is a parent of the
   merge; only its content is gone. `merge-base --is-ancestor` says yes, git
   accepts the push as a fast-forward, the guard agrees.
2. Why was ancestry the only check? Because the only failure the guard was ever
   exercised against was "remote ahead of local -> block" — the non-fast-forward
   case, which git rejects on its own — the guard did not need to exist for that.
3. Why was it never exercised against the real one? The guard was written from
   the postmortem's prose description of the incident, not from a reproduction of
   it. The prose said "remote outran local, pushing clobbered it"; the guard
   checked exactly that sentence and stopped.
4. Why did nothing catch that? Nothing in the flow asked that a guardrail's test
   reproduce the incident it closes. "Smoke-tested" meant "the block fires when
   the remote is ahead" — a test of the guard's mechanism, not of the incident.

The first fix attempt failed for a related reason and was reverted: comparing
HEAD against `merge-base HEAD remote/branch` finds nothing, because after the
merge that base *is* the remote tip. The check has to reach the merge's other,
local-side parent and compare content from there.

## Guardrail
Hook layer: `guardrails/git-remote-sync-guard.sh`. After the ahead check it
now walks every merge between the remote tip and HEAD. For each merge, the parent
that is an ancestor of the remote tip is the remote side, the other is local
(merges with no remote-side parent are skipped). For every file the remote side
changed relative to the two parents' merge base, the push is denied if the merged
tree kept the local blob (the remote's change was dropped) or deleted a file the
remote had populated. Same blob id, same content.

Repro set: `tests/git-remote-sync-guard.sh`, 6 cases through the hook's real
input (a tool-call JSON with the `git push` command): keep-ours over the bot's
file -> denied; the same merge taking the remote side -> allowed; a merge deleting
the remote-populated file -> denied; remote ahead with no local merge -> the
original block still fires; plain fast-forward -> allowed; a non-push command ->
silent. Run against the pre-fix guard, cases 1 and 3 — the incident and its
delete variant — fail; against the fixed one, 6/6.

The agentscar template got the same fix and its own 6-case set the same day
(`agentheavy/agentscar` `6d46923`, `templates/hook-push-guard.sh`,
`tests/push-guard.sh`).

Honest limits: a hand-resolved blend that keeps some of the remote's lines and
drops others, matching neither parent, passes. It only catches loss that goes
through a merge. It will also block a keep-ours that was intentional — by design; the
guard is a speed bump on the exact path the incident took, not a judge of intent.

The wider lesson is the one this repo already states for tests: a guardrail is
not tested until its test reproduces the incident it closes. Every other repro set
in `tests/` was rewritten to that standard on 15.08; this one was found by it.

## Log entry
See log.md, 2026-08-15 · verification-skip · medium.
