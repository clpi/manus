#!/bin/sh
# gate/mcp-preview.sh -- adversarial tests for the MCP preview tool.
# Pipes JSON-RPC directly into `idol run --backend=native tools/mcp/preview.id`.
# All test binaries run under timeout. Zero rows examined must fail.
set -u
cd "$(dirname "$0")/.."
PASS=0
FAIL=0

ok() { PASS=$((PASS+1)); printf 'ok %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL %s: %s\n' "$1" "$2"; }

preview_req() {
  printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":11,\"method\":\"tools/call\",\"params\":{\"name\":\"preview\",\"arguments\":$1}}" \
    | timeout 120 ./zig-out/bin/idol run --backend=native tools/mcp/preview.id 2>/dev/null | tail -1
}

inner() {
  python3 -c "import sys,json; d=json.load(sys.stdin); r=d.get('result',{}); c=r.get('content',[{}])[0].get('text','{}'); print(c)" 2>/dev/null
}
err_inner() {
  python3 -c "import sys,json; d=json.load(sys.stdin); m=d.get('error',{}).get('message','{}'); print(m)" 2>/dev/null
}
err_code() {
  python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error',{}).get('code',''))" 2>/dev/null
}

# --- subjects ---
printf 'apply: i64 = (f: i64, x: i64)\n  f(x)\nmain: i64 = ()\n  apply(1, 2)\nmain()\n' > /tmp/pv-u1.id
printf 'main: i64 = ()\n  1\nmain()\n' > /tmp/pv-simp.id
printf 'q: i64 = (z: i64)\n  z\n' > /tmp/pv-m2.id
printf 'main: i64 = ()\n  m2.q(1)\nmain()\n' > /tmp/pv-m1.id
printf 'f: i64 = (x: i64)\n  x\ng: i64 = (y: i64)\n  y\nmain: i64 = ()\n  f(1)\nmain()\n' > /tmp/pv-two.id
UNK=$(timeout 60 ./zig-out/bin/idol graph /tmp/pv-u1.id 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
nodes={n['id']:n for n in d['nodes']}
u=d['unresolved_applications'][0]
n=nodes[u]
print('call|'+n['callee_kind']+'|'+str(n['arg_count'])+'|'+str(n['line'])+'|'+str(n['col']))
" 2>/dev/null)
RK1=$(timeout 60 ./zig-out/bin/idol graph /tmp/pv-m1.id 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
c=d['concepts'][0]
print(str(c['module'])+'|'+c['home']+'|'+str(c['relations'])+'|'+str(c['shapes'])+'|'+str(c['applications'])+'|'+str(c['shared_demand']))
" 2>/dev/null)
RK2=$(timeout 60 ./zig-out/bin/idol graph /tmp/pv-m1.id 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
c=d['concepts'][1]
print(str(c['module'])+'|'+c['home']+'|'+str(c['relations'])+'|'+str(c['shapes'])+'|'+str(c['applications'])+'|'+str(c['shared_demand']))
" 2>/dev/null)
RKC=$(timeout 60 ./zig-out/bin/idol graph /tmp/pv-two.id 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
c=d['concepts'][0]
print(str(c['module'])+'|'+c['home']+'|'+str(c['relations'])+'|'+str(c['shapes'])+'|'+str(c['applications'])+'|'+str(c['shared_demand']))
" 2>/dev/null)
RKR=$(timeout 60 ./zig-out/bin/idol graph /tmp/pv-two.id 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
r=d['refusals'][0]
print(str(r['module'])+'|'+r['reason']+'|'+json.dumps(r['split'],separators=(',',':')))
" 2>/dev/null)
if [ -z "$UNK" ] || [ -z "$RK1" ] || [ -z "$RK2" ] || [ -z "$RKC" ] || [ -z "$RKR" ]; then
  bad "subject-setup" "could not derive ids from graph output"
fi
HASH1=$(sha256sum /tmp/pv-u1.id | cut -d' ' -f1)

# --- Case 1: acquire on subject with unresolved applications -> proposal ---
R=$(preview_req "{\"file\":\"/tmp/pv-u1.id\",\"projection\":\"frontier\",\"edit\":{\"kind\":\"acquire\",\"unknown\":\"$UNK\",\"decision\":\"acquire\"}}")
T=$(printf '%s' "$R" | inner)
V=$(printf '%s' "$T" | python3 -c "
import sys,json
t=json.load(sys.stdin)
p=t.get('proposal',{})
print(t.get('status',''), p.get('action',''), p.get('target',''), p.get('affected_region',{}).get('blocked_applications',[]), 'unknown-present-in-current-frontier' in p.get('checks',[]), p.get('voi_basis',{}).get('recommendation',''), t.get('provenance',{}).get('subject_hash',''))
" 2>/dev/null)
case "$V" in
  "proposal acquire $UNK ['$UNK'] True acquire-via-runtime-guard $HASH1") ok "case1-acquire" ;;
  *) bad "case1-acquire" "wrong: [$V]" ;;
esac

# --- Case 2: acquire naming a nonexistent unknown -> projection-stale ---
R=$(preview_req '{"file":"/tmp/pv-u1.id","projection":"frontier","edit":{"kind":"acquire","unknown":"call|direct|9|99|99","decision":"acquire"}}')
T=$(printf '%s' "$R" | err_inner)
E=$(printf '%s' "$T" | python3 -c "import sys,json; t=json.load(sys.stdin); print(t.get('reason',''), t.get('producer',''), 're-derive the frontier' in t.get('next',''))" 2>/dev/null)
case "$E" in
  "projection-stale preview True") ok "case2-stale" ;;
  *) bad "case2-stale" "wrong: [$E]" ;;
esac

# --- Case 3: acquire on a fully-resolved subject -> projection-stale ---
R=$(preview_req '{"file":"/tmp/pv-simp.id","projection":"frontier","edit":{"kind":"acquire","unknown":"call|direct|1|1|1","decision":"acquire"}}')
T=$(printf '%s' "$R" | err_inner)
E=$(printf '%s' "$T" | python3 -c "import sys,json; t=json.load(sys.stdin); print(t.get('reason',''))" 2>/dev/null)
case "$E" in
  "projection-stale") ok "case3-resolved-stale" ;;
  *) bad "case3-resolved-stale" "wrong: [$E]" ;;
esac

# --- Case 4: decline records a requirement ---
R=$(preview_req "{\"file\":\"/tmp/pv-u1.id\",\"projection\":\"frontier\",\"edit\":{\"kind\":\"acquire\",\"unknown\":\"$UNK\",\"decision\":\"decline\"}}")
T=$(printf '%s' "$R" | inner)
V=$(printf '%s' "$T" | python3 -c "
import sys,json
t=json.load(sys.stdin)
p=t.get('proposal',{})
print(t.get('status',''), p.get('action',''), 'decline-recorded-as-subject-requirement' in p.get('checks',[]), 'requirement' in p)
" 2>/dev/null)
case "$V" in
  "proposal decline True True") ok "case4-decline" ;;
  *) bad "case4-decline" "wrong: [$V]" ;;
esac

# --- Case 5: identify with two identical rowkeys -> direct proposal ---
RJ1=$(printf '%s' "$RK1" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))")
R=$(preview_req "{\"file\":\"/tmp/pv-m1.id\",\"projection\":\"concept\",\"edit\":{\"kind\":\"identify\",\"a\":$RJ1,\"b\":$RJ1}}")
T=$(printf '%s' "$R" | inner)
V=$(printf '%s' "$T" | python3 -c "
import sys,json
t=json.load(sys.stdin)
p=t.get('proposal',{})
print(t.get('status',''), p.get('fact',''), p.get('checks',[]), t.get('provenance',{}).get('faces',''))
" 2>/dev/null)
case "$V" in
  "proposal identity ['row-keys-identical'] agree") ok "case5-identify-same" ;;
  *) bad "case5-identify-same" "wrong: [$V]" ;;
esac

# --- Case 6: identify with two different rows -> ambiguous naming facets ---
RJ2=$(printf '%s' "$RK2" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))")
R=$(preview_req "{\"file\":\"/tmp/pv-m1.id\",\"projection\":\"concept\",\"edit\":{\"kind\":\"identify\",\"a\":$RJ1,\"b\":$RJ2}}")
T=$(printf '%s' "$R" | inner)
V=$(printf '%s' "$T" | python3 -c "
import sys,json
t=json.load(sys.stdin)
print(t.get('status',''), t.get('differing_facets',[]), len(t.get('options',[]))>0)
" 2>/dev/null)
case "$V" in
  "ambiguous ['module', 'home'] True") ok "case6-identify-ambiguous" ;;
  *) bad "case6-identify-ambiguous" "wrong: [$V]" ;;
esac

# --- Case 7: identify with a bogus rowkey -> unknown-concept ---
R=$(preview_req '{"file":"/tmp/pv-m1.id","projection":"concept","edit":{"kind":"identify","a":"0|bogus|x|0|0|0","b":"'"$RK1"'"}}')
T=$(printf '%s' "$R" | err_inner)
E=$(printf '%s' "$T" | python3 -c "import sys,json; t=json.load(sys.stdin); print(t.get('reason',''), t.get('producer',''))" 2>/dev/null)
case "$E" in
  "unknown-concept preview") ok "case7-unknown-concept" ;;
  *) bad "case7-unknown-concept" "wrong: [$E]" ;;
esac

# --- Case 8: identify naming a refusal row -> contradictory, side named ---
RKCJ=$(printf '%s' "$RKC" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))")
RKRJ=$(printf '%s' "$RKR" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))")
R=$(preview_req "{\"file\":\"/tmp/pv-two.id\",\"projection\":\"concept\",\"edit\":{\"kind\":\"identify\",\"a\":$RKRJ,\"b\":$RKCJ}}")
T=$(printf '%s' "$R" | err_inner)
E=$(printf '%s' "$T" | python3 -c "import sys,json; t=json.load(sys.stdin); print(t.get('reason',''), 'side a' in t.get('next',''))" 2>/dev/null)
case "$E" in
  "contradictory True") ok "case8-contradictory" ;;
  *) bad "case8-contradictory" "wrong: [$E]" ;;
esac

# --- Case 9: edit-kind/projection mismatch -> -32602 ---
R=$(preview_req '{"file":"/tmp/pv-m1.id","projection":"concept","edit":{"kind":"acquire","unknown":"call|direct|1|2|4","decision":"acquire"}}')
C=$(printf '%s' "$R" | err_code)
case "$C" in -32602) ok "case9a-mismatch";; *) bad "case9a-mismatch" "code=[$C]";; esac
R=$(preview_req '{"file":"/tmp/pv-u1.id","projection":"frontier","edit":{"kind":"identify","a":"x","b":"y"}}')
C=$(printf '%s' "$R" | err_code)
case "$C" in -32602) ok "case9b-mismatch";; *) bad "case9b-mismatch" "code=[$C]";; esac

# --- Case 10: malformed params -> -32602 ---
R=$(preview_req '{"file":"/tmp/pv-u1.id","projection":"frontier","edit":{"kind":"acquire","unknown":"","decision":"acquire"}}')
C=$(printf '%s' "$R" | err_code)
case "$C" in -32602) ok "case10a-empty-unknown";; *) bad "case10a-empty-unknown" "code=[$C]";; esac
R=$(preview_req '{"file":"/tmp/pv-u1.id","projection":"frontier"}')
C=$(printf '%s' "$R" | err_code)
case "$C" in -32602) ok "case10b-missing-edit";; *) bad "case10b-missing-edit" "code=[$C]";; esac
R=$(preview_req '{"projection":"frontier","edit":{"kind":"acquire","unknown":"call|direct|1|2|4","decision":"acquire"}}')
C=$(printf '%s' "$R" | err_code)
case "$C" in -32602) ok "case10c-missing-file";; *) bad "case10c-missing-file" "code=[$C]";; esac
R=$(preview_req '{"file":"/tmp/pv-u1.id","projection":"frontier","edit":{"kind":"acquire","unknown":"not-a-uid","decision":"acquire"}}')
C=$(printf '%s' "$R" | err_code)
case "$C" in -32602) ok "case10d-malformed-uid";; *) bad "case10d-malformed-uid" "code=[$C]";; esac

# --- Case 11: unreadable subject -> unreadable-subject ---
printf 'secret' > /tmp/pv-secret.id; chmod 000 /tmp/pv-secret.id
R=$(preview_req '{"file":"/tmp/pv-secret.id","projection":"frontier","edit":{"kind":"acquire","unknown":"call|direct|1|2|4","decision":"acquire"}}')
T=$(printf '%s' "$R" | err_inner)
E=$(printf '%s' "$T" | python3 -c "import sys,json; t=json.load(sys.stdin); print(t.get('reason',''), t.get('producer',''))" 2>/dev/null)
chmod 644 /tmp/pv-secret.id; rm -f /tmp/pv-secret.id
case "$E" in
  "unreadable-subject caller") ok "case11-unreadable" ;;
  *) bad "case11-unreadable" "wrong: [$E]" ;;
esac

# --- Case 12: failing world binary -> derivation-failed naming the binary ---
FAILBIN=/tmp/pv-fail-idol; printf '#!/bin/sh\nexit 3\n' > "$FAILBIN"; chmod +x "$FAILBIN"
R=$(printf '%s\n' '{"jsonrpc":"2.0","id":11,"method":"tools/call","params":{"name":"preview","arguments":{"file":"/tmp/pv-u1.id","projection":"frontier","edit":{"kind":"acquire","unknown":"call|direct|1|2|4","decision":"acquire"}}}}' \
  | IDOL_WORLD_BIN="$FAILBIN" timeout 120 ./zig-out/bin/idol run --backend=native tools/mcp/preview.id 2>/dev/null | tail -1)
T=$(printf '%s' "$R" | err_inner)
E=$(printf '%s' "$T" | python3 -c "import sys,json; t=json.load(sys.stdin); print(t.get('reason',''), 'pv-fail-idol' in t.get('next',''))" 2>/dev/null)
rm -f "$FAILBIN"
case "$E" in
  "derivation-failed True") ok "case12-derivation-failed" ;;
  *) bad "case12-derivation-failed" "wrong: [$E]" ;;
esac

rm -f /tmp/pv-u1.id /tmp/pv-simp.id /tmp/pv-m1.id /tmp/pv-m2.id /tmp/pv-two.id

printf 'pass=%d fail=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
