# Frontier Research Log (append-only)

Companion to `docs/design/frontier-research.md` (the F1–F24 baseline survey,
2026-09-11) and `docs/design/frontier-loop.md` (the permanent process spec).

- Findings are numbered in **one global sequence** continuing the survey's
  F1–F24. This log's first entry therefore starts at **F25**.
- Entries are **never rewritten**. Corrections, updates, and follow-ups
  arrive as new entries that reference the finding number.
- Each entry records: scan date, scan window, method/sources, the new
  findings (full evaluation for the top tier, short evaluation otherwise),
  and the next scan due date.

---

## Entry #1 — 2026-09-11: first continuous scan

**Scan window:** 2026-06-11 → 2026-09-11 for `[NEW]` items (published in the
~90 days before the baseline survey's research cut), plus `[MISSED]` items of
any age the baseline survey did not cover.

**Method:** targeted sweeps of arXiv cs.PL / cs.PF / cs.AR, LLVM discourse and
recent PRs, CACM 2026 research highlights, CGO'25 proceedings, DeepMind /
Google Research publications, RISC-V Summit Europe 2026 proceedings,
BSDCan / AsiaBSDCon 2026 CHERI updates, Modular/Mojo kernel docs, and the
Verus release stream. Deduped against F1–F24 by topic, not just by title.

**Next scan due:** 2026-09-18 (weekly cadence per `frontier-loop.md`).

**Headline:** no new finding displaces a current P0 on expected win (P0-2's
5–20× SME matmul remains the largest single lever). Three findings enter the
plan — F25 (equality saturation: new P0-6 + P1 lane), F26 (machine outlining:
new P0-7 size track), F27 (AlphaEvolve-style evolutionary discovery: P2).
Seven more are logged as F28–F34 (short evaluations).

---

### F25. Equality saturation / e-graphs as Idol's optimization substrate [MISSED]

**Summary.** The 2025–26 state of e-graph optimization, missed entirely by
the baseline: egg was published as a **CACM 2026 Research Highlight**
(Willsey et al., DOI 10.1145/3815481) — "50x speedups in neural network
optimizations, 63% smaller hardware circuits, and even production compilers
being rebuilt around e-graphs"; Herbie got 3,000× faster by integrating egg.
**DialEgg** (Zayed & Dubach, CGO'25) is a dialect-agnostic MLIR optimizer via
egglog. And in April 2026 Chris Fallin documented Cranelift's **ægraph**:
the production-relevant variant — acyclic, applies rewrite rules greedily at
node creation rather than saturating, and gets **GVN + LICM +
rematerialization "for free"** during translation in and out
(bytecodealliance/rfcs#27). The field has converged on two lanes: greedy
acyclic rewriting in the compile hot path, full saturation offline.

**Verdict: Yes** — this is the largest missed item in the baseline. It is
also a philosophical fit: Idol is a *law-governed* language, and equality
saturation is literally "optimizations as laws + search for the best
equivalent program." The sibling workstream's 7 runtime losses include
**reassociation** — the textbook e-graph win, since no phase-ordered pass
sequence can find the optimal parenthesization that associativity +
commutativity saturation finds routinely.

**Integration.**
- *Workstream:* compiler optimizations (`lib/compiler/native.id`) + bench
  methodology (F1 oracle lane).
- *Sketch:* two lanes, mirroring the field's convergence. **(a) Hot path
  (P0): ægraph-style greedy rewriting.** At IR-node construction time, apply
  Idol's existing rewrite laws greedily (acyclic by construction, bounded
  cost): this yields global value numbering, LICM, and rematerialization
  decisions with ~constant overhead per node — no saturation, no threat to
  the 35–45% compile-time lead. The data structure is ~2,000 LOC
  (hashcons + union-find + level annotation); the rules already exist as
  Idol laws, they only need extraction-cost annotations. **(b) Offline lane
  (P1): full egglog-style saturation** over hot functions to *discover* new
  laws; each discovered law is verified through the F1 SMT lane and baked in
  as a declarative rule — this is F1's rule-mining lane generalized from
  peepholes to whole functions.
- *Expected win:* **2–10% runtime geomean** from phase-ordering elimination
  (the class of wins LLVM leaves on the table between passes); directly
  attacks the reassociation and loop-idiom runtime losses. Compile-time cost
  of lane (a) is bounded and small; lane (b) is offline.

**Priority: new P0-6 (lane a) + P1 (lane b).** Does not beat P0-2 (5–20×) or
P0-4 (10–40% mispredict-bound); rivals P0-1 (2–8%) and P0-3 (1–5%) on
expected geomean.

### F26. Machine Outliner + PGO-guided outlining + ICF for object size [MISSED]

**Summary.** LLVM's Machine Outliner keeps advancing through 2025–26 and the
baseline never mentions it: **profile-guided outlining** (Ellis Hoag,
llvm-project PR #154437) adds `optimistic-pgo` / `conservative-pgo` modes so
only *cold* code is outlined — balancing size against performance;
**leaf-descendants outlining** (PR #90275) shows **~3% text-segment reduction
on Clang/LLD over an -Oz baseline**; and on LLVM-TestSuite/CTMark (arm64,
-Oz) the outliner saves ~8% code size. LLVM 22.1's BOLT adds a **lite mode on
AArch64 that reuses cold code instead of duplicating it** — a size win from
the layout family.

**Verdict: Yes** — half of Idol's headline is object size (45–50% smaller
than clang -O3), and the baseline has *no* size-track P0. This is the
cheapest unclaimed win in the survey: it is purely additive, cannot regress
runtime when gated on cold code, and Idol's direct emission makes it simpler
than LLVM's (no MIR layer to thread through).

**Integration.**
- *Workstream:* all backends (ARM64 first) + `bench/` size tracking.
- *Sketch:* an **Idol-native outliner as a post-emit pass**: run a suffix
  array over each function's emitted instruction stream, outline repeated
  sequences ≥ N instructions into shared `OUTLINED_*` functions (ARM64:
  `BL` + return via LR; respect the F20 constraint — NEON/SME sequences are
  never outlined across streaming-mode boundaries). Gate on the P0-1
  profile lane: outline cold code aggressively, keep hot code inline
  (LLVM's optimistic/conservative distinction, adopted wholesale). Add
  **identical code folding (ICF)** at emit time: hash emitted function bytes,
  fold duplicates — free for a direct emitter. Wire both into the bench
  harness's size column with a per-benchmark size-before/after report.
- *Expected win:* **3–8% further text-size reduction** on top of the current
  45–50% lead (LLVM-measured: ~3% on large binaries over -Oz, ~8% on
  CTMark arm64 -Oz); zero runtime regression on the profile-gated path;
  compile-time cost is one linear suffix pass.

**Priority: new P0-7 (size track).** Does not beat any P0 on *runtime* — it
is not trying to; it extends the size lead, which is half the project's
public scorecard.

### F27. AlphaEvolve-style evolutionary algorithmic discovery, offline [NEW]

**Summary.** Novikov et al., arXiv 2506.13131 (Jun 2025) — Google DeepMind's
**AlphaEvolve**, an evolutionary coding agent: LLMs propose code mutations,
automated evaluators score them, the population evolves. Results: a **4×4
complex matmul in 48 scalar multiplications** (first improvement over
Strassen's 49 in 56 years); **state-of-the-art improved on 14 matrix
multiplication algorithms**; a production kernel sped up **23%**, worth 1%
end-to-end on Gemini training; ~20% of 50+ open math problems improved. The
architecture Idol already endorses (F1/F24: untrusted search, trusted check)
extended from *peephole search* to *algorithmic discovery*.

**Verdict: Yes (P2)** — the baseline's learning lanes (F1, F6, F7, F23, F24)
all operate at the peephole/heuristic level. AlphaEvolve is the 2025 proof
that the same "propose offline, verify, bake in" loop works one level up:
*algorithms*, not just instruction sequences. Its natural Idol target is
the kernel-template pipeline (F17 SME kernels, F18 KleidiAI-style
templates): exactly the artifacts where a 23%-class algorithmic win lands.

**Integration.**
- *Workstream:* bench methodology + compiler optimizations (kernel
  templates); builds on F17/F18.
- *Sketch:* extend the F1 oracle lane with an **evolutionary loop**: (1)
  seed = current Idol kernel template (e.g., the SME matmul kernel from
  F17); (2) propose = local open-weight coder model (Qwen2.5-Coder-7B-class
  or newer, free local inference only — never a paid API) generates code
  mutations of the template; (3) evaluate = the bench harness measures
  cycles and differential-tests against the reference kernel; (4) keep
  winners, iterate. Discovered kernels are generalized to templates and
  verified once (F1 lane), then ship as data. Start with FP32 matmul
  micro-kernels and reciprocal-division sequences (both already in
  sibling workstreams).
- *Expected win:* **algorithmic-level gains beyond any peephole pass** —
  AlphaEvolve's demonstrated 23% kernel speedup is the reference class;
  compounds P0-2 rather than competing with it (better kernels *inside*
  the SME path).

**Priority: P2** (needs the F17/F18 kernel-template infrastructure first).

---

### Short evaluations (logged, not deep-dived this round)

**F28. Verus: SMT-verified systems programming at production scale [MISSED].**
2026 stream is highly active (releases 0.2026.x; IEEE-float SMT theory;
toolchain on Rust 1.95): real codebases verified — a Zephyr RTOS kernel port
(805 verified, 0 errors), machine-checked in-place quicksort (sortedness +
permutation, no admits). Verus verifies *the actual code in place* via SMT
(Z3) with specs stripped at build time — no translation gap. **Verdict: Yes
(P1/P2).** Idol's proofunity (F12) covers tactic automation; Verus is the
design reference for the *ergonomic* end state and a candidate external
checker for the ARM64 encoding layer (complements F14's differential
tester). **Expected win:** verification throughput for the proof workstream;
miscompilation-class bugs caught by proof instead of by luck.

**F29. CSSPGO / pseudo-probe sample profiling in production [MISSED].**
Pseudo-probe-based AutoFDO is the production sample-PGO substrate
(Meta/Google): probes decouple the profile from code layout, sampling
overhead is ~1–2% vs 10–30% for instrumentation. **Verdict: Yes (P1).**
This is how P0-1 (layout) and P0-4 (if-conversion) get profiles *without an
instrumented-build tax*: emit pseudo-probes in Idol's object, sample with
`perf`, convert to block/edge profiles for the layout pass. **Expected win:**
makes the P0-1/P0-4 profile lane ~free; profile freshness stops being a
reason to skip layout.

**F30. Value-profile indirect-call promotion, active LLVM 2026 [MISSED].**
LLVM 2026 work (e.g. PR #208774: ICP under sample PGO with target-feature
compatibility guards) keeps refining value-profile-driven promotion:
compare-and-branch to the hot target, then inline it. **Verdict: Yes (P1,
after the profile lane exists).** Idol's relations-as-values compile to
indirect calls; once F29 profiles exist, promote the top-N targets at hot
call sites. **Expected win:** 2–10% on dispatch-heavy code; unlocks
inlining through dynamic dispatch.

**F31. Compile-time autotuning for kernel templates [MISSED].**
Mojo's `kbench` infrastructure (compile-and-measure over tile sizes, stages,
shapes; ATLAS/OpenTuner heritage): the industry pattern is *measured* search
over tuning parameters, results baked into dispatch tables. **Verdict: Yes
(P1).** Idol-native `kbench`: search (tile, unroll, VF, interleave) for each
kernel template on the actual target (M4 SME, NEON, x86 AVX10.2), bake
winners into the F7 tables — ground truth where the learned tables are
uncertain. **Expected win:** 5–30% on tiled kernels vs the analytic choice
(ATLAS-class results); one-time cost per target machine.

**F32. RISC-V: RVA23 ratified, matrix extensions approaching freeze [NEW].**
2025–26 status: **RVA23 ratified (2025) with mandatory RVV**; matrix
extensions (IME / AME / VME) progressing toward freeze/ratification in 2026
(RISC-V Summit Europe 2026); Tenstorrent "Grendel" (late 2025) and Alibaba
XuanTie C950 (AME v0.5, RVA23, 8-wide OoO @ 3.2 GHz) shipping. **Verdict:
Watch (P2/backlog).** No Idol RISC-V backend exists and the matrix ISA is
still unratified — but the F5 cost model is already target-descriptor data,
so RISC-V should remain *a descriptor, not a redesign*. Revisit when IME/AME
freezes. **Expected win:** none until a backend exists; strategic
optionality for the "more powerful than all languages" claim.

**F33. CHERI capability hardware: Morello → FreeBSD 16 → COSMIC [MISSED].**
2025–26 status: Arm Morello prototype (armv8.2 + CHERI) running FreeBSD 16
pure-capability kernel (Sep 2025–Mar 2026) and userspace (Apr–Sep 2026) with
~450-commit WIP patch; lowRISC **COSMIC** project (Nov 2025–Mar 2028) building
the first open-source commercial-quality CHERI secure enclave; CHERI
Alliance includes Google and BT. **Verdict: Watch (P2).** No Apple hardware,
so no near-term codegen target — but capability safety is the hardware
endgame of "law-governed": spatial/temporal safety at near-zero cost.
Design consequence now: keep Idol's pointer/identity representation
lowerable to capabilities later. **Expected win:** memory-safety bugs become
hardware traps; a power story no software-only language can match.

**F34. BOLT lite mode on AArch64 (LLVM 22.1) [NEW].**
LLVM 22.1: BOLT lite mode on AArch64 **reuses cold code instead of
duplicating it** — a binary-size win from the layout family. **Verdict: Yes
— fold into P0-1.** The post-emit layout pass must *move* cold blocks to a
shared cold region, never duplicate them. No separate workstream.
**Expected win:** part of P0-1's size story.

---

### Explicitly considered and deferred

- **RISC-V backend now:** rejected — matrix ISA unratified, no bench
  hardware; revisit at IME/AME freeze (F32).
- **CHERI codegen now:** rejected — no Apple/bench hardware; design for it,
  don't build for it (F33).
- **Full equality saturation in the compile hot path:** rejected — the
  35–45% compile-time lead is non-negotiable; saturation stays offline,
  the greedy ægraph variant goes in the compiler (F25).

---

*End of entry #1.*
