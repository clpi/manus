#!/bin/sh
# gate/nul.sh — an embedded NUL is a BYTE OF THE VALUE, not the end of it, and
# both realizations must say so.
#
# ═══ WHAT THIS GATE IS FOR ═════════════════════════════════════════════════
#
# `docs/spec/text.md` rules that bytes "carry exact octets", and Lua 5.4 §3.4.7
# makes `#s` the byte count. Both realizations answered otherwise, and — this is
# the part that let it survive — they mostly answered otherwise TOGETHER. Two
# backends agreeing reads as confirmation, so the contradiction sat in a comment
# instead of a gate.
#
# MEASURED at 5418f032, `s = "a\0b"`, `s:len()` and `s:byte(1..3)`:
#
#     direct  len=1 b1=97 b2=0 b3=108     <- WRONG twice
#     wasm    len=1 b1=97 b2=0 b3=98      <- WRONG once
#     luajit  len=3 b1=97 b2=0 b3=98      <- the oracle
#
# Two distinct C representation leaks, one shared and one not:
#
#   * `:len()` lowered unconditionally to `str_len`, which is a SCAN TO THE
#     FIRST NUL in both realizations — an inline loop in `native_backend.zig`
#     and `helperStrlen` in `wasm_backend.zig`. Nothing about the value was
#     unknown; the length was simply never carried, so a C string terminator
#     answered a semantic question. Both backends, same wrong answer.
#   * the direct backend put the literal blob in `__TEXT,__cstring`,
#     S_CSTRING_LITERALS. Written out, ONE literal `"a\0b"` and TWO literals
#     `"a"`, `"b"` are the same four bytes `61 00 62 00` — the boundary between
#     literals is a fact the emitter holds and the byte stream does not carry.
#     That section type invites ld to re-derive the boundary by splitting at
#     every NUL, so it answered "two literals" and `Lduo_str_N` came out
#     pointing at `a\0` with the adjacent `len=%lld` format behind it. That is
#     where 108 comes from: the `l` of `len`. Wasm has no coalescing linker
#     step, which is the ONLY reason it was already right on that one.
#
# ═══ WHY THE SUBJECT IS A LITERAL AND WHAT THAT BOUNDS ═════════════════════
#
# A DETERMINED literal is the case where the length is a fact the compiler
# already holds, so it is the case where "scan to NUL" has no excuse. §4 states
# the boundary honestly rather than letting a reader generalize: text whose
# bytes are NOT determined — read from a stream, built by `..`, cut by `:sub` —
# still travels as a bare `const char*` with no length beside it, and every
# libc consumer on that path (`strlen`, `strcmp`, `puts`, `printf %s`,
# `snprintf`) still stops at the first NUL. §4 PINS those answers so the day
# they change, this gate says so.
#
# ═══ WHAT IT ASSERTS ═══════════════════════════════════════════════════════
#
#   §1  The control the mission names. `"a\0b"` gives `:len() == 3` and bytes
#       97/0/98, on the direct backend AND on Wasm. This is the negative
#       control: it fails on every commit before the repair.
#   §1b The same value bound at MODULE scope, whose determinacy has a different
#       producer and was still answering 1 after §1 first went green.
#   §2  The two realizations AGREE, byte for byte on stdout. Agreement alone is
#       not correctness — that is how this defect survived — so §1 owns the
#       answer and §2 owns the agreement, separately.
#   §3  A NUL-FREE program is untouched: the literal blob still ships as
#       `__TEXT,__cstring` / S_CSTRING_LITERALS, and only a module with an
#       interior NUL moves to its own `__TEXT,__conststr` / S_REGULAR section.
#       The representation choice is a CONSEQUENCE OF A FACT, not a new default.
#   §3a A module carrying BOTH an interior NUL and a determined table, so the
#       section-index and base-address arithmetic is exercised with two data
#       sections present.
#   §3b The digest §3's byte claim rests on, measured in BOTH directions: the
#       same source twice is identical, one added NUL is not. A comparison that
#       cannot tell two programs apart confirms nothing.
#   §4  The boundary, pinned as answers rather than prose: what an embedded NUL
#       still does to `print`, `:sub`, `..` and `==` in BOTH realizations. Each
#       row is a known LOSS against the oracle, and the gate fails if one
#       silently becomes something else — improved or worsened — because an
#       unremarked change here is the next comment nobody reads.
#   §5  One producer for the determined length, and one for the section choice.
#       §1 cannot see whether the fact is stated once or copied; a hand-kept
#       copy at a second consumer is the shape `gate/divisor.sh` §6 was written
#       for.
#
# ═══ HOW IT REFUSES ════════════════════════════════════════════════════════
#
# Every subject is built before it is measured, and a subject that did not
# build makes the gate exit non-zero WITHOUT reporting on the rest — a gate
# that measures nothing must fail, never pass quietly. `probe` counts the
# programs actually measured and §0 refuses a run that measured none.
#
# AND THE PROCESS STATUS IS CHECKED, NOT ONLY THE BYTES. Every subject here is
# run through `run`, which keeps the exit status beside the output and reports
# a non-zero one as its own failure. Capturing a subject with `x=$(subject)`
# alone keeps the bytes and DISCARDS the status, so a realization that printed
# exactly the right answer and then crashed compared EQUAL to the oracle and
# recorded as passing — the absence of a measurement indistinguishable from
# the absence of a violation, which is the class `gate/vacuity.sh` exists to
# convict. See the note above `run`.
set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
idol="${IDOL_BIN:-$root/zig-out/bin/idol}"
[ -x "$idol" ] || { echo "nul: no compiler at $idol" >&2; exit 2; }

work="$(mktemp -d)" || exit 2
trap 'rm -rf "$work"' EXIT

fail=0
measured=0
note() { printf 'nul: %s\n' "$1"; }
bad()  { printf 'nul: FAIL — %s\n' "$1" >&2; fail=1; }

# A WASM RUNNER IS NOT OPTIONAL HERE. This gate's whole subject is "both
# realizations", so a missing runner is a gate that measures half of what it
# claims, and half a differential is not a differential. It refuses rather
# than skipping.
wasmrun=""
for candidate in wasmtime wasmer; do
  if command -v "$candidate" >/dev/null 2>&1; then wasmrun="$candidate"; break; fi
done
[ -n "$wasmrun" ] || { echo "nul: no wasm runner (wasmtime/wasmer) — this gate is a DIFFERENTIAL and cannot report on one realization" >&2; exit 2; }

# ─── subject builder ───────────────────────────────────────────────────────
# Builds one source twice and leaves `$work/<name>.bin` and `$work/<name>.wasm`.
# Returns non-zero when either realization refused, so the caller can decline to
# measure a subject that does not exist.
build() {
  name=$1
  if ! "$idol" compile -o "$work/$name.bin" "$work/$name.id" >"$work/$name.direct.log" 2>&1; then
    bad "$name.id did not compile for the direct backend — nothing below it is measured"
    return 1
  fi
  if ! "$idol" compile --backend=wasm -o "$work/$name.wasm" "$work/$name.id" >"$work/$name.wasm.log" 2>&1; then
    bad "$name.id did not compile for the wasm backend — nothing below it is measured"
    return 1
  fi
  measured=$((measured + 1))
  return 0
}

# ─── THE PROCESS STATUS IS HALF THE ANSWER ─────────────────────────────────
# `x=$(subject)` KEEPS THE BYTES AND THROWS AWAY THE STATUS. A realization that
# prints exactly the expected stdout and then dies — a crash after the last
# `print`, a failed final return, a `SIGSEGV` in teardown — compared EQUAL to
# the oracle and was recorded as passing. That is this repository's standard
# defect one variant over: the absence of a measurement (nobody asked what the
# process did) is indistinguishable from the absence of a violation.
#
# `run <label> <cmd...>` leaves the bytes in `$ans` and the status in `$ansrc`,
# and reports a non-zero status AS ITS OWN FAILURE before any comparison
# happens. The output check still runs afterwards, because a crashing subject
# that ALSO printed the wrong bytes is two findings and the reader wants both.
#
# IT IS NEVER CALLED INSIDE `$( )`. `bad` sets `fail=1`, and item 5 on
# `gate/vacuity.sh`'s list of convicted instruments is a refusal whose `fail=1`
# died inside a command substitution while the gate printed FAIL and exited 0.
# The assignment `ans=$(...)` is inside this function; the CALL is not.
ans=''
ansrc=0
run() {
  rlabel=$1
  shift
  ans=$("$@" 2>"$work/run.err")
  ansrc=$?
  [ "$ansrc" -eq 0 ] && return 0
  rsay=$(tr -d '\r' < "$work/run.err" | grep -v '^[[:space:]]*$' | head -1 | cut -c1-72)
  rout=$(printf %s "$ans" | tr '\n' '/')
  bad "$rlabel exited $ansrc after printing [$rout] (stderr: ${rsay:-nothing}) -- a realization that does not exit cleanly has not answered, whatever it printed first"
  return 0
}

# ─── §1 the control: an embedded NUL is a byte of the value ────────────────
# `s:len()` is 3 and `s:byte(3)` is 98 ('b'), not 108 ('l', out of the next
# literal) and not 0. Both realizations, and the answer is the oracle's:
#   luajit -e 'local s="a\0b" print(#s, s:byte(1), s:byte(2), s:byte(3))'
#     -> 3  97  0  98
cat > "$work/embed.id" <<'ID'
main: i64 = ()
  s: str = "a\0b"
  n = s:len()
  a = s:byte(1)
  b = s:byte(2)
  c = s:byte(3)
  print("len={n} b1={a} b2={b} b3={c}")
  0
ID
want='len=3 b1=97 b2=0 b3=98'
if build embed; then
  run '§1 direct' "$work/embed.bin";           direct=$ans
  run '§1 wasm' "$wasmrun" "$work/embed.wasm"; wasm=$ans
  if [ "$direct" != "$want" ]; then
    bad "§1 direct: got '$direct', the oracle says '$want'. A NUL is a byte of the value; scan-to-NUL is not its length and the linker's split is not its bytes."
  else
    note "§1 direct: $direct"
  fi
  if [ "$wasm" != "$want" ]; then
    bad "§1 wasm: got '$wasm', the oracle says '$want'"
  else
    note "§1 wasm:   $wasm"
  fi
fi

# ─── §1b the same value bound at MODULE scope ──────────────────────────────
# A DIFFERENT PRODUCER OF THE SAME FACT. A function-local literal is proved
# determined by a scan of the relation body; a module binding is proved by
# `moduleConstIsStable`, which counts every write in the module including the
# ones inside relation bodies. Two proofs, one answer — and the module face was
# still answering 1 after the local face was repaired, which is why it is its
# own subject rather than a line in §1.
cat > "$work/modscope.id" <<'ID'
s: str = "a\0b"

main: i64 = ()
  n = s:len()
  c = s:byte(3)
  print("len={n} b3={c}")
  0
ID
wantmod='len=3 b3=98'
if build modscope; then
  run '§1b direct' "$work/modscope.bin";           mdirect=$ans
  run '§1b wasm' "$wasmrun" "$work/modscope.wasm"; mwasm=$ans
  [ "$mdirect" = "$wantmod" ] || bad "§1b direct module scope: got '$mdirect', the oracle says '$wantmod'"
  [ "$mwasm" = "$wantmod" ] || bad "§1b wasm module scope: got '$mwasm', the oracle says '$wantmod'"
  [ "$mdirect" != "$wantmod" ] || [ "$mwasm" != "$wantmod" ] || note "§1b module scope, both realizations: $mdirect"
fi

# ─── §2 the two realizations agree ─────────────────────────────────────────
# SEPARATE FROM §1 ON PURPOSE. Agreement is not correctness — this defect
# survived precisely because two backends agreeing read as confirmation — so
# the right answer and the agreement are two findings, and a repair that fixes
# one realization and leaves the other is caught here even if §1 half-passes.
if [ -x "$work/embed.bin" ]; then
  if [ "${direct:-x}" != "${wasm:-y}" ]; then
    bad "§2 the realizations DISAGREE on the same program: direct '$direct' vs wasm '$wasm'"
  else
    note "§2 direct and wasm agree byte for byte: $direct"
  fi
fi

# ─── §3 a NUL-free program is untouched ────────────────────────────────────
# The section type states a FACT about the literals, so it must still be
# S_CSTRING_LITERALS wherever that fact holds — which is every program anybody
# has ever compiled with this backend. A blanket move to S_REGULAR would repair
# §1 and silently cost every other module its literal coalescing.
cat > "$work/plain.id" <<'ID'
main: i64 = ()
  s: str = "abc"
  print("len={s:len()}")
  0
ID
if build plain; then
  run '§3 direct' "$work/plain.bin"; got=$ans
  [ "$got" = "len=3" ] || bad "§3 a NUL-free literal answered '$got', expected 'len=3'"
  run '§3 wasm' "$wasmrun" "$work/plain.wasm"; gotw=$ans
  [ "$gotw" = "len=3" ] || bad "§3 wasm: a NUL-free literal answered '$gotw', expected 'len=3'"
  if command -v otool >/dev/null 2>&1; then
    if otool -l "$work/plain.bin" 2>/dev/null | grep -q 'sectname __cstring'; then
      note '§3 NUL-free module keeps __TEXT,__cstring (S_CSTRING_LITERALS)'
    else
      bad '§3 a NUL-free module no longer ships __TEXT,__cstring — the section choice stopped being a consequence of the literals and became a new default'
    fi
    if otool -l "$work/embed.bin" 2>/dev/null | grep -q 'sectname __conststr'; then
      note '§3 NUL-bearing module moves to __TEXT,__conststr (S_REGULAR, ld copies it whole)'
    else
      bad '§3 the NUL-bearing module did NOT move out of the coalescing section — §1 is passing for some other reason than the repair'
    fi
  else
    note '§3 otool absent — section placement not measured on this host'
  fi
fi

# ─── §3a both data sections present at once ────────────────────────────────
# THE SECTION COUNT IS ARITHMETIC, and a new section is exactly where that
# arithmetic breaks. `__const` (determined tables) derives its index and its
# base address from whether the literal blob's section exists, and `bssBaseAddr`
# derives a third address from both. A module carrying an interior NUL AND a
# determined table exercises all three at once: if any derivation still assumes
# the literal blob is named `__cstring`, or counts sections differently, an
# `adrp/add` lands on the wrong word and the table read answers garbage.
cat > "$work/mixed.id" <<'ID'
main: i64 = ()
  s: str = "a\0b"
  t = { 11, 22, 33 }
  i = s:len()
  v = t[i]
  print("{i} {v} {s:byte(3)}")
  0
ID
if build mixed; then
  run '§3a direct' "$work/mixed.bin";           mixdirect=$ans
  run '§3a wasm' "$wasmrun" "$work/mixed.wasm"; mixwasm=$ans
  [ "$mixdirect" = '3 33 98' ] || bad "§3a direct, NUL literal beside a determined table: got '$mixdirect', expected '3 33 98'"
  [ "$mixwasm" = '3 33 98' ] || bad "§3a wasm, NUL literal beside a determined table: got '$mixwasm', expected '3 33 98'"
  if command -v otool >/dev/null 2>&1; then
    secs=$(otool -l "$work/mixed.bin" 2>/dev/null | grep -c 'sectname __const$')
    blob=$(otool -l "$work/mixed.bin" 2>/dev/null | grep -c 'sectname __conststr')
    if [ "$secs" -lt 1 ] || [ "$blob" -lt 1 ]; then
      bad "§3a the two data sections did not both ship (__const $secs, __conststr $blob) — §3a's subject is not the one it claims"
    fi
  fi
  [ "$mixdirect" = '3 33 98' ] && [ "$mixwasm" = '3 33 98' ] && note "§3a NUL literal beside a determined table, both realizations: $mixdirect"
fi

# ─── §3b the digest comparison itself, in BOTH directions ──────────────────
# A BYTE CLAIM NEEDS A LIVE COMPARISON. §3 reads the section by name; the claim
# that a NUL-free module is otherwise UNTOUCHED is a claim about bytes, and a
# digest that cannot tell two different programs apart would confirm it
# vacuously. So both directions are measured here, with no baseline compiler
# needed:
#
#   1. the same source compiled twice, into two different output paths, is
#      byte-identical — the output path is not baked in, so a difference below
#      is a difference in the PROGRAM;
#   2. the same source with one interior NUL added is NOT byte-identical — the
#      literal-coalescing decision is a function of the literals, so it must be
#      visible in the artifact.
#
# The SOURCE path is held fixed across all three, because home mangling puts it
# into symbols: arm 1's two runs share one source file, and arm 2's subject sits
# beside it under the same stem length. A comparison across two scratch
# directories would differ in every byte and measure nothing.
if command -v shasum >/dev/null 2>&1; then
  printf 'main: i64 = ()\n  s: str = "abc"\n  print(s:len())\n  0\n' > "$work/dgone.id"
  printf 'main: i64 = ()\n  s: str = "a\\0c"\n  print(s:len())\n  0\n' > "$work/dgtwo.id"
  ok=1
  for m in dgone dgtwo; do
    "$idol" compile --no-cache --emit=obj -o "$work/$m.a.o" "$work/$m.id" >/dev/null 2>&1 || ok=0
  done
  "$idol" compile --no-cache --emit=obj -o "$work/dgone.b.o" "$work/dgone.id" >/dev/null 2>&1 || ok=0
  if [ "$ok" -eq 0 ]; then
    bad '§3b the digest subjects did not compile — the byte claim is unmeasured, which is not the same as confirmed'
  else
    d1=$(shasum -a 256 "$work/dgone.a.o" | cut -d' ' -f1)
    d2=$(shasum -a 256 "$work/dgone.b.o" | cut -d' ' -f1)
    d3=$(shasum -a 256 "$work/dgtwo.a.o" | cut -d' ' -f1)
    # A DIGEST THAT DID NOT RUN COMPARES EQUAL TO ANOTHER ONE THAT DID NOT RUN.
    # `$(cmd | cut)` is `cut`'s status, so a failed `shasum` leaves three empty
    # strings, arm 1 reads them as identical and arm 2 as identical too — the
    # second catches it today by accident, and an accident is not a control.
    if [ -z "$d1" ] || [ -z "$d2" ] || [ -z "$d3" ]; then
      bad '§3b a digest came back EMPTY — shasum answered nothing and three nothings compare equal, which is not a byte claim'
    elif [ "$d1" != "$d2" ]; then
      bad '§3b the SAME source compiled twice into two output paths differs — realization is not deterministic here, so no byte-identity claim in this tree is readable'
    elif [ "$d1" = "$d3" ]; then
      bad '§3b adding an interior NUL changed NOTHING in the object — the digest cannot see the decision it is being used to confirm'
    else
      note '§3b digest live in both directions: same source twice -> identical, one added NUL -> different'
    fi
  fi
else
  note '§3b shasum absent — the digest control did not run'
fi

# ─── §4 the boundary, pinned as answers ────────────────────────────────────
# WHAT IS STILL WRONG, STATED AS A MEASUREMENT. Text whose bytes are not
# determined travels as a bare `const char*`, so every libc consumer still
# stops at the first NUL. These four rows are LOSSES against the oracle
#
#     luajit: a\0b / 3 / 4 / noteqa
#
# and they are pinned so the day one moves — repaired or broken — this gate
# reports it instead of a comment nobody reads. Raise the pins WITH the repair.
cat > "$work/boundary.id" <<'ID'
main: i64 = ()
  s: str = "a\0b"
  print(s)
  t = s:sub(1, 3)
  print(t:len())
  u = "{s}!"
  print(u:len())
  if s == "a"
    print("eqa")
  else
    print("noteqa")
  0
ID
# Known-today answers. Each line is a LOSS: the oracle says a\0b / 3 / 4 / noteqa.
pinned='a
1
2
eqa'
if build boundary; then
  run '§4 direct' "$work/boundary.bin";           bdirect=$ans
  run '§4 wasm' "$wasmrun" "$work/boundary.wasm"; bwasm=$ans
  if [ "$bdirect" != "$bwasm" ]; then
    bad "§4 the realizations disagree on the UNREPAIRED path too: direct '$(printf %s "$bdirect" | tr '\n' '/')' vs wasm '$(printf %s "$bwasm" | tr '\n' '/')'"
  fi
  if [ "$bdirect" != "$pinned" ]; then
    bad "§4 the pinned boundary MOVED: got '$(printf %s "$bdirect" | tr '\n' '/')', pinned '$(printf %s "$pinned" | tr '\n' '/')'. If this is the repair, raise the pin in the same diff and say which relation now carries its length."
  else
    note '§4 boundary pinned: print/:sub/../== all still truncate at the NUL, identically on both realizations (oracle: a\0b / 3 / 4 / noteqa)'
  fi
fi

# ─── §0 a gate that measured nothing must FAIL ─────────────────────────────
# Placed after the subjects and before the structural scans for the reason
# `gate/divisor.sh` records: enumerating zero subjects and exiting 0 is the
# recurring defect in this tree, and it is worse than a red gate because a
# reader sees a green line and believes something ran.
if [ "$measured" -eq 0 ]; then
  bad '§0 measured ZERO programs — every subject failed to build, so nothing above is a finding'
elif [ "$measured" -lt 5 ]; then
  bad "§0 measured only $measured of 5 subjects"
else
  note "§0 measured $measured subjects on both realizations"
fi
[ "$fail" -eq 0 ] || { note 'NUL BLOCKED.'; exit 1; }

# ─── §5 one producer for each fact ─────────────────────────────────────────
# §1-§4 prove the answers are right. They cannot see whether the length fact is
# stated once or copied to each consumer, and a copied membership test is how
# `gate/divisor.sh` §6's defect arrived. Both facts must have exactly one
# producer that the consumers ASK.
cd "$root" || { printf 'nul: cannot enter $root (%s)\n' "$root" >&2; exit 2; }

subject() {
  [ -f "$1" ] && return 0
  bad "§5 $1 does not exist — a scan with no subject is not a count of zero"
  return 1
}

if subject src/dnir_lower.zig; then
  producers=$(grep -c 'fn determinedTextLen' src/dnir_lower.zig || true)
  asks=$(grep -c 'determinedTextLen(ctx' src/dnir_lower.zig || true)
  emits=$(grep -c '\.op = \.str_len' src/dnir_lower.zig || true)
  if [ "$producers" -ne 1 ]; then
    bad "§5 src/dnir_lower.zig declares determinedTextLen $producers times — the determined length must have exactly one producer"
  elif [ "$asks" -lt "$emits" ]; then
    bad "§5 src/dnir_lower.zig emits str_len at $emits sites but asks determinedTextLen at only $asks — a site that scans to NUL without asking whether the length is already known is the original defect"
  else
    note "§5 determined length: 1 producer, asked at $asks of $emits str_len sites"
  fi
fi

if subject src/native_backend.zig; then
  decides=$(grep -c 'coalescable = false' src/native_backend.zig || true)
  carried=$(grep -c 'cstring_coalescable' src/native_backend.zig || true)
  if [ "$decides" -ne 1 ]; then
    bad "§5 src/native_backend.zig decides literal coalescing at $decides sites — the section type must be decided once, where the literals are known"
  elif [ "$carried" -lt 3 ]; then
    bad "§5 the coalescing fact is spelled only $carried times — it must be carried from the emitter to the section header, not re-derived from the blob, which cannot answer it"
  else
    note "§5 section choice: 1 decision, carried through $carried references"
  fi
  if grep -q '0x2); // S_CSTRING_LITERALS' src/native_backend.zig; then
    bad '§5 the section type is an unconditional S_CSTRING_LITERALS again — the fact stopped reaching the header'
  fi
fi

if [ "$fail" -eq 0 ]; then
  note 'NUL OK — an embedded NUL is a byte of the value on both realizations, and both answer the oracle.'
  exit 0
fi
note 'NUL BLOCKED.'
exit 1
