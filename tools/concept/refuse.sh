#!/bin/sh
# tools/concept/refuse.sh — build-refusal consumer of the produced concept verdict (GAP-120).
#
# A file is the durable home of one semantic concept. The graph PRODUCED that
# finding (identities plus demand-join refusals, schema 17) and `idol graph`
# exports it as `concepts[]`/`refusals[]`. Every consumer so far READS the
# verdict — the gate holds it, the docs reader renders it, the MCP and LSP
# contracts carry it. This file is the consumer that REFUSES A BUILD over it:
# one or more subject `.id` files as argv elements, one verdict line per file
# on stdout, and a nonzero exit naming the refused module when any subject's
# export carries a produced refusal. It owns no derivation: every refusal it
# reports was produced on the graph and re-verified on export before this
# file saw it; the gate never re-decides, it reads what was produced.
#
# Usage:
#   tools/concept/refuse.sh <file.id> [...]   refuse the build over refusals[]
#
# Exit: 0 every subject held (no produced refusal); 1 any subject refused,
# unreadable, or unparseable, or no subject given; 3 not measured (no
# compiler or no jq). Protocol stdout carries verdict lines only;
# diagnostics go to stderr.
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/../.." && pwd)
IDOL=${IDOL:-"$root/zig-out/bin/idol"}

[ $# -ge 1 ] || { printf 'refuse: FAIL — at least one subject file is required\n' >&2; exit 1; }

if [ ! -x "$IDOL" ]; then
  printf 'refuse: NOT MEASURED — %s is not a compiler (a checked graph was required)\n' "$IDOL" >&2
  exit 3
fi

command -v jq >/dev/null 2>&1 || {
  printf 'refuse: NOT MEASURED — jq is required to read the produced verdict\n' >&2
  exit 3
}

work=$(mktemp -d "${TMPDIR:-/tmp}/idol.conceptrefuse.XXXXXX") || exit 3
cleanup() { rm -rf -- "$work"; }
trap 'cleanup' EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup; exit 129' HUP

refused=0
for src in "$@"; do
  [ -r "$src" ] || { printf 'refuse: FAIL — subject unreadable: %s\n' "$src" >&2; refused=1; continue; }
  if ! "$IDOL" graph "$src" >"$work/graph.json" 2>"$work/graph.log"; then
    printf 'refuse: FAIL — graph did not render: %s\n' "$src" >&2
    refused=1
    continue
  fi
  # The export must carry the produced verdict, or there is nothing to enforce.
  jq -e '.concepts | type == "array"' <"$work/graph.json" >/dev/null 2>&1 || {
    printf 'refuse: FAIL — graph carries no produced concept verdict: %s\n' "$src" >&2
    refused=1
    continue
  }
  jq -e '.refusals | type == "array"' <"$work/graph.json" >/dev/null 2>&1 || {
    printf 'refuse: FAIL — graph carries no produced refusal verdict: %s\n' "$src" >&2
    refused=1
    continue
  }
  n=$(jq -r '.refusals | length' <"$work/graph.json" 2>/dev/null) || n=""
  [ -n "$n" ] || { printf 'refuse: FAIL — refusal verdict unreadable: %s\n' "$src" >&2; refused=1; continue; }
  if [ "$n" -gt 0 ]; then
    jq -r '.refusals[] | "refuse: REFUSED \(.module) \(.reason) split=\(.split | join(","))"' \
      <"$work/graph.json" 2>/dev/null || {
      printf 'refuse: FAIL — refusal verdict unreadable: %s\n' "$src" >&2
      refused=1
      continue
    }
    refused=1
  else
    printf 'refuse: HELD %s\n' "$src"
  fi
done

[ "$refused" -eq 0 ] || exit 1
exit 0
