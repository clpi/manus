# Adjudication of the 2025–2026 Idol / wart / Live Frontier Surveys

**Status:** research adjudication, not language law.
**Repository subject:** `clpi/idol` at `1ae3e38282d8d5ac8071cdcdf948a5fbb1afec69`.
**Documents reviewed:**

- *The Idol Constitution*, revision 13;
- *Frontier Survey for Idol / wart / Live — Dispositioned*;
- *Second Exhaustive Survey — Idol / wart / Live Project Family*.

The uploaded Constitution states that it was compiled without access to current private repository heads. It therefore cannot supersede the repository’s current supreme compact law by declaration. Its valuable findings are research proposals until reconciled with `docs/spec/law.md`, the executable corpus, and current implementation evidence.

## Project-boundary correction

Wart is a separate project. This adjudication does not make Wart an Idol target,
platform, backend, runtime tier, dependency, or design substrate. Wart must first
establish its own revision-bound, axis/corpus/hardware/version-scoped Pareto
frontier and compactness evidence. An unqualified “fastest Wasm runtime” is not an
admissible claim. Only then may a separately scoped experiment rewrite that exact
subject in Idol, preserve its semantics, and measure whether Idol's facts and
realization freedom improve it. External comparison evidence never becomes Idol
meaning.

## 1. Verdict vocabulary

| Verdict | Meaning |
|---|---|
| **CONFIRMED** | The cited primary evidence supports the factual finding and the project disposition is proportionate. |
| **QUALIFIED** | The underlying evidence is real, but the document generalizes beyond the measured workload, maturity, or semantic regime. |
| **REJECTED AS LAW** | The item may be an experiment or realization strategy, but evidence does not justify a constitutional prohibition or universal semantic commitment. |
| **OPEN** | The claimed project result has no decisive external evidence and must be settled by a bounded experiment in the project that owns the claim. |

## 2. High-confidence confirmations

| Finding | Verdict | Adjudication |
|---|---|---|
| Perceus/Lean-style precise reference counting with reuse can be competitive with tracing collectors on allocation-heavy, cycle-free functional workloads | **CONFIRMED** | Perceus is strong evidence for reuse, uniqueness, and in-place functional update. It is not evidence that arbitrary cyclic Lua object graphs need no cycle strategy. |
| Mutable Value Semantics is a coherent route to efficient mutation without shared mutable references | **CONFIRMED** | The MVS paper demonstrates second-class references, non-shared mutable variables, stack allocation, and copy avoidance. It validates a sealed representation regime, not a replacement for Lua semantics. |
| WebAssembly 3.0 is a stable modern target with Memory64, multiple memories, GC/reference types, tail calls, exceptions, and relaxed SIMD | **CONFIRMED** | This supports Wart's independent target choice only; it creates no Idol target or dependency. Individual proposals and host support still require target/version evidence. |
| Agent-authored pull requests exhibit an unusually high merge-conflict rate | **CONFIRMED** | AgenticFlict reports 29K+ conflicting cases among 107K+ processed agent PRs, a 27.67% rate. It motivates Live’s experiment; it does not prove semantic claims will drive the residual rate to single digits. |
| DORA reports an association between greater AI adoption and reduced delivery stability | **CONFIRMED, NON-CAUSAL** | The 2024 report gives the cited negative stability association; later reporting says throughput improved while instability persisted. This is a baseline and hypothesis source, not proof that Live will reverse it. |
| AlphaDev found production-adopted sorting improvements | **CONFIRMED** | The Nature result and libc++ adoption validate offline search followed by human/machine verification. They do not justify nondeterministic generation inside the shipping compiler. |
| Halide’s algorithm/schedule separation, Futhark’s data-parallel compiler, and ISPC’s SPMD model establish non-C frontier points | **CONFIRMED** | These systems show that richer domain information can equal or beat human-written low-level code on their domains. They are required oracles for relevant workloads. |
| Umbra/Tidy Tuples demonstrates that a purpose-built backend can radically reduce query-compilation latency without forfeiting useful execution quality | **CONFIRMED** | Strong precedent for compile latency as a first-class product axis and for a low-budget own backend. It is database-domain evidence, not automatic general-purpose parity. |
| DBSP/differential dataflow provides a rigorous foundation for incremental view maintenance | **CONFIRMED** | It is a useful candidate for derived graph projections and Live views. Calling it the settled implementation for a unified compiler/VCS graph is premature. |
| Unison demonstrates practical value from content-addressed definitions and persistent compilation/test caches | **CONFIRMED** | Strong precedent for stable identity and avoiding incidental textual conflicts. Idol still needs its own semantic identity and evolution laws; a hash is not automatically semantic identity under current law. |
| V8 abandoned a large production Sea-of-Nodes backend because of complexity, cache locality, fixpoint cost, and difficult control/effect handling | **CONFIRMED** | This is direct contrary evidence to treating one universal physical graph representation as a virtue independent of workload. |
| MLIR’s progressive multi-level lowering preserves domain structure that low-level IRs cannot recover | **CONFIRMED** | It supports a distinction between one semantic authority and several typed, provenance-connected physical lowering representations. |
| A no-resource language is a material risk for coding agents; executable fixtures, a primer, generated grammar, constrained decoding, and local diagnostics are sensible mitigations | **CONFIRMED AS RISK/MITIGATION** | No published result establishes parity with mature languages. The project’s agent-legibility claim remains an experiment. |

## 3. Findings that must be qualified

### 3.1 “Own backends remain behind LLVM”

**Verdict: QUALIFIED.**

Cranelift-class and baseline backends often trade code quality for compile speed; LLVM-backed WAMR AOT and mature native toolchains frequently win steady-state numeric workloads. The exact ratios quoted in the surveys come from particular programs, machines, runtimes, and blog methodology. They may calibrate a suite; they must not become universal constants.

Project consequence: keep mature C/LLVM/Wasm pipelines as controls and an own backend as a product/research axis, never a mandatory shipping boundary while it loses. Attribute each loss to backend, missing information, algorithm, runtime, or measurement state.

### 3.2 “The honest C baseline is max(GCC, Clang, ICX, AOCC)”

**Verdict: QUALIFIED AND EXPANDED.**

That is a better CPU control than `clang -O3` alone, but it is still not the project oracle. Fortran, Rust, ISPC, vendor math/tensor libraries, hand-tuned assembly, Halide, Futhark, Triton, TVM, FFTW, Spiral, query engines, Julia, LuaJIT, V8/Graal, and physical lower bounds may own the relevant frontier.

Project consequence: use the domain-frontier envelope defined in `domain-frontier-map.md`.

### 3.3 “One graph plus e-graphs/Datalog is the right substrate”

**Verdict: QUALIFIED.**

One resolved semantic authority is valuable. A literally universal physical graph with no typed lowering views is an unproven bet. V8’s experience and MLIR’s success show why control, vector/tensor structure, machine details, and locality may need different physical representations.

Project consequence: one semantic graph owns meaning; CFG, SSA, vector/tensor, GPU, machine, object, and indexing views are permitted when derived, provenance-linked, validated, and semantically subordinate.

### 3.4 “Method JITs won; reject tracing”

**Verdict: QUALIFIED; REJECT THE BAN.**

Method JITs with inline caches, guarded assumptions, and deoptimization dominate many general workloads. LuaJIT remains evidence that trace specialization can be powerful on suitable programs. No external result justifies banning a lawful realization strategy before measurement.

Project consequence: prefer a method/profile-specialization architecture initially, while keeping trace fragments or trace-derived implementations admissible under the same evidence and deoptimization law.

### 3.5 “AOT partial evaluation is a compiler generator”

**Verdict: CONFIRMED IN PRINCIPLE, OPEN IN MAGNITUDE.**

The Futamura projection and Truffle lineage support the mechanism. Truffle’s production results depend on runtime profiles, assumptions, deoptimization, compilation budgets, and extensive engineering. The proposed `1.5x`/`2x` bounds are hypotheses, not inherited facts.

Project consequence: preserve the experiment and kill criteria; do not treat it as a shortcut around building a capable runtime/backend.

### 3.6 “Claim-time semantic identity prevention will drive conflicts near zero”

**Verdict: OPEN.**

AgenticFlict establishes the textual conflict baseline, not the semantic/incidental decomposition. Claims may prevent duplicate and overlapping work, but can also serialize useful parallelism or miss higher-order conflicts.

Project consequence: replay an external corpus and instrument a live project before making product claims. Test Live first as coordination/context/admission over Git and merge-queue baselines; do not ratify it as a replacement for Git, branches, or human review.

## 4. Findings rejected as universal project law

### 4.1 “MVS subsumes the disjoint fact”

**Verdict: REJECTED AS A UNIVERSAL SEMANTIC CLAIM.**

MVS guarantees no shared mutable state by restricting references. Idol’s current floor preserves Lua tables, closures, metatables, aliases, and potentially cyclic graphs. A sealed value or region may satisfy MVS-like facts; dynamic Lua-correct programs do not.

Ruling: MVS is an inferred/sealed specialization regime. `disjoint`, uniqueness, no-alias, and acyclicity remain distinct provable facts unless the executable fact algebra proves equivalence in a bounded regime.

### 4.2 “No GC is settled”

**Verdict: REJECTED AS LAW.**

Perceus’s strongest guarantees are for cycle-free programs. Lua permits cyclic tables and closure/object graphs. A no-GC constitutional promise would either reject lawful Lua behavior or leak cycles unless another exact cycle mechanism exists.

Ruling: leave memory strategy open. Prefer stack/region/arena/RC/reuse when facts permit; retain a tracing, cycle-collection, explicit-cycle, or other admitted strategy for cyclic dynamic graphs.

### 4.3 “Only compiler-inserted concurrency”

**Verdict: REJECTED AS LAW.**

It would exclude I/O concurrency, servers, distributed supervision, asynchronous capability use, interactive latency, explicit atomics, and systems programming cases that cannot be derived from pure data parallelism.

Ruling: automatic parallelization of proven-pure work remains a major optimization. The language also needs a minimal structured, effect- and capability-accountable explicit concurrency floor, plus low-level memory-order operations where demanded.

### 4.4 “Agreement testing replaces coherence”

**Verdict: REJECTED AS A COMPLETE REPLACEMENT.**

Testing samples behavior; it does not prove universal equivalence over infinite domains, effects, faults, authority, termination, or temporal behavior. Overlapping implementations still need explicit applicability ordering and an exact agreement obligation.

Ruling: permit overlap only under declared laws. Use proof, translation validation, exhaustive finite checking, differential/metamorphic tests, or explicit priority/refusal according to the domain. Tests are evidence, not universal coherence.

### 4.5 “Deterministic realization makes record/replay free”

**Verdict: REJECTED.**

Reproducible builds and deterministic pure computation do not determine clocks, randomness, network input, filesystem races, scheduling, device behavior, signals, or foreign effects.

Ruling: require content-addressed reproducible builds. Provide explicit deterministic execution profiles where useful. Record or control nondeterministic world observations for replay.

### 4.6 “Static erasure makes capability attestation zero-cost”

**Verdict: REJECTED FOR ACTUAL-USE ATTESTATION.**

Static analysis can attest an upper bound or required capability set. Proving which capabilities were actually exercised in a run needs runtime evidence unless the exact execution is statically determined.

Ruling: distinguish static capability requirement, granted authority, and observed use. Measure instrumentation cost rather than declaring it zero.

### 4.7 “A single physical IR/no pass pipeline is required by one semantic graph”

**Verdict: REJECTED.**

This confuses semantic authority with compiler data structure. It risks throwing away vector/tensor, control, locality, machine, and target information or forcing one representation to serve incompatible optimization problems.

Ruling: the semantic graph owns meaning and transformation lineage. Multiple typed physical views and scheduled analyses are lawful. No physical view may become a second language authority.

### 4.8 “A fixed seven-keyword language follows from the research”

**Verdict: REJECTED AS CURRENT AUTHORITY.**

The uploaded Constitution proposes a specific small language but acknowledges it was prepared without current private repository heads. The current supreme law and executable grammar own canonical syntax. Keyword count is an axis to measure, not a result imported from a research synthesis.

### 4.9 “Imprecise faults should be the familiar default”

**Verdict: REJECTED AS CURRENT LAW.**

The cited imprecise-exception work establishes a transformation-preserving model
for lazy Haskell, not a general result that imprecision is the right familiar
default for Idol. Preserve the experiment as an explicit relaxed observation
regime if bounded evidence justifies it; ordinary fault behavior remains governed
by current observation/effect law rather than imported by analogy.

## 5. Current repository correction

The current repository law already contains the most important safe direction:

```text
semantic identity
+ exact facts
+ demand and observation
+ lawful transformation
+ late physical realization
+ exact evidence
```

The required amendments are meta-laws, not a wholesale replacement of current syntax:

1. **Domain-frontier oracle:** C is one control; the strongest equivalent domain leader is the comparator.
2. **Physical-view freedom:** one semantic authority permits multiple derived lowering representations.
3. **Strategy openness:** memory, runtime specialization, parallelism, layout, and backend strategies remain open until evidence and semantics constrain them.
4. **Evidence-gated publication:** public surfaces consume admitted evidence; they do not author language or performance claims.
5. **Website-last priority:** no product surface work outranks benchmark, artifact, self-host, runtime, or Live process evidence.

## 6. Project decisions recommended now

### Adopt now as research and implementation direction

- domain-frontier benchmark envelope;
- fact-on/fact-off strip tests;
- alias/range/alignment vectorization experiments;
- typed, provenance-linked physical lowering views;
- Perceus-style reuse only in proven cycle-free regimes;
- mature control backends plus own low-latency backend;
- differential, metamorphic, fuzz, and translation-validation gates;
- executable corpus, primer, generated grammar, and agent-legibility experiment;
- revision-bound evidence records and public projections derived from admitted records;
- Live claim/context/admission experiments with DORA and AgenticFlict-style controls.

### Keep open pending measurement

- trace versus method/profile runtime tiers;
- exact memory strategy for cyclic dynamic graphs;
- Datalog/DBSP implementation choices;
- first Futamura performance bounds;
- hardware realization;
- semantic claim granularity and conflict policy;
- explicit concurrency surface;
- proof/test/priority requirements for overlapping implementations.

### Stop or demote immediately

- generic “faster than C” prose;
- public claims of native completeness, self-hosting, executing Live, admitted worlds, or performance without exact records;
- website-authored semantic explanations that exceed current law and implementation;
- universal no-GC, no-explicit-concurrency, no-lowering-IR, or no-tracing prohibitions;
- treating research documents as authority merely because they are comprehensive.

## 7. Primary evidence consulted

- Racordon et al., *Native Implementation of Mutable Value Semantics* (2021).
- Reinking, Xie, de Moura, and Leijen, *Perceus: Garbage Free Reference Counting with Reuse* (PLDI 2021).
- V8 team, *Land ahoy: leaving the Sea of Nodes* (2025).
- LLVM MLIR rationale, Linalg rationale, dialect-conversion and target documentation.
- W3C WebAssembly 3.0 release and specification materials (2025).
- Budiu et al., *DBSP: Automatic Incremental View Maintenance for Rich Query Languages* (VLDB 2023).
- Mankowitz et al., *Faster sorting algorithms discovered using deep reinforcement learning* (Nature 2023).
- Halide, Futhark, ISPC, Umbra/Tidy Tuples, Unison, Truffle, and Bytecode Alliance primary project/paper materials.
- Ogenrwot and Businge et al., AgenticFlict dataset paper (2026).
- Google DORA 2024 and 2025 reports.

This adjudication intentionally separates published facts from project inference. All Idol-specific magnitudes remain unmeasured until an exact repository experiment produces evidence.
