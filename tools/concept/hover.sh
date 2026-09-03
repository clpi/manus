#!/bin/sh
# tools/concept/hover.sh — LSP hover projection of the produced concept verdict (GAP-120).
#
# A file is the durable home of one semantic concept. The graph PRODUCED that
# finding (identities plus demand-join refusals, schema 17), `idol explain`
# projects it as `.concept`, `tools/concept/doc.sh` renders it as a markdown
# concept record held against the graph export's own `concepts[]`/`refusals[]`,
# and `tools/concept/tool.sh` serves that render over MCP. This file is the
# LSP face of that same render: one JSON-RPC `textDocument/hover` request
# object on stdin, one response object on stdout. It owns no derivation:
# every verdict it returns was produced on the graph and re-verified on
# export before `doc.sh` saw it; the projection refuses rather than invents
# whenever the verdict cannot be produced.
#
# WHY THIS EXISTS BESIDE ANY SERVED LSP SERVER. No local LSP surface exists:
# `tools/lsp/src` carries only a retired classifier, and the compiler-query
# server lives in a tree with no checkout on this host — so a served hover
# arm is IMPLEMENTATION-BLOCKED the same way the MCP `concept` arm is (see
# gaps/GAP-120.md). This file is the exact argv-level projection that arm
# will serve, held executable here by `gate/lsp.sh`, so the contract is
# measured before any server exists instead of after. When the arm lands it
# must satisfy `gate/lsp.sh`'s fixtures; this file then becomes its
# conformance oracle, not a second server.
#
# CONTRACT. One request object per invocation, read from stdin (a single
# line; newline-delimited framing like a served stream):
#   {"jsonrpc":"2.0","id":<any>,"method":"textDocument/hover",
#    "params":{"textDocument":{"uri":"file://<subject .id>"},
#              "position":{"line":<n>,"character":<m>}}}
# The uri travels to `doc.sh` as an argv element, never interpolated through
# a host shell (host-transport norm: file arguments are argv). The `file://`
# scheme is stripped and percent-escapes decoded, so a subject whose name
# carries a space arrives intact. Position selects within the file; the
# concept verdict is a file-home fact, so every position answers the same
# render. The response is exactly one line on stdout; diagnostics go to
# stderr, so protocol stdout carries protocol data only. The hover value is
# the `doc.sh` render byte-for-byte, wrapped as LSP `MarkupContent`.
#
# FAIL-CLOSED. A produced verdict (REFUSED or HELD) returns as a hover
# result. Anything else — unparseable request, unknown method, missing or
# non-string uri, a non-`file://` uri, a misshapen position, a subject
# `doc.sh` refuses — returns a JSON-RPC error and never a hover-shaped
# result.
#
# Usage:
#   printf '%s\n' "$request" | tools/concept/hover.sh
#
# Exit: 0 a response object was written (result or error); 3 not measured
# (no jq or no python3).
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/../.." && pwd)
doc=$here/doc.sh

command -v jq >/dev/null 2>&1 || {
  printf 'hover: NOT MEASURED — jq is required to frame the hover projection\n' >&2
  exit 3
}
command -v python3 >/dev/null 2>&1 || {
  printf 'hover: NOT MEASURED — python3 is required to decode the file uri\n' >&2
  exit 3
}

# One line is one request object. A second object on the same line is not a
# longer request; it is damage, and jq refuses it below.
line=
IFS= read -r line || line=""
[ -n "$line" ] || {
  printf '{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"hover: parse error"}}\n'
  exit 0
}

work=$(mktemp -d "${TMPDIR:-/tmp}/idol.concepthover.XXXXXX") || exit 3
cleanup() { rm -rf -- "$work"; }
trap 'cleanup' EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup; exit 129' HUP

printf '%s' "$line" >"$work/request.json"
if ! jq -e . <"$work/request.json" >/dev/null 2>&1; then
  printf '{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"hover: parse error"}}\n'
  exit 0
fi
# Exactly one object per line: a second value on the same line is damage.
[ "$(jq -s 'length' <"$work/request.json" 2>/dev/null)" = "1" ] || {
  printf '{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"hover: parse error"}}\n'
  exit 0
}

idjson=$(jq -c '.id // null' <"$work/request.json" 2>/dev/null) || idjson="null"

# NOTIFICATION-ZERO. An object without an `id` member is a notification, and
# JSON-RPC demands the server NEVER reply to one — not a result, not an
# error, not even on a bad method or bad uri. A hover face that answers a
# notification corrupts the stream a reader frames by. `id: null` PRESENT is
# still a request (discouraged, but the id is a member) and keeps the answer
# path; absent is the notification. No reply is ever fabricated, so a
# notification consumes one line and responds with zero bytes, exit 0.
jq -e 'has("id")' <"$work/request.json" >/dev/null 2>&1 || exit 0

respond_error() {
  code=$1
  message=$2
  jq -n -c --argjson id "$idjson" --argjson code "$code" --arg msg "$message" \
    '{"jsonrpc":"2.0","id":$id,"error":{"code":$code,"message":$msg}}'
  exit 0
}

method=$(jq -r '.method // ""' <"$work/request.json" 2>/dev/null) || method=""
[ "$method" = "textDocument/hover" ] || respond_error -32601 "hover: method not found"
utype=$(jq -r '.params.textDocument.uri | type // "absent"' <"$work/request.json" 2>/dev/null) || utype="absent"
[ "$utype" = "string" ] || respond_error -32602 "hover: invalid params: params.textDocument.uri is required"
uri=$(jq -r '.params.textDocument.uri' <"$work/request.json" 2>/dev/null) || uri=""
case $uri in
  file://*) ;;
  *) respond_error -32602 "hover: invalid params: only the file scheme is served" ;;
esac
ptype=$(jq -r '.params.position | type // "absent"' <"$work/request.json" 2>/dev/null) || ptype="absent"
case $ptype in
  absent|null) ;;
  object)
    ltype=$(jq -r '.params.position.line | type // "absent"' <"$work/request.json" 2>/dev/null) || ltype="absent"
    ctype=$(jq -r '.params.position.character | type // "absent"' <"$work/request.json" 2>/dev/null) || ctype="absent"
    case $ltype in absent|null|number) ;; *) respond_error -32602 "hover: invalid params: position.line must be a number" ;; esac
    case $ctype in absent|null|number) ;; *) respond_error -32602 "hover: invalid params: position.character must be a number" ;; esac
    ;;
  *) respond_error -32602 "hover: invalid params: position must be an object" ;;
esac

# The uri is a file argument, never shell-interpolated: the scheme is
# stripped, percent-escapes decoded, and the path travels to doc.sh as one
# argv element, so a name carrying spaces or shell metacharacters still
# renders (gate/lsp.sh holds a spaced path as the positive control).
raw=${uri#file://}
if ! file=$(python3 -c 'import sys,urllib.parse; print(urllib.parse.unquote(sys.argv[1]))' "$raw" 2>"$work/uri.err"); then
  detail=$(tail -1 <"$work/uri.err" | tr '\n' ' ' | cut -c1-200)
  [ -n "$detail" ] || detail="the file uri could not be decoded"
  respond_error -32602 "hover: $detail"
fi

if ! render=$("$doc" "$file" 2>"$work/doc.err"); then
  detail=$(tail -3 <"$work/doc.err" | tr '\n' ' ' | cut -c1-300)
  [ -n "$detail" ] || detail="the concept verdict could not be rendered"
  respond_error -32000 "hover: $detail"
fi

value=$(printf '%s' "$render" | jq -Rs . | tr -d '\n')
[ -n "$value" ] || respond_error -32000 "hover: the concept verdict could not be rendered"
jq -n -c --argjson id "$idjson" --argjson value "$value" \
  '{"jsonrpc":"2.0","id":$id,"result":{"contents":{"kind":"markdown","value":$value}}}'
exit 0
