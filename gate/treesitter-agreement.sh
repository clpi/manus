#!/bin/sh
# gate/treesitter-agreement.sh — GAP-134 / law.grammar.one.
#
# `docs/spec/law.md` §4: "Parser, formatter, Tree-sitter, LSP, MCP,
# documentation, and canonicalization consume projections from one grammar
# owner. They do not maintain spelling or role tables that must merely
# 'agree'." Tree-sitter maintains one. This gate does not pretend otherwise —
# it measures the disagreement exactly and refuses to let it grow.
#
# The comparison itself is gate/treesitter.id, which reads three files and
# restates no fact from any of them. This wrapper only supplies the compiler
# and a positive control: a gate that reports agreement because a reader
# returned nothing is the failure mode the exit statuses separate (3 is a
# broken reader, 1 is a real divergence, 0 is agreement within the pin).
set -u
cd -- "$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)" || exit 2

IDOL=${IDOL:-./zig-out/bin/idol}
[ -x "$IDOL" ] || { printf 'treesitter agreement: FAIL — compiler is not executable: %s\n' "$IDOL" >&2; exit 2; }

# POSITIVE CONTROL. Point the gate at a tree whose owner table is empty and it
# must reach the broken-reader refusal (3), not report agreement. Without this
# the whole gate is one deleted input away from being vacuously green — which
# is exactly what happened to scripts/grammarconvergence.id, whose `main` only
# checked that two files read non-empty and exited 0 on a fully damaged owner.
control=$(mktemp -d "${TMPDIR:-/tmp}/idol-ts-agreement.XXXXXX") || exit 2
trap 'rm -rf -- "$control"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$control/src" "$control/ext/tree-sitter-idol" "$control/gate"
cp gate/treesitter.id "$control/gate/treesitter.id"
cp gate/treesitter.baseline "$control/gate/treesitter.baseline"
cp src/lexer.zig "$control/src/lexer.zig"
cp ext/tree-sitter-idol/grammar.js "$control/ext/tree-sitter-idol/grammar.js"
printf 'pub const rows = .{};\n' >"$control/src/grammar_role_table.zig"

abs=$(unset CDPATH; cd -- "$(dirname -- "$IDOL")" && pwd)/$(basename -- "$IDOL")
(cd -- "$control" && "$abs" run gate/treesitter.id) >"$control/out" 2>&1
status=$?
if [ "$status" != 3 ]; then
  printf 'treesitter agreement control: FAIL — an empty owner table exited %s, not 3.\n' "$status" >&2
  sed -n '1,20p' "$control/out" >&2
  exit 1
fi
printf 'treesitter agreement control: PASS — an owner with no rows refuses instead of agreeing\n'

exec "$IDOL" run gate/treesitter.id
