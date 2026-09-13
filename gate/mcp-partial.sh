#!/bin/sh
# gate/mcp-partial.sh -- adversarial tests for the MCP partial tool.
# Pipes JSON-RPC directly into `idol run --backend=native tools/mcp/partial.id`.
# All test binaries run under timeout. Zero rows examined must fail.
set -u
cd "$(dirname "$0")/.."
PASS=0
FAIL=0

ok() { PASS=$((PASS+1)); printf 'ok %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL %s: %s\n' "$1" "$2"; }

partial_req() {
  printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":31,\"method\":\"tools/call\",\"params\":{\"name\":\"partial\",\"arguments\":$1}}" \
    | timeout 120 ./zig-out/bin/idol run --backend=native tools/mcp/partial.id 2>/dev/null | tail -1
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
printf 'apply: i64 = (f: i64, x: i64)\n  f(x)\ng: i64 = (h: i64, y: i64)\n  h(y)\nk: i64 = (p: i64, q: i64)\n  p(q)\nmain: i64 = ()\n  0\nmain()\n' > /tmp/pa-3u.id
printf 'main: i64 = ()\n  1\nmain()\n' > /tmp/pa-simp.id
printf 'q: i64 = (z: i64)\n  z\n' > /tmp/pa-m2.id
printf 'apply: i64 = (f: i64, x: i64)\n  f(x)\nmain: i64 = ()\n  m2.q(1)\nmain()\n' > /tmp/pa-e1.id
printf 'apply: i64 = (f: i64, x: i64)\n  f(x)\nmain: i64 = ()\n  apply(1, 2)\nmain()\n' > /tmp/pa-rf.id
UIDS=$(timeout 60 ./zig-out/bin/idol graph /tmp/pa-3u.id 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
nodes={n['id']:n for n in d['nodes']}
out=[]
for u in d['unresolved_applications']:
    n=nodes[u]
    out.append('call|'+n['callee_kind']+'|'+str(n['arg_count'])+'|'+str(n['line'])+'|'+str(n['col']))
print(' '.join(out))
" 2>/dev/null)
set -- $UIDS
U1=${1:-}; U2=${2:-}; U3=${3:-}
RK_CLOSED=$(timeout 60 ./zig-out/bin/idol graph /tmp/pa-e1.id 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
c=[x for x in d['concepts'] if x['home']=='private.tmp.m2'][0]
print(str(c['module'])+'|'+c['home']+'|'+str(c['relations'])+'|'+str(c['shapes'])+'|'+str(c['applications'])+'|'+str(c['shared_demand']))
" 2>/dev/null)
RK_OPEN=$(timeout 60 ./zig-out/bin/idol graph /tmp/pa-e1.id 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
c=[x for x in d['concepts'] if x['home']=='private.tmp.pa-e1'][0]
print(str(c['module'])+'|'+c['home']+'|'+str(c['relations'])+'|'+str(c['shapes'])+'|'+str(c['applications'])+'|'+str(c['shared_demand']))
" 2>/dev/null)
U4=$(timeout 60 ./zig-out/bin/idol graph /tmp/pa-e1.id 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
nodes={n['id']:n for n in d['nodes']}
u=d['unresolved_applications'][0]; n=nodes[u]
print('call|'+n['callee_kind']+'|'+str(n['arg_count'])+'|'+str(n['line'])+'|'+str(n['col']))
" 2>/dev/null)
RK_REF=$(timeout 60 ./zig-out/bin/idol graph /tmp/pa-rf.id 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
r=d['refusals'][0]
print(str(r['module'])+'|'+r['reason']+'|'+json.dumps(r['split'],separators=(',',':')))
" 2>/dev/null)
if [ -z "$U1" ] || [ -z "$U2" ] || [ -z "$U3" ] || [ -z "$RK_CLOSED" ] || [ -z "$RK_OPEN" ] || [ -z "$U4" ] || [ -z "$RK_REF" ]; then
  bad "subject-setup" "could not derive ids from graph output"
fi
HASH3=$(sha256sum /tmp/pa-3u.id | cut -d' ' -f1)
BINHASH=$(sha256sum ./zig-out/bin/idol | cut -d' ' -f1)

# --- Case 1 (a): budget-exhausted search retains subresults + precise obligation ---
R=$(partial_req "{\"file\":\"/tmp/pa-3u.id\",\"action\":\"retain\",\"owner\":\"gate\",\"budget\":1}")
T=$(printf '%s' "$R" | inner)
V=$(printf '%s' "$T" | python3 -c "
import sys,json,re
t=json.load(sys.stdin)
v=[x['id'] for x in t['verified']]
o=[x['id'] for x in t['outstanding']]
aid=t.get('attempt_id','')
print(t.get('status',''), v, o, len(t.get('not_claimed',[])),
  bool(re.fullmatch(r'[0-9a-f]{16}', aid)),
  t.get('provenance',{}).get('subject_hash','') if 'provenance' in t else t.get('subject_hash',''),
  all(x.get('producer')=='partial' and 'voi_cents' in x.get('evidence','') for x in t['verified']))
" 2>/dev/null)
case "$V" in
  "partial ['$U1'] ['$U2', '$U3'] 4 True $HASH3 True") ok "case1-budget-exhausted" ;;
  *) bad "case1-budget-exhausted" "wrong: [$V]" ;;
esac

# --- Case 2: budget zero -> nothing verified, everything outstanding ---
R=$(partial_req '{"file":"/tmp/pa-3u.id","action":"retain","owner":"gate","budget":0}')
T=$(printf '%s' "$R" | inner)
V=$(printf '%s' "$T" | python3 -c "
import sys,json
t=json.load(sys.stdin)
print(t.get('status',''), len(t.get('verified',[])), len(t.get('outstanding',[])))
" 2>/dev/null)
case "$V" in
  "partial 0 3") ok "case2-budget-zero" ;;
  *) bad "case2-budget-zero" "wrong: [$V]" ;;
esac

# --- Case 3: budget covers all -> complete, but not_claimed still present ---
R=$(partial_req '{"file":"/tmp/pa-3u.id","action":"retain","owner":"gate","budget":9}')
T=$(printf '%s' "$R" | inner)
V=$(printf '%s' "$T" | python3 -c "
import sys,json
t=json.load(sys.stdin)
print(t.get('status',''), len(t.get('verified',[])), len(t.get('outstanding',[])), 'concept-verdict' in t.get('not_claimed',[]))
" 2>/dev/null)
case "$V" in
  "complete 3 0 True") ok "case3-budget-covers-all" ;;
  *) bad "case3-budget-covers-all" "wrong: [$V]" ;;
esac

# --- Case 4: fully resolved subject -> complete with empty verified/outstanding ---
R=$(partial_req '{"file":"/tmp/pa-simp.id","action":"retain","owner":"gate","budget":5}')
T=$(printf '%s' "$R" | inner)
V=$(printf '%s' "$T" | python3 -c "
import sys,json
t=json.load(sys.stdin)
print(t.get('status',''), len(t.get('verified',[])), len(t.get('outstanding',[])), len(t.get('blocking',[])))
" 2>/dev/null)
case "$V" in
  "complete 0 0 0") ok "case4-resolved-complete" ;;
  *) bad "case4-resolved-complete" "wrong: [$V]" ;;
esac

# --- Case 5: invalid params -> -32602 ---
R=$(partial_req '{"file":"/tmp/pa-3u.id","action":"retain","budget":1}')
C=$(printf '%s' "$R" | err_code)
case "$C" in -32602) ok "case5a-missing-owner";; *) bad "case5a-missing-owner" "code=[$C]";; esac
R=$(partial_req '{"file":"/tmp/pa-3u.id","action":"retain","owner":"gate"}')
C=$(printf '%s' "$R" | err_code)
case "$C" in -32602) ok "case5b-missing-budget";; *) bad "case5b-missing-budget" "code=[$C]";; esac
R=$(partial_req '{"file":"/tmp/pa-3u.id","action":"retain","owner":"gate","budget":"-1"}')
C=$(printf '%s' "$R" | err_code)
case "$C" in -32602) ok "case5c-negative-budget";; *) bad "case5c-negative-budget" "code=[$C]";; esac
R=$(partial_req '{"file":"/tmp/pa-3u.id","action":"frobnicate"}')
C=$(printf '%s' "$R" | err_code)
case "$C" in -32602) ok "case5d-unknown-action";; *) bad "case5d-unknown-action" "code=[$C]";; esac
R=$(partial_req '{"action":"retain","owner":"gate","budget":1}')
C=$(printf '%s' "$R" | err_code)
case "$C" in -32602) ok "case5e-missing-file";; *) bad "case5e-missing-file" "code=[$C]";; esac

# --- Case 6: unreadable subject -> unreadable-subject ---
printf 'secret' > /tmp/pa-secret.id; chmod 000 /tmp/pa-secret.id
R=$(partial_req '{"file":"/tmp/pa-secret.id","action":"retain","owner":"gate","budget":1}')
T=$(printf '%s' "$R" | err_inner)
E=$(printf '%s' "$T" | python3 -c "import sys,json; t=json.load(sys.stdin); print(t.get('reason',''), t.get('producer',''))" 2>/dev/null)
chmod 644 /tmp/pa-secret.id; rm -f /tmp/pa-secret.id
case "$E" in
  "unreadable-subject caller") ok "case6-unreadable" ;;
  *) bad "case6-unreadable" "wrong: [$E]" ;;
esac

# --- Case 7: failing world binary -> derivation-unavailable / derivation-failed ---
FAILBIN=/tmp/pa-fail-idol; printf '#!/bin/sh\nexit 3\n' > "$FAILBIN"; chmod +x "$FAILBIN"
R=$(IDOL_WORLD_BIN="$FAILBIN" partial_req '{"file":"/tmp/pa-3u.id","action":"retain","owner":"gate","budget":1}')
T=$(printf '%s' "$R" | err_inner)
E=$(printf '%s' "$T" | python3 -c "import sys,json; t=json.load(sys.stdin); print(t.get('reason',''), '$FAILBIN' in t.get('next',''))" 2>/dev/null)
case "$E" in
  "derivation-failed True") ok "case7a-graph-fails" ;;
  *) bad "case7a-graph-fails" "wrong: [$E]" ;;
esac
rm -f "$FAILBIN"
R=$(IDOL_WORLD_BIN=/tmp/does-not-exist-idol partial_req '{"file":"/tmp/pa-3u.id","action":"retain","owner":"gate","budget":1}')
T=$(printf '%s' "$R" | err_inner)
E=$(printf '%s' "$T" | python3 -c "import sys,json; t=json.load(sys.stdin); print(t.get('reason',''))" 2>/dev/null)
case "$E" in
  "derivation-unavailable") ok "case7b-bin-missing" ;;
  *) bad "case7b-bin-missing" "wrong: [$E]" ;;
esac

# --- Case 8 (b): unavailable capability keeps the verified artifact, demand unresolved ---
R=$(partial_req '{"file":"/tmp/pa-3u.id","action":"deploy","capability":"acquire-unknown"}')
T=$(printf '%s' "$R" | inner)
V=$(printf '%s' "$T" | python3 -c "
import sys,json
t=json.load(sys.stdin)
d=t.get('demand',{})
ev=t['verified'][0]['evidence']
print(t.get('status',''), d.get('status',''), d.get('evidence',''),
  'concepts=1' in ev and 'unresolved=3' in ev and 'blocking=3' in ev,
  len(d.get('next',''))>0, 'deployment-effect' in t.get('not_claimed',[]))
" 2>/dev/null)
case "$V" in
  "partial unresolved capability-unavailable True True True") ok "case8-deploy-unavailable" ;;
  *) bad "case8-deploy-unavailable" "wrong: [$V]" ;;
esac

# --- Case 9: unknown capability -> unknown-capability refusal ---
R=$(partial_req '{"file":"/tmp/pa-3u.id","action":"deploy","capability":"teleport"}')
T=$(printf '%s' "$R" | err_inner)
E=$(printf '%s' "$T" | python3 -c "import sys,json; t=json.load(sys.stdin); print(t.get('reason',''), t.get('producer',''))" 2>/dev/null)
case "$E" in
  "unknown-capability partial") ok "case9-unknown-capability" ;;
  *) bad "case9-unknown-capability" "wrong: [$E]" ;;
esac

# --- Case 10: available capability still never performs the effect ---
R=$(partial_req '{"file":"/tmp/pa-3u.id","action":"deploy","capability":"derive-frontier"}')
T=$(printf '%s' "$R" | inner)
V=$(printf '%s' "$T" | python3 -c "
import sys,json
t=json.load(sys.stdin)
print(t.get('status',''), t.get('demand',{}).get('evidence',''), len(t.get('verified',[])))
" 2>/dev/null)
case "$V" in
  "partial effect-not-performed 1") ok "case10-deploy-available" ;;
  *) bad "case10-deploy-available" "wrong: [$V]" ;;
esac

# --- Case 11 (c): closed region evaluates while dependents stay partial ---
RKCJ=$(printf '%s' "$RK_CLOSED" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))")
R=$(partial_req "{\"file\":\"/tmp/pa-e1.id\",\"action\":\"evaluate\",\"region\":$RKCJ}")
T=$(printf '%s' "$R" | inner)
V=$(printf '%s' "$T" | python3 -c "
import sys,json
t=json.load(sys.stdin)
ev=t.get('evaluated',{})
deps=t.get('dependents',[])
ids=[d['id'] for d in deps]
print(t.get('status',''), ev.get('region_verdict',''), ev.get('faces',''),
  all(d.get('status')=='partial' for d in deps),
  any(i.startswith('0|private.tmp.pa-e1') for i in ids),
  '$U4' in ids)
" 2>/dev/null)
case "$V" in
  "partial held agree True True True") ok "case11-evaluate-closed" ;;
  *) bad "case11-evaluate-closed" "wrong: [$V]" ;;
esac

# --- Case 12: open region -> region-not-closed naming the unknown ---
RKOJ=$(printf '%s' "$RK_OPEN" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))")
R=$(partial_req "{\"file\":\"/tmp/pa-e1.id\",\"action\":\"evaluate\",\"region\":$RKOJ}")
T=$(printf '%s' "$R" | err_inner)
E=$(printf '%s' "$T" | python3 -c "import sys,json; t=json.load(sys.stdin); print(t.get('reason',''), '$U4' in t.get('next',''))" 2>/dev/null)
case "$E" in
  "region-not-closed True") ok "case12-evaluate-open" ;;
  *) bad "case12-evaluate-open" "wrong: [$E]" ;;
esac

# --- Case 13: bogus region -> unknown-concept; refusal rowkey -> region-refused ---
R=$(partial_req '{"file":"/tmp/pa-e1.id","action":"evaluate","region":"0|bogus|x|0|0|0"}')
T=$(printf '%s' "$R" | err_inner)
E=$(printf '%s' "$T" | python3 -c "import sys,json; t=json.load(sys.stdin); print(t.get('reason',''))" 2>/dev/null)
case "$E" in
  "unknown-concept") ok "case13a-bogus-region" ;;
  *) bad "case13a-bogus-region" "wrong: [$E]" ;;
esac
RKRJ=$(printf '%s' "$RK_REF" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))")
R=$(partial_req "{\"file\":\"/tmp/pa-rf.id\",\"action\":\"evaluate\",\"region\":$RKRJ}")
T=$(printf '%s' "$R" | err_inner)
E=$(printf '%s' "$T" | python3 -c "import sys,json; t=json.load(sys.stdin); print(t.get('reason',''), t.get('producer',''))" 2>/dev/null)
case "$E" in
  "region-refused partial") ok "case13b-refusal-region" ;;
  *) bad "case13b-refusal-region" "wrong: [$E]" ;;
esac

# --- Case 14 (d): admit is always a refusal naming the outstanding obligation ---
CTX=$(partial_req '{"file":"/tmp/pa-3u.id","action":"retain","owner":"gate","budget":1}' | inner)
CTXJ=$(printf '%s' "$CTX" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null)
R=$(partial_req "{\"file\":\"/tmp/pa-3u.id\",\"action\":\"admit\",\"context\":$CTXJ}")
T=$(printf '%s' "$R" | err_inner)
E=$(printf '%s' "$T" | python3 -c "import sys,json; t=json.load(sys.stdin); print(t.get('reason',''), '$U2' in t.get('next',''), t.get('not-performed',''))" 2>/dev/null)
case "$E" in
  "admission-requires-completion True ['admit']") ok "case14a-admit-refused" ;;
  *) bad "case14a-admit-refused" "wrong: [$E]" ;;
esac
R=$(partial_req '{"file":"/tmp/pa-3u.id","action":"complete"}')
T=$(printf '%s' "$R" | err_inner)
E=$(printf '%s' "$T" | python3 -c "import sys,json; t=json.load(sys.stdin); print(t.get('reason',''))" 2>/dev/null)
case "$E" in
  "admission-requires-completion") ok "case14b-complete-refused" ;;
  *) bad "case14b-complete-refused" "wrong: [$E]" ;;
esac

# --- Case 15 (e): defaulting an unknown is a refusal ---
R=$(partial_req "{\"file\":\"/tmp/pa-3u.id\",\"action\":\"default\",\"unknown\":\"$U1\",\"value\":\"0\"}")
T=$(printf '%s' "$R" | err_inner)
E=$(printf '%s' "$T" | python3 -c "import sys,json; t=json.load(sys.stdin); print(t.get('reason',''), '$U1' in t.get('next',''), t.get('producer',''))" 2>/dev/null)
case "$E" in
  "unknowns-are-not-defaulted True partial") ok "case15-default-refused" ;;
  *) bad "case15-default-refused" "wrong: [$E]" ;;
esac

# --- Case 16: execute of an unresolved application is a refusal; stale uid refused too ---
R=$(partial_req "{\"file\":\"/tmp/pa-3u.id\",\"action\":\"execute\",\"unknown\":\"$U1\"}")
T=$(printf '%s' "$R" | err_inner)
E=$(printf '%s' "$T" | python3 -c "import sys,json; t=json.load(sys.stdin); print(t.get('reason',''), t.get('not-performed',''))" 2>/dev/null)
case "$E" in
  "unresolved-application ['execute']") ok "case16a-execute-refused" ;;
  *) bad "case16a-execute-refused" "wrong: [$E]" ;;
esac
R=$(partial_req '{"file":"/tmp/pa-3u.id","action":"execute","unknown":"call|direct|9|99|99"}')
T=$(printf '%s' "$R" | err_inner)
E=$(printf '%s' "$T" | python3 -c "import sys,json; t=json.load(sys.stdin); print(t.get('reason',''))" 2>/dev/null)
case "$E" in
  "projection-stale") ok "case16b-execute-stale" ;;
  *) bad "case16b-execute-stale" "wrong: [$E]" ;;
esac

# --- Case 17 (f): load continues in a fresh invocation; retained data returned verbatim ---
R=$(partial_req "{\"file\":\"/tmp/pa-3u.id\",\"action\":\"load\",\"context\":$CTXJ}")
T=$(printf '%s' "$R" | inner)
V=$(printf '%s' "$T" | python3 -c "
import sys,json
t=json.load(sys.stdin)
print(t.get('status',''), t.get('next',''))
print(json.dumps(t.get('verified',[]), sort_keys=True))
print(json.dumps(t.get('outstanding',[]), sort_keys=True))
print(json.dumps(t.get('not_claimed',[]), sort_keys=True))
" 2>/dev/null)
printf '%s' "$CTX" > /tmp/pa-ctx-check.json
LV=$(printf '%s' "$V" | sed -n '1p'); LVV=$(printf '%s' "$V" | sed -n '2p'); LVO=$(printf '%s' "$V" | sed -n '3p'); LVN=$(printf '%s' "$V" | sed -n '4p')
CVV=$(python3 -c "import json; print(json.dumps(json.load(open('/tmp/pa-ctx-check.json'))['verified'], sort_keys=True))" 2>/dev/null)
CVO=$(python3 -c "import json; print(json.dumps(json.load(open('/tmp/pa-ctx-check.json'))['outstanding'], sort_keys=True))" 2>/dev/null)
CVN=$(python3 -c "import json; print(json.dumps(json.load(open('/tmp/pa-ctx-check.json'))['not_claimed'], sort_keys=True))" 2>/dev/null)
if [ "$LV" = "continue resume at $U2" ] && [ "$LVV" = "$CVV" ] && [ "$LVO" = "$CVO" ] && [ "$LVN" = "$CVN" ]; then
  ok "case17-load-continues"
else
  bad "case17-load-continues" "wrong: [$LV]"
fi

# --- Case 18 (f): load performs no re-derivation (dead binary still loads) ---
DEADBIN=/tmp/pa-dead-idol; printf '#!/bin/sh\nexit 3\n' > "$DEADBIN"; chmod +x "$DEADBIN"
FALSEHASH=$(sha256sum "$DEADBIN" | cut -d' ' -f1)
CTX2=$(printf '%s' "$CTX" | python3 -c "
import sys,json
t=json.load(sys.stdin); t['world']['binhash']='$FALSEHASH'; print(json.dumps(t))
" 2>/dev/null)
CTX2J=$(printf '%s' "$CTX2" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null)
R=$(IDOL_WORLD_BIN="$DEADBIN" partial_req "{\"file\":\"/tmp/pa-3u.id\",\"action\":\"load\",\"context\":$CTX2J}")
rm -f "$DEADBIN"
T=$(printf '%s' "$R" | inner)
V=$(printf '%s' "$T" | python3 -c "
import sys,json
t=json.load(sys.stdin)
print(t.get('status',''), t.get('attempt_id',''))
" 2>/dev/null)
AIDX=$(printf '%s' "$CTX" | python3 -c "import sys,json; print(json.load(sys.stdin)['attempt_id'])" 2>/dev/null)
case "$V" in
  "continue $AIDX") ok "case18-load-no-rederivation" ;;
  *) bad "case18-load-no-rederivation" "wrong: [$V]" ;;
esac

# --- Case 19 (g): tampered subject hash -> context-stale refusal ---
CTX3=$(printf '%s' "$CTX" | python3 -c "
import sys,json
t=json.load(sys.stdin); t['subject_hash']='0'*64; print(json.dumps(t))
" 2>/dev/null)
CTX3J=$(printf '%s' "$CTX3" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null)
R=$(partial_req "{\"file\":\"/tmp/pa-3u.id\",\"action\":\"load\",\"context\":$CTX3J}")
T=$(printf '%s' "$R" | err_inner)
E=$(printf '%s' "$T" | python3 -c "import sys,json; t=json.load(sys.stdin); print(t.get('reason',''), t.get('producer',''), t.get('not-performed',''))" 2>/dev/null)
case "$E" in
  "context-stale partial ['load']") ok "case19-tampered-hash" ;;
  *) bad "case19-tampered-hash" "wrong: [$E]" ;;
esac

# --- Case 20: malformed / incomplete context -> context-corrupt ---
R=$(partial_req '{"file":"/tmp/pa-3u.id","action":"load","context":"not json at all"}')
T=$(printf '%s' "$R" | err_inner)
E=$(printf '%s' "$T" | python3 -c "import sys,json; t=json.load(sys.stdin); print(t.get('reason',''))" 2>/dev/null)
case "$E" in
  "context-corrupt") ok "case20a-malformed-context" ;;
  *) bad "case20a-malformed-context" "wrong: [$E]" ;;
esac
CTX4=$(printf '%s' "$CTX" | python3 -c "
import sys,json
t=json.load(sys.stdin); del t['outstanding']; print(json.dumps(t))
" 2>/dev/null)
CTX4J=$(printf '%s' "$CTX4" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null)
R=$(partial_req "{\"file\":\"/tmp/pa-3u.id\",\"action\":\"load\",\"context\":$CTX4J}")
T=$(printf '%s' "$R" | err_inner)
E=$(printf '%s' "$T" | python3 -c "import sys,json; t=json.load(sys.stdin); print(t.get('reason',''), 'outstanding' in t.get('next',''))" 2>/dev/null)
case "$E" in
  "context-corrupt True") ok "case20b-incomplete-context" ;;
  *) bad "case20b-incomplete-context" "wrong: [$E]" ;;
esac

# --- Case 21 (h): unrelated world change (revision advanced, binary same) does not invalidate ---
CTX5=$(printf '%s' "$CTX" | python3 -c "
import sys,json
t=json.load(sys.stdin); t['world']['revision']='deadbeef'; print(json.dumps(t))
" 2>/dev/null)
CTX5J=$(printf '%s' "$CTX5" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null)
R=$(partial_req "{\"file\":\"/tmp/pa-3u.id\",\"action\":\"load\",\"context\":$CTX5J}")
T=$(printf '%s' "$R" | inner)
V=$(printf '%s' "$T" | python3 -c "
import sys,json
t=json.load(sys.stdin)
rn=t.get('provenance',{}).get('revision_note')
print(t.get('status',''), rn is not None and 'retained' in rn, len(t.get('verified',[])))
" 2>/dev/null)
case "$V" in
  "continue True 1") ok "case21-revision-advanced" ;;
  *) bad "case21-revision-advanced" "wrong: [$V]" ;;
esac

# --- Case 22: changed world binary -> world-moved refusal ---
CTX6=$(printf '%s' "$CTX" | python3 -c "
import sys,json
t=json.load(sys.stdin); t['world']['binhash']='f'*64; print(json.dumps(t))
" 2>/dev/null)
CTX6J=$(printf '%s' "$CTX6" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null)
R=$(partial_req "{\"file\":\"/tmp/pa-3u.id\",\"action\":\"load\",\"context\":$CTX6J}")
T=$(printf '%s' "$R" | err_inner)
E=$(printf '%s' "$T" | python3 -c "import sys,json; t=json.load(sys.stdin); print(t.get('reason',''), t.get('producer',''))" 2>/dev/null)
case "$E" in
  "world-moved partial") ok "case22-world-moved" ;;
  *) bad "case22-world-moved" "wrong: [$E]" ;;
esac

# --- Case 23: native.id dispatch lists partial and routes tools/call ---
R=$(printf '{"jsonrpc":"2.0","id":40,"method":"tools/list"}\n' | timeout 120 ./zig-out/bin/idol run --backend=native tools/mcp/native.id 2>/dev/null | tail -1)
case "$R" in
  *'"name":"partial"'*) ok "case23a-dispatch-listed" ;;
  *) bad "case23a-dispatch-listed" "partial not in tools/list" ;;
esac
R=$(printf '{"jsonrpc":"2.0","id":41,"method":"tools/call","params":{"name":"partial","arguments":{"file":"/tmp/pa-3u.id","action":"retain","owner":"dispatch","budget":3}}}\n' | timeout 180 ./zig-out/bin/idol run --backend=native tools/mcp/native.id 2>/dev/null | tail -1)
T=$(printf '%s' "$R" | inner)
V=$(printf '%s' "$T" | python3 -c "
import sys,json
t=json.load(sys.stdin)
print(t.get('status',''), len(t.get('verified',[])), len(t.get('outstanding',[])))
" 2>/dev/null)
case "$V" in
  "complete 3 0") ok "case23b-dispatch-call" ;;
  *) bad "case23b-dispatch-call" "wrong: [$V]" ;;
esac

rm -f /tmp/pa-3u.id /tmp/pa-simp.id /tmp/pa-m2.id /tmp/pa-e1.id /tmp/pa-rf.id /tmp/pa-ctx-check.json
printf 'pass=%d fail=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && [ "$PASS" -gt 0 ]
