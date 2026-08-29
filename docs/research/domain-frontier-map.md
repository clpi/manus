# Idol Domain-Frontier Capability and Performance Map

**Status:** research disposition, not language law and not an implementation claim.  
**Repository subject:** `clpi/idol` at `1ae3e38282d8d5ac8071cdcdf948a5fbb1afec69`.  
**Purpose:** replace C-centric aspiration with a measurable map of the strongest known implementation in every relevant capability and performance domain.

## 1. The governing correction

C is an important control, not a universal oracle.

For any fixed workload and observable contract, the comparison target is the **domain-frontier envelope**: the strongest known semantically equivalent implementation, configuration, runtime, library, compiler, schedule, and target available for that domain. A claim is never admitted because Idol beats a weak C spelling, a default compiler flag, an interpreter, or a baseline tier.

The envelope is a set, not one language:

```text
oracle(workload, observations, target)
    = Pareto frontier of every credible equivalent implementation
```

The frontier includes hand-written and generated implementations, vendor libraries, domain-specific languages, runtimes, optimizing compilers, and physical lower bounds. Idol may win through information the comparator lacks, work its human author did not perform, runtime facts unavailable ahead of time, or a better algorithm selected under proven conditions. Each class is reported separately.

A result remains one of:

```text
UNMEASURED
MEASURED
REPRODUCED
ADMITTED
SUPERSEDED
```

Only `ADMITTED` evidence may feed public capability or performance claims.

## 2. Performance is a vector

No scalar score is sufficient. Every benchmark contract records at least:

- steady-state latency and throughput;
- startup, warmup, and tail latency;
- compile, link, incremental, and installation work;
- peak and retained memory;
- allocations, copies, and memory traffic;
- artifact, relocation, and loaded-code size;
- instructions, cycles, branches, misses, spills, and vector occupancy;
- energy when measurable;
- correctness, safety, determinism, and capability guarantees;
- target, ABI, machine, OS, thermal, power, and profile state;
- implementation effort and source information supplied;
- the exact strongest comparator and physical lower bound.

A win on one axis does not conceal a loss on another.

## 3. Domain-frontier matrix

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

The table is intentionally open. A new language, library, runtime, compiler, or hardware system becomes an oracle whenever it establishes a stronger point in any domain.

## 4. The language design that falls out

The performance program does **not** justify constraining the language to the current preferred implementation strategy. The source and semantic model preserve choices; evidence chooses realizations.

### 4.1 Familiar semantic floor

Idol keeps Lua’s recognizable foundation:

- dynamic values and ordinary Lua-correct fallback;
- tables, closures, metatables, multiple results, coroutines, and ordinary bindings;
- concise application and subject-oriented relation faces;
- no mandatory ownership syntax, layout annotations, monomorphization ceremony, or backend-specific types.

Static knowledge strengthens this floor rather than replacing it.

### 4.2 Orthogonal information channels

The programmer, compiler, runtime, profiler, target, and environment may contribute exact facts about:

```text
identity · descriptor · shape · range · aliasing · uniqueness · purity
world · authority · effects · stage · demand · target · profile · hardware
```

Facts qualify meaning. They do not create parallel type, effect, optimizer, hardware, or agent kingdoms.

### 4.3 Maximum realization freedom

Unless semantically observed or explicitly pinned, source does not force:

- integer width beyond its semantic law;
- boxing or unboxing;
- stack, region, arena, RC, tracing, or manual allocation;
- AoS, SoA, packing, bitmaps, or pointer topology;
- closure allocation or environment materialization;
- static, virtual, inline-cache, trace, method-JIT, or direct dispatch;
- scalar, SIMD, GPU, accelerator, Wasm, or native realization;
- a particular algorithm, schedule, loop structure, or intermediate value;
- a universal concurrency or determinism profile;
- one physical compiler IR at every optimization level.

Users may constrain any of these when it is itself an observation or operational requirement. Otherwise they remain choices.

### 4.4 One semantic authority, multiple physical views

The semantic graph is the source of resolved meaning and provenance. That does not require every optimization and backend to mutate one universal node representation.

Typed lowering views are lawful when each:

1. is derived from exact graph identities and facts;
2. states which information it preserves, refines, or intentionally forgets;
3. carries provenance back to graph identities;
4. cannot create language meaning or optimization eligibility independently;
5. has an exact consumer, validation oracle, and invalidation rule.

This permits CFG, SSA, vector/tensor, GPU, machine, object, and other target-oriented encodings without creating competing semantic authorities.

### 4.5 Plural memory and runtime strategy

Mutable-value semantics, no-alias facts, regions, and Perceus-style reuse are valuable **sealed regimes**, not the universal Lua semantic floor. Cyclic Lua tables and escaped dynamic graphs require an admitted cycle strategy. Idol must remain free to select among region, arena, RC/reuse, tracing, explicit placement, or hybrids according to proven shape, lifetime, cycles, effects, and latency requirements.

Likewise, method specialization with deoptimization is a strong default runtime direction, but tracing, copy-and-patch, interpretation, AOT, and profile-guided variants remain admissible realizations if exact evidence wins for a workload.

### 4.6 Concurrency without a performance ceiling

Compiler-inserted parallelism over proven-pure relations is valuable, but cannot be the language’s only concurrency mechanism without excluding I/O concurrency, supervision, distributed systems, low-level atomics, and latency-oriented task control. The surface should provide the smallest structured and capability-accountable explicit mechanisms needed for those domains while preserving automatic parallel realization as a separate optimization.

## 5. Benchmark architecture

Every wins-corpus entry contains:

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

The benchmark harness searches the comparator set rather than preselecting a convenient loser. For CPU controls it normally includes tuned GCC, Clang, ICX and AOCC where available, but that set is expanded or replaced whenever another implementation owns the domain frontier.

## 6. Immediate research order

1. **Claim and surface freeze.** Public products may expose only admitted records; no new display work until evidence exists.
2. **Oracle harness.** Implement the domain-frontier comparator contract and exact evidence object.
3. **Wins corpus.** Reproduce published wins before inventing new mechanisms: no-alias vectorization, Halide scheduling, ISPC SPMD, Futhark fusion/parallelism, FFTW/Spiral generation, AlphaDev primitives, BOLT/profile layout, query compilation, and dynamic specialization.
4. **Representation controls.** For every win, run fact-on/fact-off and same-algorithm controls through mature and own backends.
5. **Backend attribution.** Keep C/LLVM/Wasm controls so language-information wins cannot hide backend losses and backend losses cannot erase language wins.
6. **Agent-legibility experiment.** Measure matched tasks with primer, executable corpus, generated grammar, constrained decoding, and fail-closed diagnostics.
7. **Live process experiment.** Measure conflict prevention, accepted-change cost, purpose recall, stability, and review load against a Git/PR baseline.

## 7. Public claim rule

The website, Docs, API descriptions, MCP descriptions, and release copy are downstream projections of admitted evidence. They do not author claims.

A public sentence about capability or performance must point to an exact admitted record containing the subject, revision, oracle, observations, raw evidence, and status. In the absence of such a record, the only lawful public state is:

```text
UNMEASURED
NOT IMPLEMENTED
NOT ADMITTED
RESEARCH HYPOTHESIS
```

This project currently benefits more from a truthful empty surface than from a rich speculative one.
