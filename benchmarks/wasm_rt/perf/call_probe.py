#!/usr/bin/env python3
"""Isolate CALL cost in the Idol WASM interpreter: inline vs direct vs indirect.

Three modules with an identical hot loop and an identical five-opcode body.
Only where that body lives changes:

    inline    the body is in the loop
    direct    the body is a function reached by `call`
    indirect  the body is a function reached by `call_indirect` through a
              1-entry table, with the index coming off the stack

direct - inline  = the cost of a frame push/pop and a `call`.
indirect - direct = the extra cost of table lookup + signature check.

Both differences are per call, and the loop count is identical across probes,
so nothing else can account for the spread.

Usage: WARD=/path/to/engine python3 call_probe.py [--iters N]
"""
import argparse
import os
import subprocess
import sys
import time

BODY = """      local.get $a
      i32.const 2654435761
      i32.mul
      local.get $a
      i32.const 13
      i32.shr_u
      i32.xor"""

INLINE = """(module
  (func (export "run") (result i32)
    (local $i i32) (local $a i32)
    (local.set $a (i32.const 305419896))
    (loop $L
{body_inline}
      local.set $a
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br_if $L (i32.lt_u (local.get $i) (i32.const {iters})))
    )
    (local.get $a)
  )
)
"""

DIRECT = """(module
  (func $mix (param $a i32) (result i32)
{body}
  )
  (func (export "run") (result i32)
    (local $i i32) (local $a i32)
    (local.set $a (i32.const 305419896))
    (loop $L
      (local.set $a (call $mix (local.get $a)))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br_if $L (i32.lt_u (local.get $i) (i32.const {iters})))
    )
    (local.get $a)
  )
)
"""

INDIRECT = """(module
  (type $t (func (param i32) (result i32)))
  (table 1 1 funcref)
  (elem (i32.const 0) $mix)
  (func $mix (type $t) (param $a i32) (result i32)
{body}
  )
  (func (export "run") (result i32)
    (local $i i32) (local $a i32)
    (local.set $a (i32.const 305419896))
    (loop $L
      (local.set $a
        (call_indirect (type $t) (local.get $a) (i32.const 0)))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br_if $L (i32.lt_u (local.get $i) (i32.const {iters})))
    )
    (local.get $a)
  )
)
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--iters", type=int, default=4000000)
    ap.add_argument("--runs", type=int, default=5)
    ap.add_argument("--out", default="/tmp/idol_call_probe")
    args = ap.parse_args()

    ward = os.environ.get("WARD", "")
    if not ward or not os.path.exists(ward):
        sys.exit("set WARD=/path/to/engine binary")
    os.makedirs(args.out, exist_ok=True)

    body_inline = BODY.replace("local.get $a", "local.get $a")
    variants = [
        ("inline", INLINE.format(body_inline=body_inline, iters=args.iters)),
        ("direct", DIRECT.format(body=BODY, iters=args.iters)),
        ("indirect", INDIRECT.format(body=BODY, iters=args.iters)),
    ]

    print(f"{args.iters:,} loop iterations per probe, best of {args.runs}")
    print(f"{'variant':10s}{'best':>10s}{'ns/iteration':>15s}{'delta':>26s}")
    times = {}
    for name, src in variants:
        p = os.path.join(args.out, name)
        open(p + ".wat", "w").write(src)
        r = subprocess.run(["wat2wasm", p + ".wat", "-o", p + ".wasm"],
                           capture_output=True, text=True)
        if r.returncode != 0:
            print(f"{name:10s}   wat2wasm failed: {r.stderr.strip()[:80]}")
            continue
        env = dict(os.environ)
        env["DUO_WASM_MODULE"] = p + ".wasm"
        env["DUO_WASM_INVOKE"] = "run"
        best, ans = float("inf"), None
        for _ in range(args.runs):
            t0 = time.perf_counter()
            q = subprocess.run([ward], env=env, capture_output=True, text=True)
            dt = time.perf_counter() - t0
            if q.returncode != 0:
                best = float("inf")
                break
            for ln in q.stdout.splitlines():
                if ln.startswith("result="):
                    ans = ln[7:]
            best = min(best, dt)
        if best == float("inf"):
            print(f"{name:10s}{'CANNOT RUN':>10s}")
            continue
        times[name] = best
        ns = best / args.iters * 1e9
        d = ""
        if name == "direct" and "inline" in times:
            d = f"+{(best-times['inline'])/args.iters*1e9:.1f} ns = call"
        if name == "indirect" and "direct" in times:
            d = f"+{(best-times['direct'])/args.iters*1e9:.1f} ns = table+sig"
        print(f"{name:10s}{best*1000:8.1f} ms{ns:14.1f}{d:>26s}   result={ans}")


if __name__ == "__main__":
    main()
