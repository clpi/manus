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
# Round-2 expansion (2026-09-11): chained algebraic identities --
# identities applied in sequence, and through reassociation shapes, so a
# simplifier that fires once but not twice (or that misfires inside a
# chain) is caught. Appended additively; the original directed() is
# preserved as _base_directed.

_base_directed = directed


def _schain(cid, x0, idol_body, cbody, note=""):
    idol = f"x = {x0}\n" + idol_body + "r\n"
    return {"id": f"simp/{cid}", "idol": idol, "ret": "r",
            "cbody": cbody, "cret": "r", "signed": False,
            "full": True, "note": note}


def directed():
    cases = _base_directed()
    chains = [
        ("add0_mul1", "a = x + 0\nr = a * 1\n",
         "unsigned long long x=123456789ULL,a=x+0ULL,r=a*1ULL;",
         "(x+0)*1"),
        ("subself_add0", "a = x - x\nr = a + 0\n",
         "unsigned long long x=123456789ULL,a=x-x,r=a+0ULL;",
         "(x-x)+0"),
        ("mul1_sub0", "a = x * 1\nr = a - 0\n",
         "unsigned long long x=123456789ULL,a=x*1ULL,r=a-0ULL;",
         "(x*1)-0"),
        ("add0_add0", "a = x + 0\nr = a + 0\n",
         "unsigned long long x=123456789ULL,a=x+0ULL,r=a+0ULL;",
         "(x+0)+0"),
        ("mul0_add", "a = x * 0\nr = a + 5\n",
         "unsigned long long x=123456789ULL,a=x*0ULL,r=a+5ULL;",
         "(x*0)+5"),
        ("zeroadd_mul1", "a = 0 + x\nr = a * 1\n",
         "unsigned long long x=123456789ULL,a=0ULL+x,r=a*1ULL;",
         "(0+x)*1"),
        ("nested3", "a = x + 0\nb = a * 1\nr = b - 0\n",
         "unsigned long long x=123456789ULL,a=x+0ULL,b=a*1ULL,r=b-0ULL;",
         "((x+0)*1)-0"),
        ("max_subself", "r = x - x\n",
         "unsigned long long x=4294967295ULL,r=x-x;",
         "max 32-bit literal minus itself"),
        ("max_mul0", "r = x * 0\n",
         "unsigned long long x=4294967295ULL,r=x*0ULL;",
         "max 32-bit literal times zero"),
        ("subself_addx", "a = x - x\nr = a + x\n",
         "unsigned long long x=42ULL,a=x-x,r=a+x;",
         "(x-x)+x recovers x"),
    ]
    for cid, body, cb, note in chains:
        x0 = 4294967295 if cid.startswith("max") else \
            (42 if cid == "subself_addx" else 123456789)
        cases.append(_schain(cid, x0, body, cb, note=note))
    return cases
