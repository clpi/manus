#!/usr/bin/env bash
# Interleaved median wall-clock benchmark: ward vs wasmtime.
#
# Use THIS for any perf claim, never ward's printed `seconds=`. That value is
# os.clock, which on macOS accumulates CPU time across threads: it read 0.60 s
# while wall time was 0.40 s. Comparing it to wasmtime's wall time flattered
# ward once and faked a 55% regression later. Interleave, and take the median —
# this box drifts measurably under sustained load.
set -uo pipefail
cd "$(dirname "$0")/.."
WARD_BIN=${WARD_BIN:-/tmp/ward} MOD=${1:-bench/hash.wasm} N=${N:-7} python3 - "$@" <<'PY'
import subprocess, time, statistics, os, sys
mod=os.environ.get("MOD","bench/hash.wasm"); n=int(os.environ.get("N","7"))
env=dict(os.environ); env["WARD_WASM"]=os.path.abspath(mod)
def run(cmd,e=None):
    t=time.time(); subprocess.run(cmd,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,env=e); return time.time()-t
w=[];m=[]
for _ in range(n):
    w.append(run([os.environ["WARD_BIN"]],env))
    m.append(run(["wasmtime","--invoke","run",mod]))
mw,mm=statistics.median(w),statistics.median(m)
print("module   %s" % mod)
print("ward     median %.3f s  min %.3f" % (mw,min(w)))
print("wasmtime median %.3f s  min %.3f" % (mm,min(m)))
print("ratio    %.3f  (<1.0 means ward is faster)" % (mw/mm))
PY
