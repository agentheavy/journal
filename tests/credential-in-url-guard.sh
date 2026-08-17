#!/usr/bin/env bash
# Repro set for guardrails/credential-in-url-guard.sh (PreToolUse on Bash: git URLs).
# Case 1 is the 17.08 incident verbatim (token file replaced by a dummy): a
# `git push -u https://user:$(cat file)@host/...` that git then persisted and echoed.
# Run: bash tests/credential-in-url-guard.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="${HOOK:-$HERE/../guardrails/credential-in-url-guard.sh}"
pass=0; fail=0
run() { printf '{"tool_input":{"command":%s},"cwd":"."}' "$(printf '%s' "$1" | jq -Rs .)" | bash "$HOOK" 2>/dev/null; }
denied() { if printf '%s' "$2" | grep -q '"deny"' && printf '%s' "$2" | grep -q -- "$3"; then pass=$((pass+1)); echo "PASS  $1"; else fail=$((fail+1)); echo "FAIL  $1 (expected deny with '$3')"; printf '%s\n' "$2" | sed 's/^/      /'; fi; }
allowed() { if [ -z "$2" ]; then pass=$((pass+1)); echo "PASS  $1"; else fail=$((fail+1)); echo "FAIL  $1 (expected silence)"; printf '%s\n' "$2" | sed 's/^/      /'; fi; }

# 1. The incident: push -u with a command-substituted token in the URL.
denied  "1 incident: push -u with \$(cat token) in the URL is denied" \
  "$(run "cd ~/journal && git push -u \"https://agentheavy:\$(tr -d ' \\r\\n' < ~/.secrets/x.txt)@github.com/agentheavy/journal.git\" main")" "credentials inside a git URL"

# 2. A literal token in the URL, no -u — git would still write it to FETCH_HEAD on the next pull.
denied  "2 literal user:token@ in a push URL is denied" \
  "$(run 'git push https://agentheavy:ghp_0000000000000000000000000000000000000000@github.com/agentheavy/x.git main')" "credentials inside a git URL"

# 3. clone/fetch with credentials — same persistence, same verdict.
denied  "3 clone with user:pass@ is denied" \
  "$(run 'git clone https://u:p@github.com/o/r.git')" "credentials inside a git URL"

# 4. The safe form: named remote, token out of band via extraHeader.
allowed "4 push origin with -c http.extraHeader is allowed" \
  "$(run "git -c http.extraHeader=\"Authorization: Basic \$(printf 'agentheavy:%s' \"\$(tr -d ' \\r\\n' < ~/.secrets/x.txt)\" | base64 -w0)\" push origin main")"

# 5. Plain URL without userinfo, and a user-only URL (no secret) — allowed.
allowed "5 push to a bare https URL is allowed" \
  "$(run 'git push https://github.com/agentheavy/x.git main')"
allowed "5b user@ without a secret (ssh-style) is allowed" \
  "$(run 'git push ssh://git@github.com/agentheavy/x.git main')"

# 6. Not a git command — out of scope, silent even with user:pass@.
allowed "6 non-git command with user:pass@ is silent" \
  "$(run 'curl -s https://u:p@example.com/health')"

echo "---- $pass passed, $fail failed"; [ "$fail" -eq 0 ]
