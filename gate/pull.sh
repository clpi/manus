#!/bin/sh
# gate/pull.sh — LSP pull-diagnostic hold for the produced concept verdict (GAP-120).
#
# `tools/concept/diag.sh` is the pull-diagnostic face of the produced concept
# finding: one JSON-RPC `textDocument/diagnostic` request object on stdin, one
# `DocumentDiagnosticReport` on stdout, the verdict read from the produced
# graph through `idol explain` and `tools/concept/doc.sh`. No other gate
# crosses this face — the hover contract (`gate/lsp.sh`) is a hover, a
# position-bound `MarkupContent`; the enforcement (`gate/refuse.sh`) is an
# exit code over a build; neither answers a client's pull for the document's
# diagnostics. This gate closes that hole. It owns no derivation:
# verdict-correctness (REFUSED exactly when the export carries the refusal,
# HELD otherwise) is owned by `gate/concept.sh` over the export and by the
# docs slice over the render; framing, ids, and fail-closed JSON-RPC errors
# are owned by `gate/lsp.sh` for hover. What is measured HERE, and nowhere
# else, is the pull boundary — the report kind, the items shape, the
# severity mapping, the whole-file range, the HELD empty-items
# (OBSERVATION-MINIMUM) face, file-uri passing, framing, id round-trip, and
# fail-closed refusal.
#
# THE ROSTER CARRIES EVERY PRODUCED DIRECTION, so a one-sided gate cannot
# call itself an enforcement:
#   bucket refused: the produced refusal for the no-shared-demand cohort must
#     reach the caller as ONE diagnostic with severity 1 (Error), a
#     whole-file range, the produced reason `no_shared_demand`, and the
#     produced identity evidence in the message. THE NEGATIVE DIRECTION: a
#     projection that stops refusing is convicted. The subject uri carries a
#     %20 SPACE in its name: a projection that interpolates the path through a
#     host shell splits it and fails, and one that never decodes the uri
#     misses the file — so the spaced uri is the positive control for argv
#     passing and uri decoding (host-transport norm).
#   cohort held: one subject drives both relations, so no refusal is produced
#     and the report must answer `"kind":"full","items":[]` — a clean bill,
#     never a fabricated informational row (OBSERVATION-MINIMUM: a HELD file
#     has no diagnostic to observe). THE POSITIVE DIRECTION: a projection
#     that diagnoses a lawful cohort is convicted.
#   unwitnessed held: nothing applies the module's one relation, so no
#     refusal is produced and the report must answer empty items. THE THIRD
#     DIRECTION: a projection that diagnoses a lawful single is convicted.
#     Its produced evidence differs from the cohort's (shared_demand 0, zero
#     refusals, one applied relation), so this row holds the HELD report
#     across the boundary from different facts, distinguished by the
#     reference render's own identity line — the two HELD rows are never
#     merged.
#   position-independence: the verdict is a file-home fact, so the report
#     carries exactly one diagnostic for a refused file and its range covers
#     the whole document — a projection that derives per-line or per-binding
#     diagnostics is convicted.
# Fail-closed controls: an unknown or non-diagnostic method answers -32601; a
# missing, non-string, or non-file uri answers -32602; an unreadable subject
# answers an error carrying the refusal to render (never a report-shaped
# result); an unparseable request, or two objects on one line, answers
# -32700. A row whose measured answer differs from its demanded answer
# FAILS. Zero rows examined FAILS (GAP-201). A missing compiler or jq
# refuses NOT MEASURED (exit 3) — a clean refusal the vacuity scaffold counts
# as noticing the missing subject, never a pass.
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/.." && pwd)
cd "$root" || { printf 'pull: cannot enter root\n' >&2; exit 3; }

IDOL=${IDOL:-"$root/zig-out/bin/idol"}
diag=$here/../tools/concept/diag.sh

if [ ! -x "$IDOL" ]; then
    printf 'pull: NOT MEASURED — %s is not a compiler (a checked graph was required)\n' "$IDOL" >&2
    exit 3
fi
if [ ! -x "$diag" ]; then
    printf 'pull: NOT MEASURED — %s is not executable (the pull projection was required)\n' "$diag" >&2
    exit 3
fi

command -v jq >/dev/null 2>&1 || {
    printf 'pull: NOT MEASURED — jq is required to frame the pull contract\n' >&2
    exit 3
}
command -v python3 >/dev/null 2>&1 || {
    printf 'pull: NOT MEASURED — python3 is required to encode the file uris\n' >&2
    exit 3
}

work=$(mktemp -d "${TMPDIR:-/tmp}/idol.pull.XXXXXX") || exit 3
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
# positive controls that the verdict crossed the pull boundary intact.
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
    printf '%s\n' "$2" | sh "$diag" >"$3" 2>"$3.diag" || {
        printf 'pull: FAIL — diag exited nonzero on id %s\n' "$1" >&2
        failed=$((failed + 1))
        return 1
    }
    examined=$((examined + 1))
}

# demand_error <label> <request-json> <code>: a failure must refuse with code.
demand_error() {
    resp=$work/respErr.json
    call "$1" "$2" "$resp" || return 1
    jq -e --argjson code "$3" 'has("error") and .error.code == $code and (.error.message | type == "string")' \
        <"$resp" >/dev/null 2>&1 || {
        printf 'pull: FAIL — %s refused with the wrong shape (demanded error %s)\n' "$1" "$3" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
        return 1
    }
    jq -e '(has("result") | not)' <"$resp" >/dev/null 2>&1 || {
        printf 'pull: FAIL — %s carried a result beside its error; a refusal is never report-shaped\n' "$1" >&2
        failed=$((failed + 1))
        return 1
    }
}

# demand_refused <id-json> <file> <uri> <reason>: a produced refusal must
# reach the caller as exactly one severity-1 whole-file diagnostic carrying
# the produced reason AND the produced identity evidence, nothing else.
demand_refused() {
    resp=$work/respRef.json
    req=$(jq -n -c --arg u "$3" --argjson id "$1" \
        '{jsonrpc:"2.0",id:$id,method:"textDocument/diagnostic",params:{textDocument:{uri:$u}}}') || {
        printf 'pull: FAIL — request could not be framed for id %s\n' "$1" >&2
        failed=$((failed + 1))
        return 1
    }
    call "$1" "$req" "$resp" || return 1
    [ "$(wc -l <"$resp" | tr -d ' ')" = "1" ] || {
        printf 'pull: FAIL — id %s answered %s lines, one line was demanded\n' "$1" "$(wc -l <"$resp")" >&2
        failed=$((failed + 1))
        return 1
    }
    jq -e --argjson id "$1" '.id == $id and (has("error") | not)' <"$resp" >/dev/null 2>&1 || {
        printf 'pull: FAIL — id %s lost its id or carried an error where a report was demanded\n' "$1" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
        return 1
    }
    jq -e '.result.kind == "full"' <"$resp" >/dev/null 2>&1 || {
        printf 'pull: FAIL — id %s report is not kind full\n' "$1" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
        return 1
    }
    # Exactly one diagnostic: the concept verdict is a file-home fact, so a
    # refused file carries ONE row, never a row per binding.
    [ "$(jq '.result.items | length' <"$resp" 2>/dev/null)" = "1" ] || {
        printf 'pull: FAIL — id %s carried %s diagnostics, exactly one file-home row was demanded\n' "$1" "$(jq '.result.items | length' <"$resp" 2>/dev/null)" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
        return 1
    }
    jq -e '.result.items[0].severity == 1' <"$resp" >/dev/null 2>&1 || {
        printf 'pull: FAIL — id %s diagnostic is not severity 1 (Error)\n' "$1" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
        return 1
    }
    # Whole-file range: start at 0:0, end at the file's line count character 0.
    lines=$(wc -l <"$2" 2>/dev/null | tr -d ' ')
    jq -e --argjson lines "$lines" \
        '.result.items[0].range.start.line == 0 and .result.items[0].range.start.character == 0 and
         .result.items[0].range.end.line == $lines and .result.items[0].range.end.character == 0' \
        <"$resp" >/dev/null 2>&1 || {
        printf 'pull: FAIL — id %s diagnostic range does not cover the whole file (end demanded at line %s)\n' "$1" "$lines" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
        return 1
    }
    jq -r '.result.items[0].message // ""' <"$resp" 2>/dev/null | grep -Fq "$4" || {
        printf 'pull: FAIL — id %s message misses the produced reason %s\n' "$1" "$4" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
        return 1
    }
    # The message must carry the produced identity evidence — a message that
    # names the reason but invents the counts agrees with nothing.
    heref=$work/refRender.txt
    if ! $here/../tools/concept/doc.sh "$2" >"$heref" 2>/dev/null; then
        printf 'pull: FAIL — id %s reference render could not be produced\n' "$1" >&2
        failed=$((failed + 1))
        return 1
    fi
    ident=$(awk '/^identity: /{sub(/^identity: /, ""); print; exit}' "$heref") || ident=""
    [ -n "$ident" ] || {
        printf 'pull: FAIL — id %s reference render carries no identity line for evidence comparison\n' "$1" >&2
        failed=$((failed + 1))
        return 1
    }
    jq -r '.result.items[0].message // ""' <"$resp" 2>/dev/null | grep -Fq "$ident" || {
        printf 'pull: FAIL — id %s message misses the produced identity evidence %s\n' "$1" "$ident" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
        return 1
    }
}

# demand_held <id-json> <file> <uri>: a produced HELD verdict must answer
# an empty items array — a clean bill, never a fabricated row.
demand_held() {
    resp=$work/respHeld.json
    req=$(jq -n -c --arg u "$3" --argjson id "$1" \
        '{jsonrpc:"2.0",id:$id,method:"textDocument/diagnostic",params:{textDocument:{uri:$u}}}') || {
        printf 'pull: FAIL — request could not be framed for id %s\n' "$1" >&2
        failed=$((failed + 1))
        return 1
    }
    call "$1" "$req" "$resp" || return 1
    jq -e --argjson id "$1" '.id == $id and (has("error") | not)' <"$resp" >/dev/null 2>&1 || {
        printf 'pull: FAIL — id %s lost its id or carried an error where a report was demanded\n' "$1" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
        return 1
    }
    jq -e '.result.kind == "full"' <"$resp" >/dev/null 2>&1 || {
        printf 'pull: FAIL — id %s report is not kind full\n' "$1" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
        return 1
    }
    [ "$(jq '.result.items | length' <"$resp" 2>/dev/null)" = "0" ] || {
        printf 'pull: FAIL — id %s carried %s diagnostics; a HELD file answers an empty items array, never a fabricated row\n' "$1" "$(jq '.result.items | length' <"$resp" 2>/dev/null)" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
        return 1
    }
    # The HELD report is distinguished by its produced evidence so the two
    # HELD rows are never merged: the reference render over this file must
    # carry the demanded demand evidence.
    ref=$($here/../tools/concept/doc.sh "$2" 2>/dev/null) || ref=""
    [ -n "$ref" ] || {
        printf 'pull: FAIL — id %s reference render could not be produced\n' "$1" >&2
        failed=$((failed + 1))
        return 1
    }
    printf '%s\n' "$ref" | grep -Fq "$4" || {
        printf 'pull: FAIL — id %s reference render misses the produced evidence %s; the HELD directions would merge\n' "$1" "$4" >&2
        failed=$((failed + 1))
        return 1
    }
}

# ── every produced direction ─────────────────────────────────────────────
demand_refused 1 "$work/my bucket.id" "$bucket_uri" "no_shared_demand"
demand_held    2 "$work/cohort.id" "$cohort_uri" "shared_demand=1"
demand_held    3 "$work/unwitnessed.id" "$unwitnessed_uri" "relations=2 shapes=0 applications=1 shared_demand=0"

# The id is opaque: member order and string ids round-trip untouched.
req=$(jq -n -c --arg u "$cohort_uri" \
    '{method:"textDocument/diagnostic",params:{textDocument:{uri:$u}},jsonrpc:"2.0",id:4}') || exit 3
resp=$work/respOrder.json
call 4 "$req" "$resp" || true
jq -e '.id == 4 and .result.kind == "full"' <"$resp" >/dev/null 2>&1 || {
    printf 'pull: FAIL — id-last member order did not round-trip\n' >&2
    failed=$((failed + 1))
}
req=$(jq -n -c --arg u "$cohort_uri" \
    '{jsonrpc:"2.0",id:"pull",method:"textDocument/diagnostic",params:{textDocument:{uri:$u}}}') || exit 3
resp=$work/respString.json
call '"pull"' "$req" "$resp" || true
jq -e '.id == "pull" and .result.items == []' <"$resp" >/dev/null 2>&1 || {
    printf 'pull: FAIL — string id did not round-trip\n' >&2
    cat "$resp" >&2
    failed=$((failed + 1))
}

# ── fail-closed ──────────────────────────────────────────────────────────
req=$(jq -n -c --arg u "$cohort_uri" \
    '{jsonrpc:"2.0",id:7,method:"textDocument/hover",params:{textDocument:{uri:$u},position:{line:0,character:0}}}') || exit 3
demand_error unknown-method "$req" -32601

req=$(jq -n -c \
    '{jsonrpc:"2.0",id:8,method:"workspace/symbol",params:{query:"concept"}}') || exit 3
demand_error wrong-method "$req" -32601

req=$(jq -n -c \
    '{jsonrpc:"2.0",id:9,method:"textDocument/diagnostic",params:{}}') || exit 3
demand_error missing-uri "$req" -32602

req=$(jq -n -c \
    '{jsonrpc:"2.0",id:10,method:"textDocument/diagnostic",params:{textDocument:{uri:7}}}') || exit 3
demand_error nonstring-uri "$req" -32602

req=$(jq -n -c \
    '{jsonrpc:"2.0",id:11,method:"textDocument/diagnostic",params:{textDocument:{uri:"untitled:Tab-1"}}}') || exit 3
demand_error non-file-scheme "$req" -32602

req=$(jq -n -c --arg u "file://$work/absent.id" \
    '{jsonrpc:"2.0",id:12,method:"textDocument/diagnostic",params:{textDocument:{uri:$u}}}') || exit 3
demand_error unreadable-subject "$req" -32000

demand_error malformed '{oops' -32700
demand_error adjacent '{"jsonrpc":"2.0","id":15,"method":"ping","params":{}} {"jsonrpc":"2.0","id":16,"method":"ping","params":{}}' -32700

[ "$examined" -gt 0 ] || {
    printf 'pull: FAIL — 0 pull contracts examined\n' >&2
    exit 1
}
if [ "$failed" -ne 0 ]; then
    printf 'pull: FAIL — %s of %s examined contract(s) failed\n' "$failed" "$examined" >&2
    exit 1
fi
printf 'pull: PASS — %s examined contract(s), 0 failed\n' "$examined"
exit 0
