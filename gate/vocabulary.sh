#!/bin/sh
# gate/vocabulary.sh — deny-by-default admission for new public vocabulary.
#
# THE RULE. A candidate diff may not introduce a PUBLIC module-scope native
# identity -- relation, descriptor, case, or binding -- whose word is not
# already spelled in gate/vocabulary.admitted.
#
# WHAT THIS GATE REFUSES TO DO. It does not classify compounds by shape. It
# has no opinion about `rolebeginexpr` versus `role_begin_expr`, and it must
# never acquire one. A morphology heuristic is a rule an agent can reason its
# way past, and the premise here is that no merge may depend on an agent
# reasoning correctly. The only question asked is a set membership test:
# is the word on the list. `callextern` is refused not because it looks
# mashed but because nobody wrote it down.
#
# TWO PASSES, and the first is the one that cannot be zero:
#   (1) CENSUS. Extract every public identity from every tracked .id file and
#       require each to be admitted. 1010 subjects; if that number collapses,
#       the gate fails rather than reports clean (GAP-201/GAP-220). This also
#       means the gate is meaningful with no diff at all -- truncating the
#       admitted list fails immediately.
#   (2) DELTA. Extract identities introduced on ADDED lines of the candidate
#       diff and require each to be admitted.
#
# Extraction is gate/vocab-extract.awk, the same program that seeded the list.
# Column 1 is module scope; a leading `_` is private. No `idol check` is
# involved: check was shown to accept a read of a field a declared record does
# not have, so check-pass establishes nothing about descriptor law.
#
# USAGE:
#   gate/vocabulary.sh                 census + staged diff
#   gate/vocabulary.sh --base <rev>    census + <rev>..worktree
#   gate/vocabulary.sh --diff <file>   census + a diff file
#   gate/vocabulary.sh --census-only   census only (stated, not silent)
#   gate/vocabulary.sh --reseed        rewrite the admitted list from the tree
#                                      (prints to stdout; never auto-applied)

set -eu

MIN_SUBJECTS=900
MIN_ADMITTED=4000   # floor on the list itself; a truncated list admits nothing
                    # real and would otherwise turn this gate into a rubber
                    # stamp in the "everything is new, so nothing is checked"
                    # direction. Today's list holds 5033 words.

prog=$(basename "$0")
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
extract="$here/vocab-extract.awk"
admitted="$here/vocabulary.admitted"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/idol-vocab.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM

die() { printf '%s\n' "VOCABULARY BLOCKED -- $*" >&2; exit 1; }
note() { printf '%s\n' "$*" >&2; }

[ -f "$extract" ]  || die "gate/vocab-extract.awk is missing. Without the extractor nothing is examined, and examining nothing is not a pass."
[ -f "$admitted" ] || die "gate/vocabulary.admitted is missing. Deny-by-default with no list means deny everything; a missing list is a failure, not an exemption."

mode=full
diff_file=""
base_rev=""
while [ $# -gt 0 ]; do
    case "$1" in
        --census-only) mode=census ;;
        --reseed) mode=reseed ;;
        --base) shift; [ $# -gt 0 ] || die "--base needs a revision"; base_rev="$1" ;;
        --diff) shift; [ $# -gt 0 ] || die "--diff needs a path"; diff_file="$1" ;;
        -h|--help) sed -n '1,40p' "$0"; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
    shift
done

# ================================================================ ENUMERATION ==
subjects="$tmp/subjects.txt"
: >"$subjects"
enum_via=none
if git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
    if git -C "$root" ls-files -z -- '*.id' >"$tmp/ls.z" 2>/dev/null; then
        LC_ALL=C tr '\0' '\n' <"$tmp/ls.z" >"$subjects"
        enum_via=git
    fi
fi
n_subjects=$(LC_ALL=C awk 'END { print NR }' "$subjects")
if [ "$n_subjects" -eq 0 ]; then
    note "$prog: git enumeration yielded ZERO subjects; falling back to find (GAP-220)."
    if ! ( cd "$root" && find . -name '*.id' -type f \
            -not -path './.git/*' -not -path '*/zig-cache/*' \
            -not -path '*/.zig-cache/*' -not -path '*/zig-out/*' -print ) \
            | LC_ALL=C sed 's|^\./||' >"$subjects"; then
        die "subject enumeration failed outright (find)."
    fi
    enum_via=find
    n_subjects=$(LC_ALL=C awk 'END { print NR }' "$subjects")
fi
[ "$n_subjects" -gt 0 ] || die "ZERO subjects enumerated (GAP-201). Examining nothing is a failure."
[ "$n_subjects" -ge "$MIN_SUBJECTS" ] || die "only $n_subjects subjects via $enum_via, floor $MIN_SUBJECTS (GAP-201/GAP-220). Enumeration is broken; a clean report over it would mean nothing."

# ===================================================================== EXTRACT ==
decls="$tmp/decls.txt"
: >"$decls"
while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    [ -f "$root/$rel" ] || continue
    if ! LC_ALL=C awk -v MODE=file -f "$extract" "$root/$rel" >>"$decls" 2>"$tmp/awkerr"; then
        cat "$tmp/awkerr" >&2
        die "extractor aborted on $rel. A truncated extraction is a false pass."
    fi
done <"$subjects"

n_decls=$(LC_ALL=C awk 'END { print NR }' "$decls")
[ "$n_decls" -gt 0 ] || die "ZERO public declarations extracted from $n_subjects subjects (GAP-201). The extractor matched nothing, which means the gate is inert -- fail, do not pass."

if [ "$mode" = reseed ]; then
    LC_ALL=C awk -F'\t' '{ print $2 }' "$decls" | LC_ALL=C sort -u
    exit 0
fi

# The admitted list, comments stripped.
words="$tmp/words.txt"
LC_ALL=C awk '/^[[:space:]]*(#|$)/ { next } { gsub(/[[:space:]]/, ""); if ($0 != "") print }' "$admitted" | LC_ALL=C sort -u >"$words"
n_words=$(LC_ALL=C awk 'END { print NR }' "$words")
[ "$n_words" -ge "$MIN_ADMITTED" ] || die "gate/vocabulary.admitted holds only $n_words words, floor $MIN_ADMITTED. A truncated list is not a stricter gate, it is a broken one."

# ====================================================================== CENSUS ==
LC_ALL=C awk -F'\t' '{ print $2 }' "$decls" | LC_ALL=C sort -u >"$tmp/used.txt"
LC_ALL=C comm -23 "$tmp/used.txt" "$words" >"$tmp/unadmitted.txt"
n_unadmitted=$(LC_ALL=C awk 'END { print NR }' "$tmp/unadmitted.txt")

note "$prog: census via $enum_via -- $n_subjects .id subjects, $n_decls public declarations, $(LC_ALL=C awk 'END{print NR}' "$tmp/used.txt") distinct words, $n_words admitted."

if [ "$n_unadmitted" -gt 0 ]; then
    note ""
    note "words present in tracked source but NOT admitted:"
    while IFS= read -r w; do
        loc=$(LC_ALL=C awk -F'\t' -v w="$w" '$2 == w { print $1 " in " $3; exit }' "$decls")
        note "  $w    ($loc)"
    done <"$tmp/unadmitted.txt"
    note ""
    die "$n_unadmitted public identit(ies) in the tree are not in gate/vocabulary.admitted.
  Either the word belongs -- add the line, which is the reviewable act this gate exists to force --
  or it does not, and the declaration is what should go."
fi

LC_ALL=C comm -13 "$tmp/used.txt" "$words" >"$tmp/stale.txt"
n_stale=$(LC_ALL=C awk 'END { print NR }' "$tmp/stale.txt")
[ "$n_stale" -eq 0 ] || note "$prog: note -- $n_stale admitted word(s) no longer declared anywhere. Not a failure (deleting a relation is ordinary), but the list is drifting; prune with --reseed."

# ======================================================================= DELTA ==
if [ "$mode" = census ]; then
    note "$prog: --census-only -- the delta rule was SKIPPED, not passed."
    note "$prog: CENSUS OK."
    exit 0
fi

cand="$tmp/candidate.diff"
if [ -n "$diff_file" ]; then
    [ -f "$diff_file" ] || die "--diff $diff_file does not exist."
    cp "$diff_file" "$cand"
elif [ "$enum_via" != git ]; then
    die "no .git here, so the delta rule cannot be evaluated. Pass --diff <file>, or --census-only to say so out loud. 'Could not check' is not 'passed'."
elif [ -n "$base_rev" ]; then
    git -C "$root" rev-parse --verify "${base_rev}^{commit}" >/dev/null 2>&1 || die "--base $base_rev is not a commit."
    if ! git -C "$root" diff -U0 --no-renames --diff-filter=ACMR "$base_rev" -- '*.id' >"$cand"; then
        die "could not produce a diff against $base_rev."
    fi
else
    if ! git -C "$root" diff --cached -U0 --no-renames --diff-filter=ACMR -- '*.id' >"$cand"; then
        die "could not produce the staged diff."
    fi
fi

if ! LC_ALL=C awk -v MODE=diff -f "$extract" "$cand" >"$tmp/new.txt" 2>"$tmp/awkerr2"; then
    cat "$tmp/awkerr2" >&2
    die "extractor aborted on the candidate diff. Refusing to report a pass off a truncated scan."
fi

n_new=$(LC_ALL=C awk 'END { print NR }' "$tmp/new.txt")
n_diff=$(LC_ALL=C awk 'END { print NR }' "$cand")

denied="$tmp/denied.txt"
: >"$denied"
if [ "$n_new" -gt 0 ]; then
    LC_ALL=C sort -u -t"$(printf '\t')" -k2,2 "$tmp/new.txt" >"$tmp/new_u.txt"
    while IFS="$(printf '\t')" read -r kind name file; do
        if ! LC_ALL=C awk -v w="$name" '$0 == w { f = 1 } END { exit f ? 0 : 1 }' "$words"; then
            printf '%s\t%s\t%s\n' "$kind" "$name" "$file" >>"$denied"
        fi
    done <"$tmp/new_u.txt"
fi

n_denied=$(LC_ALL=C awk 'END { print NR }' "$denied")
if [ "$n_denied" -gt 0 ]; then
    note ""
    note "UNADMITTED public identities introduced by this diff:"
    LC_ALL=C awk -F'\t' '{ printf "  %-11s %-32s %s\n", $1, $2, $3 }' "$denied" >&2
    note ""
    die "$n_denied new public identit(ies) are not in gate/vocabulary.admitted.
  This is deny-by-default and it is deliberate. The gate has no view on how the
  word is spelled -- it was simply never admitted. If the word is right, add it
  to gate/vocabulary.admitted in this same commit; that edit is the review."
fi

note "$prog: delta OK -- $n_diff diff lines examined, $n_new public identit(ies) introduced, all admitted."
note "$prog: VOCABULARY OK."
exit 0
