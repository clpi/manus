#!/bin/sh
# gate/researchgap.sh — research GAP admission census.
#
#   sh gate/researchgap.sh
#
# Delegates to tools/node/dev/gapc0. Every GAP that DECLARES
# `**Kind:** research_gap`, plus gaps/RESEARCH-SPINE.md, must carry the
# complete zero-delta C0 alignment block. Every GAP-*.md numbered >= 170 --
# whatever its kind -- must pass the role checks of law.md 111-115: no
# parameter-position receiver binding, no annotation-position open type or void
# descriptor. Canonical relation faces (xs:any(p), `:any`) pass; canonicality
# belongs to the role, not the word. The former
# docs/research-gap-admission.md row-count pin was a shadow of the schema; this
# gate checks the real GAPs instead of a copy of the law, so it fails when a
# GAP drifts, not when a table loses a row.
#
# THE SUBJECT IS THE DECLARED KIND. Selecting `>= 175` was a proxy that held on
# the day it was written and stopped holding at GAP-203, when the same number
# line started carrying defect reports. Measured at 64928599 the proxy produced
# 18 violations, ALL of them `wrong_answer` / `crash` / `regression` /
# `evidence_gap` / architecture GAPs convicted of missing a research admission
# block they were never required to carry -- while the 21 real research GAPs
# were all compliant. Worse, a GAP with no block `return`ed before the role
# checks, so 13 GAPs were exempt from law.md 111-115 entirely.
#
# Exit 0 = clean. Non-zero = violation count (2 = the census selected nothing).

set -u
cd "$(dirname "$0")/.." || exit 2
exec tools/node/dev/gapc0
