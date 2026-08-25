#!/bin/sh
# gate/occurrence/copy.sh — A TRANSFORMATION MAY COPY AN INSTRUCTION. IT MAY
# NOT COPY AN OCCURRENCE.
#
# ═══ WHAT THIS GATE IS FOR ═════════════════════════════════════════════════
#
# Two transformations in this compiler turn one source loop into more than one
# physical occurrence of its body:
#
#   dnir_lower.emitUnrolledWhilePrologue    (src/dnir_lower.zig:5978)
#       copies the LOWERED INSTRUCTION RANGE factor-1 extra times
#       (src/dnir_lower.zig:6113-6119, through `unrollPhysicalCopy` :5969)
#       and leaves the ordinary lowering that follows as the residual.
#       Research-only: `IDOL_UNROLL` unset, empty,
#       `off`, `0`, `1` or malformed all leave the factor at 1.
#
#   dnir_lower.tryEmitVectorReductionPrologue  (src/dnir_lower.zig:7140)
#       emits a NEON group-sum AHEAD of the loop and lets the scalar loop run
#       as the residual. ON BY DEFAULT — both call sites
#       (src/dnir_lower.zig:4882, :6138) are live `try`.
#
# A copy is only lawful because of what it may NOT contain. `law.md` §11 gives
# a transformation exact input occurrence ids, replacement/result ids and
# machine lineage; this compiler has none of that, so both transforms are
# admitted on the opposite ground — they copy ONLY instructions that carry no
# graph identity at all, and every published application occurrence is
# therefore still realized exactly once.
#
# That is not documentation. It is enforced three times independently:
#
#   src/dnir_lower.zig:5698   `unrollExprIsCopyable` asks the graph's
#                             occurrence index and refuses the expression
#   src/dnir_lower.zig:5945   `unrollRangeIsCopyable` refuses any EMITTED
#                             instruction with .relation/.application/.value/
#                             .subject/.aggregate/.target/.realization_start
#   src/native_backend.zig:9181  `validateDnirApplications` refuses the whole
#                             module with `application-realization-count`
#
# MEASURED FAIL-CLOSED, not assumed. With BOTH `dnir_lower` refusals destroyed
# in a scratch build and `IDOL_UNROLL=4`, a loop whose body is a call does not
# produce a wrong answer — it refuses:
#
#   DNB011 application: 8 missing: application-realization-count
#   bail site: validateDnirApplications() at native_backend.zig:9181
#
# ═══ WHAT IT ASSERTS ═══════════════════════════════════════════════════════
#
#   §0  THE BYTE COMPARISON IS MEANINGFUL AT ALL. Every section below reads
#       an object digest, and a digest is evidence only if the emission is
#       reproducible and only if the digest can still move. Both halves are
#       measured before anything else runs.
#   §1  BOTH copying transforms actually fire. A gate that measures a
#       transform that never runs is measuring nothing, and this one would
#       have passed vacuously for as long as `tryEmitVectorReductionPrologue`
#       sat behind `if (false)`.
#   §2  The opt-in copy is OFF by default. `IDOL_UNROLL` unset, `1` and `off`
#       must produce byte-identical objects.
#   §3  Copies answer what the uncopied program answers, and the vector arm is
#       not a folded constant wearing a lane's clothes.
#   §4  A LOOP WHOSE BODY IS A PUBLISHED OCCURRENCE IS NOT COPIED. Bytes at
#       `IDOL_UNROLL=4` identical to bytes at the default.
#
# Exit 0 pass, 1 fail, 64 setup.
set -u

repo=$(unset CDPATH; cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repo" || exit 64

idol=./zig-out/bin/idol
[ -x "$idol" ] || { echo "gate/occurrence/copy.sh: no $idol — run zig build" >&2; exit 64; }

work=$(mktemp -d "${TMPDIR:-/tmp}/idoloccurrence.XXXXXX") || exit 64
trap 'rm -rf "$work"' EXIT INT TERM

unroll_subject=examples/native_differential/p02_loop.id
reduce_subject=gate/occurrence/reduce.id
occurrence_subject=gate/occurrence/callloop.id
for f in "$unroll_subject" "$reduce_subject" "$occurrence_subject"; do
    [ -r "$f" ] || { echo "gate/occurrence/copy.sh: missing subject $f" >&2; exit 64; }
done

fail=0
note() { printf '%s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }

# Every section here compares object digests, and the objects come from the
# direct backend. Without it §0 refuses and the whole gate printed
# "§0 subject refuses" — five words that name neither the host nor the backend,
# and that read as a defect in the subject rather than an absent realization.
. "$repo/gate/realization/direct.sh"
direct_native_probe "$idol"
if direct_native_absent; then
    direct_native_note 'the object-digest census needs direct-backend emission, and there is none to digest'
    exit 2
fi

# Emit one object and print its digest. An emission that refuses prints
# nothing, so every comparison below fails loudly rather than comparing two
# empty strings to each other.
obj() {
    _sub=$1; _out=$2
    "$idol" compile "$_sub" --backend=direct --emit=obj -o "$_out" >/dev/null 2>&1 || return 1
    [ -s "$_out" ] || return 1
    shasum -a 256 "$_out" | cut -d' ' -f1
}

# ═══ §0  THE DIGEST IS EVIDENCE ════════════════════════════════════════════
#
# "BYTES IDENTICAL" ON A NONDETERMINISTIC ARTIFACT IS LUCK, NOT EVIDENCE, and
# every other section here compares digests. So the comparison proves itself
# first, in both directions.
#
# REPRODUCIBLE. The same subject emitted twice, into two DIFFERENT output
# paths, must give one digest. Two different paths rather than two runs to one
# path, because the failure worth catching is an output path baked into the
# artifact: a gate that plants its subject in a fresh scratch directory per arm
# would then see every byte move and read it as a realization change. Measured
# here over the whole example corpus at this head — 219 emitted objects, two
# independent sweeps into different directories, 219 identical.
#
# STILL SENSITIVE. The same SOURCE compiled from a different SOURCE path must
# give a DIFFERENT digest, because home mangling puts the source path in every
# symbol (`_idol_<mangled path>__main`). That is the one real path hazard in
# this tree, it is a fact about identity rather than noise, and stating it as a
# required difference is what stops §2 and §4 from passing on two artifacts
# that are equal for an uninteresting reason.

det_a=$work/deta; det_b=$work/detb
mkdir -p "$det_a" "$det_b" || exit 64
d1=$(obj "$unroll_subject" "$det_a/same.o") || {
    echo "gate/occurrence/copy.sh: §0 subject refuses" >&2; exit 64; }
d2=$(obj "$unroll_subject" "$det_b/othername.o") || {
    echo "gate/occurrence/copy.sh: §0 subject refuses" >&2; exit 64; }
if [ "$d1" = "$d2" ]; then
    note "ok  §0a emission reproduces across two output paths"
else
    bad "§0a NONDETERMINISTIC emission — every byte comparison below is luck"
fi

cp "$unroll_subject" "$det_a/moved.id" || exit 64
d3=$(obj "$det_a/moved.id" "$det_a/moved.o") || {
    echo "gate/occurrence/copy.sh: §0 moved subject refuses" >&2; exit 64; }
if [ "$d3" != "$d1" ]; then
    note "ok  §0b the digest still moves when the SOURCE path does (home mangling)"
else
    bad "§0b the digest did not move for a different source path — it is not measuring the artifact"
fi

# ═══ §1  BOTH COPYING TRANSFORMS FIRE ══════════════════════════════════════

d_default=$( (unset IDOL_UNROLL; obj "$unroll_subject" "$work/u.default.o") ) || {
    echo "gate/occurrence/copy.sh: $unroll_subject refuses at the default" >&2; exit 64; }
d_four=$( (IDOL_UNROLL=4; export IDOL_UNROLL; obj "$unroll_subject" "$work/u.four.o") ) || {
    echo "gate/occurrence/copy.sh: $unroll_subject refuses at IDOL_UNROLL=4" >&2; exit 64; }

if [ "$d_default" = "$d_four" ]; then
    bad "§1a the unroll copy did not fire: $unroll_subject is byte-identical at IDOL_UNROLL=4"
else
    note "ok  §1a unroll copy fires (IDOL_UNROLL=4 changes $unroll_subject)"
fi

if "$idol" compile "$reduce_subject" --backend=direct --emit=asm -o "$work/reduce.s" >/dev/null 2>&1 &&
   grep -q 'add\.2d' "$work/reduce.s"; then
    note "ok  §1b vector reduction copy fires by default (add.2d emitted)"
else
    bad "§1b no add.2d in the default emission of $reduce_subject — tryEmitVectorReductionPrologue is unreachable again"
fi

# ═══ §2  THE OPT-IN COPY IS OFF BY DEFAULT ═════════════════════════════════
#
# A FACTOR IS NOT A BOOLEAN. `unrollFactorFromText` maps absence, "", "off",
# "0" and "1" all to factor 1, and each of those spellings is a separate way
# for the default to break. Comparing bytes, not the setting, is what makes
# this a measurement of the emitted program rather than of the parser.

for setting in 1 off 0 ''; do
    d=$( (IDOL_UNROLL="$setting"; export IDOL_UNROLL; obj "$unroll_subject" "$work/u.s.o") ) || {
        bad "§2 IDOL_UNROLL='$setting' refuses $unroll_subject"; continue; }
    if [ "$d" = "$d_default" ]; then
        note "ok  §2 IDOL_UNROLL='$setting' is byte-identical to the default"
    else
        bad "§2 IDOL_UNROLL='$setting' changed the emitted bytes — the copy is not off"
    fi
done

# ═══ §3  A COPY ANSWERS WHAT THE UNCOPIED PROGRAM ANSWERS ══════════════════

(unset IDOL_UNROLL; "$idol" compile "$unroll_subject" --backend=direct -o "$work/u.default.exe" >/dev/null 2>&1) &&
"$work/u.default.exe" >/dev/null 2>&1
a_default=$?
(IDOL_UNROLL=4; export IDOL_UNROLL; "$idol" compile "$unroll_subject" --backend=direct -o "$work/u.four.exe" >/dev/null 2>&1) &&
"$work/u.four.exe" >/dev/null 2>&1
a_four=$?
if [ "$a_default" = "$a_four" ]; then
    note "ok  §3a unrolled and rolled arms both answer $a_default"
else
    bad "§3a WRONG ANSWER: rolled $a_default, unrolled $a_four"
fi

"$idol" compile "$reduce_subject" --backend=direct -o "$work/reduce.exe" >/dev/null 2>&1 || {
    echo "gate/occurrence/copy.sh: $reduce_subject refuses" >&2; exit 64; }
env -u IDOLVECSEED "$work/reduce.exe" >/dev/null 2>&1
r_unset=$?
IDOLVECSEED=abcd "$work/reduce.exe" >/dev/null 2>&1
r_set=$?
# tbl = {1..8} with tbl[1] replaced by the seed length: 2+..+8 = 35, plus 0 or 4.
if [ "$r_unset" = 35 ] && [ "$r_set" = 39 ]; then
    note "ok  §3b vector arm sums real runtime data (35 unset, 39 seeded)"
else
    bad "§3b vector reduction answered $r_unset / $r_set, expected 35 / 39 — folded or wrong"
fi

# ═══ §4  AN OCCURRENCE IS NOT COPIED ═══════════════════════════════════════
#
# The subject's loop body is `t = t + bump()`, and `bump()` is a published
# application occurrence. `unrollExprIsCopyable` (:5698) asks `ctx.occurrences` — the
# same index `native_backend` counts realizations against — so the plan is
# declined by the producer's own record rather than by a guess about which
# syntax makes calls. Byte-identity is the whole assertion: not "it refuses",
# not "it warns", but "it emitted exactly the program it emits without the
# setting".

o_default=$( (unset IDOL_UNROLL; obj "$occurrence_subject" "$work/o.default.o") ) || {
    echo "gate/occurrence/copy.sh: $occurrence_subject refuses at the default" >&2; exit 64; }
o_four=$( (IDOL_UNROLL=4; export IDOL_UNROLL; obj "$occurrence_subject" "$work/o.four.o") ) || {
    bad "§4 $occurrence_subject refuses at IDOL_UNROLL=4"; o_four=; }
if [ -n "$o_four" ]; then
    if [ "$o_default" = "$o_four" ]; then
        note "ok  §4 a loop over a published occurrence is not copied (byte-identical)"
    else
        bad "§4 IDOL_UNROLL=4 COPIED A LOOP CONTAINING AN OCCURRENCE"
    fi
fi

if [ "$fail" = 0 ]; then
    echo "gate/occurrence/copy.sh: PASS"
    exit 0
fi
echo "gate/occurrence/copy.sh: FAIL"
exit 1
