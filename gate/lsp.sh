#!/bin/sh
# gate/lsp.sh — LSP hover-contract hold for the produced concept verdict (GAP-120).
#
# `tools/concept/hover.sh` is the LSP face of the produced concept finding:
# one JSON-RPC `textDocument/hover` request object on stdin, one response
# object on stdout, the verdict read from the produced graph through `idol
# explain` and `tools/concept/doc.sh` and wrapped as LSP `MarkupContent`.
# This gate holds that face. It owns no derivation: verdict-correctness
# (REFUSED exactly when the export carries the refusal, HELD otherwise) is
# owned by `gate/concept.sh` over the export and by the docs slice over the
# render; what is measured HERE, and nowhere else, is the LSP boundary —
# framing, id round-trip, file-uri passing, position-independence, and
# fail-closed errors.
#
# THE ROSTER CARRIES EVERY PRODUCED DIRECTION, so a one-sided gate cannot
# call itself an enforcement:
#   bucket refused: the produced refusal for the no-shared-demand cohort
#     must reach the caller as hover text. THE NEGATIVE DIRECTION: a
#     projection that stops refusing is convicted. The subject uri carries
#     a %20 SPACE in its name: a projection that interpolates the path
#     through a host shell splits it and fails, and one that never decodes
#     the uri misses the file — so the spaced uri is the positive control
#     for argv passing (host-transport norm).
#   cohort held: one subject drives both relations, so no refusal may be
#     produced and the hover must read HELD. THE POSITIVE DIRECTION: a
#     projection that refuses a lawful cohort is convicted.
#   unwitnessed held: nothing applies the module's one relation, so no
#     refusal may be produced and the hover must read HELD. THE THIRD
#     DIRECTION: a projection that refuses a lawful single is convicted.
#     Its produced evidence differs from the cohort's (shared_demand 0,
#     zero refusals, one applied relation), so this row holds the HELD
#     render across the boundary from different facts.
#   position-independence: the verdict is a file-home fact, so a second
#     position in the same file must answer the same hover text. A
#     projection that derives per-line verdicts is convicted.
# Fail-closed controls: an unknown method or a non-hover method answers
# -32601; a missing, non-string, or non-file uri answers -32602; a
# misshapen position answers -32602; an unreadable subject answers an error
# carrying the refusal to render (never a hover-shaped result); an
# unparseable request, or two objects on one line, answers -32700. A row
# whose measured answer differs from its demanded answer FAILS. Zero rows
# examined FAILS (GAP-201).
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/.." && pwd)
cd "$root" || { printf 'lsp: cannot enter root\n' >&2; exit 3; }

IDOL=${IDOL:-"$root/zig-out/bin/idol"}
hover=$here/../tools/concept/hover.sh
self=$here/$(basename -- "$0")

if [ ! -x "$IDOL" ]; then
    printf 'lsp: NOT MEASURED — %s is not a compiler (a checked graph was required)\n' "$IDOL" >&2
    exit 3
fi
if [ ! -x "$hover" ]; then
    printf 'lsp: NOT MEASURED — %s is not executable (the hover projection was required)\n' "$hover" >&2
    exit 3
fi

command -v jq >/dev/null 2>&1 || {
    printf 'lsp: NOT MEASURED — jq is required to frame the hover contract\n' >&2
    exit 3
}
command -v python3 >/dev/null 2>&1 || {
    printf 'lsp: NOT MEASURED — python3 is required to encode the file uris\n' >&2
    exit 3
}

work=$(mktemp -d "${TMPDIR:-/tmp}/idol.lsp.XXXXXX") || exit 3
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
# positive controls that the verdict crossed the LSP boundary intact.
printf 'plus(a: i64, b: i64): i64\n  a + b\nminus(a: i64, b: i64): i64\n  a - b\nmain(): i64\n  x = plus(2, 3)\n  x + 1\nentry(): i64\n  minus(7, 4)\n' >"$work/my bucket.id" || exit 3
printf 'plus(a: i64, b: i64): i64\n  a + b\nminus(a: i64, b: i64): i64\n  a - b\nmain(): i64\n  x = plus(2, 3)\n  y = plus(1, 1)\n  minus(y, 4)\n' >"$work/cohort.id" || exit 3
printf 'plus(a: i64, b: i64): i64\n  a + b\nmain(): i64\n  x = plus(2, 3)\n  x + 1\n' >"$work/unwitnessed.id" || exit 3

bucket_uri="file://$work/my%20bucket.id"
cohort_uri="file://$work/cohort.id"
unwitnessed_uri="file://$work/unwitnessed.id"

examined=0
failed=0

# call <id-json> <request-json> <response-file>: one request in, one line out.
call() {
    printf '%s\n' "$2" | sh "$hover" >"$3" 2>"$3.diag" || {
        printf 'lsp: FAIL — hover exited nonzero on id %s\n' "$1" >&2
        failed=$((failed + 1))
        return 1
    }
    examined=$((examined + 1))
}

# demand_hover <id-json> <uri> <line> <character> <needle>: a verdict must cross as hover text.
demand_hover() {
    resp=$work/respHover.json
    req=$(jq -n -c --arg u "$2" --argjson id "$1" --argjson line "$3" --argjson char "$4" \
        '{jsonrpc:"2.0",id:$id,method:"textDocument/hover",params:{textDocument:{uri:$u},position:{line:$line,character:$char}}}') || {
        printf 'lsp: FAIL — request could not be framed for id %s\n' "$1" >&2
        failed=$((failed + 1))
        return 1
    }
    call "$1" "$req" "$resp" || return 1
    [ "$(wc -l <"$resp" | tr -d ' ')" = "1" ] || {
        printf 'lsp: FAIL — id %s answered %s lines, one line was demanded\n' "$1" "$(wc -l <"$resp")" >&2
        failed=$((failed + 1))
        return 1
    }
    jq -e --argjson id "$1" '.id == $id and (has("error") | not)' <"$resp" >/dev/null 2>&1 || {
        printf 'lsp: FAIL — id %s lost its id or carried an error where a verdict was demanded\n' "$1" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
        return 1
    }
    jq -e '.result.contents.kind == "markdown"' <"$resp" >/dev/null 2>&1 || {
        printf 'lsp: FAIL — id %s hover is not markdown content\n' "$1" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
        return 1
    }
    jq -r '.result.contents.value // ""' <"$resp" 2>/dev/null | grep -Fq "$5" || {
        printf 'lsp: FAIL — id %s hover text misses %s\n' "$1" "$5" >&2
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
        printf 'lsp: FAIL — %s refused with the wrong shape (demanded error %s)\n' "$1" "$3" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
        return 1
    }
    jq -e '(has("result") | not)' <"$resp" >/dev/null 2>&1 || {
        printf 'lsp: FAIL — %s carried a result beside its error; a refusal is never hover-shaped\n' "$1" >&2
        failed=$((failed + 1))
        return 1
    }
}

# ── every produced direction ─────────────────────────────────────────────
demand_hover 1 "$bucket_uri" 0 0 "verdict: REFUSED no_shared_demand"
demand_hover 2 "$cohort_uri" 0 0 "verdict: HELD one concept"
demand_hover 3 "$unwitnessed_uri" 0 0 "verdict: HELD one concept"

# The verdict is a file-home fact: a second position answers the same hover.
demand_hover 4 "$cohort_uri" 5 3 "verdict: HELD one concept"

# The id is opaque: member order and string ids round-trip untouched.
req=$(jq -n -c --arg u "$cohort_uri" \
    '{method:"textDocument/hover",params:{textDocument:{uri:$u},position:{line:0,character:0}},jsonrpc:"2.0",id:5}') || exit 3
resp=$work/respOrder.json
call 5 "$req" "$resp" || true
jq -e '.id == 5 and .result.contents.value != ""' <"$resp" >/dev/null 2>&1 || {
    printf 'lsp: FAIL — id-last member order did not round-trip\n' >&2
    failed=$((failed + 1))
}
demand_hover '"hover"' "$cohort_uri" 0 0 "verdict: HELD one concept"

# ── fail-closed ──────────────────────────────────────────────────────────
req=$(jq -n -c --arg u "$cohort_uri" \
    '{jsonrpc:"2.0",id:7,method:"textDocument/definition",params:{textDocument:{uri:$u},position:{line:0,character:0}}}') || exit 3
demand_error unknown-method "$req" -32601

req=$(jq -n -c \
    '{jsonrpc:"2.0",id:8,method:"workspace/symbol",params:{query:"concept"}}') || exit 3
demand_error wrong-method "$req" -32601

req=$(jq -n -c \
    '{jsonrpc:"2.0",id:9,method:"textDocument/hover",params:{position:{line:0,character:0}}}') || exit 3
demand_error missing-uri "$req" -32602

req=$(jq -n -c \
    '{jsonrpc:"2.0",id:10,method:"textDocument/hover",params:{textDocument:{uri:7},position:{line:0,character:0}}}') || exit 3
demand_error nonstring-uri "$req" -32602

req=$(jq -n -c \
    '{jsonrpc:"2.0",id:11,method:"textDocument/hover",params:{textDocument:{uri:"untitled:Tab-1"},position:{line:0,character:0}}}') || exit 3
demand_error non-file-scheme "$req" -32602

req=$(jq -n -c --arg u "$cohort_uri" \
    '{jsonrpc:"2.0",id:12,method:"textDocument/hover",params:{textDocument:{uri:$u},position:"top"}}') || exit 3
demand_error bad-position "$req" -32602

req=$(jq -n -c --arg u "file://$work/absent.id" \
    '{jsonrpc:"2.0",id:13,method:"textDocument/hover",params:{textDocument:{uri:$u},position:{line:0,character:0}}}') || exit 3
demand_error unreadable-subject "$req" -32000

demand_error malformed '{oops' -32700
demand_error adjacent '{"jsonrpc":"2.0","id":15,"method":"ping","params":{}} {"jsonrpc":"2.0","id":16,"method":"ping","params":{}}' -32700

# ── notification-zero ────────────────────────────────────────────────────
# NOTIFICATION-ZERO: an object WITHOUT an id member is a notification, and
# the server must never reply to one — no result, no error, even for a bad
# method or uri. Zero reply bytes, exit 0; the face consumes the line and
# moves on. A present `id: null` still answers. The rows below are the
# contract a served arm would otherwise never have held before landing.
# demand_silence <label> <request-json>: consumes the line, answers zero bytes.
demand_silence() {
    resp=$work/respSilent.json
    printf '%s\n' "$2" | sh "$hover" >"$resp" 2>"$resp.diag" || {
        printf 'lsp: FAIL — %s exited nonzero on a notification\n' "$1" >&2
        failed=$((failed + 1))
        return 1
    }
    examined=$((examined + 1))
    [ ! -s "$resp" ] || {
        printf 'lsp: FAIL — %s replied to a notification (%s bytes); silence is demanded\n' "$1" "$(wc -c <"$resp" | tr -d ' ')" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
        return 1
    }
}

req=$(jq -n -c --arg u "$cohort_uri" \
    '{jsonrpc:"2.0",method:"textDocument/hover",params:{textDocument:{uri:$u},position:{line:0,character:0}}}') || exit 3
demand_silence notification-silent "$req"

req=$(jq -n -c \
    '{jsonrpc:"2.0",method:"textDocument/definition",params:{textDocument:{uri:"file:///x.id"},position:{line:0,character:0}}}') || exit 3
demand_silence notification-bad-method "$req"

req=$(jq -n -c --arg u "$cohort_uri" \
    '{jsonrpc:"2.0",id:null,method:"textDocument/hover",params:{textDocument:{uri:$u},position:{line:0,character:0}}}') || exit 3
demand_hover null "$cohort_uri" 0 0 "verdict: HELD one concept"
[ "$examined" -gt 0 ] || {
    printf 'lsp: FAIL — 0 hover contracts examined\n' >&2
    exit 1
}
if [ "$failed" -ne 0 ]; then
    printf 'lsp: FAIL — %s of %s examined contract(s) failed\n' "$failed" "$examined" >&2
    exit 1
fi
printf 'lsp: PASS — %s examined contract(s), 0 failed\n' "$examined"
exit 0
