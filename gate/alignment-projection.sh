#!/bin/sh
# gate/alignment-projection.sh — the compass counterfactual (GAP-133).
#
# Sibling of gate/table-projection.sh and gate/grammar-projection.sh: the same
# property, for docs/AGENT_ALIGNMENT.md. C0 law.semantic.service binds the
# constitution to generate the teaching corpus and fails independently
# handwritten copies; gaps/GAP-133.md records what a handwritten compass did
# with that freedom (deleted pass plans, a retired identity, a script that no
# longer existed, all taught as current). scripts/alignment_emit.id is the one
# producer of everything outside the compass's residue markers; this gate is
# the named live doc gate that makes hand drift a failure instead of a habit.
#
# WHY NOT a gate/generated.manifest row instead. The manifest's L2b co-change
# rule (gate/layering.sh) fails any diff that touches the projection without
# touching its generator. The compass's AUTHORED RESIDUE is the one region
# agents are supposed to edit by hand — dated mandates, the misunderstanding
# table — and those edits rightly change no generator. Byte-identity of a
# regeneration is the exact law here: a residue edit is carried verbatim and
# stays byte-identical, a frame edit or an unregenerated emitter change is
# not. So this gate asserts the sharper property directly, and the manifest
# row that would misfire on lawful residue edits is DELIBERATELY ABSENT.
#
# WHAT IS ASSERTED, in order:
#
#   §1  the compiler, a C compiler, the emitter and both documents exist
#                                                                (else exit 2)
#   §2  the emitter compiles through the dump-c bridge — the same executed
#       path gate/gap-114-boxed-len.sh binds evidence to on this host
#   §3  the tracked compass regenerates BYTE-IDENTICALLY in a scratch tree
#   §4  regeneration is IDEMPOTENT: a second run over the first run's output
#       changes nothing
#   §5  every repo-relative file the compass cites in backticks EXISTS —
#       the drift that was live at gate birth (`gate/selfhost.sh`, a sibling
#       tree's gate cited as a local one) cannot return silently
#
# CONTROLS run first, because a scanner that finds nothing is the recurring
# defect in this repository: a tampered frame must be caught, a citation of a
# law C0 does not carry must refuse, deleted residue markers must refuse, and
# the reference scan must see a planted absent file. `--selftest` runs only
# the compiler-free controls and exits.
#
# `--emit` regenerates docs/AGENT_ALIGNMENT.md in place and exits — the one
# documented way to update the projection after editing C0, the emitter, or
# the residue.
set -u

repo=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd) || exit 2
cd -- "$repo" || exit 2

FINDINGS=0
bad()  { FINDINGS=$((FINDINGS + 1)); printf 'alignment projection: FAIL — %s\n' "$*" >&2; }
info() { printf 'alignment projection: %s\n' "$*"; }
broke() { printf 'alignment projection: CANNOT MEASURE — %s\n' "$*" >&2; exit 2; }

C0=docs/spec/constitution.md
DOC=docs/AGENT_ALIGNMENT.md
EMITTER=scripts/alignment_emit.id

# ---------------------------------------------------------------------------
# THE REFERENCE SCANNER (§5). Backticked repo-relative file citations in $1,
# one per line: a suffix the tree tracks, no glob or placeholder characters,
# not a sibling-tree path (../), and not a bare suffix like `.id`. Prints the
# citations that do NOT exist; prints nothing when all resolve.
refscan() {
    grep -o '`[A-Za-z0-9._/-][A-Za-z0-9._/-]*`' "$1" 2>/dev/null \
        | tr -d '`' \
        | grep -E '\.(md|sh|id|zig|json|mdc)$' \
        | grep -v 'NN' \
        | grep -v '^\.\./' \
        | grep -v '^\.[A-Za-z0-9._-]*$' \
        | LC_ALL=C sort -u \
        | while IFS= read -r ref; do
              [ -e "$repo/$ref" ] || printf '%s\n' "$ref"
          done
}

# ---------------------------------------------------------------------------
# COMPILER-FREE CONTROLS. A gate that measures nothing passes; these prove
# the reference scanner measures before it reports a clean compass.
selftest() {
    _c=$(mktemp -d "${TMPDIR:-/tmp}/idol-alignment-control.XXXXXX") || exit 2
    _rc=0

    # C1 NEGATIVE — a planted citation of an absent gate is caught.
    printf 'Run `gate/absent-control.sh` before claiming progress.\n' >"$_c/planted.md"
    if [ -z "$(refscan "$_c/planted.md")" ]; then
        printf 'alignment projection control: FAIL — the reference scan missed a planted absent file\n' >&2
        _rc=1
    fi

    # C2 POSITIVE — resolvable and out-of-scope citations are not flagged.
    # `.id` bare-suffix, `../` sibling-tree and `GAP-0NN` placeholder shapes
    # are the exact false-positive classes measured in the live compass.
    { printf 'Start at `AGENTS.md`. A `.id` filename does not transfer authority.\n'
      printf 'Run `../idol-native/gate/selfhost.sh` and file `gaps/GAP-0NN.md`.\n'
    } >"$_c/clean.md"
    _hits=$(refscan "$_c/clean.md")
    if [ -n "$_hits" ]; then
        printf 'alignment projection control: FAIL — the reference scan flagged resolvable text:\n%s\n' "$_hits" >&2
        _rc=1
    fi

    rm -rf -- "$_c"
    [ "$_rc" -eq 0 ] || exit 1
    printf 'alignment projection control: PASS — planted absent file caught, resolvable citations clean\n'
    return 0
}

case ${1-} in
    --selftest) selftest; exit 0 ;;
    --emit|'') ;;
    *) printf 'usage: %s [--selftest|--emit]\n' "$0" >&2; exit 2 ;;
esac

# The emitter reads the compiler's own artifact tree; serialize with builds.
if [ "${IDOL_LOCK_HELD:-0}" != 1 ]; then
    exec "$repo/tools/node/dev/idol-lock" -- "$0" "$@"
fi

selftest || exit 1

# ============================== §1 PREFLIGHT ================================
idol=${IDOL:-./zig-out/bin/idol}
case $idol in
    /*) ;;
    *) idol=$repo/${idol#./} ;;
esac
cc=${CC:-cc}
[ -x "$idol" ] || broke "compiler is not executable: $idol"
command -v "$cc" >/dev/null 2>&1 || broke "C compiler is unavailable: $cc"
[ -f "$EMITTER" ] || broke "$EMITTER is missing"
[ -f "$C0" ] || broke "$C0 is missing"
[ -f "$DOC" ] || broke "$DOC is missing"

work=$(mktemp -d "${TMPDIR:-/tmp}/idol-alignment-projection.XXXXXX") || exit 2
# shellcheck disable=SC2064
trap "rm -rf -- '$work'" EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# ========================= §2 THE EMITTER COMPILES ==========================
# dump-c + cc is the executed bridge on this host (the direct backend answers
# DNB004 here); the emitted C runs the emitter exactly as an agent would.
"$idol" dump-c "$EMITTER" >"$work/emit.c" 2>"$work/emit.dump.log" \
    || broke "'idol dump-c $EMITTER' failed: $(sed -n 1,3p "$work/emit.dump.log")"
"$cc" "$work/emit.c" -o "$work/emit.bin" -lm 2>"$work/emit.cc.log" \
    || broke "the emitted C did not compile: $(grep -v Wpsabi "$work/emit.cc.log" | sed -n 1,3p)"
info '§2 the emitter compiles through the dump-c bridge'

# stage <dir> — a scratch tree holding the emitter's two fixed inputs.
stage() {
    mkdir -p "$1/docs/spec" || broke 'cannot stage a scratch tree'
    cp -- "$repo/$C0" "$1/$C0" || broke 'cannot stage the constitution'
    cp -- "$repo/$DOC" "$1/$DOC" || broke 'cannot stage the compass'
}

# --emit is the documented regeneration path: run at the repo root, report.
if [ "${1-}" = --emit ]; then
    (cd -- "$repo" && "$work/emit.bin") || exit 1
    exit 0
fi

# ==================== COMPILED CONTROLS, BEFORE MEASUREMENT =================
# C3 — a hand edit in the GENERATED frame must not survive regeneration.
ctamper=$work/control-tamper
stage "$ctamper"
sed 's/GENERATED frame/generated frame/' "$ctamper/$DOC" >"$ctamper/$DOC.tmp" \
    && mv -- "$ctamper/$DOC.tmp" "$ctamper/$DOC"
(cd -- "$ctamper" && "$work/emit.bin") >/dev/null 2>&1 \
    || bad 'control: the emitter refused a frame-tampered compass instead of regenerating it'
if cmp -s "$ctamper/$DOC" "$repo/$DOC"; then
    :
else
    bad 'control: regeneration did not restore a tampered frame'
fi

# C4 — a residue citation of a law C0 does not carry must refuse (exit 3).
cstale=$work/control-stale
stage "$cstale"
awk '/@@residue:end/ { print "This teaches law.retired.control as current." } { print }' \
    "$cstale/$DOC" >"$cstale/$DOC.tmp" && mv -- "$cstale/$DOC.tmp" "$cstale/$DOC"
(cd -- "$cstale" && "$work/emit.bin") >"$work/stale.log" 2>&1
if [ $? -ne 3 ]; then
    bad "control: a stale law citation was not refused with exit 3: $(sed -n 1,2p "$work/stale.log")"
fi

# C5 — deleted residue markers must refuse (exit 3), never emit a plausible
# compass with the whole operative residue silently dropped.
cbare=$work/control-bare
stage "$cbare"
grep -v '@@residue:' "$cbare/$DOC" >"$cbare/$DOC.tmp" && mv -- "$cbare/$DOC.tmp" "$cbare/$DOC"
(cd -- "$cbare" && "$work/emit.bin") >"$work/bare.log" 2>&1
if [ $? -ne 3 ]; then
    bad "control: a markerless compass was not refused with exit 3: $(sed -n 1,2p "$work/bare.log")"
fi
info 'controls: frame tamper restored, stale citation refused, lost markers refused'

# ==================== §3 BYTE IDENTITY AGAINST THE TREE =====================
run1=$work/run1
stage "$run1"
(cd -- "$run1" && "$work/emit.bin") >"$work/run1.log" 2>&1 \
    || { bad "the emitter refused the tracked inputs: $(sed -n 1,4p "$work/run1.log")"; }
if cmp -s "$repo/$DOC" "$run1/$DOC"; then
    info "§3 $DOC regenerates byte-identically"
else
    ndrift=$(diff "$repo/$DOC" "$run1/$DOC" 2>/dev/null | grep -c '^[<>]')
    bad "$DOC is not what the emitter produces ($ndrift drifted line(s)).
  Either a generated region was hand-edited, or C0/the emitter changed and the
  compass was not regenerated. Run: sh gate/alignment-projection.sh --emit"
fi

# =========================== §4 IDEMPOTENCE =================================
run2=$work/run2
mkdir -p "$run2/docs/spec" || broke 'cannot stage the second scratch tree'
cp -- "$repo/$C0" "$run2/$C0" || broke 'cannot stage the constitution'
cp -- "$run1/$DOC" "$run2/$DOC" || broke 'cannot carry the first regeneration'
(cd -- "$run2" && "$work/emit.bin") >/dev/null 2>&1 \
    || bad 'the second emitter run refused its own first output'
if cmp -s "$run1/$DOC" "$run2/$DOC"; then
    info '§4 regeneration is idempotent (run twice)'
else
    bad 'regeneration is not idempotent — the emitter cannot be run twice without a diff'
fi

# ========================= §5 LIVE FILE CITATIONS ===========================
dead=$(refscan "$repo/$DOC")
if [ -n "$dead" ]; then
    bad "the compass cites repo-relative files that do not exist:
$(printf '%s\n' "$dead" | sed 's/^/    /')"
else
    info '§5 every repo-relative file citation resolves'
fi

if [ "$FINDINGS" -eq 0 ]; then
    info "OK — $DOC regenerates byte-identically, idempotently, with live citations"
    exit 0
fi
printf 'alignment projection: %d finding(s)\n' "$FINDINGS" >&2
exit 1
