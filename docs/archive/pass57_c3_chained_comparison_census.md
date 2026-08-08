> **HISTORICAL — superseded by `docs/spec/pass100.md`. Not an architecture input.**

# Pass 57 C3 — chained comparisons: the corpus census

C3 asks whether `0 <= i < n` should graduate from the escape hatch into the
canonical surface, and rules that the question is **a measurement, not a
debate**: the deciding evidence is how often the shape actually occurs, in SHC
source, post-Pass-53.

This is that measurement.

## Ruling

**Stays behind the escape hatch.** The shape does not occur in SHC at all, and
occurs 8 times across every corpus in the repo combined — all 8 in one file,
all 8 the same two-line idiom repeated four times.

## Numbers

Measured 2026-08-07 by `scripts/chained_comparison_census.duo`.

| corpus | files | ` and ` | chained | share |
| --- | --- | --- | --- | --- |
| SHC (`lib/std/compiler`) | 4 | 58 | **0** | 0.0% |
| stdlib (`lib/std`) | 246 | 892 | **8** | 0.9% |
| examples | 340 | 323 | **0** | 0.0% |
| ward (`~/x/ward/src`) | 14 | 307 | **0** | 0.0% |

All 8 sites:

```
lib/std/graphics/gui.duo:94    x <= state.mouse_x and state.mouse_x <= x + w and
lib/std/graphics/gui.duo:95    y <= state.mouse_y and state.mouse_y <= y + h
lib/std/graphics/gui.duo:131   x <= state.mouse_x and state.mouse_x <= x + box_size and
lib/std/graphics/gui.duo:132   y <= state.mouse_y and state.mouse_y <= y + box_size
lib/std/graphics/gui.duo:160   (identical to 94/95)
lib/std/graphics/gui.duo:161
lib/std/graphics/gui.duo:202   (identical to 94/95)
lib/std/graphics/gui.duo:203
```

One idiom — point-in-rect — written out four times in one module, three of the
four byte-identical. That is an argument for a `gui.rect.contains` helper, not
for a language surface. A helper removes all 8 sites; the sugar removes the
`and` but leaves the duplication.

## What was counted

A site is `A op B and B op C` where the **middle term is byte-identical** on
both sides of the `and`, and both operators are ordering operators
(`<`, `<=`, `>`, `>=`). `==` and `!=` do not chain and are excluded.

This is deliberately narrow: it counts only what the sugar would actually
absorb. `a < b and c < d` is not a site; `a < b and b == c` is not a site. A
looser matcher would inflate the number and weaken the evidence in the
direction of the change — the wrong direction for a measurement whose purpose
is to justify *not* changing the language.

The denominator is occurrences of the literal string `" and "`, not `and`
tokens. It is a scale reference for the ratio, not a parse.

## Reproducing

```bash
duo run --backend=c scripts/chained_comparison_census.duo   # builds the scanner
CENSUS_LABEL="SHC (lib/std/compiler)" \
CENSUS_PATHS="$(find lib/std/compiler -name '*.duo' | tr '\n' ' ')" \
  ./chained_comparison_census.out
```

Paths arrive through `CENSUS_PATHS`, not argv, and `std.str` is bound with
`req`. Both are load-bearing, and both were found the hard way:

- **argv reads back nil** in a duo-compiled binary. An argv-driven scanner
  therefore walks zero files and prints `chained-comparison sites: 0` — which
  is very close to the answer C3 expected, and would have been believed.
- **the dotted `std.str.sub` path segfaults**, because `std.str` is a
  native-direct module whose loader returns nil. `global strm = req "std.str"`
  is the working form. This is the same defect that broke the Duo lexer.

The scanner is written in Duo so the repo stays single-language and so the
number is re-derivable rather than asserted.
