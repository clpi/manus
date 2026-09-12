"""Division: `x / C` and `C / x` lower to ARM64 sdiv. Division is
deliberately excluded from constant folding (o != 47), so `8 / 2` with
literal operands still goes through registers.

ARM64 sdiv truncates toward zero, matching C signed division, for all
nonzero divisors. Division by zero is never generated (would trap on
both sides, but the suite only asserts equal *defined* behavior).
"""
import random as _random

OPT = "div"
DESC = "integer division lowering (sdiv, never folded)"


def _mk(cid, idol, cbody, cret="r", signed=False, full=False, note=""):
    return {"id": f"div/{cid}", "idol": idol, "ret": "r",
            "cbody": cbody, "cret": cret, "signed": signed,
            "full": full, "note": note}


def directed():
    cases = [
        _mk("lit", "r = 8 / 2\nr\n",
            "unsigned long long r = 8ULL / 2ULL;",
            note="literal division still goes through sdiv"),
        _mk("one", "x = 123456789\nr = x / 1\nr\n",
            "unsigned long long x=123456789ULL,r=x/1ULL;"),
        _mk("self", "x = 98765\nr = x / x\nr\n",
            "unsigned long long x=98765ULL,r=x/x;"),
        # negative dividend via folded `0 - N`: exercises the known
        # negative-constant-fold bug THROUGH division (visible even in
        # exit-code mode, unlike pure fold cases).
        _mk("neg",
            "t = 0 - 37\nr = t / 3\nr\n",
            "long long t = (long long)0 - 37; long long r = t / 3;",
            cret="r", signed=True, full=True,
            note="known-32bit-limitation: negative folded dividend "
                 "is zero-extended, not sign-extended"),
        _mk("neg2",
            "t = 0 - 100\nr = t / 7\nr\n",
            "long long t = (long long)0 - 100; long long r = t / 7;",
            cret="r", signed=True, full=True,
            note="known-32bit-limitation"),
    ]
    return cases


def gen(rng, n):
    cases = []
    for i in range(n):
        if rng.random() < 0.7:
            x = rng.randrange(0, 2**32)
            c = rng.choice([1, 2, 3, 7, 10, 100, 1000])
            idol = f"x = {x}\nr = x / {c}\nr\n"
            cbody = f"unsigned long long x={x}ULL,r=x/{c}ULL;"
            cases.append(_mk(f"r{i:04d}", idol, cbody))
        else:
            c = rng.randrange(1, 2**32)
            x = rng.randrange(1, 100000)
            idol = f"x = {x}\nr = {c} / x\nr\n"
            cbody = f"unsigned long long x={x}ULL,r={c}ULL/x;"
            cases.append(_mk(f"d{i:04d}", idol, cbody))
    return cases
