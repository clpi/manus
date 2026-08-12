#!/bin/sh
# Run the repository-native idiom gate over the EXACT working-tree diff of
# canonical/historical Idol source. This is migration pressure over text, not
# semantic proof. Do not suppress, bypass, weaken, or route around a finding.
#
# Usage: gates.sh [path-glob ...]   (default: '*.id' '*.id')
set -eu
repo="$(cd "$(dirname "$0")/../../../.." && pwd)"
cd "$repo"
duo="$repo/zig-out/bin/duo"
gate="$repo/scripts/idiomgate.id"

if [ ! -x "$duo" ]; then
  echo "idiomgate: missing compiler artifact: $duo" >&2
  echo "  build first:  (cd $repo && zig build --summary all)" >&2
  exit 1
fi

diff="$(mktemp -t idiomgate.XXXXXX)"
trap 'rm -f "$diff"' EXIT
if [ "$#" -gt 0 ]; then
  git diff -U0 -- "$@" > "$diff"
else
  git diff -U0 -- '*.id' '*.id' > "$diff"
fi

if [ ! -s "$diff" ]; then
  echo "idiomgate: no working-tree diff for *.id/*.id"
  exit 0
fi

DUOGATEDIFF="$diff" "$duo" run --backend=c "$gate"
