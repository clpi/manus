# Duo Self-Hosting Foundation (Canonical Spec)

> **Status:** canonical specification, recorded 2026-08-05.  
> **Operational projection:** [`self_hosting_foundation.md`](self_hosting_foundation.md) (repo anchors, F-G table).  
> **Relationship:** `pass16_self_hosted_compiler.md` is the execution plan. Where documents disagree, **this file wins**.

## 1. Core rule: language monoculture

All production implementation converges to Duo.

**In scope:** compiler (all phases), parser/lexer, formatter, semantic graph system,
descriptor + shape system, compile-time system, all IR layers (syntax → machine →
artifact), instruction selection, register allocation, backend(s), runtime, standard
library, build system, package system, shell, LSP, MCP, Ward, testing + benchmarking,
release tooling.

### 1.1 Allowed non-Duo code (strictly bounded)

**A. Bootstrap — temporary authority**
- S0 Zig compiler
- temporary C / system backends
- platform bootstrap tools

**B. Foreign boundary — ABI / OS / ecosystem**
- OS calls, external libraries, ABI glue
- Must be replaced by Duo descriptors + adapters.

**C. Differential reference — non-authoritative**
- reference implementations, alternative compilers, Wasmtime comparisons
- Used only for validation.

**D. Disposable utilities**
- scripts, generators, migration tools
- Must have an explicit deletion condition **or** a tracked replacement in Duo.

## 2. Compiler bootstrap ladder

### S0 — Trusted bootstrap (Zig)

Role: builds S1; provides reference semantics; emergency recovery.

Constraints: frozen after S1 viability. Receives only correctness, reproducibility, and
security fixes. **No architectural evolution.**

### S1 — First Duo compiler

Implemented primarily in Duo. Must include: lexer, parser, semantic graph builder,
descriptor + shape system, diagnostics, canonicalization, HIR, staged evaluation
(bootstrap subset), and at least one full backend path. May call the S0 backend via an
explicit boundary.

### S2 — Self-hosted compiler

S1 compiles itself. Validation: semantic graph equivalence, IR equivalence, diagnostics
parity, test parity, artifact consistency, deterministic build behaviour.

### S3 — Reproducibility closure

S2 recompiles itself. Goal: stable semantic equivalence; deterministic or explainable
divergence.

## 3. Canonical semantic graph (single source of truth)

All meaning is stored in one graph.

### 3.1 Node types

source unit, syntax entity, declaration, binding, descriptor, shape, field, function,
closure, capture, call, parameter, return-pack, value, variant, stage, effect, contract,
assumption, guard, transformation, representation variable, realization candidate, target
capability, foreign entity, generated entity, evidence, machine artifact.

### 3.2 Edge types

defines, binds, references, contains, calls, captures, returns, consumes, refines,
specializes, transforms, guards, assumes, invalidates, depends on, aliases, mutates,
realizes as, represented by, executes on, generated from, validates, proves, falls back to.

### 3.3 Global rule

All subsystems consume **projections** of this graph. No subsystem may define independent
semantic truth. Applies to: compiler, formatter, LSP, MCP, Ward, documentation, foreign
imports.

## 4. IR system (unified multi-layer model)

A single transformation pipeline over structured graphs.

### 4.1 Syntax graph — surface truth

Preserves source structure and formatting trivia; supports recovery + incremental parsing;
maintains provenance. Entities: tokens, syntax nodes, source ranges, syntax identity,
lowering links, diagnostics.

### 4.2 Semantic graph — meaning layer

Binding + identity, descriptors + shapes, calls + return packs, effects + stages,
contracts + assumptions, unresolved freedoms.

Uncertainty states: unknown, inferred, guarded, stable, sealed, frozen, compile-time,
target-known, representation-selected.

### 4.3 Executable region graph — structured execution

Execution before linearization.

Regions: function, loop, pipeline, parser, kernel, staged computation, foreign region,
Ward region.

Transformations: fusion, splitting, tiling, specialization, closure elimination, layout
transformation, device placement, guard insertion.

### 4.4 Specialized graph — decision layer

Operations: box / unbox, dynamic call, field lookup, shape guard, descriptor
materialization, closure materialization, return-pack materialization, foreign conversion.

**Rule:** backend limitations may not introduce semantic dynamism.

### 4.5 Representation IR — physical mapping

Forms: scalar, register aggregate, stack record, heap record, dynamic table, inline array,
slice, tagged variant, closure environment, SIMD vector, GPU buffer, foreign ABI value.

Each decision records: subject, candidates, selection, reason, assumptions, fallback,
invalidation conditions.

### 4.6 SSA / scheduled IR — control + data flow

Block arguments, explicit return packs, explicit effects, explicit memory ops, explicit
calls, explicit guards + fallback edges, preserved semantic IDs, full provenance.

### 4.7 Low-level IR — target-independent machine form

Arithmetic, memory ops, atomics, vectors, control flow, calls, ABI-neutral aggregates,
traps, runtime ops, abstract intrinsics.

**Constraint:** no LLVM or C semantics allowed.

### 4.8 Machine IR — target-specific

Registers, instruction selection, addressing modes, calling conventions, stack frames,
spills, relocations, scheduling, debug/unwind info.

Targets: AArch64, x86-64, RISC-V, Wasm, GPU.

### 4.9 Artifact IR — linking layer

Sections, symbols, relocations, debug info, unwind info, imports/exports, link graph.

Targets: Mach-O, ELF, COFF/PE, Wasm, static/shared libs.

## 5. IR invariants (global laws)

1. Identity preserved across all lowering.
2. Knowledge is monotonic — no silent loss.
3. All loss must be explicit.
4. Boxing/allocation is explicit IR.
5. Return packs are first-class.
6. Calls retain full metadata.
7. Every transformation produces evidence.
8. Machine code is a projection, not truth.

## 6. Compiler foundation freeze (minimal stable core)

Freeze only what S1 requires.

- **Syntax core:** tokens, source model, function syntax, binding syntax, control flow,
  calls, return packs.
- **Semantic core:** stable IDs, descriptors, shapes, stages, effects, dynamic boundaries.
- **Memory substrate:** byte slices, strings, arrays, records, variants, arenas,
  deterministic maps, graph indices.
- **Compiler services:** snapshots, diagnostics, symbol lookup, graph queries, IR dumps,
  transformation traces.

## 7. Self-hosting execution plan

| Phase | Deliverable |
| --- | --- |
| 1 | **Substrate** — Byte/Slice, Source/Cursor, positions, interned strings, stable IDs, arenas, maps |
| 2 | **Lexer** — tokenization, classification, diagnostics, incremental boundaries |
| 3 | **Parser + syntax graph** — parsing engine, recovery, syntax graph, canonical lowering |
| 4 | **Semantic graph** — scopes, declarations, descriptors, shapes, calls |
| 5 | **HIR** — functions, regions, closures, return packs, effects, staging |
| 6 | **Compile-time system** — tables, descriptors, target catalog, compiler config |
| 7 | **Representation + SSA** — representation selection, boxing boundaries, specialization, SSA, optimizations |
| 8 | **Bootstrap backend** — IR → S0 backend, or IR → C backend |
| 9 | **Native backend** — AArch64 + Mach-O + macOS: primitives, calls/loops/branches, ABI + stack, object emission |
| 10 | **Object + linker** — Mach-O writer, relocations, symbols, link graph, executables; then ELF, COFF, RISC-V, Wasm |

## 8. Repository roles

- **duo** — S0 bootstrap, compiler source, runtime, stdlib, IR definitions, backend definitions
- **ward** — execution validation; ABI + memory + JIT testing
- **duo-lsp** — fully Duo; no JS semantic core
- **duo-mcp** — semantic graph + IR service layer

## 9. Foreign code elimination ledger (required metadata)

Each foreign file must declare: role, authority, replacement, prerequisites, migration
stage, deletion gate, status.

**Rule:** no deletion gate = architectural debt.

## 10. Immediate work program

**Foundation:** semantic IDs; semantic graph storage; syntax-semantic mapping; executable
region graph; return packs; effects/stages; dynamic boundaries.

**IR:** IR schemas; verifiers; serialization; lowering chain; SSA; machine IR; object IR;
provenance tracking.

**Self-hosting:** substrate; lexer; parser; semantic builder; diagnostics; HIR; S0 backend
interface; S1 build; S2/S3 cycle.

**Migration control:** freeze S0 architecture; enforce ledger; reject non-Duo permanence;
migrate LSP logic; migrate Ward logic; replace C blocks.

## 11. Foundation completion gate

Met when **all** hold:

- a single semantic graph exists
- all IR layers have verifiers
- identity survives all lowering
- calls + return packs are first-class
- boxing is explicit
- SSA lowers to one native target
- Duo has a native substrate
- lexer passes S0 differential tests
- parser handles the bootstrap subset
- a stable backend exists
- S0 is frozen
- MCP + LSP share the graph view
- Ward uses the same low-level model
- all foreign subsystems have replacement gates

## 12. Core principle

**Do not translate Zig. Do not wait for completeness.**

Build in order: semantic graph → executable region graph → representation IR → SSA → LIR →
machine IR → native substrate → bootstrap boundary.

Then construct the compiler as a graph-native system, not a port.

---

**Final statement.** The self-hosted compiler is not a rewrite of Zig in Duo. It is the
first full realization of a graph-native, multi-layer semantic compiler architecture built
directly in Duo.
