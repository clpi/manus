#!/bin/sh
# tools/concept/site.sh — batch generated-docs site of the produced verdict (GAP-120).
#
# A file is the durable home of one semantic concept. The graph PRODUCED that
# finding (identities plus demand-join refusals, schema 17) and
# `tools/concept/doc.sh` renders one file as one markdown concept record,
# held against the graph export before a line is printed, while
# `tools/concept/index.sh` joins the one-line verdict mappings into an
# index and `tools/concept/page.sh` joins the full records into a page.
# This file is the batch site over those faces: one or more subject `.id`
# files as argv elements, one markdown concept site on stdout carrying the
# batch index block followed by the batch page sections, in argv order. It
# owns the joining only: verdict-correctness stays owned by
# `gate/concept.sh` over the export; the single-record shape stays owned by
# `gate/docs.sh`; the one-line mapping stays owned by `gate/index.sh`; the
# section joining stays owned by `gate/page.sh`; refusing a build over
# refusals stays owned by `refuse.sh`. A REFUSED subject is a line plus a
# section, never an exit code. What is measured here is the joining only:
# every subject indexed and sectioned exactly once, the index block and the
# page sections agreeing on every produced verdict, no lost subject, no
# invented row, no swapped verdict.
#
# Usage:
#   tools/concept/site.sh <file.id> [...]   render the concept site
#
# Exit: 0 every subject indexed and sectioned; 1 any subject unreadable or
# unrenderable, or no subject given; 3 not measured (no index/page
# projection, or a render the environment could not measure). Protocol
# stdout carries complete sites only — a failed batch prints no index line
# and no section — and diagnostics go to stderr.
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/../.." && pwd)
index=$here/index.sh
page=$here/page.sh

[ $# -ge 1 ] || { printf 'site: FAIL — at least one subject file is required\n' >&2; exit 1; }

if [ ! -x "$index" ]; then
  printf 'site: NOT MEASURED — %s is not executable (the batch index was required)\n' "$index" >&2
  exit 3
fi
if [ ! -x "$page" ]; then
  printf 'site: NOT MEASURED — %s is not executable (the batch page was required)\n' "$page" >&2
  exit 3
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/idol.conceptsite.XXXXXX") || exit 3
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
if sh "$page" "$@" >"$work/page.txt" 2>"$work/page.log"; then
  page_rc=0
else
  page_rc=$?
fi

if [ "$index_rc" -eq 1 ] || [ "$page_rc" -eq 1 ]; then
  printf 'site: FAIL — batch refused (index rc=%s page rc=%s)\n' "$index_rc" "$page_rc" >&2
  [ "$index_rc" -eq 1 ] && tail -3 "$work/index.log" | sed 's/^/site:   /' >&2
  [ "$page_rc" -eq 1 ] && tail -3 "$work/page.log" | sed 's/^/site:   /' >&2
  exit 1
fi
if [ "$index_rc" -eq 3 ] || [ "$page_rc" -eq 3 ]; then
  printf 'site: NOT MEASURED — batch unmeasurable (index rc=%s page rc=%s)\n' "$index_rc" "$page_rc" >&2
  exit 3
fi
if [ "$index_rc" -ne 0 ] || [ "$page_rc" -ne 0 ]; then
  printf 'site: FAIL — batch refused (index rc=%s page rc=%s)\n' "$index_rc" "$page_rc" >&2
  exit 1
fi

printf '# Concept site — %s subject(s)\n\n' "$#"
cat "$work/index.txt"
printf '\n'
cat "$work/page.txt"
