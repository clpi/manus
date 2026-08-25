#!/bin/sh
# gate/crosspartition.sh — a program is REALIZED over every source partition it
# reaches, on the `--backend=direct` native route.
#
# ═══ THE FAILURE THIS PINS, quoted from the tree's own record ══════════════
#
# `gaps/GAP-134.md` records it as still open:
#
#     Undefined symbols for architecture arm64:
#       "_idol_token_grammarrole__rolebeginexpr", referenced from: …
#     error: native linker failed
#
# Reach was already established. Resolution found the file, sema parsed the
# declaration, the graph carried the foreign home, and the definer and the
# caller already derived the SAME mangled string from the same two facts
# because both go through `home_resolve.relationSymbol`. NOBODY EVER COMPILED
# THE REACHED PARTITION and put it on the link line. Every piece except that
# one already worked, which is why the failure surfaced at the linker rather
# than anywhere a compiler diagnostic could explain it.
#
# The C transfer route closed its half of this and has `gate/lower/fallback.sh`
# holding it closed. The direct native route closed its half with
# `main.reachedHomeObjects` and landed with NO GATE AT ALL — its evidence was
# prose in a commit message. This file is that missing instrument.
#
# ═══ WHAT IS MEASURED, AND WHY IT IS EXECUTION AND NOT INSPECTION ══════════
#
# Every subject is COMPILED WITH `--backend=direct` AND RUN, and its answer is
# checked against a number that only the reached partition can produce. A
# scan of the link line, or an `nm` of the entry object, would agree with a
# compiler that linked the right files and realized them wrongly. An answer
# does not.
#
# `nm` IS STILL READ, as a SECOND pin and never as the first: the reached
# relation must be DEFINED (`T`) in the linked image. A subject that answers
# correctly with the definition absent would mean the answer came from
# somewhere other than the partition under test — constant folding, a stale
# artifact, an aliased binary — and this column is what tells those apart from
# the thing being claimed.
#
# ═══ THE SUBJECT ROSTER IS A FILE, so zero subjects is reachable ═══════════
#
# GAP-201: a gate examining zero subjects must FAIL. That rule is only worth
# anything if zero is a state this gate can actually be in, so the roster lives
# in `gate/crosspartition.subjects` rather than in this script. A run that
# cannot read it, or reads no rows from it, exits non-zero saying so.
#
# The roster is checked BOTH WAYS. A row naming a shape this script cannot
# materialize fails, so the roster cannot name subjects that quietly stop
# existing; and a shape this script can materialize that the roster does not
# name fails, so a subject cannot be dropped from measurement by deleting one
# line. It is a ratchet, not a list.
#
# ═══ THE CONTROLS ══════════════════════════════════════════════════════════
#
# A gate that refuses everything passes every ratchet it owns and measures
# nothing, and a gate that reads only exit status agrees with a compiler that
# links the world and computes garbage. Three controls, run BEFORE any subject
# is reported, each proving a different way to be wrong:
#
#   P  POSITIVE. A SINGLE-partition program must compile and answer. Nothing
#      here is about cross-partition reach, so if this cannot pass, the
#      compiler under test is not measurable and the gate says NOT MEASURED
#      instead of reporting a cross-partition finding it did not earn. This is
#      what stops "refuse everything" from being a pass.
#
#   N1 NEGATIVE, THE CHECKER SEES A WRONG ANSWER. The two-partition subject is
#      materialized with the reached partition DAMAGED — `x * 3` where the
#      expected answer wants `x * 2` — and the SAME `run_subject` used for real
#      subjects is required to report failure. If it reports success, this file
#      is not reading answers and every green row below is worthless.
#
#   N2 NEGATIVE, THE REACH IS NOT OPTIONAL. The same subject with the reached
#      partition REMOVED must fail to produce a working program. A compiler
#      that silently drops an unrealizable input and links anyway reproduces
#      the undefined symbol one layer further from its cause, which is the
#      fail-open this whole path exists to remove.
#
# ═══ WHAT THIS GATE DELIBERATELY DOES NOT COVER, and why saying so here ════
#
# A reached partition's OWN bootstrap needs are not on the link line. Measured
# at this commit, an entry reaching `lib/token/grammarrole.id`:
#
#     _idol_<…>_token_grammarrole__roleprecedence   — DEFINED now (was the
#                                                     GAP-134 undefined symbol)
#     _duo_str_sub                                  — UNDEFINED, referenced
#                                                     from the reached
#                                                     partition's own object
#
# `directLinkInputs` is handed the ENTRY's `artifact.need` and nothing else, so
# a reached partition that needs `idol_str_runtime.o` still fails at the
# linker — a DIFFERENT hole, one layer past the one closed here, and it fails
# loudly rather than silently. Every subject below is arithmetic precisely so
# that this gate measures the reach and not that second gap, and this paragraph
# exists so that a green run here is not read as covering it. When the needs of
# reached partitions join the link line, the honest edit is a fourth shape
# whose reached partition needs the string runtime.
#
# ═══ SOURCE PATH ═══════════════════════════════════════════════════════════
#
# The mangled symbol embeds the SOURCE PATH, so `_idol_<dirs>_helper__twice`
# is not stable across work directories and is never compared as a whole
# string; only its path-independent tail is. Nothing here byte-compares two
# artifacts, precisely because the path that would have to be held fixed is
# the one this gate randomizes.
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/.." && pwd)
cd "$root" || { printf 'crosspartition: cannot enter root\n' >&2; exit 3; }

# `zig-out/bin/idol` AND NOT `out/bin/idol`. The latter is a stale artifact
# that has served as a false oracle in this tree before; it is not this build.
IDOL=${IDOL:-"$root/zig-out/bin/idol"}
roster=$here/crosspartition.subjects

if [ ! -x "$IDOL" ]; then
    printf 'crosspartition: NOT MEASURED — compiler is not executable: %s\n' "$IDOL" >&2
    exit 3
fi
if [ ! -r "$roster" ]; then
    printf 'crosspartition: FAIL — subject roster is unreadable: %s (0 subjects examined)\n' "$roster" >&2
    exit 1
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/idol.crosspartition.XXXXXX") || exit 3
# A PRIVATE SCRATCH ROOT. `src/scratch.zig` routes the executable cache,
# intermediate objects and logs through TMPDIR, so pointing it inside `$work`
# gives this run a cache no other lane can name and no other lane can evict —
# the same reason `gate/cache-home.sh` does it.
TMPDIR=$work/scratch
export TMPDIR
mkdir -p "$TMPDIR" || exit 3
cleanup() { rm -rf -- "$work"; }
trap 'cleanup' EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup; exit 129' HUP

# ── the shapes ─────────────────────────────────────────────────────────────
# Each writes ONE entry `main.id` plus the partitions it reaches, into $1.
# `damage` is the N1 control's hook: it is the empty string for a real subject
# and a factor for the deliberately-wrong one, so the control travels through
# the same materializer as the thing it is controlling for.
materialize() {
    shape=$1
    dir=$2
    factor=${3:-2}
    mkdir -p "$dir" || return 1
    case $shape in
        duo)
            # One entry, one reached partition. 21 * 2 = 42.
            printf 'twice: i64 = (x: i64)\n  x * %s\n' "$factor" >"$dir/helper.id" || return 1
            printf 'main: i64 = ()\n  helper.twice(21)\n' >"$dir/main.id" || return 1
            ;;
        trio)
            # TRANSITIVE. The entry never names `deeper`; only the partition it
            # reaches does. (21 + 1) * 2 = 44. A closure that stops at depth one
            # links `helper` and still fails at the linker on `deeper`.
            printf 'plus: i64 = (x: i64)\n  x + 1\n' >"$dir/deeper.id" || return 1
            printf 'twice: i64 = (x: i64)\n  deeper.plus(x) * %s\n' "$factor" >"$dir/helper.id" || return 1
            printf 'main: i64 = ()\n  helper.twice(21)\n' >"$dir/main.id" || return 1
            ;;
        fan)
            # TWO partitions reached from one entry, so the link line has to
            # carry more than one extra object. 10 * 2 + (4 + 1) = 25.
            printf 'plus: i64 = (x: i64)\n  x + 1\n' >"$dir/deeper.id" || return 1
            printf 'twice: i64 = (x: i64)\n  x * %s\n' "$factor" >"$dir/helper.id" || return 1
            printf 'main: i64 = ()\n  helper.twice(10) + deeper.plus(4)\n' >"$dir/main.id" || return 1
            ;;
        solo)
            # No reach at all — the positive control's shape.
            printf 'main: i64 = ()\n  7\n' >"$dir/main.id" || return 1
            ;;
        *)
            return 2
            ;;
    esac
    return 0
}
SHAPES='duo trio fan'

# ── one subject, measured ──────────────────────────────────────────────────
# Compiles `$1/main.id` with `--backend=direct`, runs it, and requires the exit
# status to equal `$2`. When `$3` is non-empty it must also name a relation the
# linked image DEFINES.
#
# Writes its own account to `$work/why` so the caller can print WHAT went wrong
# rather than only that something did. Returns 0 only on a full pass.
run_subject() {
    dir=$1
    expect=$2
    defines=$3
    : >"$work/why"

    if ! ( CDPATH='' cd -- "$dir" && "$IDOL" compile --backend=direct main.id -o prog ) \
        >"$work/compile.log" 2>&1
    then
        printf 'compile failed: %s' "$(tail -3 "$work/compile.log" | tr '\n' ' ')" >"$work/why"
        return 1
    fi
    if [ ! -x "$dir/prog" ]; then
        printf 'compile reported success and produced no executable' >"$work/why"
        return 1
    fi
    # A CRASH IS NOT AN ANSWER. 128+n is a signal, and reading one as an exit
    # status would let a segfaulting program match a numeric expectation.
    "$dir/prog" >/dev/null 2>&1
    got=$?
    if [ "$got" -gt 125 ]; then
        printf 'program did not answer (status %s — signal or exec failure)' "$got" >"$work/why"
        return 1
    fi
    if [ "$got" != "$expect" ]; then
        printf 'answered %s, expected %s' "$got" "$expect" >"$work/why"
        return 1
    fi
    if [ -n "$defines" ]; then
        # PATH-INDEPENDENT TAIL ONLY. The full symbol carries the work
        # directory, which changes every run.
        if ! nm -g "$dir/prog" 2>/dev/null | awk '$2 == "T" { print $3 }' \
            | grep -q -- "$defines\$"
        then
            printf 'answered %s but the reached relation %s is not DEFINED in the image' \
                "$got" "$defines" >"$work/why"
            return 1
        fi
    fi
    return 0
}

# ══ CONTROL P — a single partition compiles, links and answers ═════════════
materialize solo "$work/ctl.solo" || {
    printf 'crosspartition: NOT MEASURED — cannot write the positive control\n' >&2
    exit 3
}
if ! run_subject "$work/ctl.solo" 7 ''; then
    printf 'crosspartition control P: NOT MEASURED — a single-partition program does not compile and answer here: %s\n' \
        "$(cat "$work/why")" >&2
    printf 'crosspartition:   nothing this gate reports about cross-partition reach would be earned.\n' >&2
    exit 3
fi

# ══ CONTROL N1 — the checker sees a wrong answer ═══════════════════════════
materialize duo "$work/ctl.wrong" 3 || {
    printf 'crosspartition: NOT MEASURED — cannot write the negative control\n' >&2
    exit 3
}
if run_subject "$work/ctl.wrong" 42 '_helper__twice'; then
    printf 'crosspartition control N1: FAIL — a reached partition answering 63 was accepted as 42.\n' >&2
    printf 'crosspartition:   this file is not reading answers; every row below would be worthless.\n' >&2
    exit 1
fi

# ══ CONTROL N2 — a missing reached partition is not silently dropped ═══════
materialize duo "$work/ctl.gone" || {
    printf 'crosspartition: NOT MEASURED — cannot write the fail-closed control\n' >&2
    exit 3
}
rm -f "$work/ctl.gone/helper.id"
if run_subject "$work/ctl.gone" 42 ''; then
    printf 'crosspartition control N2: FAIL — the entry produced a working 42 with its reached partition deleted.\n' >&2
    printf 'crosspartition:   the reach is being ignored, not realized.\n' >&2
    exit 1
fi

# ══ THE ROSTER ═════════════════════════════════════════════════════════════
examined=0
failed=0
rows=0
named=''

while IFS= read -r line || [ -n "$line" ]; do
    case $line in ''|\#*) continue ;; esac
    rows=$((rows + 1))
    shape=$(printf '%s\n' "$line" | awk '{print $1}')
    expect=$(printf '%s\n' "$line" | awk '{print $2}')
    defines=$(printf '%s\n' "$line" | awk '{print $3}')
    if [ -z "$shape" ] || [ -z "$expect" ] || [ -z "$defines" ]; then
        printf 'crosspartition: FAIL — malformed roster row: %s\n' "$line" >&2
        failed=$((failed + 1))
        continue
    fi
    dir=$work/subject.$shape
    materialize "$shape" "$dir"
    case $? in
        0) ;;
        2)
            printf 'crosspartition: FAIL — roster names a shape this gate cannot materialize: %s\n' "$shape" >&2
            failed=$((failed + 1))
            continue
            ;;
        *)
            printf 'crosspartition: FAIL — cannot write subject %s\n' "$shape" >&2
            failed=$((failed + 1))
            continue
            ;;
    esac
    named="$named $shape"
    examined=$((examined + 1))
    if run_subject "$dir" "$expect" "$defines"; then
        printf 'crosspartition: %-6s PASS  answer=%s defines=%s\n' "$shape" "$expect" "$defines"
    else
        printf 'crosspartition: %-6s FAIL  %s\n' "$shape" "$(cat "$work/why")" >&2
        failed=$((failed + 1))
    fi
done <"$roster"

# ── the roster covers every shape, and only shapes that exist ──────────────
for shape in $SHAPES; do
    case " $named " in
        *" $shape "*) ;;
        *)
            printf 'crosspartition: FAIL — shape %s exists here and the roster does not name it; it would go unmeasured.\n' "$shape" >&2
            failed=$((failed + 1))
            ;;
    esac
done

# ── GAP-201: zero subjects is a failure, never a clean run ─────────────────
if [ "$examined" -eq 0 ]; then
    printf 'crosspartition: FAIL — 0 subjects examined (roster held %s row(s)); absence of a subject is not absence of a defect.\n' \
        "$rows" >&2
    exit 1
fi

printf 'crosspartition: %s subject(s) examined, %s failed — cross-partition realization on --backend=direct.\n' \
    "$examined" "$failed"
if [ "$failed" -ne 0 ]; then
    printf 'crosspartition: FAIL\n' >&2
    exit 1
fi
printf 'crosspartition: OK.\n'
exit 0
