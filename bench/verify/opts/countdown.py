"""Countdown-loop transform (purecount in native.id, v5).

A `while i < N` loop whose body is exactly `i = i + 1` plus statements
that never mention `i`, with `i = 0` immediately before the loop, is
compiled to a do-while that counts the *bound register* down: the `i=i+1`
is skipped and `i` keeps its initial value 0.

Soundness conditions the transform assumes but does NOT check:
  (a) the increment appears exactly once per iteration,
  (b) `i` is never observed after the loop.

Cases tagged EXPECT-MISMATCH assert the transform is currently UNSOUND
there: a mismatch is the suite working as designed (each is a compiler
bug report). All other cases must pass bit-for-bit.
"""
import random as _random

OPT = "countdown"
DESC = "pure-counter countdown loops (purecount, v5)"


def _case(cid, idol, cbody, cret="t", signed=False, full=False, note="",
          expect="pass"):
    return {"id": f"countdown/{cid}", "idol": idol, "ret": "t",
            "cbody": cbody, "cret": cret, "signed": signed,
            "full": full, "note": note, "expect": expect}


def directed():
    cases = []
    # Pure counter, result not read after: the advertised win. Must pass.
    cases.append(_case(
        "pure", "t = 0\ni = 0\nwhile i < 1000\n  t = t + 1\n  i = i + 1\nt\n",
        "unsigned long long t=0;for(unsigned long long i=0;i<1000;i++){t++;}",
        note="canonical countdown shape"))
    # ADVERSARIAL: loop var observed after the loop. Countdown leaves i=0;
    # source semantics give i=100. EXPECT-MISMATCH (bug).
    cases.append(_case(
        "read_after",
        "i = 0\nwhile i < 100\n  i = i + 1\nt = i\nt\n",
        "unsigned long long i=0;while(i<100){i=i+1;} unsigned long long t=i;",
        note="ADVERSARIAL: counter read after loop",
        expect="mismatch"))
    # ADVERSARIAL: increment appears twice per iteration. purecount only
    # checks each body row *equals* `i = i + 1`, not that it appears once,
    # so the transform fires and runs 100 iterations instead of 50.
    # EXPECT-MISMATCH (bug).
    cases.append(_case(
        "double_inc",
        "t = 0\ni = 0\nwhile i < 100\n  t = t + 1\n  i = i + 1\n  i = i + 1\nt\n",
        "unsigned long long t=0;unsigned long long i=0;"
        "while(i<100){t++;i=i+1;i=i+1;}",
        note="ADVERSARIAL: two increments per iteration",
        expect="mismatch"))
    # Non-unit stride: purecount requires the exact text `i = i + 1`,
    # so no transform fires. Must pass (slower, but correct).
    cases.append(_case(
        "stride2", "t = 0\ni = 0\nwhile i < 1000\n  t = t + 1\n  i = i + 2\nt\n",
        "unsigned long long t=0;for(unsigned long long i=0;i<1000;i+=2){t++;}",
        note="non-unit stride defeats purecount"))
    # Non-zero init: requires the row before `while` to be exactly `i = 0`.
    cases.append(_case(
        "nonzero_init",
        "t = 0\ni = 5\nwhile i < 100\n  t = t + 1\n  i = i + 1\nt\n",
        "unsigned long long t=0;for(unsigned long long i=5;i<100;i++){t++;}",
        note="init != 0 defeats purecount"))
    # Body mentions i elsewhere: hassub kills purity.
    cases.append(_case(
        "mentions_i",
        "t = 0\ni = 0\nwhile i < 100\n  t = t + i\n  i = i + 1\nt\n",
        "unsigned long long t=0;for(unsigned long long i=0;i<100;i++){t+=i;}",
        note="body reads i: no transform"))
    # Nested countdowns: inner bound register must be reloaded on every
    # outer iteration (the bound load is emitted inline at the while line).
    cases.append(_case(
        "nested",
        "t = 0\no = 0\nwhile o < 30\n  i = 0\n  while i < 40\n"
        "    t = t + 1\n    i = i + 1\n  o = o + 1\nt\n",
        "unsigned long long t=0;for(unsigned long long o=0;o<30;o++)"
        "for(unsigned long long i=0;i<40;i++){t++;}",
        note="nested pure counters, per-level bound registers"))
    # Variable bound: bound register holds a variable, not a constant.
    cases.append(_case(
        "var_bound",
        "t = 0\nn = 37\ni = 0\nwhile i < n\n  t = t + i\n  i = i + 1\nt\n",
        "unsigned long long t=0;unsigned long long n=37;"
        "for(unsigned long long i=0;i<n;i++){t+=i;}",
        note="variable loop bound"))
    return cases


def gen(rng, n):
    cases = []
    for i in range(n):
        N = rng.randrange(10, 5000)
        C = rng.randrange(1, 1000)
        op = rng.choice(["+", "*"])
        if op == "+":
            body, cbody = f"t = t + {C}", f"t += {C}ULL;"
        else:
            body, cbody = f"t = t * {C} + 1", f"t = t * {C}ULL + 1;"
        idol = (f"t = 0\ni = 0\nwhile i < {N}\n  {body}\n  i = i + 1\nt\n")
        cases.append(_case(
            f"r{i:04d}", idol,
            f"unsigned long long t=0;for(unsigned long long i=0;i<{N};i++)"
            f"{{{cbody}}}",
            note="random pure counter"))
    return cases
