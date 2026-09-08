#!/bin/sh
# gate/mcp.sh — MCP tool-contract hold for the produced concept verdict (GAP-120).
#
# `tools/concept/tool.sh` is the MCP face of the produced concept finding:
# one JSON-RPC `tools/call` request object on stdin, one response object on
# stdout, the verdict read from the produced graph through `idol explain`
# and `tools/concept/doc.sh`. This gate holds that face. It owns no
# derivation: verdict-correctness (REFUSED exactly when the export carries
# the refusal, HELD otherwise) is owned by `gate/concept.sh` over the export
# and by the docs slice over the render; what is measured HERE, and nowhere
# else, is the MCP boundary — framing, id round-trip, argv file passing, and
# fail-closed errors.
#
# THE ROSTER CARRIES EVERY PRODUCED DIRECTION, so a one-sided gate cannot
# call itself an enforcement:
#   bucket refused: the produced refusal for the no-shared-demand cohort
#     must reach the caller as a text result. THE NEGATIVE DIRECTION: a
#     projection that stops refusing is convicted. The subject file carries
#     a SPACE in its name: a projection that interpolates the path through
#     a host shell splits it and fails, so the spaced path is the positive
#     control for argv passing (host-transport norm).
#   cohort held: one subject drives both relations, so no refusal may be
#     produced and the result must read HELD. THE POSITIVE DIRECTION: a
#     projection that refuses a lawful cohort is convicted.
#   unwitnessed held: nothing applies the module's one relation, so no
#     refusal may be produced and the result must read HELD. THE THIRD
#     DIRECTION: a projection that refuses a lawful single is convicted.
#     Its produced evidence differs from the cohort's (shared_demand 0,
#     zero refusals, one applied relation), so this row holds the HELD
#     render across the boundary from different facts.
# Fail-closed controls: unknown tool or method answers -32601; a missing or
# non-string file answers -32602; an unreadable subject answers an error
# carrying the refusal to render (never a verdict-shaped result); an
# unparseable request, or two objects on one line, answers -32700. A row
# whose measured answer differs from its demanded answer FAILS. Zero rows
# examined FAILS (GAP-201).
set -u

here=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH='' cd -- "$here/.." && pwd)
cd "$root" || { printf 'mcp: cannot enter root\n' >&2; exit 3; }

if [ "${1-}" = --read ]; then
    exec python3 - "$root" "${2-}" <<'PY'
import hashlib, json, os, pathlib, selectors, shutil, signal, subprocess, sys, tempfile, time

source = pathlib.Path(sys.argv[1])
server = pathlib.Path(sys.argv[2]).resolve()
if not server.is_file() or not os.access(server, os.X_OK):
    raise SystemExit('mcp read: executable server required')
examined = 0

def check(value, name):
    global examined
    examined += 1
    if not value:
        raise AssertionError(name)

def digest(root):
    return {str(p.relative_to(root)): (hashlib.sha256(p.read_bytes()).hexdigest(), p.stat().st_mtime_ns)
            for p in root.rglob('*') if p.is_file() and not p.is_symlink()}

with tempfile.TemporaryDirectory(prefix='idol-mcp-', dir=os.environ.get('TMPDIR')) as directory:
    base = pathlib.Path(directory)
    root = base / 'source'
    root.mkdir()
    git = shutil.which('git')
    def command(*arg):
        return subprocess.check_output([git, '-C', str(root), *arg], stderr=subprocess.PIPE, text=True).strip()
    command('init', '-q')
    command('config', 'user.email', 'test@invalid')
    command('config', 'user.name', 'test')
    (root / 'fact').write_text('observed\n')
    command('add', 'fact')
    command('commit', '-qm', 'fixture')
    command('remote', 'add', 'origin', 'git@github.com:clpi/idol.git')
    head = command('rev-parse', 'HEAD')
    before = digest(root)
    bin = base / 'bin'
    bin.mkdir()
    wrapper = bin / 'git'
    wrapper.write_text('#!' + sys.executable + '\n' + '''import os,pathlib,subprocess,sys,time
if 'ls-remote' in sys.argv:
 mode=os.environ['MODE']
 if mode=='offline':
  sys.stderr.write('private credential must not escape')
  raise SystemExit(1)
 if mode=='malformed':
  print('invalid ref')
  raise SystemExit()
 if mode=='timeout':
  child=subprocess.Popen([sys.executable,'-c','import time;time.sleep(30)'])
  pathlib.Path(os.environ['CHILD']).write_text(str(child.pid))
  time.sleep(30)
 if mode=='changed':
  pathlib.Path(os.environ['IDOL_ROOT'],'change').write_text('changed')
 print(os.environ['PEER']+'\\trefs/heads/main')
else:
 os.execv(''' + repr(git) + ''',[''' + repr(git) + ''',*sys.argv[1:]])
''')
    wrapper.chmod(0o755)
    env = dict(os.environ, PATH=str(bin) + os.pathsep + os.environ['PATH'],
               IDOL_ROOT=str(root), IDOL_BIN=str(server), IDOL_MODE='read', MODE='current', PEER=head,
               CHILD=str(base / 'child'), GIT_OPTIONAL_LOCKS='0')
    def call(name='orient', change=None, missing=False, argument=None, cwd=source):
        context = dict(env, **(change or {}))
        if missing:
            context.pop('IDOL_ROOT', None)
        process = subprocess.Popen([str(server)], cwd=cwd, env=context,
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   text=True, start_new_session=True)
        select = selectors.DefaultSelector()
        select.register(process.stdout, selectors.EVENT_READ)
        def read():
            if not select.select(12):
                raise AssertionError('persistent stream response deadline')
            return json.loads(process.stdout.readline())
        try:
            process.stdin.write(json.dumps({'jsonrpc':'2.0','id':1,'method':'initialize','params':{}}, separators=(',',':'))+'\n')
            process.stdin.flush()
            response = read()
            check(response['id'] == 1 and response['result']['serverInfo']['name'] == 'idol', 'initialize before EOF')
            process.stdin.write(json.dumps({'jsonrpc':'2.0','id':2,'method':'tools/call','params':{'name':name,'arguments':argument or {}}}, separators=(',',':'))+'\n')
            process.stdin.flush()
            response = read()
            check(response['id'] == 2 and response['jsonrpc'] == '2.0', 'actual tool response identity')
            process.stdin.close()
            check(process.wait(timeout=3) == 0, 'stream exits after EOF')
            return response.get('result', response)
        finally:
            select.close()
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=3)
            process.stdout.close()
            process.stderr.close()
    result = call('head')
    check(result['isError'] is False and result['content'][0]['text'] == head, 'current head')
    result = call('status')
    check(result['isError'] is False and result['content'][0]['text'].startswith('## '), 'current status')
    result = call()
    fact = json.loads(result['content'][0]['text'])
    check(result['isError'] is False and fact['head'] == head and fact['remote']['head'] == head
          and fact['root'] == str(root) and fact['dirty'] == 0, 'current authority')
    check(fact['artifact']['digest'] == hashlib.sha256(server.read_bytes()).hexdigest()
          and fact['artifact']['source'] is None, 'artifact source remains unbound')
    check(digest(root) == before, 'no target tracked untracked index or config writes')
    result = call(change={'PEER':'0'*40})
    fact = json.loads(result['content'][0]['text'])
    check(result['isError'] is True and fact['state'] == 'stale' and fact['head'] == head
          and fact['remote']['head'] == '0'*40, 'stale subject refused')
    for name in ('head', 'status'):
        result = call(name, {'PEER':'0'*40})
        check(result['isError'] is True and json.loads(result['content'][0]['text'])['state'] == 'stale', name + ' cannot skip freshness')
    for mode in ('offline', 'malformed'):
        result = call(change={'MODE':mode})
        fact = json.loads(result['content'][0]['text'])
        check(result['isError'] is True and fact['state'] == 'unavailable'
              and fact['remote']['head'] is None and 'private credential' not in json.dumps(result), mode)
    command('remote','set-url','origin','https://credential@foreign.invalid/private')
    result = call()
    check(result['isError'] is True and json.loads(result['content'][0]['text'])['state'] == 'foreign'
          and 'credential' not in json.dumps(result), 'foreign sanitized')
    command('remote','set-url','origin','git@github.com:clpi/idol.git')
    (root/'untracked').write_text('preserve')
    dirty = digest(root)
    result = call()
    check(result['isError'] is True and json.loads(result['content'][0]['text'])['state'] == 'dirty'
          and digest(root) == dirty, 'dirty source preserved')
    (root/'untracked').unlink()
    result = call(change={'IDOL_MODE':'unknown'})
    check(result['isError'] is True and json.loads(result['content'][0]['text'])['reason'] == 'mode', 'unknown mode refuses')
    ordinary = call('head', {'IDOL_MODE':'','MODE':'offline'})
    check('isError' not in ordinary and ordinary['content'][0]['text'] == subprocess.check_output([git,'-C',str(source),'rev-parse','HEAD'],text=True).strip(), 'ordinary candidate head unchanged')
    private = base/'private'
    doc = private/'tools'/'concept'/'doc.sh'
    doc.parent.mkdir(parents=True)
    doc.write_text('#!/bin/sh\nprintf touched > reached\nprintf "%s" "$1" > argument\nprintf "doc: FAIL fixture"\n')
    doc.chmod(0o755)
    argument = {'file':str(root/'fact'), 'name':'concept'}
    for name, mode in (('concept','read'), ('head','read'), ('head','unknown')):
        result = call(name, {'IDOL_MODE':mode}, argument=argument, cwd=private)
        check(result['error']['code'] == -32000 and 'connection mode' in result['error']['message']
              and not (private/'reached').exists(), name + ' cannot execute in ' + mode)
    result = call('concept', {'IDOL_MODE':''}, argument=argument, cwd=private)
    check(result['error']['code'] == -32000 and (private/'reached').read_text() == 'touched', 'ordinary concept path remains executable')
    for subject in ("path with space.id", "quo'te.id", "' ;touch injected; $(touch injected) `touch injected` .id"):
        result = call('concept', {'IDOL_MODE':''}, argument={'file':subject}, cwd=private)
        check(result['error']['code'] == -32000 and (private/'argument').read_text() == subject
              and not (private/'injected').exists(), 'exact single shell argument ' + subject)
    result = call(missing=True)
    check(result['isError'] is True and json.loads(result['content'][0]['text'])['root'] is None, 'explicit root required')
    alias = base/'alias'
    alias.symlink_to(root,target_is_directory=True)
    result = call(change={'IDOL_ROOT':str(alias)})
    check(result['isError'] is True and json.loads(result['content'][0]['text'])['state'] == 'invalid', 'root alias refused')
    result = call(change={'MODE':'changed'})
    check(result['isError'] is True and json.loads(result['content'][0]['text'])['state'] == 'changed', 'changing source refused')
    (root/'change').unlink()
    began = time.monotonic()
    result = call(change={'MODE':'timeout'})
    check(result['isError'] is True and json.loads(result['content'][0]['text'])['state'] == 'unavailable'
          and time.monotonic()-began < 12, 'remote deadline bounded')
    child = int((base/'child').read_text())
    state = subprocess.run(['ps','-p',str(child),'-o','stat='],capture_output=True,text=True)
    check(state.returncode != 0 or state.stdout.strip().startswith('Z'), 'timed out request descendants stopped')
    final = digest(root)
    result = call()
    check(result['isError'] is False and digest(root) == final, 'failure cannot become cached authority or mutate source')
print(json.dumps({'passed':examined,'failed':0,'skipped':0,'transport':'actual persistent MCP stdio','network':'offline controlled remote boundary'}))
PY
fi

IDOL=${IDOL:-"$root/zig-out/bin/idol"}
tool=$here/../tools/concept/tool.sh
self=$here/$(basename -- "$0")

if [ ! -x "$IDOL" ]; then
    printf 'mcp: NOT MEASURED — %s is not a compiler (a checked graph was required)\n' "$IDOL" >&2
    exit 3
fi
if [ ! -x "$tool" ]; then
    printf 'mcp: NOT MEASURED — %s is not executable (the tool projection was required)\n' "$tool" >&2
    exit 3
fi

command -v jq >/dev/null 2>&1 || {
    printf 'mcp: NOT MEASURED — jq is required to frame the tool contract\n' >&2
    exit 3
}

work=$(mktemp -d "${TMPDIR:-/tmp}/idol.mcp.XXXXXX") || exit 3
TMPDIR=$work/scratch
export TMPDIR
mkdir -p "$TMPDIR" || exit 3
cleanup() { rm -rf -- "$work"; }
trap 'cleanup' EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM
trap 'cleanup; exit 129' HUP

# ── the subjects ─────────────────────────────────────────────────────────
# Same three shapes `gate/concept.sh` materializes (bucket: no subject drives
# both relations — refused; cohort: one subject drives both — held;
# unwitnessed: nothing applies the one relation — held). The
# verdict-correctness of those shapes is owned there; here they are the
# positive controls that the verdict crossed the MCP boundary intact.
printf 'plus(a: i64, b: i64): i64\n  a + b\nminus(a: i64, b: i64): i64\n  a - b\nmain(): i64\n  x = plus(2, 3)\n  x + 1\nentry(): i64\n  minus(7, 4)\n' >"$work/my bucket.id" || exit 3
printf 'plus(a: i64, b: i64): i64\n  a + b\nminus(a: i64, b: i64): i64\n  a - b\nmain(): i64\n  x = plus(2, 3)\n  y = plus(1, 1)\n  minus(y, 4)\n' >"$work/cohort.id" || exit 3
printf 'plus(a: i64, b: i64): i64\n  a + b\nmain(): i64\n  x = plus(2, 3)\n  x + 1\n' >"$work/unwitnessed.id" || exit 3

examined=0
failed=0

# call <id-json> <request-json> <response-file>: one request in, one line out.
call() {
    printf '%s\n' "$2" | sh "$tool" >"$3" 2>"$3.diag" || {
        printf 'mcp: FAIL — tool exited nonzero on id %s\n' "$1" >&2
        failed=$((failed + 1))
        return 1
    }
    examined=$((examined + 1))
}

# demand_text <id-json> <file> <needle>: a verdict must cross as text.
demand_text() {
    resp=$work/respText.json
    req=$(jq -n -c --arg f "$2" --argjson id "$1" \
        '{jsonrpc:"2.0",id:$id,method:"tools/call",params:{name:"concept",arguments:{file:$f}}}') || {
        printf 'mcp: FAIL — request could not be framed for id %s\n' "$1" >&2
        failed=$((failed + 1))
        return 1
    }
    call "$1" "$req" "$resp" || return 1
    [ "$(wc -l <"$resp" | tr -d ' ')" = "1" ] || {
        printf 'mcp: FAIL — id %s answered %s lines, one line was demanded\n' "$1" "$(wc -l <"$resp")" >&2
        failed=$((failed + 1))
        return 1
    }
    jq -e --argjson id "$1" '.id == $id and (has("error") | not)' <"$resp" >/dev/null 2>&1 || {
        printf 'mcp: FAIL — id %s lost its id or carried an error where a verdict was demanded\n' "$1" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
        return 1
    }
    jq -r '.result.content[0].text // ""' <"$resp" 2>/dev/null | grep -Fq "$3" || {
        printf 'mcp: FAIL — id %s verdict text misses %s\n' "$1" "$3" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
        return 1
    }
}

# demand_error <label> <request-json> <code>: a failure must refuse with code.
demand_error() {
    resp=$work/respErr.json
    call "$1" "$2" "$resp" || return 1
    jq -e --argjson code "$3" 'has("error") and .error.code == $code and (.error.message | type == "string")' \
        <"$resp" >/dev/null 2>&1 || {
        printf 'mcp: FAIL — %s refused with the wrong shape (demanded error %s)\n' "$1" "$3" >&2
        cat "$resp" >&2
        failed=$((failed + 1))
        return 1
    }
    jq -e '(has("result") | not)' <"$resp" >/dev/null 2>&1 || {
        printf 'mcp: FAIL — %s carried a result beside its error; a refusal is never verdict-shaped\n' "$1" >&2
        failed=$((failed + 1))
        return 1
    }
}

# ── every produced direction ─────────────────────────────────────────────
demand_text 1 "$work/my bucket.id" "verdict: REFUSED no_shared_demand"
demand_text 2 "$work/cohort.id" "verdict: HELD one concept"
demand_text 3 "$work/unwitnessed.id" "verdict: HELD one concept"

# The id is opaque: member order and string ids round-trip untouched.
req=$(jq -n -c --arg f "$work/cohort.id" \
    '{method:"tools/call",params:{name:"concept",arguments:{file:$f}},jsonrpc:"2.0",id:4}') || exit 3
resp=$work/respOrder.json
call 4 "$req" "$resp" || true
jq -e '.id == 4 and .result.content[0].text != ""' <"$resp" >/dev/null 2>&1 || {
    printf 'mcp: FAIL — id-last member order did not round-trip\n' >&2
    failed=$((failed + 1))
}
demand_text '"held"' "$work/cohort.id" "verdict: HELD one concept"

# ── fail-closed ──────────────────────────────────────────────────────────
req=$(jq -n -c --arg f "$work/cohort.id" \
    '{jsonrpc:"2.0",id:5,method:"tools/call",params:{name:"status",arguments:{file:$f}}}') || exit 3
demand_error unknown-tool "$req" -32601

req=$(jq -n -c \
    '{jsonrpc:"2.0",id:6,method:"tools/list",params:{}}') || exit 3
demand_error wrong-method "$req" -32601

req=$(jq -n -c '{jsonrpc:"2.0",id:7,method:"tools/call",params:{name:"concept",arguments:{}}}') || exit 3
demand_error missing-file "$req" -32602

req=$(jq -n -c '{jsonrpc:"2.0",id:8,method:"tools/call",params:{name:"concept",arguments:{file:7}}}') || exit 3
demand_error nonstring-file "$req" -32602

req=$(jq -n -c --arg f "$work/absent.id" \
    '{jsonrpc:"2.0",id:9,method:"tools/call",params:{name:"concept",arguments:{file:$f}}}') || exit 3
demand_error unreadable-subject "$req" -32000

demand_error malformed '{oops' -32700
demand_error adjacent '{"jsonrpc":"2.0","id":11,"method":"ping","params":{}} {"jsonrpc":"2.0","id":12,"method":"ping","params":{}}' -32700

[ "$examined" -gt 0 ] || {
    printf 'mcp: FAIL — 0 tool contracts examined\n' >&2
    exit 1
}
if [ "$failed" -ne 0 ]; then
    printf 'mcp: FAIL — %s of %s examined contract(s) failed\n' "$failed" "$examined" >&2
    exit 1
fi
printf 'mcp: PASS — %s examined contract(s), 0 failed\n' "$examined"
exit 0
