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
# So the divisor is `os.env["IDOLDIVZERO"]:len()` — a length the compiler cannot
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

# §1 and §2 EXECUTE the three binaries and read their exit codes, so a host
# that cannot build them measures nothing. This gate used to say
#     FAIL — idiv.id did not compile — the subject does not exist
# of a file it had written itself moments earlier: "does not exist" meant the
# BINARY, and read as the source. One producer for the host fact.
. "$root/gate/realization/direct.sh"
direct_native_probe "$idol"
if direct_native_absent; then
    direct_native_note 'the zero-divisor faults are read from three EXECUTED binaries, none of which can be built'
    exit 2
fi

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
  s: str = os.env["IDOLDIVZERO"]
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
  s: str = os.env["IDOLDIVZERO"]
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

# ─── §6 ONE PRODUCER, and it is a RATCHET rather than an assertion ─────────
# §1-§5 prove the obligation is COLLECTED. They cannot see whether it is
# collected in one place or five, and five is how it broke: the membership set
# `{/, //, %}` was spelled independently at the guard site, three times in
# `native_backend.zig`, and once in `demand.zig`. Adding `.idiv` to ONE of those
# five repairs the wrong answer and leaves the condition that produced it, so a
# gate that stops at §1 would go green on a tree that is still one enum-split
# away from the same defect.
#
# What this asserts is therefore STRUCTURAL: the realization consumers must ASK,
# and the two producers must EXIST. `gate/layers.manifest` forbids a BACKEND
# importing SEMA, so the one obligation cannot be one declaration — the IR side
# states it over `BinOpTag`, the meaning side over `ast.BinOp`, and the unit test
# `divisor obligation: IR and relation law agree` is what keeps them equal.
predicate='requiresNonzeroDivisor'

# A SPELLING IS CODE, NOT PROSE, AND IT IS THE EXACT SET. Two refinements this
# check needs in order to measure what it claims:
#
#   * comment lines are stripped. The repair's own commentary QUOTES the
#     retired list (`used to read tag == .div or tag == .mod`), and a gate that
#     counts its own explanation is measuring itself — `gate/all.sh` records the
#     same convention for its citation census.
#   * a SUPERSET is a different question. `dnir_lower.zig`'s width lattice reads
#     `.lshift, .rshift, .div, .idiv, .mod, .pow => .int64`, which is about how
#     wide a result is, not about who owes a divisor; `.pow` is in it and owes
#     nothing. So the match requires the set to END at `.mod`.
# §6 SCANS THE TREE, SO IT MUST SCAN THE RIGHT TREE. §1-§5 reach the compiler
# through `$root`; these scans used to name `src/...` relative to the CALLER's
# working directory. Invoked from outside the checkout that reads as "no such
# file", `2>/dev/null` swallowed it, `grep -c` answered 0, and a gate whose
# producers had all "disappeared" reported them absent rather than unfound —
# a clean zero from a scan that never ran. `gate/all.sh` masked it by cd-ing
# to the root first. Anchor the scans, and make a missing subject FATAL.
cd "$root" || { printf '%s\n' "divisor: cannot enter \$root ($root)" >&2; exit 2; }

# AND THE REFUSAL HAS TO REACH THE EXIT CODE. Refusing inside `spellings` was
# tried and is not enough: every call site reads it as `$(spellings ...)`, and a
# command substitution is a SUBSHELL, so the `fail=1` it set died with the
# subshell while the message still printed on stderr. Measured against a
# deliberately absent subject: the gate printed
# "FAIL — §6 src/doesnotexist.zig does not exist" and then "DIVISOR OK", exit 0.
# A gate that reports a failure and exits green is the same fabricated pass one
# level in, and it is worse, because a reader now has a FAIL line telling them
# the check ran. So existence is asserted by the CALLER, in the caller's shell,
# and `spellings` only counts.
subject() {
  [ -f "$1" ] && return 0
  bad "§6 $1 does not exist — a scan with no subject is not a count of zero"
  return 1
}

# `spellings` ANSWERS -1 RATHER THAN 0 FOR A SUBJECT IT CANNOT OPEN, so that a
# caller which forgot its `subject` assertion still cannot read "no such file"
# as "clean". Every comparison below treats a negative count as fatal in the
# CALLER's shell, which is the only shell whose `fail` survives.
spellings() {
  [ -f "$1" ] || { printf -- '-1\n'; return; }
  sed 's|//.*||' "$1" | grep -cE '\.div, \.idiv, \.mod *=>|tag == \.div' || true
}

for f in src/graph/lower.zig src/native.zig; do
  subject "$f" || continue
  spelled=$(spellings "$f")
  asks=$(grep -c "$predicate" "$f" 2>/dev/null || true)
  if [ "${spelled:-0}" -lt 0 ]; then
    bad "§6 $f could not be scanned — a scan with no subject is not a count of zero"
  elif [ "${spelled:-0}" -ne 0 ]; then
    bad "§6 $f spells the divisor set ${spelled} time(s) instead of asking \`$predicate\`. That is the shape the defect came in: a hand-kept member list at a consumer, which an enum split silently falsifies."
  elif [ "${asks:-0}" -eq 0 ]; then
    bad "§6 $f neither spells nor asks the obligation — it has stopped consulting it at all"
  else
    note "§6 $f: asks the obligation ${asks} time(s), spells it 0 times"
  fi
done

# THE IR PRODUCER, and that its switch is EXHAUSTIVE. Exhaustiveness is the
# structural half of the repair: an `if` chain lets a new tag slip through
# silently, which is exactly what happened, while a switch makes the compiler
# demand an answer. `tests.zig` line 97 records that the same tag split DID
# break exhaustive switches and that those were reported.
if ! subject src/native/ir.zig; then
  :
elif ! grep -q "pub fn $predicate" src/native/ir.zig; then
  bad "§6 src/native/ir.zig has no \`$predicate\` — the IR-side producer is gone"
elif ! grep -q '\.band, \.bor, \.bxor, \.shl, \.shr => false' src/native/ir.zig; then
  bad "§6 $predicate is no longer an exhaustive switch; a tag added to BinOpTag can slip through without deciding whether it divides"
else
  note "§6 src/native/ir.zig: IR producer present, switch exhaustive"
fi

# THE SEMA PRODUCER, for `sema` and `demand`, over `ast.BinOp`.
if ! subject src/demand_projection.zig; then
  :
elif ! grep -q 'divisor_nonzero' src/demand_projection.zig; then
  bad '§6 src/demand_projection.zig has no `divisor_nonzero` — the relation-law producer is gone'
else
  note '§6 src/demand_projection.zig: relation-law producer present'
fi

# `demand.zig` keeps ONE occurrence: the arm that holds the switch exhaustive,
# which routes to the same discharge helper and so cannot answer differently.
# A CEILING, not a target — lower it if the arm ever becomes unnecessary.
DEMAND_CEILING=1
demand_spellings=$(spellings src/demand.zig)
if [ "${demand_spellings:-0}" -lt 0 ]; then
  bad '§6 src/demand.zig could not be scanned — a scan with no subject is not a count of zero'
elif [ "${demand_spellings:-0}" -gt "$DEMAND_CEILING" ]; then
  bad "§6 src/demand.zig spells the divisor set ${demand_spellings} time(s), ceiling $DEMAND_CEILING"
else
  note "§6 src/demand.zig: ${demand_spellings} spelling(s), ceiling $DEMAND_CEILING"
fi

if [ "$fail" -eq 0 ]; then
  note 'DIVISOR OK — all three relations collect the obligation they are owed, and one producer states it.'
  exit 0
fi
note 'DIVISOR BLOCKED.'
exit 1
