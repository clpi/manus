#!/bin/sh
# gate/layout.sh — the declared layout law, COMPARED.
#
#   sh gate/layout.sh
#
# WHAT THIS GATE EXISTS FOR. The nine fixtures under `examples/layout/` carry
# the offside rule, one-liner termination, else-binding-by-column, operator
# adjacency and the paren/parameter-list split. Every header says the same
# thing in its own words: these must be CHECKED BY VALUE, because each shape
# COMPILES under the wrong reading too and answers a different number. That is
# the right way to write them — a wrong nesting is not a refusal, so nothing
# downstream can convict it — but it is only a proof once something reads the
# line. NOTHING DID. The readers of `# expect:` in this tree are
# `gate/gap-221-shadowstore.sh`, `gate/divsign.sh` and `gate/width.sh`, each
# over its own fixtures; the only reader this corpus ever had is
# `scripts/run_compile_fail_tests.id`, which is `#!/usr/bin/env duo` — a tool
# with no binary in this tree — and it named exactly one of the nine.
#
# WHAT WENT UNSEEN WHILE NOTHING RAN. `examples/layout/glued.id` is named for
# operator adjacency and spends its header explaining that `>>=` is `>>` with
# an `=` glued to it. Commit 98ceb52c — an argument-projection migration whose
# message never mentions compound assignment — expanded all four glued
# operators in it into `a = a >> 3`. THE ORACLE LINE DID NOT MOVE, because both
# spellings answer 8, so no number could see the loss. `idol fmt` performs the
# same expansion today. That is why arm 3 checks the FACE and not only the
# numbers: a corpus that proves its law only by value cannot notice the law
# leaving the file.
#
# IT IS NOT A SECOND PRODUCER OF THE LAW. This gate writes no arithmetic and
# holds no expected answer. Every number it compares comes out of a fixture's
# own `# expect:` or `# expect-exit:` line; the gate supplies the run and the
# comparison. The only constants it does hold are the refusal ids of arm 5 and
# the formatter behaviours of arm 6, which are not the law — they are the
# boundary where the law currently cannot be run, pinned so that it fails
# loudly when it moves.
#
# WHAT IT MAY CLAIM. Only the realization it names. Five of the nine fixtures
# compile; four refuse, and arm 5 says which and why. A green here is a
# statement about the WASM realization of five fixtures, not about the layout
# law as a whole.
#
# ARM 0  THE COMPARISON'S OWN CONTROLS, run before any fixture reaches it, each
#        one a way this gate could report PASS about a question it never asked.
#        `answers` is exercised on an agreeing and a disagreeing pair. Then THE
#        WHOLE PIPELINE — compile, run, normalise, compare — is run against
#        copies of a real fixture and required to REJECT each: an oracle line
#        FALSIFIED, one cell SHORT, and PERMUTED into the wrong order holding
#        the identical multiset. The short one proves the count is compared and
#        not a prefix; the permuted one proves the newline-to-space
#        normalisation did not become a sort. A fixture whose oracle line is
#        missing is a FAIL, not a skip. The EXIT oracle gets its own controls,
#        because a comparison that only asked "did it run" would pass every
#        exit value: a falsified exit line and a ZERO exit line must both be
#        rejected against a fixture that exits 11.
#
# ARM 1  THE STDOUT ACCEPTANCE RUN. Each compiling stdout fixture is built
#        `--backend=wasm`, run under wasmtime, and its output compared against
#        its own `# expect:` line, token for token and in order.
#
# ARM 2  THE EXIT ACCEPTANCE RUN. `paren.id` observes nothing on stdout — the
#        process status IS the answer — and is compared against its own
#        `# expect-exit:` line.
#
# ARM 3  THE FACE, WHICH NO NUMBER CAN SEE. `glued.id` must still contain all
#        four glued operators, and each glued binding must agree with the
#        expanded binding beside it on the same operands. This is the
#        equivalence witness the update-of-place law demands before the
#        compound form may be called canonical, and it is the lock that would
#        have caught 98ceb52c on the day it landed.
#
# ARM 4  THE FIXTURE'S OWN NEGATIVE CONTROL, RUN. `glued.id`'s header states
#        that the spaced form `a >> = 3` reports "expected expression, got
#        '='". The gate asks it instead of quoting it, against a copy — proof
#        that adjacency is load-bearing and not decoration.
#
# ARM 5  THE FOUR THAT DO NOT COMPILE, pinned rather than passed over.
#        `offside.id`, `guard.id`, `loopbody.id` and `walk.id` each refuse at a
#        named boundary; their oracle lines have never been compared and cannot
#        be today. THIS ARM IS MEANT TO FAIL EVENTUALLY: the day one of them
#        compiles, its numbers must be measured and this is what will say so.
#        `walk.id`'s refusal is the one its own header predicted.
#
# ARM 6  THE FORMATTER, MEASURED. `idol fmt` does not preserve three of the
#        faces this corpus exists to carry: it un-glues `glued.id`, rewrites
#        `refine.id`'s indented refinement into a braced pack, and reprints
#        `ternary.id`'s one-liner as `(if … end)` — reintroducing the `end`
#        that §3.4 says is accepted and deleted, never demanded, and that
#        `gate/architecture-companion.sh` fails on over its own synthetic
#        probe. None of that is repaired here; `src/pretty.zig` is another
#        owner's. It is pinned so it cannot decay further in silence, and this
#        arm fails when any of the three changes in either direction.
#
# ARM 7  THE C99 SLICE AND THE DIRECT REALIZATION, reported and never assumed.

set -eu

root=${LAYOUT_ROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}

if [ "${IDOL_LOCK_HELD:-0}" != 1 ]; then
    exec "$root/tools/node/dev/idol-lock" -- "$0" "$@"
fi

cd "$root" || { printf 'layout gate: FAIL cannot cd to %s\n' "$root" >&2; exit 1; }

work=$(mktemp -d "${TMPDIR:-/tmp}/idol-layout.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

fail() {
    printf 'layout gate: FAIL %s\n' "$1" >&2
    exit 1
}

blocked() {
    printf 'layout gate: NOT MEASURED — %s\n' "$1" >&2
    exit 2
}

idol=${IDOL_BIN:-"$root/zig-out/bin/idol"}
[ -x "$idol" ] || fail "compiler is not executable: $idol (run zig build)"

wasmtime=${WASMTIME_BIN:-wasmtime}
command -v "$wasmtime" >/dev/null 2>&1 ||
    blocked "no wasmtime on PATH; the only realization that answers these fixtures cannot be run"

# The five that compile, split by which observation carries their answer.
stdout_fixtures='examples/layout/attr.id examples/layout/glued.id
examples/layout/refine.id examples/layout/ternary.id'
exit_fixtures='examples/layout/paren.id'

# The four that refuse, each with the boundary it refuses at.
refusals='examples/layout/offside.id:global-init-not-constant:r
examples/layout/guard.id:unresolved-name:n
examples/layout/loopbody.id:unresolved-name:xs
examples/layout/walk.id:missing-application-id'

for fixture in $stdout_fixtures $exit_fixtures; do
    [ -f "$fixture" ] || fail "$fixture is missing"
done

answers() {
    [ "$1" = "$2" ]
}

# `expectOf FILE` — the fixture's own stdout oracle line, or empty.
expectOf() {
    sed -n 's/^# expect: *//p' "$1" | head -1
}

# `expectExitOf FILE` — the fixture's own exit oracle line, or empty.
expectExitOf() {
    sed -n 's/^# expect-exit: *//p' "$1" | head -1
}

# `buildWasm FILE OUT` — compile or fail the caller's row. Never a skip.
buildWasm() {
    if ! "$idol" compile --backend=wasm "$1" -o "$2" >"$work/compile.log" 2>&1; then
        fail "$1 did not compile --backend=wasm: $(head -3 "$work/compile.log" | tr '\n' ' ')"
    fi
    [ -f "$2" ] || fail "$1 compiled without producing $2"
}

# `wasmAnswer FILE OUT` — the run's stdout, newlines flattened to spaces so the
# whole answer is one string compared in order.
wasmAnswer() {
    buildWasm "$1" "$2"
    if ! "$wasmtime" "$2" >"$work/run.out" 2>"$work/run.err"; then
        fail "$1 exited nonzero under wasmtime: $(head -2 "$work/run.err" | tr '\n' ' ')"
    fi
    tr '\n' ' ' <"$work/run.out" | sed 's/  */ /g; s/^ //; s/ $//'
}

# `wasmExit FILE OUT` — the run's exit status as the observable. A zero here is
# an answer like any other, never a proxy for "it ran".
wasmExit() {
    buildWasm "$1" "$2"
    _rc=0
    "$wasmtime" "$2" >"$work/run.out" 2>"$work/run.err" || _rc=$?
    printf '%s' "$_rc"
}

# ===================== ARM 0: THE COMPARISON'S CONTROLS =====================

answers "20 3 6" "20 3 6" || fail "arm 0: answers rejected an agreeing pair"
if answers "20 3 6" "20 1 6"; then
    fail "arm 0: answers accepted an else bound to the inner if — the comparison is dead"
fi

# Whole-pipeline false-accept controls, built from a real fixture's own answer
# so they stay correct when the fixture changes. None of them names a number:
# keying a control to a literal oracle line would make a falsified REAL fixture
# trip here instead of in arm 1, which is the arm meant to catch it.
seed=examples/layout/ternary.id
seed_want=$(expectOf "$seed")
[ -n "$seed_want" ] || fail "arm 0: $seed carries no '# expect:' line to build controls from"

control() {
    _label=$1
    _line=$2
    _file="$work/control.id"
    [ "$_line" != "$seed_want" ] ||
        fail "arm 0: the $_label control is identical to the true oracle line and proves nothing"
    sed "s|^# expect: .*$|# expect: $_line|" "$seed" >"$_file"
    [ "$(expectOf "$_file")" = "$_line" ] || fail "arm 0: the $_label control did not take"
    _got=$(wasmAnswer "$_file" "$work/control.wasm")
    if answers "$_got" "$_line"; then
        fail "arm 0: a $_label oracle line PASSED — arm 1 proves nothing"
    fi
    printf 'layout gate: arm 0 %s oracle line rejected\n' "$_label"
}

control falsified "$(printf '%s' "$seed_want" | tr '0123456789' '9876543210')"
control short "$(printf '%s' "$seed_want" | sed 's/ [^ ]*$//')"
control permuted "$(printf '%s\n' "$seed_want" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')"

sed '/^# expect: /d' "$seed" >"$work/nooracle.id"
[ -z "$(expectOf "$work/nooracle.id")" ] || fail "arm 0: the missing-oracle control did not take"
printf 'layout gate: arm 0 a fixture with no oracle line reads empty and arm 1 fails it\n'

# The exit oracle needs its own controls. A comparison that asked only "did it
# run" would accept every status, so both a falsified value and a ZERO value
# must be rejected against a fixture that exits nonzero.
exit_seed=examples/layout/paren.id
exit_want=$(expectExitOf "$exit_seed")
[ -n "$exit_want" ] || fail "arm 0: $exit_seed carries no '# expect-exit:' line"
[ "$exit_want" != 0 ] ||
    fail "arm 0: $exit_seed exits 0, so the zero control below cannot discriminate"

exit_got=$(wasmExit "$exit_seed" "$work/exitseed.wasm")
for bogus in 0 "$((exit_want + 1))"; do
    if answers "$exit_got" "$bogus"; then
        fail "arm 0: the exit comparison accepted $bogus where the fixture exits $exit_got"
    fi
done
printf 'layout gate: arm 0 exit comparison rejected a zero and a falsified status\n'

# ==================== ARM 1: THE STDOUT ACCEPTANCE RUN =====================

cells=0
for fixture in $stdout_fixtures; do
    want=$(expectOf "$fixture")
    [ -n "$want" ] || fail "$fixture carries no '# expect:' line, so it proves nothing"
    got=$(wasmAnswer "$fixture" "$work/$(basename "$fixture" .id).wasm")
    answers "$got" "$want" ||
        fail "$fixture answered '$got' where its oracle line says '$want'"
    n=$(printf '%s' "$want" | wc -w | tr -d ' ')
    cells=$((cells + n))
    printf 'layout gate: arm 1 %s %s cells agree\n' "$fixture" "$n"
done
printf 'layout gate: arm 1 %s cells compared under wasmtime\n' "$cells"

# ===================== ARM 2: THE EXIT ACCEPTANCE RUN ======================

for fixture in $exit_fixtures; do
    want=$(expectExitOf "$fixture")
    [ -n "$want" ] || fail "$fixture carries no '# expect-exit:' line, so it proves nothing"
    got=$(wasmExit "$fixture" "$work/$(basename "$fixture" .id).wasm")
    answers "$got" "$want" ||
        fail "$fixture exited $got where its oracle line says $want"
    printf 'layout gate: arm 2 %s exits %s as its oracle line says\n' "$fixture" "$got"
done

# ================= ARM 3: THE FACE, WHICH NO NUMBER CAN SEE ================

glued=examples/layout/glued.id
for op in '>>=' '<<=' '|=' '&='; do
    grep -q "^[a-z][a-z]* $op " "$glued" ||
        fail "arm 3: $glued no longer contains a \`$op\` binding. The adjacency law left the file that carries it, and the oracle line cannot see the difference — this is what 98ceb52c did in silence"
done
printf 'layout gate: arm 3 all four glued operators are still in %s\n' "$glued"

# The glued arm and the expanded arm answer over identical operands, so the
# oracle line proves them equivalent only if it is read in halves.
glued_want=$(expectOf "$glued")
glued_left=$(printf '%s' "$glued_want" | tr ' ' '\n' | sed -n '1,4p' | tr '\n' ' ' | sed 's/ $//')
glued_right=$(printf '%s' "$glued_want" | tr ' ' '\n' | sed -n '6,9p' | tr '\n' ' ' | sed 's/ $//')
answers "$glued_left" "$glued_right" ||
    fail "arm 3: the glued arm answers '$glued_left' and the expanded arm '$glued_right'; the update-of-place witness does not hold"
printf 'layout gate: arm 3 glued and expanded arms agree cell for cell (%s)\n' "$glued_left"

# ============== ARM 4: THE FIXTURE'S OWN NEGATIVE CONTROL, RUN =============

sed 's/^a >>= 3$/a >> = 3/' "$glued" >"$work/spaced.id"
grep -q '^a >> = 3$' "$work/spaced.id" || fail "arm 4: the spaced control did not take"
if "$idol" compile --backend=wasm "$work/spaced.id" -o "$work/spaced.wasm" >"$work/spaced.log" 2>&1; then
    fail "arm 4: the SPACED form \`a >> = 3\` compiled. Adjacency is not load-bearing and $glued proves nothing"
fi
grep -q "expected expression" "$work/spaced.log" ||
    fail "arm 4: the spaced form refused, but not at 'expected expression': $(head -3 "$work/spaced.log" | tr '\n' ' ')"
printf 'layout gate: arm 4 the spaced form refuses at "expected expression"\n'

# ================= ARM 5: THE FOUR THAT DO NOT COMPILE =====================

for row in $refusals; do
    rfile=${row%%:*}
    rhint=${row#*:}
    [ -f "$rfile" ] || fail "arm 5: $rfile is missing"
    [ -n "$(expectOf "$rfile")" ] ||
        fail "arm 5: $rfile carries no oracle line, so nothing is owed by it"
    if "$idol" compile --backend=wasm "$rfile" -o "$work/owed.wasm" >"$work/owed.log" 2>&1; then
        fail "arm 5: $rfile NOW COMPILES. Its oracle line has never been compared — measure it in arm 1 and drop this row"
    fi
    grep -q "refused at: $rhint" "$work/owed.log" ||
        fail "arm 5: $rfile no longer refuses at '$rhint': $(grep -o 'refused at: .*' "$work/owed.log" | head -1)"
    printf 'layout gate: arm 5 %s STILL OWED — refused at %s\n' "$rfile" "$rhint"
done

# ======================= ARM 6: THE FORMATTER, MEASURED ====================

fmtOf() {
    cp "$1" "$work/fmt.id"
    "$idol" fmt "$work/fmt.id" >"$work/fmt.log" 2>&1 ||
        fail "arm 6: idol fmt failed on $1: $(head -2 "$work/fmt.log" | tr '\n' ' ')"
}

fmtOf "$glued"
if grep -q '^a >>= 3$' "$work/fmt.id"; then
    fail "arm 6: idol fmt now PRESERVES the glued face. The expansion this corpus decayed through is fixed — say so in $glued and delete this row"
fi
printf 'layout gate: arm 6 OWED idol fmt still un-glues %s (src/pretty.zig, another owner)\n' "$glued"

fmtOf examples/layout/refine.id
if grep -q '^p: { x: i8, y: i64 } =$' "$work/fmt.id"; then
    fail "arm 6: idol fmt now PRESERVES the indented refinement face — delete this row"
fi
printf 'layout gate: arm 6 OWED idol fmt still braces the refinement in examples/layout/refine.id\n'

fmtOf examples/layout/ternary.id
grep -q 'end)' "$work/fmt.id" ||
    fail "arm 6: idol fmt no longer reintroduces \`end\` on ternary.id — delete this row"
printf 'layout gate: arm 6 OWED idol fmt still reprints the one-liner with the retired `end`\n'

# ============ ARM 7: THE C99 SLICE AND THE DIRECT REALIZATION ==============

printf 'f: i64 = (p: i64)\n  h: i64 = p\n  h = h + 1\n  h\n\nmain: i64 = ()\n  print(f(3))\n  0\n' >"$work/inslice.id"
"$idol" compile --backend=c --emit=c "$work/inslice.id" -o "$work/inslice.c" >/dev/null 2>&1 ||
    fail "arm 7 control: a program using only + does not emit C, so a refusal below would prove nothing"
[ -s "$work/inslice.c" ] || fail "arm 7 control: --emit=c produced no C"

c_emitted=0
for fixture in $stdout_fixtures $exit_fixtures; do
    "$idol" compile --backend=c --emit=c "$fixture" -o "$work/slice.c" >"$work/slice.log" 2>&1 || true
    if [ -s "$work/slice.c" ]; then
        c_emitted=$((c_emitted + 1))
        rm -f "$work/slice.c"
        continue
    fi
    printf 'layout gate: arm 7 %s refuses the C99 slice at %s\n' \
        "$fixture" "$(grep -o 'refused at: [a-z0-9-]*' "$work/slice.log" | head -1)"
done
printf 'layout gate: arm 7 %s of the five emit C99 source\n' "$c_emitted"

direct_measured=0
for fixture in $stdout_fixtures; do
    "$idol" compile --backend=direct "$fixture" -o "$work/direct.bin" >"$work/direct.log" 2>&1 || true
    if grep -q 'DNB004' "$work/direct.log"; then continue; fi
    [ -x "$work/direct.bin" ] ||
        fail "$fixture --backend=direct neither answered DNB004 nor produced a binary: $(head -3 "$work/direct.log" | tr '\n' ' ')"
    want=$(expectOf "$fixture")
    got=$("$work/direct.bin" | tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ $//') ||
        fail "$fixture exited nonzero on --backend=direct"
    answers "$got" "$want" ||
        fail "$fixture answered '$got' on --backend=direct where its oracle line says '$want'"
    printf 'layout gate: arm 7 %s agrees (direct)\n' "$fixture"
    direct_measured=1
    rm -f "$work/direct.bin"
done
[ "$direct_measured" = 1 ] ||
    printf 'layout gate: arm 7 direct realization NOT MEASURED — DNB004 on this host\n'

printf 'layout gate: PASS (wasm realization of five fixtures; four STILL OWED, see arm 5)\n'
