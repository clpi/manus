#!/bin/sh
# gate/mcp-frontier.sh — tests for the MCP frontier tool (GAP-181).
set -u
cd "$(dirname "$0")/.."
PASS=0
FAIL=0
ok() { PASS=$((PASS+1)); printf 'ok %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL %s: %s\n' "$1" "$2"; }

# Build frontier request with printf %s for args
freq() {
  printf '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"frontier","arguments":%s}}\n' "$1" | timeout 120 ./bin/idol-main-mcp.sh 2>/dev/null | tail -1
}

# Case 1: known file
printf 'main: i64 = ()\n  0\nmain()\n' > /tmp/ft.id
R=$(freq '{"file":"/tmp/ft.id"}')
T=$(printf '%s' "$R" | python3 -c "import sys,json; print(json.load(sys.stdin)['result']['content'][0]['text'])" 2>/dev/null)
F=$(printf '%s' "$T" | python3 -c "import sys,json; t=json.load(sys.stdin); print(t['known']['applications'], t['decision'])" 2>/dev/null)
if [ "$F" = "1 nothing-to-learn" ]; then ok "frontier-known"; else bad "frontier-known" "[$F]"; fi

# Case 2: missing file arg
R=$(freq '{}')
C=$(printf '%s' "$R" | python3 -c "import sys,json; print(json.load(sys.stdin)['error']['code'])" 2>/dev/null)
if [ "$C" = "-32602" ]; then ok "frontier-missing-arg"; else bad "frontier-missing-arg" "[$C]"; fi

# Case 3: bad file
R=$(freq '{"file":"/tmp/does-not-exist-xyz.id"}')
E=$(printf '%s' "$R" | python3 -c "import sys,json; print(json.loads(json.load(sys.stdin)['error']['message'])['reason'])" 2>/dev/null)
if [ "$E" = "graph-failed" ]; then ok "frontier-badfile"; else bad "frontier-badfile" "[$E]"; fi

# Case 4: listed
R=$(printf '{"jsonrpc":"2.0","id":2,"method":"tools/list"}\n' | timeout 60 ./bin/idol-main-mcp.sh 2>/dev/null | tail -1)
case "$R" in *'"name":"frontier"'*) ok "frontier-listed";; *) bad "frontier-listed" "missing";; esac

# Case 5: world still works
R=$(printf '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"world","arguments":{"subject":"concept","file":"/tmp/ft.id"}}}\n' | timeout 120 ./bin/idol-main-mcp.sh 2>/dev/null | tail -1)
case "$R" in *'HELD'*|*'unavailable-participant'*|*'"result"'*) ok "frontier-no-world-regression";; *) bad "frontier-no-world-regression" "$(printf '%s' "$R" | head -c 80)";; esac

rm -f /tmp/ft.id
printf 'pass=%d fail=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
