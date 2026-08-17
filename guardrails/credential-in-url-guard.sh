#!/usr/bin/env bash
# PreToolUse(Bash) guard — no credentials inside a git URL (2026-08-17).
#
# Incident: a `git push -u https://user:$(cat token-file)@github.com/...` one-liner
# pushed fine — and git then persisted that URL as the branch upstream in
# .git/config and printed it, token included, in "branch 'main' set up to track".
# `git fetch`/`pull` with such a URL also lands it in .git/FETCH_HEAD. The
# "never echo a literal token" habit covered printing; it did not cover git's own
# persistence. So the shape itself is refused: any git command whose URL carries
# `scheme://<user>:<secret>@host` is denied, however the secret is spelled
# (literal, $VAR, or $(command)).
#
# Safe form (nothing persisted, nothing printed):
#   git -c http.extraHeader="Authorization: Basic $(printf 'USER:%s' "$(tr -d ' \r\n' < FILE)" | base64 -w0)" push origin main
#
# Reads the tool-call JSON on stdin; silent-allow for anything else.
set -uo pipefail
input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)"
[ -z "$cmd" ] && exit 0

# Only git commands (git, optional global flags, subcommand).
printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]])git([[:space:]]+-[^[:space:]]+|[[:space:]]+-C[[:space:]]+[^[:space:]]+)*[[:space:]]+[a-z]' || exit 0

# scheme://<anything-with-a-colon>@host — the userinfo part carries a password/token.
# `[^@]*` on both sides of the colon lets $(...) with spaces and slashes through to the match.
if printf '%s' "$cmd" | grep -Eq '[a-z][a-z0-9+.-]*://[^@[:space:]/][^@]*:[^@]+@[A-Za-z0-9.-]+'; then
  jq -n --arg r "BLOCKED: credentials inside a git URL (user:secret@host). git persists that URL — as the branch upstream with -u, in .git/FETCH_HEAD on fetch/pull — and echoes it in 'set up to track'. Use a named remote and pass the token out of band: git -c http.extraHeader=\"Authorization: Basic \$(printf 'USER:%s' \"\$(tr -d ' \\r\\n' < TOKEN_FILE)\" | base64 -w0)\" push origin BRANCH" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
fi
exit 0
