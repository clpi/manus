#!/bin/sh
# gate/mcp-contrast.sh — adversarial tests for the MCP contrast tool.
# Pipes JSON-RPC directly into tools/mcp/contrast.id via idol run.
# All test binaries run under timeout.
set -u
cd "$(dirname "$0")/.."
PASS=0
FAIL=0

ok() { PASS=$((PASS+1)); printf 'ok %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf 'FAIL %s: %s\n' "$1" "$2"; }

contrast_req() {
  printf '%s\n' "$1" | timeout 60 ./zig-out/bin/idol run --backend=native tools/mcp/contrast.id 2>/dev/null | tail -1
}

inner() {
  python3 -c "import sys,json; d=json.load(sys.stdin); r=d.get('result',{}); c=r.get('content',[{}])[0].get('text','{}'); print(c)" 2>/dev/null
}
err_inner() {
  python3 -c "import sys,json; d=json.load(sys.stdin); m=d.get('error',{}).get('message','{}'); print(m)" 2>/dev/null
}
ecode() {
  python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('error',{}).get('code',''))" 2>/dev/null
}

printf 'main: i64 = ()\n  0\nmain()\n' > /tmp/ct-subject.id
SHA=$(sha256sum /tmp/ct-subject.id | cut -d' ' -f1)

# --- Case 1: happy question, three candidates differ ---
R=$(contrast_req '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"contrast","arguments":{"file":"/tmp/ct-subject.id","ambiguity":{"kind":"tiebreak","region":"r1","candidates":["keep-first","keep-last","report-conflict"]}}}}')
T=$(printf '%s' "$R" | inner)
QID=$(printf '%s' "$T" | python3 -c "import sys,json; print(json.load(sys.stdin).get('question_id',''))" 2>/dev/null)
EXPQID=$(printf '%s' "$SHA|r1|tiebreak|keep-first,keep-last,report-conflict" | sha256sum | cut -d' ' -f1)
V=$(printf '%s' "$T" | python3 -c "
import sys,json
t=json.load(sys.stdin)
o=t.get('candidate_observations',{})
exp={'keep-first':{'d1':{'ts':100,'payload':'a'}},'keep-last':{'d1':{'ts':100,'payload':'b'}},'report-conflict':{'conflict':{'key':'d1','ts':100,'payloads':['a','b']}}}
p=t.get('provenance',{})
a=t.get('answer',{})
print(t.get('status',''), p.get('subject_hash',''), p.get('region',''), p.get('kind',''), o==exp, a.get('candidate','')=='' and a.get('candidates')==['keep-first','keep-last','report-conflict'], 'preserve the earlier arrival' in t.get('question',''))
" 2>/dev/null)
if [ "$QID" = "$EXPQID" ] && [ -n "$QID" ] && [ "$V" = "question $SHA r1 tiebreak True True True" ]; then
  ok "case1-question"
else
  bad "case1-question" "qid=[$QID] exp=[$EXPQID] v=[$V]"
fi

# --- Case 2: two candidates ---
R=$(contrast_req '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"contrast","arguments":{"file":"/tmp/ct-subject.id","ambiguity":{"kind":"tiebreak","region":"r2","candidates":["keep-last","keep-first"]}}}}')
T=$(printf '%s' "$R" | inner)
V=$(printf '%s' "$T" | python3 -c "
import sys,json
t=json.load(sys.stdin)
o=t.get('candidate_observations',{})
print(t.get('status',''), sorted(o.keys()), o.get('keep-last')=={'d1':{'ts':100,'payload':'b'}})
" 2>/dev/null)
case "$V" in
  "question ['keep-first', 'keep-last'] True") ok "case2-two" ;;
  *) bad "case2-two" "v=[$V]" ;;
esac

# --- Case 3: duplicate candidate names -> invalid-params ---
R=$(contrast_req '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"contrast","arguments":{"file":"/tmp/ct-subject.id","ambiguity":{"kind":"tiebreak","region":"r1","candidates":["keep-first","keep-first"]}}}}')
C=$(printf '%s' "$R" | ecode)
case "$C" in -32602) ok "case3-duplicates";; *) bad "case3-duplicates" "code=[$C]";; esac

# --- Case 4: unreadable subject ---
printf 'secret' > /tmp/ct-secret.id; chmod 000 /tmp/ct-secret.id
R=$(contrast_req '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"contrast","arguments":{"file":"/tmp/ct-secret.id","ambiguity":{"kind":"tiebreak","region":"r1","candidates":["keep-first","keep-last"]}}}}')
T=$(printf '%s' "$R" | err_inner)
E=$(printf '%s' "$T" | python3 -c "import sys,json; t=json.load(sys.stdin); print(t.get('reason',''), t.get('producer',''), 'verdict' in t)" 2>/dev/null)
chmod 644 /tmp/ct-secret.id; rm -f /tmp/ct-secret.id
case "$E" in
  "unreadable-subject caller False") ok "case4-unreadable" ;;
  *) bad "case4-unreadable" "wrong: [$E]" ;;
esac

# --- Case 5: unsupported ambiguity kind ---
R=$(contrast_req '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"contrast","arguments":{"file":"/tmp/ct-subject.id","ambiguity":{"kind":"merge","region":"r1","candidates":["keep-first","keep-last"]}}}}')
T=$(printf '%s' "$R" | err_inner)
E=$(printf '%s' "$T" | python3 -c "import sys,json; t=json.load(sys.stdin); print(t.get('reason',''), t.get('next',''), t.get('producer',''))" 2>/dev/null)
case "$E" in
  "unsupported-ambiguity supply kind tiebreak contrast") ok "case5-kind" ;;
  *) bad "case5-kind" "wrong: [$E]" ;;
esac

# --- Case 6: answer mode happy path -> requirement bound to subject hash ---
R=$(contrast_req '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"contrast","arguments":{"file":"/tmp/ct-subject.id","answer":{"question_id":"'"$QID"'","candidate":"keep-last","candidates":["keep-first","keep-last","report-conflict"],"region":"r1","kind":"tiebreak"}}}}')
T=$(printf '%s' "$R" | inner)
V=$(printf '%s' "$T" | python3 -c "
import sys,json
t=json.load(sys.stdin)
q=t.get('requirement',{})
o=t.get('obligations',[{}])[0]
print(t.get('status',''), q.get('resolution',''), q.get('subject_hash',''), q.get('provenance',{}).get('question_id',''), o.get('id',''), o.get('status',''))
" 2>/dev/null)
if [ "$V" = "requirement keep-last $SHA $QID answer-bound satisfied" ]; then
  ok "case6-answer"
else
  bad "case6-answer" "v=[$V]"
fi

# --- Case 7: tampered question_id -> subject-changed ---
R=$(contrast_req '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"contrast","arguments":{"file":"/tmp/ct-subject.id","answer":{"question_id":"0000000000000000000000000000000000000000000000000000000000000000","candidate":"keep-last","candidates":["keep-first","keep-last","report-conflict"],"region":"r1","kind":"tiebreak"}}}}')
T=$(printf '%s' "$R" | err_inner)
E=$(printf '%s' "$T" | python3 -c "import sys,json; t=json.load(sys.stdin); print(t.get('reason',''), t.get('next',''))" 2>/dev/null)
case "$E" in
  "subject-changed re-derive the question against the current subject") ok "case7-tampered" ;;
  *) bad "case7-tampered" "wrong: [$E]" ;;
esac

# --- Case 8: answer names a candidate not in the list -> invalid ---
Q2=$(printf '%s' "$SHA|r1|tiebreak|keep-last,report-conflict" | sha256sum | cut -d' ' -f1)
R=$(contrast_req '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"contrast","arguments":{"file":"/tmp/ct-subject.id","answer":{"question_id":"'"$Q2"'","candidate":"keep-first","candidates":["keep-last","report-conflict"],"region":"r1","kind":"tiebreak"}}}}')
C=$(printf '%s' "$R" | ecode)
case "$C" in -32602) ok "case8-badcandidate";; *) bad "case8-badcandidate" "code=[$C]";; esac

# --- Case 9: subject modified between question and answer -> subject-changed ---
cp /tmp/ct-subject.id /tmp/ct-mut.id
R=$(contrast_req '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"contrast","arguments":{"file":"/tmp/ct-mut.id","ambiguity":{"kind":"tiebreak","region":"r1","candidates":["keep-first","keep-last"]}}}}')
QM=$(printf '%s' "$R" | inner | python3 -c "import sys,json; print(json.load(sys.stdin).get('question_id',''))" 2>/dev/null)
printf '\n' >> /tmp/ct-mut.id
R=$(contrast_req '{"jsonrpc":"2.0","id":8,"method":"tools/call","params":{"name":"contrast","arguments":{"file":"/tmp/ct-mut.id","answer":{"question_id":"'"$QM"'","candidate":"keep-first","candidates":["keep-first","keep-last"],"region":"r1","kind":"tiebreak"}}}}')
T=$(printf '%s' "$R" | err_inner)
E=$(printf '%s' "$T" | python3 -c "import sys,json; t=json.load(sys.stdin); print(t.get('reason',''))" 2>/dev/null)
rm -f /tmp/ct-mut.id
case "$E" in
  "subject-changed") ok "case9-modified" ;;
  *) bad "case9-modified" "wrong: [$E]" ;;
esac

# --- Case 10: file present but ambiguity missing -> invalid-params ---
R=$(contrast_req '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"contrast","arguments":{"file":"/tmp/ct-subject.id"}}}')
C=$(printf '%s' "$R" | ecode)
case "$C" in -32602) ok "case10-noambiguity";; *) bad "case10-noambiguity" "code=[$C]";; esac

# --- Case 11: malformed JSON line -> parse error ---
R=$(printf 'not json\n' | timeout 60 ./zig-out/bin/idol run --backend=native tools/mcp/contrast.id 2>/dev/null | tail -1)
C=$(printf '%s' "$R" | ecode)
case "$C" in -32700) ok "case11-malformed";; *) bad "case11-malformed" "code=[$C]";; esac

# --- Case 12: unknown candidate name -> invalid-params ---
R=$(contrast_req '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"contrast","arguments":{"file":"/tmp/ct-subject.id","ambiguity":{"kind":"tiebreak","region":"r1","candidates":["keep-first","bogus"]}}}}')
C=$(printf '%s' "$R" | ecode)
case "$C" in -32602) ok "case12-unknown";; *) bad "case12-unknown" "code=[$C]";; esac

# --- Case 13: single candidate -> invalid-params ---
R=$(contrast_req '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"contrast","arguments":{"file":"/tmp/ct-subject.id","ambiguity":{"kind":"tiebreak","region":"r1","candidates":["keep-first"]}}}}')
C=$(printf '%s' "$R" | ecode)
case "$C" in -32602) ok "case13-single";; *) bad "case13-single" "code=[$C]";; esac

# --- Case 14: missing arguments -> invalid-params ---
R=$(contrast_req '{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"contrast"}}')
C=$(printf '%s' "$R" | ecode)
case "$C" in -32602) ok "case14-noargs";; *) bad "case14-noargs" "code=[$C]";; esac

rm -f /tmp/ct-subject.id

printf 'pass=%d fail=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
