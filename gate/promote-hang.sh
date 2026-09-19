#!/bin/sh
# gate/promote-hang.sh — module-promotion split-home hang regression.
#
# A promoted module global whose DNIR slot is frame-homed (loop-stored locals
# exceeding the callee-save home budget) must resolve every read to the frame.
# load_global once installed a temps name for such a slot; the loop head then
# read the preload register while the body stored through the frame — one slot
# with two unsynchronized physical authorities, an infinite loop. The repair
# establishes the frame home and installs no name; the std.debug.asserts in
# gpLocalHomeReg and evalDnirValue fail any future producer that regresses the
# invariant at compile time instead of emitting a hang.
#
# The subjects assert termination, not speed: both must print 100. c10 is the
# 26-line minimal hang trigger (10 fillers push the promoted slot into a frame
# home); b9 is the 9-filler near-miss that stayed correct through the bug.

set -u
root=${IDOL_REPO:-$(cd "$(dirname "$0")/.." && pwd)}
idol=${IDOL_BIN:-$root/zig-out/bin/idol}
work=$(mktemp -d "${TMPDIR:-/tmp}/idol-promote-hang.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT HUP INT TERM

fail() { printf 'promote-hang: FAIL — %s\n' "$1" >&2; exit 1; }

for subj in c10 b9; do
  src=$root/gate/promote-hang-$subj.id
  [ -r "$src" ] || fail "subject absent: $src"
  if ! "$idol" compile "$src" --backend native --no-cache -o "$work/$subj.o" >"$work/$subj.compile.log" 2>&1; then
    if grep -q 'DNB004\|refus' "$work/$subj.compile.log"; then
      printf 'promote-hang: NOT MEASURED — native backend refused on this host\n'
      exit 2
    fi
    fail "compile failed for $src: $(tail -1 "$work/$subj.compile.log")"
  fi
  out=$(timeout 10 "$work/$subj.o" 2>"$work/$subj.run.err"); rc=$?
  [ $rc -eq 0 ] || fail "$subj exited rc=$rc (hang or crash)"
  [ "$out" = "100" ] || fail "$subj printed [$out], expected 100"
done
printf 'promote-hang: PASS — promoted frame-homed loop terminates with 100 (c10, b9)\n'
