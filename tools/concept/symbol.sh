#!/bin/sh
# tools/concept/symbol.sh — LSP document-symbol projection of the produced concept verdict (GAP-120).
#
# A file is the durable home of one semantic concept. The graph PRODUCED that
# finding (identities plus demand-join refusals, schema 17), `idol graph`
# exports it as `concepts[]` and as a `concept` face on the file's module
# node, `tools/concept/doc.sh` renders it, and `tools/concept/definition.sh`
# projects the produced module-node face as a definition target. This file is
# the LSP document-symbol face of the same finding: one JSON-RPC
# `textDocument/documentSymbol` request object on stdin, one response object
# on stdout, whose result carries exactly one symbol named by the produced
# concept home at the produced file boundary. It owns no derivation: the home
# is the produced module-node face, and the projection refuses rather than
# invents whenever that face cannot be produced.
#
# WHY THIS EXISTS BESIDE ANY SERVED LSP SERVER. No local LSP surface exists:
# `tools/lsp/src` carries only a retired classifier, and the compiler-query
# server lives in a tree with no checkout on this host — so a served document
# symbol arm is IMPLEMENTATION-BLOCKED the same way the served hover and
# definition arms are (see gaps/GAP-120.md). This file is the exact argv-level
# projection that arm will serve, held executable by `gate/lsp.sh`, so the
# contract is measured before any server exists instead of after. When the arm
# lands it must satisfy `gate/lsp.sh`'s fixtures; this file then becomes its
# conformance oracle, not a second server.
#
# CONTRACT. One request object per invocation, read from stdin (a single line;
# newline-delimited framing like a served stream):
#   {"jsonrpc":"2.0","id":<any>,"method":"textDocument/documentSymbol",
#    "params":{"textDocument":{"uri":"file://<subject .id>"}}}
# The uri travels to the compiler as an argv element, never interpolated
# through a host shell. The `file://` scheme is stripped and percent-escapes
# decoded, so a subject whose name carries a space arrives intact. The response
# is exactly one line on stdout; diagnostics go to stderr, so protocol stdout
# carries protocol data only. The result is a single LSP DocumentSymbol whose
# name and extension field `concept` both carry the produced home. The numeric
# `kind` is the foreign LSP module code required by the wire protocol; it is
# not an Idol semantic discriminator.
#
# NOTIFICATION-ZERO. An object without an `id` member is a notification, and
# JSON-RPC demands the server NEVER reply to one — not a result, not an error,
# not even on a bad method or bad uri. A present `id: null` is still a request
# and keeps the answer path.
#
# FAIL-CLOSED. A produced home returns as one document symbol. Anything else —
# unparseable request, unknown method, missing or non-string uri, a non-`file://`
# uri, a subject the graph refuses (unreadable, unparseable, or verdict-less),
# or a missing/duplicated module-node face — returns a JSON-RPC error and never
# a symbol-shaped result.
#
# Usage:
#   printf '%s\n' "$request" | tools/concept/symbol.sh
#
# Exit: 0 a response object was written (result or error); 3 not measured
# (no jq or no python3 or no compiler).
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/../.." && pwd)
IDOL=${IDOL:-"$root/zig-out/bin/idol"}

command -v jq >/dev/null 2>&1 || {
  printf 'symbol: NOT MEASURED — jq is required to frame the document-symbol projection\n' >&2
  exit 3
}
command -v python3 >/dev/null 2>&1 || {
  printf 'symbol: NOT MEASURED — python3 is required to decode the file uri\n' >&2
  exit 3
}
[ -x "$IDOL" ] || {
  printf 'symbol: NOT MEASURED — %s is not a compiler (a produced graph was required)\n' "$IDOL" >&2
  exit 3
}

# One line is one request object. A second object on the same line is damage.
line=
IFS= read -r line || line=""
[ -n "$line" ] || {
  printf '{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"symbol: parse error"}}\n'
  exit 0
}

work=$(mktemp -d "${TMPDIR:-/tmp}/idol.conceptsymbol.XXXXXX") || exit 3
cleanup() { rm -rf -- "$work"; }
trap 'cleanup' EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup; exit 129' HUP

printf '%s' "$line" >"$work/request.json"
if ! jq -e . <"$work/request.json" >/dev/null 2>&1; then
  printf '{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"symbol: parse error"}}\n'
  exit 0
fi
[ "$(jq -s 'length' <"$work/request.json" 2>/dev/null)" = "1" ] || {
  printf '{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"symbol: parse error"}}\n'
  exit 0
}

idjson=$(jq -c '.id // null' <"$work/request.json" 2>/dev/null) || idjson="null"

# NOTIFICATION-ZERO: absent id means no response at all. A present null id is
# still a request because the member exists.
jq -e 'has("id")' <"$work/request.json" >/dev/null 2>&1 || exit 0

respond_error() {
  code=$1
  message=$2
  jq -n -c --argjson id "$idjson" --argjson code "$code" --arg msg "$message" \
    '{"jsonrpc":"2.0","id":$id,"error":{"code":$code,"message":$msg}}'
  exit 0
}

method=$(jq -r '.method // ""' <"$work/request.json" 2>/dev/null) || method=""
[ "$method" = "textDocument/documentSymbol" ] || respond_error -32601 "symbol: method not found"
utype=$(jq -r '.params.textDocument.uri | type // "absent"' <"$work/request.json" 2>/dev/null) || utype="absent"
[ "$utype" = "string" ] || respond_error -32602 "symbol: invalid params: params.textDocument.uri is required"
uri=$(jq -r '.params.textDocument.uri' <"$work/request.json" 2>/dev/null) || uri=""
case $uri in
  file://*) ;;
  *) respond_error -32602 "symbol: invalid params: only the file scheme is served" ;;
esac

raw=${uri#file://}
if ! file=$(python3 -c 'import sys,urllib.parse; print(urllib.parse.unquote(sys.argv[1]))' "$raw" 2>"$work/uri.err"); then
  detail=$(tail -1 <"$work/uri.err" | tr '\n' ' ' | cut -c1-200)
  [ -n "$detail" ] || detail="the file uri could not be decoded"
  respond_error -32602 "symbol: $detail"
fi

if ! "$IDOL" graph "$file" >"$work/graph.json" 2>"$work/graph.err"; then
  detail=$(tail -3 <"$work/graph.err" | tr '\n' ' ' | cut -c1-300)
  [ -n "$detail" ] || detail="the concept symbol could not be produced"
  respond_error -32000 "symbol: $detail"
fi

nodes=$(jq -c '[.nodes[] | select(.kind == "module" and has("concept"))]' <"$work/graph.json" 2>/dev/null) || nodes=""
[ "$(printf '%s' "$nodes" | jq 'length' 2>/dev/null)" = "1" ] || {
  respond_error -32000 "symbol: the produced module-node face is missing or duplicated"
}
home=$(printf '%s' "$nodes" | jq -r '.[0].concept // ""' 2>/dev/null)
line0=$(printf '%s' "$nodes" | jq -r '.[0].line // ""' 2>/dev/null)
case $home in
  ""|null) respond_error -32000 "symbol: the produced home is unreadable" ;;
esac
case $line0 in
  ""|null) respond_error -32000 "symbol: the produced line is unreadable" ;;
esac
[ "$line0" -eq 0 ] || respond_error -32000 "symbol: the produced module line is not the file boundary"

jq -n -c --argjson id "$idjson" --arg home "$home" --argjson line "$line0" \
  '{"jsonrpc":"2.0","id":$id,"result":[{"name":$home,"detail":"concept home","kind":2,"range":{"start":{"line":$line,"character":0},"end":{"line":$line,"character":0}},"selectionRange":{"start":{"line":$line,"character":0},"end":{"line":$line,"character":0}},"concept":$home}]}'
exit 0
