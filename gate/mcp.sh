#!/bin/sh
# gate/mcp.sh — MCP tool-contract hold for the produced concept verdict (GAP-120).
#
# `tools/concept/tool.sh` is the MCP face of the produced concept finding:
# one JSON-RPC `tools/call` request object on stdin, one response object on
# stdout, the verdict read from the produced graph through `idol explain`
# and `tools/concept/doc.sh`. This gate holds that face. It owns no
# derivation: verdict-correctness (REFUSED exactly when the export carries
# the refusal, HELD otherwise) is owned by `gate/concept.sh` over the export
# and by the docs slice over the render; what is measured HERE, and nowhere
# else, is the MCP boundary — framing, id round-trip, argv file passing, and
# fail-closed errors.
#
# THE ROSTER CARRIES EVERY PRODUCED DIRECTION, so a one-sided gate cannot
# call itself an enforcement:
#   bucket refused: the produced refusal for the no-shared-demand cohort
#     must reach the caller as a text result. THE NEGATIVE DIRECTION: a
#     projection that stops refusing is convicted. The subject file carries
#     a SPACE in its name: a projection that interpolates the path through
#     a host shell splits it and fails, so the spaced path is the positive
#     control for argv passing (host-transport norm).
#   cohort held: one subject drives both relations, so no refusal may be
#     produced and the result must read HELD. THE POSITIVE DIRECTION: a
#     projection that refuses a lawful cohort is convicted.
#   unwitnessed held: nothing applies the module's one relation, so no
#     refusal may be produced and the result must read HELD. THE THIRD
#     DIRECTION: a projection that refuses a lawful single is convicted.
#     Its produced evidence differs from the cohort's (shared_demand 0,
#     zero refusals, one applied relation), so this row holds the HELD
#     render across the boundary from different facts.
# Fail-closed controls: unknown tool or method answers -32601; a missing or
# non-string file answers -32602; an unreadable subject answers an error
# carrying the refusal to render (never a verdict-shaped result); an
# unparseable request, or two objects on one line, answers -32700. A row
# whose measured answer differs from its demanded answer FAILS. Zero rows
# examined FAILS (GAP-201).
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/.." && pwd)
cd "$root" || { printf 'mcp: cannot enter root\n' >&2; exit 3; }

IDOL=${IDOL:-"$root/zig-out/bin/idol"}
tool=$here/../tools/concept/tool.sh
self=$here/$(basename -- "$0")

if [ ! -x "$IDOL" ]; then
    printf 'mcp: NOT MEASURED — %s is not a compiler (a checked graph was required)\n' "$IDOL" >&2
    exit 3
fi
if [ ! -x "$tool" ]; then
    printf 'mcp: NOT MEASURED — %s is not executable (the tool projection was required)\n' "$tool" >&2
    exit 3
fi

command -v jq >/dev/null 2>&1 || {
    printf 'mcp: NOT MEASURED — jq is required to frame the tool contract\n' >&2
    exit 3
}

work=$(mktemp -d "${TMPDIR:-/tmp}/idol.mcp.XXXXXX") || exit 3
TMPDIR=$work/scratch
export TMPDIR
mkdir -p "$TMPDIR" || exit 3
cleanup() { rm -rf -- "$work"; }
trap 'cleanup' EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup; exit 129' HUP

# ── the subjects ─────────────────────────────────────────────────────────
# Same three shapes `gate/concept.sh` materializes (bucket: no subject drives
# both relations — refused; cohort: one subject drives both — held;
# unwitnessed: nothing applies the one relation — held). The
# verdict-correctness of those shapes is owned there; here they are the
# positive controls that the verdict crossed the MCP boundary intact.
printf 'plus(a: i64, b: i64): i64\n  a + b\nminus(a: i64, b: i64): i64\n  a - b\nmain(): i64\n  x = plus(2, 3)\n  x + 1\nentry(): i64\n  minus(7, 4)\n' >"$work/my bucket.id" || exit 3
printf 'plus(a: i64, b: i64): i64\n  a + b\nminus(a: i64, b: i64): i64\n  a - b\nmain(): i64\n  x = plus(2, 3)\n  y = plus(1, 1)\n  minus(y, 4)\n' >"$work/cohort.id" || exit 3
printf 'plus(a: i64, b: i64): i64\n  a + b\nmain(): i64\n  x = plus(2, 3)\n  x + 1\n' >"$work/unwitnessed.id" || exit 3

examined=0
failed=0

# call <id-json> <request-json> <response-file>: one request in, one line out.
call() {
    printf '%s\n' "$2" | sh "$tool" >"$3" 2>"$3.diag" || {
        printf 'mcp: FAIL — tool exited nonzero on id %s\n' "$1" >&2
        failed=$((failed + 1))
        return 1
    }
    examined=$((examined + 1))
}

# demand_text <id-json> <file> <needle>: a verdict must cross as text.
demand_text() {
    resp=$work/respText.json
    req=$(jq -n -c --arg f "$2" --argjson id "$1" \
        '{jsonrpc:"2.0",id:$id,method:"tools/call",params:{name:"concept",arguments:{file:$f}}}') || {
        printf 'mcp: FAIL — request could not be framed for id %s\n' "$1" >&2
        failed=$((failed + 1))
        return 1
    }
    call "$1" "$req" "$resp" || return 1
    [ "$(wc -l <"$resp" | tr -d ' ')" = "1" ] || {
        printf 'mcp: FAIL — id %s answered %s lines, one line was demanded\n' "$1" "$(wc -l <"$resp")" >&2
        failed=$((failed + 1))
        return 1
    }
    jq -e --argjson id "$1" '.id == $id and (has("error") | not)' <"$resp" >/dev/null 2>&1 || {
        printf 'mcp: FAIL — id %s lost its id or carried an error where a verdict was demanded\n' "$1" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
        return 1
    }
    jq -r '.result.content[0].text // ""' <"$resp" 2>/dev/null | grep -Fq "$3" || {
        printf 'mcp: FAIL — id %s verdict text misses %s\n' "$1" "$3" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
        return 1
    }
}

# demand_error <label> <request-json> <code>: a failure must refuse with code.
demand_error() {
    resp=$work/respErr.json
    call "$1" "$2" "$resp" || return 1
    jq -e --argjson code "$3" 'has("error") and .error.code == $code and (.error.message | type == "string")' \
        <"$resp" >/dev/null 2>&1 || {
        printf 'mcp: FAIL — %s refused with the wrong shape (demanded error %s)\n' "$1" "$3" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
        return 1
    }
    jq -e '(has("result") | not)' <"$resp" >/dev/null 2>&1 || {
        printf 'mcp: FAIL — %s carried a result beside its error; a refusal is never verdict-shaped\n' "$1" >&2
        failed=$((failed + 1))
        return 1
    }
}

# ── every produced direction ─────────────────────────────────────────────
demand_text 1 "$work/my bucket.id" "verdict: REFUSED no_shared_demand"
demand_text 2 "$work/cohort.id" "verdict: HELD one concept"
demand_text 3 "$work/unwitnessed.id" "verdict: HELD one concept"

# The id is opaque: member order and string ids round-trip untouched.
req=$(jq -n -c --arg f "$work/cohort.id" \
    '{method:"tools/call",params:{name:"concept",arguments:{file:$f}},jsonrpc:"2.0",id:4}') || exit 3
resp=$work/respOrder.json
call 4 "$req" "$resp" || true
jq -e '.id == 4 and .result.content[0].text != ""' <"$resp" >/dev/null 2>&1 || {
    printf 'mcp: FAIL — id-last member order did not round-trip\n' >&2
    failed=$((failed + 1))
}
demand_text '"held"' "$work/cohort.id" "verdict: HELD one concept"

# ── fail-closed ──────────────────────────────────────────────────────────
req=$(jq -n -c --arg f "$work/cohort.id" \
    '{jsonrpc:"2.0",id:5,method:"tools/call",params:{name:"status",arguments:{file:$f}}}') || exit 3
demand_error unknown-tool "$req" -32601

req=$(jq -n -c \
    '{jsonrpc:"2.0",id:6,method:"tools/list",params:{}}') || exit 3
demand_error wrong-method "$req" -32601

req=$(jq -n -c '{jsonrpc:"2.0",id:7,method:"tools/call",params:{name:"concept",arguments:{}}}') || exit 3
demand_error missing-file "$req" -32602

req=$(jq -n -c '{jsonrpc:"2.0",id:8,method:"tools/call",params:{name:"concept",arguments:{file:7}}}') || exit 3
demand_error nonstring-file "$req" -32602

req=$(jq -n -c --arg f "$work/absent.id" \
    '{jsonrpc:"2.0",id:9,method:"tools/call",params:{name:"concept",arguments:{file:$f}}}') || exit 3
demand_error unreadable-subject "$req" -32000

demand_error malformed '{oops' -32700
demand_error adjacent '{"jsonrpc":"2.0","id":11,"method":"ping","params":{}} {"jsonrpc":"2.0","id":12,"method":"ping","params":{}}' -32700

[ "$examined" -gt 0 ] || {
    printf 'mcp: FAIL — 0 tool contracts examined\n' >&2
    exit 1
}
if [ "$failed" -ne 0 ]; then
    printf 'mcp: FAIL — %s of %s examined contract(s) failed\n' "$failed" "$examined" >&2
    exit 1
fi
printf 'mcp: PASS — %s examined contract(s), 0 failed\n' "$examined"
exit 0
