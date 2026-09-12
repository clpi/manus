| field | value |
|---|---|
| title | PERF-MONOTONE program |

| # | directive |
|---|---|
| 1 | Durable program for historical compiler exploitation and monotone performance admission in Idol. |
| 2 | Main never loses an already-known lawful realization or an already-measured performance point merely because a new experiment lands. |

| section |
|---|---|
| Principle |

| # | directive |
|---|---|
| 1 | A known compiler technique is not adopted by slowly rediscovering it under a new name. |
| 2 | The route is: |

| # | directive |
|---|---|
| 1 | known technique → recover its semantic precondition → express that precondition in Idol facts → reuse/adapt the mature algorithm as a realization producer → prove its output equivalent → retain it alongside other candidates |

| # | directive |
|---|---|
| 1 | The opposite — rejecting a technique because it is "LLVM-like" and then rebuilding it under a new Idol name — is forbidden. |

| # | directive |
|---|---|
| 1 | Competitors are oracles, never floors. |
| 2 | C, clang, GCC, Rust, Zig, Cranelift, Wasmtime, hand assembly, tuned libraries, GPUs and existing algorithms are things to beat, not limits to reach. |
| 3 | The floor is physics, information, and required observation. |

<!-- idol-perf-matrix:v1:begin -->

| # | directive |
|---|---|
| 1 | No agent may implement a known optimization family until this row identifies the best existing implementation or reference and explicitly states what Idol adds beyond it. |

| technique | precedent | reference | idol prerequisite | idol implementation | status | benchmark |
| --- | --- | --- | --- | --- | --- | --- |
| constant folding | all optimizing compilers | GCC/LLVM/any folder | determined application fact → realization zero | pending | missing | constant expression |
| constant propagation / SCCP | Wegman/Zadeck lineage | GCC/LLVM | fact lattice over graph identities | GAP-175/197 | partial | constant paths |
| bit-known propagation | GCC/LLVM | KnownBits/bit CCP | information quotient on integer facts | GAP-175/176 | research | bit assertions |
| value-range propagation | GCC/LLVM/JITs | range domains + transfer functions | range facts | pending | partial | bounded comparisons |
| copy propagation | GCC/LLVM | standard SSA algorithms | equivalence of semantic values | pending | missing | redundant bindings |
| common-subexpression elimination | classic compilers | value numbering | witnessed denotational equivalence | GAP-178 | research | shared subexpressions |
| GVN | GCC/LLVM family | mature value-numbering algorithms | equivalence cache/index | GAP-178 | research | redundant values |
| PRE | GCC/LLVM | anticipatability/availability algorithms | candidate movement under effect/causal facts | pending | missing | hoisted expressions |
| DCE | every optimizer | mature liveness algorithms | demand quotient = none | pending | partial | dead bindings |
| ADCE | LLVM | backwards demand from observable roots | semantic observation closure | pending | missing | unused branches |
| dead store elimination | GCC/LLVM | MemorySSA/dataflow methods | no observer between updates | pending | missing | redundant stores |
| load elimination | GCC/LLVM/JITs | alias + memory versioning | place/effect equivalence | pending | missing | redundant loads |
| store forwarding | machine/JIT compilers | standard memory-dependence logic | place/version facts | pending | missing | forward stores |
| jump threading | GCC/LLVM | path-sensitive CFG algorithms | conditional facts eliminate alternative | pending | missing | folded jumps |
| if conversion | GCC/LLVM/backend compilers | branch→select/cmov heuristics | alternative realization | pending | missing | selects |
| tail merging | GCC/LLVM/linkers | equivalent suffix detection | shared physical realization | pending | missing | common tails |
| switch lowering | GCC/LLVM | jump table/tree/bit tests | realization based on cardinality/density | pending | missing | dispatch density |
| null-check elimination | managed/JIT compilers | dominance/range proofs | descriptor/refinement facts | pending | missing | safe access |
| bounds-check elimination | JVM/JS/array compilers | range + induction analysis | shape/range witness | pending | missing | safe indexing |
| loop canonicalization | LLVM/GCC | recurrence/causal normalization | recurrence facts | pending | missing | loop forms |
| LICM | LLVM/GCC | standard loop analysis | relation independent of recurrence state | pending | missing | hoisted invariants |
| induction-variable recognition | GCC/LLVM | IV analysis | recurrence facts | GAP-145/134 | missing | loops |
| induction-variable elimination | GCC/LLVM | IV equivalence | recurrence equivalence | GAP-145/134 | missing | loop variables |
| strength reduction | GCC/LLVM | cheaper equivalent realization | recurrence/operator facts | pending | missing | multiplications |
| scalar evolution / recurrence analysis | classic IV/SCEV compilers | LLVM ScalarEvolution | recurrence facts | GAP-145/134 | missing | affine recurrence |
| loop rotation | LLVM | schedule candidate | schedule fact | pending | missing | loop entry |
| loop peeling | optimizing compilers | schedule candidate | schedule + unroll fact | pending | missing | boundary peel |
| loop unrolling | virtually all compilers | schedule candidate | schedule fact | pending | missing | loop body |
| unroll-and-jam | LLVM/GCC/MLIR | schedule candidate | schedule fact | pending | missing | unroll+jam |
| loop unswitching | GCC/LLVM | invariant alternative extraction | invariant + effect facts | pending | missing | loop split |
| loop fusion | LLVM/MLIR/Polly | common dependency/dataflow region | dependence facts | pending | missing | fused loops |
| loop fission/distribution | polyhedral/MLIR | schedule candidate | dependence facts | pending | missing | split loops |
| loop interchange | polyhedral compilers | schedule candidate | dependence facts | pending | missing | loop order |
| skewing | polyhedral systems | schedule candidate | dependence facts | pending | missing | loop skew |
| tiling/blocking | Polly/MLIR/Halide | layout × schedule × cache realization | shape/demand facts | pending | missing | loop tiling |
| strip mining | vector/polyhedral compilers | schedule candidate | schedule fact | pending | missing | vector strip |
| reduction recognition | vector/polyhedral compilers | associativity/commutativity laws | relation law facts | pending | missing | reductions |
| scan recognition | array/functional compilers | recurrence law | recurrence facts | pending | missing | scans |
| closed-form recurrence elimination | scalar evolution/symbolic compilers | theorem-answer realization | recurrence facts | GAP-145/134 | missing | O(1) recurrences |
| periodicity/cycle detection | specialized optimizers | quotient/fixed-point realization | fixed-point facts | pending | missing | cyclic recurrences |
| software pipelining | production backends/VLIW | machine schedule realization | schedule fact | pending | missing | pipelined loops |
| prefetch insertion | GCC/LLVM/MLIR | memory-traffic realization | memory demand facts | pending | missing | memory traffic |
| mem2reg | LLVM/GCC | physical memory never needed | place facts | pending | missing | alloca promotion |
| SROA | LLVM/GCC | aggregate representation never materializes | aggregate demand | pending | partial | structs |
| scalar replacement of objects | HotSpot/JITs | object identity unobserved | escape + uniqueness facts | pending | missing | object split |
| argument promotion | LLVM | by-ref operand only read → pass value | demand + place facts | pending | missing | pass by value |
| escape analysis | JVM/Go/JITs | escape fact | escape, lifetime, provenance | pending | partial | allocation removal |
| partial escape analysis | Graal/HotSpot research | conditional materialization | conditional escape facts | pending | missing | conditional alloc |
| stack allocation | managed compilers | lifetime/escape realization | lifetime facts | pending | missing | stack objects |
| allocation sinking | JVM/JITs | materialize only at observation | effect/demand facts | pending | missing | sink alloc |
| object virtualization | Graal/JVM | semantic object with zero physical object | identity/demand facts | pending | missing | virtual objects |
| refcount elimination | Swift/ARC optimizers | ownership/use facts | ownership facts | pending | missing | refcnt removal |
| copy elision | C++/Rust/compiler backend | logical copy but identical physical realization | provenance equivalence | pending | missing | elided copies |
| move propagation | Rust/C++ | ownership transfer | ownership facts | pending | missing | moves |
| buffer reuse | tensor compilers | last-use + uniqueness | use facts | pending | missing | buffer reuse |
| field reordering | PGO/layout optimizers | representation search | access evidence + layout | pending | missing | layout |
| hot/cold field splitting | runtime/PGO systems | access evidence + layout | access facts | pending | missing | hot/cold split |
| pointer compression | VMs | representation-range facts | range facts | pending | missing | compressed ptrs |
| tag packing | runtimes/functional compilers | state cardinality → minimum bits | cardinality facts | pending | missing | tags |
| NaN boxing / tagged unions | dynamic VMs | candidate physical representation | representation facts | pending | missing | boxing |
| small-object/string optimization | C++ runtimes/Swift/etc. | cardinality/extent-driven representation | size/cardinality facts | pending | missing | small objects |
| SoA↔AoS | HPC/tensor systems | table representation candidate | layout facts | pending | missing | SoA/AoS |
| sparse formats | sparse compilers | shape/density realization | shape/density facts | pending | missing | sparse layout |
| dictionary encoding | databases/columnar engines | representation candidate | value distribution facts | pending | missing | dict encode |
| bitsets/bitmap indexes | database/SETL-style systems | bounded-domain set realization | domain facts | pending | missing | bitmap sets |
| function inlining | every high-quality compiler | eliminate application boundary if profitable | demand + cost facts | pending | partial | call elimination |
| partial inlining | GCC/LLVM | hot semantic region extraction | region demand | pending | missing | partial call |
| indirect inlining | GCC/LLVM/JITs | exact/guarded relation identity | relation identity facts | pending | missing | indirect call |
| interprocedural constant propagation | GCC/LTO | fact propagation across application boundary | reachability facts | pending | missing | cross-module const |
| function cloning | GCC/LLVM/JITs | specialized realization keyed on relevant facts | demand facts | pending | missing | clones |
| call-site specialization | JITs/GHC | application-shape specialization | call-shape facts | pending | missing | call variants |
| devirtualization | GCC/LLVM/JVM | cardinality of admissible relation identities | relation cardinality | pending | missing | virtual dispatch |
| speculative devirtualization | GCC/JITs | guarded witness | runtime evidence | GAP-182 | research | guarded devirt |
| whole-program DCE | LTO/MLton | world/demand reachability | reachability facts | pending | missing | dead code |
| dead argument elimination | LLVM/GHC | argument demand | demand facts | pending | missing | unused args |
| return-value specialization | functional/JIT compilers | result-pack demand | demand facts | pending | missing | return variants |
| closure specialization | functional compilers/JITs | capture-shape facts | capture facts | pending | missing | closure variants |
| defunctionalization | whole-program functional compilers | finite relation identity set | finite relation facts | pending | missing | defunctionalize |
| closure conversion | functional compilers | capture realization | capture facts | pending | missing | closures |
| monomorphization | MLton/Rust/C++ | descriptor specialization | descriptor facts | pending | missing | mono copies |
| defunctorization | MLton | sealed module/world specialization | world facts | pending | missing | functor elim |
| ICF | GCC/linkers | physical sharing of equivalent implementations | equivalence witness | pending | missing | identical code |
| interprocedural alias/modref | GCC/LLVM | relation effect facts | effect facts | pending | missing | mod/ref |
| LTO | GCC/LLVM | cross-home semantic visibility | reachability facts | pending | missing | whole program |
| ThinLTO | LLVM | compact summaries + selective importing | semantic summaries | pending | missing | incremental SHC |
| incremental LTO cache | ThinLTO | semantic-ID/fact keyed cache | stable semantic IDs | pending | missing | incremental |
| loop vectorization | GCC/LLVM | vector realization of independent applications | independence + shape | pending | missing | vector loops |
| SLP vectorization | GCC/LLVM | pack isomorphic scalar applications | isomorphic facts | pending | missing | SLP packs |
| runtime loop versioning | GCC/LLVM | guarded vector vs scalar candidate | runtime evidence | GAP-182 | research | versioned loops |
| vector reduction | vectorizers | relation laws + SIMD reduction | reduction facts | pending | missing | vector reduce |
| horizontal ops | backend compilers | machine realization | target facts | pending | missing | h-ops |
| gather/scatter | vector/tensor compilers | shape/layout fact | layout facts | pending | missing | gather/scatter |
| alignment specialization | GCC/LLVM | guarded representation fact | alignment evidence | pending | missing | aligned access |
| width specialization | modern backends | target capability | target facts | pending | missing | width variants |
| predication/masking | GPU/vector backends | alternative/causal realization | causal facts | pending | missing | predication |
| superword-level parallelism | LLVM family | pack formation | pack facts | pending | missing | SLP |
| FMA recognition | backend compilers | arithmetic-equivalence realization | equivalence facts | pending | missing | FMA |
| rotate/bitfield/popcount idioms | machine combiners | target intrinsic realization | target facts | pending | missing | bit idioms |
| saturating arithmetic idioms | DSP/vector compilers | relation law + machine intrinsic | target facts | pending | missing | sat arith |
| address-mode folding | machine backends | physical realization | target facts | pending | missing | addr modes |
| load/store combining | GCC/LLVM | memory realization | memory facts | pending | missing | mem combine |
| instruction scheduling | every serious backend | physical schedule | target facts | pending | missing | scheduling |
| register allocation | every native compiler | physical allocation only | interference facts | pending | missing | regalloc |
| spill placement | every backend | costed realization | interference facts | pending | missing | spilling |
| rematerialization | native compilers | recompute vs store | cost facts | pending | missing | remat |
| register coalescing | native compilers | physical copy elimination | copy facts | pending | missing | coalescing |
| monomorphic inline cache | Smalltalk/Self/JS VMs | runtime evidence for one relation/shape | runtime evidence | GAP-182 | research | one-shape calls |
| polymorphic inline cache | Self/V8/etc. | finite relation/shape cardinality evidence | runtime evidence | GAP-182 | research | few-shape calls |
| megamorphic fallback | dynamic VMs | generic candidate retained | cardinality facts | GAP-182 | research | megamorphic |
| hidden classes/maps/shapes | Self/V8 | table-shape identity cache | shape facts | GAP-182 | research | shape cache |
| shape transitions | Self/V8 | observed structural evolution | shape facts | GAP-182 | research | transitions |
| property-offset specialization | JS VMs | shape witness → direct field realization | shape facts | GAP-182 | research | fast property |
| type feedback vectors | JS VMs | runtime fact evidence | runtime evidence | GAP-182 | research | feedback |
| guarded specialization | every modern JIT | conditional witness | conditional witness | GAP-182 | research | guards |
| deoptimization | Self/JVM/V8 | assumption invalidation | assumption facts | GAP-182 | research | deopt |
| uncommon-trap/deferred slow cases | Self/V8 | cold alternatives omitted from fast realization | demand facts | GAP-182 | research | cold paths |
| tiered compilation | HotSpot/V8 | realization-depth economics | tier facts | pending | missing | tiers |
| baseline compiler | V8 Liftoff/JVM tiers | low-cost realization | tier facts | pending | missing | baseline |
| optimizing tier | C2/TurboFan/Graal | expensive candidate | tier facts | pending | missing | optimizing tier |
| OSR | JVM/JITs | replace active realization | reentry facts | pending | missing | OSR |
| code aging/eviction | dynamic VMs | realization cache management | cache facts | pending | missing | code aging |
| lazy feedback allocation | V8 | acquire information only when ROI warrants | ROI facts | GAP-182 | research | lazy feedback |
| code caching | V8/JVM | persisted physical realization | cache facts | pending | missing | code cache |
| background compilation | VMs | off-critical-path realization | schedule facts | pending | missing | background |
| adaptive recompilation | Self/HotSpot | evidence refinement | evidence facts | GAP-182 | research | adapt |
| unboxing specialization | JVM/JS | representation facts | representation facts | pending | missing | unbox |
| scalar replacement/virtual objects | JVM/Graal | object realization zero | escape/identity facts | pending | missing | virtual objects |
| call-target specialization | Self/JS | exact relation identity | relation identity | GAP-182 | research | call target |
| strictness analysis | GHC/functional compilers | demand/evaluation fact | demand facts | GAP-175/187 | research | strictness |
| usage/cardinality analysis | GHC | demand cardinality | demand cardinality | GAP-175/187 | research | cardinality |
| absent argument elimination | GHC | argument demand = zero | demand facts | GAP-175/187 | research | absent args |
| one-shot analysis | GHC | use cardinality = ≤1 | demand facts | GAP-175/187 | research | one-shot |
| worker/wrapper | GHC | specialized physical calling convention | demand facts | GAP-175/187 | research | worker/wrapper |
| unboxing | GHC/MLton | native representation | representation facts | GAP-175/187 | research | unbox |
| constructor-product analysis | GHC | shape/pack facts | pack facts | GAP-187 | research | products |
| CPR analysis | GHC | result-pack representation | result facts | GAP-175/187 | research | CPR |
| call-pattern specialization | GHC SpecConstr | application-shape specialization | shape facts | GAP-175/187 | research | SpecConstr |
| typeclass specialization | GHC | witness-known specialization | witness facts | pending | missing | typeclass spec |
| cross-module specialization | GHC | semantic-summary specialization | summaries | pending | missing | cross-module |
| input/output mode analysis | Mercury/logic compilers | relation slot-mode facts | relation mode | GAP-187 | research | modes |
| determinism inference | Mercury | solution-cardinality facts | cardinality | GAP-187 | research | determinism |
| producer-before-consumer reordering | Mercury | semantic scheduling | scheduling | GAP-187 | research | goal order |
| choice-point elimination | deterministic logic compilation | zero search state when cardinality ≤1 | cardinality | GAP-187 | research | no choice |
| committed choice | Mercury/concurrent logic | demand selects first solution | demand | GAP-187 | research | committed |
| uniqueness analysis | Mercury | ownership/use fact | ownership | GAP-187 | research | uniqueness |
| destructive update under uniqueness | Mercury | in-place realization | uniqueness | GAP-187 | research | in-place |
| clause indexing | Prolog implementations | application-alternative indexing | index facts | pending | missing | clause index |
| last-call optimization | Prolog/WAM | tail relation realization | tail facts | pending | missing | LCO |
| trail elimination | logic compilers | omit rollback history when unnecessary | effect facts | pending | missing | no trail |
| mode-specialized unification | Prolog/Mercury | same relation, different knowledge | mode facts | GAP-187 | research | mode unify |
| tabling/memoized relation evaluation | tabled logic systems | recurring pure application → fixed-point/cache | recurrence facts | pending | missing | tabling |
| constraint propagation before branching | CLP/Andorra lineage | constraint solving before search | constraint facts | GAP-198 | research | CLP |
| flow-sensitive type inference | CMUCL/SBCL | fact refinement | type facts | pending | missing | flow types |
| union/member type refinement | CMUCL | descriptor/refinement facts | refinement | pending | missing | union refine |
| type-test branch refinement | CMUCL | path-sensitive facts | path facts | pending | missing | type branch |
| open coding | Lisp compilers | direct realization candidate | target facts | pending | missing | open code |
| compiler macros | Common Lisp | user-provided optimization candidate | user candidate | pending | missing | macros |
| optimization policy | CL compilers | target/world objective facts | objective | pending | missing | policy |
| untagged number representation | CMUCL/SBCL | native representation | representation | pending | missing | untagged |
| source transforms | Lisp compilers | equivalence candidate | equivalence | pending | missing | transforms |
| inline expansion | Lisp compilers | application boundary elimination | demand | pending | partial | inlining |
| efficiency notes | CMUCL | semantic frontier explanation | missing frontier | pending | missing | diagnostics |
| byte compilation for cold code | Lisp compilers | realization depth economy | tier facts | pending | missing | byte code |
| direct threading | Forth/VMs | extremely low compile-latency execution | tier facts | pending | missing | direct thread |
| indirect threading | Forth/VMs | portable/cold realization | tier facts | pending | missing | indirect thread |
| token threading | VMs | compact representation | tier facts | pending | missing | token thread |
| TOS register caching | VM/JIT | pack/register realization | register facts | pending | missing | TOS cache |
| static superinstructions | Forth/VMs | known application sequence fusion | sequence facts | pending | missing | superinstr |
| dynamic superinstructions | Gforth/VMs | profile/trace-driven fusion | trace facts | pending | missing | dynamic super |
| code copying | Forth/VMs | cheap baseline native generation | tier facts | pending | missing | code copy |
| dispatch-jump elimination | VMs | fused application realization | sequence facts | pending | missing | no dispatch |
| primitive replication | VMs | context-specialized physical code | context facts | pending | missing | replicate |
| threaded-code patching | VMs | dynamic adaptation | change facts | pending | missing | patch |
| image persistence | Forth/VMs | cached semantic/runtime world | cache facts | pending | missing | image |
| integer-set/polyhedral iteration domains | Polly/MLIR | recurrence/domain facts | domain facts | pending | missing | poly domain |
| exact affine dependence analysis | Polly | legality witness | dependence facts | pending | missing | affine deps |
| schedule-tree search | Halide/MLIR | realization candidates | schedule facts | pending | missing | schedule tree |
| loop tiling | polyhedral/MLIR | schedule | schedule facts | pending | missing | tiling |
| loop permutation | polyhedral/MLIR | schedule | schedule facts | pending | missing | permute |
| fusion/fission | polyhedral/MLIR | schedule | schedule facts | pending | missing | fuse/fission |
| OpenMP extraction | polyhedral | parallel realization | effect facts | pending | missing | parallel |
| SIMD exposure | polyhedral | vector realization | vector facts | pending | missing | simd expose |
| DMA insertion | tensor compilers | placement realization | place facts | pending | missing | DMA |
| cache tiling | polyhedral | memory-hierarchy realization | cache facts | pending | missing | cache tile |
| register tiling | polyhedral | target schedule | target facts | pending | missing | reg tile |
| tensor layout transforms | tensor compilers | representation | layout facts | pending | missing | tensor layout |
| operator fusion | tensor compilers | semantic application fusion | demand facts | pending | missing | op fusion |
| quantization transforms | tensor compilers | observation/precision demand | precision facts | pending | missing | quantize |
| autoscheduling | Halide/MLIR | realization search | schedule search | pending | missing | autoschedule |
| e-graph rebuilding | equality saturation | egg | equivalence facts | GAP-178 | research | e-graphs |
| congruence closure | equality saturation | egg/Cooper | equivalence facts | GAP-178 | research | congruence |
| e-class analyses | equality saturation | egg | equivalence facts | GAP-178 | research | e-class |
| rewrite scheduling | equality saturation | egg | equivalence facts | GAP-178 | research | rewrites |
| extraction | equality saturation | egg | cost extraction | GAP-178 | research | extract |
| SMT equivalence checking | solver-based | SMT | witnessed equivalence | GAP-178 | research | smt eq |
| bitvector synthesis | superoptimization | Souper/Minotaur | exact equivalence | pending | missing | bvec synth |
| bounded enumerative search | superoptimization | STOKE/Souper | exact equivalence | pending | missing | search |
| counterexample-guided synthesis | superoptimization | Souper/Minotaur | exact equivalence | pending | missing | cegis |
| dead-section elimination | linkers | artifact graph slicing | reachability | pending | missing | dead section |
| COMDAT/ICF | linkers | physical sharing | equivalence | pending | missing | ICF |
| linker relaxation | linkers | late physical layout optimization | target facts | pending | missing | relax |
| basic-block/function layout | PGO | profile-driven machine placement | profile facts | pending | missing | layout |
| hot/cold partition | PGO/linker | realization layout | access facts | pending | missing | hot/cold |
| relocation relaxation | linkers | target materialization | target facts | pending | missing | relax rel |
| constant merging | linkers | physical constant sharing | equivalence | pending | missing | const merge |
| string pooling | linkers | representation cache | equivalence | pending | missing | string pool |
| post-link PGO | PGO | machine evidence feeding semantic IDs | profile facts | pending | missing | post-link |

<!-- idol-perf-matrix:v1:end -->

<!-- idol-perf-contract:v1:begin -->

| # | directive |
|---|---|
| 1 | Every merge touching parser, semantic analysis, graph, demand, realization, codegen, runtime, foreign bridge, optimizer, proof engine, layout, or ABI must satisfy: |

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

| # | directive |
|---|---|
| 1 | Main goes green only if every row above passes. |

<!-- idol-perf-contract:v1:end -->

| section |
|---|---|
| What remains genuinely Idol-specific |

| # | directive |
|---|---|
| 1 | The novelty budget is concentrated here: |

| # | directive |
|---|---|
| 1 | one semantic id |
| 2 | exact lawset-preserving foreign ingestion |
| 3 | world/projection algebra |
| 4 | demand as observer quotient |
| 5 | cross-law semantic equivalence |
| 6 | representation theorem FFI |
| 7 | persistent cross-representation equivalence |
| 8 | semantic continuity across revisions |
| 9 | fact provenance/trust |
| 10 | candidate-set monotonicity |
| 11 | value-of-information optimization |
| 12 | semantic lower-bound debt |
| 13 | cross-law fusion |
| 14 | semantic frontier exposed to agents |

| # | directive |
|---|---|
| 1 | Everything below that should be aggressively informed by prior art. |

| section |
|---|---|
| Three hard monotonicity laws |

| # | directive |
|---|---|
| 1 | **knowledge:** stronger facts never destroy semantic truth |
| 2 | **capability:** stronger compiler knowledge never destroys a lawful realization |
| 3 | **performance:** a new candidate never replaces a known-better candidate without evidence |

| section |
|---|---|
| Frontier experiment classification |

| kind | may land on main? | selection effect |
| --- | --- | --- |
| fact producer | yes after soundness proof | refines candidates |
| candidate producer | yes after correctness proof | only adds candidate |
| cost/evidence producer | yes after calibration | may change ranking |
| semantic law change | only via C0 | may change what candidates are legal |

| section |
|---|---|
| Historical champion realization |

| # | directive |
|---|---|
| 1 | For every semantic benchmark region: |

| # | directive |
|---|---|
| 1 | champion: revision realization target objective cost vector |

| # | directive |
|---|---|
| 1 | The champion remains a conceptual competitor until either a new candidate dominates it or a semantic-law change invalidates its equivalence. |

| section |
|---|---|
| Permanent PERF-MONOTONE gate |

| # | directive |
|---|---|
| 1 | For every merge touching compiler stages, the gate must answer: |

| # | directive |
|---|---|
| 1 | baseline revision |
| 2 | dirty: false |
| 3 | correctness: no previous-correct cases lost, no new wrong answers, no new crashes |
| 4 | capability: previously accepted applications still accepted |
| 5 | candidate: no previously lawful candidate removed |
| 6 | performance: no unresolved-or-worse replacement of a previous best |
| 7 | floors: C-equivalent, previous-head winner, and historical-best winner retained |
| 8 | evidence: every chosen replacement has measured/proven dominance |
| 9 | losses: named individually |
