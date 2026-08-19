# PERF-MONOTONE program

Durable program for historical compiler exploitation and monotone performance
admission in Idol. Canonical main never loses an already-known lawful
realization or an already-measured performance point merely because a new
experiment lands.

## Principle

A known compiler technique is not adopted by slowly rediscovering it under a new
name. The route is:

    known technique
        → recover its semantic precondition
        → express that precondition in Idol facts
        → reuse/adapt the mature algorithm as a realization producer
        → prove its output equivalent
        → retain it alongside other candidates

The opposite — rejecting a technique because it is "LLVM-like" and then
rebuilding it under a new Idol name — is forbidden.

## Compiler Prior Art Matrix

No agent may implement a known optimization family until this row identifies the
best existing implementation or reference and explicitly states what Idol adds
beyond it.

| technique | precedent | reference | idol prerequisite | idol implementation | status | benchmark |
| --- | --- | --- | --- | --- | --- | --- |
| scalar evolution / recurrence analysis | classic IV/SCEV compilers | LLVM `ScalarEvolution` | recurrence facts | pending | missing | affine recurrence |
| general SCCP / fact fixed point | Wegman/Zadeck lineage | LLVM/GCC | fact lattice | pending | partial | constant paths |
| demand/cardinality analysis a la GHC | GHC/functional compilers | GHC | demand and use-cardinality facts | GAP-175/187 | research | packs/calls |
| escape + scalar replacement | JVM/Go/LLVM/GCC | HotSpot escape analysis, LLVM SROA | escape, uniqueness, and place facts | pending | partial | structs |
| ThinLTO-style semantic summaries | LLVM | Clang ThinLTO | semantic summaries and world edges | pending | missing | incremental SHC |
| PIC/IC/deoptimization machinery | Self/Smalltalk/JVM/JS VMs | Self/V8 | runtime relation and shape cardinality | GAP-182 | research | polymorphic calls |
| mature vectorizer legality/cost models | GCC/LLVM | LLVM `LoopVectorize`/`SLPVectorizer` | independence, shape, and stride facts | pending | missing | SIMD loops |
| polyhedral dependence/scheduling | Pluto/Polly/MLIR | LLVM Polly | affine dependence and domain facts | pending | missing | loop tiling/fusion |
| worker/wrapper/call-pattern specialization | GHC | GHC | demand/cardinality and pack facts | GAP-175/187 | research | packs/calls |
| dynamic superinstructions / code copying | Forth/VMs | Gforth | application sequence and demand facts | pending | missing | cold code |
| e-graph implementation techniques | equality saturation | egg | witnessed equivalence facts | GAP-178 | research | transformations |
| synthesizing superoptimization | STOKE/Souper/Minotaur | Souper/Minotaur | exact equivalence and cost facts | pending | missing | residual hot regions |
| Mercury mode/determinism machinery | Mercury/logic compilers | Mercury | relation slot-mode and solution-cardinality facts | GAP-187 | research | solution cardinality |
| CMUCL-style efficiency diagnostics | CMUCL/SBCL | CMUCL | missing frontier fact, demand, and payoff | pending | missing | semantic frontier |
| incremental dependency invalidation | ThinLTO/build systems | Clang ThinLTO, Ninja | stable semantic IDs and fact provenance | pending | missing | incremental SHC |

## Mandatory Performance Monotonicity Contract

Every merge touching parser, sema, graph, demand, realization, codegen, runtime,
foreign bridge, optimizer, proof engine, layout, or ABI must satisfy:

| invariant | required condition |
| --- | --- |
| semantic correctness | new selected realization produces the admitted observation |
| capability monotonicity | every previously accepted semantic application remains realizable unless C0 deliberately invalidated it |
| candidate monotonicity | new knowledge may add candidates or prove candidates invalid; it cannot silently delete valid alternatives |
| performance monotonicity | previous best known candidate stays available until new candidate proves dominance |
| coverage monotonicity | backend acceptance set may not shrink |
| compile-performance monotonicity | semantic change does not unexpectedly increase compiler work without an explicit trade |
| memory monotonicity | no hidden large compiler/runtime memory regression |
| artifact-size monotonicity | tracked independently |
| startup monotonicity | tracked independently |
| runtime monotonicity | latency/throughput tracked independently |
| evidence monotonicity | newer claims cannot rely on weaker evidence than the candidate they replace |
| explainability | every selection names competing candidate, decisive dimensions, and evidence |
| revision binding | every performance fact names exact source revision + target + environment |
| statistical validity | noise is resolved rather than interpreted as improvement |
| lower-bound status | known floor reported separately from merely "fast" |
| loss visibility | no aggregate score may conceal a regression |

Main goes green only if every row above passes.

## What remains genuinely Idol-specific

The novelty budget is concentrated here:

- one semantic id
- exact lawset-preserving foreign ingestion
- world/projection algebra
- demand as observer quotient
- cross-law semantic equivalence
- representation theorem FFI
- persistent cross-representation equivalence
- semantic continuity across revisions
- fact provenance/trust
- candidate-set monotonicity
- value-of-information optimization
- semantic lower-bound debt
- cross-law fusion
- semantic frontier exposed to agents

Everything below that should be aggressively informed by prior art.

## Three hard monotonicity laws

- knowledge: stronger facts never destroy semantic truth
- capability: stronger compiler knowledge never destroys a lawful realization
- performance: a new candidate never replaces a known-better candidate without evidence
