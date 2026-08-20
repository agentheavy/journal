#!/usr/bin/env bash
# status-timestamp-guard — refuse a commit that stamps a STATUS entry with a
# clock time the session has not reached yet.
# Incident: 2026-08-20 — three entries appended the same day carried times the
# assistant extrapolated instead of reading (17:10 written at 16:36, 18:00 at
# 16:57, 17:05 at 20:13). The 2026-08-15 entry on the same class shipped a
# night-session hook, which only speaks after midnight, so nothing watched the
# daytime path.
# Only FUTURE stamps are refused. A stamp hours behind the clock is normal:
# entries routinely record something that happened earlier in the day.
# Wire: cp into .git/hooks/pre-commit of the plans clone.
set -eu

GRACE_MIN="${GRACE_MIN:-5}"
now_hm="${NOW_HHMM:-$(date '+%H:%M')}"
today="${TODAY_DDMM:-$(date '+%d.%m')}"

added="$(git diff --cached -U0 -- STATUS.md | grep '^+\*\*' || true)"
[ -z "$added" ] && exit 0

now_min=$(( 10#${now_hm%%:*} * 60 + 10#${now_hm##*:} ))
bad=""

while IFS= read -r line; do
  [ -z "$line" ] && continue
  head="$(printf '%s' "$line" | grep -o '^+\*\*[0-9][0-9]\.[0-9][0-9] ([^)]*[0-9][0-9]:[0-9][0-9])' || true)"
  [ -z "$head" ] && continue
  d="$(printf '%s' "$head" | grep -o '[0-9][0-9]\.[0-9][0-9]' | head -1)"
  [ "$d" != "$today" ] && continue
  t="$(printf '%s' "$head" | grep -o '[0-9][0-9]:[0-9][0-9]' | head -1)"
  t_min=$(( 10#${t%%:*} * 60 + 10#${t##*:} ))
  if [ $(( t_min - now_min )) -gt "$GRACE_MIN" ]; then
    bad="$bad$d $t
"
  fi
done <<EOF
$added
EOF

if [ -n "$bad" ]; then
  printf 'status-timestamp-guard: STATUS entry stamped ahead of the clock (now %s)\n' "$now_hm" >&2
  printf '%s' "$bad" >&2
  printf 'read the clock instead of extrapolating it, then commit again.\n' >&2
  exit 1
fi
exit 0
