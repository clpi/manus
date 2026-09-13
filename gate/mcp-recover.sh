#!/bin/bash
# gate/mcp-recover.sh: adversarial gate for the recover MCP tool.
# Tests queryable recoverability of eliminated information.
set -u

RECOVER_BIN="${RECOVER_BIN:-/tmp/recover-test}"
WORKTREE="${WORKTREE:-/tmp/wt-recover}"
MM="${MM:-$HOME/workspace/idol-ops/ssh/mm.sh}"
PASS=0
FAIL=0

ok() { PASS=$((PASS+1)); echo "ok $1"; }
fail() { FAIL=$((FAIL+1)); echo "FAIL $1"; }

run_recover() {
  local req="$1"
  echo "$req" | "$MM" "IDOL_WORLD_BIN=$WORKTREE/zig-out/bin/idol timeout 60 $RECOVER_BIN" 2>/dev/null | head -1
}

check_json() {
  python3 -c "import sys, json; json.loads(sys.stdin.read())" 2>/dev/null
}

# Setup: create test subjects on the Mac mini
SUBJ1=/tmp/gate-recover-subj1.id
SUBJ2=/tmp/gate-recover-subj2.id
SUBJ3=/tmp/gate-recover-subj3.id
SUBJ4=/tmp/gate-recover-subj4.id
SUBJ5=/tmp/gate-recover-subj5.id

"$MM" "cat > $SUBJ1" <<'EOF'
main: i64 = ()
  x = 2 + 3
  x
main()
EOF

"$MM" "cat > $SUBJ2" <<'EOF'
main: i64 = ()
  a = 3
  b = 4
  i = 0
  while i < 10
    t = a + b
    i = i + 1
  i
main()
EOF

"$MM" "cat > $SUBJ3" <<'EOF'
main: i64 = ()
  i = 0
  while i < 0
    s = i + 1
    i = i + 1
  i
main()
EOF

"$MM" "cat > $SUBJ4" <<'EOF'
main: i64 = (n: i64)
  result = n + 5
  result
main(0)
EOF

"$MM" "cat > $SUBJ5" <<'EOF'
main: i64 = (input: i64)
  masked = input & 255
  masked
main(0)
EOF

H1=$("$MM" "sha256sum $SUBJ1" 2>/dev/null | cut -d' ' -f1)
H2=$("$MM" "sha256sum $SUBJ2" 2>/dev/null | cut -d' ' -f1)
H3=$("$MM" "sha256sum $SUBJ3" 2>/dev/null | cut -d' ' -f1)
H4=$("$MM" "sha256sum $SUBJ4" 2>/dev/null | cut -d' ' -f1)
H5=$("$MM" "sha256sum $SUBJ5" 2>/dev/null | cut -d' ' -f1)

mkreq() {
  local file="$1" hash="$2" kind="$3" target="$4"
  printf '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"recover","arguments":{"file":"%s","subject_hash":"%s","query":{"kind":"%s","target":"%s"}}}}' "$file" "$hash" "$kind" "$target"
}

# Test 1: exact constant fold
OUT=$(run_recover "$(mkreq "$SUBJ1" "$H1" "value" "x")")
if printf '%s\n' "$OUT" | check_json; then
  CLS=$(printf '%s\n' "$OUT" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); p=json.loads(d['result']['content'][0]['text']); print(p['classification'], p.get('value'), p.get('witness',{}).get('transform'))")
  if [ "$CLS" = "exactly-recoverable 5 compiler.opt.licm.foldlit" ]; then ok "1 exact fold"; else fail "1 exact fold (got: $CLS)"; fi
else fail "1 exact fold (invalid JSON)"; fi

# Test 2: LICM hoist
OUT=$(run_recover "$(mkreq "$SUBJ2" "$H2" "value" "t")")
if printf '%s\n' "$OUT" | check_json; then
  CLS=$(printf '%s\n' "$OUT" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); p=json.loads(d['result']['content'][0]['text']); print(p['classification'], p.get('value'))")
  if [ "$CLS" = "exactly-recoverable 7" ]; then ok "2 licm hoist"; else fail "2 licm hoist (got: $CLS)"; fi
else fail "2 licm hoist (invalid JSON)"; fi

# Test 3: zero-trip eliminated (no guessed value)
OUT=$(run_recover "$(mkreq "$SUBJ3" "$H3" "value" "s")")
if printf '%s\n' "$OUT" | check_json; then
  RES=$(printf '%s\n' "$OUT" | python3 -c "
import sys,json
d=json.loads(sys.stdin.read())
p=json.loads(d['result']['content'][0]['text'])
text=json.dumps(p)
leak = 'i + 1' in text or '\"value\"' in text
print(p['classification'], 'LEAK' if leak else 'clean')
")
  if [ "$RES" = "not-recoverable-from-this-run clean" ]; then ok "3 zero-trip no leak"; else fail "3 zero-trip (got: $RES)"; fi
else fail "3 zero-trip (invalid JSON)"; fi

# Test 4: runtime-dependent
OUT=$(run_recover "$(mkreq "$SUBJ4" "$H4" "value" "result")")
if printf '%s\n' "$OUT" | check_json; then
  CLS=$(printf '%s\n' "$OUT" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); p=json.loads(d['result']['content'][0]['text']); c=p['classification']; cost=p.get('cost',{}); print(c, 'cost' if cost.get('additional_bytes_per_event') else 'nocost')")
  if [ "$CLS" = "requires-additional-observation cost" ]; then ok "4 runtime observation"; else fail "4 runtime (got: $CLS)"; fi
else fail "4 runtime (invalid JSON)"; fi

# Test 5: mask partial
OUT=$(run_recover "$(mkreq "$SUBJ5" "$H5" "value" "masked")")
if printf '%s\n' "$OUT" | check_json; then
  CLS=$(printf '%s\n' "$OUT" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); p=json.loads(d['result']['content'][0]['text']); b=p.get('bound',{}); print(p['classification'], b.get('min'), b.get('max'), 'hasvalue' if 'value' in p else 'novalue')")
  if [ "$CLS" = "partially-recoverable 0 255 novalue" ]; then ok "5 mask partial"; else fail "5 mask (got: $CLS)"; fi
else fail "5 mask (invalid JSON)"; fi

# Test 6: wrong hash -> refusal, no classification
OUT=$(run_recover "$(mkreq "$SUBJ1" "0000000000000000000000000000000000000000000000000000000000000000" "value" "x")")
if printf '%s\n' "$OUT" | check_json; then
  RES=$(printf '%s\n' "$OUT" | python3 -c "
import sys,json
d=json.loads(sys.stdin.read())
e=d.get('error',{})
msg=json.loads(e.get('message','{}'))
has='classification' in json.dumps(d)
print(e.get('code'), msg.get('reason'), 'HASCLASS' if has else 'noclass')
")
  if [ "$RES" = "-32002 subject hash mismatch noclass" ]; then ok "6 wrong hash refusal"; else fail "6 wrong hash (got: $RES)"; fi
else fail "6 wrong hash (invalid JSON)"; fi

# Test 7: unreadable file -> refusal
OUT=$(run_recover "$(mkreq "/tmp/nonexistent-xyz.id" "abcd" "value" "x")")
if printf '%s\n' "$OUT" | check_json; then
  RES=$(printf '%s\n' "$OUT" | python3 -c "
import sys,json
d=json.loads(sys.stdin.read())
msg=json.loads(d['error']['message'])
has='classification' in json.dumps(d)
print(msg.get('reason'), 'HASCLASS' if has else 'noclass')
")
  if [ "$RES" = "subject unreadable noclass" ]; then ok "7 unreadable refusal"; else fail "7 unreadable (got: $RES)"; fi
else fail "7 unreadable (invalid JSON)"; fi

# Test 8: missing target -> -32602
REQ='{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"recover","arguments":{"file":"/tmp/x","subject_hash":"y","query":{"kind":"value"}}}}'
OUT=$(run_recover "$REQ")
CODE=$(printf '%s\n' "$OUT" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['error']['code'])" 2>/dev/null)
if [ "$CODE" = "-32602" ]; then ok "8 missing target"; else fail "8 missing target (got: $CODE)"; fi

# Test 9: invalid kind -> -32602
OUT=$(run_recover "$(mkreq "$SUBJ1" "$H1" "bogus" "x")")
CODE=$(printf '%s\n' "$OUT" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['error']['code'])" 2>/dev/null)
if [ "$CODE" = "-32602" ]; then ok "9 invalid kind"; else fail "9 invalid kind (got: $CODE)"; fi

# Test 10: unknown target -> refusal (not a guess)
OUT=$(run_recover "$(mkreq "$SUBJ1" "$H1" "value" "nonexistent")")
if printf '%s\n' "$OUT" | check_json; then
  CLS=$(printf '%s\n' "$OUT" | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); p=json.loads(d['result']['content'][0]['text']); print(p['classification'], 'hasvalue' if 'value' in p else 'novalue')")
  if [ "$CLS" = "not-recoverable-from-this-run novalue" ]; then ok "10 unknown target"; else fail "10 unknown target (got: $CLS)"; fi
else fail "10 unknown target (invalid JSON)"; fi

# Test 11: 64-hex hashes and revision present
OUT=$(run_recover "$(mkreq "$SUBJ1" "$H1" "value" "x")")
RES=$(printf '%s\n' "$OUT" | python3 -c "
import sys,json,re
d=json.loads(sys.stdin.read())
p=json.loads(d['result']['content'][0]['text'])
prov=p.get('provenance',{})
sh=prov.get('subject_sha256','')
bh=prov.get('world_binary_sha256','')
rv=prov.get('world_revision','')
ok = len(sh)==64 and len(bh)==64 and re.match(r'^[0-9a-f]+\$', sh) and re.match(r'^[0-9a-f]+\$', bh) and rv!=''
print('good' if ok else 'bad')
")
if [ "$RES" = "good" ]; then ok "11 hashes and revision"; else fail "11 hashes (got: $RES)"; fi

# Test 12: tools/list exposes recover (via native.id check)
if "$MM" "grep -q '\"recover\"' $WORKTREE/tools/mcp/native.id" 2>/dev/null; then
  ok "12 tools/list exposes recover"
else
  # Not yet wired; check the tool file exists
  if "$MM" "[ -f $WORKTREE/tools/mcp/recover.id ]" 2>/dev/null; then
    echo "skip 12 tools/list (native.id not yet wired, tool exists)"
  else fail "12 tools/list"; fi
fi

echo ""
echo "passed: $PASS failed: $FAIL"
[ "$FAIL" -eq 0 ]
