#!/bin/sh
# gate/grammar-projection.sh — the grammar-role counterfactual.
#
# GAP-134 / law.grammar.one: lib/compiler/token.id is the ONE executable
# grammar-fact owner. src/grammar_role_table.zig (host bridge, read by the
# production parser) and lib/token/grammarrole.id (Idol projection) are its
# generated outputs.
#
# A tracked generated artifact that may drift from its owner is not generated:
# damaging the owner then changes NOTHING until somebody hand-regenerates, and
# "the grammar is Idol owned" becomes a claim with no counterfactual. That is
# exactly what src/lexer_tokenize.c did in this tree (build.zig, lexer-artifact).
#
# This step regenerates privately and fails unless both artifacts are
# byte-identical. The mandatory damage control proves that a producer which
# exits zero after emitting malformed output cannot alter either tracked file.
set -u
cd -- "$(unset CDPATH; cd -- "$(dirname -- "$0")/.." && pwd)" || exit 2

IDOL=${IDOL-./zig-out/bin/idol}

IDOL="$IDOL" ./tools/node/dev/grammar/emit --selftest || exit $?
IDOL="$IDOL" exec ./tools/node/dev/grammar/emit --check
