#!/bin/sh
# gate/vocabulary.sh — fail-closed source-declaration freeze.
#
# The compiler cannot yet export an authoritative public semantic vocabulary
# delta. Until it can, this gate refuses every newly declared non-private
# module-scope identity. It does not guess that a source binding is a relation,
# public reach, or canonical vocabulary, and it keeps no admitted-word list.
#
# A refusal is SEMANTIC-VOCABULARY-BLOCKED: improve the graph producer and this
# consumer before adding the declaration. Do not edit a registry to make the
# word pass. Existing declarations and body-only changes are outside this
# bounded freeze.

set -eu

prog=$(basename "$0")
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
subject="$here/subject.sh"
extract="$here/vocab-extract.awk"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/idol-vocabulary.XXXXXX")
trap 'rm -rf "$tmp"' EXIT INT TERM
die() { printf '%s\n' "VOCABULARY BLOCKED -- $*" >&2; exit 1; }
note() { printf '%s\n' "$*" >&2; }

[ -x "$subject" ] || die "gate/subject.sh is missing or not executable"
[ -f "$extract" ] || die "the conservative declaration classifier is missing"
(cd "$root" && sh "$subject" --tree) >/dev/null || die "candidate admission requires a real Git work tree (GAP-220)"
(cd "$root" && sh "$subject" '*.id') >/dev/null || die "Idol source enumeration failed or produced zero subjects (GAP-201)"

diff_file=""
base_rev=""
while [ $# -gt 0 ]; do
    case "$1" in
        --base) shift; [ $# -gt 0 ] || die "--base needs a revision"; base_rev=$1 ;;
        --diff) shift; [ $# -gt 0 ] || die "--diff needs a path"; diff_file=$1 ;;
        -h|--help) sed -n '1,26p' "$0"; exit 0 ;;
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

new="$tmp/declarations"
LC_ALL=C awk -v MODE=diff -f "$extract" "$cand" >"$new" || die "declaration scan aborted"
n_new=$(LC_ALL=C awk 'END { print NR + 0 }' "$new")
n_lines=$(LC_ALL=C awk 'END { print NR + 0 }' "$cand")

if [ "$n_new" -gt 0 ]; then
    note "new module-scope declarations whose semantic reach is not graph-proven:"
    LC_ALL=C awk -F'\t' '{ printf "  %-12s %-28s %s\n", $1, $2, $3 }' "$new" >&2
    die "SEMANTIC-VOCABULARY-BLOCKED: $n_new declaration(s). The current compiler does not export a trustworthy public semantic vocabulary delta, so admission fails closed. No word-list edit can waive this. Private `_` declarations, nested bindings, root applications, and body-only changes remain available."
fi

note "$prog: $n_lines diff lines examined; 0 unproven module-scope declarations."
note "$prog: VOCABULARY FREEZE OK."
