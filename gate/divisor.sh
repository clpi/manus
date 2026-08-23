#!/bin/sh
# gate/divisor.sh — `/`, `//` and `%` all owe a NON-ZERO DIVISOR, and an opaque
# runtime zero must not slip past one of them.
#
# ═══ WHAT THIS GATE IS FOR ═════════════════════════════════════════════════
#
# `dnir_lower.lowerBinop` decided which applications get a runtime divisor-zero
# guard from a hand-kept list over the DNIR tag: `tag == .div or tag == .mod`.
# `//` used to lower to `.div`, so that list covered it by accident. Giving `//`
# its own tag so it could carry floor law dropped it out of the list, and
# AArch64 `sdiv` DOES NOT FAULT on a zero divisor — it answers 0. Measured
# before the repair, one binary per operator and the SAME opaque divisor:
#
#     7 // d, d = 0    printed 0, exit 0     <- WRONG ANSWER
#     7 /  d, d = 0    SIGABRT, exit 134
#     7 %  d, d = 0    SIGABRT, exit 134
#
# That is not a missing diagnostic. It is the fourth outcome docs/spec/
# soundness.md §1 says does not exist: accepted, unguarded, and wrong.
#
# ═══ WHY THE DIVISOR IS READ OUT OF THE ENVIRONMENT ════════════════════════
#
# A LITERAL ZERO DIVISOR PROVES NOTHING HERE and must never be used as this
# gate's subject. `sema.check_literal_zero_divisor` refuses `7 // 0` at compile
# time with a diagnostic, so a literal-zero probe exercises the compile-time
# arm and never reaches the code path that was broken. A folded zero is the
# same trap one step further in: the comptime folder would settle it and no
# guard would be emitted either way.
#
# So the divisor is `os.env("IDOLDIVZERO"):len()` — a length the compiler cannot
# read and cannot fold. §2 below is what makes that claim CHECKED rather than
# asserted: the SAME BINARY is run twice, once with the variable unset (an
# opaque runtime 0) and once with it set (an opaque runtime 2), and it must
# answer differently. A constant-folded divisor cannot do that, so if this gate
# ever starts passing because the compiler learned to fold `os.env`, §2 fails
# and says so instead of §1 passing vacuously.
#
# ═══ WHAT IT ASSERTS ═══════════════════════════════════════════════════════
#
#   §1  All three of `/`, `//`, `%` FAULT on an opaque runtime zero divisor.
#       `//` is the negative control this gate was written for; `/` and `%`
#       are the positive controls that were already correct and must stay so.
#   §2  The divisor is genuinely opaque: same binary, non-zero divisor, all
#       three compute the right answer. Also the no-regression check.
#   §3  Floor law survives the guard, over the full sign matrix, with opaque
#       operands: `//` is 3/-4/-4/3 and `%` is 1/1/-1/-1 at (7,2)(-7,2)(7,-2)
#       (-7,-2). Computed from Lua 5.4 §3.4.1, `a % b == a - floor(a/b)*b`.
#   §4  The direct backend and the comptime folder AGREE: the same matrix
#       written with literal operands, which the folder evaluates, must print
#       exactly what §3 printed. Two answers here is `comptime.zig`'s own
#       "backend 1, interpreter 0" divergence class returning.
#   §5  A LITERAL zero divisor is still a compile-time diagnostic for all
#       three, which is the arm §1 deliberately does not exercise.
set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
idol="${IDOL_BIN:-$root/zig-out/bin/idol}"
[ -x "$idol" ] || { echo "divisor: no compiler at $idol" >&2; exit 2; }

work="$(mktemp -d)" || exit 2
trap 'rm -rf "$work"' EXIT

fail=0
note() { printf 'divisor: %s\n' "$1"; }
bad()  { printf 'divisor: FAIL — %s\n' "$1" >&2; fail=1; }

# ─── subjects ──────────────────────────────────────────────────────────────
# One relation per operator so each fault is attributable to one operator.
for spec in 'idiv://' 'div:/' 'mod:%'; do
  name=${spec%%:*}
  op=${spec#*:}
  cat > "$work/$name.id" <<ID
# Opaque runtime divisor: the compiler cannot read an environment value.
main: i64 = ()
  s: str = os.env("IDOLDIVZERO")
  d = s:len()
  q: i64 = 7 $op d
  print(q)
  0
ID
  if ! "$idol" compile "$work/$name.id" -o "$work/$name.bin" >/dev/null 2>&1; then
    bad "$name.id did not compile — the subject does not exist, so nothing below is measured"
  fi
done
[ "$fail" -eq 0 ] || { note 'REFUSING to report on unbuilt subjects'; exit 1; }

# ─── §1 opaque runtime ZERO must fault, all three ──────────────────────────
for name in idiv div mod; do
  out=$(env -u IDOLDIVZERO "$work/$name.bin" 2>/dev/null)
  code=$?
  if [ "$code" -lt 128 ]; then
    bad "§1 $name: opaque runtime zero divisor did NOT fault — exit $code, printed '$out'. A zero divisor reached a bare sdiv and sdiv answers 0."
  else
    note "§1 $name: opaque zero divisor faults, exit $code"
  fi
done

# ─── §2 opaque runtime NON-ZERO: right answer, and the divisor is opaque ───
# `IDOLDIVZERO=xx` has length 2. Same binaries as §1.
for spec in 'idiv:3' 'div:3' 'mod:1'; do
  name=${spec%%:*}
  want=${spec#*:}
  got=$(IDOLDIVZERO=xx "$work/$name.bin" 2>/dev/null)
  code=$?
  if [ "$code" -ne 0 ]; then
    bad "§2 $name: non-zero divisor faulted — exit $code. The guard is firing on a divisor that is not zero."
  elif [ "$got" != "$want" ]; then
    bad "§2 $name: 7 op 2 = '$got', expected '$want'"
  else
    note "§2 $name: opaque divisor 2 -> $got (same binary as §1, which answered differently — the divisor is NOT folded)"
  fi
done

# ─── §3 floor law over the full sign matrix, opaque operands ───────────────
cat > "$work/matrix.id" <<'ID'
# The divisor magnitude is a length the compiler cannot read, so no row here
# is constant-folded. `n` is its negation, giving both divisor signs.
main: i64 = ()
  s: str = os.env("IDOLDIVZERO")
  d = s:len()
  n = 0 - d
  a: i64 = 7 // d
  b: i64 = -7 // d
  c: i64 = 7 // n
  e: i64 = -7 // n
  f: i64 = 7 % d
  g: i64 = -7 % d
  h: i64 = 7 % n
  i: i64 = -7 % n
  print("{a} {b} {c} {e} | {f} {g} {h} {i}")
  0
ID
expect='3 -4 -4 3 | 1 1 -1 -1'
if ! "$idol" compile "$work/matrix.id" -o "$work/matrix.bin" >/dev/null 2>&1; then
  bad '§3 sign matrix did not compile'
else
  opaque=$(IDOLDIVZERO=xx "$work/matrix.bin" 2>/dev/null)
  if [ "$opaque" != "$expect" ]; then
    bad "§3 floor law over opaque operands: got '$opaque', expected '$expect'"
  else
    note "§3 floor law over opaque operands: $opaque"
  fi
fi

# ─── §4 the comptime folder must answer what the backend answered ──────────
cat > "$work/folded.id" <<'ID'
# The SAME matrix with literal operands: the comptime folder evaluates these.
main: i64 = ()
  a: i64 = 7 // 2
  b: i64 = -7 // 2
  c: i64 = 7 // -2
  e: i64 = -7 // -2
  f: i64 = 7 % 2
  g: i64 = -7 % 2
  h: i64 = 7 % -2
  i: i64 = -7 % -2
  print("{a} {b} {c} {e} | {f} {g} {h} {i}")
  0
ID
if ! "$idol" compile "$work/folded.id" -o "$work/folded.bin" >/dev/null 2>&1; then
  bad '§4 folded matrix did not compile'
else
  folded=$("$work/folded.bin" 2>/dev/null)
  if [ "$folded" != "$expect" ]; then
    bad "§4 comptime folder disagrees with the law: got '$folded', expected '$expect'"
  elif [ "${opaque:-}" != "$folded" ]; then
    bad "§4 backend '$opaque' and folder '$folded' DISAGREE on the same arithmetic"
  else
    note "§4 backend and comptime folder agree: $folded"
  fi
fi

# ─── §5 a LITERAL zero divisor is still refused at compile time ────────────
for spec in 'litidiv://' 'litdiv:/' 'litmod:%'; do
  name=${spec%%:*}
  op=${spec#*:}
  cat > "$work/$name.id" <<ID
main: i64 = ()
  q: i64 = 7 $op 0
  print(q)
  0
ID
  if "$idol" check "$work/$name.id" 2>&1 | grep -q 'division by zero'; then
    note "§5 $name: literal zero divisor refused at compile time"
  else
    bad "§5 $name: literal zero divisor was NOT refused — the compile-time arm of the obligation is gone"
  fi
done

if [ "$fail" -eq 0 ]; then
  note 'DIVISOR OK — all three relations collect the obligation they are owed.'
  exit 0
fi
note 'DIVISOR BLOCKED.'
exit 1
