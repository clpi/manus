| field | value |
|---|---|
| title | Frontier Research Survey: Breakthroughs for the Idol Compiler (2024–2026) |
| date | 2026-09-11. |
| status | design survey. |
| scope | what the Idol project can adopt *now* for measurable performance/power wins, plus near-term and research bets. |
| idol context assumed | self-hosted compiler  (v5) emitting ARM64 machine code directly (no C/assembler/linker); sibling workstreams building ARM64+ELF, x86_64+ELF, x86_64+PE/COFF, ARM64+PE/COFF backends; current standing vs clang -O3 is 10/10 wins on compile time (35–45% faster) and object size (45–50% smaller), runtime ties on 3/10 benchmarks with 7 runtime losses under repair (loop-idiom evaluation, reassociation, reciprocal division, LICM, dead-loop elimination). |

| # | directive |
|---|---|
| 2 | Companion to `docs/design/optimum.md` (what "exceeds literal optimum" means) and `docs/design/proofunity.md` (proof-assistant unification). |

| # | directive |
|---|---|
| 2 | The goal is not parity: exceed the literal optimum by maximal margins, and be more powerful than all languages combined. |

| # | directive |
|---|---|
| 1 | **How to read this document.** Six domains (§1–§6). |
| 2 | Each finding has a one-paragraph summary, an applicability verdict (Yes/No with one-line reason), and — when Yes — a concrete integration proposal naming the Idol workstream, an implementation sketch in Idol terms, and an expected measurable win. §7 is the applicability table. §8 is the prioritized plan: P0 = implementable now with measurable wins (leads the document), P1 = near-term, P2 = research bets. §9 records findings that contradict the current approach, evaluated honestly. |

---

| section |
|---|---|
| 1. Compilers |

| section |
|---|---|
| F1. SuperCoder: LLM assembly superoptimization (2025) |

| # | directive |
|---|---|
| 1 | **Summary.** Li et al., arXiv 2505.11480 (May 2025). |
| 2 | The first large-scale benchmark for assembly superoptimization: 8,072 real assembly programs (averaging 130 lines), versus prior datasets capped at 2–15 straight-line programs. |
| 3 | 23 LLMs evaluated |
| 4 | Claude-opus-4 reaches 51.5% test-passing and 1.43× mean speedup over gcc -O3. |
| 5 | Fine-tuning Qwen2.5-Coder-7B with RL on a correctness+speedup reward yields **SuperCoder: 95.0% correctness, 1.46× mean speedup over gcc -O3**, improvable further with Best-of-N sampling and iterative refinement. |
| 6 | First demonstration that LLMs beat industry compilers on real assembly at scale — superoptimization escapes the straight-line toy domain. |
| 7 | (Related: **LLM-Vectorizer**, Taneja et al. |
| 8 | 2025 — *formally verified* auto-vectorization via LLM + verifier; **autograph** — graph-based deep-RL loop vectorization, 2.49× over NeuroVectorizer and **3.69× over -O3** on Polybench, spj.science.org.) |

| # | directive |
|---|---|
| 1 | **Verdict: Yes** — offline superoptimization is directly how `optimum.md` §1 defines the L3 (superoptimizer bound) oracle, and 1.46× over gcc -O3 is the clearest 2025 evidence that "beats the industry compiler" headroom is real. |

| # | directive |
|---|---|
| 1 | **Integration.** |

| # | directive |
|---|---|
| 1 | *Workstream:* bench methodology (`bench/`, `docs/design/optimum.md`) + compiler optimizations (`lib/compiler/native.id`). |
| 2 | *Sketch:* two lanes. (a) **Oracle lane:** for each benchmark hot loop, extract the Idol-emitted assembly and the oracle assembly, run an offline superoptimization pass (SuperCoder-style: fine-tuned local 7B model, free local inference only — no paid providers; or classical enumerative Souper-style search over basic blocks with an SMT equivalence check) to establish the L3 bound: "no shorter equivalent sequence of ≤ N instructions exists." Where the superoptimizer beats the L2 hand oracle, the oracle is revised per the falsification protocol — this *is* the protocol, automated. (b) **Rule-mining lane:** every superoptimizer find is generalized to a declarative rewrite rule, verified once (Alive-style), and baked into `native.id` as a peephole pattern. The compiler stays fast (patterns, not search); the search runs offline, once per rule. |
| 3 | *Expected win:* oracle rigor (L3 bounds on all 10 benchmarks); 1–5% runtime from mined peephole rules; occasional "exceeds optimum" events that are *explained* by construction, which is exactly what `optimum.md` §2 demands. |

| section |
|---|---|
| F2. BOLT: post-link code layout beats late FDO+LTO (Meta/LLVM, ongoing) |

| # | directive |
|---|---|
| 1 | **Summary.** LLVM BOLT (Binary Optimization and Layout Tool), Meta's post-link optimizer, rewrites already-linked binaries using sampled profiles (`perf`): basic-block reordering for fall-through hot paths (`-reorder-blocks=ext-tsp`), function reordering (`-reorder-functions=hfsort`), hot/cold splitting (`-split-functions -split-all-cold`). |
| 2 | The foundational result stands: **up to 8% on datacenter workloads on top of FDO+LTO, up to 20.4% on GCC/Clang binaries on top of FDO+LTO, up to 52.1% without FDO+LTO** (Panchenko et al., CGO 2019; tool in active LLVM development through 2025–26). |
| 3 | The key insight: injecting profile data *late* enables more *accurate* use of it for code layout than early injection enables for optimization passes. |

| # | directive |
|---|---|
| 1 | **Verdict: Yes** — layout is orthogonal to every optimization the sibling workstream is adding, and Idol's direct emission makes it cheaper to implement than for LLVM. |

| # | directive |
|---|---|
| 1 | **Integration.** |

| # | directive |
|---|---|
| 1 | *Workstream:* all backends (`lib/compiler/arm64.id`, `elfarm.id`, `pecoffarm.id`, `pecoffx86.id`) + bench harness (`bench/`). |
| 2 | *Sketch:* implement **post-emit layout as a compiler pass, not an external tool.** Idol already emits the final object directly, so there is no link step to be "post" of: add a layout phase between code emission and object writing. It consumes a profile (edge counts harvested from `bench/` runs of the same binary — the harness already runs 21 interleaved rounds; record taken/not-taken per conditional branch via a lightweight instrumented build), then (1) splits each function into hot/cold regions, (2) orders basic blocks so the hot path falls through (ext-tsp ordering), (3) sorts functions hot-first. Because the emitter owns addresses, no binary rewriting is needed — this is BOLT's win without BOLT's cost. Gate on profile availability; without a profile, keep current layout (zero regression risk). |
| 3 | *Expected win:* 2–8% geomean on branchy code; **5–15% on `predbranch`-class benchmarks** (fewer i-cache misses, fewer taken branches); no compile-time regression on the unprofiled path (Idol's 35–45% compile-time lead is untouched). |

| section |
|---|---|
| F3. PolyTOPS: configurable polyhedral scheduler (CGO 2024) |

| # | directive |
|---|---|
| 1 | **Summary.** Consolaro et al., CGO 2024 (arXiv 2401.06665). |
| 2 | A *configurable* polyhedral scheduler built on isl: instead of one-size-fits-all (Pluto), high-level configurations select scheduling strategies per scenario and per kernel. |
| 3 | Integrated in MindSpore AKG; **geomean 7.66× over isl scheduling on Ascend NPU custom ops, up to 1.80× over Pluto on PolyBench** across multicore architectures. |
| 4 | The advance is configurability: the scheduler that wins on a stencil loses on a reduction, so the scheduler itself becomes a tunable artifact. |

| # | directive |
|---|---|
| 1 | **Verdict: Yes** — loop nests are exactly where Idol currently loses to clang -O3; a small affine scheduler is the principled fix, and PolyTOPS shows even a lightweight configurable one beats Pluto. |

| # | directive |
|---|---|
| 1 | **Integration.** |

| # | directive |
|---|---|
| 1 | *Workstream:* compiler optimizations — the loop-idiom evaluation sibling workstream (`lib/compiler/native.id` loop passes). |
| 2 | *Sketch:* add a **SCoP detector** (static control parts: affine bounds, affine accesses) over Idol loop nests, then a **configurable scheduler** with three canned strategies Idol tunes per loop shape: (a) tile+interchange for stencils/matmul (cache tiling to L1/L2 sizes read from the target descriptor), (b) fusion+parallel-marking for maps, (c) skewing for wavefront dependences. Emit tiled loops directly; no isl dependency (implement the needed Presburger subset natively — Idol's vocabulary already has `lib/math/`; the scheduler needs only bound manipulation and dependence direction vectors for the common cases). Start with (a): rectangular tiling of doubly-nested affine loops. |
| 3 | *Expected win:* **1.5–3× on tiled loop-nest microbenchmarks** vs untiled; closes the largest class of the 7 runtime losses (memory-bound loops where clang's tiling/prefetch wins today). |

| section |
|---|---|
| F4. MLIR RealArith/FixedPointArith: approximation-aware arithmetic dialects (2025) |

| # | directive |
|---|---|
| 1 | **Summary.** Ledoux, Cochard, de Dinechin, DSD/SEAA 2025 work-in-progress. |
| 2 | MLIR dialects that *separate real-valued mathematical intent* (`RealArith`) from *fixed-width machine arithmetic* (`FixedPointArith`), enabling algebraic rewrites and approximation-aware transforms (e.g., polynomial approximation in Horner form with explicit error budgets) that are illegal under conventional `fast-math` semantics. |
| 3 | The abstraction gap between "reals in the programmer's head" and "machine arithmetic in the compiler" is where legal optimization dies; the dialect split reopens it. |

| # | directive |
|---|---|
| 1 | **Verdict: Yes** — this is the most direct route to *legitimately* exceeding an L4 lower bound: change the bound's assumptions with an explicit, auditable error budget instead of hoping the bound was wrong. |

| # | directive |
|---|---|
| 1 | **Integration.** |

| # | directive |
|---|---|
| 1 | *Workstream:* compiler optimizations + proof unification (the error budget is a proof obligation) + bench methodology (new oracle level for approximate benchmarks). |
| 2 | *Sketch:* introduce an Idol **approximation law**: a relation that rewrites real-valued expressions to machine arithmetic *carrying a proven error bound as a witness* (proofunity vocabulary: the bound is the witness of the relation's demand). Examples: Horner-form polynomial evaluation with certified ≤1ulp error; reciprocal-division (already in the sibling workstream) generalized to Newton–Raphson with iteration count chosen from the budget. The bound travels with the value's descriptor; `bench/` oracles for approximate benchmarks record the budget in the oracle `.md`. |
| 3 | *Expected win:* enables optimizations no exact compiler may legally do; **10–40% on transcendental/polynomial-heavy kernels** at a stated error budget; turns "exceeds optimum" from paradox into protocol (the optimum was exact; Idol's is approximate-with-budget). |

| section |
|---|---|
| F5. LLVM vectorizer cost-model lessons, 2024–2025 (RISC-V Europe 2025, LLVM 20) |

| # | directive |
|---|---|
| 1 | **Summary.** LLVM loop-vectorization work reported 2024–2025 (Meijer, LLVM devmtg 2024 |
| 2 | Bradbury/Lau, RISC-V Summit Europe 2025 |
| 3 | LLVM 20): (1) **non-power-of-two SLP vectorization** (RVV `vl` handles arbitrary widths; e.g., 3-wide RGB pixels vectorize directly instead of 2-wide + scalar tail) |
| 4 | (2) `preferFixedOverScalableIfEqualCost()` — on cost ties, prefer fixed-width |
| 5 | (3) **epilogue-vectorization thresholds** — if the trip count is small, all time is spent in the scalar epilogue, so vectorize the epilogue or don't vectorize |
| 6 | (4) **loop peeling** — peel the first iteration so the loop becomes vectorizable |
| 7 | (5) gather/scatter and interleave cost tuning (`MaxInterleaveFactor` ≈ number of SIMD pipes). |
| 8 | Plus Intel 2025 **VLS (variable-length-stride) load grouping**: 3 independent strided loads replaced by one vector load + shuffles. |

| # | directive |
|---|---|
| 1 | **Verdict: Yes** — these are hard-won heuristics the sibling vectorization work can adopt on day one instead of rediscovering them. |

| # | directive |
|---|---|
| 1 | **Integration.** |

| # | directive |
|---|---|
| 1 | *Workstream:* compiler optimizations — vectorization (sibling workstream); `lib/simd.id` already exists as the target vocabulary. |
| 2 | *Sketch:* encode the five lessons as the vectorizer's cost model from the start: fixed-width NEON preference on ties (Apple Silicon has no SVE — see F11, so scalable-vector logic is dead weight on the primary target); epilogue threshold = vectorize only if `trip_count ≥ 2×VF` else scalar; peel-first-iteration for aliasing/unaligned prologues; VLS grouping for strided loads (stride-2/3/4 common in image/audio code). Implement as data (target descriptor tables), not code, so the x86_64 backends reuse the same model with AVX widths. |
| 3 | *Expected win:* avoids the classic "vectorizer makes it slower" regressions that would cost benchmark ties; **1.5–4× on stride-1 FP loops** once the vectorizer lands, with no epilogue-loss cases. |

| section |
|---|---|
| F6. MLGO: learned heuristics in production LLVM (2021–, active 2025–26) |

| # | directive |
|---|---|
| 1 | **Summary.** Google's MLGO (ml-compiler-opt) replaces hand-crafted heuristics with RL-trained models inside LLVM: inlining-for-size (in-tree, up to **7% size reduction** vs -Oz) and register-allocation eviction |
| 2 | Huawei's MLGOPerf extends the inliner to performance (**+1.8–2.2% over O3** on SPEC/CBench). |
| 3 | 2025–26 status: models moving from TF-AOT to TFLite/EmitC in-tree runners; interactive training channels stable. |
| 4 | The lesson is institutional as much as technical: the heuristics a compiler ships can be *learned artifacts* with a training pipeline, not just code. |

| # | directive |
|---|---|
| 1 | **Verdict: Yes, but P2** — Idol's 35–45% compile-time lead would be destroyed by in-compile TF inference; the correct adoption is distilled, not direct. |

| # | directive |
|---|---|
| 1 | **Integration.** |

| # | directive |
|---|---|
| 1 | *Workstream:* compiler optimizations (P2 research bet). |
| 2 | *Sketch:* train offline (any free/local pipeline) on Idol's own benchmark corpus for inline decisions and unroll factors; **distill the policy to small decision trees, then compile the trees to jump tables** inside `native.id` — inference becomes a few integer compares, nanoseconds, zero dependency. The training corpus and distillation script live in `research/`; only the tables ship. |
| 3 | *Expected win:* 1–3% over hand-tuned heuristics with no compile-time cost; the real win is methodological: heuristics become measured artifacts. |

| section |
|---|---|
| F7. autograph: RL loop vectorization, 3.69× over -O3 (2024) |

| # | directive |
|---|---|
| 1 | **Summary.** *Intelligent Computing* 2024 (spj.science.org/doi/10.34133/icomputing.0113): a data-driven graph-based deep-RL framework that predicts vectorization and interleaving factors per loop and injects them as pragmas. **2.49× over NeuroVectorizer, 3.69× over -O3 on Polybench.** The mechanism matters more than the number: the *factors* (VF, interleave) are the learnable artifact, and they transfer. |

| # | directive |
|---|---|
| 1 | **Verdict: Yes (P1)** — same adoption path as F6 but narrower and cheaper: learn (VF, interleave) tables per loop-shape class offline, ship as data. |

| # | directive |
|---|---|
| 1 | **Integration.** |

| # | directive |
|---|---|
| 1 | *Workstream:* compiler optimizations — vectorization + loop passes. |
| 2 | *Sketch:* extend the F5 cost model: where the analytic model is uncertain (unusual trip counts, mixed strides), consult a small learned table keyed by (loop-shape hash → (VF, interleave, unroll)). Train on `bench/` + Polybench-derived Idol programs; table is a few KB in the compiler binary. |
| 3 | *Expected win:* **1.2–2× over analytic-only vectorization** on irregular loops; zero compile-time impact (table lookup). |

---

| section |
|---|---|
| 2. Programming languages |

| section |
|---|---|
| F8. Koka: evidence-passing algebraic effects (Microsoft Research, active 2025–26) |

| # | directive |
|---|---|
| 1 | **Summary.** Koka (Leijen) is the mature reference for algebraic effects with *row-polymorphic effect types*: `traverse : list<int> -> yield ()`, handlers as values, `resume` with checked resume modes. |
| 2 | The 2024–26 implementation advance that matters: the **effect-jit artifact** (se-tuebingen) and the standard compilation strategy of **evidence passing** — effects compile to evidence-vector lookups, not full delimited continuations; open rows are linearized to flat index vectors at compile time (no runtime row structure). |
| 3 | Result: async/await, generators, exceptions as *user libraries* with near-zero abstraction cost. |

| # | directive |
|---|---|
| 1 | **Verdict: Yes** — "more powerful than all languages combined" needs first-class control *without* compiler extensions per feature; evidence passing is the performance story that makes it affordable. |

| # | directive |
|---|---|
| 1 | **Integration.** |

| # | directive |
|---|---|
| 1 | *Workstream:* language power — future Idol effect system (P1 design). |
| 2 | *Sketch:* effects as Idol relations: an effect operation is a `subject:edge(rest)` demand the handler relation satisfies; the compiler lowers handled regions to **evidence-vector passing** (a hidden operand pack, i.e., just another `rest` — no new calling convention, no CPS transform). Row polymorphism maps to Idol's descriptor openness: the effect row is a descriptor the type relation extends. Handlers-as-values fall out of relations-as-values. Benchmark the abstraction cost against a hand-written state machine; target: within 5%. |
| 3 | *Expected win (power):* generators/async/parsers as libraries, statically typed, zero-cost — a capability C/Rust/Go cannot express without runtime or compiler magic. *Performance:* evidence lookup ≈ 1–2 instructions; no allocation on the effect path. |

| section |
|---|---|
| F9. Quantitative Type Theory + Perceus + FBIP: linear values, zero-cost in-place update (2024–26) |

| # | directive |
|---|---|
| 1 | **Summary.** The "Fixed" language project (constructive-programming, 2025–26) combines three 2020s breakthroughs: **QTT** (Quantitative Type Theory — every value tracked as erased / linear / shared), **Perceus** (Leijen's reference counting with reuse analysis), and **FBIP** (Functional But In-Place: linear values are *guaranteed* safe to mutate in place). |
| 2 | The combination: write purely functional code; the compiler produces in-place updates with no allocator traffic, proven memory-clean. |
| 3 | This is the practical payoff of linear types that Rust's borrow checker only approximates (Rust gives safety |
| 4 | QTT+Perceus+FBIP gives *functional code at C speed*). |

| # | directive |
|---|---|
| 1 | **Verdict: Yes** — Idol's power goal plus its performance goal converge here: purity without the allocation tax. |

| # | directive |
|---|---|
| 1 | **Integration.** |

| # | directive |
|---|---|
| 1 | *Workstream:* language power + compiler optimizations (P1). |
| 2 | *Sketch:* add **usage multiplicities** to Idol's descriptor system (erased/linear/shared — see also F10/F11): the compiler's existing "witness" vocabulary already tracks constraint satisfaction; extend it to track *use count*. Linear values get in-place update (no refcount ops at all — stronger than Perceus, which still counts); shared values get Perceus-style reuse analysis; erased values (proofs, types) vanish before codegen. The `subject:edge(rest)` decomposition is multiplicity-aware: a linear subject is consumed by the edge. |
| 3 | *Expected win:* **1.5–3× on allocation-heavy functional benchmarks** (list/tree transforms) via eliminated allocator traffic; enables Idol to claim "purely functional, runs like C" — a power statement no mainstream language makes truthfully. |

| section |
|---|---|
| F10. Two-level linear dependent type theory: erasable proofs, memory-clean programs (Fu & Xi, v2 Oct 2025) |

| # | directive |
|---|---|
| 1 | **Summary.** arXiv 2309.08673 (revised Oct 2025). |
| 2 | A type theory combining linearity and dependency by *stratifying* typing into a logic level and a program level. |
| 3 | Proofs and types inside programs are **fully erasable without changing operational behavior**; heap-based operational semantics proves extracted programs "always make computational progress and run memory clean"; programs reflect into the logic level for deep proofs. |
| 4 | This is the missing link between dependent types (proofunity's direction) and linear resource safety (F9's direction): one system, both properties. |

| # | directive |
|---|---|
| 1 | **Verdict: Yes** — directly serves the proofunity workstream: proofs must cost zero at runtime, and this is the 2025 theory of how. |

| # | directive |
|---|---|
| 1 | **Integration.** |

| # | directive |
|---|---|
| 1 | *Workstream:* proof unification (`lib/proof/`, `docs/design/proofunity.md`). |
| 2 | *Sketch:* adopt the stratification as ProofUnity's phase-2 design: the kernel keeps a **logic level** (propositions, proof terms — fully erased before codegen) and a **program level** (multiplicity-tracked, F9). Erasure is a compiler pass with a machine-checked certificate (the pass from the paper: erasure preserves operational behavior). Idol's law already distinguishes descriptors from identities; the two levels map cleanly: descriptors live at the logic level, identities at the program level. |
| 3 | *Expected win (power):* dependent types + proofs with **zero runtime cost** — removes the standard objection to "one language for programming and proving." *Performance:* erased proofs shrink code and i-cache pressure; measurable on proof-carrying benchmarks. |

| section |
|---|---|
| F11. Dependent multiplicities: resource annotations for higher-order functions (Doré, Jul 2025) |

| # | directive |
|---|---|
| 1 | **Summary.** arXiv 2507.08759. |
| 2 | A dependent linear type theory where a variable's *multiplicity* (use count) can **depend on other variables** — e.g., a higher-order function's argument usage depends on the function argument's behavior. |
| 3 | Inspired by the Dialectica translation; implementable in any dependently-typed language (demonstrated in Agda). |
| 4 | This solves the long-standing expressiveness ceiling of linear type systems: previously, higher-order functions got crude "unbounded" annotations. |

| # | directive |
|---|---|
| 1 | **Verdict: Yes (P2)** — the precision upgrade that makes F9's in-place analysis work through higher-order code (map/fold/combinators), which is where naive linearity gives up. |

| # | directive |
|---|---|
| 1 | **Integration.** |

| # | directive |
|---|---|
| 1 | *Workstream:* language power (P2 research bet, builds on F9/F10). |
| 2 | *Sketch:* when F9's multiplicity analysis meets a higher-order call, instantiate the callee's multiplicity *as a function of the actual argument's descriptor* rather than defaulting to shared. Prototype on `map`/`fold` in the standard library: prove the in-place update safe when the mapped function is linear in its argument. |
| 3 | *Expected win:* extends the F9 1.5–3× win from first-order to higher-order code — the difference between a demo and a language. |

---

| section |
|---|---|
| 3. Formal methods |

| section |
|---|---|
| F12. Lean 4 `grind`: SMT-grade automation inside a proof assistant (2025–26) |

| # | directive |
|---|---|
| 1 | **Summary.** The headline Lean 4 development of 2025–26 (de Moura, "State of Lean," Lean Together 2026): the **`grind` tactic** — SMT-style proof automation combining congruence closure, E-matching, a Cutsat solver for linear integer arithmetic, Gröbner bases for nonlinear arithmetic, and case splitting with non-chronological backtracking. |
| 2 | Shipped across Lean 4.15–4.26 (12 releases in 2025) alongside a rewritten compiler, a module system, coinductive predicates, and `mvcgen` (monadic verification framework). |
| 3 | Separately: **Lean4Lean** — the first machine-checked proof that Lean 4's elaborator and kernel are mutually consistent |
| 4 | Mathlib4 at ~1.4M lines as empirical soundness evidence. |

| # | directive |
|---|---|
| 1 | **Verdict: Yes** — proofunity needs automation or it dies of tedium; `grind` is the 2025 blueprint for what that automation looks like, and its components are all implementable as Idol relations. |

| # | directive |
|---|---|
| 1 | **Integration.** |

| # | directive |
|---|---|
| 1 | *Workstream:* proof unification (`lib/proof/`). |
| 2 | *Sketch:* implement a **grind-like tactic as ordinary Idol relations**: congruence closure over the e-graph of the goal, E-matching against the lemma database, a Cutsat decision procedure for linear integer arithmetic goals (the Idol compiler already reasons about integer bounds for array elimination — share the code), Gröbner basis reduction for nonlinear goals. Each component is a relation; their combination is a tactic relation. Target the proof obligations the compiler itself generates (bounds checks, F4 error budgets, F9 linearity certificates) — automation that pays for itself inside the compiler before it serves users. |
| 3 | *Expected win (power):* closes routine goals automatically — the difference between a proof kernel and a usable proof assistant. *Performance:* discharging bounds checks statically removes runtime checks; 1–3% on bounds-heavy loops. |

| section |
|---|---|
| F13. AI provers: DeepSeek-Prover-V2, Leanstral, AlphaProof (2024–26) |

| # | directive |
|---|---|
| 1 | **Summary.** The AI×proof-assistant pipeline matured: DeepMind's **AlphaProof** (silver-medal IMO in Lean 4), **DeepSeek-Prover-V2** (open-source Lean prover), Mistral's **Leanstral** (Mar 2026 — first open-source proof agent: 120B MoE, Apache 2.0, aimed at real repositories not toy problems), plus **LeanDojo-v2** and Harmonic AI ($100M, 2025) building verified AI on Lean. |
| 2 | The pattern is stable: LLM proposes, kernel checks; untrusted search + trusted checking. |

| # | directive |
|---|---|
| 1 | **Verdict: Yes (P2)** — but only the open, local, free-inference slice: proposals from a local model, checked by Idol's kernel. |
| 2 | Never a paid API in the loop. |

| # | directive |
|---|---|
| 1 | **Integration.** |

| # | directive |
|---|---|
| 1 | *Workstream:* proof unification (P2). |
| 2 | *Sketch:* a `prove` relation that takes a goal, queries a **local** fine-tuned model (7B-class, free inference) for candidate proof terms, and runs each through the kernel; only kernel-accepted terms are kept. The model is trained on Idol's own `test/proofdata/` corpus. This is F1's rule-mining lane applied to proofs: untrusted search, trusted check, baked artifacts. |
| 3 | *Expected win (power):* lemma discovery and proof repair assisted, not manual — multiplies the proof workstream's throughput. No soundness risk: the kernel is the only authority. |

| section |
|---|---|
| F14. PureCake: verified compilation backed by the *official* Armv8 semantics (Kanabar, PhD 2024) |

| # | directive |
|---|---|
| 1 | **Summary.** Hrutvik Kanabar's 2024 Kent PhD advances CakeML two ways: **PureCake**, the first end-to-end verified compiler for a purely functional (Haskell-like) language — reusing CakeML *as an unmodified building block*, which required treating the proof interface (top-level theorems, TCB) as carefully as the code interface; and, crucially, the first compiler correctness theorem **backed by a realistic machine semantics derived from the official Arm ISA specification** — CakeML and the hardware now share one understanding of Armv8 behavior from the same official sources, shrinking the TCB at its root. |

| # | directive |
|---|---|
| 1 | **Verdict: Yes (P1/P2)** — the proof workstream's endgame needs exactly this: Idol's ARM64 emitter is *unverified machine-code emission* |
| 2 | PureCake shows the path from here to verified without rewriting the compiler in a prover. |

| # | directive |
|---|---|
| 1 | **Integration.** |

| # | directive |
|---|---|
| 1 | *Workstream:* proof infrastructure + ARM64 backend (P1 design, P2 proof). |
| 2 | *Sketch:* (P1) formalize the *encoding* layer of `arm64.id` against the official Armv8 ISA spec (instruction encodings are the silent-error surface CakeML's paper calls out: overflows, fields with special meanings). A differential tester compares Idol's emitted bytes against the spec's decode on the benchmark corpus — this alone catches miscompilations no test suite would. (P2) prove the peephole/lowering relations correct against the spec semantics, following PureCake's "reuse the verified compiler as a building block" pattern: verify *passes*, keep the unverified driver. |
| 3 | *Expected win:* miscompilation-class bugs become impossible-by-proof in the verified passes; the differential tester is immediately useful (P1) and has already been shown to find real encoding bugs in mature compilers. |

| section |
|---|---|
| F15. ML-guided quantifier selection in cvc5; Z3 arithmetic advances (2024–26) |

| # | directive |
|---|---|
| 1 | **Summary.** Two SMT advances: (1) **ML for quantifier selection in cvc5** (arXiv 2408.14338, IJAR Feb 2026) — gradient-boosted trees predict which quantifiers to instantiate during solving, "considerably" improving first-order quantified performance on Mizar-derived problems |
| 2 | (2) **Z3's new arithmetic solver** (4.12.5+, Bjorner et al.) — measurable gains over the legacy solver on QF_LIA/QF_NIA, competitive with cvc5/Yices2/MathSAT5. |
| 3 | Context: SMT-COMP-level solvers keep improving ~yearly; cvc5 leads on equality+nonlinear, Z3 on bitvectors in places, Yices2 on raw speed for QF problems. |

| # | directive |
|---|---|
| 1 | **Verdict: Yes (P1, tooling)** — wherever Idol's proof automation or superoptimizer equivalence checks call an SMT solver, the solver choice is now a measured decision, not a default. |

| # | directive |
|---|---|
| 1 | **Integration.** |

| # | directive |
|---|---|
| 1 | *Workstream:* proof infrastructure + F1 rule-mining lane. |
| 2 | *Sketch:* standardize the offline toolchain on **cvc5 (with its ML-guided quantifier instantiation) for quantified goals** and **Z3 ≥4.12.5 for bitvector equivalence checks** in the superoptimizer lane; add a solver back-to-back differential test to the proof test suite (disjoint unsolved sets across solvers are well documented — a portfolio beats any single solver). No Idol dependency on solver binaries at user compile time; solvers live in `research/`/`tools/`. |
| 3 | *Expected win:* more goals closed automatically (F12), more rewrite rules verified per compute-hour (F1); portfolio solving is a free 5–15% on solver-bound tasks. |

---

| section |
|---|---|
| 4. Architecture |

| section |
|---|---|
| F16. Intel APX: 32 GPRs, 3-operand NDD, conditional load/store (2025–26) |

| # | directive |
|---|---|
| 1 | **Summary.** Intel Advanced Performance Extensions — the biggest x86 general-purpose change in decades, shipping in Nova Lake (AVX10.2 + APX): **16 new GPRs (R16–R31, 32 total)**, NDD 3-operand forms for integer ops (no more destructive two-operand encoding), **conditional load/store/compare** with NF (no-flags) variants — explicitly designed to *expand if-conversion* past CMOV's limits and cut branch-mispredict penalties on deep out-of-order cores — plus PUSH2/POP2 and zero-upper SETcc. |
| 2 | Intel's claim: ~10% fewer loads, >20% fewer stores from better register retention. |
| 3 | Compiler support is real: GCC 15 (full), LLVM 22, Linux 6.16 (Jul 2025, XSAVE context-switch support). |

| # | directive |
|---|---|
| 1 | **Verdict: Yes** — the x86_64 backend workstreams should be APX-*shaped* now, even before the hardware is on the test bench. |

| # | directive |
|---|---|
| 1 | **Integration.** |

| # | directive |
|---|---|
| 1 | *Workstream:* x86_64 backends (`pecoffx86.id`, x86_64+ELF) — P1 hardware, P0 design. |
| 2 | *Sketch:* (P0, now) design the x86_64 register allocator over a **32-GPR abstract file** and the encoder over **NDD-capable forms**, with APX emission behind a CPUID gate (`CPUID.(EAX=7,ECX=1):EDX[21]`); on non-APX hardware emit legacy forms — one allocator, two encodings. (P0, now) **widen if-conversion**: the F2 profile data marks unpredictable branches (`predbranch`!); convert them to branchless selects (CMOV today, APX conditional load/store when gated on). EVEX-encoded NF forms avoid the flags-dependency chains that currently limit if-conversion. (P1) when Nova Lake hardware is available, flip the gate and measure. |
| 3 | *Expected win:* P0: **10–40% on mispredict-bound microbenchmarks** from aggressive if-conversion (this is the `predbranch` fix, principled); register pressure relief from 32 GPRs: fewer spills, **2–5% on register-heavy code** once hardware lands. P1 hardware win compounds. |

| section |
|---|---|
| F17. ARM SME/SME2 on Apple M4: >2.3 FP32 TFLOPS, JIT kernels beat Accelerate BLAS (2024–26) |

| # | directive |
|---|---|
| 1 | **Summary.** "Hello SME!" (SC-W 2024, arXiv 2409.18779): Apple's **M4 is the first publicly available SME-capable chip** (ARMv9.2a, SME+SME2, SVL=512b); microbenchmarks show **>2.3 FP32 TFLOPS** from the SME unit, FP32-centric, with a two-step ZA transfer discipline for max bandwidth. |
| 2 | Their **JIT SME small-matmul generator outperforms Apple's Accelerate BLAS in almost all tested configurations** — hand-tuned vendor libraries lose to generated kernels. |
| 3 | 2026 follow-ups: **SMEPilot** (arXiv 2606.16332) roofline-models SME for LLM inference |
| 4 | KleidiAI (Arm, active 2026) ships open SME/SME2 micro-kernels |
| 5 | Snapdragon 8 Elite Gen 5 and Dimensity 9500 add SME2 — SME is becoming the mobile/edge matrix ISA. |
| 6 | Compiler support: Clang/GCC 14+ ACLE intrinsics, `-march=armv8-a+sme`. |

| # | directive |
|---|---|
| 1 | **Verdict: Yes — P0.** The dev machine is an **Apple M4** (confirmed 2026-09-11): this is measurable *today*, on the machine where Idol is built and benchmarked. |
| 2 | And Idol emits ARM64 directly — no waiting on LLVM's auto-vectorizer to learn SME. |

| # | directive |
|---|---|
| 1 | **Integration.** |

| # | directive |
|---|---|
| 1 | *Workstream:* ARM64 backend (`lib/compiler/arm64.id`) + loop-idiom evaluation (sibling workstream) + `lib/simd.id`. |
| 2 | *Sketch:* recognize the **matmul idiom** (the sibling workstream's loop-idiom evaluation is already building this) and, for FP32 matmul with compatible shapes, emit a **streaming-SVE SME kernel**: `SMSTART`, outer-product accumulation via `FMOPA` into ZA tiles (16×16 FP32 per instruction at SVL=512 → 512 FLOP/instruction), two-step ZA load/store, `SMSTOP`. **Runtime dispatch**: feature-detect SME at startup (`sysctl`/HWCAP); M4+ → SME kernel, older → NEON kernel, with a correctness-differential test between the two paths in the test suite. Keep the kernel generator *in the compiler* (Hello SME! shows JIT beats the vendor library — Idol doesn't need to link Accelerate at all). Note the constraint the paper documents: **M4 does not support non-streaming SVE** (SIGILL outside streaming mode) — all SME code must run under `SMSTART`/locally-streaming. |
| 3 | *Expected win:* **5–20× on FP32 matmul microbenchmarks on M4** vs scalar/NEON baselines (paper: 2.3 TFLOPS achievable; JIT beats Accelerate BLAS); this single idiom is the highest-FLOP item in any ML-flavored benchmark and directly serves `lib/onnx.id`/`lib/ml` users. |

| section |
|---|---|
| F18. KleidiAI: open Arm micro-kernel library (Arm, 2024–26) |

| # | directive |
|---|---|
| 1 | **Summary.** Arm's **KleidiAI** (github.com/arm-software/kleidiai): open, dependency-free, allocation-free C micro-kernels for Neon/SVE/SME/SME2 (matmul, softmax, etc.) with a stable stateless API, designed for third-party runtime integration. |
| 2 | The industry pattern is now explicit: compilers *recognize idioms and call micro-kernels* rather than generating every loop from scratch. |

| # | directive |
|---|---|
| 1 | **Verdict: Yes (P1)** — Idol shouldn't hand-roll every kernel; but Idol emits machine code directly, so "calling" means vendoring, not linking. |

| # | directive |
|---|---|
| 1 | **Integration.** |

| # | directive |
|---|---|
| 1 | *Workstream:* ARM64 backend + `lib/simd.id` (P1). |
| 2 | *Sketch:* vendor the KleidiAI *algorithms* (not the C) as Idol-native kernel templates in the compiler: the loop-idiom recognizer (F17's sibling workstream) maps idioms → kernel template → direct machine-code emission with Idol's own calling convention. No libc, no dynamic allocation — consistent with Idol's zero-dependency emission. SME2 multi-vector outer products (MOPA with multiple tiles) are the 2026 upgrade path once the recognizer handles them. |
| 3 | *Expected win:* expert-level kernels for every recognized idiom from day one; **2–8× on dot-product/softmax/reduction idioms** on NEON today, more under SME2; frees the compiler team from hand-tuning each kernel. |

| section |
|---|---|
| F19. AVX10.2 / AMX on x86 (2025–26) |

| # | directive |
|---|---|
| 1 | **Summary.** Intel's vector story converges: **AVX10.2** (Nova Lake) unifies AVX-512-class ops across P- and E-cores (no more downclocking lottery); **AMX** (tile matrix multiply, bf16/int8/fp16) is established for inference. |
| 2 | Compiler support tracks APX (GCC 15, LLVM 22). |

| # | directive |
|---|---|
| 1 | **Verdict: Yes (P1, x86_64 backends only)** — same treatment as F16/F17: recognize matmul/convolution idioms, emit AMX tile sequences behind a CPUID gate, AVX10.2 as the vector baseline for the x86_64 vectorizer. |

| # | directive |
|---|---|
| 1 | **Integration.** |

| # | directive |
|---|---|
| 1 | *Workstream:* x86_64 backends (P1). |
| 2 | *Sketch:* mirror the F17 idiom→kernel path for AMX (`TILELOADD`, `TDPBF16PS`/`TDPBSSD`); vectorizer cost model (F5/F7) parameterized by AVX10.2 widths. Gated; measured when hardware exists. |
| 3 | *Expected win:* **4–10× on quantized matmul** on AMX hardware; AVX10.2 removes the P-core/E-core vectorization cliff. |

| section |
|---|---|
| F20. Apple Silicon has no SVE — design accordingly (confirmed fact) |

| # | directive |
|---|---|
| 1 | **Summary.** Verified 2024–26 across multiple sources: Apple M4 supports **SME/SME2 in streaming mode only**; non-streaming SVE instructions fault (SIGILL). |
| 2 | M1–M3 have neither SVE nor SME (only NEON/AdvSIMD). |
| 3 | No Apple Silicon supports SVE2. |

| # | directive |
|---|---|
| 1 | **Verdict: No** (for SVE/SVE2 codegen on Idol's primary target) — with a positive corollary. |

| # | directive |
|---|---|
| 1 | **Integration.** |

| # | directive |
|---|---|
| 1 | *Workstream:* ARM64 backend — a *negative* result with a design consequence. |
| 2 | *Sketch:* **do not build an SVE codegen path for Apple targets**; the vector story on macOS is NEON (fixed 128-bit) + SME (streaming, M4+). This *simplifies* the F5 cost model (prefer-fixed-width always wins the tie on Apple) and means the SME kernel generator (F17) is the *only* scalable-vector investment needed. (Linux ARM64/ELF backend keeps an SVE gate for server chips where SVE2 exists.) |
| 3 | *Expected win:* saves a wasted backend investment; focuses vectorization effort where the FLOPS are (SME). |

---

| section |
|---|---|
| 5. Performance |

| section |
|---|---|
| F21. If-conversion renaissance via APX conditional ops (2025–26) |

| # | directive |
|---|---|
| 1 | **Summary.** Intel's APX paper and the 2025–26 compiler work make explicit what the `predbranch` benchmark already tells us: on deep, wide out-of-order cores, **data-dependent branch mispredicts dominate**, and predictor improvements can't fix them — only *removing the branch* can. |
| 2 | APX's conditional load/store/compare + NF (no-flags) forms are designed to push if-conversion "to much larger code regions" than CMOV ever could. |
| 3 | LLVM 22/GCC 15 implement the expanded if-conversion. |

| # | directive |
|---|---|
| 1 | **Verdict: Yes — P0** (the ARM64 half today; the APX half gated). |

| # | directive |
|---|---|
| 1 | **Integration.** |

| # | directive |
|---|---|
| 1 | *Workstream:* compiler optimizations + all backends. |
| 2 | *Sketch:* (now, ARM64) use F2 profile data to find branches with ~50/50 taken rates (unpredictable by construction), and convert single-assignment conditional updates to `CSEL`/conditional-select sequences — ARM64 already has the instructions; what's missing is the *profile-driven policy*. (x86_64) CMOV today; APX conditional forms behind the F16 CPUID gate. Add a `predbranch`-style microbenchmark per backend measuring mispredicts (PMU counters) before/after. |
| 3 | *Expected win:* **10–40% on unpredictable-branch microbenchmarks**; directly attacks one of the 7 runtime losses if any loss is branch-bound. |

| section |
|---|---|
| F22. Post-link insight applied at emit time (BOLT lesson, restated for Idol) |

| # | directive |
|---|---|
| 1 | Covered in F2. |
| 2 | Restated here as a performance-domain verdict: the 2024–26 literature keeps confirming that **layout is the highest-ROI late optimization** (BOLT 20.4% over FDO+LTO |
| 3 | Propeller's basic-block sections in the same family). |
| 4 | Idol's direct emission captures this without a linker. |

---

| section |
|---|---|
| 6. AI/ML for code |

| section |
|---|---|
| F23. Verified neural code generation: LLM-Vectorizer (2025) |

| # | directive |
|---|---|
| 1 | **Summary.** Taneja et al. |
| 2 | 2025 (cited in the SuperCoder paper): LLM proposes vectorizations, a **formal verifier** accepts/rejects — *verified* auto-vectorization, not heuristic. |
| 3 | The architecture (neural proposal + symbolic check) is the one that survives contact with production compilers. |

| # | directive |
|---|---|
| 1 | **Verdict: Yes (P1)** — the template for every neural component Idol adopts: the neural net never has authority; the checker does. |

| # | directive |
|---|---|
| 1 | **Integration.** |

| # | directive |
|---|---|
| 1 | *Workstream:* compiler optimizations (vectorizer) + proof infrastructure. |
| 2 | *Sketch:* in the vectorizer (F5/F7), add a neural *proposal* lane (local model, free inference): propose (VF, interleave, schedule); accept only what the dependence checker + equivalence check prove legal. Proposals that verify get cached as rules; the checker is the same SMT-backed equivalence used in F1. |
| 3 | *Expected win:* vectorizer coverage on loops the analytic model rejects (unusual dependence shapes); correctness by construction — no "AI made the compiler miscompile" class of bug. |

| section |
|---|---|
| F24. Learning-based superoptimization at the bench, not in the compiler (2025–26) |

| # | directive |
|---|---|
| 1 | Covered in F1 (SuperCoder) and F6/F7 (MLGO/autograph). |
| 2 | The 2024–26 consensus verdict for Idol: **learning belongs in the offline lanes** (oracle establishment, rule mining, heuristic tables) and **never in the compile hot path** except as compiled-down tables (F6/F7). |
| 3 | This preserves the 35–45% compile-time win while capturing the 1.46×-class optimization wins. |

---

| section |
|---|---|
| 7. Applicability table |

| # | Breakthrough | Domain | Verdict | Why (one line) |
|---|--------------|--------|---------|----------------|
| F1 | SuperCoder LLM superoptimization (1.46×/gcc -O3) | Compilers | **Yes** | Automates `optimum.md` L3 oracle bounds + mines peephole rules |
| F2 | BOLT post-link layout (≤20.4% over FDO+LTO) | Compilers | **Yes** | Layout is orthogonal to all 7 in-flight fixes; Idol emits directly so it's nearly free |
| F3 | PolyTOPS configurable polyhedral scheduler (1.8×/Pluto) | Compilers | **Yes** | Loop nests are where Idol loses; configurable scheduler beats one-size-fits-all |
| F4 | MLIR RealArith/FixedPointArith approximation dialects | Compilers | **Yes** | Only legitimate way to beat an L4 bound: explicit error budgets |
| F5 | LLVM vectorizer cost-model lessons (2024–25) | Compilers | **Yes** | Five hard-won heuristics to adopt on day one of the vectorizer |
| F6 | MLGO learned heuristics | Compilers | **Yes (P2)** | Learn offline, distill to jump tables — never TF inference in the compiler |
| F7 | autograph RL vectorization (3.69×/-O3) | Compilers | **Yes (P1)** | (VF, interleave) tables per loop-shape class, shipped as data |
| F8 | Koka evidence-passing algebraic effects | PL | **Yes** | First-class control without compiler extensions; ~2 instructions per operation |
| F9 | QTT + Perceus + FBIP linear in-place update | PL | **Yes** | Purely functional code at C speed: 1.5–3× on allocation-heavy benchmarks |
| F10 | Two-level linear dependent type theory | PL | **Yes** | Erasable proofs + memory-clean programs: the theory proofunity needs |
| F11 | Dependent multiplicities | PL | **Yes (P2)** | Makes F9's analysis precise through higher-order code |
| F12 | Lean 4 `grind` tactic | Formal | **Yes** | SMT-grade automation as Idol relations; discharges the compiler's own proof obligations |
| F13 | AI provers (DeepSeek-Prover-V2, Leanstral) | Formal | **Yes (P2)** | Untrusted local-model search + trusted kernel check only |
| F14 | PureCake official-Armv8-backed verification | Formal | **Yes** | Path from unverified emitter to verified passes; differential tester is P1-useful now |
| F15 | ML-guided cvc5 quantifiers; Z3 arithmetic | Formal | **Yes** | Solver portfolio for the F1/F12 lanes; free 5–15% on solver-bound tasks |
| F16 | Intel APX (32 GPRs, NDD, cond. load/store) | Arch | **Yes** | Shape the x86_64 backends now; if-conversion is the `predbranch` fix |
| F17 | ARM SME/SME2 on Apple M4 (>2.3 TFLOPS) | Arch | **Yes (P0)** | Dev machine is M4; JIT SME matmul beats Accelerate BLAS; Idol emits ARM64 directly |
| F18 | KleidiAI open micro-kernels | Arch | **Yes (P1)** | Vendor the algorithms as Idol-native kernel templates, not the C |
| F19 | AVX10.2 / AMX | Arch | **Yes (P1)** | x86_64 idiom→kernel path; removes the P/E-core vectorization cliff |
| F20 | No SVE on Apple Silicon | Arch | **No** | Negative result: skip SVE codegen on Apple; NEON + SME only |
| F21 | If-conversion renaissance (APX cond. ops) | Perf | **Yes (P0)** | Profile-driven CSEL/CMOV on unpredictable branches; 10–40% on mispredict-bound code |
| F22 | Layout is the highest-ROI late optimization | Perf | **Yes** | Same as F2, performance-domain restatement |
| F23 | LLM-Vectorizer (verified neural vectorization) | AI/ML | **Yes (P1)** | Neural proposes, symbolic checker disposes — the only safe neural architecture |
| F24 | Learning offline, tables in the compiler | AI/ML | **Yes** | Consensus rule protecting the 35–45% compile-time lead |

| # | directive |
|---|---|
| 1 | **Explicitly rejected:** wholesale MLIR adoption (would destroy the compile-time and object-size leads; adopt its *ideas* — declarative patterns, progressive lowering, approximation dialects — in Idol-native form; see §9) |
| 2 | SVE codegen for Apple targets (F20); paid-API inference anywhere in the toolchain (all neural lanes use free/local inference or compiled tables). |

---

| section |
|---|---|
| 8. Prioritized integration plan |

| section |
|---|---|
| P0 — implementable now, measurable wins (do first) |

| # | directive |
|---|---|
| 1 | Post-emit code layout (Idol-native BOLT-lite).** *Workstream:* all backends + `bench/`. *Sketch:* layout phase between emission and object writing: hot/cold split, ext-tsp block ordering, hot-first function sort, driven by edge profiles harvested from the existing 21-round bench runs; no-profile → current layout (no regression). *Win:* 2–8% geomean; **5–15% on `predbranch`-class benchmarks**; zero compile-time cost on the unprofiled path. |

| # | directive |
|---|---|
| 1 | SME matmul kernels on Apple M4 (hardware-gated, NEON fallback).** *Workstream:* ARM64 backend + loop-idiom evaluation + `lib/simd.id`. *Sketch:* matmul-idiom recognition → streaming-SVE SME kernel emission (`SMSTART`, `FMOPA` 16×16 FP32 tiles = 512 FLOP/instruction at SVL=512, two-step ZA transfers, `SMSTOP`); runtime feature detection with NEON fallback; differential test between paths. |
| 2 | Respect the M4 constraint: no non-streaming SVE (SIGILL). *Win:* **5–20× on FP32 matmul on M4** (paper: >2.3 TFLOPS achievable |
| 3 | JIT kernels beat Accelerate BLAS); the single biggest FLOP lever in the project, measurable on the dev machine today. |

| # | directive |
|---|---|
| 1 | Offline superoptimization loop: L3 oracles + peephole rule mining.** *Workstream:* `bench/` + `docs/design/optimum.md` + `lib/compiler/native.id`. *Sketch:* extract hot-loop assembly per benchmark; run enumerative/LLM superoptimization offline (free local inference only) to establish L3 superoptimizer bounds; generalize finds to verified declarative rewrite rules baked into `native.id`. |
| 2 | The compiler stays pattern-driven and fast; search happens once per rule. *Win:* L3 bounds on all 10 benchmarks (the falsification protocol, automated); **1–5% runtime** from mined rules; explained "exceeds optimum" events. |

| # | directive |
|---|---|
| 1 | Profile-driven if-conversion on unpredictable branches.** *Workstream:* compiler optimizations + all backends. *Sketch:* F2 profiles mark ~50/50 branches; convert single-assignment conditional updates to branchless selects (`CSEL` on ARM64 now, `CMOV` on x86_64 now, APX conditional load/store behind the F16 CPUID gate later) |
| 2 | PMU-counter microbenchmark per backend. *Win:* **10–40% on mispredict-bound microbenchmarks**; the principled `predbranch` fix. |

| # | directive |
|---|---|
| 1 | Vectorizer cost model with 2024–25 LLVM lessons (adopt as the sibling vectorizer lands).** *Workstream:* compiler optimizations — vectorization; `lib/simd.id`. *Sketch:* fixed-width-NEON preference on ties, epilogue threshold (`trip ≥ 2×VF` else scalar), first-iteration peeling, VLS strided-load grouping — as target-descriptor data shared across backends. *Win:* no vectorizer regressions (protects benchmark ties); **1.5–4× on stride-1 FP loops** when the vectorizer lands. |

| section |
|---|---|
| P1 — near-term (next workstream cycles) |

| # | directive |
|---|---|
| 1 | **P1-1. PolyTOPS-lite:** SCoP detection + configurable scheduler (tile/interchange first); 1.5–3× on tiled loop nests; closes memory-bound runtime losses. *(F3)* |
| 2 | **P1-2. QTT multiplicities → guaranteed in-place update:** erased/linear/ shared usage in the descriptor system; linear values mutate in place with zero refcount ops; 1.5–3× on allocation-heavy functional code; "purely functional, runs like C." *(F9)* |
| 3 | **P1-3. Evidence-passing effect handlers:** effects as relations, handlers as values, evidence vectors as hidden operand packs; generators/async as typed user libraries at ~2 instructions per operation. *(F8)* |
| 4 | **P1-4. `grind`-like tactic as Idol relations:** congruence closure + E-matching + Cutsat + Gröbner, aimed first at the compiler's own proof obligations (bounds checks, F4 error budgets, F9 linearity); removes runtime checks (1–3% on bounds-heavy loops) and makes proofunity usable. *(F12)* |
| 5 | **P1-5. Approximation law with certified error budgets:** RealArith-style separation of real intent from machine arithmetic; the error bound is a proof witness; enables legally-unbeatable-by-exact-compilers transforms (10–40% on polynomial/transcendental kernels). *(F4)* |
| 6 | **P1-6. KleidiAI algorithms as Idol-native kernel templates:** idiom → template → direct emission; 2–8× on dot/softmax/reduction idioms; SME2 multi-tile MOPA as the upgrade path. *(F18)* |
| 7 | **P1-7. Learned (VF, interleave) tables** per loop-shape class, shipped as data; 1.2–2× over analytic-only vectorization on irregular loops. *(F7)* |
| 8 | **P1-8. SMT solver portfolio** (cvc5 ML-quantifiers for quantified goals, Z3 ≥4.12.5 for bitvectors) in `research/`/`tools/`; differential tester for the ARM64 *encoding* layer against the official ISA spec (first half of F14). *(F15, F14)* |
| 9 | **P1-9. x86_64: AMX tile sequences + AVX10.2 vector baseline** behind CPUID gates; 4–10× on quantized matmul when hardware lands. *(F19)* |
| 10 | **P1-10. Two-level linear dependent types** as ProofUnity phase 2: logic-level proofs fully erased before codegen (zero runtime cost). *(F10)* |

| section |
|---|---|
| P2 — research bets |

| # | directive |
|---|---|
| 1 | **P2-1. MLGO-style learned heuristics distilled to jump tables:** offline training on Idol's corpus for inline/unroll decisions; inference becomes integer compares; 1–3% over hand-tuned heuristics, zero compile-time cost. *(F6)* |
| 2 | **P2-2. Verified neural proposal lanes** (LLM-Vectorizer pattern): local model proposes, symbolic checker disposes — for vectorization, then peephole rules, then proof terms (F13's `prove` relation on `test/proofdata/`). The kernel/checker always has sole authority. *(F23, F13)* |
| 3 | **P2-3. PureCake-style verified passes:** prove lowering/peephole relations against the official Armv8 semantics; miscompilation-class bugs impossible-by-proof in verified passes. *(F14)* |
| 4 | **P2-4. Dependent multiplicities** for higher-order precision in the F9 analysis (prototype on `map`/`fold`). *(F11)* |

---

| section |
|---|---|
| 9. Findings that contradict the current approach (honest evaluation) |

| # | directive |
|---|---|
| 1 | **"Direct emission can't do link-time optimization, so it must lose to LTO/BOLT."** — *Evaluated: no contradiction.* BOLT's wins come from *late layout*, not from linking per se. |
| 2 | Idol emits the final object directly, so a layout phase between emission and object writing captures BOLT's win class with *less* machinery than LLVM needs (no binary rewriting). |
| 3 | And Idol's monolithic emission (`monolith.id`) is already whole-program by construction — the LTO use case (cross-module optimization) doesn't exist as a separate problem. **Recommendation: adopt F2 (P0-1); the approach stands.** |

| # | directive |
|---|---|
| 1 | **"Adopt MLIR instead of a hand-rolled direct emitter."** — *Evaluated: reject for infrastructure, adopt for ideas.* MLIR's transformation-oriented design, declarative patterns, and progressive lowering are genuinely the 2020s' best compiler-construction ideas — but MLIR-based compilers are notoriously slow to compile with, which would directly destroy Idol's 35–45% compile-time lead (the lead that funds everything else), and the C++ toolchain dependency contradicts zero-dependency direct emission. **Recommendation: reimplement the ideas (F1's declarative verified rules, F4's approximation dialect, progressive idiom lowering in F17/F18) in Idol-native form; do not take the dependency.** |

| # | directive |
|---|---|
| 1 | **"Superoptimization / neural methods in the compile loop."** — *Evaluated: contradicts the compile-time goal; adopt offline only.* Souper-style synthesis and LLM inference are orders of magnitude too slow for a compiler whose headline win is compiling 35–45% faster than clang. |
| 2 | The 2024–26 consensus (SuperCoder as benchmark tool, MLGO distilling to in-tree models, LLM-Vectorizer's neural-propose/symbolic-check split) points the same way: **learning and search live offline; only verified rules and compiled tables ship in the compiler** (F1, F6, F7, F23, F24). |
| 3 | The approach stands, with this boundary made explicit. |

| # | directive |
|---|---|
| 1 | **"SVE2 is the ARM vector future; invest there."** — *Evaluated: wrong for Idol's primary target.* Apple Silicon (M1–M4) has no SVE/SVE2 |
| 2 | M4 has streaming-only SME/SME2. |
| 3 | An SVE codegen investment would be dead code on every machine Idol benchmarks on. **Recommendation: F20 — NEON + SME only on Apple; keep an SVE gate solely for the Linux ARM64 server backend.** |

| # | directive |
|---|---|
| 1 | **"Exceeding the literal optimum is impossible by definition."** — *Evaluated: the paradox dissolves twice.* First, `optimum.md` already handles it: beating the oracle falsifies the oracle (L2/L3), and the finding improves the bound. |
| 2 | Second, F4 (approximation with certified error budgets) and F1 (superoptimizer-found sequences the L2 author missed) are 2024–25 results showing *where* the headroom actually lives. **Recommendation: the methodology stands |
| 3 | F4 gives it a new legal move (beat exact-optimum with budgeted approximation).** |

---

| section |
|---|---|
| 10. Source index |

| # | directive |
|---|---|
| 1 | SuperCoder (2505.11480, May 2025) — https://arxiv.org/abs/2505.11480 |
| 2 | LLM-Vectorizer (Taneja et al. 2025) — via SuperCoder §related work |
| 3 | autograph (Intelligent Computing 2024) — https://spj.science.org/doi/10.34133/icomputing.0113 |
| 4 | BOLT (Panchenko et al., CGO 2019; LLVM in-tree, active 2025–26) — https://llvm.googlesource.com/llvm-project/+/91423d71938d7a1dba27188e6d854148a750a3dd/bolt/ |
| 5 | PolyTOPS (CGO 2024, arXiv 2401.06665) — https://arxiv.org/abs/2401.06665?context=cs.CL |
| 6 | RealArith/FixedPointArith MLIR dialects (DSD/SEAA 2025 WIP) — https://hal.science/hal-05385229v1/file/dsdwip2025.pdf |
| 7 | LLVM vectorizer advances (Meijer, LLVM devmtg 2024; Bradbury/Lau, RISC-V Europe 2025) — https://llvm.org/devmtg/2024-10/slides/techtalk/Meijer-Loop-Vectorisation.pdf |
| 8 | MLGO / ml-compiler-opt (Google, active 2026) — https://github.com/google/ml-compiler-opt |
| 9 | MLGOPerf (Ashouri et al., 2207.08389) — http://arxiv.org/pdf/2207.08389 |
| 10 | Koka (Leijen; koka-lang, active 2026) — https://github.com/koka-lang/koka |
| 11 | Fixed / QTT+Perceus+FBIP (constructive-programming, 2025–26) — https://github.com/constructive-programming/fixed |
| 12 | Two-level linear dependent type theory (Fu & Xi, arXiv 2309.08673v2, Oct 2025) — https://arxiv.org/abs/2309.08673v1 |
| 13 | Dependent multiplicities (Doré, arXiv 2507.08759, Jul 2025) — https://arxiv.org/abs/2507.08759v1 |
| 14 | Lean 4 `grind` / State of Lean (Lean Together 2026) — https://www.youtube.com/watch?v=Wu8hyxqOar8 |
| 15 | Lean4Lean / Mathlib4 scale (2026) — via llvm-mlir-book ch.184 |
| 16 | DeepSeek-Prover-V2; Leanstral (Mistral, Mar 2026); AlphaProof (DeepMind) |
| 17 | PureCake (Kanabar, Kent PhD 2024) — https://kar.kent.ac.uk/105396/ |
| 18 | ML-guided quantifier selection in cvc5 (arXiv 2408.14338v2, IJAR Feb 2026) — https://arxiv.org/abs/2408.14338v2 |
| 19 | Intel APX (spec; GCC 15 / LLVM 22 / Linux 6.16) — https://www.intel.com/content/www/us/en/developer/articles/technical/advanced-performance-extensions-apx.html |
| 20 | Hello SME! (SC-W 2024, arXiv 2409.18779) — http://arxiv.org/abs/2409.18779v1 |
| 21 | SMEPilot (arXiv 2606.16332, 2026) — https://arxiv.org/pdf/2606.16332.pdf |
| 22 | KleidiAI (Arm, active 2026) — https://github.com/arm-software/kleidiai |
| 23 | Apple M4 SME programming notes — https://github.com/minoki/zenn/blob/HEAD/english/arm-scalable-matrix-extension.md |
