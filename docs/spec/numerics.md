# duon 0.1 — Numerics (Pass 108)

**One of the two boring tables experts check first** (Pass 106 §2 item 4).
Everything an implementer must agree with to produce the same bits: what a
literal means, which type an operator selects, where a sign lands, what happens
at the edge of a width, and how a number becomes text. Normative until the
graph service hosts it. Companion: `text.md`.

Rows sourced from Pass 100 §12 (B-4, OVFL) and Pass 107 §3 (FLOAT) are marked;
everything else is decided here.

## 1. The scalar descriptors

```
signed     i8  i16  i32  i64          two's complement, exact width
unsigned   u8  u16  u32  u64          modular, exact width
float      f32 f64                    IEEE-754 binary32 / binary64
```

There is no `int`, no `uint`, no `float`, no `double`, no target-dependent
width. A width is part of the name or it is not a numeric descriptor. `i64` is
the default integer and `f64` the default float, and that default is a
*literal-typing* rule (§3), never a widening rule.

`bool` is not a numeric descriptor. It does not participate in arithmetic and
does not convert to `0`/`1` implicitly (B-2: truthiness is not hookable, and it
does not run in the other direction either).

## 2. Mixing — the rule is that there is no mixing

**Binary arithmetic requires both operands to hold the same descriptor.** There
is no integer promotion, no usual-arithmetic-conversions table, no
signed/unsigned coercion ladder. `i64 + u64` is a diagnostic, not a puzzle. The
repair is a stated edge: `a + b:to(i64)`, and that edge is checked (§7).

The one exception is the one B-13 already carves out: **literals are the special
case.** An untyped integer literal in an operand position adopts the descriptor
of the other operand, if it fits (§3). `x: u8` with `x + 1` is `u8` arithmetic;
`x + 300` is a diagnostic on the literal, not a silent widen.

This is the whole of i64/u64 mixing. Every language that instead publishes a
conversion lattice publishes, one page later, the list of places it surprises
people. Duo declines the lattice.

**Width of an expression is the width of its operands, never of its
destination.** `f: i8, g: i8` ⇒ `f + g` is `i8` arithmetic in every context,
including when the result is bound to an inferred local. A destination of a
different width is an edge, and edges are written.

## 3. Literals

```
17            untyped integer literal
0x1f          untyped integer literal, base 16
0b1010        untyped integer literal, base 2
1_000_000     "_" legal only BETWEEN digits (grammar §1)
1.5   1e9     untyped float literal
1.5f          -- does not exist; f32 comes from the position, not a suffix
```

An untyped literal takes its descriptor from **position**, in this order:

1. a declared shape on the binding or parameter — `a: u8 = 200` ⇒ `u8`;
2. the other operand of a binary operator — `x: f32` in `x * 2` ⇒ `2` is `f32`;
3. the declared return of the enclosing contract, in `return`/tail position;
4. otherwise the **default**: `i64` for an integer literal, `f64` for a float
   literal.

A literal that does not fit its position is a **diagnostic at the literal**, with
the position named. `a: u8 = 300` never wraps, never truncates, never warns —
it is refused. This is the one place where overflow is always a compile-time
question, because both operands are known.

`0.1` is `f64` and is therefore the nearest double to one tenth. Duo does not
pretend otherwise, and §8 makes sure the rendering does not pretend either.

## 4. Division and modulo — B-4, and the signs

**B-4: division is operand-selected.** `i64 / i64` is integer division; any
float operand makes the whole operation float; `%` selects the same way. There
is no `//` and no separate float-division operator.

**Signs: division truncates toward zero, and `%` takes the sign of the
dividend.** The identity that must hold for every integer pair with `b ≠ 0`:

```
(a / b) * b + (a % b)  ==  a
```

| `a` | `b` | `a / b` | `a % b` |
|---|---|---|---|
| 7 | 2 | 3 | 1 |
| −7 | 2 | **−3** | **−1** |
| 7 | −2 | **−3** | **1** |
| −7 | −2 | 3 | −1 |

Truncation, not flooring, is chosen for exactly one reason: it is the rule that
keeps the identity above true *and* keeps `a % b` a remainder rather than a
modulus. A language that floors `%` and truncates `/` — which is what happens
when the two are lowered by different hands — breaks the identity silently, and
the breakage is invisible until a negative reaches it. §10 records that this
tree currently contains that exact defect.

**`%` on floats is the same operation**: the IEEE remainder-after-truncation,
`a − b * trunc(a/b)`, sign of the dividend. `−7.5 % 2.0` is `−1.5`. A *floored*
float `%` beside a truncated integer `%` is two operators wearing one spelling,
and is forbidden.

**Division by zero is a fault** (Pass 107 FAULT), not a value and not silence:
integer `a / 0` and `a % 0` unwind the world with a witness naming the dividend.
Float division by zero is **not** a fault — it is IEEE: `±inf` for a non-zero
dividend, `NaN` for `0.0/0.0`, and the invalid/divide-by-zero flags are raised.
The asymmetry is deliberate: floats have a defined answer, integers do not.

## 5. Overflow — OVFL

Pass 100 OVFL, restated with its edges:

```
checked      DEFAULT. Overflow of +, -, *, <<, negation, and narrowing
             conversions is a FAULT with a witness (the two operands and the
             operator). Not a wrap, not a trap-with-no-message.
wrap         by policy fact: `i64 & wrap` — two's-complement modular
saturate     by policy fact: `i64 & saturate` — clamp to the descriptor's ends
proven away  when range facts on both operands prove the result in range, the
             check is ERASED. This is the common case and it costs nothing.
```

Unsigned types are **not** implicitly modular. `u64 & wrap` is how you ask for
modular arithmetic; a bare `u64` that overflows faults like every other
descriptor. "Unsigned wraps, signed is UB" is C's accident, not a design.

The policy fact travels with the *descriptor*, not the operator, so a wrapping
hash accumulator is declared once and every operation on it inherits the policy
— no `wrapping_add` vocabulary, no operator zoo.

Constant folding obeys the same law: an overflow the compiler evaluates is a
**diagnostic at that expression**, never a wrapped constant and never a
compiler crash.

## 6. Shifts

```
a << n        n ∈ [0, width)        shift amount is a RANGE-FACTED operand
a >> n        n ∈ [0, width)
```

**At and beyond the width is a fault**, not a mask and not undefined behaviour.
`1i64 << 64` faults; it does not answer `1` (mask-mod-64, which is what ARM64
and x86-64 hardware does) and it does not answer `0` (which is what a naive
widening does). Masking is available by asking for it — `a << (n % 64)` — and
then the mask is in the source where a reader can see it.

Where a range fact proves `n < width`, the check is erased and the instruction
is the bare hardware shift. This is the same erasure ladder as §5, and it means
the safe rule costs nothing in the loops that matter.

**`>>` is arithmetic on signed descriptors and logical on unsigned ones.** The
descriptor selects, exactly as it does for `/`:

| expression | descriptor | result |
|---|---|---|
| `-8 >> 1` | `i64` | `-4` (sign-propagating) |
| `-1 >> 63` | `i64` | `-1` |
| `0xFFFFFFFFFFFFFFFF >> 63` | `u64` | `1` |

One spelling, two lowerings, selected by a fact that is written down. A language
in which `>>` means arithmetic in one backend and logical in another has two
languages; §10 records that this tree currently is that language.

**`<<` is the same operation for both signednesses** — bits move left, zeros
enter — but the overflow check differs: signed `<<` faults when a set bit is
shifted out of or into the sign position under the checked policy.

## 7. Conversion and truncation

Every numeric conversion is an **edge**, written `x:to(T)`, never implicit and
never a cast syntax. Three families, with three different failure stances:

```
WIDENING       i8→i64, u8→u64, f32→f64, u32→i64 …  total; cannot fail
NARROWING      i64→i8, u64→u32, i64→u32, f64→f32   FALLIBLE under the checked
                                                    policy; total under
                                                    `& wrap` / `& saturate`
FLOAT ↔ INT    f64→i64, i64→f64                     see below
```

- **Narrowing** under the default checked policy has result shape `T | error` —
  it is a fallible edge, consumed by the B-12 ladder like any other. Under
  `& wrap` it is a total modular truncation of the low bits; under
  `& saturate` it clamps. Range facts erase the check.
- **f64 → integer truncates toward zero** (`3.7 → 3`, `−3.7 → −3`), never
  rounds. Out-of-range and non-finite inputs are **failures**, not
  implementation-defined values: `NaN:to(i64)`, `inf:to(i64)`, and
  `1e30:to(i64)` all yield `error`, they do not yield `0`, `INT64_MIN`, or a
  saturated end. This is the single edge where C's behaviour is most often
  wrong in the field and is therefore worth spelling out.
- **integer → f64** is exact for `|x| ≤ 2^53` and rounds to nearest-even
  outside it. It cannot fail, and the rounding is *not* an error — but a range
  fact that proves exactness is recorded, so `why(precision)` can answer.
- **Integer → integer of the same width, different signedness** is a
  reinterpretation and is fallible for negative or high-bit-set values under the
  checked policy. `(-1i64):to(u64)` is an `error`, not `18446744073709551615`;
  ask for the reinterpretation with `& wrap` if that is what you meant.

**CDR applies.** Inside a declared contract the edge is implied by the demand;
`x:to(i64)` restating a contract the position already declares is ERASED
(CLAUDE.md §0.5). Conversions are written where they carry information and
nowhere else.

## 8. Floats

**IEEE-754, without a fast-math dialect.** Duo does not reassociate float
arithmetic, does not assume finiteness, does not fuse a multiply and an add
unless the source wrote a fused operation, and does not treat `−0.0` as `0.0`.
Every one of those is a *different function*, and a compiler that silently
substitutes one for another is not an optimizer, it is a second language wearing
the first one's syntax. Reassociation and contraction are available as **policy
facts** on the operation, admitted through the edge gate like any other rewrite
(Pass 104), with the legality data attached.

This is the strongest single claim on this page and the one most likely to be
violated by an implementation shortcut. §10 records that it is violated today.

**Rounding** is round-to-nearest, ties-to-even, and the mode is a world fact,
not a process-global mutable register.

### NaN, and what `cmp` and `sort` do with it

The comparison **operators** are IEEE:

| expression, `n` = NaN | result |
|---|---|
| `n == n` | `false` |
| `n != n` | `true` |
| `n < 1.0`, `n > 1.0`, `n <= n`, `n >= n` | `false` |

So `==` on floats is not reflexive, and that is correct: it reports numeric
equality, and NaN is not numerically equal to anything.

The **ordering family** is a different thing and must not inherit that mess,
because a comparator that answers `false` in both directions makes every sort
algorithm undefined. Therefore:

- **`cmp` is a total order.** `a:cmp(b)` on floats uses the IEEE-754 `totalOrder`
  predicate: `−NaN < −inf < … < −0.0 < +0.0 < … < +inf < +NaN`. `−0.0` sorts
  *before* `+0.0` even though `−0.0 == 0.0`, and NaNs sort to the ends by sign.
  It never answers "incomparable", so it is a lawful comparator.
- **`sort` is `cmp`-derived** (B-10) and therefore total, stable, and defined in
  the presence of NaN: NaNs land at the ends, deterministically, and the sort
  does not corrupt the sequence or loop.
- **`min` and `max` are `cmp`-derived too** (B-10), so `min(n, 1.0)` answers by
  the total order — it does not inherit C's `fmin` NaN-swallowing.

The split is the point: `==`/`<` answer the *numeric* question and are allowed
to be partial; `cmp`/`sort`/`min`/`max` answer the *ordering* question and are
required to be total. Naming them differently is how the language avoids the
choice every other language gets wrong in one direction or the other.

**Signed zero** is preserved by arithmetic and by `to(str)` (§9), compares equal
under `==`, and orders under `cmp`. **Infinities** are ordinary values, are
produced by float division by zero and by overflow, and are not faults.

## 9. Rendering — FLOAT (Pass 107 §3)

**`to(str)` on a float is the shortest round-trip decimal (Ryu-class).**
Shortest means: the fewest significant digits that parse back to the identical
bit pattern under `to(f64)`. Not `%.17g`, not a fixed precision, not
"whatever the C library does".

```
0.1        → "0.1"                    not "0.10000000000000001"
0.3        → "0.3"                    not "0.29999999999999999"
1.0        → "1.0"                    the ".0" is KEPT — a float renders as a
                                      float; "1" is the i64 rendering and the
                                      two must not collide
-0.0       → "-0.0"
1e300      → "1e300"
NaN        → "nan"      inf → "inf"      -inf → "-inf"
```

**Locale is never involved.** The decimal separator is `.`, there is no digit
grouping, there is no alternative digit set, and no ambient world fact can
change any of that. This is B-11's sibling: text produced by the language is
byte-determined, and human-facing formatting is a library that takes a locale as
an explicit argument.

`to(str)` on an integer is the exact decimal, with `-` for negatives, no
grouping. **`u64` renders unsigned across its whole range**: `9223372036854775808`
renders as `9223372036854775808`, never as `-9223372036854775808`. A descriptor
whose arithmetic is unsigned and whose rendering is signed is not one
descriptor.

The inverse edge `to(f64)` / `to(i64)` from `str` is fallible (`f64 | error`),
tolerates surrounding whitespace (B-13: "numeric str-edges tolerate
whitespace"), and **fails on trailing garbage** — `"12abc":to(i64)` is an
`error`, not `12`, and `"abc":to(i64)` is an `error`, not `0`. Round-tripping is
exact: `x:to(str):to(f64) == x` for every non-NaN `x`, which is what makes §9's
"shortest" claim testable rather than aesthetic.

## 10. Status in this repository

Measured 2026-08-08 on `canonical-to-relation` at `0cea14c`, `zig build` clean,
every row run through **both** `--backend=c` and `--backend=direct` and read by
value with a positive control. `duo check` was run on every program; where it
answered green on something that then failed, that is recorded, because a green
check on an uncompilable program is worse than a red one.

The short version: **this page is almost entirely SPECIFIED, NOT IMPLEMENTED,
and the two backends disagree on the sign of `%`, on the meaning of `>>`, and on
the precision of `/`.** Naming that is the point of the section.

### Implemented and agreeing with this page

| row | evidence |
|---|---|
| B-4 operand-selected division | `i64/i64` ⇒ `3`; `7.0/2` ⇒ `3.5`; `7/2` ⇒ `3`. Both backends. |
| §4 truncating `/` for negatives | `-7/2` ⇒ `-3`, `7/-2` ⇒ `-3`. Both backends. |
| §7 f64→i64 truncates toward zero | `3.7:to(i64)` ⇒ `3`, `-3.7:to(i64)` ⇒ `-3` (C backend; direct bails). |
| §8 NaN comparison operators | `n==n` false, `n!=n` true, `n<1.0` false, `n>=1.0` false (C backend, `-O0`). |
| §1 the scalar inventory exists | `i8 i16 i32 i64 u8 u16 u32 u64 f32 f64` all parse, lower, and print. |
| §5 `u8` wraps at 8 bits *when the destination is `u8`* | `200 + 100` through a `u8` contract ⇒ `44`. |
| §6 `<<` at width 63 | `1 << 63` ⇒ `-9223372036854775808` in both backends. |

### The backends disagree — every one of these is a silent wrong number

| program | `--backend=c` | `--backend=direct` | this page |
|---|---|---|---|
| `-7 % 2` | **1** (floored) | **−1** (truncated) | −1 |
| `7 % -2` | **−1** (floored) | **1** (truncated) | 1 |
| `9007199254740993 / 1` | **9007199254740992** | 9007199254740993 | 9007199254740993 |
| `-8 >> 1` | **−4** (arithmetic) | **9223372036854775804** (logical) | −4 |
| `-1 >> 63` | **−1** | **1** | −1 |
| `1 << 64` | **−9223372036854775808** | **1** (masked mod 64) | fault |
| `1 << 65` | **−9223372036854775808** | **2** (masked mod 64) | fault |
| `1 >> 64` | **−1** | **1** | fault |
| `i64max + 1` | **−9223372036854775808** (wraps) | **compiler panic** | diagnostic |

Three of these deserve their cause named, because the cause is one line each:

- **`%` disagrees because the two backends implement different operators.** The
  C backend emits `lua_imod_i64`, a *floored* modulus (`src/codegen.zig`
  prelude); the direct backend emits ARM64 `sdiv`/`msub`, a *truncated*
  remainder. `/` truncates in both. So under `--backend=c` the identity
  `(a/b)*b + (a%b) == a` is **false for every negative operand**: `-7/2 = -3`
  and `-7%2 = 1` give `-5`.
- **`/` loses precision because the C backend routes integer division through
  `double`.** The emitted C for `a / b` on two `int64_t` is
  `((double)(a) / (double)(b))` assigned to `int64_t` — correct below 2^53,
  silently wrong above it, and a two-instruction detour besides.
- **`>>` disagrees because the C backend emits raw C `>>` on `int64_t`** (which
  clang implements as arithmetic, and which is *undefined* for a shift count ≥
  64) while the direct backend emits ARM64 `LSR`, which is logical and masks the
  count mod 64. Neither is checked; neither matches §6.

The `i64max + 1` row is a compiler crash, not a wrong answer:
`src/region_transform.zig:166` constant-folds with a plain Zig `a + b` inside
`evalConstBinop`, so the fold panics with `thread N panic: integer overflow` and
dumps a Zig stack trace. §5's "a diagnostic at that expression" is the target.

### Specified and NOT implemented

- **OVFL entirely.** No checked arithmetic anywhere: `i64max + 1` wraps (C) or
  crashes the compiler (direct); `u64max + 1` is `0` in both. There is no
  `& wrap` and no `& saturate` surface — `grep -rl saturat src/*.zig` returns
  **0** files (positive control: the same grep for `overflow` returns 6, and
  `grep -rn @addWithOverflow src/codegen.zig` finds three hits, all
  constant-folding). Overflow is unconditionally modular, which is
  the *policy* branch of OVFL taken as the default.
- **§4 division-by-zero faults.** `7 / 0` and `7 % 0` answer `0` and `7`
  respectively under `--backend=direct`, exit 0, no diagnostic, `duo check`
  green. There is no fault machinery to route to (Pass 107 records FAULT as
  decided-and-unimplemented).
- **§6 shift bounds.** Neither backend checks a shift count.
- **§2 no-mixing.** Not tested against a diagnostic, because there is no
  diagnostic: mixed-width arithmetic lowers through C's usual arithmetic
  conversions. Marked SPECIFIED, NOT DEMONSTRATED.
- **§2 width-of-operands.** Implemented *backwards*: measured, `f: i8, g: i8`
  gives `h: i8 = f + g` ⇒ **−56** and `k = f + g` ⇒ **200**. The emitted C is
  `int8_t h = ((int8_t)((f + g)))` beside `int64_t k = (f + g)` — the width of
  an arithmetic expression is the width of its *destination*, which is C's
  integer-promotion rule leaking through the C backend. §2 says the opposite.
- **§7 fallible narrowing.** `e:to(u8)` from an `i64` does not compile: the C
  backend emits `e__to(lua_val_from_literal("u8", 188920568, 2))`, two
  undeclared C functions and a pointer-shaped integer, after `duo check`
  answered green. `str:to(i64)` likewise emits an undeclared `lua_to_num`.
  Only `f64:to(i64)` works, and it is total, not fallible.
- **§8 IEEE without a fast-math dialect.** Violated at the flag level:
  `src/main.zig:4436-4444` (and `:4409` for `wasm32-wasi`) passes
  **`-ffast-math`, `-ffp-contract=fast`,
  `-fno-trapping-math`, `-fno-math-errno`** to every `--backend=c` compile, on
  every target. Consequence, measured: a program that computes `0.0/0.0` and
  `1.0/0.0` and prints both answers `nan=5.3049894774131808e-315
  inf=5.3049894774131808e-315` at the default `-O3`, and `nan=nan inf=inf` at
  `-O0`. The value is not merely imprecise, it is garbage, and it changes with
  the optimization level. **The C oracle is not an IEEE oracle**, which matters
  beyond this page: Pass 103 §5 licenses the C backend as the differential
  oracle, and for float code that licence is currently void.
- **§8 `cmp`/`sort` totality.** Cannot be demonstrated, because `sort` does not
  work. `t:sort()` on a table of `f64` compiles and is a **silent no-op** —
  `{3.0, 1.0, nan, 2.0}` comes back in input order, `duo check` green. The
  positive control (`{3, 1, 4, 2}`, all integers) does not even build:
  `error: initializing 'lua_Value' with an expression of incompatible type
  'int64_t *'`. So there is no working `sort` to ask a NaN question of, and no
  `cmp` family either. SPECIFIED, NOT DEMONSTRATED — and the float no-op is the
  more dangerous of the two, because it is green all the way to the wrong answer.
- **§9 shortest round-trip.** Not implemented. The float `to(str)` edge is
  `snprintf(b, 48, "%.17g", v)` (the `duo_str_from_f64` prelude), so `0.1`
  renders `0.10000000000000001` and `0.3` renders `0.29999999999999999`. It also
  drops the `.0`: `1.0` renders as `1`, colliding with the `i64` rendering.
  Pass 107's newest ruling, unimplemented on the day it was written — which is
  the honest state and is why it is a row here rather than a claim above.
- **§9 unsigned rendering.** Wrong, and identically wrong in both backends:
  `d: u64 = 9223372036854775808` prints **−9223372036854775808**, while
  `d / 2` correctly prints `4611686018427387904`. Unsigned arithmetic, signed
  rendering.

### Grammar §1 says these lex; they do not

`0b1010` and `1_000_000` are both in the grammar's `number` production and
neither is lexed. `0b1010` splits into `0` and `b1010`; `1_000_000` splits into
`1` and `_000_000`. **`duo check` answers "✓ checked — no errors"** on both, and
the failure arrives from clang as `error: use of undeclared identifier 'b1010'`
against a line number in `/tmp/duo_n24.c`, a file the user did not write. Hex
(`0x1f` ⇒ 31) and `^` as exponentiation (`2 ^ 10` ⇒ 1024) both work.

### What would close the largest share of this page

One ruling, applied twice: **pick the sign convention and lower it once.** The
`%` and `>>` rows above are not two bugs, they are one missing shared lowering
between `src/codegen.zig` and `src/dnir_lower.zig`, and a differential fixture
that runs a negative operand through both backends would have caught all six
rows on the day they diverged. `zig build abi-matrix` and the native
differential exist and are licensed (Pass 103 §5); neither carries a negative
integer.
