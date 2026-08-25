#!/bin/sh
# gate/realization/direct.sh — ONE producer of "can this host realize direct
# native code?", for gates to SOURCE rather than re-derive.
#
#   . "$ROOT/gate/realization/direct.sh"
#   direct_native_absent && { direct_native_note 'the digest census'; exit 1; }
#
# WHY THIS EXISTS. The direct backend emits machine code for aarch64-darwin and
# refuses every other host. Eleven gates in this home depend on that capability,
# and each one discovered its absence separately and described it in its own
# words — so the same single fact reached the reader as:
#
#   byte/face.sh          "expected the answer [{"a":1}], got exit 1"
#   occurrence/copy.sh    "§0 subject refuses"
#   divisor.sh            "idiv.id did not compile — the subject does not exist"
#   effect.sh             "EFFECT BLOCKED -- the subject did not compile"
#   cache-home.sh         "cold left compile failed"
#   defaults.sh           "positive control did not direct-compile"
#
# Not one of those sentences contains the word host. The first reads as a wrong
# answer, the third as a missing file, and every one of them sends a reader
# looking for a defect in the subject. `law.fact.producer.one`: one fact, one
# producer. This is that producer, and the gates that consult it say the same
# true thing instead of six different misleading ones.
#
# IT ASKS THE COMPILER, and does not consult `uname`. The supported-triple set
# is the compiler's to know and has changed before; a gate that hardcodes
# Darwin/arm64 goes stale silently the day an x86-64 realization lands, and
# would then skip on a host that can measure. The refusal is identified —
# DNB004, `directDiagnostic(error.UnsupportedTarget)` — so this reads an
# identity rather than matching prose.
#
# THIS FILE IS SOURCED, NEVER RUN, and says so on the next line so that the two
# enumerators over `gate/**.sh` can tell a library from a gate by reading the
# file rather than by carrying a name list each. `gate/vacuity.sh` checks that
# every file claiming this role is actually sourced by some gate, so the marker
# cannot be used as an escape hatch: a gate that declared it would have to be
# sourced by another gate to survive, which is a visible fact.
# gate-role: library

# Sets IDOL_DIRECT_NATIVE to one of:
#   yes      — the host realized a trivial program through the direct backend
#   no       — the compiler refused BY NAME (DNB004); a host limit
#   unbuilt  — no compiler to ask, which is not a host finding
#   broken   — it failed for some OTHER reason, which is a real defect and
#              must not be reported as a host limit
#
# EXIT 0 IS NOT THE ANSWER; THE ARTIFACT IS. The first version of this concluded
# `yes` from the compiler's exit status alone, and `gate/vacuity.sh` found the
# hole by planting a compiler that is `exit 0` and nothing else: a host with no
# realization at all was classified as having one, which is the direction of
# error that silently converts a HOST LIMIT into eleven law violations. The
# realization is a file, so the file is what gets checked.
direct_native_probe() {
  _idol=${1:-}
  if [ -z "$_idol" ] || [ ! -x "$_idol" ]; then
    IDOL_DIRECT_NATIVE=unbuilt
    return 0
  fi
  _probe=$(mktemp -d "${TMPDIR:-/tmp}/idol-realization.XXXXXX") || {
    IDOL_DIRECT_NATIVE=broken
    return 0
  }
  printf 'main: i64 = ()\n  0\n' > "$_probe/control.id"
  if "$_idol" compile --backend=direct -o "$_probe/control.bin" "$_probe/control.id" \
      >"$_probe/log" 2>&1; then
    if [ -s "$_probe/control.bin" ]; then
      IDOL_DIRECT_NATIVE=yes
    else
      IDOL_DIRECT_NATIVE=broken
      IDOL_DIRECT_NATIVE_WHY='the compiler reported success and produced no artifact'
    fi
  elif grep -q 'DNB004' "$_probe/log"; then
    IDOL_DIRECT_NATIVE=no
  else
    IDOL_DIRECT_NATIVE=broken
    IDOL_DIRECT_NATIVE_WHY=$(cat "$_probe/log")
  fi
  rm -rf "$_probe"
  return 0
}

# True when this host cannot realize direct native code. `unbuilt` and `broken`
# are deliberately NOT absent: an unbuilt tree and a compiler that fails for
# another reason are findings of their own, and folding them in here would let
# either one wear a host limit's excuse.
direct_native_absent() {
  [ "${IDOL_DIRECT_NATIVE:-}" = no ]
}

# The uniform sentence. Takes what could not be measured, so the reader learns
# both the limit and its cost in one line.
direct_native_note() {
  printf '%s: NOT MEASURED — %s. This host has no direct-native realization: the compiler refused a trivial program with DNB004.\n' \
    "${0##*/}" "${1:-this gate could not run}" >&2
}
