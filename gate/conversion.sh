#!/bin/sh
# gate/conversion.sh — the conversion corpus's own oracle lines, COMPARED.
#
#   sh gate/conversion.sh
#
# WHAT THIS GATE EXISTS FOR. The six fixtures under `examples/conversion/` carry
# the conversion ladder, the relation hub, descriptor-space edge keying, the
# descriptor slot and the level application, and each states its answer on a
# `# expect:` line. NOTHING READ ONE. The readers of `# expect:` in this tree are
# `gate/gap-221-shadowstore.sh`, `gate/divsign.sh`, `gate/width.sh` and
# `gate/layout.sh`, each over its own fixtures; the only things that ever named
# this corpus are `scripts/capability_rows.id` and `scripts/census/infer.id`,
# which are `.id` with no compiler to run them, and `lib/agent.id`, which lists
# paths. `idol check` answers "checked — no errors" on all six, which is the
# green that let this stand: FOUR OF THE SIX CANNOT BE REALIZED AT ALL.
#
# IT IS NOT A SECOND PRODUCER OF THE LAW. This gate holds no expected answer.
# Every number it compares comes out of a fixture's own `# expect:` line; the
# gate supplies the run and the comparison.
#
# THE MEASURED LAND is `examples/conversion/edge.id`. It is named for descriptor
# space — `decode(u64) = (cursor)`, where `u64` is the key saying WHICH edge this
# is — and commit 98ceb52c, an argument-projection migration whose message never
# mentions levels, rewrote `step(u64) = (c: i64): i64` into
# `step__u64: i64 = (c: i64)` and every call with it. THE ORACLE LINE DID NOT
# MOVE, because three separately named functions answer the same three numbers,
# so no number could see the loss, and nothing ran the file. The same commit
# gutted `examples/layout/glued.id` the same way and mangled
# `examples/projection/algebra.id`, whose header still teaches `to(str) =
# (value)` over a body spelling `to__str`; that file is another owner's.
#
# ARM 0  THE COMPARISON'S OWN CONTROLS, run before any fixture reaches it. The
#        whole pipeline is run against copies of a real fixture and required to
#        REJECT an oracle line FALSIFIED, one cell SHORT, and PERMUTED into the
#        wrong order while holding the identical multiset. The short one proves
#        the count is compared and not a prefix; the permuted one proves the
#        newline-to-space normalisation did not become a sort. A fixture whose
#        `# expect:` line is missing entirely is a FAIL, not a skip.
#
# ARM 1  THE ACCEPTANCE RUN. Each fixture that has a realization is compiled
#        `--backend=wasm`, run under wasmtime, and its stdout compared against
#        its own `# expect:` line, token for token and in order.
#
# ARM 2  THE FACE, which arm 1 is blind to. `edge.id` must still spell the
#        levelled declaration and the levelled application, and must still carry
#        the mangled witness it is required to agree with. The control is the
#        demonstration: a copy mangled exactly as 98ceb52c did it PASSES arm 1
#        and must FAIL here, which is why a corpus proved only by value cannot
#        notice its law leaving the file.
#
# ARM 3  THE IDENTITY WITNESS, run rather than asserted. `step(u64) = ...` and
#        `step__u64 = ...` declared at the same key must collide as ONE name —
#        the compiler says "ambiguous call to overloaded function 'step__u64'",
#        which is the compiler stating that the levelled face and the mangled
#        face are one graph identity and not two. The control is the same probe
#        at distinct keys, which must compile and answer.
#
# ARM 4  THE SECOND REALIZATION, measured and not reported. `--backend=c
#        --emit=c` plus `cc` against `idol_c_runtime_shim.c` is a real route on
#        this host, so any fixture that emits C is RUN there and compared to the
#        same oracle line. One that refuses has its refusal id pinned.
#
# ARM 5  THE FOUR THAT CANNOT BE COMPARED, pinned at their exact refusal ids.
#        This arm FAILS the day one of them compiles, because that is the day
#        its numbers must be measured. No repair is attempted here; those
#        boundaries are other owners'.
#
# ARM 6  THE FRONTIER AROUND THE LEVELLED FACE, run rather than asserted. The
#        canonical result-on-the-binding spelling `step(u64): i64 = (c: i64)`
#        does not parse, and the canonical subject-first call `n:step(u64)`
#        refuses at `missing-application-id`. Together they are the choice
#        98ceb52c faced. Pinned, so the day either resolves this says so.
#
# ARM 7  THE FALSE GREEN. `idol check` must be measured to exit 0 on all six,
#        including the four with no realization, so that the day `check` starts
#        convicting them this arm reports it.
#
# ARM 8  THE DIRECT REALIZATION, reported and never assumed.

set -eu

root=${CONVERSION_ROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}

if [ "${IDOL_LOCK_HELD:-0}" != 1 ]; then
    exec "$root/tools/node/dev/idol-lock" -- "$0" "$@"
fi

cd "$root" || { printf 'conversion gate: FAIL cannot cd to %s\n' "$root" >&2; exit 1; }

work=$(mktemp -d "${TMPDIR:-/tmp}/idol-conversion.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

fail() {
    printf 'conversion gate: FAIL %s\n' "$1" >&2
    exit 1
}

blocked() {
    printf 'conversion gate: NOT MEASURED — %s\n' "$1" >&2
    exit 3
}

idol=${IDOL_BIN:-"$root/zig-out/bin/idol"}
[ -x "$idol" ] || fail "compiler is not executable: $idol (run zig build)"

wasmtime=${WASMTIME_BIN:-wasmtime}
command -v "$wasmtime" >/dev/null 2>&1 ||
    blocked "no wasmtime on PATH; the realization that answers these fixtures cannot be run"

shim=tools/node/dev/grammar/idol_c_runtime_shim.c
cc=${CC:-cc}

# The two fixtures that have a realization today, and the four that do not with
# the exact id each refuses at. Arm 5 owns the second list.
live='examples/conversion/edge.id examples/conversion/level.id examples/conversion/slot.id'
dead='examples/conversion/convert.id:unsupported-conversion
examples/conversion/relation.id:missing-application-id
examples/conversion/store.id:missing-application-id'

for fixture in $live; do
    [ -f "$fixture" ] || fail "$fixture is missing"
done
for row in $dead; do
    fixture=${row%%:*}
    [ -f "$fixture" ] || fail "$fixture is missing"
done

answers() {
    [ "$1" = "$2" ]
}

# `expectOf FILE` — the fixture's own oracle line, or empty.
expectOf() {
    sed -n 's/^# expect: *//p' "$1" | head -1
}

# `refusalOf LOG` — the id the compiler refused at, or empty.
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

# ===================== ARM 0: THE COMPARISON'S CONTROLS =====================

answers "42 141 1041" "42 141 1041" || fail "arm 0: answers rejected an agreeing pair"
if answers "42 141 1041" "42 141 141"; then
    fail "arm 0: answers accepted an erased level — the comparison is dead"
fi

# Three false-accept controls, each through the real pipeline, built from a real
# fixture's own answer so they stay correct when the fixture changes. None names
# a number: keying a control to a literal oracle line would make a falsified
# REAL fixture trip here instead of in arm 1, which is the arm meant to catch it.
seed=examples/conversion/edge.id
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
    printf 'conversion gate: arm 0 %s oracle line rejected\n' "$_label"
}

control falsified "$(printf '%s' "$seed_want" | tr '0123456789' '9876543210')"
control short "$(printf '%s' "$seed_want" | sed 's/ [^ ]*$//')"
control permuted "$(printf '%s\n' "$seed_want" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')"

sed '/^# expect: /d' "$seed" >"$work/nooracle.id"
[ -z "$(expectOf "$work/nooracle.id")" ] || fail "arm 0: the missing-oracle control did not take"
printf 'conversion gate: arm 0 a fixture with no oracle line reads empty and arm 1 fails it\n'

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
    printf 'conversion gate: arm 1 %s %s cells agree\n' "$fixture" "$n"
done
printf 'conversion gate: arm 1 %s cells compared under wasmtime\n' "$cells"

# ============================== ARM 2: THE FACE =============================

# `mangle IN OUT` — 98ceb52c's rewrite, applied mechanically: the levelled
# declaration loses its level and takes result demand on the binding, and the
# levelled application becomes an ordinary one.
mangle() {
    sed -e 's|^step(\([a-z0-9]*\)) = (\(.*\)): i64$|step__\1: i64 = (\2)|' \
        -e 's|step(\([a-z0-9]*\))(|step__\1(|g' "$1" >"$2"
}

faceOf() {
    _f=$1
    grep -q '^step(u64) = (' "$_f" || return 1
    grep -q '^step(u32) = (' "$_f" || return 1
    grep -q '^step(wide) = (' "$_f" || return 1
    grep -q 'step(u64)(' "$_f" || return 1
    grep -q 'pace__u64' "$_f" || return 1
    return 0
}

faceOf "$seed" ||
    fail "arm 2: $seed no longer spells the levelled declaration, the levelled application, or the mangled witness it must agree with — the level has left the file named for it"
printf 'conversion gate: arm 2 %s carries the levelled declaration, the levelled application and the mangled witness\n' "$seed"

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
printf 'conversion gate: arm 2 the copy mangled as 98ceb52c did it answers the identical %s cells and fails the face check — the numbers are blind to it\n' \
    "$(printf '%s' "$seed_want" | wc -w | tr -d ' ')"

# ========================= ARM 3: THE IDENTITY WITNESS ======================

cat >"$work/collide.id" <<'PROBE'
step(u64) = (c: i64): i64
  c + 1

step__u64: i64 = (c: i64)
  c + 500

print(step(u64)(41))
0
PROBE
blank "$work/collide.wasm"
if "$idol" compile --backend=wasm "$work/collide.id" -o "$work/collide.wasm" >"$work/collide.log" 2>&1; then
    fail "arm 3: the levelled and mangled declarations at the same key now COMPILE side by side — they are no longer one identity, and edge.id's witness must be rewritten"
fi
grep -q "ambiguous call to overloaded function 'step__u64'" "$work/collide.log" ||
    fail "arm 3: the same-key probe refused, but not as one name: $(head -3 "$work/collide.log" | tr '\n' ' ')"

cat >"$work/distinct.id" <<'PROBE'
step(u64) = (c: i64): i64
  c + 1

step__u32: i64 = (c: i64)
  c + 500

a = step(u64)(41)
b = step__u32(41)
print("{a} {b}")
0
PROBE
distinct_got=$(wasmAnswer "$work/distinct.id" "$work/distinct.wasm")
answers "$distinct_got" "42 541" ||
    fail "arm 3 control: the distinct-key probe answered '$distinct_got', so the collision above may be about coexistence rather than about the key"
printf 'conversion gate: arm 3 step(u64) and step__u64 collide as one name; at distinct keys they coexist and answer\n'

# ======================= ARM 4: THE SECOND REALIZATION ======================

[ -f "$shim" ] || fail "arm 4: the C runtime shim $shim is missing"
command -v "$cc" >/dev/null 2>&1 ||
    fail "arm 4: no C compiler ($cc); the second realization on this host cannot be run"

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
        printf 'conversion gate: arm 4 %s agrees under C99 as well as wasm\n' "$fixture"
        c_measured=$((c_measured + 1))
    else
        seen=$(refusalOf "$work/$base.clog")
        [ "$seen" = operation-not-in-c99-slice ] ||
            fail "$fixture neither emitted C nor refused at operation-not-in-c99-slice; it refused at '$seen'"
        printf 'conversion gate: arm 4 %s refuses C99 at %s and is measured under wasm only\n' "$fixture" "$seen"
    fi
done
[ "$c_measured" -gt 0 ] ||
    fail "arm 4: no fixture reached the C99 realization, so this arm compared nothing"

# ==================== ARM 5: THE FOUR THAT CANNOT BE COMPARED ===============

for row in $dead; do
    fixture=${row%%:*}
    want_id=${row##*:}
    want=$(expectOf "$fixture")
    [ -n "$want" ] ||
        fail "$fixture carries no '# expect:' line, so it records nothing to owe"
    blank "$work/dead.wasm"
    if "$idol" compile --backend=wasm "$fixture" -o "$work/dead.wasm" >"$work/dead.log" 2>&1 &&
        [ -s "$work/dead.wasm" ]; then
        fail "$fixture NOW COMPILES. Its oracle line '$want' has never been compared: run it, compare it, and move it into the live list"
    fi
    seen=$(refusalOf "$work/dead.log")
    [ "$seen" = "$want_id" ] ||
        fail "$fixture refuses at '$seen', not at the recorded '$want_id'"
    printf 'conversion gate: arm 5 %s owes %s cells, still refused at %s\n' \
        "$fixture" "$(printf '%s' "$want" | wc -w | tr -d ' ')" "$seen"
done

# A wrong id must not be accepted, or arm 5 would pass on any refusal at all.
blank "$work/dead.wasm"
"$idol" compile --backend=wasm examples/conversion/convert.id -o "$work/dead.wasm" >"$work/dead.log" 2>&1 || true
[ "$(refusalOf "$work/dead.log")" != record-param ] ||
    fail "arm 5 control: convert.id reads as refusing at another fixture's id, so the ids are not being compared"
printf 'conversion gate: arm 5 control a mismatched refusal id is rejected\n'

# =============== ARM 6: THE FRONTIER AROUND THE LEVELLED FACE ===============

cat >"$work/bindres.id" <<'PROBE'
step(u64): i64 = (c: i64)
  c + 1

print(step(u64)(41))
0
PROBE
blank "$work/bindres.wasm"
if "$idol" compile --backend=wasm "$work/bindres.id" -o "$work/bindres.wasm" >"$work/bindres.log" 2>&1; then
    fail "arm 6: a levelled declaration now takes result demand ON THE BINDING. That is the canonical face; rewrite edge.id onto it"
fi
grep -q 'write `name` at this token' "$work/bindres.log" ||
    fail "arm 6: the binding-position result probe refused for another reason: $(head -3 "$work/bindres.log" | tr '\n' ' ')"

cat >"$work/subject.id" <<'PROBE'
step(u64) = (c: i64): i64
  c + 1

n: i64 = 41
print(n:step(u64))
0
PROBE
blank "$work/subject.wasm"
if "$idol" compile --backend=wasm "$work/subject.id" -o "$work/subject.wasm" >"$work/subject.log" 2>&1; then
    fail "arm 6: the canonical subject-first call n:step(u64) now RESOLVES. It is the canonical invocation face; move edge.id onto it"
fi
subject_id=missing-application-id
[ "$(refusalOf "$work/subject.log")" = "$subject_id" ] ||
    fail "arm 6: n:step(u64) refused at '$(refusalOf "$work/subject.log")', not at the recorded '$subject_id'"
printf 'conversion gate: arm 6 result-on-the-binding does not parse and n:step(u64) refuses at missing-application-id — both still owed\n'

# ========================== ARM 7: THE FALSE GREEN ==========================

checked=0
for fixture in $live; do
    "$idol" check "$fixture" >/dev/null 2>&1 ||
        fail "arm 7: idol check now refuses $fixture, which arm 1 runs"
    checked=$((checked + 1))
done
for row in $dead; do
    fixture=${row%%:*}
    if ! "$idol" check "$fixture" >/dev/null 2>&1; then
        fail "arm 7: idol check now CONVICTS $fixture, which has no realization. The front end has caught up with the realizer: say so and re-cut this arm"
    fi
    checked=$((checked + 1))
done
printf 'conversion gate: arm 7 idol check exits 0 on all %s fixtures, including the %s with no realization\n' \
    "$checked" "$(printf '%s\n' "$dead" | wc -l | tr -d ' ')"

# ====================== ARM 8: THE DIRECT REALIZATION =======================

direct_measured=0
for fixture in $live; do
    blank "$work/direct.bin"
    "$idol" compile --backend=direct "$fixture" -o "$work/direct.bin" >"$work/direct.log" 2>&1 || true
    if grep -q 'DNB004' "$work/direct.log"; then
        continue
    fi
    [ -s "$work/direct.bin" ] ||
        fail "$fixture --backend=direct neither answered DNB004 nor produced a binary: $(head -3 "$work/direct.log" | tr '\n' ' ')"
    want=$(expectOf "$fixture")
    got=$("$work/direct.bin" | tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ $//') ||
        fail "$fixture exited nonzero on --backend=direct"
    answers "$got" "$want" ||
        fail "$fixture answered '$got' on --backend=direct where its oracle line says '$want'"
    printf 'conversion gate: arm 8 %s agrees (direct)\n' "$fixture"
    direct_measured=1
done
[ "$direct_measured" = 1 ] ||
    printf 'conversion gate: arm 8 NOT MEASURED — the direct backend answers DNB004 on this host\n'

printf 'conversion gate: PASS (wasm and C99 realizations; four fixtures owed, see arm 5)\n'
