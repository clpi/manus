#!/bin/sh
# gate/admission.sh — the std ratchet. Mechanical. Not arguable.
#
# WHY THIS FILE EXISTS, stated so nobody has to reconstruct it:
#   lib/std.id is a seven-line tombstone. GAP-157 is P0 OPEN and says the std
#   namespace does not come back "not as a migration alias". The compiler
#   correctly REFUSES `std.*` source. And yet hundreds of `std.` spellings sit
#   in tracked .id files, because they were written, merged, and only later
#   diagnosed -- by other agents -- as a COMPILER defect. One of those agents
#   nearly added a resolver alias to make the forbidden source compile.
#
#   This gate exists so that no merge depends on an agent reasoning correctly
#   about any of the above. It counts bytes and compares to a pinned integer.
#
# TWO RULES, and the second is strictly stronger than the first:
#   (A) CENSUS.  Total canonical `std.` spellings over tracked .id source,
#       minus files pinned in gate/std-fixtures.manifest, must not EXCEED the
#       pinned budget. This is a ratchet: it only ever moves down.
#   (B) ADDED LINES.  No ADDED line in the candidate diff may introduce a
#       `std.` spelling. At all. This is independent of (A) on purpose:
#       a migration that deletes 10 spellings and adds 1 lowers the census
#       and STILL FAILS here. You may not buy a new one with an old one.
#
# NON-NEGOTIABLES this file honours:
#   * FAILS on zero subjects (GAP-201). A gate that examines nothing and
#     reports clean is the defect this repository keeps re-finding. Most
#     recently 44 gates enumerated via `git ls-files`, which returns ZERO in a
#     `git archive` mirror, so all 44 "passed" while reading no bytes
#     (GAP-220). Enumeration here falls back to `find` and then asserts a
#     hard floor on the subject count before it will report anything.
#   * Never reads `$?` after a pipe. Every stage that matters writes to a
#     file and is tested with `if ! cmd`.
#   * Uses awk, not `grep`. `grep` on a contributor machine may be a shell
#     function wrapping ugrep, whose regex dialect differs.
#   * LC_ALL=C. At least one tracked .id file contains bytes that abort a
#     UTF-8 awk mid-stream -- which would silently SHORTEN the count.
#   * Does NOT invoke `idol check`. `check` was shown to accept a read of a
#     field a declared record does not have; check-pass is not law.
#
# USAGE:
#   gate/admission.sh                  census + staged-diff added-line rule
#   gate/admission.sh --base <rev>     census + <rev>..worktree added-line rule
#   gate/admission.sh --diff <file>    census + added-line rule over a diff file
#   gate/admission.sh --census-only    census only (explicit; the added-line
#                                      rule is SKIPPED, never silently passed)

set -eu

# ---------------------------------------------------------------- constants --
# Pinned 2026-08-22 against idol@40de041c55541c5b86781135858ecc8a7d5c2231.
#
# DENOMINATOR, with power, because a numerator alone is a rumour:
#   subjects enumerated .................. 1010 tracked .id files
#   files carrying >=1 std. spelling ......   86
#   total canonical spellings ............  512
#   of those, in pinned fixtures .........   39  (6 files, gate/std-fixtures.manifest)
#   BUDGET (census subject) ..............  473
# The single largest contributor is `std.script` at 304 occurrences.
STD_BUDGET=473

# Floor on enumerated subjects. Not a round guess: today's tree has 1010
# tracked .id files. Anything under this floor means enumeration broke --
# an archive mirror, a partial checkout, a bad pathspec -- and a broken
# enumeration must FAIL, never report clean.
MIN_SUBJECTS=900

# The canonical spelling. `std` bounded on the left by a non-identifier byte
# (or start of line), a literal dot, then an identifier start. Deliberately
# matches `law.std.zero` too: dotted-path hiding is not a loophole, it is a
# manifest entry.
#
# The doubled backslash is load-bearing: `awk -v` processes escape sequences in
# the assigned value, so a single `\\.` would reach the regex engine as a bare
# `.` -- ANY byte -- and `stdXio` would count as a std spelling.
STD_RE='(^|[^A-Za-z0-9_])std\\.[A-Za-z_]'

# ------------------------------------------------------------------ plumbing --
prog=$(basename "$0")
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
manifest="$root/gate/std-fixtures.manifest"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/idol-admission.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM

die() { printf '%s\n' "ADMISSION BLOCKED -- $*" >&2; exit 1; }
note() { printf '%s\n' "$*" >&2; }

# count_std <file>  -> prints an integer, nonzero exit if awk fails
count_std() {
    LC_ALL=C awk -v re="$STD_RE" '
        BEGIN { n = 0 }
        { s = $0; while (match(s, re)) { n++; s = substr(s, RSTART + RLENGTH) } }
        END { print n }
    ' "$1"
}

# ----------------------------------------------------------------- arguments --
mode=full
diff_file=""
base_rev=""
while [ $# -gt 0 ]; do
    case "$1" in
        --census-only) mode=census ;;
        --base) shift; [ $# -gt 0 ] || die "--base needs a revision"; base_rev="$1" ;;
        --diff) shift; [ $# -gt 0 ] || die "--diff needs a path"; diff_file="$1" ;;
        -h|--help) sed -n '1,40p' "$0"; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
    shift
done

# ================================================================ ENUMERATION ==
# git first, find second, hard floor third. GAP-220: `git ls-files` in a
# `git archive` mirror returns zero and every consumer reports clean.
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
    # Paths MUST come out relative to $root, exactly as `git ls-files` gives
    # them. The manifest keys on repo-relative paths; absolute paths here
    # would silently match nothing, every fixture would read as debt, and the
    # archive-mirror case -- the one this fallback exists for -- would be the
    # one case where exemptions quietly stop applying.
    if ! ( cd "$root" && find . -name '*.id' -type f \
            -not -path './.git/*' -not -path '*/zig-cache/*' \
            -not -path '*/.zig-cache/*' -not -path '*/zig-out/*' \
            -print ) | LC_ALL=C sed 's|^\./||' >"$subjects"; then
        die "subject enumeration failed outright (find)."
    fi
    enum_via=find
    n_subjects=$(LC_ALL=C awk 'END { print NR }' "$subjects")
fi

if [ "$n_subjects" -eq 0 ]; then
    die "ZERO subjects enumerated (GAP-201). A gate that examines nothing does not pass; it fails."
fi
if [ "$n_subjects" -lt "$MIN_SUBJECTS" ]; then
    die "only $n_subjects subjects enumerated via $enum_via, floor is $MIN_SUBJECTS (GAP-201).
  Enumeration is broken -- archive mirror, partial checkout, or bad pathspec.
  A short subject list must fail, because a clean report over it means nothing."
fi

# ===================================================================== MANIFEST =
[ -f "$manifest" ] || die "gate/std-fixtures.manifest is missing. Without it every fixture reads as debt and the budget is meaningless."

fixtures="$tmp/fixtures.txt"
if ! LC_ALL=C awk '
    /^[[:space:]]*(#|$)/ { next }
    { sub(/[[:space:]]*#.*$/, ""); if (NF < 2) { bad = 1; exit } print $1 "\t" $2 }
    END { if (bad) exit 3 }
' "$manifest" >"$fixtures"; then
    die "gate/std-fixtures.manifest is malformed (every entry needs '<path> <exact-count>')."
fi

n_fixtures=$(LC_ALL=C awk 'END { print NR }' "$fixtures")
[ "$n_fixtures" -gt 0 ] || die "gate/std-fixtures.manifest classifies zero files. If nothing is a fixture, delete the file and drop the exemption -- do not ship an empty escape hatch."

# ======================================================================= CENSUS =
total=0
fixture_total=0
fixture_seen="$tmp/seen.txt"
: >"$fixture_seen"
offenders="$tmp/offenders.txt"
: >"$offenders"

while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    f="$root/$rel"
    [ -f "$f" ] || continue
    if ! n=$(count_std "$f"); then
        die "awk aborted while counting $rel. A short count is a false pass; refusing to report one."
    fi
    [ "$n" -gt 0 ] || continue

    cap=$(LC_ALL=C awk -F'\t' -v p="$rel" '$1 == p { print $2; exit }' "$fixtures")
    if [ -n "$cap" ]; then
        printf '%s\n' "$rel" >>"$fixture_seen"
        fixture_total=$((fixture_total + n))
        if [ "$n" -ne "$cap" ]; then
            die "pinned fixture drift: $rel carries $n canonical std. spellings, manifest pins $cap.
  The manifest count is EXACT, not a ceiling. Re-pin it in the same commit that changed the file, and say why."
        fi
    else
        total=$((total + n))
        printf '%6d  %s\n' "$n" "$rel" >>"$offenders"
    fi
done <"$subjects"

# Stale manifest entries are a live exemption for a file that no longer needs
# one -- exactly the shape a future evasion takes.
while IFS="$(printf '\t')" read -r p c; do
    if ! LC_ALL=C awk -v p="$p" '$0 == p { found = 1 } END { exit found ? 0 : 1 }' "$fixture_seen"; then
        die "stale fixture exemption: $p is pinned at $c in the manifest but carries no canonical std. spelling (or no longer exists). Remove the entry."
    fi
done <"$fixtures"

note "$prog: census via $enum_via -- $n_subjects .id subjects, $((total + fixture_total)) canonical std. spellings total, $fixture_total in $n_fixtures pinned fixtures, $total counted against budget $STD_BUDGET."

if [ "$total" -gt "$STD_BUDGET" ]; then
    note ""
    note "top non-fixture carriers:"
    LC_ALL=C sort -rn "$offenders" | LC_ALL=C awk 'NR <= 15' >&2
    die "std census is $total, budget is $STD_BUDGET. The budget is a RATCHET: it moves down, never up.
  lib/std.id: \"NO std namespace. NO std table. NO std.* spellings in Idol source.\" GAP-157 is P0 OPEN.
  If you believe the compiler should accept these spellings, you are about to write the resolver alias GAP-157 forbids. Do not."
fi

if [ "$total" -lt "$STD_BUDGET" ]; then
    note "$prog: census is $total, UNDER the pinned budget $STD_BUDGET. Lower STD_BUDGET to $total in this same commit so the ground you took cannot be given back."
fi

# ================================================================= ADDED LINES ==
if [ "$mode" = census ]; then
    note "$prog: --census-only -- the added-line rule was SKIPPED, not passed."
    note "$prog: CENSUS OK."
    exit 0
fi

cand="$tmp/candidate.diff"
if [ -n "$diff_file" ]; then
    [ -f "$diff_file" ] || die "--diff $diff_file does not exist."
    cp "$diff_file" "$cand"
elif [ "$enum_via" != git ]; then
    die "no .git here, so the added-line rule cannot be evaluated. Pass --diff <file>, or --census-only to state in the open that you are skipping it. 'Could not check' is not 'passed'."
elif [ -n "$base_rev" ]; then
    git -C "$root" rev-parse --verify "${base_rev}^{commit}" >/dev/null 2>&1 \
        || die "--base $base_rev is not a commit."
    if ! git -C "$root" diff -U0 --no-renames --diff-filter=ACMR "$base_rev" -- '*.id' >"$cand"; then
        die "could not produce a diff against $base_rev."
    fi
else
    if ! git -C "$root" diff --cached -U0 --no-renames --diff-filter=ACMR -- '*.id' >"$cand"; then
        die "could not produce the staged diff."
    fi
fi

# Added lines only: `+` but not the `+++` file header. Fixture files are
# exempt from the added-line rule ONLY up to their pinned exact count, which
# the census above already enforced to the byte.
added_hits="$tmp/added.txt"
if ! LC_ALL=C awk -v re="$STD_RE" -v fx="$fixtures" '
    BEGIN {
        while ((getline line < fx) > 0) {
            split(line, a, "\t"); exempt[a[1]] = 1
        }
        file = "(unknown)"
    }
    /^\+\+\+ / {
        p = $2; sub(/^b\//, "", p); file = p; next
    }
    /^--- / { next }
    /^\+/ {
        s = substr($0, 2)
        if (file in exempt) next
        t = s
        while (match(t, re)) {
            print file "\t" s
            t = substr(t, RSTART + RLENGTH)
            break
        }
    }
' "$cand" >"$added_hits"; then
    die "awk aborted while scanning added lines. Refusing to report a pass off a truncated scan."
fi

n_added=$(LC_ALL=C awk 'END { print NR }' "$added_hits")
if [ "$n_added" -gt 0 ]; then
    note ""
    note "ADDED lines introducing a canonical std. spelling:"
    LC_ALL=C awk -F'\t' '{ printf "  %s\n    + %s\n", $1, $2 }' "$added_hits" >&2
    note ""
    die "$n_added added line(s) introduce a std. spelling.
  This rule is SEPARATE from and STRICTER than the census. Removing ten
  elsewhere does not buy one here. The census budget is not a currency.
  Repair, not migration alias: worlds are the capability namespaces --
  stdin:read() / path:read() / subject:relation(). See docs/spec/world.md, GAP-157."
fi

n_diff_lines=$(LC_ALL=C awk 'END { print NR }' "$cand")
note "$prog: added-line rule OK -- $n_diff_lines diff lines examined, 0 new std. spellings."
note "$prog: ADMISSION OK."
exit 0
