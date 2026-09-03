#!/bin/sh
# gate/converge.sh — cross-face agreement hold for the produced concept verdict (GAP-120).
#
# The produced concept finding leaves the graph through three faces that each
# already has its own gate: the generated-docs render (`tools/concept/doc.sh`,
# held by `gate/docs.sh`), the MCP tool text (`tools/concept/tool.sh`, held by
# `gate/mcp.sh`), and the LSP hover value (`tools/concept/hover.sh`, held by
# `gate/lsp.sh`). Every one of those gates holds its face against NEEDLES — a
# face that carries the demanded verdict line plus one invented paragraph still
# passes all three, while no two faces agree with each other. This gate closes
# that hole: for one subject it renders all three faces and demands the MCP
# text and the LSP hover value be BYTE-IDENTICAL to the docs render.
#
# It owns no derivation: verdict-correctness (REFUSED exactly when the export
# carries the refusal, HELD otherwise) is owned by `gate/concept.sh` over the
# export; the record shape and the opposite-verdict absence are owned by
# `gate/docs.sh`; framing, ids, and fail-closed errors are owned by
# `gate/mcp.sh` and `gate/lsp.sh`. What is measured HERE, and nowhere else, is
# the agreement — one produced verdict reaching three readers as one text.
#
# THE ROSTER CARRIES EVERY PRODUCED DIRECTION, so a one-sided agreement cannot
# call itself an enforcement:
#   bucket refused: the no-shared-demand cohort must reach all three faces as
#     `verdict: REFUSED no_shared_demand` with `shared_demand=0`. The subject
#     file carries a SPACE in its name: a face that interpolates the path
#     through a host shell splits it, a face that never decodes the uri misses
#     the file, and either breaks the agreement — so the spaced path is the
#     positive control for argv passing across all three faces at once.
#   cohort held: one subject drives both relations, so all three faces must
#     read `verdict: HELD one concept` with `shared_demand=1`.
#   unwitnessed held: nothing applies the module's one relation, so all three
#     faces must read `verdict: HELD one concept` over the exact identity
#     `relations=2 shapes=0 applications=1 shared_demand=0` — different
#     produced evidence from the cohort's, so the two HELD agreements are
#     never merged.
# The demanded needles keep the agreement non-empty (three empty faces agree
# and carry nothing); absence and correctness stay owned where they are. A row
# whose faces disagree, or whose docs face misses a needle, FAILS. Zero rows
# examined FAILS (GAP-201).
#
# CONFORMANCE SEAM. `CONVERGE_DOC`, `CONVERGE_TOOL`, and `CONVERGE_HOVER` point
# this gate at the faces it holds (default: the `tools/concept` projections).
# When the served MCP `concept` arm or the served hover arm lands, it must
# satisfy this gate with the seam pointed at it; the projections then become
# its conformance oracle, not a second enforcement.
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/.." && pwd)
cd "$root" || { printf 'converge: cannot enter root\n' >&2; exit 3; }

IDOL=${IDOL:-"$root/zig-out/bin/idol"}
doc=${CONVERGE_DOC:-$here/../tools/concept/doc.sh}
tool=${CONVERGE_TOOL:-$here/../tools/concept/tool.sh}
hover=${CONVERGE_HOVER:-$here/../tools/concept/hover.sh}

if [ ! -x "$IDOL" ]; then
    printf 'converge: NOT MEASURED — %s is not a compiler (a checked graph was required)\n' "$IDOL" >&2
    exit 3
fi
if [ ! -x "$doc" ]; then
    printf 'converge: NOT MEASURED — %s is not executable (the docs projection was required)\n' "$doc" >&2
    exit 3
fi
if [ ! -x "$tool" ]; then
    printf 'converge: NOT MEASURED — %s is not executable (the tool projection was required)\n' "$tool" >&2
    exit 3
fi
if [ ! -x "$hover" ]; then
    printf 'converge: NOT MEASURED — %s is not executable (the hover projection was required)\n' "$hover" >&2
    exit 3
fi

command -v jq >/dev/null 2>&1 || {
    printf 'converge: NOT MEASURED — jq is required to frame the tool and hover contracts\n' >&2
    exit 3
}
command -v python3 >/dev/null 2>&1 || {
    printf 'converge: NOT MEASURED — python3 is required to encode the file uris\n' >&2
    exit 3
}

work=$(mktemp -d "${TMPDIR:-/tmp}/idol.converge.XXXXXX") || exit 3
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
# positive controls that one produced verdict reaches three readers as one
# text.
printf 'plus(a: i64, b: i64): i64\n  a + b\nminus(a: i64, b: i64): i64\n  a - b\nmain(): i64\n  x = plus(2, 3)\n  x + 1\nentry(): i64\n  minus(7, 4)\n' >"$work/my bucket.id" || exit 3
printf 'plus(a: i64, b: i64): i64\n  a + b\nminus(a: i64, b: i64): i64\n  a - b\nmain(): i64\n  x = plus(2, 3)\n  y = plus(1, 1)\n  minus(y, 4)\n' >"$work/cohort.id" || exit 3
printf 'plus(a: i64, b: i64): i64\n  a + b\nmain(): i64\n  x = plus(2, 3)\n  x + 1\n' >"$work/unwitnessed.id" || exit 3

examined=0
failed=0

# agree <label> <file> <needle> [<needle> ...]: all three faces render one text.
agree() {
    label=$1
    file=$2
    shift 2
    id=$((examined + 1))
    # The docs face is the reference text; the needles keep it non-empty.
    sh "$doc" "$file" >"$work/face.doc" 2>"$work/face.doc.diag" || {
        printf 'converge: FAIL — %s docs face refused a subject that demands a record\n' "$label" >&2
        cat "$work/face.doc.diag" >&2
        failed=$((failed + 1))
        return 1
    }
    # The reference answered, so the agreement is examined even when a later
    # face fails — the same examined semantics the sibling gates hold.
    examined=$((examined + 1))
    for needle in "$@"; do
        grep -Fq "$needle" <"$work/face.doc" || {
            printf 'converge: FAIL — %s reference text misses %s\n' "$label" "$needle" >&2
            cat "$work/face.doc" >&2
            failed=$((failed + 1))
            return 1
        }
    done
    # The MCP face must answer the same text as a tool result.
    req=$(jq -n -c --arg f "$file" --argjson id "$id" \
        '{jsonrpc:"2.0",id:$id,method:"tools/call",params:{name:"concept",arguments:{file:$f}}}') || exit 3
    printf '%s\n' "$req" | sh "$tool" >"$work/face.mcp.json" 2>"$work/face.mcp.diag" || {
        printf 'converge: FAIL — %s tool face exited nonzero\n' "$label" >&2
        failed=$((failed + 1))
        return 1
    }
    [ "$(wc -l <"$work/face.mcp.json" | tr -d ' ')" = "1" ] || {
        printf 'converge: FAIL — %s tool face answered more than one line\n' "$label" >&2
        failed=$((failed + 1))
        return 1
    }
    jq -e --argjson id "$id" '.id == $id and (has("error") | not)' <"$work/face.mcp.json" >/dev/null 2>&1 || {
        printf 'converge: FAIL — %s tool face lost its id or carried an error where a verdict was demanded\n' "$label" >&2
        cat "$work/face.mcp.json" >&2
        failed=$((failed + 1))
        return 1
    }
    jq -r '.result.content[0].text // ""' <"$work/face.mcp.json" 2>/dev/null >"$work/face.mcp" || {
        printf 'converge: FAIL — %s tool face carried no text\n' "$label" >&2
        failed=$((failed + 1))
        return 1
    }
    # The LSP face must answer the same text as hover markdown. The uri is a
    # file argument: spaces travel percent-encoded and the projection decodes
    # them, so the spaced bucket crosses intact or not at all.
    uri="file://$(printf '%s' "$file" | sed 's/ /%20/g')"
    req=$(jq -n -c --arg u "$uri" --argjson id "$id" \
        '{jsonrpc:"2.0",id:$id,method:"textDocument/hover",params:{textDocument:{uri:$u},position:{line:0,character:0}}}') || exit 3
    printf '%s\n' "$req" | sh "$hover" >"$work/face.hover.json" 2>"$work/face.hover.diag" || {
        printf 'converge: FAIL — %s hover face exited nonzero\n' "$label" >&2
        failed=$((failed + 1))
        return 1
    }
    [ "$(wc -l <"$work/face.hover.json" | tr -d ' ')" = "1" ] || {
        printf 'converge: FAIL — %s hover face answered more than one line\n' "$label" >&2
        failed=$((failed + 1))
        return 1
    }
    jq -e --argjson id "$id" '.id == $id and (has("error") | not) and .result.contents.kind == "markdown"' \
        <"$work/face.hover.json" >/dev/null 2>&1 || {
        printf 'converge: FAIL — %s hover face lost its id, carried an error, or is not markdown\n' "$label" >&2
        cat "$work/face.hover.json" >&2
        failed=$((failed + 1))
        return 1
    }
    jq -r '.result.contents.value // ""' <"$work/face.hover.json" 2>/dev/null >"$work/face.hover" || {
        printf 'converge: FAIL — %s hover face carried no value\n' "$label" >&2
        failed=$((failed + 1))
        return 1
    }
    # The agreement itself: a face carrying the verdict line plus one invented
    # paragraph passes every needle gate and fails here.
    cmp -s "$work/face.doc" "$work/face.mcp" || {
        printf 'converge: FAIL — %s tool text differs from the docs render\n' "$label" >&2
        failed=$((failed + 1))
        return 1
    }
    cmp -s "$work/face.doc" "$work/face.hover" || {
        printf 'converge: FAIL — %s hover value differs from the docs render\n' "$label" >&2
        failed=$((failed + 1))
        return 1
    }
}

# ── every produced direction ─────────────────────────────────────────────
agree refused-bucket "$work/my bucket.id" \
    "# Concept record — " \
    "shared_demand=0" \
    "verdict: REFUSED no_shared_demand split="
agree held-cohort "$work/cohort.id" \
    "# Concept record — " \
    "shared_demand=1" \
    "verdict: HELD one concept"
agree held-unwitnessed "$work/unwitnessed.id" \
    "# Concept record — " \
    "identity: relations=2 shapes=0 applications=1 shared_demand=0" \
    "verdict: HELD one concept"

[ "$examined" -gt 0 ] || {
    printf 'converge: FAIL — 0 face agreements examined\n' >&2
    exit 1
}
if [ "$failed" -ne 0 ]; then
    printf 'converge: FAIL — %s of %s examined agreement(s) failed\n' "$failed" "$examined" >&2
    exit 1
fi
printf 'converge: PASS — %s examined agreement(s), 0 failed\n' "$examined"
exit 0
