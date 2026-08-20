#!/usr/bin/env bash
# Repro set for hooks/status-timestamp-guard.sh (pre-commit).
# Each case is a scratch repo with a staged STATUS.md edit and a pinned clock.
# Run: bash .agentscar/tests/status-timestamp-guard.sh
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="${HOOK:-$HERE/../guardrails/status-timestamp-guard.sh}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0

# $1 name, $2 line appended to STATUS.md, $3 pinned now HH:MM, $4 pinned today DD.MM, $5 expected exit
case_() {
  local d="$T/$(echo "$1" | tr -cd '[:alnum:]')"
  git init -q "$d"; git -C "$d" config user.email t@e; git -C "$d" config user.name t
  printf 'seed\n' > "$d/STATUS.md"
  git -C "$d" add STATUS.md; git -C "$d" commit -qm seed
  printf '%s\n' "$2" >> "$d/STATUS.md"
  git -C "$d" add STATUS.md
  ( cd "$d" && NOW_HHMM="$3" TODAY_DDMM="$4" bash "$HOOK" >/dev/null 2>&1 ); local rc=$?
  if [ "$rc" -eq "$5" ]; then pass=$((pass+1)); echo "PASS  $1"; else fail=$((fail+1)); echo "FAIL  $1 (exit $rc, expected $5)"; fi
}

# The ledger's entries are localized; the guard matches only the header shape
# `**DD.MM (<day>, HH:MM)`, so the fixtures below carry it in English. Case 10
# pins the multibyte day abbreviation the real entries use, written as escapes
# so this file stays ASCII for the public mirror.

# 1. The 20.08 incident: entry stamped 17:10 while the clock said 16:36 -> refused.
case_ "1 future stamp refused"            '**20.08 (Thu, 17:10) FIRST ENTRY.**' "16:36" "20.08" 1
# 2. The second instance the same day: 18:00 written at 16:57 -> refused.
case_ "2 second future stamp refused"     '**20.08 (Thu, 18:00) SECOND ENTRY.**'       "16:57" "20.08" 1
# 3. Stamp equal to the clock -> allowed.
case_ "3 stamp at the clock allowed"      '**20.08 (Thu, 16:57) SECOND ENTRY.**'       "16:57" "20.08" 0
# 4. Back-recorded entry, hours behind the clock -> allowed; this is normal.
case_ "4 past stamp allowed"              '**20.08 (Thu, 11:30) BACK-RECORDED ENTRY.**'            "16:57" "20.08" 0
# 5. Entry for another day -> not our business, allowed.
case_ "5 other day allowed"               '**19.08 (Wed, 23:50) EARLIER ENTRY.**'      "16:57" "20.08" 0
# 6. Inside the grace window -> allowed (clock drift, not invention).
case_ "6 within grace allowed"            '**20.08 (Thu, 17:02) ENTRY.**'            "16:57" "20.08" 0
# 7. One minute past the grace window -> refused.
case_ "7 just past grace refused"         '**20.08 (Thu, 17:03) ENTRY.**'            "16:57" "20.08" 1
# 8. A bold line that is not a timestamped header -> ignored.
case_ "8 non-header bold line allowed"    '**House rules**'                          "16:57" "20.08" 0
# 10. Multibyte day abbreviation, as the real entries carry it -> still matched.
case_ "10 multibyte day name refused"     "**20.08 ($(printf '\xd1\x87\xd1\x82'), 19:00) ENTRY.**" "16:57" "20.08" 1

# 9. STATUS.md untouched -> the guard has nothing to read.
d="$T/notouch"; git init -q "$d"; git -C "$d" config user.email t@e; git -C "$d" config user.name t
printf 'seed\n' > "$d/STATUS.md"; git -C "$d" add STATUS.md; git -C "$d" commit -qm seed
printf 'x\n' > "$d/other.md"; git -C "$d" add other.md
( cd "$d" && NOW_HHMM="16:57" TODAY_DDMM="20.08" bash "$HOOK" >/dev/null 2>&1 ); rc=$?
if [ "$rc" -eq 0 ]; then pass=$((pass+1)); echo "PASS  9 no STATUS change allowed"; else fail=$((fail+1)); echo "FAIL  9 no STATUS change allowed (exit $rc)"; fi

echo "---"; echo "pass=$pass fail=$fail"
exit "$fail"
