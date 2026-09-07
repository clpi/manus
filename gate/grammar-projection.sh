#!/bin/sh
# gate/grammar-projection.sh — the grammar-role counterfactual.
#
# GAP-134 / law.grammar.one: lib/compiler/token.id is the ONE executable
# grammar-fact owner. src/grammar_role_table.zig (host bridge, read by the
# production parser) and lib/token/grammarrole.id (Idol projection) are its
# generated outputs.
#
# A tracked generated artifact that may drift from its owner is not generated:
# damaging the owner then changes NOTHING until somebody hand-regenerates, and
# "the grammar is Idol owned" becomes a claim with no counterfactual. That is
# exactly what src/lexer_tokenize.c did in this tree (build.zig, lexer-artifact).
#
# This step regenerates privately and fails unless both artifacts are
# byte-identical. The mandatory damage control proves that a producer which
# exits zero after emitting malformed output cannot alter either tracked file.
#
# ═══ WHY THIS FILE IS NOT TWO LINES ════════════════════════════════════════
#
# It was: `emit --selftest || exit $?` then `exec emit --check`. Both halves
# reduced the whole verdict to a producer's exit status, and `gate/vacuity.sh`
# could not measure it at all — it recorded UNPROVEN, meaning the harness never
# once observed this gate DECIDE anything. Two separate defects were stacked
# under that label:
#
#   THE PLANT WAS WRONG. `build_hollow` dropped a regular file at
#   `tools/node/dev/grammar`, where the real repo has a DIRECTORY, so
#   `./tools/node/dev/grammar/emit` resolved to ENOTDIR and the gate died at
#   126 before its first check. That was the harness's defect, and it is fixed
#   in `gate/vacuity.sh`.
#
#   THE GATE WAS A PASS-THROUGH. With the plant corrected the producer becomes
#   what HOLLOW makes every producer — a program that runs, succeeds, and says
#   nothing — and two lines of `exec` report that as a clean regeneration. A
#   producer that emitted nothing is indistinguishable from a producer that
#   emitted two byte-identical projections, because both spell the answer `0`.
#
# `tools/node/dev/grammar/emit` carries real refusals of its own (`-x` on the
# compiler, `-f` on the owner and both projections, all exit 2). None of them
# can be reached THROUGH a pass-through: this file cannot tell a guard that
# ran and was satisfied from a guard that was never there. So the subjects are
# asserted here, on disk, before the producer is trusted, and the producer's
# REPORT — not merely its status — is what closes the gate.
#
# Exit 0 = both projections regenerate byte-identically and the damage control
# refused. 1 = drift or a producer refusal. 2 = the counterfactual could not be
# run: no producer, or a subject that is absent, empty, or unreported.
set -u
cd -- "$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)" || exit 2

refuse() {
  printf 'grammar-projection: FAIL — %s\n' "$*" >&2
  exit 2
}

emit=./tools/node/dev/grammar/emit
[ -x "$emit" ] || refuse "no executable producer at $emit — the counterfactual cannot have been run"

# ── the subjects, named and required to have bytes ─────────────────────────
# `-s` rather than `-f`: an empty owner regenerates to empty projections that
# compare byte-identical to empty tracked files, which is a clean PASS over
# nothing at all.
owner=lib/compiler/token.id
zigout=src/grammar_role_table.zig
idout=lib/token/grammarrole.id
for subject in "$owner" "$zigout" "$idout"; do
  [ -s "$subject" ] || refuse "subject absent or empty: $subject"
done

IDOL=${IDOL-./zig-out/bin/idol}

work=$(mktemp -d "${TMPDIR:-/tmp}/idol-grammar-gate.XXXXXX") || exit 2
trap 'rm -rf -- "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# ── the damage control must SAY it refused ─────────────────────────────────
IDOL="$IDOL" "$emit" --selftest >"$work/self.out" 2>"$work/self.err"
rc=$?
[ -s "$work/self.out" ] && cat -- "$work/self.out"
[ -s "$work/self.err" ] && cat -- "$work/self.err" >&2
[ "$rc" -eq 0 ] || exit "$rc"
grep -q '^grammar projection control: PASS' -- "$work/self.out" ||
  refuse "$emit --selftest exited 0 without reporting a control verdict — a silent control refused nothing"

# ── the regeneration must SAY what it compared ─────────────────────────────
IDOL="$IDOL" "$emit" --check >"$work/check.out" 2>"$work/check.err"
rc=$?
[ -s "$work/check.out" ] && cat -- "$work/check.out"
[ -s "$work/check.err" ] && cat -- "$work/check.err" >&2
[ "$rc" -eq 0 ] || exit "$rc"

# Each projection is named individually. A count would be satisfied by the
# same artifact asserted twice; the claim being closed is one per artifact.
for subject in "$zigout" "$idout"; do
  grep -qxF "grammar projection: $subject regenerates byte-identically" -- "$work/check.out" ||
    refuse "$emit --check exited 0 without asserting that $subject regenerates byte-identically"
done
grep -q '^grammar projection entry: PASS' -- "$work/check.out" ||
  refuse "$emit --check exited 0 without the entry-selection verdict — the owner root was never exercised"

printf 'grammar-projection: PASS — control refused a wrong dense-table producer; %s and %s regenerate byte-identically from %s\n' \
  "$zigout" "$idout" "$owner"
exit 0
