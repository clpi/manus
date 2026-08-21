#!/bin/sh
# Counterfactual proof that cache identity consumes the executed lexer producer,
# while the former host scanner remains available only as a differential oracle.

set -eu

root=${TAINT_ROOT:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}
idol=${IDOL_BIN:-"$root/zig-out/bin/idol"}
main="$root/src/main.zig"
dispatch="$root/src/lexer_dispatch.zig"

fail() {
    printf 'taint gate: FAIL %s\n' "$1" >&2
    exit 1
}

[ -r "$main" ] || fail "missing source: $main"
[ -r "$dispatch" ] || fail "missing source: $dispatch"
[ -x "$idol" ] || fail "compiler is not executable: $idol"
[ "$(uname -s)" = Darwin ] || fail 'counterfactual interposition currently requires Darwin'
command -v clang >/dev/null 2>&1 || fail 'clang is unavailable'

quotient=$(
    awk '
        /^fn hashSourceQuotient\(/ { inside = 1 }
        inside { print }
        inside && /^}/ { exit }
    ' "$main"
)
oracle=$(
    awk '
        /^fn tokenizeHost\(/ { inside = 1 }
        inside { print }
        inside && /^}/ { exit }
    ' "$dispatch"
)

[ -n "$quotient" ] || fail 'cache quotient subject is absent'
[ -n "$oracle" ] || fail 'host oracle subject is absent'
printf '%s\n' "$quotient" | grep -Fq 'routeThroughDuoLexer(' \
    || fail 'cache quotient does not execute the producer route'
if printf '%s\n' "$quotient" | grep -Fq '.next_tok('; then
    fail 'cache quotient still scans through the former host'
fi
printf '%s\n' "$oracle" | grep -Fq '.next_tok(' \
    || fail 'differential host oracle was deleted'
grep -Fq 'const host = try tokenizeHost(' "$dispatch" \
    || fail 'differential no longer observes the host oracle'

work=$(mktemp -d "${TMPDIR:-/tmp}/idol-taint.XXXXXX")
cleanup() {
    rm -rf "$work"
}
trap cleanup EXIT INT TERM

# The replacee is the former host scanner's generated keyword edge. A direct
# call must die with 86, proving the poison is live; an ordinary compilation
# must survive, proving no production cache decision observes that edge.
clang -dynamiclib -Wl,-undefined,dynamic_lookup -x c - \
    -o "$work/poison.dylib" <<'EOF'
#include <stdint.h>
#include <stdlib.h>
extern int64_t duo_keyword_classify(const char *);
static int64_t poison(const char *word) {
    (void)word;
    _Exit(86);
}
__attribute__((used)) static const struct {
    const void *replacement;
    const void *replacee;
} interposers[] __attribute__((section("__DATA,__interpose"))) = {
    { (const void *)poison, (const void *)duo_keyword_classify },
};
EOF

clang -x c - -o "$work/control" <<'EOF'
#include <stdint.h>
__attribute__((weak, noinline)) int64_t duo_keyword_classify(const char *word) {
    (void)word;
    return 0;
}
int main(void) {
    return (int)duo_keyword_classify("fun");
}
EOF

set +e
DYLD_INSERT_LIBRARIES="$work/poison.dylib" "$work/control"
control_status=$?
set -e
[ "$control_status" -eq 86 ] \
    || fail "counterfactual poison is not live (control status $control_status)"

cp "$idol" "$work/idol"
touch "$work/idol"
cat >"$work/probe.id" <<'EOF'
helper: i64 = ()
    42
main: i64 = ()
    helper()
EOF
if ! DYLD_INSERT_LIBRARIES="$work/poison.dylib" \
    "$work/idol" compile --backend=direct "$work/probe.id" \
    -o "$work/probe.out" >"$work/compile.log" 2>&1; then
    sed -n '1,120p' "$work/compile.log" >&2
    fail 'former-host death reached production compilation'
fi
[ -x "$work/probe.out" ] || fail 'counterfactual compile emitted no executable'

production_scans=$(printf '%s\n' "$quotient" | awk 'index($0, ".next_tok(") { n += 1 } END { print n + 0 }')
oracle_scans=$(printf '%s\n' "$oracle" | awk 'index($0, ".next_tok(") { n += 1 } END { print n + 0 }')
bridge_externs=$(
    awk '/^extern fn / { n += 1 } END { print n + 0 }' \
        "$root/src/lexer_bridge.zig" \
        "$root/src/lexer_dispatch.zig" \
        "$root/src/keyword_bridge.zig"
)
oracle_cases=$(awk 'index($0, "differential(a") { n += 1 } END { print n + 0 }' "$dispatch")

printf 'TAINT producer.route=1 production.host.scan=%s oracle.host.scan=%s bridge.extern=%s oracle.case.group=%s\n' \
    "$production_scans" "$oracle_scans" "$bridge_externs" "$oracle_cases"
printf 'SUBJECT revision=%s dirty=%s platform=darwin compiler=%s\n' \
    "$(git -C "$root" rev-parse HEAD)" \
    "$(if git -C "$root" diff --quiet && git -C "$root" diff --cached --quiet; then printf clean; else printf dirty; fi)" \
    "$idol"
printf 'taint gate: PASS\n'
