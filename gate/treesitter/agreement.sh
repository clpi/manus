#!/bin/sh
# gate/treesitter/agreement.sh — GAP-134 / law.grammar.one.
#
# `docs/spec/law.md` §4: "Parser, formatter, Tree-sitter, LSP, MCP,
# documentation, and canonicalization consume projections from one grammar
# owner. They do not maintain spelling or role tables that must merely
# 'agree'." Tree-sitter maintains one. This gate does not pretend otherwise —
# it measures the disagreement exactly and refuses to let it grow.
#
# The comparison itself is gate/treesitter/agreement.id, which reads the
# owner's own Idol projection and the editor grammar, and restates no fact
# from either. This wrapper supplies the compiler and a positive control.
set -u
cd -- "$(unset CDPATH; cd -- "$(dirname -- "$0")/../.." && pwd)" || exit 2

IDOL=${IDOL:-./zig-out/bin/idol}
[ -x "$IDOL" ] || { printf 'treesitter agreement: FAIL — compiler is not executable: %s\n' "$IDOL" >&2; exit 2; }

. "./gate/realization/direct.sh"
direct_native_probe "$IDOL"
if direct_native_absent; then
  direct_native_note 'the broken-reader control in this gate is unreachable'
  exit 2
fi

# POSITIVE CONTROL. Point the gate at a tree whose owner bridge carries no
# rows and it must reach the broken-reader refusal (3), not report agreement.
# Without this the whole gate is one deleted input away from being vacuously
# green — which is exactly what happened to scripts/grammarconvergence.id,
# whose `main` only checked that two files read non-empty and exited 0 on a
# fully damaged owner.
control=$(mktemp -d "${TMPDIR:-/tmp}/idol.treesitter.agreement.XXXXXX") || exit 2
trap 'rm -rf -- "$control"' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$control/src" "$control/ext/tree-sitter-idol" "$control/gate/treesitter"
cp gate/treesitter/agreement.id "$control/gate/treesitter/agreement.id"
cp gate/treesitter/agreement.baseline "$control/gate/treesitter/agreement.baseline"
cp ext/tree-sitter-idol/grammar.js "$control/ext/tree-sitter-idol/grammar.js"
printf 'pub const rows = [0]RoleRow{};\n' >"$control/src/grammar_role_table.zig"

abs=$(unset CDPATH; cd -- "$(dirname -- "$IDOL")" && pwd)/$(basename -- "$IDOL")
(cd -- "$control" && "$abs" run gate/treesitter/agreement.id) >"$control/out" 2>&1
status=$?
if [ "$status" != 3 ]; then
  printf 'treesitter agreement control: FAIL — an owner bridge with no rows exited %s, not 3.\n' "$status" >&2
  sed -n '1,20p' "$control/out" >&2
  exit 1
fi
printf 'treesitter agreement control: PASS — an owner with no rows refuses instead of agreeing\n'

exec "$IDOL" run gate/treesitter/agreement.id
