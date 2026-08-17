---
type: postmortem
date: 2026-08-17
failure-type: wrong-assumption
severity: high
---

# A token in a git URL: git kept it, and printed it (17.08)

## What happened
The journal repo's first push. The owner's Git Credential Manager wanted a
browser window the session shell could not open, so the assistant gave a
one-liner that put the brand token into the URL, read from a file:

    git push -u "https://user:$(tr -d ' \r\n' < ~/.secrets/token.txt)@github.com/org/repo.git" main

The push succeeded. Then git did two things the one-liner had not thought about:
with `-u` it stored the URL it had just pushed to as the branch upstream in
`.git/config` — token expanded — and it printed that URL, token included, in
"branch 'main' set up to track …". The token was on the terminal and in the
session transcript on disk. The upstream was repointed to `origin/main` minutes
later and `.git/config` scrubbed; the token was flagged for rotation.

## Root cause (whys)
1. Why was the token in the URL? Because it was the quickest way past a
   credential prompt with no stdin, and "read from a file, never a literal" felt
   like the whole of the secrets rule.
2. Why did that feel sufficient? The rule was written about what the assistant
   prints. It never asked what the tool receiving the token would do with it.
3. Why did nobody know git would keep it? The inline-token idiom had only been
   used with npm, PyPI and curl, where the secret goes into a header or an env
   var and nothing retains the command. Git is different: `-u` persists the
   pushed URL as upstream, and fetch/pull write the URL to `.git/FETCH_HEAD`.
   Same idiom, different tool, and the tool's own persistence was assumed to
   match the last one's.
4. Why did nothing catch it? No check looked at the shape of a git URL. The
   push guard inspects branches and merges, not credentials.

## Guardrail
Hook layer: `guardrails/credential-in-url-guard.sh`, PreToolUse on Bash.
Any git command whose URL carries `scheme://user:secret@host` is denied,
however the secret is spelled — literal, `$VAR`, or `$(…)`. The deny message
carries the safe form:

    git -c http.extraHeader="Authorization: Basic $(printf 'USER:%s' "$(tr -d ' \r\n' < FILE)" | base64 -w0)" push origin BRANCH

That form was verified read-only against the live remote: it authenticates, and
`.git/config` and `.git/FETCH_HEAD` stay clean afterwards.

Repro set: `tests/credential-in-url-guard.sh`, 7 checks. Case 1 is the incident
command verbatim with a dummy token file — denied. Also denied: a literal token
in a push URL, a clone with `user:pass@`. Allowed: the extraHeader form, a bare
https URL, `ssh://git@host` (user, no secret), and a non-git command with
`user:pass@` (out of scope). Run against the hook: 7/7.

Honest limit: the hook sees the assistant's own tool calls. A one-liner the
owner pastes into his terminal — which is exactly what happened here — never
passes through it. For that path the fix is upstream of the hook: the safe form
now lives in the note the assistant reads before touching a secret, and the
inline-URL form is named there as the thing not to write.

## Log entry
See log.md, 2026-08-17 · wrong-assumption · high.
