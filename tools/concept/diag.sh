#!/bin/sh
# tools/concept/diag.sh — LSP pull-diagnostic projection of the produced concept verdict (GAP-120).
#
# A file is the durable home of one semantic concept. The graph PRODUCED that
# finding (identities plus demand-join refusals, schema 17), `idol explain`
# projects it as `.concept`, `tools/concept/doc.sh` renders it as a markdown
# concept record held against the graph export's own
# `concepts[]`/`refusals[]`, `tools/concept/tool.sh` serves that render over
# MCP, and `tools/concept/hover.sh` serves it as the LSP hover. This file is
# the fourth crossable face of that same render and the first one that is NOT
# a hover or a build refusal: the LSP 3.17 pull model
# `textDocument/diagnostic`, where the client REQUESTS the document's
# diagnostics and the answer is a `DocumentDiagnosticReport`
# (`{"kind":"full","items":[...]}). It owns no derivation: every verdict it
# publishes was produced on the graph and re-verified on export before
# `doc.sh` saw it; the projection refuses rather than invents whenever the
# verdict cannot be produced.
#
# WHY THIS EXISTS BESIDE ANY SERVED LSP SERVER. No local LSP surface exists:
# `tools/lsp/src` carries only a retired classifier, and the compiler-query
# server lives in a tree with no checkout on this host — so a served pull
# arm is IMPLEMENTATION-BLOCKED the same way the MCP `concept` arm is (see
# gaps/GAP-120.md). Push diagnostics (`textDocument/publishDiagnostics`) are
# server-initiated and carry no request; the pull face is the one a client
# can be held to contractually. This file is the exact argv-level projection
# that arm will serve, held executable here by `gate/pull.sh`, so the
# contract is measured before any server exists instead of after. When the
# arm lands it must satisfy `gate/pull.sh`'s fixtures; this file then becomes
# its conformance oracle, not a second server.
#
# CONTRACT. One request object per invocation, read from stdin (a single
# line; newline-delimited framing like a served stream):
#   {"jsonrpc":"2.0","id":<any>,"method":"textDocument/diagnostic",
#    "params":{"textDocument":{"uri":"file://<subject .id>"}}}
# The uri travels to `doc.sh` as an argv element, never interpolated through
# a host shell (host-transport norm: file arguments are argv). The `file://`
# scheme is stripped and percent-escapes decoded, so a subject whose name
# carries a space arrives intact. The concept verdict is a file-home fact, so
# the report spans the whole document and carries NO position dependence:
# a produced REFUSED verdict yields one `severity:1` (Error) diagnostic whose
# range covers the file and whose message is the produced verdict line plus
# the produced identity evidence; a produced HELD verdict yields an empty
# `items` array — a clean bill, never a fabricated informational row
# (OBSERVATION-MINIMUM: a HELD file has no diagnostic to observe). The
# response is exactly one line on stdout; diagnostics go to stderr, so
# protocol stdout carries protocol data only.
#
# FAIL-CLOSED. A produced verdict returns as a report. Anything else —
# unparseable request, unknown method, missing or non-string uri, a
# non-`file://` uri, a misshapen `params`, a subject `doc.sh` refuses —
# returns a JSON-RPC error and never a report-shaped result.
#
# Usage:
#   printf '%s\n' "$request" | tools/concept/diag.sh
#
# Exit: 0 a response object was written (result or error); 3 not measured
# (no jq or no python3).
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/../.." && pwd)
doc=$here/doc.sh

command -v jq >/dev/null 2>&1 || {
  printf 'diag: NOT MEASURED — jq is required to frame the pull projection\n' >&2
  exit 3
}
command -v python3 >/dev/null 2>&1 || {
  printf 'diag: NOT MEASURED — python3 is required to decode the file uri\n' >&2
  exit 3
}

# One line is one request object. A second object on the same line is not a
# longer request; it is damage, and jq refuses it below.
line=
IFS= read -r line || line=""
[ -n "$line" ] || {
  printf '{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"diag: parse error"}}\n'
  exit 0
}

work=$(mktemp -d "${TMPDIR:-/tmp}/idol.conceptdiag.XXXXXX") || exit 3
cleanup() { rm -rf -- "$work"; }
trap 'cleanup' EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup; exit 129' HUP

printf '%s' "$line" >"$work/request.json"
if ! jq -e . <"$work/request.json" >/dev/null 2>&1; then
  printf '{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"diag: parse error"}}\n'
  exit 0
fi
# Exactly one object per line: a second value on the same line is damage.
[ "$(jq -s 'length' <"$work/request.json" 2>/dev/null)" = "1" ] || {
  printf '{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"diag: parse error"}}\n'
  exit 0
}

idjson=$(jq -c '.id // null' <"$work/request.json" 2>/dev/null) || idjson="null"

respond_error() {
  code=$1
  message=$2
  jq -n -c --argjson id "$idjson" --argjson code "$code" --arg msg "$message" \
    '{"jsonrpc":"2.0","id":$id,"error":{"code":$code,"message":$msg}}'
  exit 0
}

method=$(jq -r '.method // ""' <"$work/request.json" 2>/dev/null) || method=""
[ "$method" = "textDocument/diagnostic" ] || respond_error -32601 "diag: method not found"
utype=$(jq -r '.params.textDocument.uri | type // "absent"' <"$work/request.json" 2>/dev/null) || utype="absent"
[ "$utype" = "string" ] || respond_error -32602 "diag: invalid params: params.textDocument.uri is required"
uri=$(jq -r '.params.textDocument.uri' <"$work/request.json" 2>/dev/null) || uri=""
case $uri in
  file://*) ;;
  *) respond_error -32602 "diag: invalid params: only the file scheme is served" ;;
esac

# The uri is a file argument, never shell-interpolated: the scheme is
# stripped, percent-escapes decoded, and the path travels to doc.sh as one
# argv element, so a name carrying spaces or shell metacharacters still
# renders (gate/pull.sh holds a spaced path as the positive control).
raw=${uri#file://}
if ! file=$(python3 -c 'import sys,urllib.parse; print(urllib.parse.unquote(sys.argv[1]))' "$raw" 2>"$work/uri.err"); then
  detail=$(tail -1 <"$work/uri.err" | tr '\n' ' ' | cut -c1-200)
  [ -n "$detail" ] || detail="the file uri could not be decoded"
  respond_error -32602 "diag: $detail"
fi

if ! render=$("$doc" "$file" 2>"$work/doc.err"); then
  detail=$(tail -3 <"$work/doc.err" | tr '\n' ' ' | cut -c1-300)
  [ -n "$detail" ] || detail="the concept verdict could not be rendered"
  respond_error -32000 "diag: $detail"
fi

# The render carries two produced evidence lines: `verdict: ...` and
# `identity: ...`. Anything missing them is damage the gate convicts.
verdict=$(printf '%s\n' "$render" | awk '/^verdict: /{print; exit}')
identity=$(printf '%s\n' "$render" | awk '/^identity: /{print; exit}')
[ -n "$verdict" ] || respond_error -32000 "diag: the render carries no produced verdict line"

# The report spans the whole document: the verdict is a file-home fact, so
# the diagnostic range covers the file and no position selects within it.
line_count=$(wc -l <"$file" 2>/dev/null | tr -d ' ') || line_count=""
case $line_count in
  ''|*[!0-9]*) respond_error -32000 "diag: the subject file could not be measured" ;;
esac

case $verdict in
  "verdict: REFUSED "*)
    reason=${verdict#verdict: REFUSED }
    msg="concept $reason"
    [ -n "$identity" ] && msg="$msg — $identity"
    jq -n -c --argjson id "$idjson" --arg msg "$msg" --argjson end "$line_count" \
      '{"jsonrpc":"2.0","id":$id,"result":{"kind":"full","items":[{"range":{"start":{"line":0,"character":0},"end":{"line":$end,"character":0}},"severity":1,"source":"idol-concept","message":$msg}]}}'
    ;;
  "verdict: HELD "*)
    # A clean bill: no diagnostic to observe (OBSERVATION-MINIMUM). The
    # report still answers, with an empty items array.
    jq -n -c --argjson id "$idjson" \
      '{"jsonrpc":"2.0","id":$id,"result":{"kind":"full","items":[]}}'
    ;;
  *)
    respond_error -32000 "diag: the render carries no produced verdict line"
    ;;
esac
exit 0
