---
type: log
generated:
  by: agentscar/0.1.0
  at: 2026-08-06
status: stable
---

# agentscar log

One incident = one entry. An entry does not close without a guardrail;
a guardrail is not written without an incident. Newest first.

## 2026-08-17 · wrong-assumption · high
**What happened:** The assistant handed the owner a `git push -u "https://user:$(tr -d ' \r\n' < token-file)@github.com/…"` one-liner for the journal's first push. The push worked — and git then wrote that URL, token and all, into `.git/config` as the branch upstream, and printed it in "branch 'main' set up to track …". The token was echoed to the terminal and written into the session transcript on disk. It is a fine-grained token scoped to the brand's repos; we repointed the upstream and scrubbed the config within minutes. The transcript is a local file the harness owns; it was left in place — which is why rotating the token is the real fix. Only the owner can rotate it, and he hadn't when this was written.
**Root cause:** the inline-token idiom (`$(tr -d < file)`, never a literal) was applied to a git URL -> the rule about never echoing a literal token was about what the assistant prints, and nobody thought about what git itself keeps (`-u` stores the pushed URL as upstream) -> the idiom had only ever been used with npm/PyPI/curl, where the token is a header or an env var and nothing stores the command line -> nothing re-checks how a secret is passed when the idiom moves to a tool that stores its arguments.
**Guardrail:** guardrails/credential-in-url-guard.sh — a hook the harness runs before the agent's shell command; it can deny the command. It denies any git command whose URL carries `scheme://user:secret@host`, however the secret is spelled (literal, `$VAR`, `$(…)`). The deny message shows the safe form instead: `git -c http.extraHeader="Authorization: Basic $(printf 'USER:%s' "$(tr -d ' \r\n' < TOKEN_FILE)" | base64 -w0)" push origin BRANCH`. The token is read from a file when the line runs, so the typed line carries none of it. Git does not print or store a `-c` value — no upstream URL, no config entry. We ran it read-only against the live remote — `.git/config` and `FETCH_HEAD` stayed clean. Repro set tests/credential-in-url-guard.sh, 7 checks; case 1 is the incident command verbatim with a dummy token file. Honest limit: the hook sees the assistant's own tool calls; a one-liner the owner pastes into his terminal never passes through it — for that path the safe form now sits in the note the assistant reads before touching a secret.
**Status:** shipped · last-reviewed: 2026-08-17
**Postmortem:** [2026-08-17-token-in-git-url-persisted-by-git](postmortems/2026-08-17-token-in-git-url-persisted-by-git.md)

## 2026-08-15 · verification-skip · medium
**What happened:** The push guard let through the exact incident it was written to catch. So did the copy we ship as an agentscar template (agentscar `cf151a2`, since 2026-08-02). We reproduced it against a scratch remote (2026-08-15, nothing lost). A pull conflicted with a file the CI bot regenerates. We resolved it with `checkout --ours`, the way the agent had in July, and the push went through as a clean fast-forward: exit 0, and the bot's content gone from the remote.
**Root cause:** the guard checked ancestry ("is the remote tip in my history?"), and after a merge it always is, even when the merge threw the remote's content away -> the only test the guard ever had was "remote ahead -> block", which git rejects on its own anyway -> the guardrail was written from the postmortem's description of the incident, not from a reproduction of it, so it shipped without ever catching the thing it names -> nothing required a guardrail's test to reproduce the incident before it shipped.
**Guardrail:** guardrails/git-remote-sync-guard.sh — a hook the harness runs before the agent's shell command; it can deny the command. After the ahead check it now walks every merge between the remote tip and HEAD and looks at each merge's two parents, the remote-side one and the local-side one. It denies the push if the merged tree kept the local blob where the remote had changed the file, or deleted a file the remote had changed. Repro set tests/git-remote-sync-guard.sh, 6 cases — cases 1 and 3, the incident and its delete variant, get past the pre-fix guard. The agentscar template got the same fix and its own 6-case set the same day (agentscar `6d46923`). Honest limit: it still lets through a hand-edited resolution — one that drops some of the remote's lines and matches neither parent.
**Status:** shipped · last-reviewed: 2026-08-15
**Postmortem:** [2026-08-15-push-guard-missed-the-incident-it-was-written-for](postmortems/2026-08-15-push-guard-missed-the-incident-it-was-written-for.md)

