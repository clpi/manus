# Benchmark suite round 2: adversarial programs (batches 1-3)

Ten new programs for `bench/programs/`, each with a bit-identical C oracle
twin. They target the seven known loss patterns from the 21-round v5
results (commit `85886ee3`): div-by-constant shapes, unpredictable
branches, zero-trip loops, arith reassociation shapes, big-constant
materialization, nested-loop shapes the loop evaluator may miss, and
loop-idiom recognition (the `sum` gap).

Like the sibling's five extended programs (`predbranch mul11 subbig
stride2 startupbig`), these are **opt-in**, not in the default run list:

```
./run.sh --progs "divby7 divmul upbr2 zerotrip2" --compilers "clang"
```

Every program is correctness-gated the same way (Idol and C exit codes
must agree) before it may join the default list.

## Commit status: C oracles only

The `.id` sources are **withheld by the vocabulary gate**
(`gate/vocabulary.sh`): top-level value bindings are fail-closed --
their graph reach/cardinality projection is not exported yet, so no new
`.id` program with bindings can be admitted. This is the same status as
the v5 ten (withheld in `85886ee3`: "vocabulary gate requires
graph-backed admission for bindings") and the sibling's five pairs
(working-tree only). The `.id` files are validated (see below) and kept
in the working tree; the C oracles are committed so the expected
behavior is frozen for repro. The day the gate exports the binding
projection, the `.id` files commit as-is.

## Oracle discipline

Per `docs/design/optimum.md`, every program below carries an oracle
level and a **falsifiable expectation**. All ten use **L1 (idiom
ceiling)**: the oracle is `clang -O3` on the same source -- "beats the
industry", never "literal optimum". If Idol beats the expectation, the
response is not celebration but investigation: either an optimization
landed (good -- update the expectation), or the program does not stress
what we thought (revise the program), or the oracle was wrong (revise
the oracle, per the optimum spec section 2).

| program | loss pattern | falsifiable expectation (L1 vs clang -O3) |
|---|---|---|
| `divby7` | div-by-constant | **Expect loss.** clang lowers `x/7` to magic-multiply (~3-4 cycles/iter); Idol emits `sdiv` (~12-20 cycles, unpipelined). Falsified if Idol median <= clang median: would mean div-by-constant strength reduction landed. |
| `divmul` | div-by-constant + reassociation | **Expect loss.** `(x/3)*3+1` keeps a division in the carried chain. Falsified if Idol wins: check for an unsound `(x/3)*3 -> x` fold (the gate compares exit codes, so a miscompile shows as gate failure, not a win -- a clean win means genuinely faster code, investigate). |
| `upbr2` | unpredictable branches | **Expect loss.** Data-dependent branch taken ~50% (LCG sign bit), asymmetric work both sides; clang goes branchless (`cmov`) or lays out better. Falsified if Idol wins: branch-predictor or layout surprise, investigate. |
| `zerotrip2` | zero-trip loops | **Expect loss.** 10M zero-trip inner loops in do-while form pay the extra initial compare+jump; the bound (`o/10000000`, always 0) is division-opaque to hoisting. Falsified if Idol ties/wins: the loop evaluator learned division-opaque zero-trip bounds. |
| `reassoc` | arith reassociation | **Expect loss-or-tie.** `(x+7)+9000-3` is 3 adds/iter; clang folds to one `add` imm. When the e-graph reassociation workstream lands, expect tie. Falsified by a significant Idol win: measurement artifact or clang pessimization, investigate. |
| `reassocmul` | reassociation + strength reduction | **Expect loss.** `(x*3)*5+1`; clang folds to `x*15` (single mul/lea). Falsified if Idol <= clang: reassociation *and* strength reduction firing through the chain. |
| `bigconst2` | big-constant materialization | **Expect loss-or-tie.** `+2000000000`/`-1000000000` need multi-instruction materialization (`movz`/`movk`); clang does the same. The margin measures materialization quality directly. |
| `nest3` | nested loops (3-deep) | **Expect loss.** Per-level bound registers + branch overhead over 8M inner iters; clang collapses the nest. Falsified by a tie: the loop evaluator learned 3-deep nests. |
| `nestvar` | nested loops, variable bound | **Expect loss-or-tie.** Triangular loop, inner bound = outer counter: defeats the countdown transform; clang's idiom recognition likely fails here too, so a tie is honest, a loss measures branch overhead. |
| `sumstride` | loop idiom (strided series) | **Expect loss.** clang recognizes the odd-number series `1+3+...+99999999` and runs O(1); Idol runs 50M iterations. Falsified if Idol wins: clang failed the closed form -- investigate, do not celebrate. |

## Validation status

All ten `.id` programs pass the Idol-vs-clang exit-code gate. Note: as
of this writing the harness's step 1 (build `lib/compiler/native.id`
from source) is broken on `origin/main` -- the v6 `native.id` is refused
by every idol binary on disk (DNB011, `checkedBindingI64`, no zig
available to rebuild). Validation above used the last working
combination: v5 `native.id` (at `85886ee3`) compiled with the Sep-9
`zig-out/bin/idol`. Re-gate against the fresh compiler once the
v6/binary mismatch is resolved.
