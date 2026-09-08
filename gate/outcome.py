import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

if len(sys.argv) != 2:
    raise SystemExit('usage: python3 gate/outcome.py <gate>')
try:
    source = pathlib.Path(sys.argv[1]).read_text()
except (OSError, UnicodeError):
    raise SystemExit('outcome: gate source unavailable; no controls executed')
match = re.findall(r'^carrier\(\) \{.*?^\}', source, re.M | re.S)
if len(match) != 1:
    raise SystemExit('carrier source was not resolved uniquely')
limit = shutil.which('timeout') or shutil.which('gtimeout')
if not limit:
    raise SystemExit('timeout command unavailable; no outcome controls executed')
rows = []
with tempfile.TemporaryDirectory(prefix='outcome-control-') as directory:
    root = pathlib.Path(directory)
    for name, compile, run, output, artifact, want in [
        ('success', 0, 0, '1 0 0', True, True),
        ('failed guest with matching output', 0, 7, '1 0 0', True, False),
        ('compiler failure without diagnostic', 1, 0, '1 0 0', False, False),
        ('missing compiler', 127, 0, '1 0 0', False, False),
        ('compiler timed out', 124, 0, '1 0 0', False, False),
        ('compiler signal', 137, 0, '1 0 0', False, False),
        ('guest missing', 0, 127, '1 0 0', True, False),
        ('guest timed out', 0, 124, '1 0 0', True, False),
        ('guest signal', 0, 139, '1 0 0', True, False),
        ('wrong output', 0, 0, 'wrong', True, False),
        ('missing artifact', 0, 0, '1 0 0', False, False),
    ]:
        (root / 'probe.wasm').unlink(missing_ok=True)
        compiler = ('printf wasm > "$4"\n' if artifact else '') + 'exit ' + str(compile) + '\n'
        runner = "printf '%s\\n' '" + output + "'\nexit " + str(run) + '\n'
        for path, content in [(root / 'compiler', compiler), (root / 'runner', runner)]:
            path.write_text('#!/bin/sh\n' + content)
            path.chmod(0o700)
        code = ('set -u\nwork="$1"\nlimit="$2"\nidol="$work/compiler"\nwasmrun="$work/runner"\n'
                'fail=0\nmeasured=0\n'
                'note() { printf "%s\\n" "$1"; }\n'
                'bad() { printf "%s\\n" "$1" >&2; fail=1; }\n' + match[0] +
                '\ncarrier probe "1 0 0" "print(1)"\n[ "$fail" -eq 0 ]\n')
        result = subprocess.run(['sh', '-c', code, 'gate-control', str(root), limit],
                                capture_output=True, text=True, timeout=5)
        accepted = result.returncode == 0
        rows.append({'case': name, 'pass': accepted == want, 'accepted': accepted,
                     'out': result.stdout, 'error': result.stderr})
print(json.dumps({'boundary': 'the production carrier function; external compiler and runtime explicitly simulated', 'cases': rows}, indent=2))
raise SystemExit(0 if all(row['pass'] for row in rows) else 1)
