#!/bin/sh
# gate/admission.sh — added-source quarantine for the retired std namespace.
#
# TWO RULES. They answer two different questions and neither substitutes.
#
#   (B) QUARANTINE, on the candidate diff. No added line in Idol source may
#       carry a raw `std.` spelling, ANY position. Deleting or rewriting old
#       debt is admitted; moving or re-adding it is not. This is deliberately a
#       source quarantine and NOT a claim that comments or strings carry
#       semantic reach -- new prose teaching the retired root is its own
#       problem (GAP-157 acceptance 1 and 3).
#
#   (A) CENSUS, over the tracked tree. The number of CODE-POSITION `std.`
#       reaches, minus the exact reaches pinned in gate/std-fixtures.manifest,
#       must not EXCEED the pinned budget. A ratchet: it moves down, never up.
#
# WHY (A) IS BACK, AND WHY IT IS NOT THE THING THAT WAS REMOVED.
#   The census deleted here in ee8adabf was position-blind: it charged 473
#   TOKENS, of which 123 were comments and text literals, and it exempted six
#   gate scanners WHOLE-FILE to stop charging them for their own detector
#   needles. The objection recorded against it was exact and correct -- it was
#   "a second, false authority one commit after the ledger was published",
#   because docs/spec/std-zero-ledger.json had already measured the tree by
#   POSITION and got a different number.
#
#   Deleting it left rule (B) alone, and (B) cannot ratchet. It stops the debt
#   growing on added lines; nothing makes the 332 reaches already in the tree
#   go down, and nothing notices if a rewrite quietly relocates them. So the
#   census returns measuring what the ledger measures. It is not a second
#   authority: it is the ledger's own counting rule, executable. Cross-checked
#   at ce03c7eb against all 94 carriers in that file, per position, zero drift.
#
# WHAT "CODE-POSITION" MEANS, AND WHY (A) AND (B) DIFFER ON IT.
#   `law.std.zero` is a rule about a NAMESPACE REACH: `std.io.open(p)` routes a
#   world through a root that owns no meaning, and sema refuses it by name
#   (src/sema.zig refuseOsDotFace). A `std.` inside a `#` comment or a `"`
#   literal resolves no home and cannot violate that rule -- it is prose, or it
#   is a DETECTOR'S OWN NEEDLE. gate/idiom.id carries eighteen for that reason.
#
#   So the CENSUS charges reaches only: a budget that counts prose is a budget
#   payable in prose, and deleting a comment must not buy a reach. The
#   QUARANTINE still charges everything, because on an ADDED line the cheap
#   rule is the strong one and nobody needs to write a new one of either.
#
#   The lexer is exact rather than approximate BECAUSE THE LANGUAGE MAKES IT
#   SO: docs/spec/grammar.md holds Lua long strings and long comments to be
#   noncanonical Idol, so no literal spans a newline and per-line state is
#   complete.
#
# Usage:
#   gate/admission.sh                  census + staged-diff quarantine
#   gate/admission.sh --base <rev>     census + <rev>..worktree quarantine
#   gate/admission.sh --diff <file>    census + quarantine over a diff file
#   gate/admission.sh --census-only    census only (explicit; the quarantine is
#                                      SKIPPED, never silently passed)

set -eu

# ---------------------------------------------------------------- constants --
# Pinned 2026-08-23 against idol@c77dea60 + the eighteen-site migration in the
# same commit. Re-measured from scratch, not carried across the rebase.
#
# DENOMINATOR, with power, because a numerator alone is a rumour. Every figure
# below is printed by `gate/admission.sh --census-only` on every run, so the
# comment cannot drift away from the code that produces it.
#
#   subjects enumerated ..................  1001 tracked .id files
#   token occurrences, ALL positions .....   510  = 323 code + 187 text/comment
#   code-position reaches ................   323  (37 unpinned carriers)
#   of those, pinned exempt ..............    15  (3 files)
#   BUDGET (census subject) ..............   308
#
# THE BASE, so the migration in this commit is visible rather than asserted.
# Pristine c77dea60: 1012 subjects, 534 tokens = 344 code + 108 text + 82
# comment; 501 of the 534 carry an identifier after the dot, and all 33 that
# do not sit in text or comments. 344 - 18 migrated here = 326.
#
# RECONCILIATION WITH THE 473 THIS REPLACES, because two live numbers with no
# stated relation is how a ratchet quietly stops meaning anything. Measured at
# ce03c7eb, where the 473 was last actually pinned and enforced:
#
#   547  word-bounded `std.` tokens, all positions = 350 code + 114 text + 83 comment
#   512  ... of which have an identifier after the dot (the old regex's tail);
#        the 35 it dropped are bare `std.` -- print("std."), a flag needle --
#        and ALL 35 sit in text or comments, so the tail was harmless, not right
#   473  = 512 - 39 pinned. Those 39 are whole-file exemptions over 6 files and
#        ALL 39 are text/comment positions: the 6 have zero code reaches
#   350  code-position reaches, every class
#   335  ... of those, in files classed `canonical` by the ledger
#
#   473 - 335 = 138, decomposing with nothing left over:
#     123 = text/comment tokens charged outside the 6 pinned files (88+74-39)
#      15 = code reaches in files that are NOT canonical debt
#           (14 historical, 1 the law.std.zero compile-fail fixture)
#
# THIS DOES NOT RAISE THE BUDGET. The tree measured exactly 473 of 473, so
# there was no visible slack -- but 123 of the 473 were prose, and deleting
# prose bought real reaches. Purchasable headroom goes 123 -> 0. The escape
# hatch goes 6 files / 39 whole-file tokens -> 3 files / 15 code reaches.
STD_BUDGET=308

# Floor on enumerated subjects. Today's tree has 1013 tracked .id files.
# gate/subject.sh already refuses a non-work-tree and a zero-subject pathspec;
# this catches the third shape -- a partial checkout that enumerates SOME
# files. A short subject list must fail, because a clean report over it means
# nothing (GAP-201).
MIN_SUBJECTS=900

prog=$(basename "$0")
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
subject="$here/subject.sh"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/idol-admission.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM

manifest="$root/gate/std-fixtures.manifest"

die() { printf '%s\n' "ADMISSION BLOCKED -- $*" >&2; exit 1; }
note() { printf '%s\n' "$*" >&2; }

[ -x "$subject" ] || die "gate/subject.sh is missing or not executable."
(cd "$root" && sh "$subject" --tree) >/dev/null || die "candidate admission requires a real Git work tree (GAP-220)."

subjects="$tmp/subjects.txt"
(cd "$root" && sh "$subject" '*.id') >"$subjects" || die "Idol source enumeration failed or produced zero subjects (GAP-201)."

mode=full
diff_file=""
base_rev=""
while [ $# -gt 0 ]; do
    case "$1" in
        --census-only) mode=census ;;
        --base) shift; [ $# -gt 0 ] || die "--base needs a revision"; base_rev=$1 ;;
        --diff) shift; [ $# -gt 0 ] || die "--diff needs a path"; diff_file=$1 ;;
        -h|--help) sed -n '1,60p' "$0"; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
    shift
done
[ -z "$diff_file" ] || [ -z "$base_rev" ] || die "--base and --diff are mutually exclusive"

# ==================================================================== SCANNER ==
# ONE awk program, so the census has one counting rule and not two.
#
# It is a LEXER, not a regex: it walks the line tracking whether it is in code,
# in a `"` text literal, in a `'` byte literal, or past a `#` that runs to end
# of line, and charges a `std.` only in the first state.
#
# NO LITERAL QUOTE OR BACKSLASH BYTE APPEARS IN IT. The three bytes it compares
# against are built with sprintf, because a program about quoting that is hard
# to quote is a program the next shell edit silently breaks.
#
# The left bound is `[^A-Za-z0-9_]` or start of line, so `stdXio`, `my_std.` and
# `standard` are not reaches -- and `wrapper.std.io` IS one, because dotted-path
# hiding is not a loophole. There is no requirement of an identifier AFTER the
# dot: at code position a bare `std.` is a reach that failed to finish.
SCANNER='
function codehits(line,   n, i, ch, st, prev, h, dq, sq, bs) {
    dq = sprintf("%c", 34); sq = sprintf("%c", 39); bs = sprintf("%c", 92)
    n = length(line); st = 0; i = 1; h = 0
    while (i <= n) {
        ch = substr(line, i, 1)
        if (st == 0) {
            if (substr(line, i, 4) == "std.") {
                prev = (i == 1) ? "" : substr(line, i - 1, 1)
                if (prev !~ /[A-Za-z0-9_]/) { h++; i += 4; continue }
            }
            if (ch == "#") return h
            if (ch == dq) st = 1
            else if (ch == sq) st = 2
        } else {
            if (ch == bs) i++
            else if ((st == 1 && ch == dq) || (st == 2 && ch == sq)) st = 0
        }
        i++
    }
    return h
}
function allhits(line,   n, i, prev, h) {
    n = length(line); i = 1; h = 0
    while (i <= n) {
        if (substr(line, i, 4) == "std.") {
            prev = (i == 1) ? "" : substr(line, i - 1, 1)
            if (prev !~ /[A-Za-z0-9_]/) { h++; i += 4; continue }
        }
        i++
    }
    return h
}
'

# ==================================================================== MANIFEST =
[ -f "$manifest" ] || die "gate/std-fixtures.manifest is missing. Without it every pinned reach reads as debt and the budget is meaningless."

fixtures="$tmp/fixtures.txt"
if ! LC_ALL=C awk '
    /^[[:space:]]*(#|$)/ { next }
    {
        sub(/[[:space:]]*#.*$/, "")
        if (NF < 2) { bad = 1; exit }
        # A pin of 0 is not an exemption, it is a placeholder for one, and it
        # would make "this file stopped carrying reaches" indistinguishable
        # from "this file is allowed to carry them again".
        if ($2 !~ /^[1-9][0-9]*$/) { bad = 1; exit }
        print $1 "\t" $2
    }
    END { if (bad) exit 3 }
' "$manifest" >"$fixtures"; then
    die "gate/std-fixtures.manifest is malformed (every entry needs '<path> <exact-count>', count a positive integer)."
fi

n_fixtures=$(LC_ALL=C awk 'END { print NR + 0 }' "$fixtures")
[ "$n_fixtures" -gt 0 ] || die "gate/std-fixtures.manifest classifies zero files. If nothing is exempt, delete the file and drop the exemption -- do not ship an empty escape hatch."

# ====================================================================== CENSUS =
# Emits one row per subject the census has something to SAY about -- it carries
# a code reach, or it is pinned and so must be checked even at zero -- plus one
# `=census=` summary row carrying the totals over EVERY subject.
#
# The marker is a non-path string on purpose: an EMPTY first field was tried
# first, and `read` with IFS=tab collapses a leading tab, so the summary row
# read as a subject named "1013" carrying 529 reaches.
#
# ONE awk process, not one per subject: the per-file shape forked 1013 times
# and made the control harness -- ten synthetic 950-file trees -- unaffordable,
# and a gate nobody can afford to run is a gate that gets skipped.
scanned="$tmp/scanned.tsv"
if ! LC_ALL=C awk -v root="$root" -v fx="$fixtures" "$SCANNER"'
    BEGIN {
        while ((getline line < fx) > 0) { split(line, f, "\t"); pinned[f[1]] = 1 }
        close(fx)
    }
    {
        rel = $0
        if (rel == "") next
        p = root "/" rel
        c = 0; a = 0; opened = 0; r = 0
        while ((r = (getline line < p)) > 0) {
            opened = 1
            c += codehits(line)
            a += allhits(line)
        }
        close(p)
        # Unreadable emits nothing, exactly as the old `[ -f ]` test did. NOT
        # zero: a zero would let a broken path read as clean.
        if (r < 0 && !opened) next
        readable++
        grand += a
        if (c > 0 || (rel in pinned)) printf "%s\t%d\t%d\n", rel, c, a
    }
    END { printf "=census=\t%d\t%d\n", readable + 0, grand + 0 }
' "$subjects" >"$scanned"; then
    die "awk aborted while counting subjects. A short count is a false pass; refusing to report one."
fi

n_scanned=$(LC_ALL=C awk -F'\t' '$1 == "=census=" { print $2; exit }' "$scanned")
all_total=$(LC_ALL=C awk -F'\t' '$1 == "=census=" { print $3; exit }' "$scanned")
[ -n "$n_scanned" ] || die "the census produced no summary row. Refusing to report off a truncated scan."
if [ "$n_scanned" -lt "$MIN_SUBJECTS" ]; then
    die "only $n_scanned .id subjects were READABLE, floor is $MIN_SUBJECTS (GAP-201).
  Enumeration or the checkout is partial. A clean report over a short list means nothing."
fi

total=0
fixture_total=0
n_carriers=0
fixture_seen="$tmp/seen.txt"
: >"$fixture_seen"
offenders="$tmp/offenders.txt"
: >"$offenders"

while IFS="$(printf '\t')" read -r rel n a; do
    [ -n "$rel" ] || continue
    [ "$rel" != "=census=" ] || continue

    cap=$(LC_ALL=C awk -F'\t' -v p="$rel" '$1 == p { print $2; exit }' "$fixtures")
    if [ -n "$cap" ]; then
        printf '%s\n' "$rel" >>"$fixture_seen"
        fixture_total=$((fixture_total + n))
        if [ "$n" -ne "$cap" ]; then
            if [ "$n" -eq 0 ]; then
                die "earned-out exemption: $rel is pinned at $cap but now carries ZERO code-position reaches.
  Delete the entry. An exemption nobody needs is an exemption waiting to be spent."
            fi
            die "pinned drift: $rel carries $n code-position reaches, the manifest pins $cap.
  The count is EXACT, not a ceiling. Re-pin it in the same commit that changed the file, and say why."
        fi
        continue
    fi

    [ "$n" -gt 0 ] || continue
    n_carriers=$((n_carriers + 1))
    total=$((total + n))
    printf '%6d  %s\n' "$n" "$rel" >>"$offenders"
done <"$scanned"

# A pin for a path that no longer exists is a live exemption with no subject --
# exactly the shape a future evasion takes.
while IFS="$(printf '\t')" read -r p c; do
    if ! LC_ALL=C awk -v p="$p" '$0 == p { found = 1 } END { exit found ? 0 : 1 }' "$fixture_seen"; then
        die "stale exemption: $p is pinned at $c but no such subject exists. Remove the entry."
    fi
done <"$fixtures"

# THE ARITHMETIC IS PRINTED, NOT ASSERTED -- this is what makes the header
# comment checkable, and the gap between the two counts is the reconciliation.
code_total=$((total + fixture_total))
note "$prog: census -- $n_scanned .id subjects."
note "$prog:   token occurrences, ALL positions ... $all_total"
note "$prog:   CODE-position reaches ............. $code_total  ($n_carriers unpinned carriers)"
note "$prog:   of those, pinned exempt ........... $fixture_total  ($n_fixtures files)"
note "$prog:   counted against budget ............ $total  (budget $STD_BUDGET)"
note "$prog:   text/comment mentions, NOT charged . $((all_total - code_total))"

if [ "$total" -gt "$STD_BUDGET" ]; then
    note ""
    note "top unpinned carriers (code-position reaches):"
    LC_ALL=C sort -rn "$offenders" | LC_ALL=C awk 'NR <= 15' >&2
    die "code-position std census is $total, budget is $STD_BUDGET. The budget is a RATCHET: it moves down, never up.
  lib/std.id: \"NO std namespace. NO std table. NO std.* spellings in Idol source.\" GAP-157 is P0 OPEN.
  If you believe the compiler should accept these spellings, you are about to write the resolver alias GAP-157 forbids. Do not."
fi

if [ "$total" -lt "$STD_BUDGET" ]; then
    note "$prog: census is $total, UNDER the pinned budget $STD_BUDGET. Lower STD_BUDGET to $total in this same commit so the ground you took cannot be given back."
fi

if [ "$mode" = census ]; then
    note "$prog: --census-only -- the added-source quarantine was SKIPPED, not passed."
    note "$prog: CENSUS OK."
    exit 0
fi

# ================================================================== QUARANTINE =

cand="$tmp/candidate.diff"
if [ -n "$diff_file" ]; then
    [ -f "$diff_file" ] || die "--diff $diff_file does not exist"
    cp "$diff_file" "$cand"
elif [ -n "$base_rev" ]; then
    git -C "$root" rev-parse --verify "${base_rev}^{commit}" >/dev/null 2>&1 || die "--base $base_rev is not a commit"
    git -C "$root" diff --no-ext-diff --no-textconv -U0 --no-renames --diff-filter=ACMR "$base_rev" -- '*.id' >"$cand" \
        || die "could not produce the candidate diff"
else
    git -C "$root" diff --cached --no-ext-diff --no-textconv -U0 --no-renames --diff-filter=ACMR -- '*.id' >"$cand" \
        || die "could not produce the staged diff"
fi

# Raw-source quarantine. A word byte on the left prevents `my_std.` from being
# mistaken for the retired root. Dotted hiding such as wrapper.std.io remains a
# violation because `std` is still used as a namespace component.
hits="$tmp/hits"
LC_ALL=C awk '
    /^\+\+\+ / { file = $2; sub(/^b\//, "", file); next }
    /^--- / { next }
    /^\+/ {
        line = substr($0, 2)
        rest = line
        while (match(rest, /(^|[^A-Za-z0-9_])std\.[A-Za-z_]/)) {
            print file "\t" line
            break
        }
    }
' "$cand" >"$hits" || die "added-source scan aborted"

n_hits=$(LC_ALL=C awk 'END { print NR + 0 }' "$hits")
n_lines=$(LC_ALL=C awk 'END { print NR + 0 }' "$cand")
if [ "$n_hits" -gt 0 ]; then
    note "new raw std. spellings:"
    LC_ALL=C awk -F'\t' '{ printf "  %s\n    + %s\n", $1, $2 }' "$hits" >&2
    die "$n_hits added line(s) reintroduce the retired std namespace. Existing classified debt remains in docs/spec/std-zero-ledger.json; it cannot be moved or bought with deletions elsewhere."
fi

note "$prog: $n_lines diff lines examined; 0 new raw std. spellings. Existing debt was not reclassified."
note "$prog: ADMISSION OK."
