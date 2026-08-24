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
  direct=$("$work/embed.bin" 2>/dev/null)
  wasm=$($wasmrun "$work/embed.wasm" 2>/dev/null)
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
  mdirect=$("$work/modscope.bin" 2>/dev/null)
  mwasm=$($wasmrun "$work/modscope.wasm" 2>/dev/null)
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
  got=$("$work/plain.bin" 2>/dev/null)
  [ "$got" = "len=3" ] || bad "§3 a NUL-free literal answered '$got', expected 'len=3'"
  gotw=$($wasmrun "$work/plain.wasm" 2>/dev/null)
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
  bdirect=$("$work/boundary.bin" 2>/dev/null)
  bwasm=$($wasmrun "$work/boundary.wasm" 2>/dev/null)
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
elif [ "$measured" -lt 4 ]; then
  bad "§0 measured only $measured of 4 subjects"
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
