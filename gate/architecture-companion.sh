#!/bin/sh
# gate/architecture-companion.sh — surface gates must have architectural companions.
#
#   sh gate/architecture-companion.sh

set -eu
cd "$(dirname "$0")/.." || exit 2

FAILED=0

run() {
    name=$1
    shift
    if "$@"; then
        printf '  ok    %s\n' "$name"
    else
        printf '  FAIL  %s\n' "$name" >&2
        FAILED=$((FAILED + 1))
    fi
}

printf 'architecture-companion gate: behavioral debt checks\n\n'

run gap-111-subject-first sh gate/gap-111-subject-first.sh
run gap-111-map-ambiguity sh gate/gap-111-map-ambiguity.sh
run delimiter-projection-law sh gate/delimiter-projection-law.sh

printf '\narchitecture-companion gate: %d failure(s)\n' "$FAILED"
exit "$FAILED"
