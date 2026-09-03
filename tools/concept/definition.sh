#!/bin/sh
# tools/concept/definition.sh — LSP definition projection of the produced concept verdict (GAP-120).
#
# A file is the durable home of one semantic concept. The graph PRODUCED that
# finding (identities plus demand-join refusals, schema 17), `idol explain`
# projects it as `.concept`, `tools/concept/doc.sh` renders it as a markdown
# concept record, `tools/concept/tool.sh` serves it over MCP, and
# `tools/concept/hover.sh` serves it as LSP hover text. This file is the LSP
# definition face of the same finding: one JSON-RPC `textDocument/definition`
# request object on stdin, one response object on stdout, whose result carries
# the produced concept home as an LSP `Location` — the uri of the subject file
# itself and the 1-based produced line of the module node (the definition of
# the concept is the file boundary that produced it). It owns no derivation:
# the home is the produced module-node face, re-verified against the
# `concepts[]` row by `gate/node.sh` before this file saw it; the projection
# refuses rather than invents whenever the home cannot be produced.
#
# WHY THIS EXISTS BESIDE ANY SERVED LSP SERVER. No local LSP surface exists:
# `tools/lsp/src` carries only a retired classifier, and the compiler-query
# server lives in a tree with no checkout on this host — so a served
# definition arm is IMPLEMENTATION-BLOCKED the same way the served hover arm
# is (see gaps/GAP-120.md). This file is the exact argv-level projection that
# arm will serve, held executable here by `gate/lsp.sh`, so the contract is
# measured before any server exists instead of after. When the arm lands it
# must satisfy `gate/lsp.sh`'s fixtures; this file then becomes its
# conformance oracle, not a second server.
#
# CONTRACT. One request object per invocation, read from stdin (a single
# line; newline-delimited framing like a served stream):
#   {"jsonrpc":"2.0","id":<any>,"method":"textDocument/definition",
#    "params":{"textDocument":{"uri":"file://<subject .id>"},
#              "position":{"line":<n>,"character":<m>}}}
# The uri travels to the compiler as an argv element, never interpolated
# through a host shell (host-transport norm: file arguments are argv). The
# `file://` scheme is stripped and percent-escapes decoded, so a subject whose
# name carries a space arrives intact. Position selects within the file; the
# concept definition is a file-home fact, so every position answers the same
# Location. The response is exactly one line on stdout; diagnostics go to
# stderr, so protocol stdout carries protocol data only. The definition is
# the produced module-node face (kind `module`, field `concept`): its uri is
# the subject uri byte-for-byte and its range starts at the produced 1-based
# line (0-based for the wire), the file boundary where the concept lives.
#
# NOTIFICATION-ZERO. An object without an `id` member is a notification, and
# JSON-RPC demands the server NEVER reply to one — not a result, not an
# error, not even on a bad method or bad uri. A present `id: null` is still a
# request (the id is a member) and keeps the answer path.
#
# FAIL-CLOSED. A produced home returns as a definition Location. Anything
# else — unparseable request, unknown method, missing or non-string uri, a
# non-`file://` uri, a misshapen position, a subject the graph refuses
# (unreadable, unparseable, or verdict-less) — returns a JSON-RPC error and
# never a Location-shaped result.
#
# Usage:
#   printf '%s\n' "$request" | tools/concept/definition.sh
#
# Exit: 0 a response object was written (result or error); 3 not measured
# (no jq or no python3 or no compiler).
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/../..")
IDOL=${IDOL:-"$root/zig-out/bin/idol"}

command -v jq >/dev/null 2>&1 || {
  printf 'definition: NOT MEASURED — jq is required to frame the definition projection\n' >&2
  exit 3
}
command -v python3 >/dev/null 2>&1 || {
  printf 'definition: NOT MEASURED — python3 is required to decode the file uri\n' >&2
  exit 3
}
[ -x "$IDOL" ] || {
  printf 'definition: NOT MEASURED — %s is not a compiler (a produced graph was required)\n' "$IDOL" >&2
  exit 3
}

# One line is one request object. A second object on the same line is not a
# longer request; it is damage, and jq refuses it below.
line=
IFS= read -r line || line=""
[ -n "$line" ] || {
  printf '{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"definition: parse error"}}\n'
  exit 0
}

work=$(mktemp -d "${TMPDIR:-/tmp}/idol.conceptdef.XXXXXX") || exit 3
cleanup() { rm -rf -- "$work"; }
trap 'cleanup' EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup; exit 129' HUP

printf '%s' "$line" >"$work/request.json"
if ! jq -e . <"$work/request.json" >/dev/null 2>&1; then
  printf '{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"definition: parse error"}}\n'
  exit 0
fi
# Exactly one object per line: a second value on the same line is damage.
[ "$(jq -s 'length' <"$work/request.json" 2>/dev/null)" = "1" ] || {
  printf '{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"definition: parse error"}}\n'
  exit 0
}

idjson=$(jq -c '.id // null' <"$work/request.json" 2>/dev/null) || idjson="null"

# NOTIFICATION-ZERO. An object without an `id` member is a notification, and
# JSON-RPC demands the server NEVER reply to one — not a result, not an
# error, not even on a bad method or bad uri. `id: null` PRESENT is still a
# request (discouraged, but the id is a member) and keeps the answer path;
# absent is the notification. No reply is ever fabricated, so a notification
# consumes one line and responds with zero bytes, exit 0.
jq -e 'has("id")' <"$work/request.json" >/dev/null 2>&1 || exit 0

respond_error() {
  code=$1
  message=$2
  jq -n -c --argjson id "$idjson" --argjson code "$code" --arg msg "$message" \
    '{"jsonrpc":"2.0","id":$id,"error":{"code":$code,"message":$msg}}'
  exit 0
}

method=$(jq -r '.method // ""' <"$work/request.json" 2>/dev/null) || method=""
[ "$method" = "textDocument/definition" ] || respond_error -32601 "definition: method not found"
utype=$(jq -r '.params.textDocument.uri | type // "absent"' <"$work/request.json" 2>/dev/null) || utype="absent"
[ "$utype" = "string" ] || respond_error -32602 "definition: invalid params: params.textDocument.uri is required"
uri=$(jq -r '.params.textDocument.uri' <"$work/request.json" 2>/dev/null) || uri=""
case $uri in
  file://*) ;;
  *) respond_error -32602 "definition: invalid params: only the file scheme is served" ;;
esac
ptype=$(jq -r '.params.position | type // "absent"' <"$work/request.json" 2>/dev/null) || ptype="absent"
case $ptype in
  absent|null) ;;
  object)
    ltype=$(jq -r '.params.position.line | type // "absent"' <"$work/request.json" 2>/dev/null) || ltype="absent"
    ctype=$(jq -r '.params.position.character | type // "absent"' <"$work/request.json" 2>/dev/null) || ctype="absent"
    case $ltype in absent|null|number) ;; *) respond_error -32602 "definition: invalid params: position.line must be a number" ;; esac
    case $ctype in absent|null|number) ;; *) respond_error -32602 "definition: invalid params: position.character must be a number" ;; esac
    ;;
  *) respond_error -32602 "definition: invalid params: position must be an object" ;;
esac

# The uri is a file argument, never shell-interpolated: the scheme is
# stripped, percent-escapes decoded, and the path travels to the compiler as
# one argv element, so a name carrying spaces or shell metacharacters still
# produces its graph (gate/lsp.sh holds a spaced path as the positive
# control).
raw=${uri#file://}
if ! file=$(python3 -c 'import sys,urllib.parse; print(urllib.parse.unquote(sys.argv[1]))' "$raw" 2>"$work/uri.err"); then
  detail=$(tail -1 <"$work/uri.err" | tr '\n' ' ' | cut -c1-200)
  [ -n "$detail" ] || detail="the file uri could not be decoded"
  respond_error -32602 "definition: $detail"
fi

if ! "$IDOL" graph "$file" >"$work/graph.json" 2>"$work/graph.err"; then
  detail=$(tail -3 <"$work/graph.err" | tr '\n' ' ' | cut -c1-300)
  [ -n "$detail" ] || detail="the concept definition could not be produced"
  respond_error -32000 "definition: $detail"
fi

# The definition is the produced module-node face: exactly one kind==module
# node carrying the `concept` field (the produced home). Zero or several, or
# a home that is not a string, is damage — refuse, never invent. The
# module-node face is the FILE boundary, so its produced line names the
# first line of the subject; a face answering any other line is damage.
nodes=$(jq -c '[.nodes[] | select(.kind == "module" and has("concept"))]' <"$work/graph.json" 2>/dev/null) || nodes=""
[ "$(printf '%s' "$nodes" | jq -s '.[0] | length' 2>/dev/null)" = "1" ] || {
  respond_error -32000 "definition: the produced module-node face is missing or duplicated"
}
home=$(printf '%s' "$nodes" | jq -r '.[0].concept // ""' 2>/dev/null)
line1=$(printf '%s' "$nodes" | jq -r '.[0].line // ""' 2>/dev/null)
case $home in
  ""|null) respond_error -32000 "definition: the produced home is unreadable" ;;
esac
case $line1 in
  ""|null) respond_error -32000 "definition: the produced line is unreadable" ;;
esac
[ "$line1" -eq 0 ] || respond_error -32000 "definition: the produced module line is not the file boundary"
line0=$line1

jq -n -c --argjson id "$idjson" --arg uri "$uri" --argjson line "$line0" \
  --arg home "$home" \
  '{"jsonrpc":"2.0","id":$id,"result":{"uri":$uri,"range":{"start":{"line":$line,"character":0},"end":{"line":$line,"character":0}},"concept":$home}}'
exit 0
