| field | value |
|---|---|
| title | Idol Domain-Frontier Capability and Performance Map |
| status | research disposition, not language law and not an implementation claim. |
| repository subject | at . |
| purpose | replace C-centric aspiration with a measurable map of the strongest known implementation in every relevant capability and performance domain. |

| section |
|---|---|
| 1. The governing correction |

| # | directive |
|---|---|
| 1 | C is an important control, not a universal oracle. |

| # | directive |
|---|---|
| 1 | For any fixed workload and observable contract, the comparison target is the **domain-frontier envelope**: the strongest known semantically equivalent implementation, configuration, runtime, library, compiler, schedule, and target available for that domain. |
| 2 | A claim is never admitted because Idol beats a weak C spelling, a default compiler flag, an interpreter, or a baseline tier. |

| # | directive |
|---|---|
| 1 | The envelope is a set, not one language: |

```text
oracle(workload, observations, target)
    = Pareto frontier of every credible equivalent implementation
```

| section |
|---|---|
| 1.1 Project boundary: Wart is external |

| # | directive |
|---|---|
| 1 | Wart is an independent Wasm runtime/compiler, not an Idol target, platform, backend, runtime tier, dependency, or design substrate. |
| 2 | It may enter an Idol comparison set only as an external oracle whose own evidence remains Wart's claim. |
| 3 | A future Wart-in-Idol rewrite is a separate experiment after Wart itself has established the reference frontier and compactness subject; the rewrite must preserve that subject's semantics and earn independent evidence for every gain. |

| # | directive |
|---|---|
| 1 | The frontier includes hand-written and generated implementations, vendor libraries, domain-specific languages, runtimes, optimizing compilers, and physical lower bounds. |
| 2 | Idol may win through information the comparator lacks, work its human author did not perform, runtime facts unavailable ahead of time, or a better algorithm selected under proven conditions. |
| 3 | Each class is reported separately. |

| # | directive |
|---|---|
| 1 | A result remains one of: |

```text
UNMEASURED
MEASURED
REPRODUCED
ADMITTED
SUPERSEDED
```

| # | directive |
|---|---|
| 1 | Only `ADMITTED` evidence may feed public capability or performance claims. |

| section |
|---|---|
| 2. Performance is a vector |

| # | directive |
|---|---|
| 1 | No scalar score is sufficient. |
| 2 | Every benchmark contract records at least: |

| # | directive |
|---|---|
| 1 | steady-state latency and throughput; |
| 2 | startup, warmup, and tail latency; |
| 3 | compile, link, incremental, and installation work; |
| 4 | peak and retained memory; |
| 5 | allocations, copies, and memory traffic; |
| 6 | artifact, relocation, and loaded-code size; |
| 7 | instructions, cycles, branches, misses, spills, and vector occupancy; |
| 8 | energy when measurable; |
| 9 | correctness, safety, determinism, and capability guarantees; |
| 10 | target, ABI, machine, OS, thermal, power, and profile state; |
| 11 | implementation effort and source information supplied; |
| 12 | the exact strongest comparator and physical lower bound. |

| # | directive |
|---|---|
| 1 | A win on one axis does not conceal a loss on another. |

| section |
|---|---|
| 3. Domain-frontier matrix |

| Domain | Leaders and control implementations | Information or freedom they exploit | Idol mechanism to test | Required oracle and admission suite |
|---|---|---|---|---|
| Scalar CPU and systems code | Best of tuned GCC, Clang, ICX, AOCC, Fortran, Rust, Zig, vendor libraries, and hand-written assembly where credible | aliasing law, ranges, calling convention, instruction selection, profile layout, undefined-behavior freedom in C | checked facts, specialization, late ABI and representation choice, own backend plus control backends | SPEC CPU subsets, application kernels, hardware counters, same-algorithm controls, max over tuned pipelines |
| SIMD and SPMD CPU | ISPC, hand-written intrinsics, vectorizing Fortran/C, LLVM/Polly, vendor kernels | lane structure, uniform/varying values, no-alias facts, alignment, trip counts, predication | preserve data-parallel relations before scalar lowering; checked disjoint/range/alignment facts; target-specific realization | ISPC examples, PolyBench/C, vector-library kernels, code inspection and lane-utilization counters |
| GPU, tensor, and accelerator kernels | CUDA, CUTLASS/cuBLAS/cuDNN, Triton, TVM, Halide, Futhark, IREE, hand-tuned kernels | tensor shape, purity, schedule, memory hierarchy, tiling, fusion, target topology, autotuning | graph-level data-parallel relations, library-authored lawful implementations, measured schedule search, multiple lowering representations | vendor libraries and best generated schedules on target-specific suites; never scalar C alone |
| Image and signal pipelines | Halide, FFTW, Spiral, vendor DSP libraries | algorithm/schedule separation, size-specialized codelets, fusion, locality, vectorization | staged relation specializations, implementation families with agreement/equivalence evidence, measured search | Halide apps, FFTW/Spiral fixtures, vendor libraries, same-output and same-algorithm controls |
| Query, analytics, and database execution | Umbra/HyPer, DuckDB, ClickHouse, Velox, DataFusion, vendor engines | relational algebra, cardinality, indexes, layout, vectorization, query compilation and adaptive planning | preserve questions and demand as relations; select algorithms and layouts from facts; low-latency own backend | TPC-H/TPC-DS-like controlled subsets and operator microbenchmarks; report planning and compile latency separately |
| Dynamic-language specialization | Julia, LuaJIT, V8, Graal/Truffle, PyPy, optimized Smalltalk lineage | observed types/classes, inline caches, profiles, guarded assumptions, deoptimization, partial evaluation | dynamic Lua floor, AOT specialization where known, optional runtime profile tier, guarded specialization and deopt | language-relevant benchmark corpus with startup/warmup/peak separated; compare against each runtime’s strongest tier |
| Compile and iteration latency | Go, Zig, Cranelift/Winch, Umbra-style custom backends, incremental query compilers | simple pipelines, low optimization budgets, caching, dependency precision | tiered realization budgets, copy-and-patch/baseline tier, content-addressed graph slices, incremental fact closure | Sightglass-like per-phase measurements, Rust/Go/Zig build cases, cold and incremental runs |
| Memory management and mutation | Rust, Hylo/MVS, Koka/Lean/Perceus, MLton, tracing collectors, arenas, C/C++ | ownership, no-sharing guarantees, uniqueness/reuse, regions, escape analysis, generational behavior | preserve Lua semantics first; infer sealed no-alias/acyclic/unique regimes; select stack, region, arena, RC, tracing, or explicit placement as lawful | allocation-heavy and cyclic workloads; peak memory, latency tails, copies, collector/RC overhead, cycle behavior |
| Safety and verification | Rust, SPARK/Ada, CompCert, CakeML, CHERI research, sanitizers and translation validators | ownership, contracts, proof, capability hardware, verified lowering | checked facts, bounded unsafe operations, translation validation, differential/metamorphic testing, capability worlds | miscompilation fuzzing, safety suites, proof/validation coverage, runtime overhead and rejected-safe-program rate |
| Determinism and reproducibility | Wasm deterministic profiles, Java strict FP, Nix/Bazel/Guix, rr/Pernosco for replay | fixed arithmetic law, hermetic inputs, recorded nondeterminism | content-addressed builds; explicit deterministic execution profiles; world facts for time/random/I/O; record external observations when demanded | cross-target bitwise tests, artifact reproducibility, replay tests; build determinism never implies free runtime replay |
| Incremental compilation and persistent code identity | Salsa/rustc, Roslyn, Unison, DBSP/differential dataflow systems | query dependency graphs, content addressing, incremental view maintenance | one semantic authority with exact dependency closure; incremental projections and evidence invalidation | large-project edit traces, affected-slice closure, cache hit correctness, semantic rename/move tests |
| Concurrency and distributed systems | Erlang/BEAM, Go/CSP, Rust async/Tokio, structured-concurrency runtimes, Pony, high-performance task systems | isolation, supervision, channels, ownership, structured lifetimes, work stealing | safe structured explicit concurrency plus compiler-inserted parallelism for proven-pure work; effects and memory order remain explicit | latency/throughput/failure-recovery suites; deterministic pure kernels; no single concurrency paradigm is constitutionally forced |
| Embedded and real-time | C, Ada/SPARK, Rust, Zig, domain RTOS toolchains | bounded allocation, WCET analysis, explicit memory and interrupts, target control | explicit low-level places, bounded worlds, target facts, no hidden allocation in sealed regimes, narrow unsafe escape hatch | WCET, footprint, startup, interrupt and memory-layout evidence on actual hardware |
| Metaprogramming and generation | Lisp/Racket, Zig compile time, Terra, Julia generated functions, C++ templates, staged DSLs | code as data, staging, constant propagation, specialized generators | ordinary Idol evaluation under compile-stage worlds; graph-preserving generation with provenance; no separate macro language required by default | expressiveness corpus, compile cost, diagnostics, generated-code provenance, agent accuracy |
| Agent legibility and coordination | mainstream languages with mature model training; constrained decoding; merge queues; semantic-development research | training corpus, local diagnostics, executable specs, stable identities, explicit task/claim protocols | small familiar surface, generated grammar, executable corpus, missing-fact diagnostics, Live context leases and admission | held-out matched tasks against Python/TypeScript/Rust; tokens and wall time per accepted change; conflict and failure rates |
| Hardware/RTL realization | expert RTL, Bluespec/Clash/Spade, Calyx/CIRCT, vendor HLS | cycle structure, explicit pipelines, resources, timing and placement | future target projection only after semantic graph proves useful structure survives; no Edition-1 claim | standard HLS suites and actual area/timing/power versus expert RTL/HLS; deprioritize on failure |

| # | directive |
|---|---|
| 1 | The table is intentionally open. |
| 2 | A new language, library, runtime, compiler, or hardware system becomes an oracle whenever it establishes a stronger point in any domain. |

| section |
|---|---|
| 4. The language design that falls out |

| # | directive |
|---|---|
| 1 | The performance program does **not** justify constraining the language to the current preferred implementation strategy. |
| 2 | The source and semantic model preserve choices; evidence chooses realizations. |

| section |
|---|---|
| 4.1 Familiar semantic floor |

| # | directive |
|---|---|
| 1 | Idol keeps Lua’s recognizable foundation: |

| # | directive |
|---|---|
| 1 | dynamic values and ordinary Lua-correct fallback; |
| 2 | tables, closures, metatables, multiple results, coroutines, and ordinary bindings; |
| 3 | concise application and subject-oriented relation faces; |
| 4 | no mandatory ownership syntax, layout annotations, monomorphization ceremony, or backend-specific types. |

| # | directive |
|---|---|
| 1 | Static knowledge strengthens this floor rather than replacing it. |

| section |
|---|---|
| 4.2 Orthogonal information channels |

| # | directive |
|---|---|
| 1 | The programmer, compiler, runtime, profiler, target, and environment may contribute exact facts about: |

```text
identity · descriptor · shape · range · aliasing · uniqueness · purity
world · authority · effects · stage · demand · target · profile · hardware
```

| # | directive |
|---|---|
| 1 | Facts qualify meaning. |
| 2 | They do not create parallel type, effect, optimizer, hardware, or agent kingdoms. |

| # | directive |
|---|---|
| 1 | Each non-axiomatic fact carries producer, provenance, trust, scope, dependencies, invalidation, and any guard/witness. |
| 2 | Evidence and assumptions remain distinct from truth. |
| 3 | Acquisition cost and expected realization value guide whether a fact is worth learning; they never strengthen its trust class. |

| section |
|---|---|
| 4.3 Maximum realization freedom |

| # | directive |
|---|---|
| 1 | Unless semantically observed or explicitly pinned, source does not force: |

| # | directive |
|---|---|
| 1 | integer width beyond its semantic law; |
| 2 | boxing or unboxing; |
| 3 | stack, region, arena, RC, tracing, or manual allocation; |
| 4 | AoS, SoA, packing, bitmaps, or pointer topology; |
| 5 | closure allocation or environment materialization; |
| 6 | static, virtual, inline-cache, trace, method-JIT, or direct dispatch; |
| 7 | scalar, SIMD, GPU, accelerator, Wasm, or native realization; |
| 8 | a particular algorithm, schedule, loop structure, or intermediate value; |
| 9 | a universal concurrency or determinism profile; |
| 10 | one physical compiler IR at every optimization level. |

| # | directive |
|---|---|
| 1 | Users may constrain any of these when it is itself an observation or operational requirement. |
| 2 | Otherwise they remain choices. |

| section |
|---|---|
| 4.4 One semantic authority, multiple physical views |

| # | directive |
|---|---|
| 1 | The semantic graph is the source of resolved meaning and provenance. |
| 2 | That does not require every optimization and backend to mutate one universal node representation. |

| # | directive |
|---|---|
| 1 | Typed lowering views are lawful when each: |

| # | directive |
|---|---|
| 1 | is derived from exact graph identities and facts; |
| 2 | states which information it preserves, refines, or intentionally forgets; |
| 3 | carries provenance back to graph identities; |
| 4 | cannot create language meaning or optimization eligibility independently; |
| 5 | has an exact consumer, validation oracle, and invalidation rule. |

| # | directive |
|---|---|
| 1 | This permits CFG, SSA, vector/tensor, GPU, machine, object, and other target-oriented encodings without creating competing semantic authorities. |

| section |
|---|---|
| 4.5 Plural memory and runtime strategy |

| # | directive |
|---|---|
| 1 | Mutable-value semantics, no-alias facts, regions, and Perceus-style reuse are valuable **sealed regimes**, not the universal Lua semantic floor. |
| 2 | Cyclic Lua tables and escaped dynamic graphs require an admitted cycle strategy. |
| 3 | Idol must remain free to select among region, arena, RC/reuse, tracing, explicit placement, or hybrids according to proven shape, lifetime, cycles, effects, and latency requirements. |

| # | directive |
|---|---|
| 1 | Likewise, method specialization with deoptimization is a strong default runtime direction, but tracing, copy-and-patch, interpretation, AOT, and profile-guided variants remain admissible realizations if exact evidence wins for a workload. |

| section |
|---|---|
| 4.6 Concurrency without a performance ceiling |

| # | directive |
|---|---|
| 1 | Compiler-inserted parallelism over proven-pure relations is valuable, but cannot be the language’s only concurrency mechanism without excluding I/O concurrency, supervision, distributed systems, low-level atomics, and latency-oriented task control. |
| 2 | The surface should provide the smallest structured and capability-accountable explicit mechanisms needed for those domains while preserving automatic parallel realization as a separate optimization. |

| section |
|---|---|
| 5. Benchmark architecture |

| # | directive |
|---|---|
| 1 | Every wins-corpus entry contains: |

```text
subject and exact observations
Idol source/graph revision
facts and stages supplied
facts stripped for ablation
all lawful Idol realizations tested
frontier comparator set
compiler/runtime/library versions and flags
hardware, OS, power, thermal and profile state
correctness/equivalence oracle
raw samples and counters
algorithmic-vs-codegen attribution
status and kill criterion
```

| # | directive |
|---|---|
| 1 | Every reported frontier adjective is additionally scoped by exact axes, semantics, corpus/input, hardware/world/target, implementations, versions/configurations, and uncertainty. |
| 2 | Unqualified “fastest” and “best-in-class” are refused. |

| # | directive |
|---|---|
| 1 | The benchmark harness searches the comparator set rather than preselecting a convenient loser. |
| 2 | For CPU controls it normally includes tuned GCC, Clang, ICX and AOCC where available, but that set is expanded or replaced whenever another implementation owns the domain frontier. |

| section |
|---|---|
| 6. Immediate research order |

| # | directive |
|---|---|
| 1 | **Claim and surface freeze.** Public products may expose only admitted records; no new display work until evidence exists. |
| 2 | **Oracle harness.** Implement the domain-frontier comparator contract and exact evidence object. |
| 3 | **Wins corpus.** Reproduce published wins before inventing new mechanisms: no-alias vectorization, Halide scheduling, ISPC SPMD, Futhark fusion/parallelism, FFTW/Spiral generation, AlphaDev primitives, BOLT/profile layout, query compilation, and dynamic specialization. |
| 4 | **Representation controls.** For every win, run fact-on/fact-off and same-algorithm controls through mature and own backends. |
| 5 | **Backend attribution.** Keep C/LLVM/Wasm controls so language-information wins cannot hide backend losses and backend losses cannot erase language wins. |
| 6 | **Agent-legibility experiment.** Measure matched tasks with primer, executable corpus, generated grammar, constrained decoding, and fail-closed diagnostics. |
| 7 | **Live process experiment.** Measure conflict prevention, accepted-change cost, purpose recall, stability, and review load as a layer over a Git/PR + merge-queue baseline; replacement of Git, branches, or human review is not admitted without process dominance and preserved knowledge transfer. |

| section |
|---|---|
| 7. Public claim rule |

| # | directive |
|---|---|
| 1 | The website, Docs, API descriptions, MCP descriptions, and release copy are downstream projections of admitted evidence. |
| 2 | They do not author claims. |

| # | directive |
|---|---|
| 1 | A public sentence about capability or performance must point to an exact admitted record containing the subject, revision, oracle, observations, raw evidence, and status. |
| 2 | In the absence of such a record, the only lawful public state is: |

```text
UNMEASURED
NOT IMPLEMENTED
NOT ADMITTED
RESEARCH HYPOTHESIS
```

| # | directive |
|---|---|
| 1 | This project currently benefits more from a truthful empty surface than from a rich speculative one. |
