#!/bin/sh
# BYTE COMPARISON IS NOT SAFE BY DEFAULT, and this measures exactly how far it
# is safe. Several lanes compare artifact bytes to decide whether a change had
# an effect — AST-provenance sovereignty, occurrence identity, Native/Wasm
# convergence, observer demand. A comparison whose baseline is unstable cannot
# distinguish a real effect from build noise, and one lane already could not
# answer whether `--observer` changes realization for exactly that reason.
#
# The answer this gate pins, measured rather than assumed:
#
#   OBJECT      (`--emit obj`, `--backend=direct`) is stable across processes
#               and independent of the OUTPUT path. Safe to diff.
#   EXECUTABLE  (linked) is stable across processes and across DIRECTORIES, but
#               NOT across output BASENAMES. arm64 macOS binaries are ad-hoc
#               code-signed, the signature's Identifier IS the output basename,
#               the CDHash covers it, and `ld` derives LC_UUID from the output
#               path. Two identical programs written to `a.out` and `b.out`
#               differ, and always will. NO BYTE COUNT IS WRITTEN DOWN: §4
#               asserts only that they DIFFER, so a figure here would be prose
#               the runner does not defend and could drift with the toolchain.
#               `codesign -dvvv` and the load commands give it for a given one.
#   SOURCE      the SOURCE path is mangled into every symbol
#               (`_idol_private_tmp_..._arith__main`), so the same program read
#               from two directories, or under two filenames, emits different
#               symbols and therefore different bytes. This is the hazard that
#               matters, because it scales with symbol count: a large module
#               compiled from two scratch directories differs almost everywhere.
#
#   => Hold the SOURCE path fixed across arms and diff OBJECTS. If you must diff
#      executables, hold the output BASENAME fixed too and vary the directory.
#
# Measured on `--backend=direct` only. Wasm and the C route are NOT covered;
# re-establish the baseline there before diffing bytes on either.
#
# FIVE SECTIONS, and §4/§5 are what stop this passing vacuously — each pins a
# comparison that must still be able to SEE a difference:
#
#   §1 SUBJECTS    the corpus is enumerated and a zero refuses.
#   §2 OBJECT      same source path, separate processes, DIFFERENT output
#                  BASENAMES *and* a DIFFERENT output DIRECTORY -> bytes must be
#                  IDENTICAL on both dimensions, which is what "path
#                  independent" has to mean to be usable.
#   §3 DIRECTORY   linked executable, same basename, different directory ->
#                  bytes must be IDENTICAL.
#   §4 CONTROL     linked executable, DIFFERENT basenames -> bytes must DIFFER.
#   §5 SOURCE      identical content from two source directories, and under two
#                  source filenames -> bytes must be IDENTICAL: the source path
#                  no longer reaches the symbols, and no emitted symbol may
#                  carry it, so the cause is exhibited and not inferred.
set -eu
root=${BYTESTABLEROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)}
if [ "${IDOL_LOCK_HELD:-0}" != 1 ]; then
    exec "$root/tools/node/dev/idol-lock" -- "$0" "$@"
fi
idol=${IDOL_BIN:-"$root/zig-out/bin/idol"}

# SIGKILL LEAVES THIS DIRECTORY BEHIND, and that is the accepted outcome. `trap`
# cannot catch signal 9, so a killed run leaks one `idol-byte-stable.XXXXXX`
# under TMPDIR until the OS reclaims it (per-user `/var/folders/.../T`, swept by
# `periodic daily`). A startup sweep of the prefix is deliberately REFUSED: gates
# in this tree run concurrently from several worktrees under one TMPDIR, each
# holding a repo-local lock that says nothing about the others, so a sweep would
# delete a live sibling's working directory and corrupt its run. Leaking a few
# kilobytes the OS already collects is the cheaper failure. 32 of the 35
# temp-using gates here use this exact pattern and none sweeps.
work=$(mktemp -d "${TMPDIR:-/tmp}/idol-byte-stable.XXXXXX")
cleanup() { rm -rf "$work"; }
trap cleanup EXIT INT TERM
fail() { printf 'byte/stable gate: FAIL %s\n' "$1" >&2; exit 1; }
[ -x "$idol" ] || fail "compiler is not executable: $idol"

# AN UNSUPPORTED HOST IS A REFUSAL, NOT A SKIP. The first version of this file
# printed `SKIP` and exited 0 here, which is indistinguishable from a measured
# baseline to the only thing that reads it: `gate/all.sh` discards gate output
# (`sh "$gate" >/dev/null 2>&1`) and counts every zero exit as a pass. There is
# no skip protocol in that runner to opt into. So on a host where the direct
# backend emits no artifact to compare, this gate has NOT MEASURED its subject
# and says so with a refusal status. No gate in this home exits 0 for a host it
# could not measure; the four that print SKIP do so only under an explicit
# `--census-only` / `--static-only` flag, where the CALLER asked for the
# reduced run.
#
# IT ASKED `uname` AND HARDCODED Darwin/arm64, which is the one spelling of this
# check that goes stale in the WRONG DIRECTION: the supported-triple set belongs
# to the compiler and has changed before, so the day an x86-64 realization lands
# this gate would keep refusing on a host that could measure — and it would keep
# doing so silently, because a refusal here reads as expected. The producer asks
# the compiler and reads the DNB004 identity instead.
. "$root/gate/realization/direct.sh"
direct_native_probe "$idol"
if direct_native_absent; then
    direct_native_note 'the byte-stability baseline (there is no artifact to compare)'
    exit 2
fi

# ---------------------------------------------------------------- §1 SUBJECTS
# One file per construct, written here rather than referenced, so the gate
# cannot start measuring a corpus that drifted out from under it.
mkdir -p "$work/src"
subjects=''
plant() {
    printf '%s\n' "$2" >"$work/src/$1.id"
    subjects="$subjects $1"
}
plant arith 'main: i64 = ()
    x = 6
    y = 7
    x * y + 3'
plant call 'twice: i64 = (n: i64)
    n + n

main: i64 = ()
    twice(20) + twice(1)'
plant projection 'main: i64 = ()
    row = { 11, 22, 33 }
    row[2] + row[3]'
plant text 'main: i64 = ()
    s = "abcdef"
    stdout:write(s)
    s:len()'
plant loop 'main: i64 = ()
    total = 0
    i = 1
    while i <= 5
        total += i
        i += 1
    total'

count=0
for s in $subjects; do count=$((count + 1)); done
[ "$count" -gt 0 ] || fail "§1 enumerated zero subjects; a census of nothing is not a baseline"

sum() { shasum -a 256 "$1" | cut -d' ' -f1; }

# ------------------------------------------------------------------ §2 OBJECT
# `--no-cache` because the build cache would hand back the same file and the
# comparison would be measuring the cache, not the emitter.
#
# THE OUTPUT PATH HAS TWO DIMENSIONS AND BOTH ARE EXERCISED. An earlier version
# varied only the BASENAME, with both objects written into one directory, and
# then the header claimed output-PATH independence — a claim one dimension wider
# than the measurement. If object emission ever started folding in the parent
# directory (the linker already does, for `LC_UUID`), that gate would still have
# passed while every consumer following its advice compared noisy objects. So
# each subject is emitted three times: two basenames in one directory, and the
# first basename again in a DIFFERENT directory. All three must be identical.
mkdir -p "$work/objA" "$work/objB"
objects=0
for s in $subjects; do
    "$idol" compile --no-cache --emit obj -o "$work/objA/alpha.o" "$work/src/$s.id" >/dev/null 2>&1 ||
        fail "§2 $s: object emission failed"
    "$idol" compile --no-cache --emit obj -o "$work/objA/verylongerdifferentname.o" "$work/src/$s.id" >/dev/null 2>&1 ||
        fail "§2 $s: object emission failed on the second name"
    "$idol" compile --no-cache --emit obj -o "$work/objB/alpha.o" "$work/src/$s.id" >/dev/null 2>&1 ||
        fail "§2 $s: object emission failed in the second output directory"
    a=$(sum "$work/objA/alpha.o")
    b=$(sum "$work/objA/verylongerdifferentname.o")
    c=$(sum "$work/objB/alpha.o")
    [ "$a" = "$b" ] ||
        fail "§2 $s: OBJECT BYTES ARE NOT STABLE across processes/output BASENAMES ($a vs $b) -- every lane diffing objects is now measuring noise"
    [ "$a" = "$c" ] ||
        fail "§2 $s: OBJECT BYTES DEPEND ON THE OUTPUT DIRECTORY ($a vs $c) -- this gate's header claims path independence and it is no longer true; re-measure before any lane diffs objects from two directories"
    objects=$((objects + 1))
done
[ "$objects" -eq "$count" ] || fail "§2 measured $objects of $count subjects"

# --------------------------------------------------------------- §3 DIRECTORY
mkdir -p "$work/one" "$work/two"
dirs=0
for s in $subjects; do
    "$idol" compile --no-cache -o "$work/one/same.out" "$work/src/$s.id" >/dev/null 2>&1 ||
        fail "§3 $s: link failed"
    "$idol" compile --no-cache -o "$work/two/same.out" "$work/src/$s.id" >/dev/null 2>&1 ||
        fail "§3 $s: link failed in the second directory"
    a=$(sum "$work/one/same.out")
    b=$(sum "$work/two/same.out")
    [ "$a" = "$b" ] ||
        fail "§3 $s: EXECUTABLE BYTES DIFFER for the same basename in two directories ($a vs $b) -- the safe comparison recorded in this gate's header is no longer safe"
    dirs=$((dirs + 1))
done
[ "$dirs" -eq "$count" ] || fail "§3 measured $dirs of $count subjects"

# ----------------------------------------------------------------- §4 CONTROL
# The positive control, and the reason §2 and §3 mean something. If the two
# names below ever produce identical bytes, this comparison has stopped being
# able to see a difference at all, and the two passes above are worthless.
"$idol" compile --no-cache -o "$work/one/aaaa.out" "$work/src/arith.id" >/dev/null 2>&1 ||
    fail "§4 link failed"
"$idol" compile --no-cache -o "$work/one/bbbb.out" "$work/src/arith.id" >/dev/null 2>&1 ||
    fail "§4 link failed on the second name"
a=$(sum "$work/one/aaaa.out")
b=$(sum "$work/one/bbbb.out")
if [ "$a" = "$b" ]; then
    # This is a WIN, not a failure of the compiler — but it invalidates the
    # header above and must be re-measured before the ledger is rewritten.
    fail "§4 CONTROL: two different output basenames produced IDENTICAL bytes. Either the ad-hoc signature identity stopped tracking the basename (re-measure and rewrite this gate's header), or this comparison can no longer see any difference (in which case §2 and §3 proved nothing)."
fi

# ------------------------------------------------------------------ §5 SOURCE
# Source-path independence, pinned in BOTH of its faces, with the cause
# exhibited. Identical source from different directories or under different
# filenames must emit identical bytes; no emitted symbol may carry the path.
# If either comparison ever comes back different, path mangling returned and
# the rule in this gate's header must be re-measured before anyone relies on
# it.
mkdir -p "$work/aa" "$work/bbbbbbbb"
cp "$work/src/arith.id" "$work/aa/arith.id"
cp "$work/src/arith.id" "$work/bbbbbbbb/arith.id"
cp "$work/src/arith.id" "$work/aa/zzzzzzzzzz.id"
"$idol" compile --no-cache --emit obj -o "$work/s1.o" "$work/aa/arith.id" >/dev/null 2>&1 ||
    fail "§5 object emission failed"
"$idol" compile --no-cache --emit obj -o "$work/s2.o" "$work/bbbbbbbb/arith.id" >/dev/null 2>&1 ||
    fail "§5 object emission failed from the second directory"
"$idol" compile --no-cache --emit obj -o "$work/s3.o" "$work/aa/zzzzzzzzzz.id" >/dev/null 2>&1 ||
    fail "§5 object emission failed under the second filename"
[ "$(sum "$work/s1.o")" = "$(sum "$work/s2.o")" ] ||
    fail "§5 identical source in two DIRECTORIES produced different bytes; the source path reaches the symbols"
[ "$(sum "$work/s1.o")" = "$(sum "$work/s3.o")" ] ||
    fail "§5 identical source under two FILENAMES produced different bytes; the source path reaches the symbols"
# Exhibit the cause rather than inferring it from a hash identity.
nm "$work/s1.o" 2>/dev/null | grep -q '_aa_' &&
    fail "§5 an emitted symbol carries the source path; the byte identity above has some OTHER cause and the header is wrong"

printf 'byte/stable gate: %d subject(s). object bytes: stable across processes, output basenames and output directories.\n' "$count"
printf 'byte/stable gate: executable bytes: basename-sensitive (ad-hoc signature identity + LC_UUID).\n'
printf 'byte/stable gate: source path reaches no symbol -- builds are source-path independent.\n'
printf 'byte/stable gate: OK.\n'
