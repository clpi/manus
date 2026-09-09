#!/usr/bin/env python3
"""Spec conformance for the Idol WASM engine, scored against the FULL suite.

Why not benchmarks/wasm_rt/conform/run_spec.id: that harness drives the engine
through WARD_INVOKE / WARD_ARGS, environment variables the engine has never
read.  The engine's actual protocol is DUO_WASM_MODULE / DUO_WASM_INVOKE, and
it has no argument channel at all -- `run_body(bytes, len, tgt, 0)` is the only
call site and it passes no operands.  So every assertion whose invoke takes
arguments is UNRUNNABLE, not failing, and must be reported as a capability gap
against the full denominator rather than quietly dropped from it.

Denominator policy: `assert_return` + `assert_trap` over every .wast in the
official testsuite that wabt can convert.  Validation-only assertions
(assert_invalid / assert_malformed / assert_unlinkable / assert_uninstantiable)
are reported separately: the engine exposes no validator entry point, so they
are neither passed nor failed.

Usage:
  WARD=/path/to/engine python3 spec_conformance.py [--suite DIR] [--only a,b]
"""
import argparse
import glob
import json
import os
import struct
import subprocess
import sys

MASK32 = 0xFFFFFFFF


def canon(t, v):
    """Expected value -> comparable python object."""
    if isinstance(v, list):
        return ("v128", tuple(v))
    if v in ("nan:canonical", "nan:arithmetic"):
        return ("nan",)
    try:
        n = int(v)
    except (TypeError, ValueError):
        # "null" (a null reference) and other symbolic values the engine has
        # no channel for.  Treated as raw so they can only match literally.
        return ("raw", str(v))
    if t == "i32":
        return ("int", n & MASK32)
    if t == "i64":
        return ("int", n & 0xFFFFFFFFFFFFFFFF)
    if t == "f32":
        bits = n & MASK32
        if (bits & 0x7F800000) == 0x7F800000 and (bits & 0x007FFFFF):
            return ("nan",)
        return ("float", struct.unpack("<f", struct.pack("<I", bits))[0])
    if t == "f64":
        bits = n & 0xFFFFFFFFFFFFFFFF
        if (bits & 0x7FF0000000000000) == 0x7FF0000000000000 and (bits & 0xFFFFFFFFFFFFF):
            return ("nan",)
        return ("float", struct.unpack("<d", struct.pack("<Q", bits))[0])
    return ("raw", str(v))


def parse_result(t, line):
    """Engine `result=` payload -> comparable python object, or None."""
    if line is None:
        return None
    s = line.strip()
    if s in ("nan", "-nan", "inf", "-inf") and t in ("f32", "f64"):
        return ("nan",) if "nan" in s else ("float", float(s))
    try:
        if t in ("f32", "f64"):
            f = float(s)
            if f != f:
                return ("nan",)
            return ("float", f)
        n = int(float(s)) if ("e" in s or "." in s) else int(s)
    except ValueError:
        return None
    if t == "i32":
        return ("int", n & MASK32)
    return ("int", n & 0xFFFFFFFFFFFFFFFF)


def eq(a, b):
    if a is None or b is None:
        return False
    if a[0] == "nan" or b[0] == "nan":
        return a[0] == b[0] == "nan"
    if a[0] == "float" and b[0] == "float":
        if a[1] == b[1]:
            return True
        # engine prints decimal, not bits; accept a tight relative match
        if a[1] != 0 and b[1] != 0:
            return abs(a[1] - b[1]) <= 1e-12 * max(abs(a[1]), abs(b[1]))
        return False
    return a == b


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--suite", default="$HOME/x/wart/third_party/testsuite")
    ap.add_argument("--work", default="/tmp/idol_wasm_spec")
    ap.add_argument("--only", default="")
    ap.add_argument("--timeout", type=float, default=20.0)
    ap.add_argument("--engine", default="", help="DUO_WASM_ENGINE value, e.g. interp")
    args = ap.parse_args()

    ward = os.environ.get("WARD", "")
    if not ward or not os.path.exists(ward):
        sys.exit("set WARD=/path/to/engine binary")

    os.makedirs(args.work, exist_ok=True)
    wasts = sorted(glob.glob(os.path.join(args.suite, "*.wast")))
    only = [x for x in args.only.split(",") if x]

    conv_ok = conv_fail = 0
    n_ret = n_trap = 0            # executable assertions in the full suite
    n_valid = 0                   # validation-only assertions
    unrunnable_args = 0           # engine has no argument channel
    unrunnable_other = 0
    npass = nfail = 0
    fails = []
    per_suite = {}

    for wast in wasts:
        name = os.path.splitext(os.path.basename(wast))[0]
        if only and name not in only:
            continue
        out = os.path.join(args.work, name)
        os.makedirs(out, exist_ok=True)
        js = os.path.join(out, name + ".json")
        if not os.path.exists(js):
            r = subprocess.run(["wast2json", wast, "-o", js],
                               capture_output=True)
            if r.returncode != 0:
                conv_fail += 1
                continue
        conv_ok += 1
        spec = json.load(open(js))
        cur = None
        s_pass = s_fail = s_skip = 0
        for cmd in spec["commands"]:
            k = cmd["type"]
            if k == "module":
                cur = os.path.join(out, cmd["filename"])
                continue
            if k in ("assert_invalid", "assert_malformed", "assert_unlinkable",
                     "assert_uninstantiable"):
                n_valid += 1
                continue
            if k not in ("assert_return", "assert_trap"):
                continue
            if k == "assert_return":
                n_ret += 1
            else:
                n_trap += 1
            act = cmd.get("action") or {}
            if act.get("type") != "invoke" or cur is None:
                unrunnable_other += 1
                s_skip += 1
                continue
            if act.get("args"):
                unrunnable_args += 1
                s_skip += 1
                continue
            if "\x00" in act["field"]:
                # names.wast exports NUL-bearing names; the engine selects the
                # export through an environment variable, which cannot carry one.
                unrunnable_other += 1
                s_skip += 1
                continue
            env = dict(os.environ)
            env["DUO_WASM_MODULE"] = cur
            env["DUO_WASM_INVOKE"] = act["field"]
            if args.engine:
                env["DUO_WASM_ENGINE"] = args.engine
            try:
                r = subprocess.run([ward], env=env, capture_output=True,
                                   text=True, timeout=args.timeout)
                text = r.stdout
                rc = r.returncode
            except subprocess.TimeoutExpired:
                text, rc = "", -9
            res = None
            for ln in text.splitlines():
                if ln.startswith("result="):
                    res = ln[len("result="):]
            if k == "assert_trap":
                # a trap must not yield a value
                good = (res is None)
            else:
                exp = cmd.get("expected") or []
                if not exp:
                    good = (rc == 0 and res is not None)
                elif len(exp) > 1:
                    good = False          # engine returns one scalar
                else:
                    et = exp[0]["type"]
                    if "value" not in exp[0]:
                        good = res is not None
                    else:
                        good = eq(parse_result(et, res), canon(et, exp[0]["value"]))
            if good:
                npass += 1
                s_pass += 1
            else:
                nfail += 1
                s_fail += 1
                if len(fails) < 40:
                    fails.append(f"{name}:{cmd.get('line')} {act['field']} "
                                 f"want={cmd.get('expected')} got={res!r} rc={rc}")
        if s_pass or s_fail or s_skip:
            per_suite[name] = (s_pass, s_fail, s_skip)

    executable = n_ret + n_trap
    attempted = npass + nfail
    print(f"suite dir            : {args.suite}")
    print(f"engine               : {ward}"
          + (f"  (DUO_WASM_ENGINE={args.engine})" if args.engine else ""))
    print(f".wast converted      : {conv_ok}  (wast2json refused {conv_fail})")
    print()
    print(f"FULL-SUITE DENOMINATOR (assert_return + assert_trap) : {executable}")
    print(f"  attempted by engine (zero-arg invoke)              : {attempted}"
          f"  ({100*attempted/executable:.2f}%)")
    print(f"  UNRUNNABLE - engine has no argument channel        : {unrunnable_args}")
    print(f"  UNRUNNABLE - other (non-invoke action, no module)  : {unrunnable_other}")
    print()
    print(f"  pass  : {npass}   = {100*npass/executable:.2f}% OF THE FULL SUITE")
    print(f"  fail  : {nfail}")
    if attempted:
        print(f"  (pass rate within the attempted subset only: "
              f"{100*npass/attempted:.1f}%)")
    print()
    print(f"validation-only assertions (no validator entry point): {n_valid}"
          f"  - neither passed nor failed")
    print()
    print(f"{'suite':24s}{'pass':>7s}{'fail':>7s}{'skip':>8s}")
    for nm in sorted(per_suite):
        p, f_, s = per_suite[nm]
        print(f"{nm:24s}{p:7d}{f_:7d}{s:8d}")
    if fails:
        print("\nfirst failures:")
        for f_ in fails:
            print("  " + f_)


if __name__ == "__main__":
    main()
