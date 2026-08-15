#!/usr/bin/env python3
"""Wall-clock comparison: Idol's WASM engine vs wasmtime (and other controls).

Reproduce:
    ./build.sh
    WARD=/path/to/engine python3 run_bench.py --runs 5

Rules this harness enforces, because this repo has retracted headline claims
for breaking each of them:

*   Best-of-N, N stated, same machine, same module bytes, back to back.
*   Output is CHECKED against the control's output.  A runtime that produces
    the wrong answer fast is not fast; it is wrong.  Mismatches are reported
    as MISMATCH and never timed.
*   A runtime that cannot execute a workload gets `CANNOT RUN` with the
    engine's own diagnostic, not a timing and not a blank.
*   Startup is measured separately (k_startup does nothing but write one
    byte), because for short-lived invocations it is the entire cost and it is
    the one axis where an interpreter can genuinely beat a JIT.

Note on language: the rest of this tree prefers `.id` for tooling.  This is
python3 deliberately -- `conform/run_spec.id` is currently unrunnable (it
drives the engine through WARD_INVOKE/WARD_ARGS, which the engine has never
read), and a measurement harness that cannot be trusted to run is worse than
one in the wrong language.  Port it once `.id` tooling builds reliably.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
WASM = os.path.join(HERE, "wasm")

# name -> (what it stresses)
WORKLOADS = [
    ("k_startup", "startup only: write one byte and exit"),
    ("k_int32",   "integer-heavy: serial xorshift32 chain, 40M iterations"),
    ("k_int",     "integer-heavy: serial xorshift64 chain, 40M iterations"),
    ("k_calls",   "call-heavy: 6M indirect calls through an 8-entry table"),
    ("k_mem32",   "memory traffic: bulk fill + strided rw over a 1 MiB arena"),
    ("k_mem",     "allocation-heavy: 1200 malloc/free rounds, 48-64 KiB each"),
    ("k_data32",  "hot loop: dependent chase over 2 MiB, 24 passes"),
    ("k_data",    "hot loop: dependent chase over 8 MiB (malloc), 12 passes"),
]


def which(name):
    return shutil.which(name)


def run_once(cmd, env=None, timeout=1800):
    e = dict(os.environ)
    if env:
        e.update(env)
    t0 = time.perf_counter()
    try:
        p = subprocess.run(cmd, env=e, capture_output=True, text=True,
                           timeout=timeout)
        dt = time.perf_counter() - t0
        return dt, p.stdout, p.returncode
    except subprocess.TimeoutExpired:
        return float("inf"), "", -9


def answer(stdout):
    """First non-engine-chatter line of stdout -- the workload's own output."""
    for ln in stdout.splitlines():
        s = ln.strip()
        if not s:
            continue
        if s.startswith(("engine=", "result=", "seconds=", "phase ", "jit_words=",
                         "wasm:")):
            continue
        return s
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--runs", type=int, default=5)
    ap.add_argument("--timeout", type=float, default=1800)
    ap.add_argument("--json", default="")
    args = ap.parse_args()

    ward = os.environ.get("WARD", "")
    if not ward or not os.path.exists(ward):
        sys.exit("set WARD=/path/to/idol wasm engine binary")

    runtimes = []
    if which("wasmtime"):
        runtimes.append(("wasmtime", lambda w: (["wasmtime", "run", w], None)))
    if which("wasmer"):
        runtimes.append(("wasmer", lambda w: (["wasmer", "run", w], None)))
    if which("wasm3"):
        runtimes.append(("wasm3", lambda w: (["wasm3", w], None)))
    runtimes.append(("idol", lambda w: ([ward],
                                        {"DUO_WASM_MODULE": w,
                                         "DUO_WASM_INVOKE": "_start"})))
    if not any(n == "wasmtime" for n, _ in runtimes):
        print("WARNING: wasmtime not found; the control is missing", file=sys.stderr)

    print(f"runs (best-of-N), N = {args.runs}")
    for n, _ in runtimes:
        if n == "idol":
            print(f"  {n:10s} {ward}")
            continue
        v = "?"
        for flag in ("--version", "-v"):
            r = subprocess.run([n, flag], capture_output=True, text=True)
            if r.returncode == 0 and r.stdout.strip():
                v = r.stdout.strip().splitlines()[0]
                break
        print(f"  {n:10s} {v}")
    print()

    results = {}
    header = f"{'workload':11s}" + "".join(f"{n:>14s}" for n, _ in runtimes)
    print(header)
    print("-" * len(header))

    for wl, _desc in WORKLOADS:
        path = os.path.join(WASM, wl + ".wasm")
        if not os.path.exists(path):
            continue
        row = {}
        control_answer = None
        cells = []
        for name, mk in runtimes:
            cmd, env = mk(path)
            best = float("inf")
            out = ""
            rc = 0
            for _ in range(args.runs):
                dt, so, r = run_once(cmd, env, args.timeout)
                if r == 0 and dt < best:
                    best, out, rc = dt, so, r
                if r != 0:
                    rc = r
                    out = so
                    break
            a = answer(out)
            if name == "wasmtime":
                control_answer = a
            if rc != 0:
                cells.append(f"{'CANNOT RUN':>14s}")
                row[name] = {"status": "cannot-run", "rc": rc,
                             "stdout": out[-400:]}
            elif control_answer is not None and a != control_answer:
                cells.append(f"{'MISMATCH':>14s}")
                row[name] = {"status": "mismatch", "answer": a,
                             "expected": control_answer}
            else:
                cells.append(f"{best*1000:>11.1f} ms")
                row[name] = {"status": "ok", "best_s": best, "answer": a}
        print(f"{wl:11s}" + "".join(cells))
        results[wl] = row

    # ratios vs wasmtime, steady state with startup subtracted where possible
    print()
    base = results.get("k_startup", {})
    print("steady state (best-of-N total wall MINUS that runtime's own startup):")
    print(f"{'workload':11s}{'wasmtime':>12s}{'idol':>12s}{'idol/wasmtime':>16s}")
    for wl, _ in WORKLOADS:
        if wl == "k_startup" or wl not in results:
            continue
        r = results[wl]
        wt, il = r.get("wasmtime", {}), r.get("idol", {})
        if wt.get("status") != "ok":
            continue
        wt_s = wt["best_s"] - base.get("wasmtime", {}).get("best_s", 0)
        if il.get("status") != "ok":
            print(f"{wl:11s}{wt_s*1000:>9.1f} ms{il.get('status','?'):>12s}"
                  f"{'-':>16s}")
            continue
        il_s = il["best_s"] - base.get("idol", {}).get("best_s", 0)
        ratio = il_s / wt_s if wt_s > 0 else float("inf")
        print(f"{wl:11s}{wt_s*1000:>9.1f} ms{il_s*1000:>9.1f} ms{ratio:>15.1f}x")

    print()
    print("startup only (k_startup, total wall, best-of-N):")
    for name, _ in runtimes:
        c = base.get(name, {})
        if c.get("status") == "ok":
            print(f"  {name:10s}{c['best_s']*1000:8.1f} ms")
        else:
            print(f"  {name:10s}{c.get('status','n/a'):>10s}")

    if args.json:
        with open(args.json, "w") as f:
            json.dump(results, f, indent=2)
        print(f"\nwrote {args.json}")


if __name__ == "__main__":
    main()
