"""Constant folding: `r = C1 op C2` for op in {+, -, *} is evaluated at
compile time by foldop(). Division is deliberately never folded.

What must hold: folded result == runtime 64-bit result, observed through
the exit code (low 8 bits) and, with full=True, through all 8 byte slices.

Known limitation: host-side compile-time arithmetic
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
                              "arithmetic wraps at 32 bits (host compile-time wrap)"))
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

# Round-2 expansion (2026-09-11): reassociation-shaped constant folds.
# Chains of literal ops fold pairwise at compile time with 32-bit host
# arithmetic; each boundary case below pins the true 64-bit result against
# the folded one. Cases tagged known-32bit-limitation mismatch today and
# flip to passing the day the host goes 64-bit. Appended additively; the
# original directed() is preserved as _base_directed.

_base_directed = directed

_KNOWN32 = ("known-32bit-limitation: compile-time arithmetic wraps at "
            "32 bits (see bench/README.md Known limitations)")


def _chain(cid, idol, cbody, full=False, signed=False, note=""):
    return {"id": f"fold/{cid}", "idol": idol, "ret": "r",
            "cbody": cbody, "cret": "r", "signed": signed,
            "full": full, "note": note}


def directed():
    cases = _base_directed()
    # reassociation chains crossing the 32-bit fold boundary (full=True:
    # exit-code mode is blind to these by construction).
    boundary = [
        ("addwrap0", "r = 4294967295 + 1\nr = r + 1\nr\n",
         "unsigned long long r = 4294967295ULL + 1ULL; r = r + 1ULL;"),
        ("addwrap1", "r = 4000000000 + 4000000000\nr = r + 5\nr\n",
         "unsigned long long r = 4000000000ULL + 4000000000ULL; r = r + 5ULL;"),
        ("addwrap2", "r = 2147483647 + 2147483647\nr = r + 3\nr\n",
         "unsigned long long r = 2147483647ULL + 2147483647ULL; r = r + 3ULL;"),
        ("mulwrap0", "r = 100000 * 100000\nr = r * 3\nr\n",
         "unsigned long long r = 100000ULL * 100000ULL; r = r * 3ULL;"),
        ("mulwrap1", "r = 65536 * 65536\nr = r * 2\nr\n",
         "unsigned long long r = 65536ULL * 65536ULL; r = r * 2ULL;"),
        ("mulwrap2", "r = 4294967295 * 4294967295\nr = r + 0\nr\n",
         "unsigned long long r = 4294967295ULL * 4294967295ULL; r = r + 0ULL;"),
        ("rightlean0", "r = 4294967295 + 1\nr = 1 + r\nr\n",
         "unsigned long long r = 4294967295ULL + 1ULL; r = 1ULL + r;"),
        ("subwrap0", "r = 4294967295 + 5\nr = r - 3\nr\n",
         "unsigned long long r = 4294967295ULL + 5ULL; r = r - 3ULL;"),
        ("addwrap3", "r = 4294967295 + 4294967295\nr = r + 1\nr\n",
         "unsigned long long r = 4294967295ULL + 4294967295ULL; r = r + 1ULL;"),
        ("mulwrap3", "r = 3000000000 * 3\nr = r + 7\nr\n",
         "unsigned long long r = 3000000000ULL * 3ULL; r = r + 7ULL;"),
        ("nestmul0", "r = 4294967295 + 1\nr = 2 * r\nr\n",
         "unsigned long long r = 4294967295ULL + 1ULL; r = 2ULL * r;"),
        ("nestmul1", "r = 2000000000 + 2000000000\nr = 5 * r\nr\n",
         "unsigned long long r = 2000000000ULL + 2000000000ULL; r = 5ULL * r;"),
        ("nestadd0", "a = 3000000000 + 2000000000\nr = a + 100\nr\n",
         "unsigned long long a = 3000000000ULL + 2000000000ULL, r = a + 100ULL;"),
        ("nestadd1", "a = 100000 * 100000\nb = 200000 * 200000\nr = a + b\nr\n",
         "unsigned long long a = 100000ULL * 100000ULL, "
         "b = 200000ULL * 200000ULL, r = a + b;"),
    ]
    for cid, idol, cbody in boundary:
        cases.append(_chain(cid, idol, cbody, full=True, note=_KNOWN32))
    # negative folds through chains.
    cases.append(_chain(
        "negchain0", "r = 5 - 10\nr = r - 3\nr\n",
        "long long r = (long long)5 - 10; r = r - 3;",
        full=True, signed=True, note=_KNOWN32))
    cases.append(_chain(
        "negchain1", "r = 0 - 1\nr = r - 1\nr\n",
        "long long r = (long long)0 - 1; r = r - 1;",
        full=True, signed=True, note=_KNOWN32))
    # sanity chains: folds are exact here, must pass in exit-code mode.
    sanity = [
        ("ok0", "r = 1 + 2\nr = r + 3\nr\n",
         "unsigned long long r = 1ULL + 2ULL; r = r + 3ULL;"),
        ("ok1", "r = 10 - 4\nr = r - 3\nr\n",
         "unsigned long long r = 10ULL - 4ULL; r = r - 3ULL;"),
        ("ok2", "r = 2 * 3\nr = r * 4\nr\n",
         "unsigned long long r = 2ULL * 3ULL; r = r * 4ULL;"),
        ("ok3", "r = 100 + 200\nr = r + 300\nr\n",
         "unsigned long long r = 100ULL + 200ULL; r = r + 300ULL;"),
        ("ok4", "r = 6 + 7\nr = 5 + r\nr\n",
         "unsigned long long r = 6ULL + 7ULL; r = 5ULL + r;"),
        ("ok5", "r = 20 - 8\nr = r + 4\nr\n",
         "unsigned long long r = 20ULL - 8ULL; r = r + 4ULL;"),
        ("ok6", "r = 7 * 6\nr = r * 5\nr\n",
         "unsigned long long r = 7ULL * 6ULL; r = r * 5ULL;"),
        ("ok7", "r = 1000 + 2000\nr = r - 500\nr\n",
         "unsigned long long r = 1000ULL + 2000ULL; r = r - 500ULL;"),
        ("ok8", "r = 9 + 9\nr = r + 9\nr\n",
         "unsigned long long r = 9ULL + 9ULL; r = r + 9ULL;"),
        ("ok9", "r = 50 - 25\nr = r - 10\nr\n",
         "unsigned long long r = 50ULL - 25ULL; r = r - 10ULL;"),
        ("ok10", "r = 11 * 11\nr = r + 11\nr\n",
         "unsigned long long r = 11ULL * 11ULL; r = r + 11ULL;"),
        ("ok11", "r = 100 + 100\nr = 1000 - r\nr\n",
         "unsigned long long r = 100ULL + 100ULL; r = 1000ULL - r;"),
        ("ok12", "a = 2 + 3\nb = 4 + 5\nr = a * b\nr\n",
         "unsigned long long a = 2ULL + 3ULL, b = 4ULL + 5ULL, r = a * b;"),
        ("ok13", "r = 8 * 9\nr = 7 * r\nr\n",
         "unsigned long long r = 8ULL * 9ULL; r = 7ULL * r;"),
        ("ok14", "r = 3 * 100\nr = r + 200\nr\n",
         "unsigned long long r = 3ULL * 100ULL; r = r + 200ULL;"),
        ("ok15", "r = 8 + 8\nr = r + 8\nr\n",
         "unsigned long long r = 8ULL + 8ULL; r = r + 8ULL;"),
        ("ok16", "r = 3 * 3\nr = r * 3\nr\n",
         "unsigned long long r = 3ULL * 3ULL; r = r * 3ULL;"),
        ("ok17", "r = 4 * 4\nr = r * 4\nr\n",
         "unsigned long long r = 4ULL * 4ULL; r = r * 4ULL;"),
        ("ok18", "r = 12 + 12\nr = r - 12\nr\n",
         "unsigned long long r = 12ULL + 12ULL; r = r - 12ULL;"),
    ]
    for cid, idol, cbody in sanity:
        cases.append(_chain(cid, idol, cbody,
                            note="exact reassociation fold, must pass"))
    return cases
