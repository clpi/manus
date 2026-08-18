# FTCFTW / Wasm / foreign-world master directive (user, 2026-08-17)

Preserved verbatim-in-substance from the issued directive. This file is
the durable projection; conflicts defer to the issuing authority and C0.

## Mission

Build the smallest self-hosted semantic execution system that achieves
the best lawful physical realization of programs expressed in Idol and
admitted foreign source laws. Wasm/WASI/WASIX are not side runtimes —
they are semantic source/foreign-law inputs into the same graph.
clpi/wart is the compatibility/performance oracle; do not port it
line-for-line. Wasmtime is the principal industrial competitor; beat it
across separate dimensions (decode, validation, compilation,
instantiation, startup, steady execution, memory, footprint,
WASI/component overhead, incremental execution). Never claim global
dominance from a small-module benchmark.

## Architecture rulings

- Wasm bytes → law wasm → validate exact semantics → publish graph
  facts → demand → realize. No permanent Wasm semantic IR. The operand
  stack is source provenance; blocks are control provenance; locals are
  semantic bindings; linear memory is ONE observable address space, not
  the representation of internal values; tables are semantic aggregates;
  imports/exports are boundary facts.
- Component Model: WIT contributes descriptor/pack/ownership/resource/
  world/effect/future/stream/provenance facts. Canonical ABI is a
  boundary realization to ERASE when a sealed composition makes it
  unobservable (component → adapter → ABI → adapter → component becomes
  direct graph application).
- WASI projects onto ordinary Idol worlds/effects. No permanent
  WasiCtx kingdom. Sealed world targets: world object 0, capability
  dispatch 0, import lookup 0, permission lookup 0.
- WASI 0.3 native async (async func, future<T>, stream<T>) maps onto
  ONE dependency/concurrency graph — never regress to universal
  polling. No-overlap async collapses to synchronous direct code.
- WASIX is compatibility law, not native ontology: thread_spawn →
  concurrency edge, fd_pipe → stream relation, proc_spawn → process
  relation (realizable in-process when identity is unobserved).
  Preserve POSIX observations exactly; do not assume POSIX is the
  cheapest realization.

## Execution regimes (not compiler tiers)

zero / direct / guarded / optimized / persistent — one graph, cost
decides realization depth. Search effort is itself a cost.

## FTCFTW search order (1–25)

observation → computation → theorem answer → foreign runtime →
component boundary → canonical ABI → process/thread boundary →
serialization → copy → aggregate/place → algorithm → fusion → state →
compile-time → representation → linear-memory promotion → bounds →
ABI specialization → devirtualization → async state → synchronization →
layout/placement → schedule/vector/GPU → machine instruction → local
superoptimization. Never optimize rung 24 while a higher rung
plausibly dominates. Idol's strongest wins live at rungs 1–15;
Wasmtime competes from ~10–25.

## Parallel lanes (fact ownership disjoint)

1 source/lex (close host ingress + GAP-145) · 2 grammar/parser ·
3 wasm ingest (decoder/validator → graph facts; no realization) ·
4 component/WIT · 5 demand/representation · 6 native realization ·
7 WASI/WASIX (wart as oracle) · 8 performance matrices.

## First runtime verticals (in order)

core Wasm → law → graph add/loop/memory semantics → direct x64/arm64,
no interpreter object, compare wart/Winch/Cranelift. Then sealed
component calling (ABI erased vs reference). Then WASI stdout pipeline
(no generic WasiCtx). Then WASI 0.3 stream (sync collapse + real
async). Then WASIX process/pipe (in-process when identity unobserved).
Only then broad opcode/WASI breadth.

## Where effort goes NOW (per the directive)

Compiler lane closes host source-law ingress and GRAMMAR-ONE execution.
In parallel: one isolated Wasm research lane defines Wasm validation
facts → existing semantic graph vocabulary (no production runtime);
one runtime lane mines wart's JIT emitter for the minimum physical
emitter basis. Convergence from both sides, not a second compiler
architecture.

## Release-claim law

Never say "faster than Wasmtime" globally until the matrix proves every
demanded dimension or names the remaining loss.


## Lane status (first pass, 2026-08-17)

- Lane 3 (wasm ingest research): evidence/mop/wasm/validation.facts.md —
  every core validation family mapped onto existing graph vocabulary
  (applications/cards, places, regions, packs, worlds). The two headline
  dissolutions stated in facts: operand stack = provenance order (edges,
  no place); canonical ABI = result-pack demand cards (payload 0 /
  status 1), sealed composition narrows the witness.
- Lane 6 (emitter mining): evidence/mop/wasm/emitter.mining.md — wart's
  JIT measured at 40,986 LOC fused; the minimum physical basis
  extracted (encoding tables, register-slot model, region-edge branch
  helpers, application call helpers, icache coherence) with fact-driven
  selection shared across Idol and Wasm origins.
- Lanes 1-2 (source-law ingress, GRAMMAR-ONE): compiler lane, untouched.
