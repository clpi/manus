#!/bin/sh
# tools/concept/index.sh — batch generated-docs projection of the produced verdict (GAP-120).
#
# A file is the durable home of one semantic concept. The graph PRODUCED that
# finding (identities plus demand-join refusals, schema 17) and
# `tools/concept/doc.sh` renders one file as one markdown concept record,
# held against the graph export before a line is printed. This file is the
# batch face over that reader: one or more subject `.id` files as argv
# elements, one markdown concept index on stdout with one line per subject
# naming the file beside its rendered verdict and identity evidence. It owns
# no derivation and no enforcement: every verdict it names was rendered by
# `doc.sh` from produced rows, and a REFUSED subject is rendered, never
# refused — refusing a build over refusals is owned by `refuse.sh`. What is
# measured here is the mapping only: every subject rendered, every line
# faithful to its single-file render, no lost subject, no invented row.
#
# Usage:
#   tools/concept/index.sh <file.id> [...]   render the concept index
#
# Exit: 0 every subject rendered; 1 any subject unreadable or unrenderable,
# or no subject given; 3 not measured (no doc projection, or a render the
# environment could not measure). Protocol stdout carries index lines only;
# diagnostics go to stderr.
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/../.." && pwd)
doc=$here/doc.sh

[ $# -ge 1 ] || { printf 'index: FAIL — at least one subject file is required\n' >&2; exit 1; }

if [ ! -x "$doc" ]; then
  printf 'index: NOT MEASURED — %s is not executable (the docs projection was required)\n' "$doc" >&2
  exit 3
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/idol.conceptindex.XXXXXX") || exit 3
cleanup() { rm -rf -- "$work"; }
trap 'cleanup' EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup; exit 129' HUP

failed=0
unmeasured=0
: >"$work/lines.txt" || exit 3

for src in "$@"; do
  [ -r "$src" ] || { printf 'index: FAIL — subject unreadable: %s\n' "$src" >&2; failed=1; continue; }
  if sh "$doc" "$src" >"$work/render.txt" 2>"$work/render.log"; then
    verdict=$(grep '^verdict: ' "$work/render.txt" | head -n 1) || verdict=""
    identity=$(grep '^identity: ' "$work/render.txt" | head -n 1) || identity=""
    [ -n "$verdict" ] || { printf 'index: FAIL — rendered verdict unreadable: %s\n' "$src" >&2; failed=1; continue; }
    [ -n "$identity" ] || { printf 'index: FAIL — rendered identity unreadable: %s\n' "$src" >&2; failed=1; continue; }
    printf 'index: %s %s %s\n' "$src" "$verdict" "$identity" >>"$work/lines.txt" || { failed=1; continue; }
  else
    rc=$?
    if [ "$rc" -eq 3 ]; then
      printf 'index: NOT MEASURED — render unmeasurable: %s\n' "$src" >&2
      unmeasured=1
    else
      printf 'index: FAIL — render refused: %s\n' "$src" >&2
      tail -3 "$work/render.log" | sed 's/^/index:   /' >&2
      failed=1
    fi
    continue
  fi
done

[ "$failed" -eq 0 ] || exit 1
[ "$unmeasured" -eq 0 ] || exit 3

printf '# Concept index — %s subject(s)\n' "$#"
cat "$work/lines.txt"
