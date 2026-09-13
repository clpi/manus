#!/bin/bash
# Gate: persistent MCP server integration via bin/idol-main-mcp.sh.
# Verifies the full request path through ONE long-lived server process:
# initialize -> tools/list -> world -> world (incarnation stability) ->
# frontier -> adversarial no-shell probe.
set -u
cd "$(dirname "$0")/.." || exit 1

pass=0; fail=0
ok() { pass=$((pass+1)); echo "ok $1"; }
bad() { fail=$((fail+1)); echo "FAIL $1: $2"; }

printf 'main: i64 = ()\n  1\nmain()\n' > /tmp/ps-wt.id

# Start the persistent server via the real launcher, on FIFOs.
rm -f /tmp/ps-in /tmp/ps-out
mkfifo /tmp/ps-in /tmp/ps-out
timeout 120 bin/idol-main-mcp.sh </tmp/ps-in >/tmp/ps-out 2>/tmp/ps-srv.err &
SRV_PID=$!
exec 3>/tmp/ps-in
exec 4</tmp/ps-out

send() { printf '%s\n' "$1" >&3; }
recv() { timeout 60 head -1 <&4; }

# --- Case 1: initialize + tools/list on the persistent server ---
send '{"jsonrpc":"2.0","id":1,"method":"initialize"}'
R1=$(recv)
case "$R1" in
  *'"protocolVersion":"2024-11-05"'*) ok "ps-initialize" ;;
  *) bad "ps-initialize" "[$R1]" ;;
esac

send '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
R2=$(recv)
case "$R2" in
  *'"name":"world"'*'"name":"frontier"'*) ok "ps-tools-list" ;;
  *) bad "ps-tools-list" "[$R2]" ;;
esac

# --- Case 2: world call through the persistent server ---
send '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"world","arguments":{"subject":"concept","file":"/tmp/ps-wt.id"}}}'
R3=$(recv)
V3=$(printf '%s' "$R3" | python3 -c "
import sys,json
t=json.load(sys.stdin)
inner=json.loads(t['result']['content'][0]['text'])
print(inner.get('verdict',''), inner['world'].get('incarnation',''))
" 2>/dev/null)
INC1=$(printf '%s' "$V3" | awk '{print $2}')
case "$V3" in
  "HELD "*) ok "ps-world-held" ;;
  *) bad "ps-world-held" "[$V3]" ;;
esac

# --- Case 3: second world call on the SAME server shares the incarnation ---
send '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"world","arguments":{"subject":"concept","file":"/tmp/ps-wt.id"}}}'
R4=$(recv)
INC2=$(printf '%s' "$R4" | python3 -c "
import sys,json
t=json.load(sys.stdin)
inner=json.loads(t['result']['content'][0]['text'])
print(inner['world'].get('incarnation',''))
" 2>/dev/null)
if [ -n "$INC1" ] && [ "$INC1" = "$INC2" ]; then
  ok "ps-incarnation-stable"
else
  bad "ps-incarnation-stable" "[$INC1] vs [$INC2]"
fi

# --- Case 4: frontier call through the persistent server ---
send '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"frontier","arguments":{"file":"/tmp/ps-wt.id"}}}'
R5=$(recv)
case "$R5" in
  *known*unknown*decision*) ok "ps-frontier" ;;
  *) bad "ps-frontier" "[$R5]" ;;
esac

# --- Case 5: adversarial no-shell probe ---
# Shell metacharacters in the request must reach the worker as data, never execute.
rm -f /tmp/ps-pwned
send '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"world","arguments":{"subject":"concept","file":"/tmp/ps-wt.id\";touch /tmp/ps-pwned;echo \""}}}'
timeout 60 head -1 <&4 >/dev/null 2>&1
sleep 1
if [ -e /tmp/ps-pwned ]; then
  bad "ps-no-shell" "/tmp/ps-pwned was created"
else
  ok "ps-no-shell"
fi

# --- Case 6: incarnation consistent within this server ---
send '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"world","arguments":{"subject":"concept","file":"/tmp/ps-wt.id"}}}'
R7=$(recv)
INC3=$(printf '%s' "$R7" | python3 -c "
import sys,json
t=json.load(sys.stdin)
inner=json.loads(t['result']['content'][0]['text'])
print(inner['world'].get('incarnation',''))
" 2>/dev/null)
if [ -n "$INC3" ] && [ "$INC3" = "$INC1" ]; then
  ok "ps-incarnation-consistent"
else
  bad "ps-incarnation-consistent" "[$INC3] vs [$INC1]"
fi

# --- Case 7: contrast dispatch through the persistent server ---
printf 'main: i64 = ()\n  0\nmain()\n' > /tmp/ps-ct.id
send '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"contrast","arguments":{"file":"/tmp/ps-ct.id","ambiguity":{"kind":"tiebreak","region":"r1","candidates":["keep-first","keep-last","report-conflict"]}}}}'
R8=$(recv)
case "$R8" in
  *question_id*) ok "ps-contrast" ;;
  *) bad "ps-contrast" "[$R8]" ;;
esac

# --- Case 8: preview dispatch through the persistent server ---
printf 'apply: i64 = (f: i64, x: i64)\n  f(x)\nmain: i64 = ()\n  apply(1, 2)\nmain()\n' > /tmp/ps-pv.id
UNK=$(timeout 60 ./zig-out/bin/idol graph /tmp/ps-pv.id 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
nodes={n['id']:n for n in d['nodes']}
u=d['unresolved_applications'][0]
n=nodes[u]
print('call|'+n['callee_kind']+'|'+str(n['arg_count'])+'|'+str(n['line'])+'|'+str(n['col']))
" 2>/dev/null)
send "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"tools/call\",\"params\":{\"name\":\"preview\",\"arguments\":{\"file\":\"/tmp/ps-pv.id\",\"projection\":\"frontier\",\"edit\":{\"kind\":\"acquire\",\"unknown\":\"$UNK\",\"decision\":\"acquire\"}}}}"
R9=$(recv)
case "$R9" in
  *proposal*acquire*) ok "ps-preview" ;;
  *) bad "ps-preview" "[$R9]" ;;
esac

# Shut down the persistent server.
exec 3>&- 4<&-
wait $SRV_PID 2>/dev/null
rm -f /tmp/ps-in /tmp/ps-out

# --- Case 9: a fresh server gets a fresh incarnation ---
INC4=$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"world","arguments":{"subject":"concept","file":"/tmp/ps-wt.id"}}}' \
  | timeout 60 bin/idol-main-mcp.sh 2>/dev/null | tail -1 | python3 -c "
import sys,json
t=json.load(sys.stdin)
inner=json.loads(t['result']['content'][0]['text'])
print(inner['world'].get('incarnation',''))
" 2>/dev/null)
if [ -n "$INC4" ] && [ -n "$INC1" ] && [ "$INC4" != "$INC1" ]; then
  ok "ps-incarnation-fresh"
else
  bad "ps-incarnation-fresh" "[$INC4] vs [$INC1]"
fi

rm -f /tmp/ps-wt.id /tmp/ps-pwned /tmp/ps-ct.id /tmp/ps-pv.id
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
