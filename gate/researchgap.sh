#!/bin/sh
# gate/researchgap.sh — research GAP admission census.
#
#   sh gate/researchgap.sh
#
# Delegates to tools/node/dev/gapc0: every gaps/GAP-*.md numbered >= 175 plus
# gaps/RESEARCH-SPINE.md must carry the complete zero-delta C0 alignment block
# (schema home: gaps/RESEARCH-SPINE.md) and avoid the two retired spellings —
# the receiver parameter and the open type. The former
# docs/research-gap-admission.md row-count pin was a shadow of the schema; this
# gate now checks the real GAPs instead of a copy of the law, so it fails when
# a GAP drifts, not when a table loses a row.
#
# Exit 0 = clean. Non-zero = violation count (2 = census ran on nothing).

set -u
cd "$(dirname "$0")/.." || exit 2
exec tools/node/dev/gapc0
