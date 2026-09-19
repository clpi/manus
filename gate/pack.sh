#!/bin/sh
# gate/pack.sh — the pack corpus's own oracle lines, COMPARED.
#
#   sh gate/pack.sh
#
# The gate holds no expected answer. Every number it compares comes out of a
# fixture's own `# expect:` line; the gate supplies the run and the comparison.
#
# arm 0  the comparison's controls, through the real pipeline
# arm 1  the acceptance run, wasm under wasmtime
# arm 2  the face arm 1 is blind to, with the mangling that demonstrates it
# arm 3  the declaration read past its first separator, run not asserted
# arm 4  the realizations that refuse, pinned at their exact ids
# arm 5  the fixtures with no realization, pinned; FAILS the day one compiles
# arm 6  the loop law consume.id was rewritten off, run not asserted
# arm 7  the check green, and the one fixture check convicts
# arm 8  a second wasm engine on the same artifact

set -eu

root=${PACK_ROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}

if [ "${IDOL_LOCK_HELD:-0}" != 1 ]; then
    exec "$root/tools/node/dev/idol-lock" -- "$0" "$@"
fi

cd "$root" || { printf 'pack gate: FAIL cannot cd to %s\n' "$root" >&2; exit 1; }

work=$(mktemp -d "${TMPDIR:-/tmp}/idol-pack.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

fail() {
    printf 'pack gate: FAIL %s\n' "$1" >&2
    exit 1
}

blocked() {
    printf 'pack gate: NOT MEASURED — %s\n' "$1" >&2
    exit 3
}

idol=${IDOL_BIN:-"$root/zig-out/bin/idol"}
[ -x "$idol" ] || fail "compiler is not executable: $idol (run zig build)"

wasmtime=${WASMTIME_BIN:-wasmtime}
command -v "$wasmtime" >/dev/null 2>&1 ||
    blocked "no wasmtime on PATH; the realization that answers these fixtures cannot be run"

shim=tools/node/dev/grammar/idol_c_runtime_shim.c
cc=${CC:-cc}

live='examples/pack/x8.id'
dead='examples/pack/consume.id:missing-application-id
examples/pack/ladder.id:missing-application-id
examples/pack/merge.id:result-pack-arity'
unparsed='examples/pack/apply.id'

for fixture in $live $unparsed; do
    [ -f "$fixture" ] || fail "$fixture is missing"
done
for row in $dead; do
    [ -f "${row%%:*}" ] || fail "${row%%:*} is missing"
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

# `blank PATH` — a stale artifact from an earlier row must never read as this
# row's result. Every artifact test below is `-s`.
blank() {
    : >"$1"
}

# `wasmAnswer FILE OUT` — compile, run, echo the values in order with the
# newlines flattened. A refusal or a nonzero run is the caller's failure, never
# a skip. The artifact is checked as well as the status.
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

answers "8 417" "8 417" || fail "arm 0: answers rejected an agreeing pair"
if answers "8 417" "8 8"; then
    fail "arm 0: answers accepted a collapsed pair — the comparison is dead"
fi

seed=examples/pack/x8.id
seed_want=$(expectOf "$seed")
[ -n "$seed_want" ] || fail "arm 0: $seed carries no '# expect:' line to build controls from"

# Each control runs the whole pipeline against a copy of the real fixture and is
# built from that fixture's own answer, so none names a number: keying a control
# to a literal would make a falsified REAL fixture trip here instead of in arm 1.
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
    printf 'pack gate: arm 0 %s oracle line rejected\n' "$_label"
}

control falsified "$(printf '%s' "$seed_want" | tr '0123456789' '9876543210')"
control short "$(printf '%s' "$seed_want" | sed 's/ [^ ]*$//')"
control permuted "$(printf '%s\n' "$seed_want" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')"

sed '/^# expect: /d' "$seed" >"$work/nooracle.id"
[ -z "$(expectOf "$work/nooracle.id")" ] || fail "arm 0: the missing-oracle control did not take"
printf 'pack gate: arm 0 a fixture with no oracle line reads empty and arm 1 fails it\n'

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
    printf 'pack gate: arm 1 %s %s cells agree\n' "$fixture" "$n"
done
printf 'pack gate: arm 1 %s cells compared under wasmtime\n' "$cells"

# ============================== ARM 2: THE FACE =============================

# `mangle IN OUT` — 98ceb52c's rewrite, applied mechanically: a descriptor
# declared across newlines is collapsed onto one comma-separated line.
mangle() {
    awk '
      /^[a-z][a-z0-9]*: \{$/ { name = $0; sub(/: \{$/, "", name); body = ""; inb = 1; next }
      inb && /^\}$/ { printf "%s: { %s }\n", name, body; inb = 0; next }
      inb { f = $0; sub(/^[[:space:]]+/, "", f); sub(/,$/, "", f)
            body = (body == "" ? f : body ", " f); next }
      { print }
    ' "$1" >"$2"
}

# The three separator spellings the fixture must carry: newline-only, the
# one-line comma witness they must agree with, and the optional comma inside a
# newline-separated block.
faceOf() {
    _f=$1
    # `span` is declared across newlines with no comma anywhere in the block.
    awk '/^span: \{$/ { inb = 1; n = 0; next }
         inb && /^\}$/ { inb = 0; done = 1; next }
         inb { n++; if ($0 ~ /,$/) bad = 1 }
         END { exit (done && n >= 3 && !bad) ? 0 : 1 }' "$_f" || return 1
    # the one-line comma witness `span` has to agree with, at the same arity
    grep -q '^pace: { step: i64, start: i64, stop: i64 }$' "$_f" || return 1
    # `mix` separates by newline and spells the comma on one field only
    awk '/^mix: \{$/ { inb = 1; next }
         inb && /^\}$/ { inb = 0; done = 1; next }
         inb { if ($0 ~ /,$/) c++; else p++ }
         END { exit (done && c >= 1 && p >= 1) ? 0 : 1 }' "$_f" || return 1
    return 0
}

faceOf "$seed" ||
    fail "arm 2: $seed no longer spells a newline-separated descriptor, the one-line comma witness, or the optional comma — the separator has left the file named for it"
printf 'pack gate: arm 2 %s carries the newline-separated declaration, the comma witness and the optional comma\n' "$seed"

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
printf 'pack gate: arm 2 the copy mangled as 98ceb52c did it answers the identical %s cells and fails the face check — the numbers are blind to it\n' \
    "$(printf '%s' "$seed_want" | wc -w | tr -d ' ')"

# ================= ARM 3: THE DECLARATION READ PAST ITS FIRST SEPARATOR =====

# The last field of the newline-separated block is two separators deep. Delete
# it and the fixture must refuse: that is the compiler saying the field `417`
# reads was contributed by this declaration and not by an unchecked table.
awk 'BEGIN { n = 0 } /^  step: i64$/ && n == 0 { n = 1; next } { print }' "$seed" >"$work/nostep.id"
if cmp -s "$seed" "$work/nostep.id"; then fail "arm 3: the field-deletion control did not take"; fi
blank "$work/nostep.wasm"
if "$idol" compile --backend=wasm "$work/nostep.id" -o "$work/nostep.wasm" >"$work/nostep.log" 2>&1; then
    fail "arm 3: the newline-separated block lost its last field and the fixture STILL compiles — the declaration is not what supplies the fields these cells read"
fi
grep -q "descriptor 'span' has no field 'step'" "$work/nostep.log" ||
    fail "arm 3: deleting the last field refused for another reason: $(head -3 "$work/nostep.log" | tr '\n' ' ')"

# The control separates the deletion from the editing: removing a blank line
# through the same machinery must leave the fixture compiling and answering.
awk 'BEGIN { n = 0 } /^$/ && n == 0 { n = 1; next } { print }' "$seed" >"$work/noblank.id"
if cmp -s "$seed" "$work/noblank.id"; then fail "arm 3 control: the blank-line control did not take"; fi
noblank_got=$(wasmAnswer "$work/noblank.id" "$work/noblank.wasm")
answers "$noblank_got" "$seed_want" ||
    fail "arm 3 control: a blank-line deletion changed the answer to '$noblank_got', so arm 3's refusal is not about the field"
printf 'pack gate: arm 3 the last field of the newline-separated block is what answers; deleting a blank line instead still agrees\n'

# ==================== ARM 4: THE REALIZATIONS THAT REFUSE ===================

[ -f "$shim" ] || fail "arm 4: the C runtime shim $shim is missing"
command -v "$cc" >/dev/null 2>&1 ||
    fail "arm 4: no C compiler ($cc); the second realization on this host cannot be measured"

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
        answers "$got" "$(expectOf "$fixture")" ||
            fail "$fixture answered '$got' as C99 where its oracle line says '$(expectOf "$fixture")'"
        printf 'pack gate: arm 4 %s NOW agrees under C99 as well as wasm — record it\n' "$fixture"
    else
        seen=$(refusalOf "$work/$base.clog")
        [ "$seen" = operation-not-in-c99-slice ] ||
            fail "$fixture neither emitted C nor refused at operation-not-in-c99-slice; it refused at '$seen'"
        printf 'pack gate: arm 4 %s refuses C99 at %s\n' "$fixture" "$seen"
    fi

    blank "$work/$base.bin"
    "$idol" compile --backend=direct "$fixture" -o "$work/$base.bin" >"$work/$base.dlog" 2>&1 || true
    if [ -s "$work/$base.bin" ]; then
        got=$("$work/$base.bin" | tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ $//') ||
            fail "$fixture exited nonzero on --backend=direct"
        answers "$got" "$(expectOf "$fixture")" ||
            fail "$fixture answered '$got' on --backend=direct where its oracle line says '$(expectOf "$fixture")'"
        printf 'pack gate: arm 4 %s NOW agrees on the direct backend — record it\n' "$fixture"
    else
        grep -q DNB004 "$work/$base.dlog" ||
            fail "$fixture --backend=direct neither answered DNB004 nor produced a binary: $(head -3 "$work/$base.dlog" | tr '\n' ' ')"
        printf 'pack gate: arm 4 %s has no direct realization on this host (DNB004)\n' "$fixture"
    fi
done

# =============== ARM 5: THE FIXTURES THAT CANNOT BE COMPARED ================

for row in $dead; do
    fixture=${row%%:*}
    want_id=${row##*:}
    want=$(expectOf "$fixture")
    blank "$work/dead.wasm"
    if "$idol" compile --backend=wasm "$fixture" -o "$work/dead.wasm" >"$work/dead.log" 2>&1 &&
        [ -s "$work/dead.wasm" ]; then
        fail "$fixture NOW COMPILES. Its answer has never been compared: run it, state its '# expect:' line if it has none, and move it into the live list"
    fi
    seen=$(refusalOf "$work/dead.log")
    [ "$seen" = "$want_id" ] ||
        fail "$fixture refuses at '$seen', not at the recorded '$want_id'"
    if [ -n "$want" ]; then
        printf 'pack gate: arm 5 %s owes %s cells, still refused at %s\n' \
            "$fixture" "$(printf '%s' "$want" | wc -w | tr -d ' ')" "$seen"
    else
        printf 'pack gate: arm 5 %s states NO oracle line at all and is refused at %s — doubly uncomparable\n' \
            "$fixture" "$seen"
    fi
done

# A wrong id must not be accepted, or arm 5 would pass on any refusal at all.
blank "$work/dead.wasm"
"$idol" compile --backend=wasm examples/pack/merge.id -o "$work/dead.wasm" >"$work/dead.log" 2>&1 || true
[ "$(refusalOf "$work/dead.log")" != missing-application-id ] ||
    fail "arm 5 control: merge.id reads as refusing at another fixture's id, so the ids are not being compared"
printf 'pack gate: arm 5 control a mismatched refusal id is rejected\n'

# apply.id does not reach a refusal id: it is a parse error, so it is pinned by
# position and text instead.
for fixture in $unparsed; do
    [ -z "$(expectOf "$fixture")" ] ||
        fail "$fixture now states an oracle line but still does not parse; pin it where it can be compared"
    blank "$work/unparsed.wasm"
    if "$idol" compile --backend=wasm "$fixture" -o "$work/unparsed.wasm" >"$work/unparsed.log" 2>&1; then
        fail "$fixture NOW PARSES. It states no answer at all: give it a '# expect:' line, run it, and move it into the live list"
    fi
    grep -q "^$fixture:16:15: error:.*law.brace" "$work/unparsed.log" ||
        fail "$fixture no longer fails at 16:15 'law.brace': $(grep -m1 error: "$work/unparsed.log")"
    printf 'pack gate: arm 5 %s does not parse (16:15 law.brace) and states no oracle line\n' "$fixture"
done

# ==================== ARM 6: THE LOOP LAW consume.id LOST ===================

# 762e2bff rewrote `while b = pull()` into the compiler's own desugaring inside
# the fixture that existed to pin the binding condition. Both spellings are run
# here. If they refuse identically the rewrite bought nothing; if either one
# resolves, consume.id must be moved onto the form that runs.
cat >"$work/wbind.id" <<'PROBE'
f: i64 = (a: i64)
  a + 1
total = 0
i = 0
while b = f(i)
  total = total + b
  i = i + 1
  if i > 3
    break
print(total)
PROBE
cat >"$work/wdesugar.id" <<'PROBE'
f: i64 = (a: i64)
  a + 1
total = 0
i = 0
while true
  b = f(i)
  if b
    total = total + b
    i = i + 1
    if i > 3
      break
  else
    break
print(total)
PROBE

loop_id=missing-application-id
for probe in wbind wdesugar; do
    "$idol" check "$work/$probe.id" >"$work/$probe.check" 2>&1 ||
        fail "arm 6: the $probe probe no longer passes idol check: $(grep -m1 error: "$work/$probe.check")"
    blank "$work/$probe.wasm"
    if "$idol" compile --backend=wasm "$work/$probe.id" -o "$work/$probe.wasm" >"$work/$probe.log" 2>&1 &&
        [ -s "$work/$probe.wasm" ]; then
        fail "arm 6: the $probe probe NOW has a realization. consume.id can be measured: put its law back and compare its 26"
    fi
    seen=$(refusalOf "$work/$probe.log")
    [ "$seen" = "$loop_id" ] ||
        fail "arm 6: the $probe probe refuses at '$seen', not at the recorded '$loop_id'"
done

# The control: the same loop with no call inside compiles and answers, so the
# refusal above is about the call in the loop and not about `while` itself.
cat >"$work/wplain.id" <<'PROBE'
total = 0
i = 0
while true
  i = i + 1
  if i > 4
    break
  total = total + i
print(total)
PROBE
plain_got=$(wasmAnswer "$work/wplain.id" "$work/wplain.wasm")
answers "$plain_got" "10" ||
    fail "arm 6 control: a call-free while answered '$plain_got', so the refusal above is not about the call"
printf 'pack gate: arm 6 the binding condition and the desugaring 762e2bff wrote in its place refuse identically at %s; a call-free while answers\n' "$loop_id"

# consume.id's header ends the loop on a falsy binding. A constant index past
# the end is refused before it runs, and a computed one traps: nothing here
# answers nil, so that termination is not realized either.
cat >"$work/oob.id" <<'PROBE'
src = { 3, 5, 7, 11 }
print(src[9])
PROBE
blank "$work/oob.wasm"
if "$idol" compile --backend=wasm "$work/oob.id" -o "$work/oob.wasm" >"$work/oob.log" 2>&1; then
    fail "arm 6: a constant index past the end now compiles; measure what it answers and re-cut this arm"
fi
[ "$(refusalOf "$work/oob.log")" = aggregate-index-bounds ] ||
    fail "arm 6: the constant out-of-range index refused at '$(refusalOf "$work/oob.log")', not aggregate-index-bounds"

cat >"$work/oobrun.id" <<'PROBE'
src = { 3, 5, 7, 11 }
pos = 0
total = 0
while b = src[pos + 1]
  pos = pos + 1
  total = total + b
print(total)
PROBE
blank "$work/oobrun.wasm"
"$idol" compile --backend=wasm "$work/oobrun.id" -o "$work/oobrun.wasm" >"$work/oobrun.log" 2>&1 ||
    fail "arm 6: the computed-index loop no longer compiles: $(refusalOf "$work/oobrun.log")"
[ -s "$work/oobrun.wasm" ] || fail "arm 6: the computed-index loop compiled without an artifact"
if "$wasmtime" "$work/oobrun.wasm" >"$work/oobrun.out" 2>"$work/oobrun.err"; then
    fail "arm 6: reading past the end now TERMINATES the loop instead of trapping — it answered '$(tr '\n' ' ' <"$work/oobrun.out")'. consume.id's nil termination is realized: measure it"
fi
grep -q 'wasm trap' "$work/oobrun.err" ||
    fail "arm 6: the computed out-of-range read exited nonzero without trapping: $(head -2 "$work/oobrun.err" | tr '\n' ' ')"
printf 'pack gate: arm 6 a constant index past the end refuses at aggregate-index-bounds and a computed one traps — no nil terminates a loop here\n'

# ========================== ARM 7: THE CHECK GREEN ==========================

checked=0
for fixture in $live; do
    "$idol" check "$fixture" >/dev/null 2>&1 ||
        fail "arm 7: idol check now refuses $fixture, which arm 1 runs"
    checked=$((checked + 1))
done
for row in $dead; do
    if ! "$idol" check "${row%%:*}" >/dev/null 2>&1; then
        fail "arm 7: idol check now CONVICTS ${row%%:*}, which has no realization. The front end has caught up with the realizer: say so and re-cut this arm"
    fi
    checked=$((checked + 1))
done
for fixture in $unparsed; do
    if "$idol" check "$fixture" >/dev/null 2>&1; then
        fail "arm 7: idol check now passes $fixture, which does not parse — re-cut this arm"
    fi
    checked=$((checked + 1))
done
printf 'pack gate: arm 7 idol check exits 0 on %s of %s fixtures, including the %s with no realization, and convicts only %s\n' \
    "$((checked - 1))" "$checked" "$(printf '%s\n' "$dead" | wc -l | tr -d ' ')" "$unparsed"

# ======================= ARM 8: THE SECOND WASM ENGINE ======================

if command -v node >/dev/null 2>&1; then
    cat >"$work/engine.mjs" <<'ENGINE'
import { WASI } from 'node:wasi'
import { readFile } from 'node:fs/promises'
const wasi = new WASI({ version: 'preview1', args: [], env: {}, returnOnExit: true })
const inst = await WebAssembly.instantiate(
  await WebAssembly.compile(await readFile(process.argv[2])),
  wasi.getImportObject())
process.exit(wasi.start(inst))
ENGINE
    for fixture in $live; do
        base=$(basename "$fixture" .id)
        [ -s "$work/$base.wasm" ] || fail "arm 8: arm 1 left no artifact for $fixture"
        got=$(node --no-warnings "$work/engine.mjs" "$work/$base.wasm" |
            tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ $//') ||
            fail "arm 8: $fixture exited nonzero under node's WASI"
        answers "$got" "$(expectOf "$fixture")" ||
            fail "arm 8: $fixture answered '$got' under node's WASI where its oracle line says '$(expectOf "$fixture")'"
        printf 'pack gate: arm 8 %s agrees under a second wasm engine\n' "$fixture"
    done
else
    printf 'pack gate: arm 8 NOT MEASURED — no node on PATH for a second wasm engine\n'
fi

printf 'pack gate: PASS (%s cells under two wasm engines; three fixtures owed and one unparsed, see arm 5)\n' "$cells"
