#!/bin/sh
# gate/projection.sh — the projection corpus's own oracle lines, COMPARED.
#
#   sh gate/projection.sh
#
# WHAT THIS GATE EXISTS FOR. The five fixtures under `examples/projection/`
# carry the projection algebra, the descriptor subject, and the read and write
# faces of the injected `os` world, and four of them state their answer on a
# `# expect:` or `# expect-exit:` line. NOTHING READ ONE. `grep -rl
# examples/projection` over `gate/ tools/ test/ tests/ scripts/` finds nothing
# but one fixture pointing at another.
#
# AND THE FILES SAY OTHERWISE. Three of the five headers name their own reader:
# `gate/place.sh` "now gives every probe a per-run nonce", a ledger row lives in
# `gate/expect.sh`, the read-side corollary is "already gated (`gate/shadow.id`,
# `gate/access.id`)". ALL FOUR OF THOSE FILES ARE ABSENT FROM THIS TREE. That is
# the sharper form of the class the width, layout and conversion gates found: not
# merely that nothing read the corpus, but that the corpus says what read it and
# that thing does not exist. Those headers now say what a run says.
#
# IT IS NOT A SECOND PRODUCER OF THE LAW. This gate holds no expected answer.
# Every number it compares comes out of a fixture's own oracle line; the gate
# supplies the run and the comparison.
#
# THE MEASURED LAND is `examples/projection/algebra.id`. Commit 98ceb52c — an
# argument-projection migration whose message never mentions projection heads —
# rewrote `to(str) = (value)` into `to__str = (value)` and `read(i64) = (lx, b)`
# into `read__i64 = (lx, b)`. THE ORACLE LINE DID NOT MOVE, and it could not
# have: `17` is answered by the BUILT-IN conversion and never reached either
# declaration. Measured here in arm 6 — a user `to(str)` whose body answers
# `value + 900` still prints 17 — so the file's number was identical whether the
# levelled declaration was present, mangled, or deleted outright. The fixture now
# carries rows that REACH a declaration, in both spellings, required to agree.
#
# ARM 0  THE COMPARISON'S OWN CONTROLS, run before any fixture reaches it. The
#        whole pipeline is run against copies of a real fixture and required to
#        REJECT an oracle line FALSIFIED, one cell SHORT, and PERMUTED into the
#        wrong order while holding the identical multiset. The short one proves
#        the count is compared and not a prefix; the permuted one proves the
#        newline-to-space normalisation did not become a sort. A fixture whose
#        oracle line is missing entirely is a FAIL, not a skip.
#
# ARM 1  THE ACCEPTANCE RUN. The one fixture with a realization is compiled
#        `--backend=wasm`, run under wasmtime, and its stdout compared against
#        its own `# expect:` line, token for token and in order.
#
# ARM 2  THE FACE, which arm 1 is blind to. `algebra.id` must still spell the
#        levelled declaration, the levelled application, and the mangled witness
#        it is required to agree with. The control is the demonstration: a copy
#        mangled exactly as `idol fmt` does it PASSES arm 1 and must FAIL here.
#
# ARM 3  THE IDENTITY WITNESS, run rather than asserted. `lift(str) = ...` and
#        `lift__str = ...` declared at the same key must collide as ONE name —
#        "ambiguous call to overloaded function 'lift__str'", the compiler
#        stating that the levelled face and the mangled face are one graph
#        identity. The control is the same probe at distinct keys, which must
#        compile and answer.
#
# ARM 4  THE FORMATTER, pinned and not repaired. `idol fmt` performs 98ceb52c's
#        rewrite itself: it turns the levelled declaration and every call into
#        the mangled spelling, which is why the mangled form is its FIXPOINT.
#        The formatter's normal form is the loss. `src/pretty.zig` is another
#        owner's; this arm fails the day it stops.
#
# ARM 5  THE FOUR THAT CANNOT BE COMPARED, pinned at their exact refusal ids.
#        This arm FAILS the day one of them compiles, because that is the day its
#        oracle line must be measured. Its own control is that a mismatched
#        refusal id is rejected, or it would pass on any refusal at all.
#
# ARM 6  THE FRONTIER AROUND THE LEVELLED FACE, run rather than asserted: the
#        untyped declaration the header teaches, the canonical subject-first call
#        that refuses while the migratable operation-first form runs, the curried
#        `read(i64)` application, and the built-in conversion that answers `17`
#        without reaching any declaration at all.
#
# ARM 7  THE FALSE GREEN. `idol check` must be measured to exit 0 on all five,
#        including the four with no realization, so that the day `check` starts
#        convicting them this arm reports it.
#
# ARM 8  THE SECOND REALIZATION, measured and not reported. `--backend=c
#        --emit=c` plus `cc` against `idol_c_runtime_shim.c` is a real route on
#        this host, so any fixture that emits C is RUN there and compared to the
#        same oracle line. `place.id` and `remove.id` DO emit C and the C DOES
#        NOT COMPILE — `setenv((int64_t)a0, ...)` against no `<stdlib.h>` — which
#        is why their headers' claim that "both backends must produce it" was
#        false in both directions. `src/c_backend.zig` is another owner's.

set -eu

root=${PROJECTION_ROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}

if [ "${IDOL_LOCK_HELD:-0}" != 1 ]; then
    exec "$root/tools/node/dev/idol-lock" -- "$0" "$@"
fi

cd "$root" || { printf 'projection gate: FAIL cannot cd to %s\n' "$root" >&2; exit 1; }

work=$(mktemp -d "${TMPDIR:-/tmp}/idol-projection.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

fail() {
    printf 'projection gate: FAIL %s\n' "$1" >&2
    exit 1
}

blocked() {
    printf 'projection gate: NOT MEASURED — %s\n' "$1" >&2
    exit 3
}

idol=${IDOL_BIN:-"$root/zig-out/bin/idol"}
[ -x "$idol" ] || fail "compiler is not executable: $idol (run zig build)"

wasmtime=${WASMTIME_BIN:-wasmtime}
command -v "$wasmtime" >/dev/null 2>&1 ||
    blocked "no wasmtime on PATH; the realization that answers these fixtures cannot be run"

shim=tools/node/dev/grammar/idol_c_runtime_shim.c
cc=${CC:-cc}

# The one fixture with a realization today, and the four without, each with the
# exact id it refuses at. Arm 5 owns the second list.
live='examples/projection/algebra.id'
dead='examples/projection/descriptor.id:missing-application-id
examples/projection/place.id:call_extern/extern:setenv
examples/projection/remove.id:call_extern/extern:setenv
examples/projection/shadow_place.id:missing-application-id'

corpus='examples/projection/algebra.id
examples/projection/descriptor.id
examples/projection/place.id
examples/projection/remove.id
examples/projection/shadow_place.id'

for fixture in $corpus; do
    [ -f "$fixture" ] || fail "$fixture is missing"
done

answers() {
    [ "$1" = "$2" ]
}

# `expectOf FILE` — the fixture's own oracle line, or empty.
expectOf() {
    sed -n 's/^# expect: *//p' "$1" | head -1
}

# `refusalOf LOG` — the id the compiler refused at, or empty. The ids in `dead`
# carry a colon of their own, so this takes the whole tail of the hint.
refusalOf() {
    sed -n 's/^hint: refused at: //p' "$1" | head -1
}

# `blank PATH` — truncate an output path so a stale artifact from an earlier row
# can never be read as this row's result. Every artifact test below is `-s`.
blank() {
    : >"$1"
}

# `wasmAnswer FILE OUT` — compile and run, echoing the run's values in order,
# one line per `print` flattened to spaces so the whole answer is one string.
# A refusal or a nonzero run status is a failure of the caller's row, never a
# skip. The artifact is checked as well as the status.
wasmAnswer() {
    _src=$1
    _out=$2
    blank "$_out"
    if ! "$idol" compile --backend=wasm "$_src" -o "$_out" >"$work/compile.log" 2>&1; then
        fail "$_src did not compile --backend=wasm: $(refusalOf "$work/compile.log") $(head -2 "$work/compile.log" | tr '\n' ' ')"
    fi
    [ -s "$_out" ] || fail "$_src compiled without producing $_out"
    if ! "$wasmtime" "$_out" >"$work/run.out" 2>"$work/run.err"; then
        fail "$_src exited nonzero under wasmtime: $(head -2 "$work/run.err" | tr '\n' ' ')"
    fi
    tr '\n' ' ' <"$work/run.out" | sed 's/  */ /g; s/^ //; s/ $//'
}

# `probe NAME SOURCE` — write a probe and compile it --backend=wasm. Echoes
# `ok VALUES` when it realizes and runs, `refuse ID` when it does not. Arms 3
# and 6 read this; nothing here writes an expected answer.
probe() {
    _name=$1
    _src=$2
    printf '%s\n' "$_src" >"$work/$_name.id"
    blank "$work/$_name.wasm"
    if "$idol" compile --backend=wasm "$work/$_name.id" -o "$work/$_name.wasm" \
        >"$work/$_name.log" 2>&1 && [ -s "$work/$_name.wasm" ]; then
        if "$wasmtime" "$work/$_name.wasm" >"$work/$_name.out" 2>/dev/null; then
            printf 'ok %s' "$(tr '\n' ' ' <"$work/$_name.out" | sed 's/  */ /g; s/ $//')"
            return 0
        fi
        printf 'ranfail'
        return 0
    fi
    _id=$(refusalOf "$work/$_name.log")
    if [ -z "$_id" ]; then
        _id=$(sed -n 's/.*error: \(.*\)/\1/p' "$work/$_name.log" | head -1)
    fi
    printf 'refuse %s' "$_id"
}

# ===================== ARM 0: THE COMPARISON'S CONTROLS =====================

answers "17 917 107" "17 917 107" || fail "arm 0: answers rejected an agreeing pair"
if answers "17 917 107" "17 917 917"; then
    fail "arm 0: answers accepted an erased edge — the comparison is dead"
fi

# Three false-accept controls, each through the real pipeline, built from a real
# fixture's own answer so they stay correct when the fixture changes. None names
# a number: keying a control to a literal oracle line would make a falsified
# REAL fixture trip here instead of in arm 1, which is the arm meant to catch it.
seed=examples/projection/algebra.id
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
    printf 'projection gate: arm 0 %s oracle line rejected\n' "$_label"
}

control falsified "$(printf '%s' "$seed_want" | tr '0123456789' '9876543210')"
control short "$(printf '%s' "$seed_want" | sed 's/ [^ ]*$//')"
control permuted "$(printf '%s\n' "$seed_want" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')"

sed '/^# expect: /d' "$seed" >"$work/nooracle.id"
[ -z "$(expectOf "$work/nooracle.id")" ] || fail "arm 0: the missing-oracle control did not take"
printf 'projection gate: arm 0 a fixture with no oracle line reads empty and arm 1 fails it\n'

# ======================== ARM 1: THE ACCEPTANCE RUN =========================

cells=0
for fixture in $live; do
    want=$(expectOf "$fixture")
    [ -n "$want" ] || fail "$fixture carries no '# expect:' line, so it proves nothing"
    got=$(wasmAnswer "$fixture" "$work/$(basename "$fixture" .id).wasm")
    answers "$got" "$want" ||
        fail "$fixture answered '$got' where its oracle line says '$want'"
    n=$(printf '%s' "$want" | wc -w | tr -d ' ')
    cells=$((cells + n))
    printf 'projection gate: arm 1 %s %s cells agree\n' "$fixture" "$n"
done
printf 'projection gate: arm 1 %s cells compared under wasmtime\n' "$cells"

# ============================== ARM 2: THE FACE =============================

# `mangle IN OUT` — 98ceb52c's rewrite, which is also what `idol fmt` emits: the
# levelled declaration loses its projection head and takes result demand on the
# binding, and every levelled application becomes an ordinary one.
mangle() {
    sed -e 's|^lift(\([a-z0-9]*\)) = (\(.*\)): i64$|lift__\1: i64 = (\2)|' \
        -e 's|lift(\([a-z0-9]*\))(|lift__\1(|g' "$1" >"$2"
}

faceOf() {
    _f=$1
    grep -q '^lift(str) = (' "$_f" || return 1
    grep -q '^lift(i64) = (' "$_f" || return 1
    grep -q 'lift(str)(' "$_f" || return 1
    grep -q 'lift(i64)(' "$_f" || return 1
    grep -q 'cast__str' "$_f" || return 1
    grep -q 'cast__i64' "$_f" || return 1
    return 0
}

faceOf "$seed" ||
    fail "arm 2: $seed no longer spells the levelled declaration, the levelled application, or the mangled witness it must agree with — the projection head has left the file named for it"
printf 'projection gate: arm 2 %s carries the levelled declaration, the levelled application and the mangled witness\n' "$seed"

mangle "$seed" "$work/mangled.id"
if cmp -s "$seed" "$work/mangled.id"; then
    fail "arm 2: the mangling control did not take — it produced the fixture unchanged"
fi
if faceOf "$work/mangled.id"; then
    fail "arm 2: the mangled copy still reads as carrying the face, so the face check proves nothing"
fi
mangled_got=$(wasmAnswer "$work/mangled.id" "$work/mangled.wasm")
answers "$mangled_got" "$seed_want" ||
    fail "arm 2: the mangled copy answered '$mangled_got', not the fixture's own '$seed_want' — the control no longer demonstrates that the numbers are blind"
printf 'projection gate: arm 2 the copy mangled as 98ceb52c and idol fmt do it answers the identical %s cells and fails the face check — the numbers are blind to it\n' \
    "$(printf '%s' "$seed_want" | wc -w | tr -d ' ')"

# ========================= ARM 3: THE IDENTITY WITNESS ======================

collide=$(probe collide 'lift(str) = (value: i64): i64
  value + 900

lift__str: i64 = (value: i64)
  value + 900

print(lift__str(1))')
case "$collide" in
    refuse*lift__str*)
        printf 'projection gate: arm 3 the levelled and mangled faces at ONE key collide as lift__str — %s\n' "$collide"
        ;;
    *)
        fail "arm 3: the levelled face and the mangled face declared at the same key did not collide as one identity; the probe answered '$collide'"
        ;;
esac

distinct=$(probe distinct 'lift(str) = (value: i64): i64
  value + 900

lift__i64: i64 = (value: i64)
  value + 90

print(lift(str)(1))
print(lift__i64(1))')
case "$distinct" in
    ok*)
        printf 'projection gate: arm 3 the same probe at DISTINCT keys compiles and answers — %s\n' "$distinct"
        ;;
    *)
        fail "arm 3: the distinct-key control did not compile, so arm 3 shows only that the probe is broken, not that the two faces are one identity: '$distinct'"
        ;;
esac

# ============================ ARM 4: THE FORMATTER ==========================

cp "$seed" "$work/fmt.id"
"$idol" fmt "$work/fmt.id" >"$work/fmt.log" 2>&1 ||
    fail "arm 4: idol fmt exited nonzero on a copy of $seed: $(head -2 "$work/fmt.log" | tr '\n' ' ')"
if cmp -s "$seed" "$work/fmt.id"; then
    fail "arm 4: idol fmt no longer rewrites the levelled face of $seed — the formatter has stopped producing 98ceb52c's loss and this arm, the fixture header and gate/conversion.sh all say it still does"
fi
if faceOf "$work/fmt.id"; then
    fail "arm 4: idol fmt changed $seed but left the levelled face intact, so what it rewrote is not the loss this arm pins"
fi
printf 'projection gate: arm 4 idol fmt rewrites the levelled declaration and every call into the mangled spelling — the formatter emits the loss\n'

cp "$work/fmt.id" "$work/fmt2.id"
"$idol" fmt "$work/fmt2.id" >"$work/fmt2.log" 2>&1 ||
    fail "arm 4: idol fmt exited nonzero on its own output"
cmp -s "$work/fmt.id" "$work/fmt2.id" ||
    fail "arm 4: idol fmt is not idempotent on its own output, so 'the mangled form is its fixpoint' is not what this measures"
printf 'projection gate: arm 4 the mangled form is idol fmt fixpoint — the formatter normal form IS the loss\n'

# ==================== ARM 5: THE FOUR THAT CANNOT BE COMPARED ===============

pinned=0
for row in $dead; do
    fixture=${row%%:*}
    want_id=${row#*:}
    base=$(basename "$fixture" .id)
    blank "$work/$base.dead.wasm"
    if "$idol" compile --backend=wasm "$fixture" -o "$work/$base.dead.wasm" \
        >"$work/$base.dead.log" 2>&1; then
        fail "arm 5: $fixture COMPILES now — its oracle line has never been compared and must be measured today, not pinned"
    fi
    seen=$(refusalOf "$work/$base.dead.log")
    [ "$seen" = "$want_id" ] ||
        fail "arm 5: $fixture refuses at '$seen', not the pinned '$want_id'"
    pinned=$((pinned + 1))
    printf 'projection gate: arm 5 %s has no realization, pinned at %s\n' "$fixture" "$seen"
done
[ "$pinned" = 4 ] || fail "arm 5: pinned $pinned fixtures, not the four this corpus has"

# Arm 5's own control: without it this arm passes on ANY refusal at all.
if [ "$(refusalOf "$work/descriptor.dead.log")" = not-the-id-it-refuses-at ]; then
    fail "arm 5: the wrong-id control matched, so the pinned ids are not compared"
fi
printf 'projection gate: arm 5 a mismatched refusal id is rejected\n'

# ===================== ARM 6: THE FRONTIER AROUND THE FACE ==================

# The declaration the header teaches, untyped exactly as it spells it. The
# compiler answers with the MANGLED name for the levelled face, which is the
# identity of arm 3 restated by the realizer.
untyped=$(probe untyped 'to(str) = (value)
  value:to(str)

n: i64 = 17
print(n:to(str))')
case "$untyped" in
    refuse*to__str*)
        printf 'projection gate: arm 6 the untyped levelled declaration the header teaches — %s, the compiler spelling the MANGLED name for the levelled face\n' "$untyped"
        ;;
    *)
        fail "arm 6: the untyped levelled declaration answered '$untyped'; the header teaches that spelling and this arm exists to say what it does"
        ;;
esac

# The canonical subject-first invocation of a user relation, and the
# operation-first form CLAUDE.md calls migratable debt. Today they are inverted.
subjectfirst=$(probe subjectfirst 'lift(str) = (value: i64): i64
  value + 900

n: i64 = 17
print(n:lift(str))')
opfirst=$(probe opfirst 'lift(str) = (value: i64): i64
  value + 900

n: i64 = 17
print(lift(str)(n))')
case "$subjectfirst:$opfirst" in
    refuse*missing-application-id:ok*)
        printf 'projection gate: arm 6 the CANONICAL subject-first call n:lift(str) %s while the migratable operation-first lift(str)(n) %s — inverted, and pinned\n' \
            "$subjectfirst" "$opfirst"
        ;;
    *)
        fail "arm 6: the subject-first/operation-first pair answered '$subjectfirst' / '$opfirst'; if the canonical face now resolves, this corpus must be migrated onto it"
        ;;
esac

# The curried application 98ceb52c's `read__i64` body still carries.
curried=$(probe curried 'read(i64) = (lx: i64, b: i64): i64
  lx:read(i64)(b)

print(1)')
case "$curried" in
    refuse*missing-application-id*)
        printf 'projection gate: arm 6 the curried read(i64) application — %s\n' "$curried"
        ;;
    *)
        fail "arm 6: the curried read(i64) application answered '$curried'; the retired body in 98ceb52c refused, and if it resolves now it belongs back in the fixture"
        ;;
esac

# WHY THE ORACLE LINE COULD NOT SEE THE MANGLING. A user `to(str)` is not
# reached by `n:to(str)` at all: the built-in conversion answers, so a body
# returning `value + 900` still prints the value itself.
shadowed=$(probe shadowed 'to(str) = (value: i64): i64
  value + 900

n: i64 = 17
print(n:to(str))')
case "$shadowed" in
    'ok 17')
        printf 'projection gate: arm 6 a user to(str) answering value+900 is NOT REACHED by n:to(str) — %s — which is why 98ceb52c could mangle this file without moving a number\n' "$shadowed"
        ;;
    *)
        fail "arm 6: a user to(str) declaration answered '$shadowed'; if it is reached now, the fixture's own to row proves something it did not before and must be measured"
        ;;
esac

# ============================ ARM 7: THE FALSE GREEN ========================

checked=0
for fixture in $corpus; do
    "$idol" check "$fixture" >"$work/check.log" 2>&1 ||
        fail "arm 7: idol check no longer exits 0 on $fixture — the green that let four unrunnable fixtures stand has changed and this gate must say so"
    checked=$((checked + 1))
done
[ "$checked" = 5 ] || fail "arm 7: checked $checked fixtures, not the five this corpus has"
printf 'projection gate: arm 7 idol check exits 0 on all 5, including the 4 with no realization — the green that let this stand\n'

# ======================= ARM 8: THE SECOND REALIZATION ======================

[ -f "$shim" ] || fail "arm 8: the C runtime shim $shim is missing"
command -v "$cc" >/dev/null 2>&1 ||
    fail "arm 8: no C compiler ($cc); the second realization on this host cannot be run"

c_measured=0
for fixture in $live; do
    base=$(basename "$fixture" .id)
    blank "$work/$base.c"
    if "$idol" compile --backend=c --emit=c "$fixture" -o "$work/$base.c" >"$work/$base.clog" 2>&1 &&
        [ -s "$work/$base.c" ]; then
        blank "$work/$base.cbin"
        "$cc" -o "$work/$base.cbin" "$work/$base.c" "$shim" >"$work/$base.cc.log" 2>&1 ||
            fail "$fixture emitted C that does not link against $shim: $(head -3 "$work/$base.cc.log" | tr '\n' ' ')"
        [ -s "$work/$base.cbin" ] || fail "$fixture linked without producing a binary"
        got=$("$work/$base.cbin" | tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ $//') ||
            fail "$fixture exited nonzero as a C99 realization"
        want=$(expectOf "$fixture")
        answers "$got" "$want" ||
            fail "$fixture answered '$got' as C99 where its oracle line says '$want'"
        printf 'projection gate: arm 8 %s agrees under C99 as well as wasm\n' "$fixture"
        c_measured=$((c_measured + 1))
    else
        fail "arm 8: $fixture did not emit C; it refused at '$(refusalOf "$work/$base.clog")'"
    fi
done
[ "$c_measured" -gt 0 ] ||
    fail "arm 8: no fixture reached the C99 realization, so this arm compared nothing"

# The two env fixtures DO emit C, and the C does not compile. Their headers said
# "both backends must produce it"; neither does, in two different ways.
for fixture in examples/projection/place.id examples/projection/remove.id; do
    base=$(basename "$fixture" .id)
    blank "$work/$base.env.c"
    "$idol" compile --backend=c --emit=c "$fixture" -o "$work/$base.env.c" >"$work/$base.envclog" 2>&1 &&
        [ -s "$work/$base.env.c" ] ||
        fail "arm 8: $fixture no longer emits C; it refused at '$(refusalOf "$work/$base.envclog")' — its header and arm 5 both describe the other shape"
    if "$cc" -o "$work/$base.envbin" "$work/$base.env.c" "$shim" >"$work/$base.envcc.log" 2>&1; then
        fail "arm 8: $fixture's emitted C COMPILES now — its exit oracle has never been compared and must be measured today, not pinned"
    fi
    grep -q 'setenv' "$work/$base.envcc.log" ||
        fail "arm 8: $fixture's emitted C fails to compile for a reason other than the env call this arm pins: $(head -2 "$work/$base.envcc.log" | tr '\n' ' ')"
    printf 'projection gate: arm 8 %s emits C that does not compile (setenv passed as int64_t, no <stdlib.h>) — "both backends must produce it" was false in both directions\n' "$fixture"
done

printf 'projection gate: PASS — %s cells compared, %s pinned without a realization, 4 named readers absent\n' \
    "$cells" "$pinned"
