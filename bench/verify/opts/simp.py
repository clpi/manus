"""Algebraic simplification (simpadd/simpmul in calc()):
    x+0 -> x,  0+x -> x,  x-0 -> x,  x-x -> 0,
    x*1 -> x,  1*x -> x,  x*0 -> 0,  0*x -> 0.

All identities are sound over 64-bit two's-complement arithmetic,
including x-x -> 0 (no NaN-like hazards on integers). Randomized x
covers loop-carried values as well as plain constants.
"""
import random as _random

OPT = "simp"
DESC = "algebraic identities: x+0, x-0, x-x, x*1, x*0 (simpadd/simpmul)"

_TEMPLATES = [
    ("x + 0", "x + 0"), ("0 + x", "0 + x"),
    ("x - 0", "x - 0"), ("x - x", "x - x"),
    ("x * 1", "x * 1"), ("1 * x", "1 * x"),
    ("x * 0", "x * 0"), ("0 * x", "0 * x"),
]


def _mk(cid, tmpl, cval, note=""):
    iexpr, cexpr = tmpl
    idol = f"x = {cval}\nr = {iexpr}\nr\n"
    cbody = f"unsigned long long x = {cval}ULL; unsigned long long r = {cexpr};"
    # C: mirror the identity literally so the oracle does not itself fold
    # in a way that masks a bug; -O3 will fold it, which is fine.
    return {"id": f"simp/{cid}", "idol": idol, "ret": "r",
            "cbody": cbody, "cret": "r", "signed": False,
            "full": True, "note": note}


def directed():
    cases = []
    for i, tmpl in enumerate(_TEMPLATES):
        cases.append(_mk(f"zero{i}", tmpl, 0))
        cases.append(_mk(f"max{i}", tmpl, 4294967295))
    # x-x with a loop-carried (non-constant) x: the identity must hold
    # for values only known at runtime.
    cases.append({
        "id": "simp/carried", "ret": "r", "signed": False, "full": True,
        "note": "x-x with runtime-carried x",
        "idol": ("x = 7\n"
                 "i = 0\n"
                 "while i < 1000\n"
                 "  x = x * 3\n"
                 "  x = x + 1\n"
                 "  i = i + 1\n"
                 "r = x - x\n"
                 "r\n"),
        "cbody": ("unsigned long long x=7;for(unsigned long long i=0;i<1000;i++)"
                  "{x=x*3ULL;x=x+1ULL;} unsigned long long r = x - x;"),
        "cret": "r",
    })
    return cases


def gen(rng, n):
    cases = []
    for i in range(n):
        tmpl = rng.choice(_TEMPLATES)
        cval = rng.choice([0, 1, rng.randrange(0, 2**32),
                           rng.randrange(0, 2**64)])
        cases.append(_mk(f"r{i:04d}", tmpl, cval))
    return cases
