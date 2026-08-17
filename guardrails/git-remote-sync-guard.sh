#!/usr/bin/env bash
# PreToolUse(Bash) push guard — lesson from a clobbered CI commit (2026-07-06).
#
# CI workflows with `contents: write` (e.g. an auto-regenerate job) do
# `git commit` + `git push origin HEAD:$BRANCH` as github-actions[bot], so the
# REMOTE branch can outrun your LOCAL ref. Pushing (or force-pushing) over that
# clobbers the CI commit, and a `git checkout --ours` on a stale local merges the
# WRONG (old-version) files. Memory alone did not hold this — so it is enforced
# here: before any `git push`, fetch the target branch and BLOCK if the remote is
# ahead of local HEAD. Integrate first, then re-push.
#
# Reads the tool-call JSON on stdin; silent-allow for anything that is not a real
# `git push`, or when the remote branch is absent / not ahead.
set -uo pipefail
input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)"
[ -z "$cmd" ] && exit 0

# Precise `git push` subcommand match: git, optional global flags (-x / -C <path>),
# then `push`. Excludes "legit push", "git stash; echo push", "git pushup".
printf '%s' "$cmd" | grep -Eq '(^|[^[:alnum:]])git([[:space:]]+-[^[:space:]]+|[[:space:]]+-C[[:space:]]+[^[:space:]]+)*[[:space:]]+push([[:space:]]|$)' || exit 0

# Branch deletions cannot clobber remote work — the ahead check does not apply.
printf '%s' "$cmd" | grep -Eq '[[:space:]](--delete|-d)([[:space:]]|$)' && exit 0

deny() { # $1 = reason
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# Working dir: `git -C <path>`, else a leading `cd <path> &&`, else the hook cwd.
workdir="$(printf '%s' "$input" | jq -r '.cwd // "."' 2>/dev/null)"
if [[ "$cmd" =~ git[[:space:]]+-C[[:space:]]+([^[:space:]]+) ]]; then
  workdir="${BASH_REMATCH[1]}"
elif [[ "$cmd" =~ (^|[[:space:]\&\;])cd[[:space:]]+([^[:space:]\&\;]+) ]]; then
  workdir="${BASH_REMATCH[2]}"
fi
cd "$workdir" 2>/dev/null || exit 0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

# Resolve remote + target branch from the args after `push`.
remote="origin"
branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
rest="${cmd#*push}"
refspec=""
for t in $rest; do
  case "$t" in
    -*) continue ;;                                   # flag
    *)  if git remote 2>/dev/null | grep -qx -- "$t"; then remote="$t"; continue; fi
        refspec="$t"; break ;;                        # first non-flag, non-remote = refspec
  esac
done
if [ -n "$refspec" ]; then
  refspec="${refspec#+}"                              # drop force-refspec '+'
  case "$refspec" in :*) exit 0 ;; esac               # ':branch' = deletion — nothing to clobber
  if [[ "$refspec" == *:* ]]; then branch="${refspec#*:}"; else branch="$refspec"; fi
fi
branch="${branch#refs/heads/}"
[ -z "$branch" ] && exit 0                            # detached / undeterminable -> allow

# Fetch the target branch; a brand-new branch (absent on remote) can't be behind.
git fetch "$remote" "$branch" >/dev/null 2>&1 || exit 0
git rev-parse --verify --quiet "${remote}/${branch}" >/dev/null 2>&1 || exit 0
ahead="$(git rev-list --count "HEAD..${remote}/${branch}" 2>/dev/null || echo 0)"
if [ "${ahead:-0}" -gt 0 ]; then
  newest="$(git log -1 --format='%h %an: %s' "${remote}/${branch}" 2>/dev/null)"
  deny "PUSH BLOCKED: ${remote}/${branch} is ${ahead} commit(s) AHEAD of your local HEAD — a CI workflow (bot commit) or someone else pushed to it, and this push would be non-fast-forward or clobber remote work. Integrate first: 'git fetch ${remote} && git reset --hard ${remote}/${branch}' if you have no unique local work, else merge/rebase, then re-push. Newest remote commit: ${newest}"
fi

# Ahead == 0 only proves the remote tip is in local history, not that its content
# survived: a conflicted pull resolved `checkout --ours` keeps the bot commit as an
# ancestor while its file content is gone, and the push is a clean fast-forward
# (found 2026-08-15 — the check above missed the very incident it was written for).
# So walk every merge between the remote tip and HEAD; for each, the remote-side
# parent is the one that is an ancestor of the remote tip, the other is local. For
# every file the remote side changed vs the parents' merge base, block if the merged
# tree kept the local blob (remote change dropped) or deleted a file the remote had.
remote_ref="$(git rev-parse "${remote}/${branch}" 2>/dev/null)" || exit 0
while IFS= read -r merge; do
  [ -n "$merge" ] || continue
  remote_parent=""; local_parent=""
  for p in $(git log -1 --format=%P "$merge"); do
    if git merge-base --is-ancestor "$p" "$remote_ref"; then remote_parent="$p"; else local_parent="$p"; fi
  done
  [ -n "$remote_parent" ] && [ -n "$local_parent" ] || continue
  base="$(git merge-base "$local_parent" "$remote_parent" 2>/dev/null)" || continue
  while IFS= read -r -d '' path; do
    rmt="$(git rev-parse -q --verify "$remote_parent:$path" 2>/dev/null || true)"
    [ -n "$rmt" ] || continue                          # remote deleted it — not a content loss
    res="$(git rev-parse -q --verify "$merge:$path" 2>/dev/null || true)"
    loc="$(git rev-parse -q --verify "$local_parent:$path" 2>/dev/null || true)"
    if [ -z "$res" ]; then
      deny "PUSH BLOCKED: merge ${merge:0:9} deletes '${path}', which ${remote}/${branch} had populated — remote work would be dropped. Re-resolve keeping the remote side, then re-push."
    fi
    if [ "$res" = "$loc" ] && [ "$res" != "$rmt" ]; then
      deny "PUSH BLOCKED: merge ${merge:0:9} kept the local '${path}' and dropped the ${remote}/${branch} change to it (keep-ours over a remote/bot commit). Re-resolve keeping the remote side, then re-push."
    fi
  done < <(git diff --no-renames --name-only -z "$base" "$remote_parent")
done < <(git rev-list --merges "${remote_ref}..HEAD")
exit 0
