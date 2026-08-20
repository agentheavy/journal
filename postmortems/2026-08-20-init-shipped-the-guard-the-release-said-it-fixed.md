---
type: postmortem
date: 2026-08-20
failure-type: verification-skip
severity: high
---

# `agentscar init` shipped the guard the release said it had fixed (20.08)

## What happened
`6d46923` (15.08) added the dropped-remote-content check to
`templates/hook-push-guard.sh` in the agentscar repo. `0.1.2` was cut on 19.08
specifically so that an install would carry that check.

It did not. `bin/agentscar` does not read `templates/`. It writes each
template from its own heredoc, and the push-guard heredoc was never updated. So
`agentscar init` kept writing the pre-fix guard — the one that only asks whether
the remote is ahead.

Found on 20.08 by installing the published package the way a user would and
grepping the file it wrote:
`uv tool run --from agentscar==0.1.2 agentscar init` → one occurrence of `merge`
in `.agentscar/templates/hook-push-guard.sh`, and it is `merge-base --is-ancestor`.
The canonical file in the same tarball has fifteen.

Anyone who ran `agentscar init` on 0.1.2 and wired the written hook into their
push path got the ancestry check alone. The release notes said otherwise.

## Root cause (whys)
1. Why did the user get the old guard? `init` writes heredocs; `templates/` is
   a parallel copy that nothing at runtime reads.
2. Why did the heredoc drift? The fix was made in `templates/`, which is where
   the file is reviewed, tested and diffed. The heredoc is 60 lines above the
   function that writes it and looks like documentation.
3. Why did the tests pass? `tests/push-guard.sh` sets
   `GUARD="$ROOT/templates/hook-push-guard.sh"`. It exercises the canonical file,
   which was correct. 6/6 green over a stale artifact.
4. Why did the release gate pass? It grepped `templates/hook-push-guard.sh`
   inside the npm tarball — present, fifteen matches — and concluded the package
   carried the fix. It never ran `init` and looked at the output. The smoke test
   that did run was `agentscar version`.
5. Why was there no drift check? There is one, for the other embedded copy:
   smoke `t7` diffs the AGENTS.md heredoc against `adapters/agents-md/SECTION.md`.
   It was written when that heredoc drifted. The guardrail templates were never
   added to it.

## Guardrail
Test layer: smoke `t16` in the agentscar repo. After `init`, it diffs all three
written templates against their `templates/` counterparts byte-for-byte. It fails
against the pre-fix `bin/agentscar` (`93afcd3`) and passes against the fixed one
(`c0f809c`), so the check reproduces this incident rather than describing it.

The fix itself rebuilds `write_push_guard`'s heredoc from the canonical file.
Released as `0.1.3` to npm and PyPI. Verified from both install paths on a clean
machine: `npx -y agentscar@0.1.3 init` and
`uv tool run --refresh --from agentscar==0.1.3 agentscar init` each write a hook
with the merge check, and the 6-case push-guard set run against the
**init-written** file — not the canonical one — is 6/6, including "keep-ours over
bot's file is blocked".

Honest limit: `t16` proves the two copies agree; it does not remove the second
copy. The real fix is for `init` to have one source for each template, and that
is a larger change than this fix. Until then the drift check is
what stands between the reviewed file and the shipped one.

## The lesson this repeats
The 15.08 entry closes on: a guardrail is not tested until its test reproduces
the incident it closes. This is the same rule one level up. The test reproduced
the incident faithfully — against the file a maintainer reads. Nobody had asked
whether that file is the one a user gets.

Second-order note for the release checklist: a package gate verifies the output
of the tool, not the contents of the archive. "The right file is in the tarball"
and "the tool produces the right file" are different claims.

## Log entry
See log.md, 2026-08-20 · verification-skip · high.
