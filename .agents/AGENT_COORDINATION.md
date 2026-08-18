# Idol agent coordination

This file is a durable ownership and gate map. It is not language law, a live
control plane, or a current-status ledger. Any line likely to drift belongs in
the ignored `.agents/session/` state or in evidence from an exact run.

## State and evidence

| Purpose | Owner |
|---|---|
| Semantic law | `docs/spec/constitution.md` only |
| Executed compiler frontier | `docs/bootstrap.md`, verified against production dispatch |
| Live claims and leases | shared Git-common-dir claim locks, accessed through `tools/node/dev/claim` |
| Open obligations | exact `gaps/GAP-0NN.md` records; `orient` derives the P0 census |
| Performance evidence | `docs/performance.md` |
| Source-family classification | `docs/spec/corpus.md` |
| Source/home/package/world closure | `docs/spec/source.md` |
| Historical changes | Git history |

**Live control plane (`law.control.derived`):** do not read HEAD, dirty, or
lane holders from this file. Obtain them from `git`, `tools/node/dev/claim`,
and `tools/node/dev/orient`. This file names
durable lane *roles* only.

No string-world / relation catalogs. Storage class is not a representation
producer. Family is a tokenize operand; `suffix(file)` is deleted. Production
compile/fmt/embed use `sourceFacts` then `initFacts`. Do not report metrics
“at HEAD” unless the measured subject equals the live tree
(`law.evidence.subject`).

**Eight production lanes** (35 realization risks fold here — not new reports).
Designated long-term owners: Devin = 1–2, Codex = 3, Poolside = 4–7, Cursor =
8 + interim when a designated owner is absent. **Acquire the claim file
before editing.** Lane labels here are not locks.

| # | Lane | Owns |
|---|---|---|
| 1 | Ingress + lexical SHC | source-family, GAP-145, token schema/magic/ordinals, bridge copies, oracle bound |
| 2 | Grammar + parser SHC | GAP-134, roles, immutable token view, Idol parser |
| 3 | Resolver + graph | exact binding, ontology, application facts, world/effect/witness, lineage |
| 4 | Demand + realization choice | demand, **REPRESENTATION-ONE**, specialize-budget, ABI, tail, numeric/range |
| 5 | Memory + effects | guard/deopt, alloc/region, alias/lifetime, copy/tag, bounds, string/table/layout, fusion/SIMD, concurrency, coroutine, metamethod |
| 6 | Direct native + runtime | I/O witness, crashes→0, C-bridge death, object writer, DCE/link reachability, FFI, startup/size |
| 7 | Wasm | same graph, import/export specialization, Wasmtime matrix |
| 8 | Evidence + anti-drift | evidence-subject, MCP/LSP same-graph, census death, ratchets, B/C, miss diagnostics |

**P0** source-family → GAP-145 → token ABI → GAP-134 → parser → graph
(**GRAPH-SOVEREIGNTY G1–G12**, `scripts/ledger/graph.id`) → world/effect/witness
→ demand → crashes/failures to zero.
**P1** representation-one (items 1–3), then boxing/call/shape/closure/region/copy/tag/ABI/bounds/string/table/metamethod/fusion/concurrency/DCE (items 4–26).
**P2** zero-copy tokens, dense graph, exact invalidation, parallel compiler, stage cache, object writer, LSP/MCP same-graph, replace grep census (items 27–35).
**P3** crash 0, matrices, C + Wasmtime suites, B then C (items 36–44).

Full 1–35: `docs/spec/realization.md`. Graph sovereignty G1–G12: same file § Graph sovereignty.
Cluster map: `WORKSTREAM_DEBT_REGISTER.md` § Optimization architecture + § BI.

`law.representation.one`, `law.guard.one`, `law.specialize.budget`, `law.abi.internal`,
`law.error.cold`, `law.crash.first`, `law.cost.explain`, `law.application.consumer`,
`law.fact.locality`, `law.grammar.one`, `law.control.derived` in C0 +
`docs/spec/canonical.md` §11i–11q.

No lane may mint relation catalogs, boolean-mirror rows, string-world tables,
magic rejection codes, or host slot maps as substitutes for lane 3.
Lane labels do not imply an active lock. Acquire before producing owned facts.

## Implementation owners

Owner means the boundary that currently decides. Existing Zig and `.id`
paths are bootstrap or compatibility debt, not destination architecture. A
suffix-only `.id` rename is not canonicality or self-host transfer. A new bounded
Zig bridge is admitted when it is the fastest path to the next executed SHC
transfer and carries a `law.bridge.death` deletion witness
(`law.bootstrap.velocity`); foreign is forbidden only as permanent architecture
or semantic authority.

| Boundary | Current implementation owner |
|---|---|
| Driver and production dispatch | `src/main.zig` |
| Lexer bridge | `src/lexer_bridge.zig`, `src/lexer_dispatch.zig` |
| Lexer source and generated physical projection | `lib/compiler/lexer.id`, `src/lexer_tokenize.c` |
| Grammar and parser | `docs/spec/grammar.md`, `src/parser.zig`, `src/pass3*.zig` |
| Binding and semantic production | `src/sema.zig`, `src/semantic_context.zig`, `src/semantic_graph.zig` |
| Realization scheduling | `src/dnir_lower.zig`, `src/native_ir.zig`, `src/region_graph.zig` |
| Direct machine and object emission | `src/native_backend.zig` |
| Generated-C bootstrap backend | `src/codegen.zig` |
| Token and Wasm generated projections | `src/token_classify_gen.zig`, `src/wasm_semantic_gen.zig` |
| LSP | sibling `idol-native/tools/lsp/` over that compiler's graph |
| MCP | `tools/mcp/` plus sibling `idol-native/tools/mcp/` |
| Wasm consumer | `tools/wasm/` (standalone debt; destination: shared graph and realization) |

Read `docs/bootstrap.md` before choosing work. Attack the earliest host-owned
production boundary whose prerequisites exist. Do not infer progress from file
counts or translate a host module line for line.

## Gates

| Step | Scope |
|---|---|
| `zig build agent-smoke` | fast repository and canonical-source admission |
| `zig build audit100` | current corpus deny ratchets; the historical name is a tool alias |
| `zig build repo-hygiene` | tracked repository hygiene |
| `zig build language-census` | source-family and foreign debt census |
| `zig build native-census` | direct-native reachability |
| `zig build unit-test --summary all` | unit aggregate |
| `zig build test` | unit and compile-fail aggregate |
| `zig build bench` | serialized performance gate |

## Protocol

1. Never use `git stash`, `git reset --hard`, or hidden worktree cleanup.
2. Claim exact paths and commit only explicit owned pathspecs.
3. Serialize heavy commands through
   `repo="$(git rev-parse --show-toplevel)"` and
   `"$repo/tools/node/dev/idol-lock" -- <command>`.
4. Positive-control every zero and report the inner requested outcome.
5. Never repair an integration failure by restoring a shadow authority another
   owner removed.

## Fact handoffs (`law.coordination.fact`)

When lane A needs a fact owned by lane B:

- record needed fact, current producer, consumer, blocking interface, owner
- do not duplicate the fact locally or reconstruct it from names/paths/text
- schedule work on producer→consumer chains, not directories
- stop on ambiguity and file a gap rather than invent helper semantics

Claim semantic boundaries as well as paths. Integration state outranks
branch-local success.
