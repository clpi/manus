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
- Lane 3 EXECUTES: tools/wasm/factsprobe decodes real Wasm bytes into
  fact-shaped JSON (wasm-facts-probe-v1). On bench/fib.wasm (wasi-libc,
  203 functions): f192 -> 71 applications with exact shapes — constants
  carry determinacy exact, local.get is a read application, binops
  carry width 32 + overflow wrap + origin wasm, block/loop/if map to
  refinement/recurrence/alternative regions. The operand stack exists
  nowhere in the output; it is the edge order. Snapshot:
  evidence/mop/wasm/probe.fib.json.
- Lanes 1-2 (source-law ingress, GRAMMAR-ONE): compiler lane, untouched.


## Lane 3 idol-native research status + H9 (measured)

tools/wasm/ingest.id is executable research/bootstrap Idol with known
canonicality debt. It checks, compiles under direct-native, and runs as
a process, but executable production source is not a canonical teaching
surface. Compound identities, the hex transport, local opcode labels,
and the line transport remain migration evidence rather than language
authority.

UPDATE 4 (FINAL for the census): the idol ingest matches ground truth
EXACTLY — 29,004 instructions, 1,028 locals across 203 bodies. Two more
grammar bugs closed by per-body trace diff: (a) the walk-ending op
(br_table) was excluded from the count; (b) call_indirect's TWO LEB
immediates had no handler — padded LEBs were counted as opcodes (body
48: 5 GT ops vs 15). The measured fixture instruction/local census
agrees with its independent oracle; snapshot at evidence/mop/wasm/
ingest.fib.facts. This does not prove complete Wasm validation. Open
semantic work includes block signatures, stack typing, branch arity,
indices, reference types, feature gates, proposal instructions, and
publication into the shared semantic graph.

UPDATE 3: full body walk lands — locals EXACT (1,028 across 203
bodies), instruction census 29,356 vs independent ground truth 29,004
(1.2% divergence). The big correctness fix was a SIGN ERROR: the sleb
class is -2 but its handler tested cl == 2, so every i32.const value
byte was counted as an opcode (38,001 before the fix). The remaining
1.2% is diagnosed by per-body trace-diff (84 bodies differ, both +1 and
+40 patterns) with the trace methodology proven; one instrumentation
lesson recorded: emit-at-read-time, never post-skip (positions shift).

UPDATE 2: per-section content counts now parsed IN IDOL and CROSS-
VALIDATED against an independent read of the same bytes: types 39,
imports 6, functions 203, exports 3, bodies 203 — exact match. The
ingest is the census authority candidate for the module face; the next
increment is body walk (local decls + application chains).

UPDATE: the ingest now RUNS END TO END over a DECLARED hex transport
(in-place pair reads, O(1) per byte, zero materialization) — real
fib.wasm bytes -> idol -> fact lines: magic, version, and the full
section census with byte sizes. The binary face (H9) later replaces the
byteat accessor alone; no fact line changes.

Idiom lessons paid (fleet-relevant, measured): args() is 1-based over
CLI args (args(1) = first arg; args(2) past the end is NULL and
propagates SILENTLY through ==, :len, and :byte guards — guard with an
explicit range check); `_ = call()` discard-bindings are a no-op shape
(call directly as a statement); loop-built str concatenation segfaults
on ~73k iterations (read in place instead).

MEASURED BLOCKER (H9): binary-safe ingress. `path:read()` on a .wasm
file yields an EMPTY str — the current read face is text-only and the
wasm magic (\0asm) does not survive. The canonical ingest is therefore
blocked on the bytes-vs-text contract (the architecture memo's 'text
and bytes need a true semantic contract' item): a bytes face on
path:read, or a world-authorized binary ingress relation. No shell
piping workaround was wired in — that would be a silent fallback.


## Style ruling (user, 2026-08-17): `.` only for static members

Field access via `.` is for STATIC members (world/home fields like
`os.args`); dynamic values relate through subject-first `:` edges
(`s:byte(i)`, `path:read()`). Recorded; ingest.id audited compliant
(no `.` on dynamic values — all access is `:` edges or plain locals).


## Lane 3: records are graph-shaped evidence, not graph publication

Every emitted record has an application-shaped schema, but its
application number is a sequential source occurrence counter, its
caller is a Wasm function index, and its relation is a locally assigned
string. Those are provenance and classification coordinates, not exact
semantic graph identities. Explicit unknown cards prove schema
coverage only. Closure requires the Wasm-law producer to publish exact
occurrence, caller, relation, subject, operand, result, demand, effect,
world, and witness facts into the same graph used by Idol source.


## Lane 3 corpus classification census; semantic closure remains open

The full-bounds census found the last unnamed ops (0x46 eq outside the
cmp start; conversions 0xA7/0xA9-0xAC inside the arith64 block).
The measured corpus has no opcode left without a local family label.
That establishes byte-decoding and classification coverage for those
fixtures, not exact relation resolution. Current status is:

- byte decoding: complete for the measured corpus;
- opcode family classification: complete for the measured corpus;
- section/body census: complete for the measured corpus;
- semantic relation resolution: partial;
- Wasm validation: partial;
- shared semantic graph identity publication: not implemented.

Track schema coverage, known-fact coverage, trust/proof status, and
semantic-id continuity separately. An unknown card is an honest blocker,
not evidence that the corresponding semantic fact has been closed.
