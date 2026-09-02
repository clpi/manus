#!/bin/sh
# GAP-221 regression control: deletion witness for binding-identity fix.
# The two-store shape (shadow check followed by spelling lookup) is the defect.
# This gate verifies that moduleFieldWord returns both type and storage key,
# eliminating the ctx.module_globals.storageKey by-spelling lookup after
# the binding check.
#
#   sh gate/gap-221-shadowstore.sh

set -eu

root=${GAP221_ROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}

if [ "${IDOL_LOCK_HELD:-0}" != 1 ]; then
    exec "$root/tools/node/dev/idol-lock" -- "$0" "$@"
fi

fail() {
    printf 'gap-221-shadowstore gate: FAIL %s\n' "$1" >&2
    exit 1
}

# Verify the compiler builds
cd "$root" || fail "cannot cd to $root"
zig build >/dev/null 2>&1 || fail "compiler build failed"

# Verify the deleted function is gone (deletion witness from session fix)
if grep -q "fn bodyDeclaresBinding" src/dnir_lower.zig; then
    fail "bodyDeclaresBinding still exists (deletion witness unmet)"
fi

# Verify the new binding-identity approach is in place
if ! grep -q "bindingNamedIn" src/dnir_lower.zig; then
    fail "bindingNamedIn not found (binding-identity approach missing)"
fi

# Verify moduleFieldWord returns both type and storage key
if ! grep -q "moduleFieldWord.*struct { RT, \[\]const u8 }" src/dnir_lower.zig; then
    fail "moduleFieldWord does not return struct with type and storage key"
fi

# Verify the two-store shape is eliminated: no ctx.module_globals.storageKey
# after moduleFieldWord call
if grep -A5 "moduleFieldWord" src/dnir_lower.zig | grep -q "ctx.module_globals.storageKey"; then
    fail "ctx.module_globals.storageKey still used after moduleFieldWord (two-store shape persists)"
fi

printf 'gap-221-shadowstore gate: PASS\n'
