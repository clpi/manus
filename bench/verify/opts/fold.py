"""Constant folding: `r = C1 op C2` for op in {+, -, *} is evaluated at
compile time by foldop(). Division is deliberately never folded.

What must hold: folded result == runtime 64-bit result, observed through
the exit code (low 8 bits) and, with full=True, through all 8 byte slices.

Known limitation (bench/README.md): host-side compile-time arithmetic
wraps at 32 bits, so folded values whose true result needs bits 32..63
are truncated. Those cases are directed, labelled, and run with full=True
because exit-code comparison is BLIND to them (mod 2^32 preserves the
low 8 bits). Random cases stay below 2^32 and are expected to pass.
"""
import random as _random

OPT = "fold"
DESC = "constant folding of literal+literal for +,-,* (foldop)"


def _mk(cid, a, op, b, full=False, note="", signed=False):
    idol = f"r = {a} {op} {b}\nr\n"
    if signed:
        cbody = f"long long r = (long long){a}LL {op} (long long){b}LL;"
    else:
        cbody = f"unsigned long long r = {a}ULL {op} {b}ULL;"
    return {"id": f"fold/{cid}", "idol": idol, "ret": "r",
            "cbody": cbody, "cret": "r", "signed": signed,
            "full": full, "note": note}


def directed():
    cases = []
    # sanity: small folds every compiler must get right
    for i, (a, op, b) in enumerate(
            [(0, "+", 0), (1, "+", 2), (100, "*", 200),
             (1000, "-", 1), (7, "*", 6), (123456, "+", 654321)]):
        cases.append(_mk(f"sanity{i}", a, op, b))
    # 32-bit wrap boundary: true result needs bits >= 32.
    # folded with 32-bit host wrap -> wrong above bit 31; needs --full.
    for i, (a, op, b) in enumerate([
            (2147483647, "+", 1),   # 2^31 -> wraps to -2^31 at compile time
            (4294967295, "+", 1),   # 2^32-1 + 1 -> folds to 0
            (4294967295, "*", 2),   # low 32 bits accidentally right; hi wrong
            (4294967296, "+", 5),   # literal itself wraps at parse (num)
            (100000000000, "+", 7), # 1e11: literal wraps at parse
    ]):
        cases.append(_mk(f"wrap{i}", a, op, b, full=True,
                         note="known-32bit-limitation: compile-time "
                              "arithmetic wraps at 32 bits (see "
                              "bench/README.md Known limitations)"))
    # negative folds via `0 - N`: imm() emits movz+movk(hw=1) with no sign
    # extension, so e.g. 0-37 becomes 4294967259 instead of 2^64-37.
    for i, (a, op, b) in enumerate([(0, "-", 1), (0, "-", 37), (5, "-", 10)]):
        cases.append(_mk(f"neg{i}", a, op, b, full=True, signed=True,
                         note="known-32bit-limitation: negative folded "
                              "constants are zero-extended, not sign-extended"))
    return cases


def gen(rng, n):
    cases = []
    ops = ["+", "-", "*"]
    for i in range(n):
        op = rng.choice(ops)
        if op == "*":
            # keep the true product below 2^32 so only folding is tested
            a = rng.randrange(0, 65536)
            b = rng.randrange(0, 65536)
        elif op == "+":
            a = rng.randrange(0, 2**31)
            b = rng.randrange(0, 2**31 - a) if a < 2**31 else 0
        else:
            a = rng.randrange(0, 2**32)
            b = rng.randrange(0, a + 1)
        signed = op == "-" and rng.random() < 0.5
        cases.append(_mk(f"r{i:04d}", a, op, b, signed=signed))
    return cases
