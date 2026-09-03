#!/bin/sh
# tools/concept/page.sh — batch generated-docs page of the produced verdict (GAP-120).
#
# A file is the durable home of one semantic concept. The graph PRODUCED that
# finding (identities plus demand-join refusals, schema 17) and
# `tools/concept/doc.sh` renders one file as one markdown concept record,
# held against the graph export before a line is printed, while
# `tools/concept/index.sh` joins the one-line verdict mappings into an
# index. This file is the batch page over that reader: one or more subject
# `.id` files as argv elements, one markdown concept page on stdout carrying
# every subject's FULL record as its own section, in argv order. It owns the
# joining only: verdict-correctness stays owned by `gate/concept.sh` over
# the export; the single-record shape stays owned by `gate/docs.sh`; the
# one-line mapping stays owned by `gate/index.sh`; refusing a build over
# refusals stays owned by `refuse.sh`. A REFUSED subject is a section, never
# an exit code. What is measured here is the joining only: every subject
# sectioned exactly once, every section faithful to its single-file render,
# no lost subject, no invented section, no swapped verdict.
#
# Usage:
#   tools/concept/page.sh <file.id> [...]   render the concept page
#
# Exit: 0 every subject sectioned; 1 any subject unreadable or unrenderable,
# or no subject given; 3 not measured (no doc projection, or a render the
# environment could not measure). Protocol stdout carries complete pages
# only — a failed batch prints no section — and diagnostics go to stderr.
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/../.." && pwd)
doc=$here/doc.sh

[ $# -ge 1 ] || { printf 'page: FAIL — at least one subject file is required\n' >&2; exit 1; }

if [ ! -x "$doc" ]; then
  printf 'page: NOT MEASURED — %s is not executable (the docs projection was required)\n' "$doc" >&2
  exit 3
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/idol.conceptpage.XXXXXX") || exit 3
cleanup() { rm -rf -- "$work"; }
trap 'cleanup' EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup; exit 129' HUP

failed=0
unmeasured=0
: >"$work/sections.txt" || exit 3

for src in "$@"; do
  [ -r "$src" ] || { printf 'page: FAIL — subject unreadable: %s\n' "$src" >&2; failed=1; continue; }
  if sh "$doc" "$src" >"$work/render.txt" 2>"$work/render.log"; then
    grep -Fq '# Concept record — ' "$work/render.txt" || { printf 'page: FAIL — rendered record unreadable: %s\n' "$src" >&2; failed=1; continue; }
    grep -Fq 'verdict: ' "$work/render.txt" || { printf 'page: FAIL — rendered verdict unreadable: %s\n' "$src" >&2; failed=1; continue; }
    {
      printf '## %s\n' "$src"
      cat "$work/render.txt"
      printf '\n'
    } >>"$work/sections.txt" || { failed=1; continue; }
  else
    rc=$?
    if [ "$rc" -eq 3 ]; then
      printf 'page: NOT MEASURED — render unmeasurable: %s\n' "$src" >&2
      unmeasured=1
    else
      printf 'page: FAIL — render refused: %s\n' "$src" >&2
      tail -3 "$work/render.log" | sed 's/^/page:   /' >&2
      failed=1
    fi
    continue
  fi
done

[ "$failed" -eq 0 ] || exit 1
[ "$unmeasured" -eq 0 ] || exit 3

printf '# Concept page — %s subject(s)\n\n' "$#"
cat "$work/sections.txt"
