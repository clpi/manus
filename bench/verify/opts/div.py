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
# Round-2 expansion (2026-09-11): rewrite-sensitive directed cases for the
# e-graph and loop-eval workstreams. Appended additively; the original
# directed() is preserved as _base_directed. Division chains reassociate
# soundly under trunc-toward-zero division ((x/a)/b == x/(a*b)), so these
# cases must pass whether or not the rewrite fires -- and the 32-bit
# divisor-product traps catch a folding-width bug the day it lands.

_base_directed = directed


def _chain(cid, x, a, b, note="", full=False):
    idol = f"x = {x}\nt = x / {a}\nr = t / {b}\nr\n"
    cbody = f"unsigned long long x={x}ULL,t=x/{a}ULL,r=t/{b}ULL;"
    return _mk(cid, idol, cbody, full=full, note=note)


def directed():
    cases = _base_directed()
    # (x/3)/7 chains: sound reassociation target, must agree either way.
    for i, x in enumerate([0, 1, 2, 20, 21, 22, 100, 1000000, 4294967295]):
        cases.append(_chain(f"chain37_{i}", x, 3, 7,
                            note="division chain (x/3)/7: sound reassoc target"))
    # power-of-two chains.
    for i, x in enumerate([0, 1, 2, 3, 4, 5, 6, 7, 8, 4294967295]):
        cases.append(_chain(f"chain22_{i}", x, 2, 2,
                            note="division chain (x/2)/2"))
    # constant-dividend chains.
    for i, x in enumerate([1, 2, 3, 7]):
        cases.append(_mk(f"cdiv_{i}", f"x = {x}\nt = 100 / x\nr = t / 3\nr\n",
                         f"unsigned long long x={x}ULL,t=100ULL/x,r=t/3ULL;",
                         note="constant-dividend chain (100/x)/3"))
    # 32-bit divisor-product traps: folding (c1*c2) at 32 bits miscompiles.
    cases.append(_mk(
        "trap_prod10",
        "x = 4294967295\nt = x / 100000\nr = t / 100000\nr\n",
        "unsigned long long x=4294967295ULL,t=x/100000ULL,"
        "r=t/100000ULL;",
        full=True,
        note="ADVERSARIAL: (x/100000)/100000 must not fold the divisor "
             "product 100000*100000=1e10 at 32 bits (wraps to 1410065408)"))
    cases.append(_mk(
        "trap_prod12",
        "x = 4294967295\nt = x / 1000000\nr = t / 1000000\nr\n",
        "unsigned long long x=4294967295ULL,t=x/1000000ULL,"
        "r=t/1000000ULL;",
        full=True,
        note="ADVERSARIAL: divisor product 1e12 does not fit 32 bits"))
    cases.append(_mk(
        "trap_prodzero",
        "x = 4294967295\nt = x / 65536\nr = t / 65536\nr\n",
        "unsigned long long x=4294967295ULL,t=x/65536ULL,"
        "r=t/65536ULL;",
        full=True,
        note="ADVERSARIAL: divisor product 65536*65536 wraps to 0 at 32 "
             "bits -- folding it would divide by zero"))
    # div-then-multiply-back is NOT the identity (truncation).
    for i, x in enumerate([10, 11, 12]):
        cases.append(_mk(
            f"divmulback_{i}", f"x = {x}\nt = x / 3\nr = t * 3\nr\n",
            f"unsigned long long x={x}ULL,t=x/3ULL,r=t*3ULL;",
            note="(x/3)*3 != x: trunc division is not invertible"))
    # big divisors, full 64-bit observability.
    cases.append(_mk(
        "bigdiv0", "x = 4294967295\nr = x / 1000003\nr\n",
        "unsigned long long x=4294967295ULL,r=x/1000003ULL;",
        full=True, note="divisor > 2^20"))
    cases.append(_mk(
        "bigdiv1", "x = 4294967295\nr = x / 4294967295\nr\n",
        "unsigned long long x=4294967295ULL,r=x/4294967295ULL;",
        full=True, note="max 32-bit divisor"))
    cases.append(_mk(
        "bigdiv2", "x = 4294967295\nr = x / 7\nr\n",
        "unsigned long long x=4294967295ULL,r=x/7ULL;",
        full=True, note="max 32-bit dividend"))
    # negative chains through the known 32-bit fold limitation.
    cases.append(_mk(
        "negchain0", "x = 0 - 100\nt = x / 3\nr = t / 7\nr\n",
        "long long x=(long long)0-100,t=x/3,r=t/7;",
        signed=True, full=True,
        note="known-32bit-limitation: negative folded dividend is "
             "zero-extended, then chained through division"))
    cases.append(_mk(
        "negchain1", "x = 0 - 37\nt = x / 5\nr = t / 2\nr\n",
        "long long x=(long long)0-37,t=x/5,r=t/2;",
        signed=True, full=True,
        note="known-32bit-limitation"))
    # extra (x/5)/11 pair.
    for i, x in enumerate([0, 4294967295]):
        cases.append(_chain(f"chain511_{i}", x, 5, 11,
                            note="division chain (x/5)/11"))
    # extra constant-dividend and div-mul-back probes.
    cases.append(_mk("cdiv_4", "x = 10\nt = 100 / x\nr = t / 3\nr\n",
                     "unsigned long long x=10ULL,t=100ULL/x,r=t/3ULL;",
                     note="constant-dividend chain (100/10)/3"))
    cases.append(_mk("divmulback_3", "x = 13\nt = x / 3\nr = t * 3\nr\n",
                     "unsigned long long x=13ULL,t=x/3ULL,r=t*3ULL;",
                     note="(x/3)*3 != x: trunc division is not invertible"))
    return cases
