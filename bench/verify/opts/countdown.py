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

# Round-2 expansion (2026-09-11): countdown-adjacent shapes -- zero-trip
# pure loops, multiple counters, nested pure loops, variable bounds, and
# counter reads at small bounds. Appended additively; the original
# directed() is preserved as _base_directed.

_base_directed = directed


def directed():
    cases = _base_directed()
    cases.extend([
        _case("two_counters",
              "t = 0\ni = 0\nj = 0\nwhile i < 100\n  t = t + 1\n"
              "  i = i + 1\n  j = j + 1\nt\n",
              "unsigned long long t=0;for(unsigned long long i=0,j=0;"
              "i<100;i++,j++){t++;}",
              note="second counter alongside the canonical one"),
        _case("nested_pure",
              "t = 0\ni = 0\nwhile i < 50\n  j = 0\n  while j < 20\n"
              "    t = t + 1\n    j = j + 1\n  i = i + 1\nt\n",
              "unsigned long long t=0;for(unsigned long long i=0;i<50;i++)"
              "for(unsigned long long j=0;j<20;j++){t++;}",
              note="pure loop nested in pure loop"),
        _case("zero_trip_pure",
              "t = 0\ni = 0\nwhile i < 0\n  t = t + 1\n  i = i + 1\nt\n",
              "unsigned long long t=0;for(unsigned long long i=0;i<0;i++)"
              "{t++;}",
              note="zero-trip pure countdown loop"),
        _case("var_bound_pure",
              "t = 0\nn = 50\ni = 0\nwhile i < n\n  t = t + 1\n  i = i + 1\nt\n",
              "unsigned long long t=0,n=50;for(unsigned long long i=0;"
              "i<n;i++){t++;}",
              note="pure countdown against a variable bound"),
        _case("mentions_i_bound1",
              "t = 0\ni = 0\nwhile i < 1\n  t = t + i\n  i = i + 1\nt\n",
              "unsigned long long t=0;for(unsigned long long i=0;i<1;i++)"
              "{t=t+i;}",
              note="counter-reading body at bound 1"),
        _case("read_after_small",
              "i = 0\nwhile i < 3\n  i = i + 1\nt = i\nt\n",
              "unsigned long long i=0;for(;i<3;i++){}"
              "unsigned long long t=i;",
              expect="mismatch",
              note="ADVERSARIAL: counter read after loop (small bound) -- "
                   "same unsoundness family as read_after"),
    ])
    return cases
