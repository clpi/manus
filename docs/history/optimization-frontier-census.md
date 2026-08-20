# Optimization frontier census

**Status:** research projection and capability map. **Not language law.** Use this
so major compiler/research families stay **visible** and can be expressed in the
one semantic graph when admissible.

## Unifying criterion

Any optimization or capability belongs in the one semantic graph when it can be
expressed as **relations, facts, observations, demands, laws, witnesses,
transformations, worlds, or realizations**.

Create a separate IR or subsystem only when **irreducibility is proved**.

Current Idol already partial-fits: one graph, one identity, sparse consequence
closure, demand, witnessed transformations, candidate realization economics.
The remaining work is expanding the fact/law/candidate universe until the
optimization surface is **open-ended** rather than manually enumerated.

Guiding question for each family:

**what information about a computation does Idol still not model, and what
physical work becomes removable once that information is available?**

## Universal optimization state

See `.agents/ARCHITECTURE_INJECTION.md` for agent orientation. Census entries
below attach to one or more of:

`identity · facts · observations · demand · laws · change · correspondence ·
search · proof · cost · world · realization`

---

## I. P0 — foundations that unlock many families at once

1. **General relation-law algebra** — attach algebraic laws to relations
   (associativity, commutativity, identity, annihilator, idempotence,
   distributivity, monotonicity) as first-class facts, not ad hoc optimizer
   predicates.
2. **Law induction and mining** — prove an implementation satisfies a law → add
   to graph; SMT/symbolic/enumerative proposal of candidate laws with proof/refusal.
3. **Scoped and specialized laws** — laws with preconditions; idempotence over
   a sealed descriptor subset only.
4. **Proof-directed demand propagation** — derive minimal upstream projections
   from downstream demand through relation laws (algebraic demand synthesis).
5. **Minimal sufficient semantics** — for observation `D(f(x))`, find smallest
   `p(x)` with `D(f(x)) = g(p(x))`; unifies dead-field elimination, precision
   narrowing, recurrence contraction, partial parsing, query projection, wire
   elision, foreign boundary minimization.
6. **Automatic discovery of sufficient statistics** — search projections via laws,
   symbolic execution, SMT, examples+proof, agent candidates.
7. **Information-flow as optimization** — invert taint: if result cannot depend
   on input dimension, eliminate associated work/storage/transfer.
8. **Logical relations (executable fragment)** — prove representation independence
   (boxed≈unboxed, hash≈perfect hash, foreign≈native) under exposed observations.
9. **Change propagation algebra** — incremental facts when inputs/worlds change;
   pairs with correspondence for cross-version reuse.

---

## II. Supercompilation / fold–unfold / generalized partial computation

Emphasize beyond ordinary partial evaluation: unfold, specialize, fold,
generalize, residualize under demand.

| Capability | Graph expression |
|---|---|
| Termination control | whistle / homeomorphic embedding policies as search facts |
| Memoized configurations | correspondence + memo keys over semantic state |
| Constructor/data-shape specialization | unfold + law-scoped facts |
| Deforestation | fold law consequence, not a named pass |
| Interprocedural fusion | relation composition + boundary contraction |
| KMP-like matchers | supercompilation from generic search relations |
| Demand-aware equivalence | `x ≡_demand y` — equivalence under observer, not full value |

Engine shape: observe → unfold → propagate → recognize recurrence → generalize →
fold → residualize demanded semantics only.

---

## III. Optimal graph reduction / interaction nets (selective import)

Do not become an interaction-net language. Import **sharing of semantic work**:

- shared redex / specialization / proof / compile-time evaluation identity
- duplication tracking; fan-in/fan-out where duplication is observable or costly
- higher-order closure reduction without rebuilding equivalent environments
- reduction-order selection for demanded normal form

Relevant to compile-time FTCFTW, not runtime only.

---

## IV. Relational execution / backward semantics

miniKanren-style **modes over one relation** (not separate APIs):

- forward, inverse, partial, synthesis, legality queries
- parser ↔ printer, serializer ↔ deserializer, ABI adapter synthesis
- counterexample / configuration / world synthesis
- backward demand as relational solving

---

## V. Search completeness & strategy as realization

Classify relations: deterministic · finite ND · infinite enumerable · constraint ·
probabilistic · optimization — without new surface syntax.

Search strategies are **realizations**: DFS, BFS, best-first, A*, branch-and-bound,
SAT, SMT, ILP, constraint propagation, sampling, beam search, learned search.

---

## VI. Deductive synthesis / proof-directed construction

```text
desired relation + laws + target world + cost → synthesize realization
```

Examples: FSM parser from grammar, perfect hash, comparator network, SIMD shuffle,
protocol decoder, bitpack layout, lock-free transition, dispatch automaton, foreign
adapter, incremental updater from relation semantics. Stronger than picking among
existing expressions (superoptimization).

---

## VII. Proof-producing optimization & trusted core

Pattern: untrusted candidate → semantic reference → optimized candidate →
certificate → small trusted checker (eBPF Kops, Jitterbug).

Enables agents, autotuners, plugins without joining trusted core.

---

## VIII. Compiler extension without enlarging semantic authority

Plugins may propose: candidate, law, witness, cost, applicability.

Plugins may **not**: define relation meaning, create identity, bypass proof.

---

## IX. Kernel / OS / unikernel specialization

World facts drive stack elimination (filesystem, threads, loader, locale, signals,
DNS, TLS subset). Realization extends to process, unikernel, WASI, eBPF,
firmware, bare-metal, kernel module, GPU, FPGA.

---

## X. Compiler ↔ kernel cooperation

Lifetime hints, huge pages, access patterns, NUMA, deadlines, batching, io_uring
fusion, prefault, DVFS, affinity, QoS — as inferable realization facts.

---

## XI. Syscall elimination & fusion

Recognize open/read/close, stat/open/read, write sequences → fewer syscalls,
vectored I/O, mmap, io_uring batch, static embedded resources, zero runtime when
input is compile-time known.

---

## XII. Storage-aware compilation

SSD/HDD, local/remote object store, NVRAM, append-only logs, mmap DBs, format
selection, block sizes, read/write amplification, durability, fsync batching,
WAL vs COW, replication — realization under durability law X.

---

## XIII. Network protocol & topology realization

RPC vs direct call, serialization vs shared memory, HTTP/2 vs HTTP/3, batching,
compression, pooling, zero-copy, kernel bypass, RDMA; fleet-scale placement as
graph mapping minimizing cut + latency + storage movement.

---

## XIV. Communication & data-movement complexity

Optimize toward lower bounds on bits across boundaries, memory words moved,
synchronization messages, device transfers — often dominates arithmetic.

---

## XV. Red/blue pebble / recomputation–storage duality

I/O-complexity pebble games: residency vs recompute vs migration. Universal graph
law: store · recompute · invert · checkpoint · compress · materialize lazily —
cost from demand, lifetime, dependencies. Unifies AD checkpointing, memoization,
cache policy, coroutine state, distributed caching.

---

## XVI. Semantic memoization & observation-relative reuse

Memo keys: relation id + demanded input facts + world dependencies.

**Observation-relative memo:** reuse when equivalent for current demand
(`x ≡_demand y`). Cross-program reuse by **proven semantic correspondence**, not
source hash — incremental compilation as semantic caching.

---

## XVII. Stateful / reactive equivalence

Bisimulation/simulation for coroutines, actors, services, state machines.
**Trace quotienting:** erase internal scheduling, transient writes, hidden retries
when trace projection does not observe them.

---

## XVIII. Temporal logic as demand/law

Eventually, never, before, at-most-once, always — as graph laws optimizing state
machines and concurrency while preserving required traces. Automata minimization
for parsers, protocols, coroutines, UI, transactions. Symbolic automata for
large alphabets.

---

## XIX. Parsing realization space

Grammar stays one; **parser algorithm is realization**: Pratt, RD, DFA, LR,
packrat, specialized recognizer, decision tree, derivative-based, PEG/automata
hybrid per region. Entropy-optimal dispatch when alternative probabilities known.

---

## XX. Succinct & learned structures

Rank/select, succinct trees, Elias–Fano, wavelets, MPH, compressed tries for
compiler-owned graphs. Learned indexes/hashes/cost models as **candidates** with
bounded error and fallback — never semantic authority.

---

## XXI. Learned compilation without learned correctness

Models predict profitability, inlining, layout, reg hints, schedule, algorithm
candidates; correctness from semantic validation. Meta-learning across project
history; multi-objective Bayesian Pareto fronts; regret-minimizing and robust
choices under uncertain profiles; online algorithms with competitive-ratio facts;
amortized laws with potential functions.

---

## XXII. Adaptive representations

Cache-adaptive structures; self-tuning linear→sorted→hash→tree with **hysteresis**;
persistent vs destructive update from linear/uniqueness facts; region polymorphism;
ownership-transfer eliminating copies across threads/processes/foreign/GPU.

---

## XXIII. Device memory & heterogeneous placement

Places: CPU reg/mem, GPU global/shared, NPU, FPGA BRAM, remote memory. Migration
is realization transition. Communication-avoiding transforms; replicate vs
recompute vs transfer; specialize for data location; energy/thermal/wear/reliability
as explicit cost dimensions; approximate hardware when error demand permits.

---

## XXIV. Observer virtualization & semantic tooling

Debuggers, profilers, LSP, MCP, tracing express **exact observation demand** — need
not disable optimization. Semantic breakpoints, semantic profiling surviving layout,
cross-version profile correspondence, static hotness, semantic diff-driven compile
priority, deadline-aware and any-time compilation, proof-budgeted validation.

Reversible debugging via checkpoint + provenance + recomputation + invertible
relations.

---

## XXV. Trusted-core minimization & semantic linking

Small checker verifies graph facts, transform witnesses, machine refinement,
evidence integrity. Proof-carrying foreign libraries; packages export graph-level
semantics; ABI-less whole-program composition where identity shared; semantic
linking/dynamic linking; hot replacement by refinement; state migration synthesis;
schema evolution as relations.

---

## XXVI. Boundary contraction & composition-driven optimization

Explicit **no-op boundary** when module/foreign/descriptor/closure/world boundary
has zero physical realization. Generic pattern: `A → X → B` becomes `A → B` when
X unobserved. Cancellation laws: encode∘decode, box∘unbox, compress∘decompress.
Adjoint/inverse-pair exploitation in relation algebra.

---

## XXVII. Error, nondeterminism, reproducibility

Rich failure algebra: may/must fail, retryable, idempotent, recoverable, error
identity demanded or not. Nondeterminism: choose any refinement when observation
permits. Fairness and determinism as explicit observations. Reproducibility
(build, numeric, distributed) as world demand.

---

## XXVIII. Resources, topology, privacy, security

Semantic resource types (file, socket, GPU, token, transaction) with lifecycle
laws — not a separate linear type language. Temporal lifetime and spatial
(co-located, NUMA, device) facts. Topology-aware world algebra; automatic
distributed partitioning; distributed fusion; compute-vs-data migration; edge/server
split. Privacy, differential privacy, crypto/MPC/homomorphic/enclave realization
when world requires. Verified secure compilation extends refinement to
noninterference/capability laws.

---

---

## XXIX. Generalize ↔ specialize (anti-unification axis)

The complement of specialization is not merely “don’t specialize.” Given several
relations sharing structure, discover the **least general generalization**: common
semantic skeleton plus varying facts.

| Capability | Graph expression |
|---|---|
| Anti-unification / LGG | correspondence + fact deltas over shared skeleton |
| Automatic generic discovery | generalize ↑ then specialize ↓ as fundamental ops |
| Shared specialization | one skeleton, many fact patches |
| Common machine-code extraction | identical demanded behavior after quotient |
| Descriptor abstraction | factor repeated descriptor shape |
| Optimizer-rule generalization | law candidates from specialized instances |
| Cross-package semantic deduplication | correspondence across compilation units |
| Re-generalization for code size | undo specialization explosion when economics flip |

Engine axis:

```text
generalize ↑
  semantic identity + facts
specialize ↓
```

Pairs with supercompilation (§ II) and semantic factoring (§ XXX).

---

## XXX. Semantic factoring & minimum-description state

Search for smallest factorization of repeated semantic structure:

```text
common meaning + small varying facts
```

instead of storing N independently expanded copies. Optimization objective:

**minimize description length of retained semantic state while preserving every
useful distinction.**

Applies to: instantiated generics, specialized relations, target/world variants,
parser states, descriptor families, machine variants, proof objects, compiler
analysis states. Material compile-time memory win when paired with fact liveness
(§ XXXVII).

---

## XXXI. Specialization economics & semantic clone control

Specialization itself obeys realization economics — not an inlining threshold:

```text
specialize · share · outline · generalize · merge · discard
```

Trade runtime gain, code size, I-cache, compile work, profile frequency, future
reuse.

| Capability | Graph expression |
|---|---|
| Explosion control | cost facts + re-generalization triggers |
| Semantic clone merging | merge equivalent demanded behavior before machine code |
| Semantic outlining | inverse of inlining — extract shared subregion when size/cache wins |
| Version lattice | partial order of versions by required facts |
| Version subsumption | delete dominated versions |
| Cluster synthesis | profile-driven version creation |
| Version migration | correspondence retains specialization across revisions |
| Semantic multiversioning | versions = meaningful fact sets; ISA is just another fact |

---

## XXXII. Granularity as a physical degree of freedom

Granularity is not only SIMD width. A computation may realize per element, vector,
cache line, page, batch, task, process, or machine — jointly optimized with
representation and placement.

| Pattern | Graph expression |
|---|---|
| Granularity algebra | realization fact over batch grain |
| Conversion elimination | contract `granularity A → convert → B` across boundaries |
| Database morsels / network packets / GPU blocks | same abstraction, different domains |

Generalizes fusion/fission (§ XXVI) with an explicit grain axis.

---

## XXXIII. Dimensional, shape, tensor, and sparse facts (without tensor kingdom)

Dimensions and shape are **facts**, not a permanent Tensor semantic identity.

| Capability | Graph expression |
|---|---|
| Unit/dimension semantics | length, time, mass, bytes, cycles, joules as facts |
| Impossible comparisons rejected | contradiction / unreachable region |
| Scale elimination & conversion motion | law-guided rewrite |
| Symbolic shape analysis | stride, alignment, tile, SIMD width, GPU map, footprint |
| Shape polymorphism | sequence/table descriptor + dimensional facts |
| Contraction planning | ordering, matmul lowering, transpose elimination, layout, tiling, fusion, device, precision — XLA/TVM ideas without tensor IR |
| Sparse structure family | pattern, density, block, sorted index, symmetry, banded |
| Sparse realizations | dense, CSR, CSC, COO, bitmap, block, implicit, procedural |
| Structural zeros | proven zero/default/identity → physical absence |
| Symmetry exploitation | store/compute equivalence-class representatives only |
| Group-action quotienting | quotient state space when group action preserves observations |

---

## XXXIV. Abstraction, precision, and compiler self-query

Analysis precision becomes a **resource** chosen by expected optimization gain.

| Capability | Graph expression |
|---|---|
| Predicate abstraction | track only predicates sufficient for demand |
| CEGAR | refine only relevant distinctions when coarse abstraction fails |
| Lazy precision | unknown → range → finite → exact on consumer demand |
| Precision tiers | cheap/coarse · medium · exact/expensive as cost facts |
| State-space reduction | invariants eliminate impossible states before search |
| Abstract-state minimization | merge states with identical downstream facts |
| Canonical representatives | equivalent states → same cache/search key |
| Semantic query planning | optimize compiler’s own graph queries (order, index, join, batch) |
| Analysis fusion | fuse traversals when cheaper than independent scans |
| Analysis sharing | one range producer for all consumers |

Compiler analysis explosion is itself optimizable graph state (pairs with § XXX).

---

## XXXV. Negative knowledge, contradiction, and minimal explanations

Positive facts dominate today; **negative and contradictory facts** are equally
first-class.

| Fact class | Graph expression |
|---|---|
| Negative knowledge | cannot alias, cannot trap, cannot be NaN, world excludes X |
| Exclusion sets | `target ∈ {A,B,C,D}` minus learned exclusions, not collapse to unknown |
| Contradiction | unreachable semantic region → delete code / shrink search |
| Unsat core | minimal conflicting fact set for diagnostics and agent repair |
| Explanation-minimal diagnostics | smallest missing/conflicting fact set explaining failure |
| Optimization refusal minimization | minimal fact blocking realization R (`idol why-not` built-in) |

Truth lattice extends beyond unknown/absent/exact:

```text
unknown · absent · possible · exact · contradictory
```

---

## XXXVI. Guards, profiles, and dynamic patching

Runtime guards are synthesized artifacts subject to the same economics as code.

| Capability | Graph expression |
|---|---|
| Minimal guard synthesis | smallest runtime check sufficient for optimization |
| Guard sharing | hoist common guard; downstream consumes refinement |
| Guard implication | emit B only when A does not already imply B |
| Guard ordering | decision-tree synthesis by cost, failure rate, downstream gain |
| Profile/world sealing | guards disappear when deployment facts establish them |
| Proof-directed guard removal | incremental proof invalidates guard realization only |
| Dynamic semantic patching | new fact patches one machine region, not whole compile |
| Hot-code / hot-data relocation | layout change without identity/provenance change |
| Runtime representation migration | inline vector → hash → frozen table when phase changes |
| Phase detection | construction · mutation · steady read · shutdown |
| Freeze-point inference | immutability triggers representation transition |
| Init/runtime separation | initialization machinery absent from steady state |
| Destructive initialization | reuse construction memory for final state |

---

## XXXVII. Compiler-graph lifetimes & physical realization of Compiler B

The compiler graph itself needs lifetime and placement optimization.

| Capability | Graph expression |
|---|---|
| Ephemeral semantic facts | scratch proofs, indexes, candidate sets evicted after last consumer |
| Fact liveness | which facts have future consumers? (analogous to value liveness) |
| Proof liveness | retain witnesses only for demanded validation/diagnostics/reuse |
| Provenance liveness | full provenance externalized or compressed in release builds |
| Semantic cold storage | rarely queried facts → compressed / on-disk |
| Store vs recompute | same trade as compiled programs, applied to compiler state |
| Compile-time memory hierarchy | hot / RAM / compressed / persistent / recomputable tiers |
| Semantic prefetching | predict next fact columns during traversal |
| Layout autotuning | column order, packing, index form, chunk size for compiler workloads |
| Target-specific compiler realization | different physical graph layout per host while same semantics |
| Self-specializing Compiler B | fixed grammar/world/target/policy removes generic machinery |
| Compiler feature DCE | reachability builds compiler variants (Idol→ARM64 release only) |
| Compiler staging | precompute grammar tables, law closures, target facts, standard proofs |
| Snapshot image / zero-deserialization startup | mmap pre-resolved immutable semantic pages |
| Shared semantic pages | copy-on-write / fork-friendly immutable compiler libraries |
| Daemon as realization | cold exe · mmap snapshot · persistent daemon · distributed service |

---

## XXXVIII. Determinism, distribution, and untrusted optimization

Separate **semantic correspondence** from **physical coordinate**.

| Capability | Graph expression |
|---|---|
| Deterministic parallel evaluation | independent fact production, deterministic evidence where demanded |
| IDs without hash identity | dense resident ids may differ; correspondence stays exact |
| Canonical semantic serialization | evidence/caching order independent of id allocation |
| Merkle acceleration | hash identifies candidate unchanged regions; verify exact facts |
| Proof-carrying distributed compilation | worker returns region + subject + witness + closure |
| Untrusted build farm | coordinator validates; heterogeneous workers safe |
| Optimization marketplace | external provider proposes candidate + proof + cost; core validates |
| Hardware vendor semantic providers | vendor supplies lawful realization candidates without source intrinsics |

ONE-ID law preserved: hashes accelerate search; they do not become semantic identity.

---

## Architectural moat (summary)

Push hardest on **interoperable algebras** over one identity set so that:

```text
compiler optimization
query planning
partial evaluation
incremental computation
automatic differentiation
program synthesis
hardware synthesis
distributed placement
foreign adaptation
```

are one family of graph queries — the largest unexplored moat still available to Idol.

---

## How to use this file

1. Before proposing a new subsystem, locate the family here and express it as
   graph facts/laws/candidates first.
2. Record new families here when discovery proves they are not reducible.
3. Tie implementation work to open `gaps/GAP-*.md` obligations; this file does not
   replace gap authority.
