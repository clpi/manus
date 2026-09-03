#!/bin/sh
# tools/concept/tool.sh — MCP tool projection of the produced concept verdict (GAP-120).
#
# A file is the durable home of one semantic concept. The graph PRODUCED that
# finding (identities plus demand-join refusals, schema 17), `idol explain`
# projects it as `.concept`, and `tools/concept/doc.sh` renders it as a
# markdown concept record held against the graph export's own
# `concepts[]`/`refusals[]`. This file is the MCP face of that same render:
# one JSON-RPC `tools/call` request object on stdin, one response object on
# stdout. It owns no derivation: every verdict it returns was produced on the
# graph and re-verified on export before `doc.sh` saw it; the tool refuses
# rather than invents whenever the projection cannot be produced.
#
# WHY THIS EXISTS BESIDE tools/mcp/native.id. The served `idol` MCP server
# answers `tools/call` from `native.id`'s dispatch loop, and the `concept`
# arm belongs there (Still OPEN in gaps/GAP-120.md). That arm is
# IMPLEMENTATION-BLOCKED on the toolchain lane: the current parser refuses
# the `s:r(...)` subject face `native.id` is written in, in every position,
# on every host — `x:len()` and `stdin:line()` are rejected at parse, before
# any backend runs (GAP-145 transfer debt, not this gap). This file is the
# exact argv-level projection that arm will serve, held executable here by
# `gate/mcp.sh`, so the contract is measured before the parser heals instead
# of after. When the arm lands it must satisfy `gate/mcp.sh`'s fixtures; this
# file then becomes its conformance oracle, not a second server.
#
# CONTRACT. One request object per invocation, read from stdin (a single
# line; newline-delimited framing like the served stream):
#   {"jsonrpc":"2.0","id":<any>,"method":"tools/call",
#    "params":{"name":"concept","arguments":{"file":"<subject .id>"}}}
# The subject path travels to `doc.sh` as an argv element, never interpolated
# through a host shell (host-transport norm: file arguments are argv). The
# response is exactly one line on stdout; diagnostics go to stderr, so protocol
# stdout carries protocol data only.
#
# FAIL-CLOSED. A produced verdict (REFUSED or HELD) returns as a text result.
# Anything else — unparseable request, unknown tool or method, missing or
# non-string file, a subject `doc.sh` refuses — returns a JSON-RPC error and
# never a verdict-shaped result.
#
# Usage:
#   printf '%s\n' "$request" | tools/concept/tool.sh
#
# Exit: 0 a response object was written (result or error); 3 not measured
# (no jq).
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/../.." && pwd)
doc=$here/doc.sh

command -v jq >/dev/null 2>&1 || {
  printf 'tool: NOT MEASURED — jq is required to frame the tool projection\n' >&2
  exit 3
}

# One line is one request object. A second object on the same line is not a
# longer request; it is damage, and jq refuses it below.
line=
IFS= read -r line || line=""
[ -n "$line" ] || {
  printf '{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"tool: parse error"}}\n'
  exit 0
}

work=$(mktemp -d "${TMPDIR:-/tmp}/idol.concepttool.XXXXXX") || exit 3
cleanup() { rm -rf -- "$work"; }
trap 'cleanup' EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup; exit 129' HUP

printf '%s' "$line" >"$work/request.json"
if ! jq -e . <"$work/request.json" >/dev/null 2>&1; then
  printf '{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"tool: parse error"}}\n'
  exit 0
fi
# Exactly one object per line: a second value on the same line is damage.
[ "$(jq -s 'length' <"$work/request.json" 2>/dev/null)" = "1" ] || {
  printf '{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"tool: parse error"}}\n'
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
[ "$method" = "tools/call" ] || respond_error -32601 "tool: method not found"
name=$(jq -r '.params.name // ""' <"$work/request.json" 2>/dev/null) || name=""
[ "$name" = "concept" ] || respond_error -32601 "tool: method not found"
ftype=$(jq -r '.params.arguments.file | type // "absent"' <"$work/request.json" 2>/dev/null) || ftype="absent"
[ "$ftype" = "string" ] || respond_error -32602 "tool: invalid params: arguments.file is required"
file=$(jq -r '.params.arguments.file' <"$work/request.json" 2>/dev/null) || file=""

# The subject path is an argv element, never shell-interpolated: a path
# carrying spaces or shell metacharacters must still render (gate/mcp.sh
# holds a spaced path as the positive control).
if ! render=$("$doc" "$file" 2>"$work/doc.err"); then
  detail=$(tail -3 <"$work/doc.err" | tr '\n' ' ' | cut -c1-300)
  [ -n "$detail" ] || detail="the concept verdict could not be rendered"
  respond_error -32000 "tool: $detail"
fi

text=$(printf '%s' "$render" | jq -Rs . | tr -d '\n')
[ -n "$text" ] || respond_error -32000 "tool: the concept verdict could not be rendered"
jq -n -c --argjson id "$idjson" --argjson text "$text" \
  '{"jsonrpc":"2.0","id":$id,"result":{"content":[{"type":"text","text":$text}]}}'
exit 0
