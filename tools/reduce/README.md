# tools/reduce/idol — source reducer for the Idol toolchain

Minimizes an `.id` program while an external predicate holds. Tooling only;
no language or compiler semantics. (Pickle Mission A.)

## Usage

```sh
export IDOL="/path/to/zig-out/bin/idol"
tools/reduce/idol <input.id> -p '<predicate text>' [-o out.id]
```

The predicate runs as `sh -c "<predicate>" reduce-sh <candidate-path>`, so
`"$1"` inside the predicate text is the candidate file. Predicate exit 0
means the failure-of-interest is PRESENT. Examples:

```sh
# exact first diagnostic (family F3b)
-p '"$IDOL" compile "$1" --emit obj -o /tmp/r.o 2>&1 | grep -q "global-init-not-constant:g"'

# compiler crash / internal error (family F5)
-p '"$IDOL" compile "$1" --emit obj -o /tmp/r.o 2>&1 | grep -q "InvalidAggregateFact"'

# wrong answer against an oracle expectation (program prints 8, oracle says 6)
-p '[ "$("$IDOL" run "$1" 2>/dev/null)" = "8" ]'
```

## Admission controls

The reducer refuses to start unless the predicate holds on the original
AND fails on a blank floor — an always-true (broken) predicate is rejected
before any reduction runs. A candidate is accepted only if it is non-empty
and strictly smaller; a different earlier failure simply fails the
predicate, so reduction never trades one failure for another.

## Passes

1. ddmin over lines (chunk deletion; explicit range emission — degenerate
   `1,0p` ranges are no-ops on some seds and would fake deletions).
2. Per-line simplification (non-zero numeric literal → 0), comment and
   blank stripping fall out of pass 1.

## Selftest

`tools/reduce/selftest` proves the five required behaviors: an exact
diagnostic reduces, a crash reduces, a wrong answer reduces, a deliberately
broken predicate is rejected, and the original still fails after reduction
(restoration control).

## Proven theorems (2026-08-17, idol @ 4724e589, compiler ee08e553)

- F3b `global-init-not-constant:g` — 4 lines (tools/reduce/fixtures/global/write.id).
- F5 `InvalidAggregateFact` compiler crash — parser.id 1792 → 27 lines;
  the crash survives hoisting the tail nested call, so it lives in the
  chained condition applications (`lexer.peek(lx).kind`).
- F2 `application-operand-abi` — graph.id is line-irreducible at 112
  lines: EVERY line deletion breaks the predicate. The missing fact is
  module-granularity, not local — a finding, not a failure.

## Performance (2026-08-17)

Guarded inert pre-pass: comment-only and blank lines are stripped in one
shot and verified with a single predicate call (reverted untouched if the
failure does not survive — sound for text predicates too). On
lib/compiler/parser.id (438 inert lines of 1792) the F5 crash reduction
went 12m54s -> 3m54s and landed a strictly smaller theorem (1792 -> 11
lines, recursive relation + nested application as argument). Predicate
call counts are emitted in the closing report line.

## Negative result: parallel chunk sweeps (2026-08-17)

Batch-testing ddmin round candidates 8-wide produced the identical
reduction but ran SLOWER (5m06s vs 3m54s on parser.id) with system time
exploding (1m44s -> 5m38s): `idol compile` serializes on the compiler's
own cache/lock, so parallel candidates contend instead of overlapping.
Candidate-level parallelism is structurally pointless until compiles run
lock-free; the guarded inert pre-pass remains the throughput lever.
