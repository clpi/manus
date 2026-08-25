#!/bin/sh
# gate/gap-115-evidence.sh — gate evidence must be private to its run.
#
# GAP-115's ruling: a test result whose evidence can be overwritten by another
# agent is not an authoritative fact. The measured corruption channel was a
# FIXED path under /tmp — `/tmp/as.log`, `/tmp/idol-orient.out`,
# `/tmp/idol-census-projection.out` — written by one session and read back as
# a verdict or displayed as evidence by another. The name is the whole defect:
# a path any concurrent session can spell in advance is a path any concurrent
# session can substitute.
#
# Two arms, and each can fail:
#
#   1. CLASS SCAN. No tracked gate, hook, or dev tool redirects into a literal
#      /tmp path. `${TMPDIR:-/tmp}` fallbacks and mktemp templates do not
#      match, because the minted name is not spellable in advance. The scan is
#      positive-controlled against the exact retired shape.
#
#   2. PLANTED CONCURRENT WRITER. The production evidence script
#      `tools/node/dev/census/projection` runs while a writer that knows only
#      the RETIRED fixed name clobbers it at the precise window between the
#      evidence write and the evidence read (the writer rides the script's own
#      `sed` invocation, so the race is deterministic, not probabilistic). The
#      displayed evidence must be this run's bytes. The same writer against a
#      copy DAMAGED back to the fixed-name shape must poison the displayed
#      evidence — proving the writer fires and the assertion can fail.
set -u

root=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd) || exit 2
cd "$root" || exit 2

work=$(mktemp -d "${TMPDIR:-/tmp}/idol-gap115.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

fail() {
    printf 'gap-115 evidence gate: FAIL %s\n' "$1" >&2
    exit 1
}

# ============================ ARM 1: CLASS SCAN =============================
# A redirect whose target starts with the literal string /tmp/ names a file
# every concurrent session can name too.
pattern='>>?[[:space:]]*/tmp/'

plant=$work/planted.sh
{
    printf '#!/bin/sh\n'
    printf 'printf x >%s/idol-planted-control.out\n' /tmp
} >"$plant"
grep -qE "$pattern" "$plant" \
    || fail 'scan positive control: detector missed the retired fixed-path shape'

hits=$(git ls-files gate tools/node/dev .githooks | xargs grep -nIE "$pattern" 2>/dev/null) || true
[ -z "$hits" ] || fail "fixed /tmp evidence path in tracked measurement code:
$hits"

# ====================== ARM 2: PLANTED CONCURRENT WRITER ====================
# The modeled shared root. The writer below is given ONLY the retired fixed
# name inside it — exactly what a concurrent session knew when the evidence
# path was fixed. It is never given the run-private name.
shared=$work/shared
mkdir -p "$shared" "$work/bin"
poison='POISON-ANOTHER-SESSIONS-BYTES-83f1'
token="gap115-$$-$(date +%s)"

# Stand-in compiler: the subject under test is the evidence routing of the
# census script, not the compiler, and `tools/node/dev/census/projection`
# admits the substitution through its IDOL input.
{
    printf '#!/bin/sh\n'
    printf 'printf %%s\\\\n "RESULT census evidence $IDOL_GAP115_TOKEN"\n'
    printf 'exit 0\n'
} >"$work/bin/idolstub"
chmod +x "$work/bin/idolstub"

# The planted writer. The census script pipes its evidence file through `sed`
# to display it, so an interposed `sed` runs INSIDE the race window: after the
# evidence was written, before it is read. It clobbers the retired fixed name,
# drops a marker proving it fired, then hands over to the real sed.
realsed=$(command -v sed) || fail 'no sed on PATH'
{
    printf '#!/bin/sh\n'
    printf 'printf %%s "$IDOL_GAP115_POISON" >"$IDOL_GAP115_SHARED/idol-census-projection.out"\n'
    printf ': >"$IDOL_GAP115_SHARED/writer-ran"\n'
    printf 'exec "$IDOL_GAP115_REALSED" "$@"\n'
} >"$work/bin/sed"
chmod +x "$work/bin/sed"

run_subject() {
    subject=$1
    log=$2
    if env TMPDIR="$shared" PATH="$work/bin:$PATH" \
        IDOL="$work/bin/idolstub" \
        IDOL_GAP115_SHARED="$shared" \
        IDOL_GAP115_POISON="$poison" \
        IDOL_GAP115_TOKEN="$token" \
        IDOL_GAP115_REALSED="$realsed" \
        sh "$subject" >"$log" 2>&1; then
        return 0
    else
        return $?
    fi
}

# Isolation arm: the production script, private evidence name, hostile writer.
run_subject "$root/tools/node/dev/census/projection" "$work/fixed.log" \
    || fail 'census evidence run failed under a planted concurrent writer'
[ -e "$shared/writer-ran" ] \
    || fail 'planted writer never fired — the isolation observation is vacuous'
grep -Fq "$token" "$work/fixed.log" \
    || fail 'displayed evidence lost this run own bytes'
if grep -Fq "$poison" "$work/fixed.log"; then
    fail 'planted writer substituted the displayed evidence through a private name'
fi

# Damage arm: restore the retired fixed-name shape and prove the same writer
# poisons the displayed evidence — the assertion above is falsifiable.
rm -f "$shared/writer-ran"
damaged=$work/census-damaged
sed 's|out="$(mktemp "${TMPDIR:-/tmp}/idol-census-projection.XXXXXX")"|out="${IDOL_GAP115_SHARED:?}/idol-census-projection.out"|' \
    "$root/tools/node/dev/census/projection" >"$damaged"
grep -Fq 'IDOL_GAP115_SHARED' "$damaged" \
    || fail 'fixed-name damage did not land'
if grep -Fq 'mktemp' "$damaged"; then
    fail 'fixed-name damage left the private name in place'
fi
run_subject "$damaged" "$work/damaged.log" \
    || fail 'damaged census run failed outright instead of silently corrupting'
[ -e "$shared/writer-ran" ] \
    || fail 'planted writer never fired against the damaged shape'
grep -Fq "$poison" "$work/damaged.log" \
    || fail 'retired fixed-name shape was NOT corrupted by the planted writer — the control cannot fail'

printf 'SUBJECT revision=%s dirty=%s\n' \
    "$(git -C "$root" rev-parse HEAD)" \
    "$(if git -C "$root" diff --quiet && git -C "$root" diff --cached --quiet; then printf clean; else printf dirty; fi)"
printf 'gap-115 evidence gate: PASS\n'
