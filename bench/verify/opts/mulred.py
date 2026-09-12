"""Multiply strength reduction (mulred in calc()):
    x * 2^k -> lsl (shift)
    x * 3   -> addsh (x + x<<1)
    x * 5   -> addsh (x + x<<2)
    x * 7   -> lsl + sub (x<<3 - x)
    x * 9   -> addsh (x + x<<3)
    anything else -> generic mul

Both operand orders are tested (mulred is consulted for `x*C` and `C*x`).
All rewrites are exact over 64-bit wrapping arithmetic, so randomized x
up to 2^64-1 must agree bit-for-bit (full=True throughout).
"""
import random as _random

OPT = "mulred"
DESC = "multiply strength reduction: shifts and shift-adds (mulred)"

_REDUCED = [2, 3, 4, 5, 7, 8, 9, 16, 32, 64]
_GENERIC = [6, 10, 11, 12, 13, 14, 15, 17, 100, 1000]


def _mk(cid, c2, c1, swap, note=""):
    if swap:
        iexpr, cexpr = f"{c2} * x", f"{c2}ULL * x"
    else:
        iexpr, cexpr = f"x * {c2}", f"x * {c2}ULL"
    idol = f"x = {c1}\nr = {iexpr}\nr\n"
    cbody = f"unsigned long long x = {c1}ULL; unsigned long long r = {cexpr};"
    return {"id": f"mulred/{cid}", "idol": idol, "ret": "r",
            "cbody": cbody, "cret": "r", "signed": False,
            "full": True, "note": note}


def directed():
    cases = []
    for i, c2 in enumerate(_REDUCED + _GENERIC):
        cases.append(_mk(f"c{i}", c2, 123456789012345, False,
                         note="reduced" if c2 in _REDUCED else "generic"))
        cases.append(_mk(f"c{i}s", c2, 123456789012345, True,
                         note="swapped operand order"))
    # wrap: reduced forms must wrap identically to mul
    cases.append(_mk("wrap3", 3, 18446744073709551615, False,
                     note="x*3 near 2^64-1"))
    cases.append(_mk("wrap7", 7, 18446744073709551615, False,
                     note="x*7 near 2^64-1"))
    return cases


def gen(rng, n):
    cases = []
    for i in range(n):
        c2 = rng.choice(_REDUCED + _GENERIC)
        c1 = rng.choice([0, 1, rng.randrange(0, 2**32),
                         rng.randrange(0, 2**64)])
        swap = rng.random() < 0.5
        cases.append(_mk(f"r{i:04d}", c2, c1, swap))
    return cases
# Round-2 expansion (2026-09-11): multiply chains -- reassociation
# through strength-reduced multiplies. (x*a)*b must equal x*(a*b) over
# 64-bit wrapping arithmetic regardless of which multiplies the compiler
# reduces to shifts/shift-adds. Appended additively; the original
# directed() is preserved as _base_directed.

_base_directed = directed

_KNOWN32 = ("known-32bit-limitation: integer literals above 4294967295 "
            "are truncated at compile time (bench/README.md); this 64-bit "
            "wrap probe mismatches until literals go 64-bit")


def _mchain(cid, x0, ops, note=""):
    # ops: list of (op, const) applied left to right starting from x.
    lines = [f"x = {x0}"]
    assigns = []
    var = "x"
    decls = ["x"]
    for i, (op, c) in enumerate(ops):
        nv = "r" if i == len(ops) - 1 else f"v{i}"
        lines.append(f"{nv} = {var} {op} {c}")
        assigns.append(f"{nv}={var}{op}{c}ULL")
        decls.append(nv)
        var = nv
    idol = "\n".join(lines) + "\nr\n"
    cbody = (f"unsigned long long {','.join(decls)};x={x0}ULL;"
             + ";".join(assigns) + ";")
    return {"id": f"mulred/{cid}", "idol": idol, "ret": "r",
            "cbody": cbody, "cret": "r", "signed": False,
            "full": True, "note": note}


def directed():
    cases = _base_directed()
    pairs = [
        ("p35", 1234567890, [("*", 3), ("*", 5)]),
        ("p53", 1234567890, [("*", 5), ("*", 3)]),
        ("p27", 1234567890, [("*", 2), ("*", 7)]),
        ("p72", 1234567890, [("*", 7), ("*", 2)]),
        ("p99", 1234567890, [("*", 9), ("*", 9)]),
        ("p33", 1234567890, [("*", 3), ("*", 3)]),
        ("p45", 1234567890, [("*", 4), ("*", 5)]),
        ("p1113", 777, [("*", 11), ("*", 13)]),
        ("p66", 1234567890, [("*", 6), ("*", 6)]),
        ("p163", 1234567890, [("*", 16), ("*", 3)]),
        ("p88", 1234567890, [("*", 8), ("*", 8)]),
        ("p911", 1234567890, [("*", 9), ("*", 11)]),
    ]
    for cid, x0, ops in pairs:
        cases.append(_mchain(cid, x0, ops,
                             note="mul chain: reassociation through "
                                  "strength-reduced multiplies"))
    # wrap-around chains near 2^64.
    for cid, x0, ops in [
            ("w35", 18446744073709551615, [("*", 3), ("*", 5)]),
            ("w22", 18446744073709551615, [("*", 2), ("*", 2)]),
            ("w79", 18446744073709551615, [("*", 7), ("*", 9)]),
    ]:
        cases.append(_mchain(cid, x0, ops,
                             note="mul chain wrapping 2^64. " + _KNOWN32))
    # mul chains with a carried add (the arith shape).
    cases.append(_mchain("a0", 1000, [("*", 3), ("+", 7), ("*", 5)],
                         note="(x*3+7)*5: add through the chain"))
    cases.append(_mchain("a1", 4294967295, [("*", 3), ("+", 7), ("*", 5)],
                         note="(x*3+7)*5 near 2^32"))
    # three-deep chain.
    cases.append(_mchain("deep0", 100, [("*", 3), ("*", 5), ("*", 7)],
                         note="three-deep mul chain"))
    # swapped first multiply (C*x form in the chain).
    cases.append({"id": "mulred/swapchain", "idol": "x = 5000\nt = 3 * x\nr = t * 5\nr\n",
                  "ret": "r",
                  "cbody": "unsigned long long x=5000ULL,t=3ULL*x,r=t*5ULL;",
                  "cret": "r", "signed": False, "full": True,
                  "note": "chain starting from swapped multiply"})
    return cases
