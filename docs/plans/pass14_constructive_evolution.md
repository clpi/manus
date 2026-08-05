# Pass 14 — Constructive Evolution, Architectural Sovereignty, Universal Performance, and Living Compiler Development

> **Mission:** Continuously evolve Duo toward the best known compiler and language
> architecture without destroying recoverable work, accumulating stale
> abstractions, accepting unnecessary dependencies, privileging one architecture,
> or freezing provisional APIs before public commitments require stability.
>
> **Catalog:** `duo catalog | jq '.pass14'` · **Audit owner:** `src/pass14_constructive_audit.zig`
> **Preservation owner:** `src/git_preservation.zig` · **Salvage owner:** `src/salvage_registry.zig`

This pass establishes the **permanent development philosophy** required to preserve
the foundational goals (Passes 1–13) through years of implementation. It does not
add a new language subsystem or a new IR. It reconciles how the project evolves,
how work is preserved, how dependencies are owned, how performance is kept uniform
across architectures, and how the compiler stays current.

Duo is not a fixed compiler implementation. It is a **living semantic architecture.**

## Authority order (this pass governs process, not semantics)

Pass 14 is a *process* pass layered over Pass 13's control plane. It does not
override compiler semantic facts; it governs **how changes are evaluated,
preserved, reconciled, and removed**. Where Pass 13 owns *coordination state*
(snapshots, claims, presentation), Pass 14 owns the *preservation philosophy*
and *evolution discipline*.

| Layer | Pass | Owns |
| --- | --- | --- |
| Coordination state | Pass 13 | snapshots, claims, audit log, presentation records |
| Preservation & evolution discipline | **Pass 14** | salvage before delete, dependency sovereignty, architecture parity, shrink-first, currency loop |

## Governing thesis

The project must:

- reconcile before replacing;
- preserve before deleting;
- own essential capabilities;
- optimize across every major target;
- expose the lowest useful interfaces;
- derive high-level ergonomics from low-level power;
- remain the strongest practical Lua compiler;
- treat cross-language semantic computation as first-class;
- update its architecture continuously as the state of the art changes;
- become smaller, faster, clearer, and more capable over time.

---

## 1. Permanent priority order

Evaluate every design, implementation, refactor, dependency, API, compatibility
decision, Git operation, backend, optimization, and tool in this order.

### 1.1 Maximum runtime performance

Duo should produce the fastest valid realization available for the target,
observable semantics, and declared constraints.

Prefer designs that **reduce**: allocations, boxing, generic tables, dynamic
dispatch, indirection, virtual calls, redundant guards, redundant bounds checks,
conversions, copying, materialized intermediates, closure environments, runtime
metadata, ABI adaptation, cache misses, branch unpredictability, code size where
it harms locality, and unnecessary runtime components.

Prefer designs that **increase**: compile-time knowledge, call-shape
specialization, table-shape specialization, closure specialization, return-pack
specialization, partial evaluation, representation selection, algorithm
selection, data-layout selection, direct native calls, inlining, fusion,
vectorization, instruction-level parallelism, cache locality, target-specific
lowering, profile-guided realization, and hardware capability use.

> C is not the semantic model. C is not the performance ceiling. A fast path that
> changes semantics, skips validation, narrows the workload, or bypasses the
> released compiler is not proof.

### 1.2 Architectural sovereignty and no required dependencies

Duo should own every essential layer required to understand, compile, optimize,
emit, execute, inspect, and eventually build itself.

The long-term canonical toolchain must not **require**: LLVM, Cranelift, Clang,
GCC, Zig, a Lua interpreter, Lua bytecode, generated Lua, generated C, another
compiler framework, another runtime, host-language reflection, a mandatory cloud
service, or a mandatory external linker/assembler/object writer/parser/allocator/package runtime.

Dependencies may be temporary bootstrap, optional portability backends, optional
foreign integrations, development tools, platform interfaces, imported software,
or explicit user-selected libraries. They must never become **hidden semantic
authorities.** Duo adapters conform foreign systems to Duo; Duo does not
internally conform itself to foreign abstractions.

### 1.3 Development ergonomics

Duo should be exceptionally pleasant to build, use, inspect, debug, profile, and
extend. Prioritize fast clean and incremental builds, precise invalidation,
deterministic caching, low memory use, immediate diagnostics, beautiful terminal
output, semantically dense messages, causal traces, direct repair suggestions,
stable semantic navigation, structured machine output, concise commands,
reproducible failures, transparent backend selection, transparent runtime
dependencies, inspectable optimization decisions, direct generated/machine-code
inspection, simple self-hosting cycles, and proportional validation.

Runtime performance may not be sacrificed for convenience. Developer experience
may not be ignored in the pursuit of runtime performance. The compiler must
excel at both.

### 1.4 Maximum semantic power per permanent concept

Always ask: *How can this become smaller while remaining equally or more
intuitive, expressive, optimizable, inspectable, and general?* Assume that a
more compressed design usually exists.

Compression ratio:

```
semantic capability
──────────────────────────────────────────────
source tokens + visual complexity + permanent concepts + maintenance cost
```

Compression means fewer duplicated facts, fewer independent systems, fewer
files, fewer wrappers, fewer APIs, fewer keywords, fewer runtime components,
fewer dependencies, fewer parallel sources of truth, fewer required edits per
feature, and fewer agent-context requirements. It does **not** mean cryptic
punctuation or clever code.

---

## 2. Universal performance across architectures

Duo must not become excellent on one flagship architecture and mediocre
elsewhere. Its goal: **the best practical performance consistently across all
major architectures and execution environments**, with target-specific
capabilities exposed where useful and abstracted where unnecessary.

### 2.1 Required architecture classes

The target architecture must be capable of representing and optimizing for:
AArch64, x86-64, RISC-V, WebAssembly, major GPU execution models, mobile,
embedded, server, desktop, cloud, accelerator/device targets, and future
architectures without redesigning semantic foundations. Support status may
differ by release; architectural design may **not** assume one ISA, object
format, ABI, vector width, memory model, or operating system.

### 2.2 Shared semantics, target-specific realizations

The intended path:

```
semantic intent → legal realization candidates → target capability analysis
              → architecture-specific realization → validated machine artifact
```

Target-independent layers own: semantics, descriptors, shapes, calls, effects,
stages, contracts, laws, representation freedoms, optimization opportunities.

Target-specific layers own: instruction selection, register classes, calling
conventions, relocation details, vector widths, memory-order encodings, cache and
alignment characteristics, ISA features, object-format details, platform
execution boundaries. Backends consume canonical semantic and realization
decisions rather than independently reinterpreting the program.

### 2.3 Architecture-specific specialization

Duo should expose target capabilities through descriptors, `@`, `@comp.*`,
hardware queries, realization candidates, target intrinsics, capability
constraints, and target-aware LSP/MCP facts: SIMD width, predication, vector
masks, fused operations, atomics, memory ordering, cache line size, page size,
register availability, calling convention, GPU memory spaces, warp/wave
properties, device limits, WebAssembly proposals. Ordinary code should
specialize automatically; explicit target control should remain available when
required.

### 2.4 Cross-architecture parity

For each released capability track: semantic support, native lowering, runtime
support, object emission, ABI support, optimization support, diagnostics,
testing, fuzzing, benchmark evidence, artifact inspection, and known
architecture-specific gaps. A feature must not be described as generally
supported when only one target implements it. Performance claims must identify
architecture, microarchitecture, operating system, target features, compiler
configuration, runtime profile, benchmark semantics, and warm/cold state.

### 2.5 Performance portability without lowest-common-denominator design

Portable semantics must not force lowest-common-denominator implementations. The
same source may realize as scalar ARM64, SVE, NEON, AVX2, AVX-512, RISC-V vector,
WebAssembly SIMD, GPU kernel, compile-time result, or specialized scalar
fallback. The language remains stable; the realization changes.

---

## 3. Continuous architectural currency

Duo is intended to remain current day by day and hour by hour during active
development. The compiler, language, tooling, APIs, optimizer, runtime, MCP, LSP,
and development process must continuously evaluate meaningful advances in
language design, compiler research, systems research, hardware, runtime
architecture, formal methods, static analysis, metaprogramming, build systems,
package systems, debugging, profiling, AI-assisted development, agent
coordination, developer discourse, production engineering, newly influential
languages, newly popular paradigms, and shifts in compiler/language expectations.
Duo must never remain stale merely because an existing API works.

### 3.1 Living architecture rule

Canonical APIs and architecture should evolve whenever a clearly superior design
is discovered. Stability exists to serve users. It does not exist to preserve
unpublished mistakes. During pre-release development, immediately reconsider
public-looking APIs, internal APIs, syntax, descriptors, IRs, transformation
contracts, target surfaces, diagnostics, compiler services, LSP schemas, MCP
schemas, build interfaces, runtime boundaries, and foreign-binding models when
new evidence demonstrates a better approach.

### 3.2 Continuous external-awareness loop

`observe → classify → compare → reconcile → adopt, adapt, defer, or reject →
record rationale → update architecture and APIs where justified.`

### 3.3 No trend chasing

Popularity is evidence of relevance, not proof of quality. Every external
development must be evaluated against Duo's permanent priorities (§1). Classify
discoveries as: irrelevant, already subsumed, useful implementation technique,
useful ergonomic lesson, adaptation candidate, architectural opportunity,
immediate correction, experimental branch, long-term research, or rejected with
rationale. Do not accumulate fashionable features. Generalize valuable ideas into
Duo's existing foundations.

### 3.4 API freshness

APIs should be revised when a new paradigm reveals hidden duplication, user
discourse exposes recurring confusion, a new language demonstrates a better
interface, compiler research enables stronger guarantees, hardware evolution
changes the correct abstraction, agent workflows reveal unstable semantic
boundaries, existing APIs prevent specialization, or existing APIs encode
temporary implementation details. API changes must propagate through parser,
formatter, Tree-sitter, semantic graph, transformations, backends, runtime,
documentation, tests, examples, LSP, MCP, Ward, and migration tooling.

---

## 4. Constructive development

The default response to imperfect or conflicting work is **reconciliation**.
Preferred order: understand → identify intent → identify retained value →
identify invalid assumptions → identify canonical ownership → refit → refactor →
merge → generalize → specialize → migrate → validate → integrate → remove
irreducible residue only after salvage.

A new finding does not automatically invalidate all work built under earlier
assumptions. Most incomplete or superseded work contains reusable algorithms,
tests, fixtures, target knowledge, domain models, diagnostics, semantic
contracts, benchmarks, negative cases, generated data, implementation lessons,
provenance, and failure evidence. Recover these before deletion.

---

## 5. Git preservation

### 5.1 Prohibited defaults

Do not casually: `git stash`, delete a worktree, delete a branch, hard reset,
clean untracked files, restore entire files over concurrent changes, force push
shared history, revert mixed-value work, overwrite another agent's changes,
discard incomplete work, select broad "ours"/"theirs" conflict resolution, or
delete code because a newer design appears better. Destructive operations are
exceptional; they require prior preservation and explicit justification.

### 5.2 No routine stash

`git stash` hides state, weakens provenance, complicates agent coordination, and
creates forgotten work. Prefer named worktrees, checkpoint commits, preservation
branches, patch artifacts, content-addressed snapshots, semantic transactions,
and explicit work-in-progress commits. Invisible state is inferior to
recoverable state.

### 5.3 Worktree retirement protocol

A worktree may be removed only after: recording its revision, inspecting dirty
files, inspecting untracked files, identifying associated claims, preserving
every unique change, classifying meaningful work, extracting reusable tests and
logic, creating a commit/patch/snapshot, recording disposition, confirming no
tooling depends on the path, and obtaining integration-owner approval where
required. Worktree deletion is storage cleanup, not conflict resolution.

### 5.4 Revert policy

Use revert only when an integrated change creates a verified urgent regression,
security issue, release blocker, or destructive failure. Even then preserve the
original commit, retain tests, record exact invalid behavior, identify valid
portions, attach evidence, create a reconciliation item, and distinguish
emergency removal from architectural rejection.

### 5.5 Deletion threshold

Code may be deleted only when it is completely unsalvageable, **or** every useful
property has been transferred, **and** its continued presence creates measurable
confusion, duplication, risk, or cost. Deletion justification must identify
original purpose, consumers, tests, unique behavior, valid and invalid
assumptions, reusable parts, replacement, transferred evidence, equivalence or
superiority proof, and remaining risks. "Old," "unused," "experimental,"
"messy," "not canonical," or "written by another agent" are insufficient.

---

## 6. Reconciliation strategies

When work conflicts with current architecture, choose among: **refit** (adapt to
canonical system), **strategic refactor** (change ownership/representation,
preserve behavior), **merge** (combine complementary implementations),
**extract** (move reusable algorithms/descriptors/tests/diagnostics/fixtures),
**generalize** (project-specific machinery → reusable foundation), **specialize**
(retain general path + optimized target realizations), **lower** (compat infra →
lower-level primitive, migrate APIs onto it), **isolate** (bounded experiment,
no architectural contamination), **translate** (valuable host logic → Duo),
**preserve as evidence** (failed approach → regression/negative
test/benchmark/differential/rejected-decision record/migration fixture/debugging
reference), and **retire through replacement** (delete only after behavior,
tests, provenance, and knowledge have moved).

---

## 7. Replacement standard

A proposed replacement must be evaluated against the existing implementation for
semantic coverage, correctness, runtime performance, compile time, binary size,
memory use, allocations, boxing, runtime dependencies, target coverage,
diagnostics, trace quality, debuggability, test coverage, source size, concept
count, integration maturity, LSP support, MCP support, agent understandability,
and future extensibility. Architectural elegance without completed integration
does not justify deleting working code. Use staged migration when the replacement
is superior but incomplete.

---

## 8. Dependency sovereignty

Classify every dependency as: bootstrap, optional backend, optional integration,
development tool, platform interface, imported source, or forbidden
architectural dependency. Each dependency must record owner, purpose, scope,
linked artifacts, targets, semantic authority, runtime cost, compile-time cost,
performance cost, fallback, license, provenance, replacement plan, removal gate,
and permanence rationale.

### 8.1 Implement the smallest owned substrate

When an external project supplies a capability Duo fundamentally requires,
evaluate implementing the smallest sufficient Duo-owned substrate: object
writers, assemblers, linkers, debug information, unwind generation, executable
memory, allocators, parsers, collections, compression, hashing, target
descriptions, terminal rendering, protocol encoders, semantic caches, package
resolution. Do not reproduce an external project wholesale; own the precise
capability Duo requires.

### 8.2 No dependency-shaped semantics

Do not structure Duo around LLVM types, C types, Zig allocators, Lua VM stacks,
Rust ownership syntax, Clang AST nodes, host-language tagged unions, foreign
build graphs, or foreign object models. Foreign adapters map into Duo semantics.

---

## 9. Lowest useful interfaces

For every subsystem ask: *What is the lowest useful primitive from which
higher-level facilities can be derived?* (bytes beneath strings; pointer+length
beneath slices; sections+relocations beneath object emission; machine
instructions beneath native functions; semantic calls beneath language wrappers;
descriptors beneath schemas; capability records beneath platform APIs;
continuation state beneath async; semantic events beneath logging; memory
operations beneath collection abstractions.)

### 9.1 Capability ladder

`ordinary high-level Duo → inferred native realization → descriptor-constrained
realization → explicit low-level operation → target intrinsic → raw platform or
machine interface.` Users should not need to leave Duo to reach necessary
low-level facilities; low-level operations must remain semantically represented,
optimizable, stageable, inspectable, effect-aware, capability-aware, visible to
LSP/MCP, and usable from compile time when valid.

### 9.2 Platform and hardware access

Duo should ergonomically expose pointers, memory, bytes, alignment, atomics,
memory ordering, SIMD, target instructions, syscalls, virtual memory, executable
memory, threads, files, sockets, clocks, processes, GPUs, accelerators,
firmware, embedded hardware, object formats, ABIs, WebAssembly, foreign
callbacks, and continuations. High-level APIs should derive from these
foundations. Do not create unrelated safe/fast/FFI/intrinsic/device/runtime
systems when descriptors, effects, capabilities, stages, and realization can
unify them.

---

## 10. Compatibility layers

A compatibility layer is justified only when it supplies actual semantic
translation, ABI adaptation, representation conversion, ownership conversion,
safety validation, portability, staged specialization, capability discovery,
provenance, error enrichment, or optional convenience. Reject wrappers that
merely rename a foreign call, copy an already-compatible type, box native
values, hide a direct interface, allocate without semantic need, preserve
temporary architecture, imitate a weaker host language, or prevent
specialization. Every adapter must expose why it exists, whether it allocates,
copies, boxes, dispatches dynamically, changes ownership, and whether stronger
knowledge can eliminate it.

---

## 11. Cross-language semantic substrate

Cross-language metaprogramming is a first-class Duo use case. Duo should import
foreign declarations, import bounded foreign implementations, construct semantic
descriptors, inspect foreign structure, preserve uncertainty, validate ABI,
specialize calls, transform algorithms, eliminate wrappers, generate adapters
only where required, re-emit declarations/source where useful, compile
mixed-language systems, expose imported entities through LSP/MCP, and preserve
provenance across every boundary.

Unknown semantics remain unknown; opaque regions remain opaque; do not invent
precision. The same transformation architecture should operate, when contracts
permit, on native Duo functions, imported C functions, imported Wasm functions,
foreign records, foreign call graphs, model graphs, generated kernels, and
foreign schemas. Language-specific logic belongs in importers and adapters. One
imported semantic source should derive bindings, ABI validation, layout
validation, direct calls, adapters, documentation, hover, completion, tests,
fuzz cases, target variants, and release manifests — not unrelated generators per
language.

---

## 12. Compatibility policy

### 12.1 Pre-release Duo compatibility

Duo has not yet made a broad public compatibility promise. Therefore do not
preserve temporary syntax, weak APIs, duplicate mechanisms, poor names,
host-language leakage, obsolete configuration, accidental semantics, pass-era
architecture, or provisional command surfaces solely to avoid internal migration.
Before first public release: **architectural quality outranks compatibility with
unpublished Duo behavior.** Breaking changes should still be deliberate,
justified, migratable where practical, propagated through every tool,
reconciled with active work, and validated.

### 12.2 Lua compatibility

Lua compatibility is a permanent first-class goal. Duo should become the fastest
practical Lua interpreter (where interpretation is appropriate), AOT compiler,
JIT or adaptive compiler, the best migration path from dynamic Lua to native
specialization, and the most inspectable/ergonomic Lua implementation. Preserve
observable Lua semantics where required; do not preserve historical Lua VM
representations. Lua compatibility must not force universal boxing, generic
tables, Lua stack calls, heap closures, dynamic return containers, mandatory GC,
runtime metatable lookup, or interpreter mediation inside specialized regions.
**Preserve Lua behavior. Eliminate Lua implementation costs whenever compiler
knowledge permits.**

### 12.3 Explicit modes and no silent fallback

Backends, representation profiles, runtime profiles, and compatibility modes must
be explicit. Unsupported direct-backend code must fail with a precise diagnostic.
It must not silently emit C, invoke an external compiler, enter boxed execution,
use a generic Lua runtime, or interpret the program. Artifacts, benchmarks, logs,
and release manifests must disclose the selected path.

---

## 13. Shrink-first engineering

Every work item must answer: *What can this change remove, unify, derive, or
make unnecessary?* Measure source tokens, semantic facts, duplicated facts,
permanent concepts, files, APIs, wrappers, registries, dependencies, runtime
components, dynamic boundaries, allocations, conversions, build steps, agent
context, documentation, required edits per feature, and validation commands.

A new permanent mechanism should normally replace a weaker mechanism, subsume
multiple capabilities, eliminate duplicated logic, increase optimization
opportunities, reduce future implementation work, simplify agent reasoning, and
clarify canonical ownership. A narrow convenience that adds parser/semantic/
backend/runtime/LSP/MCP/documentation/test complexity is presumptively poor.
Prefer one descriptor source → parser behavior → validation → codegen → tests →
documentation → diagnostics → LSP → MCP, and one target descriptor → ABI →
object format → features → CLI → release manifest, and one structured diagnostic
→ terminal/JSON/LSP/MCP/regression fixture.

---

## 14. Development speed as architecture

Development speed comes from eliminating repeated work, not skipping rigor.
Prioritize incremental semantic caching, precise invalidation, deterministic
generation, targeted validation, semantic diffs, representation diffs,
dependency-aware claims, reusable context bundles, compiler-authored
explanations, one-command reproductions, automated failure reduction, benchmark
attribution, generated test plans, generated architecture maps, automated
stale-document detection, direct self-hosting cycles, reusable foreign import,
and stable ownership. The ideal change requires one canonical semantic edit, one
automatically derived validation plan, one evidence-backed integration, and zero
duplicated metadata updates.

---

## 15. Compiler presentation

Maximize `useful semantic information / (characters + visual complexity +
attention cost)`. Every character should add information, disambiguation,
causality, navigation, repair value, or machine readability — otherwise remove
it. Use coordinated terminal presentation (stable symbols, meaningful color,
bold, dim, underline, indentation, alignment, compact trees, whitespace, source
spans); color may not be the only information carrier. A causal trace should
answer what happened, why, which semantic entity was involved, which
transformation acted, which fact enabled/prevented it, which assumption failed,
which fallback occurred, what it cost, how to reproduce it, and how to repair it.

---

## 16. Commit and history philosophy

A commit should represent a coherent, recoverable state: identify semantic
purpose, preserve tests and evidence, expose incomplete status honestly,
separate mechanical migration from semantic change where useful, remain
reviewable and bisectable. Unfinished work may be committed explicitly; invisible
work should not be preferred. Before public release, history may be
rebased/squashed/reordered/message-cleaned/stripped/consolidated only after all
unique work is inventoried, all valuable work is preserved, integration is
complete, proof artifacts are retained, abandoned work is classified, and private
material is audited. **Permanent names** for production files, symbols, tests,
directories, and public APIs must be enduring semantic names — not names based on
pass numbers, agents, sessions, dates, temporary campaigns, or implementation
chronology.

---

## 17. Agent execution contract

Before editing, every agent must inspect project snapshot, Git status,
worktrees, active claims, recent relevant commits, canonical ownership, competing
implementations, tests and benchmarks, affected release claims, salvageable work,
dependencies and adapters, required validation, and acquire a bounded claim.
During implementation: modify canonical owners, preserve unrelated work, refit
before replacing, avoid parallel systems, commit recoverable checkpoints, retain
provenance, update generated projections canonically, report scope expansion,
avoid destructive Git operations, run proportional validation, measure
performance-sensitive changes, ask what can shrink, check every major
architecture affected, and check whether new external developments alter the
preferred design.

On conflict: inspect both implementations, identify unique value, compare
semantics/performance/architecture/maturity, identify shared foundations,
preserve both until integration, propose semantic convergence, and record
rejected portions. Before completion, report semantic changes, files
added/removed/merged/renamed, work preserved/refitted/deleted (with deletion
justification), dependencies added/removed, architecture and target coverage,
Lua compatibility impact, cross-language impact, runtime and compile-time impact,
performance evidence, LSP/MCP impact, validation, limitations, compression
achieved, stale APIs updated, external developments considered, and proof that no
valuable state was discarded.

---

## 18. Required audits

Machine-readable owner: `src/pass14_constructive_audit.zig` (`duo dev preserve`,
`duo catalog` → `pass14.audits`).

| # | Audit | Live data source |
| --- | --- | --- |
| 1 | Destructive Git practices | `src/git_preservation.zig` (stash, reset, clean, force push, worktree deletion, branch deletion, broad restore, blind conflict resolution) |
| 2 | Abandoned work | `src/git_preservation.zig` + `src/salvage_registry.zig` (branches, worktrees, dirty states, untracked artifacts, dormant modules, disabled features, shadow systems) |
| 3 | Dependency sovereignty | per-dependency authority/necessity/cost/replacement |
| 4 | Architecture parity | AArch64, x86-64, RISC-V, WebAssembly, GPU/accelerator |
| 5 | Target assumptions | pointer width, endianness, registers, vector width, calling convention, object format, stack, alignment, memory ordering, OS, host==target |
| 6 | Compatibility layers | wrappers, adapters, bridges, generated bindings, runtime conversions, boxed boundaries, generated-C boundaries, Lua/host intermediaries |
| 7 | Lowest-level interfaces | memory, bytes, pointers, ABI, object emission, machine code, syscalls, threads, atomics, SIMD, GPU, executable memory, foreign layouts, callbacks, continuations |
| 8 | Compression | duplicated facts, overlapping APIs, unnecessary files, wrapper-only abstractions, independent registries, repeated validation/documentation/agent context |
| 9 | Pre-release compatibility | provisional Duo syntax and APIs: remove/migrate/retain experimentally/retain for Lua/publish and stabilize |
| 10 | Lua supremacy | compatibility, interpreter startup, AOT, JIT, adaptive specialization, table/closure/metatable/multi-return/coroutine performance, embedding, FFI, debugging, diagnostics, memory, compilation latency |
| 11 | Cross-language convergence | importers reuse one SIM, one descriptor/ABI/transformation/evidence/provenance/validation architecture |
| 12 | Development ergonomics | clean/incremental build time, self-hosting cycle, diagnostic/LSP/MCP latency, validation selection, trace usefulness, benchmark readability, repair quality |
| 13 | Architectural currency | languages, compilers, research, hardware, WebAssembly, AI tooling, LSP, MCP, debugging, profiling, build systems, developer discourse |
| 14 | API staleness | APIs persisting only because they already exist or tooling/old examples/internal code depend on them |

---

## 19. Enforcement

Pass 14 must become enforceable through development duo-mcp, repository audit
commands, CI, pre-commit checks, pre-push checks, integration gates, artifact
assertions, and release proof generation. Enforce: preservation before
destructive Git operations; preservation before worktree removal; salvage
analysis before deletion; dependency classification; adapter cost records;
explicit backend selection; explicit compatibility mode; no silent fallback; no
generated C in direct-backend proofs; no boxing in native-proof paths;
architecture support records; target-specific validation; no duplicate semantic
registries; no pass-shaped production files; no release claim without evidence;
no stale API retained without classification; no completed claim without
integration proof. Overrides must be explicit, bounded, record actor, record
reason, preserve state, and leave an audit event.

---

## 20. Initial milestones

| ID | Milestone | Owner |
| --- | --- | --- |
| M1 | Preservation-aware repository operations | `src/git_preservation.zig` (`duo dev preserve`) |
| M2 | Salvage registry | `src/salvage_registry.zig` |
| M3 | Dependency manifest | `src/dependency_manifest.zig` (future) |
| M4 | Cross-architecture target matrix | `src/target_model.zig` extension (future) |
| M5 | Direct low-level substrate proof | future |
| M6 | Cross-language semantic proof | `src/sim.zig` extension (future) |
| M7 | Architecture-specific realization proof | `src/native_backend.zig` extension (future) |
| M8 | Currency loop | `src/arch_currency.zig` (future) |
| M9 | Shrink proof | `src/semantic_compression.zig` extension (future) |

M1 and M2 are the **implementation delivered in this pass**: a preservation
report that inventories destructive risks, dirty worktrees, unique branches,
untracked artifacts, and prunable worktrees; and a seeded salvage registry that
captures the repository's real displaced work (stale pass-name stubs still
referenced by docs, prunable worktrees, dormant branches) with disposition and
eligibility — rather than wholesale deletion.

---

## 21. Prohibited outcomes

Reject work that: destroys unreviewed work; uses stash as routine coordination;
deletes worktrees to avoid integration; reverts mixed-value work without salvage;
deletes code because a new design exists; force-pushes shared development state;
replaces incomplete architecture with incomplete architecture without migration;
introduces permanent dependencies for owned capabilities; makes an external
compiler canonical; optimizes only one architecture; hides target gaps; forces
lowest-common-denominator implementations; hardcodes ISA assumptions into
semantic layers; creates wrappers without semantic value; hides low-level
facilities; forces users out of Duo for systems access; preserves unpublished
mistakes; weakens Lua compatibility casually; forces Lua representation costs into
specialized code; creates importer-specific semantic frameworks; introduces
narrow syntax without concept reduction; remains stale because an API already
exists; trend-chases without convergence; ignores major external advances; emits
noisy diagnostics; or reports completion without integration and proof.

---

## 22. Required deliverables

Every Pass 14 execution must produce an executive summary, a Git preservation
report, a salvage matrix, a dependency matrix, an architecture performance
matrix, a compatibility-layer matrix, a lowest-level capability map, a
compression report, a compatibility table, a Lua readiness report, a
cross-language report, an architectural currency report, an enforcement report,
and an integration proof. Machine-readable projections of the live ones
(preservation, salvage, audits, success criteria) are emitted by
`duo catalog | jq '.pass14'` and `duo dev preserve`.

---

## 23. Success criteria

Pass 14 is successful when:

1. Destructive Git operations are exceptional and audited.
2. Dirty work cannot be silently discarded.
3. Worktrees cannot be removed without preservation.
4. New findings cause reconciliation before deletion.
5. Removed implementations have salvage records.
6. Useful tests, algorithms, diagnostics, and evidence survive supersession.
7. Essential semantics remain independent of external frameworks.
8. Temporary dependencies have explicit exit paths.
9. Duo exposes the lowest useful systems interfaces.
10. High-level ergonomics derive from low-level power.
11. Compatibility layers exist only where semantically justified.
12. Unreleased Duo mistakes are not permanent compatibility burdens.
13. Lua compatibility remains a first-class product.
14. Lua semantics do not force Lua implementation costs into specialized code.
15. Cross-language work uses canonical semantic foundations.
16. Major features have explicit architecture coverage.
17. Target-specific strengths are exploited.
18. Portable semantics do not imply mediocre generic realization.
19. Compiler APIs remain current with meaningful external advances.
20. Architectural discoveries are adopted, adapted, or deliberately rejected quickly.
21. New permanent mechanisms reduce existing complexity.
22. Source, architecture, dependencies, and workflow shrink over time.
23. Runtime performance remains the first priority.
24. Compile time remains excellent.
25. Diagnostics remain beautiful, causal, and dense.
26. Agents coordinate without erasing one another's work.
27. Self-hosting becomes easier.
28. Ward consumes general low-level capabilities rather than hacks.
29. The repository accumulates knowledge rather than resetting.
30. Duo never becomes stale through passive compatibility with its own past.

---

## 24. Final governing questions

For every **Git operation**: Could this destroy unique work? Has all state been
inspected? Is there a recoverable snapshot? Has useful content been extracted? Is
a non-destructive alternative available?

For every **deletion**: What purpose did this serve? What remains valuable? Where
has the value moved? What proves the replacement is better? Is deletion necessary?

For every **dependency**: Does it define Duo semantics? Does it constrain
performance? Does it block self-hosting? Can Duo own the required subset? Can it
become optional?

For every **architecture**: Is semantic support equivalent? Is performance
competitive? Are architecture-specific strengths used? Are gaps explicit? Can the
shared architecture support future targets?

For every **abstraction**: Does it expose or hide the lowest useful capability?
Does it add semantic value? Can it specialize away? Is it merely a wrapper? Can
one lower-level mechanism subsume it?

For every **compatibility decision**: Has this behavior been publicly promised?
Is it required for Lua? Is it an internal accident? Can it be migrated? Does
preserving it weaken Duo?

For every **API**: Is it still the best known design? Has recent language or
compiler work revealed a better model? Does current developer discourse expose
confusion? Does it preserve optimization freedom? Should it change now before
release?

For every **implementation**: Is this the fastest valid design? Is it fast across
major architectures? Can it avoid dependencies? Can it compile faster? Can it use
less memory? Can diagnostics become denser? Can traces become more causal? Can
source become smaller? Can concept count become smaller? Can multiple artifacts
derive from one fact? Can a lower-level primitive remove this wrapper? Can the
same transformation cross language boundaries? Has the state of the art changed
since this was designed? Should the architecture update immediately?

> The permanent assumption: **a more compact, direct, general, performant,
> portable, current, and semantically unified solution probably exists.** Pass 14
> exists to find it continuously without destroying the useful work already
> pointing toward it.

---

## Validation

```bash
duo catalog | jq '.pass14'                          # full machine-readable catalog
duo catalog | jq '.pass14.audits'                   # 14 audits with status
duo catalog | jq '.pass14.preservation'             # live Git preservation report
duo catalog | jq '.pass14.salvage'                  # seeded salvage registry
duo dev preserve                                     # standalone preservation report (JSON)
zig test src/pass14_catalog.zig
zig test src/git_preservation.zig
zig test src/salvage_registry.zig
zig test src/pass14_constructive_audit.zig
zig build unit-test --summary all
```

*Pass 14 succeeds when the repository can only become better, smaller, faster,
clearer, and more capable — and never silently loses useful work in the process.*
