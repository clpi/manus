#!/bin/sh
# gate/table-projection.sh — the generated-table counterfactual.
#
# Sibling of gate/grammar-projection.sh, which asserts the same property for
# the two grammar-role artifacts. This one covers the OTHER generated family:
# everything `idol wasm-tables emit` and `idol token-tables emit` write.
#
# WHY THIS EXISTS. Before it, none of the three tracked `.id` tables was
# reproduced by its generator, and the documented regeneration command was a
# trap: run it and the corpus reverted to pre-migration syntax, and `idol
# check` accepted the result. Measured at the time (gate/surface/reach.sh §2c,
# PR #111): 1222 changed lines in lib/wasm/opcode_lookup.id, 745 in
# lib/token/classify.id, 11 in lib/wasm/ward_mvp_opcodes.id.
#
# A generated file whose generator does not reproduce it is not generated. The
# committed text is authoritative for readers, the generator is authoritative
# for nobody, and the first person to follow the banner destroys the corpus.
#
# WHAT IS ASSERTED, in order:
#
#   §1  the compiler exists and the manifest is readable            (else exit 2)
#   §2  the emit commands write EXACTLY the declared subject set —
#       a subject silently added or dropped fails, and ZERO subjects fails
#   §3  every subject regenerates BYTE-IDENTICALLY into a scratch cwd
#   §4  regeneration is IDEMPOTENT: a second run over the first run's
#       output changes nothing
#   §5  no emitted `.id` byte carries RETIRED SYNTAX, so a diff that
#       corrupts the generator AND the tracked file together — which §3
#       alone would call clean — still fails
#
# `--selftest` runs the planted-violation controls for §2 and §5 and exits.
# The full run executes them first: a scanner that finds nothing is the
# recurring defect in this repository, so this gate proves it finds something
# before it reports that it found nothing.
set -u

repo=$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd) || exit 2
cd -- "$repo" || exit 2

FINDINGS=0
bad()  { FINDINGS=$((FINDINGS + 1)); printf 'table projection: FAIL — %s\n' "$*" >&2; }
info() { printf 'table projection: %s\n' "$*"; }
broke() { printf 'table projection: CANNOT MEASURE — %s\n' "$*" >&2; exit 2; }

# ---------------------------------------------------------------------------
# THE DECLARED SUBJECT SET.
#
# Every path the two emit commands write, relative to the working directory
# they are run in. §2 refuses if the commands write anything else, or omit
# any of these, so this list cannot silently fall behind the generators.
#
# DELIBERATELY NOT HERE: tools/wasm/src/duo_keyword_classify.c and
# tools/lsp/src/duo_keyword_classify.c. gate/generated.manifest names
# src/token_classify_gen.zig as their generator, but no invocation of it
# writes those paths and their banners cite `lib/std/token/classify.id` and
# `src/duo_keyword_bridge.zig`, neither of which exists in this repository.
# They are vendored copies from another tree, and claiming this gate covers
# them would be the exact lie this gate was written to stop.
SUBJECTS='lib/wasm/opcode_lookup.id
lib/wasm/ward_mvp_opcodes.id
lib/token/classify.id
src/keyword_classify.c'

# ---------------------------------------------------------------------------
# THE RETIRED-SYNTAX SCANNER (§5).
#
# Each pattern is a form a CLOSED law removed, cited to the law that removed
# it. Prints one line per finding on stdout; prints nothing when clean.
retired_syntax() {
    _f=$1
    # C0 law.comment.one: "hash begins the one canonical line comment";
    # "lua dash comments ... are never native Idol comment forms". Read on the
    # RAW file — a retired comment is exactly the thing being looked for.
    grep -nE '^[[:space:]]*--' "$_f" \
        | sed 's/^/    dash comment (C0 law.comment.one): /'
    # Everything below is a CODE-POSITION fact, so it reads a view with
    # canonical `#` comment lines blanked and their line numbers preserved.
    # Without this the gate flags the English word "then" in a generator's own
    # prose, which is a gate that cannot be satisfied rather than a law.
    _code=$(awk '{ if ($0 ~ /^[[:space:]]*#/) print ""; else print }' "$_f")
    # C0 syntax.block: bound = .offside, close = false. A bare `end` line and
    # a `then` are both the retired closing face.
    printf '%s\n' "$_code" | grep -nE '^[[:space:]]*end[[:space:]]*$' \
        | sed 's/^/    end terminator (C0 syntax.block .offside): /'
    printf '%s\n' "$_code" | grep -nE '(^|[[:space:]])then([[:space:]]|$)' \
        | sed 's/^/    then keyword (C0 syntax.block .offside): /'
    # The Lua-form relation head `name(p: t): r` — canonical is
    # `name: r = (p: t)`.
    printf '%s\n' "$_code" \
        | grep -nE '^[a-z][a-z0-9]*\([^)]*\):[[:space:]]*[a-z0-9]+[[:space:]]*$' \
        | sed 's/^/    lua-form relation head: /'
    # law.md §5: "`()` is ordinary application. It never means table
    # indexing." A screaming-case table name in application position is the
    # hand migration that turned T[i] into T(i) and made the compiler refuse
    # with DNB011 unresolved-application-facts.
    printf '%s\n' "$_code" | grep -nE '[A-Z][A-Z0-9]*(_[A-Z0-9]+)*\(' \
        | sed 's/^/    paren-indexed table (law.md §5): /'
    # AGENTS.md, retired source forms: "expanded same-place updates:
    # `hits = hits + 1`, `n = n - 1`, `x = x * y`, `y = y / z`, or any
    # `place = place op value` — use compound update". The generator emitted
    # `i = i + 1` into `lib/token/classify.id` and every section above passed it,
    # so the table reproduced byte-identically, idempotently, and in a form the
    # tree bans by name. A retired-form scan that cannot see a retired form is
    # the control-that-cannot-fail class AGENTS.md records.
    #
    # The back-reference pins the SAME place on both sides, so `a = b + 1` — an
    # ordinary binding and not an update — is not flagged.
    printf '%s\n' "$_code" \
        | grep -nE '^[[:space:]]*([a-z][a-z0-9]*)[[:space:]]*=[[:space:]]*\1[[:space:]]*[-+*/][[:space:]]*' \
        | sed 's/^/    expanded same-place update (AGENTS.md, use compound): /'
}

# ---------------------------------------------------------------------------
# CONTROLS. A gate that measures nothing passes; these prove it measures.
selftest() {
    _c=$(mktemp -d "${TMPDIR:-/tmp}/idol-table-projection-control.XXXXXX") || exit 2
    # shellcheck disable=SC2064
    trap "rm -rf -- '$_c'" EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    _rc=0

    # C1 NEGATIVE — every retired form is caught, one planted line each.
    cat >"$_c/retired.id" <<'PLANT'
-- GENERATED from nowhere — do not edit by hand.
COUNT = 2

pick(i: i64): i64
    if i < 0 then return -1 end
    TABLE(i + 1)
    n = n + 1
end
PLANT
    _found=$(retired_syntax "$_c/retired.id")
    # COUNTED, NOT ASSERTED. The count in the PASS line below was written as
    # the literal 5 and stayed 5 when a sixth form was added — a number in prose
    # that the runner checking it did not produce. It is derived now.
    _forms=0
    for _want in 'dash comment' 'end terminator' 'then keyword' \
                 'lua-form relation head' 'paren-indexed table' \
                 'expanded same-place update'; do
        _forms=$((_forms + 1))
        case $_found in
            *"$_want"*) ;;
            *) printf 'table projection control: FAIL — scanner missed %s\n' "$_want" >&2
               _rc=1 ;;
        esac
    done

    # C2 POSITIVE — canonical text is not flagged. Without this the scanner
    # could pass C1 by refusing everything.
    cat >"$_c/canonical.id" <<'PLANT'
# GENERATED from nowhere — do not edit by hand.
COUNT = 2
TABLE = {
  10,
  20,
}

pick: i64 = (i: i64)
  if i < 0
    return -1
  TABLE[i + 1]
PLANT
    _clean=$(retired_syntax "$_c/canonical.id")
    if [ -n "$_clean" ]; then
        printf 'table projection control: FAIL — scanner flagged canonical text:\n%s\n' \
            "$_clean" >&2
        _rc=1
    fi

    # C3 ZERO SUBJECTS — the recurring defect in this repository is a gate
    # that passes while comparing nothing. An empty subject set must FAIL.
    if ( SUBJECTS=''; compare_subjects "$_c" "$_c" >/dev/null 2>&1 ); then
        printf 'table projection control: FAIL — zero subjects was accepted\n' >&2
        _rc=1
    fi

    # C4 DRIFT — a subject that differs by one byte must FAIL.
    mkdir -p "$_c/a" "$_c/b"
    printf 'x\n' >"$_c/a/t.id"
    printf 'y\n' >"$_c/b/t.id"
    if ( SUBJECTS='t.id'; compare_subjects "$_c/a" "$_c/b" >/dev/null 2>&1 ); then
        printf 'table projection control: FAIL — a drifted subject was accepted\n' >&2
        _rc=1
    fi

    [ "$_rc" -eq 0 ] || exit 1
    printf 'table projection control: PASS — %s retired forms caught, canonical text clean, zero subjects refused, one-byte drift refused\n' "$_forms"
    trap - EXIT
    rm -rf -- "$_c"
    return 0
}

# compare_subjects <want-root> <got-root> — byte-compares every SUBJECT.
# Returns 1 on any drift AND on an empty subject set.
compare_subjects() {
    _want=$1
    _got=$2
    _n=0
    _rc=0
    for _s in $SUBJECTS; do
        _n=$((_n + 1))
        if [ ! -f "$_got/$_s" ]; then
            printf '  ABSENT      %s\n' "$_s"
            _rc=1
            continue
        fi
        if cmp -s "$_want/$_s" "$_got/$_s"; then
            printf '  reproduces  %s\n' "$_s"
        else
            printf '  DRIFT %-5s %s\n' \
                "$(diff "$_want/$_s" "$_got/$_s" 2>/dev/null | grep -c '^[<>]')" "$_s"
            _rc=1
        fi
    done
    if [ "$_n" -eq 0 ]; then
        printf '  ZERO SUBJECTS — nothing was compared\n'
        return 1
    fi
    return "$_rc"
}

case ${1-} in
    --selftest) selftest; exit 0 ;;
    '') ;;
    *) printf 'usage: %s [--selftest]\n' "$0" >&2; exit 2 ;;
esac

selftest || exit 1

# ============================== §1 PREFLIGHT ================================
idol=${IDOL:-./zig-out/bin/idol}
case $idol in
    /*) ;;
    *) idol=$repo/${idol#./} ;;
esac
[ -x "$idol" ] || broke "compiler is not executable: $idol"
[ -r gate/generated.manifest ] || broke 'gate/generated.manifest is unreadable'

for s in $SUBJECTS; do
    [ -f "$s" ] || broke "declared subject is not a tracked file: $s"
    grep -q "^$(printf '%s' "$s" | sed 's/[.[\*^$]/\\&/g')	" gate/generated.manifest \
        || bad "$s is not declared in gate/generated.manifest"
done

work=$(mktemp -d "${TMPDIR:-/tmp}/idol-table-projection.XXXXXX") || exit 2
# shellcheck disable=SC2064
trap "rm -rf -- '$work'" EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

# ========================= §2 WHAT THE COMMANDS WRITE =======================
# Run both emit commands in a scratch cwd — they write relative to the working
# directory, so the tracked tree is never touched — and take the set of files
# they created as ground truth for the subject list.
run1=$work/run1
mkdir -p "$run1" || broke 'cannot stage the generator scratch'
printf 'main: i64 = ()\n  0\n' >"$run1/seed.id"
( cd -- "$run1" && "$idol" wasm-tables emit seed.id ) >"$work/wasm.log" 2>&1 </dev/null \
    || broke "'idol wasm-tables emit' failed: $(sed -n 1,3p "$work/wasm.log")"
( cd -- "$run1" && "$idol" token-tables emit seed.id ) >"$work/token.log" 2>&1 </dev/null \
    || broke "'idol token-tables emit' failed: $(sed -n 1,3p "$work/token.log")"

( cd -- "$run1" && find . -type f ! -name seed.id | sed 's|^\./||' | sort ) >"$work/written"
printf '%s\n' $SUBJECTS | sort >"$work/declared"
nwritten=$(grep -c . "$work/written")
ndeclared=$(grep -c . "$work/declared")
[ "$ndeclared" -gt 0 ] || bad 'the declared subject set is EMPTY — this gate would measure nothing'
[ "$nwritten" -gt 0 ] || bad 'the emit commands wrote NOTHING — this gate would measure nothing'
if ! cmp -s "$work/written" "$work/declared"; then
    bad 'the emit commands do not write exactly the declared subject set'
    diff "$work/declared" "$work/written" | sed 's/^/    /' >&2
fi
info "§2 emit writes $nwritten file(s); $ndeclared declared"

# ====================== §3 BYTE IDENTITY AGAINST THE TREE ===================
printf 'table projection: §3 committed vs regenerated\n'
compare_subjects "$repo" "$run1" || bad 'a tracked table is not reproduced by its generator'

# =========================== §4 IDEMPOTENCE =================================
# A second run over the first run's own output must change nothing. A
# generator that is only stable against the tree, not against itself, cannot
# be run twice by a human without producing a diff.
run2=$work/run2
mkdir -p "$run2" || broke 'cannot stage the second generator scratch'
# `cpio` is not POSIX and is absent from stock container images, so the gate
# that measures generator idempotence could not measure it on any host lacking
# one optional tool — a CANNOT MEASURE that reads as a gate failure. `cp -R` is
# POSIX and this is a scratch tree of generated files, so the reason
# gate/layering-controls.sh avoids it (a tree carrying .git) does not apply.
cp -R -- "$run1/." "$run2/" >/dev/null 2>&1 \
    || broke 'cannot copy the first run for the idempotence check'
( cd -- "$run2" && "$idol" wasm-tables emit seed.id ) >/dev/null 2>&1 </dev/null \
    || broke "second 'idol wasm-tables emit' failed"
( cd -- "$run2" && "$idol" token-tables emit seed.id ) >/dev/null 2>&1 </dev/null \
    || broke "second 'idol token-tables emit' failed"
printf 'table projection: §4 idempotence (run twice)\n'
compare_subjects "$run1" "$run2" || bad 'regeneration is not idempotent'

# ========================= §5 RETIRED SYNTAX ================================
# §3 compares the generator against the tree. It cannot catch a diff that
# corrupts BOTH in one move, which is exactly how the migration would be
# reverted. This reads the emitted bytes against the closed laws directly.
printf 'table projection: §5 retired syntax in emitted .id\n'
scanned=0
for s in $SUBJECTS; do
    case $s in *.id) ;; *) continue ;; esac
    [ -f "$run1/$s" ] || continue
    scanned=$((scanned + 1))
    found=$(retired_syntax "$run1/$s")
    if [ -n "$found" ]; then
        bad "the generator emits retired syntax into $s"
        printf '%s\n' "$found" | sed -n 1,12p >&2
    else
        printf '  canonical   %s\n' "$s"
    fi
done
[ "$scanned" -gt 0 ] || bad 'ZERO .id subjects were scanned for retired syntax'

if [ "$FINDINGS" -eq 0 ]; then
    info "OK — $ndeclared subject(s) regenerate byte-identically, idempotently, in canonical syntax"
    exit 0
fi
printf 'table projection: %d finding(s)\n' "$FINDINGS" >&2
exit 1
