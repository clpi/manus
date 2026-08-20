#!/bin/sh
# gate/architecture-companion.sh — runtime architectural companion probes.
#
#   sh gate/architecture-companion.sh
#
# Exercises behaviors that static scans cannot see. Exit 0 = all probes held.
set -eu

ROOT=${ARCHITECTURE_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}

if [ "${IDOL_LOCK_HELD:-0}" != 1 ]; then
    exec "$ROOT/tools/node/dev/idol-lock" -- "$0" "$@"
fi

IDOL=${IDOL_BIN:-"$ROOT/zig-out/bin/idol"}
WORK=$(mktemp -d "${TMPDIR:-/tmp}/idol-arch-companion.XXXXXX")
LOG=$WORK/log.txt

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT INT TERM

fail() {
    printf 'architecture-companion: FAIL %s\n' "$1" >&2
    exit 1
}

probe_ok() {
    printf 'architecture-companion: ok   %s\n' "$1"
}

[ -x "$IDOL" ] || fail "compiler not executable: $IDOL"

# AMBIGUITY-FAILS / RESOLUTION-ORDER-INDEPENDENT: two sequence homes both declare `map`.
AMBIG=$WORK/ambiguity.id
cat >"$AMBIG" <<'PROBE'
main: i64 = ()
    xs = {1, 2, 3}
    xs:map(twice)
    0

twice: any = (x: any)
    x
PROBE

if (CDPATH='' cd -- "$ROOT" && "$IDOL" check "$AMBIG") >"$LOG" 2>&1; then
    cat "$LOG" >&2
    fail 'AMBIGUITY-FAILS: xs:map(twice) admitted without disambiguating iter vs table'
fi

grep -Eiq 'ambiguous|ambig' "$LOG" \
    || fail 'AMBIGUITY-FAILS: refusal did not name ambiguity'
probe_ok 'AMBIGUITY-FAILS RESOLUTION-AMBIGUITY'

# GRAPH-ARG-EXACT: nearby binding must not break save/restore call shape.
SAVE=$ROOT/examples/bind_save_state.id
[ -f "$SAVE" ] || fail "missing probe: $SAVE"
if ! (CDPATH='' cd -- "$ROOT" && "$IDOL" check "$SAVE") >"$LOG" 2>&1; then
    cat "$LOG" >&2
    fail 'GRAPH-ARG-EXACT: bind_save_state.id check failed'
fi
probe_ok 'GRAPH-ARG-EXACT'

# FORMAT-FIXPOINT: fmt must not reintroduce retired directive faces.
CANON=$ROOT/examples/bind_concat.id
[ -f "$CANON" ] || fail "missing probe: $CANON"
FMT1=$WORK/fmt1.id
FMT2=$WORK/fmt2.id
cp "$CANON" "$FMT1"
if ! (CDPATH='' cd -- "$ROOT" && "$IDOL" fmt "$FMT1") >"$LOG" 2>&1; then
    cat "$LOG" >&2
    fail 'FORMAT-FIXPOINT: idol fmt failed on canonical probe'
fi
if grep -Eiq '\bfun\b|\bend\b|\bthen\b' "$FMT1"; then
    cat "$FMT1" >&2
    fail 'FORMAT-FIXPOINT: fmt reintroduced retired faces (fun/end/then)'
fi
cp "$FMT1" "$FMT2"
if ! (CDPATH='' cd -- "$ROOT" && "$IDOL" fmt "$FMT2") >"$LOG" 2>&1; then
    cat "$LOG" >&2
    fail 'FORMAT-FIXPOINT: second fmt pass failed'
fi
if ! cmp -s "$FMT1" "$FMT2"; then
    diff -u "$FMT1" "$FMT2" >&2 || true
    fail 'FORMAT-FIXPOINT: fmt is not idempotent on canonical probe'
fi
if ! (CDPATH='' cd -- "$ROOT" && "$IDOL" check "$FMT2") >"$LOG" 2>&1; then
    cat "$LOG" >&2
    fail 'FORMAT-FIXPOINT: formatted canonical probe failed check'
fi
probe_ok 'FORMAT-FIXPOINT'

# CHECK-NOT-DIRECT-ADMISSION: sema-only check must not be mistaken for direct reach.
DIRECT_PROBE=$ROOT/examples/call_index_assign.id
[ -f "$DIRECT_PROBE" ] || fail "missing probe: $DIRECT_PROBE"
if ! (CDPATH='' cd -- "$ROOT" && "$IDOL" check "$DIRECT_PROBE") >"$LOG" 2>&1; then
    cat "$LOG" >&2
    fail 'CHECK-NOT-DIRECT-ADMISSION: call_index_assign.id must pass idol check (sema path)'
fi
set +e
(CDPATH='' cd -- "$ROOT" && "$IDOL" run "$DIRECT_PROBE") >"$LOG" 2>&1
RUN_RC=$?
set -e
if [ "$RUN_RC" -eq 0 ]; then
    cat "$LOG" >&2
    fail 'CHECK-NOT-DIRECT-ADMISSION: call_index_assign.id must refuse direct run (not exit 0)'
fi
grep -Eiq 'DNB001|UnsupportedProgram|direct backend' "$LOG" \
    || fail 'CHECK-NOT-DIRECT-ADMISSION: direct refusal did not name DNB/direct backend'
probe_ok 'CHECK-NOT-DIRECT-ADMISSION'

# RESOLUTION-PERMUTATION — static gate requires sorted foreign_module_homes + unit test.
if ! sh "$ROOT/gate/architecture-negative.sh" >"$LOG" 2>&1; then
    cat "$LOG" >&2
    fail 'RESOLUTION-PERMUTATION: architecture-negative RESOLUTION-PERMUTATION checks failed'
fi
grep -Fq 'RESOLUTION-PERMUTATION: foreign_module_homes documents order independence' "$LOG" \
    || fail 'RESOLUTION-PERMUTATION: static order-independence check missing from negative gate'
grep -Fq 'RESOLUTION-PERMUTATION: unit test must guard non-first-wins resolution' "$LOG" \
    || fail 'RESOLUTION-PERMUTATION: unit-test guard missing from negative gate'
probe_ok 'RESOLUTION-PERMUTATION'

printf 'architecture-companion gate: PASS\n'
