#!/bin/sh
# gate/admission.sh — added-source quarantine for the retired std namespace.
#
# This gate does not count the current tree and does not decide which existing
# occurrences are code, text, comments, compatibility, or history. That exact
# classification already lives in docs/spec/std-zero-ledger.json. The previous
# gate replaced it with a position-blind 473-token census and therefore created
# a second, false authority one commit after the ledger was published.
#
# The enforceable rule at this boundary is smaller and stronger: a candidate
# may introduce no new raw `std.` spelling in Idol source. Deleting or rewriting
# old debt is admitted; moving or re-adding it is not. This is deliberately a
# source quarantine, not a claim that comments or strings carry semantic reach.
#
# Usage:
#   gate/admission.sh
#   gate/admission.sh --base <revision>
#   gate/admission.sh --diff <diff-file>

set -eu

prog=$(basename "$0")
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
subject="$here/subject.sh"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/idol-admission.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM

die() { printf '%s\n' "ADMISSION BLOCKED -- $*" >&2; exit 1; }
note() { printf '%s\n' "$*" >&2; }

[ -x "$subject" ] || die "gate/subject.sh is missing or not executable."
(cd "$root" && sh "$subject" --tree) >/dev/null || die "candidate admission requires a real Git work tree (GAP-220)."
(cd "$root" && sh "$subject" '*.id') >/dev/null || die "Idol source enumeration failed or produced zero subjects (GAP-201)."

diff_file=""
base_rev=""
while [ $# -gt 0 ]; do
    case "$1" in
        --base) shift; [ $# -gt 0 ] || die "--base needs a revision"; base_rev=$1 ;;
        --diff) shift; [ $# -gt 0 ] || die "--diff needs a path"; diff_file=$1 ;;
        -h|--help) sed -n '1,28p' "$0"; exit 0 ;;
        *) die "unknown argument: $1" ;;
    esac
    shift
done
[ -z "$diff_file" ] || [ -z "$base_rev" ] || die "--base and --diff are mutually exclusive"

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
