#!/usr/bin/env bash
# Two-compiler corpus differential, done correctly.
#
# Written because a hand-rolled differential in this tree produced FOUR
# separate confident wrong answers in one session, each plausible on its
# face. Every lane runs differentials; nobody should re-derive these.
#
#   TRAP 1 — per-run timings in compiler stderr.
#     `ok compile (375 ms — ./x.out)` differs run to run. Comparing raw
#     stderr reported 279 of 943 files "changed" when nothing had.
#
#   TRAP 2 — lib/ is resolved from the BINARY, not the cwd.
#     src/main.zig:483 `detectCompilerLibRoot(..., args[0])`. Two binaries
#     from different mirrors therefore compare two different lib/ trees,
#     and diagnostics carry the mirror path. Reported 126 false diffs.
#
#   TRAP 3 — shared cwd, shared compile cache, shared output artifact.
#     Both arms write ./<name>.out into the same directory; the second arm
#     hits the first's cached artifact. Reported 28 false diffs, INCLUDING
#     apparent exit-code regressions (0 -> 1) on programs whose output was
#     byte-identical. Each arm gets its own cwd here.
#
#   TRAP 5 — `$?` after a pipe is the PIPE's status, not the command's.
#     `gate/x.sh | tail -3; echo rc=$?` reports tail's 0 and reads as a
#     pass. This hid a genuinely failing gate in this session. Read the
#     status from the direct command, or use "${PIPESTATUS[0]}" in bash
#     ("${pipestatus[1]}" in zsh — the names and indices BOTH differ, so
#     a snippet copied between the two shells is silently wrong).
#
#   TRAP 4 — a timeout emits NO diagnostic.
#     A killed run produces empty stderr, which a naive census scores as a
#     CLEAN COMPILE. The error is silent and OPTIMISTIC. Under load this
#     moved a measured refusal count from 445 to 345 with no signal at all.
#     Timeouts are recorded separately and never folded into either side.
#
# Usage: gate/differential.sh <base-idol> <cand-idol> [file-list]
set -u
BASE="${1:?base compiler}"; CAND="${2:?candidate compiler}"
SRC="$(cd "$(dirname "$0")/.." && pwd)"
TMO="${DIFFERENTIAL_TIMEOUT:-90}"
list="${3:-}"
[ -n "$list" ] || { list="$(mktemp)"; (cd "$SRC" && find examples lib scripts -name '*.id' 2>/dev/null | sort) > "$list"; }
for b in "$BASE" "$CAND"; do [ -x "$b" ] || { echo "differential: not executable: $b" >&2; exit 2; }; done
hb="$(shasum -a 256 "$BASE" | cut -c1-16)"; hc="$(shasum -a 256 "$CAND" | cut -c1-16)"
[ "$hb" != "$hc" ] || { echo "differential: BOTH ARMS ARE THE SAME BINARY ($hb) — a patched build that never finished linking reports 0 differences and looks like success" >&2; exit 2; }
echo "base $hb   cand $hc"
A="$(mktemp -d)"; B="$(mktemp -d)"; trap 'rm -rf "$A" "$B"' EXIT
norm() { sed -E -e 's/\([0-9]+ ms/(MS/' -e 's#/Volumes/[^ ]*/tmp-[a-z0-9]+/#TREE/#g' \
                -e 's#^.*\(cached\)$#COMPILED#' -e 's#^  ok compile.*#COMPILED#'; }
chg=0; same=0; tmo=0
while IFS= read -r f; do
  ao=$(cd "$A" && timeout "$TMO" "$BASE" run "$SRC/$f" 2>/dev/null </dev/null); arc=$?
  bo=$(cd "$B" && timeout "$TMO" "$CAND" run "$SRC/$f" 2>/dev/null </dev/null); brc=$?
  if [ "$arc" -eq 124 ] || [ "$brc" -eq 124 ]; then tmo=$((tmo+1)); continue; fi
  ae=$(cd "$A" && timeout "$TMO" "$BASE" run "$SRC/$f" 2>&1 >/dev/null </dev/null | norm)
  be=$(cd "$B" && timeout "$TMO" "$CAND" run "$SRC/$f" 2>&1 >/dev/null </dev/null | norm)
  if [ "$arc" = "$brc" ] && [ "$ao" = "$bo" ] && [ "$ae" = "$be" ]; then same=$((same+1))
  else chg=$((chg+1)); printf '%s rc:%s->%s\n' "$f" "$arc" "$brc"; fi
done < "$list"
# DENOMINATOR WITH POWER. "Zero regressions" over files that already fail
# to compile is vacuous, and was accepted as evidence in this repo once.
ran=$(( chg + same ))
echo "compared $ran   CHANGED $chg   IDENTICAL $same   TIMEOUT $tmo (excluded)"
exit 0
