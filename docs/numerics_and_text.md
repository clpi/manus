# The numerics and text pages, MEASURED

Pass 106 asked for "the boring tables experts check FIRST, because they reveal
whether the designer has met the edge cases," and for twenty MUNDANE programs
beside the golden corpus of lexers and LEB128.

Every number below was **measured against the compiler**, never read off the
spec. The command is `zig build boring-corpus`; the fixtures are
`examples/boring/*.id` (the twenty programs) and `examples/table/*.id` (one
per row here). Each fixture asserts a VALUE, and the gate compares stdout
against the `-- expect:` line the fixture carries.

**The fixtures assert what the compiler DOES, not what the spec says.** That
makes `examples/table` a change detector: a red row means the behaviour moved
and this page must be re-measured in the same commit. It is not a conformance
claim, and several rows are marked below as contradicting Pass 100 §12.

**The gate cannot write to what it measures.** Every binary lands in
`/tmp/duo-boring-corpus`. The first capability table in this repository ran
`duo fmt` over the corpus it was counting and reported 46/0 from evidence it
had destroyed.

Measured 2026-08-08 against `canonical-to-relation` at `afad6f3`, ReleaseFast,
macOS aarch64, C backend.

---

## 1. The boring corpus — 10 of 20

Ten everyday programs compile and print the value they declare. **Ten do not,
and those are the deliverable.** Each red row names a construct that
lexer-shaped code never exercised. No program was bent away from canonical
Pass 100 spelling to make it pass; where the canonical spelling fails, the
fixture keeps the canonical spelling and the row stays red.

| program | state | what it needs |
|---|---|---|
| binarysearch | **pass** | `5 0 1` |
| bubblesort | **pass** | `1 4 12 25 33 38 55 71 88 97` |
| calculator | **pass** | `5 12 14` |
| csvread | **pass** | `3 bob 30` |
| fib | **pass** | `6765 6765` |
| jsonparse | **pass** | `2 7` |
| matmul | **pass** | `30 36 42 66 81 96 102 126 150` |
| palindrome | **pass** | `1 0` |
| quicksort | **pass** | `1 33 97` |
| wordfreq | **pass** | `3 1 8` |
| anagram | FAIL | rebinding a `for` loop's name after the loop |
| caesar | FAIL | `by` is unusable as an identifier |
| fizzbuzz | FAIL | a string that is exactly one interpolation hole |
| linecount | FAIL | `s[i]` in a function that also calls `s:split` |
| linkedlist | FAIL | a self-referencing descriptor field |
| primes | FAIL | `t:push(v)` — §0.9's own spelling |
| reverse | FAIL | `str{ b }` — §0.8's own spelling |
| roman | FAIL | SIGSEGV; two calls to a str-returning function |
| stackqueue | FAIL | `t:push(v)` / `t:pop()` |
| temperature | FAIL | float rendering (see row N-8) |

### The ten failures, with minimal repros

Every repro below is the smallest program that reproduces it. **These are filed
for the live compiler agents; nothing here was fixed by this work.**

---

**F-1 · `#t` on a table does not compile.** §12 LEN makes `#` a family face
over every container; it works on `str` and not on a table.

```duo
main = (): i64
    xs = { 5, 3, 8 }
    n = #xs
    print("{n}")
    0
end
```
```
error: passing 'int64_t *' to parameter of incompatible type 'lua_Value'
       double n = lua_len_num(__dt_xs);
```
The same shape breaks `xs:len()` and `xs:sort()`. A native table reaches the
boxed-value helpers with a raw pointer.

---

**F-2 · `t:push(v)` is a SILENT NO-OP on an empty table, and a compile error on
a non-empty one.** §0.9 spells growth exactly this way. This is the worst row
on the page, because one half of it produces a wrong answer with exit 0.

```duo
main = (): i64
    xs = { }
    xs:push(7)
    n = xs[1]
    print("{n}")
    0
end
```
Prints `nil`, exit 0. Seeding the literal instead:
```duo
    xs = { 1 }
    xs:push(7)
```
```
error: initializing 'lua_Value' with an expression of incompatible type 'int64_t *'
```
`primes` and `stackqueue` both fail through this. `primes` reports `0 0` where
the sieve should report `10 29` — a silent wrong answer, not a crash.

---

**F-3 · Assigning into an empty table literal does not compile.** The empty
literal is typed as a string list.

```duo
main = (): i64
    xs = { }
    xs[1] = 7
    print("{xs}")
    0
end
```
```
error: incompatible integer to pointer conversion assigning to 'const char *' from 'int'
       xs_items[xs_len++] = 7;
```

---

**F-4 · `str{ b }` does not exist.** §0.8 states the migration in so many
words: `string.char(b)` → `str{ b }`. The target spelling is undeclared.

```duo
main = (): i64
    b = 104
    s = str{ b }
    print("{s}")
    0
end
```
```
error: call to undeclared function 'str'
```
`reverse` and `caesar` both need it. There is currently **no way to build a
string from a byte** in canonical Duo.

---

**F-5 · `by` cannot be an identifier.** No §1 row reserves it, and the
diagnostic does not say it is reserved.

```duo
f = (a: i64, by: i64): i64
    a + by
end
```
```
error: expected 'name', got 'by'
```
Renaming to `step` compiles and runs. §0.1 sends qualifiers to a LEVEL, so
short English words are exactly what canonical Duo produces — a silently
reserved one is a trap.

---

**F-6 · A string literal that is EXACTLY one interpolation hole takes the
hole's type, not `str`.**

```duo
main = (): i64
    i = 5
    word = "{i}"
    word = "fizz"
    print("{word}")
    0
end
```
```
error: incompatible pointer to integer conversion assigning to 'int64_t' from 'char[5]'
```
`word = "n{i}"` — the same hole with one extra byte — compiles and prints
`fizz`. So `"{i}"` is being folded to `i` rather than to its rendering. This is
what breaks `fizzbuzz`, and it is a §0.7 construct ("`"…{expr}…"` always").

---

**F-7 · Rebinding a name after a `for` loop used it does not compile.**

```duo
main = (): i64
    for i = 1, 3
        print("{i}")
    end
    i = 0
    print("{i}")
    0
end
```
```
error: use of undeclared identifier 'i'
```
The loop name is emitted scoped to the loop, but the later binding is emitted
as an assignment rather than a declaration. `anagram` fails through this.

---

**F-8 · `s[i]` does not compile in a function that also calls `s:split`.**

```duo
main = (): i64
    text = "a b"
    b = text[0]
    for w in text:split(" ")
        b = b + 0
    end
    print("{b}")
    0
end
```
```
error: initializing 'lua_Value' with an expression of incompatible type 'const char'
```
The split face forces the string to the boxed representation; the byte index
still expects the native one. `linecount` fails through this. The same error
appears for `s[0]` on an EMPTY string literal and for a negative index.

---

**F-9 · A self-referencing descriptor field does not compile.**

```duo
node: {
    value: i64
    next: node
}
main = (): i64
    a: node = { value = 10 }
    v = a.value
    print("{v}")
    0
end
```
```
error: unknown type name 'duo_rec_cb8cabafc4c6db01'
```
The record struct is emitted without a forward declaration, so it cannot name
itself. Every linked structure — list, tree, trie — is blocked on this one.

---

**F-10 · Two calls to a str-returning function that reads a string table →
SIGSEGV.**

```duo
conv = (n: i64): str
    value = { 10, 9, 5, 4, 1 }
    glyph = { "X", "IX", "V", "IV", "I" }
    out = ""
    left = n
    for i = 1, 5
        v = value[i]
        g = glyph[i]
        while left >= v
            out = "{out}{g}"
            left = left - v
        end
    end
    out
end
main = (): i64
    a = conv(14)
    b = conv(40)
    print("{a} {b}")
    0
end
```
Exits 139. **One** call returns `XIV` correctly. A smaller sibling shows the
same corruption without crashing — a string read from a table declared INSIDE a
function renders as its ADDRESS:

```duo
conv = (n: i64): str
    g = { "a", "b" }
    out = ""
    for i = 1, n
        p = g[i]
        out = "{out}{p}"
    end
    out
end
main = (): i64
    a = conv(1)
    b = conv(2)
    print("{a} {b}")
    0
end
```
prints `4362735412 43627354124362735414`. The same table at FILE scope is fine,
so the lifetime of a function-local string table is the suspect. `roman` fails
through this.

---

## 2. Numerics, as measured

`C` marks a row that contradicts Pass 100 §12 or a Pass 107 decision. The
verdict column says whether the contradiction is a **compiler bug** (spec is
right, implementation is wrong) or a **spec defect** (implementation is
defensible, the spec text is not met and should be restated).

| # | row | measured | spec | verdict |
|---|---|---|---|---|
| N-1 | i64/u64 mixing | `5 + 3u` = `8`, no diagnostic, signed domain | no §12 row | — |
| N-2 | u64 above i64 max | `18446744073709551615` prints `-1`; hex path identical | no §12 row | **C · compiler bug** |
| N-3 | integer overflow | `i64max + 1` = `-9223372036854775808`, silent wrap | §12 **OVFL**: "checked default" | **C · compiler bug** |
| N-4 | division sign | `-7/2` = `-3`, `7/-2` = `-3` | B-4 "truncates" | ok |
| N-5 | modulo sign | `-7%2` = `-1`, `7%-2` = `1` (dividend's sign) | B-4 "% matches" | ok (diverges from Lua, which floors) |
| N-6 | i64/i64 truncation | `7/2` = `3`, `1/2` = `0` | B-4 | ok |
| N-7 | float → int | `2.7` → `2`, `-2.7` → `-2` (toward zero) | no §12 row | — |
| N-8 | float rendering | `0.1` → `0.10000000000000001`; `1.0/3.0` → `0.33333333333333331`; `1.0` → `1`; `1e3` → `1000` | Pass 107: shortest round-trip, Ryu-class | **C · compiler bug** |
| N-9 | NaN | `n == n` false; `n < 1.0` false; `n > 1.0` false; renders `nan` | IEEE | ok |
| N-10 | `-0.0` | renders `-0`; `-0.0 == 0.0` true | IEEE | ok |
| N-11 | float literal typing | `1.0` and `1e3` render with no fractional part, so a float is indistinguishable from an i64 at the value face | — | **C · spec defect** (§12 has no rendering row) |
| N-12 | precision above 2^53 | i64 `9007199254740993` holds and renders exactly | — | ok |
| N-13 | `>>` on signed | `-8 >> 1` = `9223372036854775804` — LOGICAL, not arithmetic | no §12 row | **C · spec defect** |
| N-14 | shift ≥ width | `1 << 64` = `1`, `1 << 65` = `2` — taken mod 64, silently | no §12 row | **C · spec defect** |
| N-15 | integer ÷ 0 | `1 / 0` and `1 % 0` return **garbage** (`8281414992` on one run), exit 0 | Pass 107: faults at sealed boundaries | **C · compiler bug** |
| N-16 | float ÷ 0 | `1.0 / 0.0` = `inf` | IEEE | ok |

N-15 is **not fixtured** — the garbage is not stable between runs, so no
`-- expect:` line can hold it. That instability is itself the finding.

### The §12 contradictions, argued

- **N-3 (OVFL).** §12 says "overflow = realization dimension: **checked
  default**; wrap/saturate by policy fact". Measured: wrap, unconditionally, no
  policy fact consulted, no diagnostic. **Compiler bug** — the spec states a
  default the implementation never had. The wrap is not defensible as a
  deliberate choice because there is no way to ask for the checked behaviour.
- **N-2.** The u64 descriptor keeps the bit pattern (arithmetic on it is
  correct) but its rendering goes through the signed path. **Compiler bug**:
  the descriptor exists and its value face is wrong, which is narrower and more
  clearly wrong than a missing feature.
- **N-8 (Pass 107 float rendering).** Pass 107 decided shortest round-trip is
  the `to(str)` edge. Measured: `printf("%.17g")`-shaped output.
  **Compiler bug** — Pass 107 is law and the implementation predates it.
- **N-13, N-14 (shifts).** §12 has **no shift row at all**, so nothing is
  contradicted textually — but a language that publishes B-1..B-15 and OVFL and
  omits shift semantics has an omission an expert checks for first.
  **Spec defect**: §12 needs a `SHIFT` row, and it should say which of logical
  and arithmetic `>>` is, and what happens at or above the width. The current
  behaviour (logical, mod-64) is C's, chosen by inheritance rather than decision.
- **N-11.** Same shape: §12 has no rendering row, and the measured behaviour
  makes `1.0` and `1` the same text. **Spec defect** — Pass 107 fixed the
  *precision* question and left the *float-ness* question open.
- **N-15.** Pass 107 says contract violations at sealed boundaries are FAULTS
  that unwind the world. Integer division by zero produces uninitialised memory
  and exit 0, which is neither a fault, nor a routed failure, nor a diagnosis.
  **Compiler bug**, and the most dangerous row on this page.

---

## 3. Text, as measured

| # | row | measured | spec | verdict |
|---|---|---|---|---|
| T-1 | `#s` with an embedded NUL | `#"a\0b"` = `3` — byte count, not strlen | §12 LEN | ok (was red earlier this epoch) |
| T-2 | `s[i]` is the byte, 0-based | `#"é"` = `2`, `s[0]` = `195`, `s[1]` = `169` | §0.8, B-1 | ok |
| T-3 | byte vs char vs grapheme | only bytes exist; no char face, no grapheme face, no default iteration | §12 TEXT "iteration explicit by unit; no default iter" | ok |
| T-4 | normalization | none. NFC "é" (2 bytes) and NFD "e"+U+0301 (3 bytes) are different strings and compare unequal | §12 TEXT is silent | ok — but §12 should SAY so |
| T-5 | invalid UTF-8 | `"\xff\xfe"` is an ordinary 2-byte string; indexes fine; nothing validates | §12 TEXT: "str = bytes **& utf8.valid**" | **C · spec defect** |
| T-6 | `s[i]` past the end | `#"ab"` = 2; `s[2]` = `0` (the NUL terminator); `s[99]` returned `110`, out-of-bounds memory | B-1 says "no negative wrapping" and nothing about the high end | **C · compiler bug** |
| T-7 | `s[-1]` | does not compile, and the diagnostic is a raw C type error | B-1 "no negative wrapping" | ok in outcome, **compiler bug** in diagnosis |
| T-8 | `s[0]` on `""` | does not compile — same raw C type error | — | **C · compiler bug** |
| T-9 | string comparison | `"Z" < "a"` true; `"ab" < "abc"` true; **`"\xc3\xa9" < "z"` true** | B-11 "byte-lexicographic" | **C · compiler bug** |
| T-10 | split, empty fields | `"a,,b":split(",")` → 3 parts, the middle one `""` | — | ok |
| T-11 | numeric str-edge, above 2^53 | `"9007199254740993":to(i64)` = `9007199254740993` | B-13 | ok — **repaired 2026-08-08**, gap[081] |
| T-12 | numeric str-edge, not a number | `"abc":to(i64)` FAULTS and names the input; `"12x"` faults on the trailing text; `"0"` still answers `0` | B-13/B-14 | **partly repaired 2026-08-08** — it refuses, but it TEARS DOWN rather than routing a failure |

### The §12 contradictions, argued

- **T-5.** §12 TEXT literally reads "str = bytes & utf8.valid". Measured: the
  second conjunct is enforced nowhere — not at a literal, not at an index, not
  at a length. Marked **spec defect** rather than compiler bug on purpose:
  making every `str` carry a validity invariant would make `s[i]` on a
  half-written buffer impossible, and the byte semantics of T-2/T-3 are the
  more valuable half. §12 should say `str = bytes`, and give validity to a
  `utf8` face that is asked for.
- **T-6.** `s[99]` on a 2-byte string read adjacent memory and answered `110`.
  There is no bounds check on the high end at all. **Compiler bug**, and it is
  a memory-safety hole rather than a semantics question. Note the interaction
  with T-1: `#s` is now a real byte count, so `s[#s]` reads one past the last
  byte and answers the terminator rather than failing.
- **T-9.** Byte-lexicographic ordering is UNSIGNED. `0xC3` must sort ABOVE
  `0x7A`. Measured, it sorts below — which is exactly what comparing `char` as
  SIGNED does. So every non-ASCII string sorts before every ASCII one.
  **Compiler bug** against B-11, one character wide in the fix.
- **T-11, T-12, REMEASURED 2026-08-08 (gaps/GAP-081.md step 1).** Both rows
  above were understated, and the understatement mattered. The edge did route
  through a double and did answer `0` for input holding no number — but only
  where it ran at all: in a full-native module `to(i64)` on a typed `str`
  reached `lua_to_num`, which such a module never declares, so the conversion
  did not COMPILE, in either face. That is why gap[081] reads the corpus census
  of 1647 operation-first conversions against one canonical one as partly
  capability rather than taste. The commonest conversion direction in this tree
  is parsing a number, and its canonical spelling did not build.

  It now lowers to a plain-C integer parse. T-11 keeps all 64 bits, so
  `"9007199254740993"` round-trips. T-12 refuses: no digits, or text after the
  digits, or a value out of range, and it names which. `"0"` still answers `0`,
  which is the row that keeps the refusal honest — a parse failure and a
  successful parse of zero are no longer the same observation.

  **T-12 IS ONLY PARTLY REPAIRED, and the remaining half is stated rather than
  hidden.** B-14 says an unconsumed failure DIAGNOSES and routes; this FAULTS —
  §0c world teardown, the end of a demand that cannot be met. Teardown is
  admitted by the boring rulings and is categorically better than a silent `0`,
  but it is not a routed `i64 | error`, and it will not be until the failure
  position has somewhere to go at a conversion edge. `zig build convert-proof`
  asserts the exit code so the distinction stays visible.

  `tonumber` was repaired earlier this epoch to return nil rather than 0;
  `to(i64)` is the same defect at the canonical spelling and reached its repair
  a whole epoch later, through a census that looked like a taste problem.

---

## 4. The Pass 107 rows

| row | decided | measured | verdict |
|---|---|---|---|
| hashing | keyed, SipHash-class, key is a world fact | `hash(x)` is undeclared; `s:hash()` returns **`nil` silently**, exit 0 | not implemented; the silent nil is the compiler bug |
| panics | no panic — only diagnoses, routed failures, and FAULTS that unwind the world; `abort` is a capability | `abort()` is undeclared. No fault machinery exists: N-15 shows a contract violation producing garbage and exit 0 | not implemented |
| recursion / stack | TAIL guaranteed; non-tail depth METERED with a routed `error.depth`; **no SIGSEGV as an API** | TAIL holds — 10,000,000 tail frames return the right answer. Non-tail: **SIGSEGV, no diagnosis** | **contradicted** |
| float rendering | shortest round-trip, Ryu-class, locale never involved | 17 significant digits (N-8); locale is indeed never involved | **contradicted** |

**The recursion row needs its measurement stated carefully, because a naive
test passes it by accident.** A single call site to a non-tail recursive
function is flattened by the host C compiler, so `body(1000000)` alone returns
`1000000` with exit 0 and looks like evidence of metering. It is not. Two call
sites defeat the flattening and the real frames appear:

```duo
body = (n: i64): i64
    if n <= 0
        return 0
    end
    1 + body(n - 1)
end
main = (): i64
    a = body(1)
    b = body(1000000)
    print("{a} {b}")
    0
end
```
Exits **139**. There is no `error.depth`, no world fact bounding depth, and no
way to observe the limit before it is hit — the failure mode is the signal
Pass 107 names as forbidden. This is the same trap recorded in
`docs/` as the perf-repro lesson: a single-call-site loop measures the
optimizer, not the language.

---

## 5. Spec constructs that DO NOT EXIST

Measured the same way, and belonging on this page for the same reason: an
expert checks whether the document's own examples run.

| construct | source | measured |
|---|---|---|
| `todo(gap[nn])` | §0.2 and §19 — the stub spelling the audit asks diffs to cite | `error: call to undeclared function 'todo'` |
| `str{ b }` | §0.8 — the stated replacement for `string.char` | `error: call to undeclared function 'str'` |
| `s[i, j]` | §12 B-1 — "half-open; `s[i, j] = [i, j)`" | `error: expected ']', got ','` |
| `t:push(v)` | §0.9 | silent no-op, or a C type error (F-2) |
| `t:sort(cmp)` | §0.9, §0.6 | C type error (F-1) |
| `#t` on a table | §12 LEN | C type error (F-1) |
| `abort` | Pass 107 — "a capability" | undeclared |
| `hash` | Pass 107 | undeclared ambient; `s:hash()` silently nil |

---

## 6. Two more compiler bugs found while measuring

These are not §12 rows; they surfaced because the fixtures put two of something
in one function, which lexer-shaped fixtures rarely do.

**X-1 · The SECOND string-literal comparison in a function answers wrong.**

```duo
main = (): i64
    a = 0
    if "a" < "b"
        a = 1
    end
    b = 0
    if "Z" < "a"
        b = 1
    end
    print("{a} {b}")
    0
end
```
Prints `1 0`. `"Z" < "a"` is TRUE, and the same comparison ALONE in a program
prints `1`. Swapping the print order to `"{b} {a}"` prints `0 1`, so it is the
second comparison that is wrong and not the reporting. This is separate from
T-9 (the signed-byte ordering), which is wrong even in isolation.

**X-2 · Two `to(i64)` calls in one function do not compile.**

```duo
main = (): i64
    a = to(i64)("42")
    b = to(i64)("7")
    print("{a} {b}")
    0
end
```
```
error: call to undeclared function 'lua_to_num'
```
One call compiles and runs. Binding the strings first does not help. The helper
is emitted for the first use and referenced without declaration for the second.

---

## 7. What would move these numbers

In the order that unblocks the most red rows per fix:

1. **F-1/F-2/F-3, the native-table faces** — `#t`, `t[i] = v` on an empty
   literal, `t:push`, `t:sort`, `t:len`. Four boring programs and every
   growable-collection program in existence. `t:push` being a silent no-op
   should be raised to a diagnostic first, before it is made to work: a wrong
   answer with exit 0 is worse than a red build.
2. **F-4, `str{ b }`** — there is currently no way to build a string from a
   byte, which blocks every encoder, every cipher, every formatter.
3. **F-9, self-referencing descriptor fields** — blocks every linked structure.
4. **T-9 and X-1, string comparison** — one is a signedness fix, the other is a
   codegen fix, and together they make sorting strings trustworthy.
5. **N-15, integer division by zero** — the only row on this page that returns
   uninitialised memory.
6. **N-3 and Pass 107's fault machinery** — the two are the same work.
