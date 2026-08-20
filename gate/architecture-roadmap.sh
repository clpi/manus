#!/bin/sh
# gate/architecture-roadmap.sh — planned architecture-negative gates not yet executable.
#
#   sh gate/architecture-roadmap.sh
#
# Always exits 0. Lists behavioral gates awaiting harnesses; does not block CI.

set -u
cd "$(dirname "$0")/.." || exit 2

cat <<'EOF'
architecture-roadmap: planned behavioral gates (not yet blocking)

  GRAPH-ONLY-REALIZATION     poison AST after graph closure; supported path emits
  HOME-MOVE                  move relation file; semantic application unchanged
  MODULE-TOPOLOGY            perturb filesystem layout after ingress; ids stable
  REPRESENTATION-HISTORY       exploded locals vs aggregate; same realization set
  ZERO-TEXT-SEMANTICS        rename locals post-resolution; machine unchanged
  EFFECT-NO-RESULT           unused result + required effect; call remains
  RESULT-NO-EFFECT           unused result + pure; call may disappear

Manifest: docs/architecture-negative-controls.md
Static/debt gates: sh gate/architecture-negative.sh
EOF

exit 0
