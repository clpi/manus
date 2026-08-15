#!/usr/bin/env python3
"""Measure the Idol interpreter's DISPATCH cost, isolated from arm cost.

The interpreter in tools/wasm/src/engine.id decodes one opcode and then walks a
linear `if / elseif` chain to find its arm.  Four hot opcodes are tested first
(i32.const, local.get, i32 arithmetic, local.tee); roughly forty-five more arms
follow in source order.  If dispatch really is linear, two opcodes with the
same stack shape and the same trivial body should differ in cost purely by how
far down the chain they sit.

Three probes, identical except for one unary i32->i32 opcode repeated 32x per
loop iteration:

    i32.eqz        0x45   ~arm  7
    i32.clz        0x67   ~arm 18
    i32.extend8_s  0xC0   ~arm 44

Any spread between them is dispatch, not work: all three are a single ALU
operation on a value already on the stack.

Usage: WARD=/path/to/engine python3 dispatch_probe.py [--iters N]
"""
import argparse
import os
import subprocess
import sys
import time

PROBES = [("i32.eqz", 7), ("i32.clz", 18), ("i32.extend8_s", 44)]
UNROLL = 32


def wat(op, iters):
    body = "\n".join(f"      local.get $x\n      {op}\n      local.set $x"
                     for _ in range(UNROLL))
    return f"""(module
  (func (export "run") (result i32)
    (local $i i32) (local $x i32)
    (local.set $x (i32.const 305419896))
    (loop $L
{body}
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br_if $L (i32.lt_u (local.get $i) (i32.const {iters})))
    )
    (local.get $x)
  )
)
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--iters", type=int, default=1000000)
    ap.add_argument("--runs", type=int, default=5)
    ap.add_argument("--out", default="/tmp/idol_dispatch_probe")
    args = ap.parse_args()

    ward = os.environ.get("WARD", "")
    if not ward or not os.path.exists(ward):
        sys.exit("set WARD=/path/to/engine binary")
    os.makedirs(args.out, exist_ok=True)

    # Each unrolled unit is THREE dispatches: local.get, OP, local.set.  Only
    # OP differs between probes, so the spread between probes is the cost of
    # OP's position in the chain and nothing else.
    total_units = args.iters * UNROLL
    print(f"{total_units:,} units per probe "
          f"({args.iters:,} iterations x {UNROLL} unrolled), "
          f"one unit = local.get + OP + local.set, best of {args.runs}")
    print(f"{'opcode':16s}{'arm':>5s}{'best':>10s}{'ns/unit':>10s}"
          f"{'delta = chain cost':>22s}")
    base = None
    base_arm = None
    for op, arm in PROBES:
        p = os.path.join(args.out, op.replace(".", "_"))
        open(p + ".wat", "w").write(wat(op, args.iters))
        r = subprocess.run(["wat2wasm", p + ".wat", "-o", p + ".wasm"],
                           capture_output=True, text=True)
        if r.returncode != 0:
            print(f"{op:16s}{arm:5d}   wat2wasm failed: {r.stderr.strip()[:60]}")
            continue
        env = dict(os.environ)
        env["DUO_WASM_MODULE"] = p + ".wasm"
        env["DUO_WASM_INVOKE"] = "run"
        best = float("inf")
        for _ in range(args.runs):
            t0 = time.perf_counter()
            q = subprocess.run([ward], env=env, capture_output=True, text=True)
            dt = time.perf_counter() - t0
            if q.returncode != 0:
                best = float("inf")
                break
            best = min(best, dt)
        if best == float("inf"):
            print(f"{op:16s}{arm:5d}{'CANNOT RUN':>10s}")
            continue
        ns = best / total_units * 1e9
        if base is None:
            base, base_arm = ns, arm
            print(f"{op:16s}{arm:5d}{best*1000:8.1f} ms{ns:9.2f}"
                  f"{'(reference)':>22s}")
        else:
            d = ns - base
            per_arm = d / (arm - base_arm)
            print(f"{op:16s}{arm:5d}{best*1000:8.1f} ms{ns:9.2f}"
                  f"{'+' + format(d, '.2f') + ' ns = ' + format(per_arm, '.3f') + ' ns/arm':>22s}")


if __name__ == "__main__":
    main()
