#!/bin/sh
# gate/researchgap.sh — research GAP admission census.
#
#   sh gate/researchgap.sh
#
# Delegates to tools/node/dev/gapc0: every gaps/GAP-*.md numbered >= 175 plus
# gaps/RESEARCH-SPINE.md must carry the complete zero-delta C0 alignment block
# and pass the role checks of law.md 111-115: no parameter-position receiver
# binding, no annotation-position open type or void descriptor. Canonical
# relation faces (xs:any(p), `:any`) pass; canonicality belongs to the role,
# not the word. The former
# docs/research-gap-admission.md row-count pin was a shadow of the schema; this
# gate now checks the real GAPs instead of a copy of the law, so it fails when
# a GAP drifts, not when a table loses a row.
#
# Exit 0 = clean. Non-zero = violation count (2 = census ran on nothing).

set -u
cd "$(dirname "$0")/.." || exit 2
exec tools/node/dev/gapc0
