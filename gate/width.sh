#!/bin/sh
# gate/width.sh — the declared integer width law, COMPARED.
#
#   sh gate/width.sh
#
# WHAT THIS GATE EXISTS FOR. The seven fixtures under `examples/width/` carry
# 538 numbers between them, each one an answer the truncation law owes at a
# type boundary, and each fixture says in its own header that those numbers
# were computed from the width and the signedness and NEVER READ BACK from a
# backend. That is the right way to write them — a differential cannot convict
# two backends that are wrong together — but it only becomes a proof when
# something reads the line. Nothing did: a repository-wide scan for a reader of
# `examples/width` finds none, and the only readers of `# expect:` anywhere are
# `gate/gap-221-shadowstore.sh` over its own four fixtures and
# `gate/divsign.sh` over its own three. So the defect these files were written
# for — the direct backend truncating nothing, `h: u32 = 4294967295` then
# `h = h + 5` answering 4294967300 — was recorded, and then no run was ever
# asked whether it had come back.
#
# IT IS NOT A SECOND PRODUCER OF THE LAW. This gate writes no arithmetic and
# holds no expected number. Every number it compares comes out of a fixture's
# own `# expect:` line; the gate supplies only the run and the comparison.
#
# WHAT IT MAY CLAIM. Only the realization it names. `--backend=c` refuses all
# seven at `binop-not-in-c99-slice` and `--backend=direct` answers DNB004 on an
# aarch64 Linux host, so a green here is a statement about the WASM
# realization, and arms 2 and 3 say exactly that.
#
# ARM 0  THE COMPARISON'S OWN CONTROLS, run before any fixture reaches it, and
#        each one a way this gate could report PASS about a question it never
#        asked. `answers` is exercised on an agreeing and a disagreeing pair.
#        Then THE WHOLE PIPELINE — compile, run, normalise, compare — is run
#        three times against copies of a real fixture and required to REJECT
#        each: an oracle line FALSIFIED, an oracle line one cell SHORT, and an
#        oracle line PERMUTED into the wrong order but holding the identical
#        multiset of numbers. The short one is what proves the count is
#        compared and not a prefix; the permuted one is what proves the
#        newline-to-space normalisation did not become a sort. A fixture whose
#        `# expect:` line is missing entirely is a FAIL, not a skip.
#
# ARM 1  THE ACCEPTANCE RUN. Each fixture is compiled `--backend=wasm`, run
#        under wasmtime, and its stdout — one value per line — compared against
#        its own `# expect:` line, token for token and in order. A refusal, a
#        nonzero exit, or a missing wasmtime is never a pass.
#
# ARM 2  THE C99 SLICE BOUNDARY, asked rather than asserted. Every fixture uses
#        `<<`, `>>`, `&`, `|` or `~`, none of which the C99 realizer admits, so
#        each must refuse at `binop-not-in-c99-slice` while `+`, `-` and `*`
#        emit C through the same command. THIS ARM IS MEANT TO FAIL EVENTUALLY:
#        the day `emitBinop` admits the bitwise operations, these fixtures must
#        be measured there too, and this is what will say so.
#
# ARM 3  THE DIRECT REALIZATION, reported and never assumed. This is the
#        backend the fixtures were written against. If it answers DNB004 the
#        arm prints NOT MEASURED and claims nothing; if the host gains a native
#        realization the fixtures are RUN and compared there, with no edit here.

set -eu

root=${WIDTH_ROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}

if [ "${IDOL_LOCK_HELD:-0}" != 1 ]; then
    exec "$root/tools/node/dev/idol-lock" -- "$0" "$@"
fi

cd "$root" || { printf 'width gate: FAIL cannot cd to %s\n' "$root" >&2; exit 1; }

work=$(mktemp -d "${TMPDIR:-/tmp}/idol-width.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

fail() {
    printf 'width gate: FAIL %s\n' "$1" >&2
    exit 1
}

blocked() {
    printf 'width gate: NOT MEASURED — %s\n' "$1" >&2
    exit 3
}

idol=${IDOL_BIN:-"$root/zig-out/bin/idol"}
[ -x "$idol" ] || fail "compiler is not executable: $idol (run zig build)"

wasmtime=${WASMTIME_BIN:-wasmtime}
command -v "$wasmtime" >/dev/null 2>&1 ||
    blocked "no wasmtime on PATH; the only realization that answers these fixtures cannot be run"

fixtures='examples/width/tiny.id examples/width/octet.id examples/width/short.id
examples/width/half.id examples/width/word.id examples/width/long.id
examples/width/fnv.id'

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

# `wasmAnswer FILE OUT` — compile and run, echoing the run's values in order,
# one line per `print` flattened to spaces so the whole answer is one string.
# Any refusal or nonzero run status is a failure of the caller's row, never a
# skip.
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
    tr '\n' ' ' <"$work/run.out" | sed 's/  */ /g; s/^ //; s/ $//'
}

# ===================== ARM 0: THE COMPARISON'S CONTROLS =====================

answers "1 2 0 127" "1 2 0 127" || fail "arm 0: answers rejected an agreeing pair"
if answers "1 2 0 127" "1 2 0 255"; then
    fail "arm 0: answers accepted a zero-extended store — the comparison is dead"
fi

# Three false-accept controls, each through the real pipeline. They are built
# from a real fixture's own answer so that they stay correct when the fixture
# changes, and none of them names a number: keying a control to a literal
# oracle line would make a falsified REAL fixture trip here instead of in arm
# 1, which is the arm that is supposed to catch it.
seed=examples/width/tiny.id
seed_want=$(expectOf "$seed")
[ -n "$seed_want" ] || fail "arm 0: $seed carries no '# expect:' line to build controls from"

control() {
    _label=$1
    _line=$2
    _file="$work/control.id"
    [ "$_line" != "$seed_want" ] ||
        fail "arm 0: the $_label control is identical to the true oracle line and proves nothing"
    sed "s|^# expect: .*$|# expect: $_line|" "$seed" >"$_file"
    _want=$(expectOf "$_file")
    [ "$_want" = "$_line" ] || fail "arm 0: the $_label control did not take"
    _got=$(wasmAnswer "$_file" "$work/control.wasm")
    if answers "$_got" "$_want"; then
        fail "arm 0: a $_label oracle line PASSED — arm 1 proves nothing"
    fi
    printf 'width gate: arm 0 %s oracle line rejected\n' "$_label"
}

control falsified "$(printf '%s' "$seed_want" | tr '0123456789' '9876543210')"
control short "$(printf '%s' "$seed_want" | sed 's/ [^ ]*$//')"
control permuted "$(printf '%s\n' "$seed_want" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')"

# A fixture with no oracle line must not sail through as a trivially equal
# empty comparison.
sed '/^# expect: /d' "$seed" >"$work/nooracle.id"
[ -z "$(expectOf "$work/nooracle.id")" ] || fail "arm 0: the missing-oracle control did not take"
printf 'width gate: arm 0 a fixture with no oracle line reads empty and arm 1 fails it\n'

# ======================== ARM 1: THE ACCEPTANCE RUN =========================

cells=0
for fixture in $fixtures; do
    want=$(expectOf "$fixture")
    [ -n "$want" ] || fail "$fixture carries no '# expect:' line, so it proves nothing"
    got=$(wasmAnswer "$fixture" "$work/$(basename "$fixture" .id).wasm")
    answers "$got" "$want" ||
        fail "$fixture answered '$got' where its oracle line says '$want'"
    n=$(printf '%s' "$want" | wc -w | tr -d ' ')
    cells=$((cells + n))
    printf 'width gate: arm 1 %s %s cells agree\n' "$fixture" "$n"
done
printf 'width gate: arm 1 %s cells compared under wasmtime\n' "$cells"

# ======================= ARM 2: THE C99 SLICE BOUNDARY ======================

printf 'f: i64 = (p: i64)\n  h: i64 = p\n  h = h * 3 - 1 + 2\n  h\n\nmain: i64 = ()\n  print(f(3))\n  0\n' >"$work/inslice.id"
"$idol" compile --backend=c --emit=c "$work/inslice.id" -o "$work/inslice.c" >/dev/null 2>&1 ||
    fail "arm 2 control: a program using only + - * does not emit C, so a refusal below would prove nothing"
[ -s "$work/inslice.c" ] || fail "arm 2 control: --emit=c produced no C for + - *"

for fixture in $fixtures; do
    "$idol" compile --backend=c --emit=c "$fixture" -o "$work/slice.c" >"$work/slice.log" 2>&1 || true
    if [ -s "$work/slice.c" ]; then
        fail "$fixture now EMITS C. The C99 slice admits the bitwise operations: measure these fixtures there and add the arm"
    fi
    grep -q 'refused at: binop-not-in-c99-slice' "$work/slice.log" ||
        fail "$fixture did not refuse at binop-not-in-c99-slice: $(head -3 "$work/slice.log" | tr '\n' ' ')"
    rm -f "$work/slice.c"
done
printf 'width gate: arm 2 all seven refuse at binop-not-in-c99-slice, and "+ - *" emits C\n'

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
    got=$("$work/direct.bin" | tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ $//') ||
        fail "$fixture exited nonzero on --backend=direct"
    answers "$got" "$want" ||
        fail "$fixture answered '$got' on --backend=direct where its oracle line says '$want'"
    printf 'width gate: arm 3 %s agrees (direct)\n' "$fixture"
    direct_measured=1
    rm -f "$work/direct.bin"
done
[ "$direct_measured" = 1 ] ||
    printf 'width gate: arm 3 NOT MEASURED — the direct backend answers DNB004 on this host\n'

printf 'width gate: PASS (wasm realization only; see arm 2 and arm 3)\n'
