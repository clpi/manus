#!/usr/bin/env bash
# Canonical-Duo idiom enforcement across every .duo file in the repo.
#
# Two kinds of rule:
#   ENFORCED — the repo is at zero and must stay there.
#   RATCHET  — debt that remains; the count may fall but never rise. Lower the
#              ceiling as you migrate. A ratchet that is beaten is reported so
#              the ceiling gets tightened rather than silently drifting.
#
# Counts ignore comment lines. Occurrences inside string literals and `[[ ]]`
# long brackets (inline C for @c.emit) are counted here but must be judged by
# eye — a corpus fixture may legitimately contain graveyarded syntax as data.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ROOTS=(lib examples scripts)
FAIL=0

# Non-comment lines matching a pattern.
# Duo code only: strips comments, `[[ ]]` long brackets and double-quoted
# strings before matching. Those regions are not Duo -- a `[[ ]]` block carries
# inline C for @c.emit (`__builtin_prefetch` is a C identifier, not a Duo name)
# and a lexer corpus fixture carries graveyarded syntax as *data*
# ("a == b ~= c"). Counting them made the gate measure the wrong thing.
duo_code() {
    find "${ROOTS[@]}" -name '*.duo' -print0 2>/dev/null \
        | xargs -0 awk '
            { line = $0 }
            in_long {
                if (line ~ /\]\]/) { sub(/.*\]\]/, "", line); in_long = 0 } else next
            }
            {
                sub(/--.*$/, "", line)
                while (match(line, /\[\[/)) {
                    pre = substr(line, 1, RSTART - 1)
                    rest = substr(line, RSTART + 2)
                    if (match(rest, /\]\]/)) {
                        line = pre substr(rest, RSTART + 2)
                    } else { line = pre; in_long = 1; break }
                }
                gsub(/"[^"]*"/, "", line)
                print line
            }'
}

count() {
    duo_code | sed -E "s/(${METAMETHODS:-__NOTHING__})//g" | grep -cE "$1" || true
}

enforce() {
    local name="$1" rx="$2" hint="$3"
    local n
    n=$(count "$rx")
    if [ "$n" -ne 0 ]; then
        echo "idiom FAIL [$name]: $n occurrence(s) — $hint"
        grep -rEn "$rx" --include='*.duo' "${ROOTS[@]}" 2>/dev/null | grep -vE ':[0-9]+:\s*--' | head -5 || true
        FAIL=1
    fi
}

ratchet() {
    local name="$1" rx="$2" ceiling="$3" hint="$4"
    local n
    n=$(count "$rx")
    if [ "$n" -gt "$ceiling" ]; then
        echo "idiom FAIL [$name]: $n > ceiling $ceiling — $hint"
        FAIL=1
    elif [ "$n" -lt "$ceiling" ]; then
        echo "idiom RATCHET [$name]: $n < ceiling $ceiling — lower the ceiling in $0"
    fi
}

# ── Enforced: migrated to zero, must not regress ──────────────────────────────
enforce lua-neq        '~=[^=]'                                  'use != (Lua ~= is graveyarded)'
enforce lua-local      '^\s*local\s+[A-Za-z_]'                   'bindings are already function-local; omit local'
enforce lua-require    '\brequire\('                             'use req "module.path"'
enforce named-fun      '^\s*fun\s+[A-Za-z_][A-Za-z_0-9]*\s*\('   'declare bare: name(params) ... end'
enforce lua-function   '^\s*function\s'                         'declare bare: name(params) ... end'
# `then` is optional everywhere the parser accepts a condition — including
# `elseif` and single-line `if cond <stmt> end`. An earlier reading called this
# parser-blocked; that was wrong. The failing probe used `f(x)` as a
# declaration, which parses as a *call*, and the resulting stray `end` was
# misread as evidence about `then`.
enforce retired-then   '\bthen\b'                                'if/elseif take a bare condition'
# Bare `M:hash(): i64` needed `scan_func_header_signal` to accept a `: Ret`
# return type as a header signal, the way it already accepted `-> Ret`. Until
# then these parsed as method *calls* and crashed sema on a func_decl/local_decl
# union mismatch, which read like a hard grammar limit and was not one.
enforce method-fun     '^\s*fun\s+[A-Za-z_][A-Za-z_0-9]*\s*[:.]' 'declare bare: M:method(params) ... end'

# ── Ratchet: remaining debt (none) ────────────────────────────────────────────
# `__`-prefixed names. Every graveyarded Duo name has left the namespace:
# `__emit` became `@c.emit`, and 37 compiler intrinsics moved to the `@comp.*`
# public spellings that src/meta_module.zig already mapped them to.
#
# The Lua metatable protocol is excluded below, not counted-and-tolerated.
# Duo is a Lua *superset*: `__index`, `__add`, `__eq`, `__call`, `__gc` and the
# rest are the interop surface itself, so renaming them would break the superset
# contract rather than make anything more canonical.
#
# What is left is genuinely un-mapped compiler internals (`__native_load_u8`,
# `__duo_kind`) — they need a `@comp.*` public name in src/meta_module.zig
# before the source can move, the same way the 37 above already had one.
METAMETHODS='__index|__newindex|__add|__sub|__mul|__div|__mod|__pow|__unm|__idiv|__band|__bor|__bxor|__bnot|__shl|__shr|__concat|__len|__eq|__lt|__le|__call|__tostring|__metatable|__gc|__iter|__contains|__pairs|__close|__name'
enforce dunder         "__[a-z]" 'use the @comp.* public spelling from src/meta_module.zig'
ratchet retired-match  '^\s*match\b'                                8 'use if/elseif'

# ── Tooling scripts must delegate to their Duo implementation ────────────────
for pair in run_benchmark_proof verify_build; do
    sh="scripts/${pair}.sh"
    duo="scripts/${pair}.duo"
    if [ -f "$sh" ] && [ -f "$duo" ] && ! grep -Eq "(duo run|run ).*${pair}\.duo" "$sh"; then
        echo "idiom FAIL [delegation]: $sh must delegate to scripts/${pair}.duo"
        FAIL=1
    fi
done

if [ "$FAIL" -eq 0 ]; then
    echo "duo_idiom_gate: PASS ($(find "${ROOTS[@]}" -name '*.duo' | wc -l | tr -d ' ') .duo files)"
else
    echo "duo_idiom_gate: FAIL"
    exit 1
fi
