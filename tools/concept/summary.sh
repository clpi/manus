#!/bin/sh
# tools/concept/summary.sh — batch verdict summary of the produced concept finding (GAP-120).
#
# A file is the durable home of one semantic concept. The graph PRODUCED that
# finding (identities plus demand-join refusals, schema 17) and
# `tools/concept/index.sh` joins the one-line verdict mappings into an
# index — one `index: ` line per subject naming the file beside its
# rendered verdict and identity evidence. Every face so far renders
# per-file verdicts or refuses the build over them; no face answered the
# batch reduction a build log actually needs: how many held, how many
# refused. This file is that reduction: one or more subject `.id` files as
# argv elements, one `summary: ` line on stdout. It owns the counting
# only: verdict-correctness stays owned by `gate/concept.sh` over the
# export; the single-record shape stays owned by `gate/docs.sh`; the
# one-line mapping stays owned by `gate/index.sh`; refusing a build over
# refusals stays owned by `refuse.sh`. A REFUSED subject is a count,
# never an exit code. What is measured here is the reduction only: every
# subject counted exactly once beside the verdict the index render
# produced for it, no lost subject, no invented row, no swapped count.
#
# Usage:
#   tools/concept/summary.sh <file.id> [...]   render the verdict summary
#
# Exit: 0 every subject counted; 1 any subject unreadable or unrenderable,
# or no subject given; 3 not measured (no index projection, or a render
# the environment could not measure). Protocol stdout carries complete
# summaries only — a failed batch prints no `summary: ` line — and
# diagnostics go to stderr.
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/../.." && pwd)
index=$here/index.sh

[ $# -ge 1 ] || { printf 'summary: FAIL — at least one subject file is required\n' >&2; exit 1; }

if [ ! -x "$index" ]; then
  printf 'summary: NOT MEASURED — %s is not executable (the batch index was required)\n' "$index" >&2
  exit 3
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/idol.conceptsummary.XXXXXX") || exit 3
cleanup() { rm -rf -- "$work"; }
trap 'cleanup' EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup; exit 129' HUP

if sh "$index" "$@" >"$work/index.txt" 2>"$work/index.log"; then
  index_rc=0
else
  index_rc=$?
fi

if [ "$index_rc" -eq 3 ]; then
  printf 'summary: NOT MEASURED — batch unmeasurable\n' >&2
  exit 3
fi
if [ "$index_rc" -ne 0 ]; then
  printf 'summary: FAIL — batch refused (index rc=%s)\n' "$index_rc" >&2
  tail -3 "$work/index.log" | sed 's/^/summary:   /' >&2
  exit 1
fi

n=$(grep -c '^index: ' <"$work/index.txt") || n=0
[ "$n" -eq "$#" ] || {
  printf 'summary: FAIL — index carried %s line(s) for %s subject(s); a subject is never lost or doubled\n' "$n" "$#" >&2
  exit 1
}
held=$(grep -c '^index: .* verdict: HELD' <"$work/index.txt") || held=0
refused=$(grep -c '^index: .* verdict: REFUSED' <"$work/index.txt") || refused=0
[ $((held + refused)) -eq "$n" ] || {
  printf 'summary: FAIL — %s line(s) carry neither a HELD nor a REFUSED verdict; the mapping invents\n' "$n" >&2
  exit 1
}

printf 'summary: %s held %s refused of %s\n' "$held" "$refused" "$n"
