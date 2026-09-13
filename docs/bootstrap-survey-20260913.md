# Bootstrap Survey: Production Self-Hosting Compilers → Idol Plan

Survey date: 2026-09-13. Purpose: concrete bootstrap plan for making the Idol
toolchain fully Idol-implemented, compiled by Idol. Practical, not academic.

---

## 1. SBCL (Steel Bank Common Lisp)

**Seed strategy.** SBCL forked from CMUCL (1999) specifically to fix bootstrapping.
CMUCL could only be compiled by itself (same-version binary required) via fragile
image-based "bring the internal state to new version" techniques. SBCL reworked
bootstrapping so the core compiler parts can be hosted in *any mostly-complete*
ANSI CL implementation — then that host compiles the full SBCL. You build SBCL
from source with GNU CLISP, ECL, Clozure CL, or a commercial Lisp plus a C
compiler for the thin runtime. Key paper: Rhodes, "SBCL: A Sanely-Bootstrappable
Common Lisp" (2008).

**Transition without breaking.** The fork was amicable and deliberate: continue the
bootstrap rework *without destabilizing CMUCL*, which was mature and in production
use. Lesson: do the bootstrap rework on a branch/fork; keep the production
compiler untouched until the new bootstrap path is proven.

**Minimal viable subset.** A "genesis" phase: a minimal Lisp cross-compiler that
only needs enough of the host to compile SBCL's own compiler sources. The
trick is host-agnosticism — depending on as little host behavior as possible.

**Timeline/critical path.** Fork announced Dec 1999; v1.0 Nov 2006 (~7 years to
stable release, though usable much earlier). Critical path was the genesis
cross-compiler and purging CMUCL's image-based assumptions.

**Idol takeaway.** Make the Idol bootstrap host-agnostic: the first Idol-written
compiler stage should depend on as little of the host (Zig) compiler's behavior
as possible — only that it correctly compiles a restricted Idol subset. Do the
rework on branches; keep the Zig production compiler stable until the flip.

---

## 2. GHC (Glasgow Haskell Compiler)

**Seed strategy.** Original prototype (1989) written in Lazy ML as a frontend to
an existing Lazy ML implementation; then a complete rewrite in Haskell itself,
bootstrapped by compiling the new Haskell-written compiler with the old
implementation until the new one could compile itself. Today: building GHC
requires a previous GHC (stage0 = installed bootstrap compiler).

**Transition without breaking.** Staged build discipline (Hadrian/make):
- stage0: installed bootstrap GHC (binary, not built)
- stage1: basic GHC with core libraries, built by stage0
- stage2: complete GHC with all libraries, built by stage1
- stage3: optional, built by stage2 (for cross-compilation checks)

New platforms bootstrap via *unregisterised* C: stage1 emits portable C on a
host machine, which is compiled by a plain C compiler on the target. Human
intervention expected; rarely done, deliberately under-automated.

**Minimal viable subset.** The `.hs-boot` mechanism: mutually recursive modules
are broken with minimal interface files containing only what's needed to start
bootstrapping — a lesson in *minimal interface surfaces* between compiler stages.

**Timeline/critical path.** 1989 prototype → 1992 v0.10 (3 years to first
complete self-hosted version). Critical path: the rewrite had to be complete
enough to compile itself before the old implementation could be dropped.

**Idol takeaway.** Adopt explicit stage discipline with named stages and a
build system that understands staging (GHC's cabal still doesn't — Hadrian
exists because of this). For a new target, keep an unregisterised/portable
fallback path (for Idol: a Wasm or portable-C emission path from the Idol
compiler as the "can build anywhere" escape hatch).

---

## 3. Rust (rustc)

**Seed strategy.** Original compiler written in OCaml (2006–2010), then rewritten
in Rust itself. Bootstrap chain: every Rust release is built by the *previous*
stable release (stage0 = beta-1 compiler). A known-good snapshot binary anchors
the chain. Today `x.py` orchestrates: download stage0 → build stage1 (new
compiler, old libs) → build stage2 (new compiler, new libs).

**Transition without breaking.** The OCaml→Rust rewrite happened pre-1.0 when
the language could still break itself to ease migration — an advantage Idol does
*not* have if it freezes semantics. Rust kept the old compiler working until the
new one reached parity, then flipped.

**Minimal viable subset.** The rewrite started with the frontend (lexer/parser)
and grew. Crucially, Rust distinguishes "stage1 working" from "stage2
byte-identical" — these were *years* apart. Don't conflate "it compiles itself"
with "it's a trustworthy bootstrap."

**Timeline/critical path.** ~2006 OCaml start → 2015 1.0 self-hosted (~9 years,
though the rewrite itself was ~2010–2012). Full reproducible byte-identical
builds came years after 1.0. Critical path: borrow checker and trait solver
were the hard parts to re-express; everything else was mechanical.

**Idol takeaway.** The single most important Rust lesson: **keep the old
compiler as a permanent diff oracle.** Never delete the Zig implementation
after the flip — it is the only independent check that the Idol compiler's
output is correct. Also: plan for "compiles itself" (months) vs "verified
bootstrap" (much longer) as separate milestones.

---

## 4. Go (1.4 → 1.5: the closest precedent)

**Seed strategy.** Go's compiler was written in C through Go 1.4. For 1.5, the
team built a **mostly-automated C→Go translator** (not a hand rewrite). The
translator preserved behavior; the team then hand-optimized the translated code
for Go idioms over 1.5→1.7.

**Transition without breaking.** This is the key case: a *working production
compiler* ported in a *single release* rather than a multi-year staged effort.
How:
1. The C compiler was stable and well-tested (behavioral baseline).
2. The translator was semantics-preserving by construction (mechanical).
3. Verification was differential: C-compiler output vs Go-compiler output on
   identical inputs, over the entire test corpus.
4. The flip happened in one release (1.5); post-flip cleanup was idiomatic
   hand-optimization, not behavior change.

**Minimal viable subset.** The whole compiler at once — possible *because* the
translation was mechanical. No subset needed; the translator handled all of it.

**Timeline/critical path.** ~2012–2015 (~3 years with a team), but the
translation+flip itself was a fraction of that; most time was Go runtime work
happening in parallel. Post-1.5: building Go requires a previous Go
(GOROOT_BOOTSTRAP); the bootstrap binary is *not* checked in.

**Idol takeaway.** This is the model to copy if feasible: **build a Zig→Idol
mechanical translator** for the production compiler sources, verify by
differential testing (Zig-compiler output vs Idol-compiler output on the full
corpus), flip in a single release. The translator doesn't need to produce
idiomatic Idol — it needs to produce *correct* Idol; idioms come later
(Go 1.5→1.7 pattern). Risk: Zig→Idol is a bigger semantic gap than C→Go
(Zig has comptime, error unions, defer; Idol is relational/graph-based). The
translator may need to target a restricted Zig subset — which means first
restricting the compiler sources to that subset.

---

## 5. Zig (stage1 C++ → stage2 Zig: the cautionary tale)

**Seed strategy.** Stage1: compiler written in C++ (with LLVM backend). Stage2:
complete rewrite in Zig itself, built by stage1. Later stage3 planned. 8+ years
and still in progress with a small team + community.

**Transition without breaking.** Years of dual maintenance: stage1 remained the
production compiler while stage2 matured. The two implementations coexisted;
stage2 had to reach parity module by module. Lesson: **expect to rewrite the
self-hosted compiler at least once** — the first version is too literal a port;
the second exploits native patterns and is cleaner. Plan for both.

**Minimal viable subset.** Zig's stage2 started with the frontend and a
*self-hosted backend for debug builds only* — release builds still used LLVM.
Key insight: **the self-hosted compiler doesn't need to be the optimizing
compiler at first.** A correct-but-unoptimized self-hosted compiler is a valid
stage1; optimization comes later. (Zig: self-hosted = fast debug builds; LLVM
= slow optimized releases. The split is explicit and honest.)

**Timeline/critical path.** 2016 start → still in progress 2026 (10 years).
Critical path: semantic analysis (the 30K-line type-resolution redesign in 2026
shows this never really ends) and native backends per architecture.

**Idol takeaway.** The most important Zig lesson for Idol: **don't require the
first self-hosted compiler to be the fast one.** An Idol-written compiler that
correctly compiles Idol but generates unoptimized code is a complete bootstrap
milestone. The production optimizer work (poly, ivrange, satadd prologues) can
be ported after. Also: dual maintenance is the cost — budget for it, don't
pretend the Zig compiler disappears on flip day.

---

## 6. TCC (Tiny C Compiler)

**Seed strategy.** Self-hosted from very early; single-pass compiler, no
separate optimizer. The entire compiler is small enough that self-hosting was
never a "project" — it was a design constraint from day one.

**Idol takeaway.** TCC's lesson is about *architecture*, not process: a
single-pass, no-IR compiler is trivially self-hostable. Idol's production
compiler is a multi-pass graph machine (247K LOC of Zig) — the opposite. Where
Idol can choose single-pass/local reasoning (e.g., the peephole prologues in
lower.zig), it should, because those parts will be cheapest to port. The
already-Idol opt passes (poly.id, licm.id, zerotrip.id) prove this works.

---

## 7. LuaJIT (DynASM)

**Seed strategy.** Not a self-hosting story per se — but the *technique* matters:
LuaJIT's JIT backend is written using DynASM, a **build-time assembly DSL
preprocessor**. The machine-code encodings are expressed as a DSL embedded in
C, processed at build time into C code that emits machine code at runtime.

**Idol takeaway.** Idol already does this better: `lib/compiler/hw/neon.id`
(1,279 lines) and `lib/compiler/elfx86.id` (995 lines) express machine
encodings directly in Idol. The lesson is to *keep* machine encoding in Idol
(DynASM pattern) and never let it fall back to a foreign assembler — which is
exactly what the "no foreign assembler/linker" requirement demands. The
existing Idol encoding modules are the seed; grow them to cover the full ARM64
ISA subset the production backend emits.

---

## Cross-cutting techniques

### Staged bootstraps
Every production case uses named stages with a strict build order:
stage0 (trusted binary) → stage1 (new compiler, old libs) → stage2 (new
compiler, new libs) → optional stage3. The build system must understand staging
(GHC built Hadrian because make/cabal didn't).

### Verification: how they know the self-hosted compiler is correct
1. **Differential testing** (Go): old-compiler output vs new-compiler output on
   identical inputs, whole corpus. This is the primary correctness signal.
2. **Triple bootstrap** (dea-lang/Rust practice): build stage1 with stage0,
   stage2 with stage1, stage3 with stage2. If stage2 and stage3 produce
   byte-identical output, the compiler is self-consistent (a fixed point).
   Note: self-consistency ≠ correctness — you still need (1).
3. **Byte-identity** (Rust): stage2 built by stage1 must be byte-identical to
   stage2 built by stage0. Years after "it works."
4. **Keep the old compiler as oracle** (TypeScript/tsgo, jakechampion/lang):
   two implementations forever; the old one is the diff oracle. Never delete it.

### Performance regressions during transition
- Zig: stage2 was *slower* at first; the win was memory usage and debug-build
  speed, not codegen quality. They were explicit about the split (self-hosted =
  debug, LLVM = release).
- Go: the mechanically translated 1.5 compiler was *slower* than the C 1.4
  compiler; hand-optimization over 1.5→1.7 recovered it. Budget for this.
- Rule: the first self-hosted compiler buys you *independence*, not speed.
  Speed is a follow-on project with its own measurements.

### The translator question (Go vs Zig)
- Go proves mechanical translation of a stable codebase beats hand-rewrite for
  *correctness preservation* (the translator can't introduce logic bugs, only
  translation bugs, which are systematic and findable by differential testing).
- Zig proves hand-rewrite produces a better long-term architecture but takes
  10 years.
- Recommendation for Idol: **translator first (correctness), hand-rewrite
  second (architecture)** — the Go 1.5→1.7 pattern. The translator targets a
  restricted Zig subset; the compiler sources are first restricted to that
  subset (mechanical, verifiable); then translated; then hand-optimized.

---

## Idol's current position (2026-09-13)

Already in Idol (~59K LOC in lib/, compiler-relevant):
- lib/compiler/lexer.id (1,050) — lexer
- lib/compiler/parser.id (1,941) — expression/parser (partial; needs full grammar)
- lib/compiler/native.id (1,897) — restricted native route, ARM64 Mach-O (v2)
- lib/compiler/elfx86.id (995) — x86_64 ELF emission (proven: 165-byte static
  ELF from pure Idol, prints `hi`, exits 0)
- lib/compiler/hw/neon.id (1,279) — NEON encodings
- lib/compiler/opt/{poly,licm,zerotrip,unroll,indred,esat,outline}.id — opt passes
- lib/compiler/token.id (923), lib/wasm.id (433) — tokenization, Wasm

Still in Zig (~247K LOC in src/):
- src/codegen.zig (39,805) — codegen
- src/native.zig (25,505) — production native backend
- src/graph/lower.zig (23,977) — graph lowering + optimization prologues
- src/sema.zig (18,177) — semantic analysis
- src/graph.zig (15,183) — graph construction
- src/parser.zig (12,945) — production parser
- (rest: demand, observation, comptime, types, wasm, main, etc.)

The gap is the middle: sema → graph → lowering → native backend. The front
(lexer/parser) and the leaves (opt passes, encodings) already exist in Idol.

---

## Recommended Idol bootstrap sequence

### Stage 0 — Harden the Idol route (soft self-host; now → weeks)
Goal: the existing Idol-native pipeline compiles real Idol programs end to end.
1. Extend parser.id to the full Idol grammar (it's currently expression-level).
   Gate: parses the entire lib/compiler/*.id corpus without error.
2. Wire lexer.id → parser.id → native.id into a single driver (`idolc.id`).
   Gate: compiles and runs the 52 bench programs; outputs match the Zig
   compiler's outputs exactly (differential, the Go verification).
3. This stage produces **idolc-stage1**: an Idol program (compiled by the Zig
   `idol` binary) that compiles Idol to native code. It need not optimize.

### Stage 1 — Restrict the Zig sources to a translatable subset (weeks)
Goal: make mechanical translation possible.
1. Define the translatable Zig subset (no comptime metaprogramming, no error
   unions across function boundaries, no async; plain structs, enums, arrays,
   slices, while/for, switch).
2. Mechanically refactor src/ modules bottom-up (place.zig 1.6K →
   loop_closure.zig 1.9K → …) into the subset. Each refactor is behavior-
   preserving; verify by rebuilding and running the full gate suite.
   (This is pure win regardless of translation: simpler Zig is easier to audit.)

### Stage 2 — Mechanical Zig→Idol translator (weeks–months)
Goal: a translator that converts subset-Zig to Idol, verified differentially.
1. Write the translator itself in Idol (dogfood; it's a tree-walking
   source-to-source transform, exactly what parser.id + opt passes do).
2. Bootstrap the translator: write it first in the Idol subset that stage0
   already compiles, compile with Zig-`idol`, then use it to translate itself.
3. Translate the restricted Zig modules to Idol, largest-first by value:
   sema → graph → lower → native backend → codegen.
4. After each module: differential test — Zig-compiled vs Idol-compiled
   compiler produce identical output on the corpus.

### Stage 3 — The flip (single release, Go-1.5 pattern)
Goal: `idol` binary is built from Idol sources by the previous `idol`.
1. Triple bootstrap: zig-idol builds idol-A (Idol sources); idol-A builds
   idol-B; idol-B builds idol-C. Require idol-B ≡ idol-C byte-identical
   (self-consistency) AND idol-B's output ≡ zig-idol's output on the corpus
   (correctness).
2. Flip in one release: the release's `idol` is idol-C. Keep the Zig sources
   in-tree as the diff oracle (TypeScript/tsgo posture: two impls forever).
3. Post-flip: hand-optimize the translated Idol for Idol idioms (Go 1.5→1.7
   pattern) — this is where the graph-native rewrite happens (the Zig
   "second rewrite" lesson).

### Stage 4 — Close the toolchain (follows the flip)
The compiler is the hard part; the rest follows the same translator:
timing harness (already in progress), build orchestrator, router/dispatch,
gate scripts, proof checker. Each: translate → differential-test → flip.

---

## Critical risks

1. **Semantic gap Zig→Idol is larger than C→Go.** Zig's comptime, error
   handling, and manual memory management don't map 1:1 to Idol's
   relational/graph model. Mitigation: Stage 1 (restrict first) shrinks the
   gap before translation starts; the translator only handles the subset.
   Anything outside the subset is a compile error, not a silent miscompile.

2. **Performance regression on flip (Go-1.5 pattern).** The translated compiler
   will be slower than the Zig one. Mitigation: be explicit like Zig was
   (translated = correct, hand-optimized = fast, separate milestones); the
   production optimizer passes already exist in Idol and can compile the
   compiler's own source (dogfood the speedups).

3. **"Two rewrites" (Zig lesson).** The translated Idol will be too literal.
   Budget the second, idiomatic rewrite (Stage 3 post-flip) from the start;
   don't let the literal port become permanent.

4. **Bootstrap trust / provenance.** Triple-bootstrap proves self-consistency,
   not correctness; differential testing against the Zig oracle proves
   correctness. Both are required. The Zig oracle must never be deleted.

5. **Scope: 247K LOC of Zig.** The minimal viable subset for the flip is:
   lexer + parser + sema(core) + graph + lowering(core) + ONE backend (ARM64).
   Wasm, x86_64, esat, and the full opt-pass suite follow after the flip.
   Do not try to translate everything before flipping anything.

6. **Language gaps block translation.** The Intent ADR lesson: each stage2
   component needs language extensions first. Before Stage 2, audit what the
   restricted Zig subset requires (string indexing? byte slices? file I/O?
   process spawning?) and land those in Idol first. A translator that emits
   Idol the language can't express is useless.

7. **Dual maintenance cost (Zig lesson: 10 years).** From Stage 1 to the flip,
   every production compiler change must be made in Zig *and* kept
   translatable. Mitigation: keep Stage 1 short (weeks, not months); the
   subset restriction is a forcing function — if a change can't be expressed
   in the subset, it doesn't land.
