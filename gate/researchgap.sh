#!/bin/sh
# gate/researchgap.sh — research GAP admission census.
#
#   sh gate/researchgap.sh
#
# Delegates the measurement to tools/node/dev/gapc0. Every GAP that DECLARES
# `**Kind:** research_gap`, plus gaps/RESEARCH-SPINE.md, must carry the
# complete zero-delta C0 alignment block. Every GAP-*.md numbered >= 170 --
# whatever its kind -- must pass the role checks of law.md 111-115: no
# parameter-position receiver binding, no annotation-position open type or void
# descriptor. Canonical relation faces (xs:any(p), `:any`) pass; canonicality
# belongs to the role, not the word. The former
# docs/research-gap-admission.md row-count pin was a shadow of the schema; this
# gate checks the real GAPs instead of a copy of the law, so it fails when a
# GAP drifts, not when a table loses a row.
#
# THE SUBJECT IS THE DECLARED KIND. Selecting `>= 175` was a proxy that held on
# the day it was written and stopped holding at GAP-203, when the same number
# line started carrying defect reports. Measured at 64928599 the proxy produced
# 18 violations, ALL of them `wrong_answer` / `crash` / `regression` /
# `evidence_gap` / architecture GAPs convicted of missing a research admission
# block they were never required to carry -- while the real research GAPs were
# all compliant. Worse, a GAP with no block `return`ed before the role checks,
# so a whole class of GAPs was exempt from law.md 111-115 entirely.
#
# ═══ WHY THIS FILE IS NOT ONE LINE ═════════════════════════════════════════
#
# It was. It was `exec tools/node/dev/gapc0`, which made the delegate's exit
# status the entire verdict, and `gate/vacuity.sh` convicted it:
#
#   real tree      `gapc0: N GAPs in range, M research GAPs C0-checked,
#                   0 violations`                                      rc=0
#   silent gapc0   (no output whatsoever)                              rc=0
#
# One census examined every GAP in the tree; the other examined none. Nothing
# this gate printed or returned could tell a reader which had happened.
#
# `tools/node/dev/gapc0` DOES carry the floor -- `checked -gt 0` and
# `research -gt 0`, both exit 2. That guard was UNREACHABLE FROM HERE, and not
# because of anything wrong with it: a pass-through cannot distinguish a guard
# that ran and was satisfied from a guard that never existed. A gapc0 that is
# deleted, unexecutable, truncated to `exit 0`, or replaced by a stub during a
# refactor is spelled `0` in the only channel this gate was reading.
#
# So a DELEGATE IS NOT A SUBJECT and its silence is not agreement. This file
# now owns three things the delegate cannot own for it:
#
#   1. a subject floor over gaps/, counted here, on disk, before delegating;
#   2. the requirement that the census actually REPORT what it swept;
#   3. a cross-check that the reported population is not smaller than the one
#      visible from here -- a delegate that swept a subset is not a sweep.
#
# Exit 0 = clean. 1..N = the violation count gapc0 returned. 2 = the census
# could not be trusted: no delegate, no subject, or no report.
set -u
cd "$(dirname "$0")/.." || exit 2

refuse() {
  printf 'researchgap: FAIL — %s\n' "$*" >&2
  exit 2
}

census=tools/node/dev/gapc0
[ -x "$census" ] || refuse "no executable census at $census — the measurement cannot have happened"

# ── the subject floor, asserted here rather than borrowed ──────────────────
# `gaps/` must hold the population the census claims to sweep. An absent or
# empty gaps home is exactly the shape that reads as a clean zero.
[ -d gaps ] || refuse 'no gaps/ directory — the census has no population'
[ -f gaps/RESEARCH-SPINE.md ] ||
  refuse 'gaps/RESEARCH-SPINE.md absent — the schema home is itself part of the census'

inrange=0
for f in gaps/GAP-*.md; do
  [ -f "$f" ] || continue
  n=$(printf '%s' "${f##*/}" | sed -n 's/^GAP-0*\([0-9][0-9]*\)\.md$/\1/p')
  [ -n "$n" ] || continue
  [ "$n" -ge 170 ] || continue
  inrange=$((inrange + 1))
done
[ "$inrange" -gt 0 ] ||
  refuse 'zero GAP-*.md at or above 170 — the census selects an empty set (GAP-201)'

out=$(mktemp "${TMPDIR:-/tmp}/idol-researchgap.XXXXXX") || exit 2
err=$(mktemp "${TMPDIR:-/tmp}/idol-researchgap.XXXXXX") || exit 2
trap 'rm -f -- "$out" "$err"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

"$census" >"$out" 2>"$err"
rc=$?
[ -s "$out" ] && cat -- "$out"
[ -s "$err" ] && cat -- "$err" >&2

# ── the report is the evidence ─────────────────────────────────────────────
# A zero exit is what a stub says too. The census line is the only thing that
# carries what was swept, so its ABSENCE under a zero exit is a refusal.
report=$(grep -E '^gapc0: [0-9]+ GAPs in range, [0-9]+ research GAPs C0-checked, [0-9]+ violations$' \
  -- "$out" | tail -1)
if [ "$rc" -eq 0 ] && [ -z "$report" ]; then
  refuse "$census exited 0 without printing its census report — a silent delegate is not a clean sweep"
fi
[ "$rc" -eq 0 ] || exit "$rc"

checked=$(printf '%s' "$report" | sed -E 's/^gapc0: ([0-9]+) GAPs in range.*/\1/')
research=$(printf '%s' "$report" | sed -E 's/.*, ([0-9]+) research GAPs C0-checked.*/\1/')
violations=$(printf '%s' "$report" | sed -E 's/.*, ([0-9]+) violations$/\1/')

# EVERY FIELD OF THE REPORT IS READ, and this line is here because the first
# version of this file did not read this one. It parsed the two population
# counts, ignored the violation count, and then printed a LITERAL `0
# violations` in its own PASS. A delegate reporting `5 violations` and exiting
# 0 was therefore laundered into a clean sweep BY THE WRAPPER — this gate
# committing the exact offence it was written to stop, one field over. gapc0's
# contract is that its exit code IS the violation count, so a nonzero count
# beside a zero status is the two channels disagreeing, and a disagreement is
# never resolved in favour of the quieter one.
[ "$violations" -eq 0 ] ||
  refuse "$census reported $violations violation(s) and still exited 0 — report and status disagree"

# gapc0 counts RESEARCH-SPINE.md alongside the numbered GAPs, so its `checked`
# is at least the count taken here. Smaller means it swept a subset of what is
# on disk, which is the same lie as sweeping nothing, only harder to see.
[ "$checked" -ge "$inrange" ] ||
  refuse "$census reported $checked GAPs in range; $inrange are on disk at or above 170"
[ "$research" -gt 0 ] ||
  refuse "$census C0-checked 0 research GAPs — the admission census selected an empty subject"

# The counts printed here are the delegate's own, re-read from its report.
# Nothing on this line is a constant.
printf 'researchgap: PASS — %s GAPs in range (%s counted here), %s research GAPs C0-checked, %s violations\n' \
  "$checked" "$inrange" "$research" "$violations"
exit 0
