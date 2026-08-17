#!/usr/bin/env bash
# Repro set for guardrails/git-remote-sync-guard.sh (PreToolUse on Bash: `git push`).
# Bare remote + a "bot" clone that pushes a regenerated file + a "work" clone that
# pulls it in with a conflict. Case 1 is the 15.08 finding: the guard passed a
# keep-ours merge that dropped the bot's content. Run: bash tests/git-remote-sync-guard.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="${HOOK:-$HERE/../guardrails/git-remote-sync-guard.sh}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
g() { git -c core.autocrlf=false -c init.defaultBranch=main "$@"; }   # LF everywhere: identical text must hash identically
pass=0; fail=0
run() { printf '{"tool_input":{"command":"%s"},"cwd":"%s"}' "$1" "$2" | bash "$HOOK" 2>/dev/null; }
denied() { if printf '%s' "$2" | grep -q '"deny"' && printf '%s' "$2" | grep -q -- "$3"; then pass=$((pass+1)); echo "PASS  $1"; else fail=$((fail+1)); echo "FAIL  $1 (expected deny with '$3')"; printf '%s\n' "$2" | sed 's/^/      /'; fi; }
allowed() { if [ -z "$2" ]; then pass=$((pass+1)); echo "PASS  $1"; else fail=$((fail+1)); echo "FAIL  $1 (expected silence)"; printf '%s\n' "$2" | sed 's/^/      /'; fi; }

# Fixture: remote with base commit; bot clone; work clone.
g init -q --bare "$T/remote.git"
g clone -q "$T/remote.git" "$T/seed" 2>/dev/null; cd "$T/seed"
printf '* -text\n' > .gitattributes; printf 'v1\n' > gen.txt; printf 'a\n' > other.txt
g add -A; g commit -qm base; g push -q origin main
g clone -q "$T/remote.git" "$T/bot"; g clone -q "$T/remote.git" "$T/work"

# 1. Bot regenerates gen.txt; work edits the same line, pulls with conflict, keeps ours -> ancestry ok, content lost.
cd "$T/bot";  printf 'v2-bot\n' > gen.txt;  g commit -qam "bot: regen"; g push -q origin main
cd "$T/work"; printf 'v2-work\n' > gen.txt; g commit -qam "work: edit"
g fetch -q origin; g merge origin/main -m merge >/dev/null 2>&1 || true
g checkout --ours gen.txt 2>/dev/null; g add gen.txt; g commit -qm "merge (keep ours)"
denied  "1 keep-ours over the bot's file is denied"          "$(run 'git push origin main' "$T/work")" "kept the local 'gen.txt'"

# 2. Same shape, but the merge honestly takes the remote side -> allowed.
g reset -q --hard HEAD~1
g merge origin/main -m merge >/dev/null 2>&1 || true
g checkout --theirs gen.txt 2>/dev/null; g add gen.txt; g commit -qm "merge (keep theirs)"
allowed "2 merge keeping the remote change is allowed"       "$(run 'git push origin main' "$T/work")"

# 3. Merge that deletes a file the remote had populated -> denied.
g reset -q --hard HEAD~1
g merge origin/main -m merge >/dev/null 2>&1 || true
g rm -q --cached gen.txt 2>/dev/null; rm -f gen.txt; g commit -qm "merge (delete)"
denied  "3 merge deleting a remote-populated file is denied" "$(run 'git push origin main' "$T/work")" "deletes 'gen.txt'"

# 4. Remote strictly ahead, no local merge -> the original AHEAD block still fires.
cd "$T/bot"; printf 'b\n' >> other.txt; g commit -qam "bot: more"; g push -q origin main
cd "$T/work"; g reset -q --hard origin/main~1
denied  "4 remote ahead of local is denied"                  "$(run 'git push origin main' "$T/work")" "AHEAD"

# 5. Plain fast-forward on top of the remote tip -> allowed.
g reset -q --hard origin/main; g fetch -q; g reset -q --hard origin/main
printf 'c\n' >> other.txt; g commit -qam "work: ff"
allowed "5 plain fast-forward is allowed"                    "$(run 'git push origin main' "$T/work")"

# 6. Not a push -> the hook stays silent.
allowed "6 non-push git command is silent"                   "$(run 'git status' "$T/work")"

echo "---- $pass passed, $fail failed"
[ "$fail" -eq 0 ]
