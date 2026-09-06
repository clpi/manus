#!/bin/sh
# gate/divsign.sh — the integer sign law, COMPARED.
#
#   sh gate/divsign.sh
#
# WHAT THIS GATE EXISTS FOR. `examples/table/divsign.id`,
# `examples/table/div/sign.id` and `examples/cbackend/modsign.id` each carry an
# `# expect:` line pinning Idol's floored `%` and `//`. NO HARNESS IN THIS TREE
# HAS EVER READ ONE OF THEM. A repository-wide scan for a reader of `# expect:`
# finds `gate/gap-221-shadowstore.sh`, which reads only its own four fixtures,
# and `examples/table/tailcall.id` recorded the same absence as STILL OWED when
# its own oracle line was corrected. So three files stated a numeric law, cited
# it to `docs/rulings.md` — a document `git log --all --diff-filter=A` shows was
# never added on any branch — and nothing compared the numbers to a run.
#
# IT IS NOT A SECOND PRODUCER OF THE LAW. `gate/divisor.sh` owns that: its §3
# writes its own sign matrix over operands read from the environment, §4
# requires the comptime folder to answer what the backend answered, §1 the
# zero-divisor fault. Nothing of that is restated here — this gate writes no
# arithmetic of its own and holds no expected numbers; every number it compares
# comes out of a fixture. What it adds is the comparison those fixtures never
# had, on a host where `gate/divisor.sh` measures nothing: that gate reads its
# faults from three EXECUTED direct binaries, so `direct_native_absent` exits it
# 2 before §3, §4 and §5 — none of which need a faulting binary or the direct
# backend — and this host has no direct-native realization. Lifting that is
# `gate/divisor.sh`'s own STILL OWED and is not done here.
#
# WHAT IT MAY CLAIM. Only the wasm realization. The direct backend answers
# DNB004 on an aarch64 Linux host and the C99 realizer refuses `%`, `//` and `/`
# outright, so a green here is a statement about ONE realization and arm 3 says
# which. It is not "the law holds"; it is "the law holds where it can be run,
# and the two places it cannot are the ones named".
#
# ARM 0  THE COMPARISON'S OWN CONTROL, run before any fixture reaches it.
#        `answers` is exercised on an agreeing and a disagreeing pair, and then
#        THE WHOLE PIPELINE is run against a copy of a real fixture whose
#        `# expect:` has been falsified — compile, run, compare — and required
#        to REJECT. Without that last one the arm is unfalsifiable: a gate whose
#        comparison silently always agrees reports PASS about a question it
#        never asked, which is exactly what `gate/gap-221-shadowstore.sh` was
#        written to stop happening again.
#
# ARM 1  THE ACCEPTANCE RUN. Each fixture is compiled `--backend=wasm`, run
#        under wasmtime, and its stdout compared BYTE FOR BYTE against its own
#        `# expect:` line plus a newline. A fixture with no `# expect:` line
#        fails; a refusal fails; a missing wasmtime is NOT MEASURED and exits
#        nonzero rather than passing.
#
# ARM 2  THE C99 SLICE BOUNDARY, asked rather than asserted. Each fixture must
#        refuse at `binop-not-in-c99-slice`, and a program using only `+` must
#        emit C through the same command — the control that the refusal is the
#        slice and not a broken file. THIS ARM IS MEANT TO FAIL EVENTUALLY: the
#        day `emitBinop` admits division, these three fixtures must be measured
#        there too, and this is what will say so.
#
# ARM 3  THE DIRECT REALIZATION, reported and never assumed. If it answers
#        DNB004 the arm prints NOT MEASURED and claims nothing. If the host
#        gained a native realization the fixtures are RUN and compared there,
#        with no edit here.

set -eu

root=${DIVSIGN_ROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}

if [ "${IDOL_LOCK_HELD:-0}" != 1 ]; then
    exec "$root/tools/node/dev/idol-lock" -- "$0" "$@"
fi

cd "$root" || { printf 'divsign gate: FAIL cannot cd to %s\n' "$root" >&2; exit 1; }

work=$(mktemp -d "${TMPDIR:-/tmp}/idol-divsign.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

fail() {
    printf 'divsign gate: FAIL %s\n' "$1" >&2
    exit 1
}

blocked() {
    printf 'divsign gate: NOT MEASURED %s\n' "$1" >&2
    exit 3
}

idol=${IDOL_BIN:-"$root/zig-out/bin/idol"}
[ -x "$idol" ] || fail "compiler is not executable: $idol (run zig build)"

wasmtime=${WASMTIME_BIN:-wasmtime}
command -v "$wasmtime" >/dev/null 2>&1 ||
    blocked "no wasmtime on PATH; the only realization that answers these fixtures cannot be run"

fixtures='examples/table/divsign.id examples/table/div/sign.id examples/cbackend/modsign.id'

for fixture in $fixtures; do
    [ -f "$fixture" ] || fail "$fixture is missing"
done

answers() {
    [ "$1" = "$2" ]
}

# `expectOf FILE` — the fixture's own oracle line, or empty.
expectOf() {
    sed -n 's/^# expect: *//p' "$1" | head -1
}

# `wasmAnswer FILE OUT` — compile and run, echoing stdout. Any refusal or
# nonzero run status is a failure of the caller's row, never a skip.
wasmAnswer() {
    _src=$1
    _out=$2
    if ! "$idol" compile --backend=wasm "$_src" -o "$_out" >"$work/compile.log" 2>&1; then
        fail "$_src did not compile --backend=wasm: $(head -3 "$work/compile.log" | tr '\n' ' ')"
    fi
    [ -f "$_out" ] || fail "$_src compiled without producing $_out"
    if ! "$wasmtime" "$_out" >"$work/run.out" 2>"$work/run.err"; then
        fail "$_src exited nonzero under wasmtime: $(head -2 "$work/run.err" | tr '\n' ' ')"
    fi
    cat "$work/run.out"
}

# ===================== ARM 0: THE COMPARISON'S CONTROL ======================

answers "3 -4 -4 3" "3 -4 -4 3" || fail "arm 0: answers rejected an agreeing pair"
if answers "3 -4 -4 3" "3 -3 -3 3"; then
    fail "arm 0: answers accepted the truncating quotient — the comparison is dead"
fi

# The false-accept control, through the real pipeline. A copy of the first
# fixture with its oracle line falsified must be REJECTED by the same three
# steps arm 1 uses. The replacement does not name the true answer: keying this
# control to a literal expect line would make a falsified REAL fixture trip
# here instead of in arm 1, which is the arm that is supposed to catch it.
control="$work/falsified.id"
sed 's/^# expect: .*$/# expect: not the answer/' examples/table/divsign.id >"$control"
control_want=$(expectOf "$control")
[ "$control_want" = "not the answer" ] ||
    fail "arm 0: the falsified control did not take — expect line reads '$control_want'"
control_got=$(wasmAnswer "$control" "$work/falsified.wasm")
if answers "$control_got" "$control_want"; then
    fail "arm 0: a falsified oracle line PASSED — arm 1 proves nothing"
fi
printf 'divsign gate: arm 0 the comparison rejects a falsified oracle line\n'

# ======================== ARM 1: THE ACCEPTANCE RUN =========================

for fixture in $fixtures; do
    want=$(expectOf "$fixture")
    [ -n "$want" ] || fail "$fixture carries no '# expect:' line, so it proves nothing"
    got=$(wasmAnswer "$fixture" "$work/$(basename "$fixture" .id).wasm")
    answers "$got" "$want" ||
        fail "$fixture answered '$got' where its oracle line says '$want'"
    printf 'divsign gate: arm 1 %s = %s\n' "$fixture" "$got"
done

# ======================= ARM 2: THE C99 SLICE BOUNDARY ======================

printf 'print("{7 + 2}")\n0\n' >"$work/inslice.id"
"$idol" compile --backend=c --emit=c "$work/inslice.id" -o "$work/inslice.c" >/dev/null 2>&1 ||
    fail "arm 2 control: a program using only '+' does not emit C, so a refusal below would prove nothing"
[ -s "$work/inslice.c" ] || fail "arm 2 control: --emit=c produced no C for '+'"

for fixture in $fixtures; do
    "$idol" compile --backend=c --emit=c "$fixture" -o "$work/slice.c" >"$work/slice.log" 2>&1 || true
    if [ -s "$work/slice.c" ]; then
        fail "$fixture now EMITS C. The C99 slice admits division: measure these fixtures there and add the arm"
    fi
    grep -q 'refused at: binop-not-in-c99-slice' "$work/slice.log" ||
        fail "$fixture did not refuse at binop-not-in-c99-slice: $(head -3 "$work/slice.log" | tr '\n' ' ')"
    rm -f "$work/slice.c"
done
printf 'divsign gate: arm 2 all three refuse at binop-not-in-c99-slice, and "+" emits C\n'

# ====================== ARM 3: THE DIRECT REALIZATION ======================

direct_measured=0
for fixture in $fixtures; do
    "$idol" compile --backend=direct "$fixture" -o "$work/direct.bin" >"$work/direct.log" 2>&1 || true
    if grep -q 'DNB004' "$work/direct.log"; then
        continue
    fi
    [ -x "$work/direct.bin" ] ||
        fail "$fixture --backend=direct neither answered DNB004 nor produced a binary: $(head -3 "$work/direct.log" | tr '\n' ' ')"
    want=$(expectOf "$fixture")
    got=$("$work/direct.bin") || fail "$fixture exited nonzero on --backend=direct"
    answers "$got" "$want" ||
        fail "$fixture answered '$got' on --backend=direct where its oracle line says '$want'"
    printf 'divsign gate: arm 3 %s = %s (direct)\n' "$fixture" "$got"
    direct_measured=1
    rm -f "$work/direct.bin"
done
[ "$direct_measured" = 1 ] ||
    printf 'divsign gate: arm 3 NOT MEASURED — the direct backend answers DNB004 on this host\n'

printf 'divsign gate: PASS (wasm realization only; see arm 2 and arm 3)\n'
