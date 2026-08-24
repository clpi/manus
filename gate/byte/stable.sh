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
#   OBJECT      (`--emit obj`) is stable across processes AND independent of
#               the output path. Safe to diff, unconditionally.
#   EXECUTABLE  (linked) is stable across processes and across DIRECTORIES, but
#               NOT across output BASENAMES. arm64 macOS binaries are ad-hoc
#               code-signed, the signature's Identifier IS the output basename,
#               the CDHash covers it, and `ld` derives LC_UUID from the output
#               path. Two identical programs written to `a.out` and `b.out`
#               differ in ~52 bytes and always will.
#
#   => Diff objects. If you must diff executables, hold the BASENAME fixed and
#      vary the directory.
#
# FOUR SECTIONS, and §4 is what stops this passing vacuously:
#
#   §1 SUBJECTS    the corpus is enumerated and a zero refuses.
#   §2 OBJECT      same subject, separate processes, DIFFERENT output names ->
#                  bytes must be IDENTICAL.
#   §3 DIRECTORY   linked executable, same basename, different directory ->
#                  bytes must be IDENTICAL.
#   §4 CONTROL     linked executable, DIFFERENT basenames -> bytes must DIFFER.
#                  Without this the gate could pass by comparing nothing, and
#                  the known path sensitivity could silently appear or vanish
#                  without anyone noticing which.
set -eu
root=${BYTESTABLEROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/../.." && pwd)}
if [ "${IDOL_LOCK_HELD:-0}" != 1 ]; then
    exec "$root/tools/node/dev/idol-lock" -- "$0" "$@"
fi
idol=${IDOL_BIN:-"$root/zig-out/bin/idol"}

work=$(mktemp -d "${TMPDIR:-/tmp}/idol-byte-stable.XXXXXX")
cleanup() { rm -rf "$work"; }
trap cleanup EXIT INT TERM
fail() { printf 'byte/stable gate: FAIL %s\n' "$1" >&2; exit 1; }
[ -x "$idol" ] || fail "compiler is not executable: $idol"

case $(uname -s)/$(uname -m) in
    Darwin/arm64) : ;;
    *)
        # The direct backend emits AArch64 Mach-O and nothing else, so there is
        # no artifact to compare anywhere else. Say so rather than pass.
        printf 'byte/stable gate: SKIP -- direct-native artifacts exist only on Darwin/arm64\n'
        exit 0
        ;;
esac

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
plant call 'twice(n: i64): i64
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
objects=0
for s in $subjects; do
    "$idol" compile --no-cache --emit obj -o "$work/alpha.o" "$work/src/$s.id" >/dev/null 2>&1 ||
        fail "§2 $s: object emission failed"
    "$idol" compile --no-cache --emit obj -o "$work/verylongerdifferentname.o" "$work/src/$s.id" >/dev/null 2>&1 ||
        fail "§2 $s: object emission failed on the second name"
    a=$(sum "$work/alpha.o")
    b=$(sum "$work/verylongerdifferentname.o")
    [ "$a" = "$b" ] ||
        fail "§2 $s: OBJECT BYTES ARE NOT STABLE across processes/output names ($a vs $b) -- every lane diffing objects is now measuring noise"
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

printf 'byte/stable gate: %d subject(s); object bytes path-independent; executable bytes basename-sensitive by design.\n' "$count"
printf 'byte/stable gate: OK.\n'
