#!/bin/sh
# gate/decimal.sh — the value a decimal spelling NAMES must survive the whole
# way to the answer, and the spellings that break a decimal carrier must break
# it CLOSED.
#
# ═══ WHAT THIS GATE IS FOR ═════════════════════════════════════════════════
#
# `0.1` names one tenth. `f64` has no one tenth, so a compiler that ingests the
# spelling through `parseFloat` has destroyed the fact at the LEXER — before any
# binding, call, return or equality can carry it. Every later answer is then
# about a rounding, and `0.1 + 0.2 == 0.3` is false in a language whose own
# source says otherwise.
#
# THAT ROW ALONE IS NOT THE SUBJECT. A carrier can be made to answer it by
# recognizing the three spellings and folding, and such a carrier is worse than
# none: it answers the demonstration and still drops, traps or spins on the four
# spellings below, each of which is a real program someone can type.
#
#   1e-19                  a value, and one whose exponent no fixed scale holds
#   -9223372036854775808   an i64, and one whose MAGNITUDE is not an i64
#   0.0e-2147483648        zero, and one whose exponent underflows i32 when the
#                          fraction digit count is subtracted from it
#   0e+2147483647          zero, and one that materializing 10^e would spin on
#
# §3 measures all four THROUGH THE COMPILER, because the failure modes are
# process-level — a `null` where a value belongs, an integer-overflow trap, a
# loop that does not end — and none of them is visible to a unit test that has
# already decided which function to call.
#
# ═══ WHAT IT ASSERTS ═══════════════════════════════════════════════════════
#
#   §1  `examples/decimal/exact.id` answers `1 1 0` on an EXECUTED artifact.
#       The file is its own positive control: `apart` compares the same sum
#       against `0.30000000000000004`, which IS the f64 sum, so a carrier still
#       on f64 answers `0 0 1`. No single-value answer produces `1 1 0`.
#
#   §2  The three relations are separate hops — a local binding, two module
#       bindings through an operand pack and a return — so a carrier that holds
#       the fact at one seam and drops it at the next fails here rather than in
#       whichever program a user writes first.
#
#   §3  Each named carrier spelling compiles or is REFUSED with a diagnostic,
#       within a bounded time, and never traps. A refusal is a pass; a crash, a
#       timeout, or a silently wrong value is not.
#
#   §4  `1e-19` and `-9223372036854775808` are not merely accepted, they are
#       carried: the program distinguishes them from the values a dropped fact
#       would collapse them to (`0` and `0`).
#
#   §5  ORDER IS A SEAM TOO, and it opens exactly where two distinct values
#       share one f64: the realization holds ONE number for both and cannot
#       order them at all, while the values are strictly ordered.
set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
idol="${IDOL_BIN:-$root/zig-out/bin/idol}"
[ -x "$idol" ] || { echo "decimal: no compiler at $idol" >&2; exit 2; }

# THE ANSWER MUST BE EXECUTED, NOT REPORTED. `idol run` prints a completion on
# this host without running the program, so a gate that reads its output is
# measuring transport, not semantics.
wasmrun=""
for candidate in wasmtime wasmer; do
  if command -v "$candidate" >/dev/null 2>&1; then wasmrun="$candidate"; break; fi
done
[ -n "$wasmrun" ] || { echo "decimal: no wasm runner (wasmtime/wasmer) — this gate cannot execute its subject" >&2; exit 2; }

work="$(mktemp -d)" || exit 2
trap 'rm -rf "$work"' EXIT

fail=0
measured=0
note() { printf 'decimal: %s\n' "$1"; }
bad()  { printf 'decimal: FAIL — %s\n' "$1" >&2; fail=1; }

# ─── §1/§2 the executed answer ─────────────────────────────────────────────
subject="$root/examples/decimal/exact.id"
[ -f "$subject" ] || { echo "decimal: missing $subject" >&2; exit 2; }

if ! "$idol" compile --backend=wasm -o "$work/exact.wasm" "$subject" >"$work/exact.log" 2>&1; then
  bad "examples/decimal/exact.id did not compile for the wasm backend — §1 and §2 measure nothing"
  head -5 "$work/exact.log" >&2
else
  ans=$("$wasmrun" "$work/exact.wasm" 2>"$work/exact.err")
  ansrc=$?
  measured=$((measured + 1))
  if [ "$ansrc" -ne 0 ]; then
    bad "the artifact exited $ansrc — a status is half the answer and this half is wrong"
    head -3 "$work/exact.err" >&2
  fi
  got=$(printf '%s' "$ans" | tr '\n' ' ' | sed 's/ *$//')
  if [ "$got" = "1 1 0" ]; then
    note "§1/§2 exact decimal meaning survives the binding, the call, the return and the equality"
  elif [ "$got" = "0 0 1" ]; then
    bad "§1/§2 answered '$got' — that is the f64 rounding answering in the carrier's place"
  else
    bad "§1/§2 answered '$got', expected '1 1 0'"
  fi
fi

# ─── §3/§4 the named carriers, measured through the compiler ───────────────
# A subject here PASSES when the compiler answers the expected value AND when it
# refuses with a diagnostic. It FAILS when it traps, when it does not finish, or
# when it answers a different value — a wrong answer is the defect this gate is
# about and a refusal is not.
carrier() {
  cname=$1
  cwant=$2
  cbody=$3
  printf '%s\n' "$cbody" > "$work/$cname.id"
  timeout 30 "$idol" compile --backend=wasm -o "$work/$cname.wasm" "$work/$cname.id" >"$work/$cname.log" 2>&1
  crc=$?
  if [ "$crc" -eq 124 ]; then
    bad "§3 $cname did not finish in 30s — the carrier is iterating on an exponent"
    return
  fi
  if [ "$crc" -ge 128 ]; then
    bad "§3 $cname killed by signal $((crc - 128)) — the carrier trapped instead of declining"
    head -3 "$work/$cname.log" >&2
    return
  fi
  if [ "$crc" -ne 0 ]; then
    if grep -qi 'panic\|unreachable\|integer overflow\|index out of bounds' "$work/$cname.log"; then
      bad "§3 $cname refused by trapping, not by deciding"
      head -3 "$work/$cname.log" >&2
      return
    fi
    measured=$((measured + 1))
    note "§3 $cname refused with a diagnostic (fail-closed)"
    return
  fi
  ans=$(timeout 30 "$wasmrun" "$work/$cname.wasm" 2>"$work/$cname.err")
  ansrc=$?
  if [ "$ansrc" -eq 124 ]; then
    bad "§4 $cname artifact did not finish in 30s"
    return
  fi
  measured=$((measured + 1))
  got=$(printf '%s' "$ans" | tr '\n' ' ' | sed 's/ *$//')
  if [ "$got" = "$cwant" ]; then
    note "§4 $cname answered '$cwant'"
  else
    bad "§4 $cname answered '$got', expected '$cwant'"
  fi
}

# `1e-19` IS A VALUE. A carrier that normalizes to a fixed scale drops it, and
# the drop reads as `0`, so `vanished` asks the question the round trip cannot.
#
# `swallowed` is the row that separates the fact from the realization: `1e-19`
# is far below the ulp of `0.1`, so `0.1 + 1e-19 == 0.1` is TRUE in f64 and
# FALSE about the values. A carrier that dropped back to f64 answers 1 here.
carrier smallexp '1 0 0' '
holds: i64 = ()
  tiny = 1e-19
  if tiny == 1e-19
    1
  else
    0

vanished: i64 = ()
  tiny = 1e-19
  if tiny == 0.0
    1
  else
    0

swallowed: i64 = ()
  if 0.1 + 1e-19 == 0.1
    1
  else
    0

print(holds())
print(vanished())
print(swallowed())
'

# THE MAGNITUDE OF THE INTEGER FLOOR IS NOT AN INTEGER. `9223372036854775808`
# read into a SIGNED coefficient overflows, and the overflow reads as `0`.
#
# `holds` and `vanished` measure the exact-integer ingestion face, which the
# lexer already classified; `crowded` measures the DECIMAL carrier at the same
# magnitude, and it is the row that cannot be answered by a realization: both
# spellings round to the same f64, so f64 answers 1 and the values answer 0.
carrier intfloor '1 0 0' '
floorv: i64 = ()
  -9223372036854775808

holds: i64 = ()
  if floorv() == -9223372036854775808
    1
  else
    0

vanished: i64 = ()
  if floorv() == 0
    1
  else
    0

crowded: i64 = ()
  if 9223372036854775808.0 == 9223372036854775807.0
    1
  else
    0

print(holds())
print(vanished())
print(crowded())
'

# ZERO IS ZERO AT EVERY SCALE. Subtracting the fraction digit count from an
# exponent already at the i32 floor is the trap; the answer never needed the
# exponent at all.
carrier zerounder '1' '
holds: i64 = ()
  z = 0.0e-2147483648
  if z == 0.0
    1
  else
    0

print(holds())
'

# THE SAME FACT FROM THE OTHER END. Materializing 10^2147483647 to normalize is
# the spin.
carrier zeroover '1' '
holds: i64 = ()
  z = 0e+2147483647
  if z == 0.0
    1
  else
    0

print(holds())
'

# EQUALITY IS NOT THE ONLY SEAM. `0.1 + 0.2 <= 0.3` does NOT separate the two
# carriers — the exact sum's f64 projection IS the f64 nearest `0.3`, so asking
# the realization about an exact sum still answers correctly. The seam only
# opens where two DISTINCT values share one f64, and then the realization cannot
# order them at all because it holds one number for both.
#
# Both pairs below are one f64 and two values, so f64 calls them EQUAL and
# answers '0 0 1' — the exact inverse of the expected row.
carrier ordered '1 1 0' '
tight: i64 = ()
  if 0.1 < 0.1 + 1e-19
    1
  else
    0

crowded: i64 = ()
  if 9223372036854775807.0 < 9223372036854775808.0
    1
  else
    0

merged: i64 = ()
  if 0.1 >= 0.1 + 1e-19
    1
  else
    0

print(tight())
print(crowded())
print(merged())
'

# ─── the census ────────────────────────────────────────────────────────────
# A gate that measured nothing is not a gate that found nothing.
if [ "$measured" -eq 0 ]; then
  echo "decimal: FAIL — measured ZERO subjects; the report below is about nothing" >&2
  exit 1
fi
note "measured $measured subjects"
[ "$fail" -eq 0 ] || exit 1
note "PASS"
