#!/bin/sh
# gate/mcp-world.sh — adversarial tests for the MCP world tool.
# Uses the actual persistent newline-delimited MCP server (bin/idol-main-mcp.sh).
# All test binaries run under timeout. Zero rows examined must fail.
set -u
cd "$(dirname "$0")/.."
PASS=0
FAIL=0
BIN="$PWD/zig-out/bin/idol"

ok() { PASS=$((PASS+1)); printf 'ok %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL %s: %s\n' "$1" "$2"; }

world_req() {
  printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/call\",\"params\":{\"name\":\"world\",\"arguments\":$1}}" \
    | timeout 120 ./bin/idol-main-mcp.sh 2>/dev/null | tail -1
}

# Extract inner text JSON field via python3
inner() {
  python3 -c "import sys,json; d=json.load(sys.stdin); r=d.get('result',{}); c=r.get('content',[{}])[0].get('text','{}'); print(c)" 2>/dev/null
}
err_inner() {
  python3 -c "import sys,json; d=json.load(sys.stdin); m=d.get('error',{}).get('message','{}'); print(m)" 2>/dev/null
}

# --- Case 1: happy path ---
printf 'main: i64 = ()\n  0\nmain()\n' > /tmp/wt1.id
R=$(world_req '{"subject":"concept","file":"/tmp/wt1.id"}')
T=$(printf '%s' "$R" | inner)
V=$(printf '%s' "$T" | python3 -c "import sys,json; t=json.load(sys.stdin); print(t.get('verdict',''), t['world'].get('revision',''), t['world'].get('binhash',''), len(t.get('obligations',[])))" 2>/dev/null)
case "$V" in
  HELD\ *\ *\ *)
    ok "case1-happy" ;;
  *) bad "case1-happy" "bad verdict/world: [$V]" ;;
esac

# --- Case 2: missing binary ---
R=$(printf '%s\n' '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"world","arguments":{"subject":"concept","file":"/tmp/wt1.id"}}}' \
  | env -u IDOL_WORLD_BIN timeout 120 ./zig-out/bin/idol run --backend=native tools/mcp/native.id 2>/dev/null | tail -1)
T=$(printf '%s' "$R" | err_inner)
E=$(printf '%s' "$T" | python3 -c "import sys,json; t=json.load(sys.stdin); print(t.get('reason',''), t.get('producer',''), 'verdict' in t)" 2>/dev/null)
case "$E" in
  "unavailable-participant launcher/build False") ok "case2-nobin" ;;
  *) bad "case2-nobin" "wrong: [$E]" ;;
esac

# --- Case 3: irrelevant changes -> same verdict/revision/binhash ---
R1=$(world_req '{"subject":"concept","file":"/tmp/wt1.id"}')
V1=$(printf '%s' "$R1" | inner | python3 -c "import sys,json; t=json.load(sys.stdin); print(t['verdict'], t['world']['revision'], t['world']['binhash'])" 2>/dev/null)
printf "x" > /tmp/irrelevant.txt
R2=$(world_req '{"subject":"concept","file":"/tmp/wt1.id"}')
V2=$(printf '%s' "$R2" | inner | python3 -c "import sys,json; t=json.load(sys.stdin); print(t['verdict'], t['world']['revision'], t['world']['binhash'])" 2>/dev/null)
rm -f /tmp/irrelevant.txt
if [ "$V1" = "$V2" ] && [ -n "$V1" ]; then ok "case3-irrelevant"; else bad "case3-irrelevant" "[$V1] vs [$V2]"; fi

# --- Case 4: duplicate revision ---
DUPBIN=/tmp/dup-idol; cp "$BIN" "$DUPBIN"; cp "$BIN.buildid" "$DUPBIN.buildid" 2>/dev/null || true
REV=$(git rev-parse HEAD); HASH=$(sha256sum "$DUPBIN" | cut -d' ' -f1)
printf '{"revision":"%s","binhash":"%s","revision":"%s"}\n' "$REV" "$HASH" "$REV" > "$DUPBIN.buildid"
R=$(printf '%s\n' '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"world","arguments":{"subject":"concept","file":"/tmp/wt1.id"}}}' \
  | IDOL_WORLD_BIN="$DUPBIN" IDOL_WORLD_ROOT="$PWD" timeout 120 ./zig-out/bin/idol run --backend=native tools/mcp/native.id 2>/dev/null | tail -1)
T=$(printf '%s' "$R" | err_inner)
E=$(printf '%s' "$T" | python3 -c "import sys,json; t=json.load(sys.stdin); print(t.get('reason',''), 'verdict' in t)" 2>/dev/null)
case "$E" in
  "ambiguous-revision False") ok "case4-duprev" ;;
  "malformed-sidecar False") ok "case4-duprev" ;;
  *) bad "case4-duprev" "wrong: [$E]" ;;
esac
rm -f "$DUPBIN" "$DUPBIN.buildid"

# --- Case 5: binary replaced ---
TMPBIN=/tmp/repl-idol; cp "$BIN" "$TMPBIN"; cp "$BIN.buildid" "$TMPBIN.buildid"
printf '#!/bin/sh\necho hi\n' > "$TMPBIN"; chmod +x "$TMPBIN"
R=$(printf '%s\n' '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"world","arguments":{"subject":"concept","file":"/tmp/wt1.id"}}}' \
  | IDOL_WORLD_BIN="$TMPBIN" IDOL_WORLD_ROOT="$PWD" timeout 120 ./zig-out/bin/idol run --backend=native tools/mcp/native.id 2>/dev/null | tail -1)
T=$(printf '%s' "$R" | err_inner)
E=$(printf '%s' "$T" | python3 -c "import sys,json; t=json.load(sys.stdin); print(t.get('reason',''), 'verdict' in t)" 2>/dev/null)
case "$E" in
  "binary-identity False") ok "case5-replaced" ;;
  *) bad "case5-replaced" "wrong: [$E]" ;;
esac
rm -f "$TMPBIN" "$TMPBIN.buildid"

# --- Case 6: sibling ---
R=$(world_req '{"subject":"sibling","file":"/tmp/wt1.id"}')
T=$(printf '%s' "$R" | err_inner)
case "$T" in
  *materialize\ the\ pinned\ idol-native\ checkout\ and\ provision\ credentials*) ok "case6-sibling" ;;
  *) bad "case6-sibling" "wrong next: $(printf '%s' "$T" | head -c 200)" ;;
esac

# --- Case 7: always-fail binary ---
FAILBIN=/tmp/fail-idol; printf '#!/bin/sh\nexit 3\n' > "$FAILBIN"; chmod +x "$FAILBIN"
FHASH=$(sha256sum "$FAILBIN" | cut -d' ' -f1)
printf '{"revision":"%s","binhash":"%s"}\n' "$REV" "$FHASH" > "$FAILBIN.buildid"
R=$(printf '%s\n' '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"world","arguments":{"subject":"concept","file":"/tmp/wt1.id"}}}' \
  | IDOL_WORLD_BIN="$FAILBIN" IDOL_WORLD_ROOT="$PWD" timeout 120 ./zig-out/bin/idol run --backend=native tools/mcp/native.id 2>/dev/null | tail -1)
T=$(printf '%s' "$R" | err_inner)
E=$(printf '%s' "$T" | python3 -c "import sys,json; t=json.load(sys.stdin); print(t.get('reason',''), 'derivation' in str(t.get('not-performed',[])), 'verdict' in t)" 2>/dev/null)
case "$E" in
  "derivation-failed True False") ok "case7-failbin" ;;
  *) bad "case7-failbin" "wrong: [$E]" ;;
esac
rm -f "$FAILBIN" "$FAILBIN.buildid"

# --- Case 8: unreadable subject ---
printf 'secret' > /tmp/wt-secret.id; chmod 000 /tmp/wt-secret.id
R=$(world_req '{"subject":"concept","file":"/tmp/wt-secret.id"}')
T=$(printf '%s' "$R" | err_inner)
E=$(printf '%s' "$T" | python3 -c "import sys,json; t=json.load(sys.stdin); print(t.get('reason',''), t.get('producer',''))" 2>/dev/null)
chmod 644 /tmp/wt-secret.id; rm -f /tmp/wt-secret.id
case "$E" in
  "unreadable-subject caller") ok "case8-unreadable" ;;
  *) bad "case8-unreadable" "wrong: [$E]" ;;
esac

# --- Malformed world params ---
R=$(printf '%s\n' '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"world"}}' | timeout 60 ./bin/idol-main-mcp.sh 2>/dev/null | tail -1)
C=$(printf '%s' "$R" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error',{}).get('code',''))" 2>/dev/null)
case "$C" in -32602) ok "malformed-params";; *) bad "malformed-params" "code=[$C]";; esac

# --- Existing arms ---
R=$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"ping"}' | timeout 60 ./bin/idol-main-mcp.sh 2>/dev/null | tail -1)
case "$R" in *'"result":{}'*) ok "existing-ping";; *) bad "existing-ping" "$(printf '%s' "$R" | head -c 100)";; esac
R=$(printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | timeout 60 ./bin/idol-main-mcp.sh 2>/dev/null | tail -1)
case "$R" in *'"name":"world"'*) ok "existing-list";; *) bad "existing-list" "$(printf '%s' "$R" | head -c 100)";; esac

printf 'pass=%d fail=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
