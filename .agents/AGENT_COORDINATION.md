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

## Handoff — research admission surface (main 5c7124f6, 2026-08-18)

One admission program survives: `gaps/RESEARCH-SPINE.md` (schema, structural
map, dependency DAG, horizons). Enforcer: `tools/node/dev/gapc0`, exposed as
`sh gate/researchgap.sh`; it fails closed on a missing/incomplete zero-delta
C0 block or on a role violation of law.md 111-115 in the research GAP set
(parameter-position receiver binding, annotation-position open type or void
descriptor — the existential relation faces `xs:any(p)` and `:any` are
canonical and pass). Every GAP ≥ 175 carries its block;
`docs/research-gap-admission.md` was a same-day duplicate and is deleted with
its map absorbed. Blockers found and left for their lanes:
`scripts/audit100.id` and `gate/idiom.id` are refused DNB001 by every current
binary (`mod-global-written`, `concat`), so both script gates are unrunnable
repo-wide; audit100 row-8 control parity was verified by running the row-8
regex directly over the rendered probe strings (deny 1, decline 0, before and
after).

## Handoff — canonical closure (codex/canonical-closure-20260818 @ 3afd79d6)

Vocabulary closure is ruled in law.md 111-115 and C0 (user commits 72170e6a,
e7aa01f4); this branch adds the mechanical complement: role-aware gapc0
(receiver/open-type/void roles, canonical `xs:any(p)`/`:any` faces pass),
gate/agentlaw.sh over agent-instruction blocks (no @-directive
recommendation, no follow-existing-patterns guidance, no open-type/void
teaching without a ban), the GAP-145 bytes ruling (element + shape facts, no
bytes descriptor kingdom), and the corpus teaching-status mapping. All gates
green with planted-defect negatives; main untouched per instruction. Open
work: gate/corpus-status.sh reports 964 .id files awaiting TEACHING-STATUS
headers (classification lane), and audit100/idiom remain DNB001-blocked
repo-wide.

## Handoff — script-gate unblocking (codex/canonical-closure-20260818 @ feda71ee)

The repo's script gates were dark on DNB001. Three walls moved, each with
by-value proof on this branch:

1. mod-global-written RETIRED (4cb1fd1c): the bss globals map answers, the
   stale scalar-precheck refusal is deleted, g066/g108 promoted into the
   differential corpus proper agreeing with the C column (6 5 / exit 6, 8 8).
2. The `{{}}` class (feda71ee): `{{` is a PACK HOLE by law, literal braces are
   `\{\}`; both gates' display strings were parsed as pack holes and refused
   by the concat planner. Fixed in gate/idiom.id (3 sites) and
   scripts/audit100.id (2 sites).
3. An idol_str_concat runtime export was drafted for the concat lane and
   DELETED: after the brace fix routed around the pack-hole parse, it had zero
   consumers, and a fact with no consumer is deleted, not shelved. Re-add it
   the day a lawful pack-in-text rendering needs it.

Wall chain remaining, with reproduction (build zig-out first):

    ./zig-out/bin/idol run gate/idiom.id < any.diff
      → SemanticFactsInvalid, validateDnirApplications native_backend.zig:7704
        missing-application-lineage (a module-local .call_direct lowered
        without application facts — graph/DNIR lineage lane)
    AUDIT100paths=/tmp/x.list ./zig-out/bin/idol run scripts/audit100.id
      → DNB001 native-scalar precheck — ret-type:any
        (return-type inference, sema lane; do NOT annotate the script around
        it — inference is the canonical face, IMPLEMENTATION-BLOCKED is honest)

Unit-test failure set is IDENTICAL to baseline (one pre-existing failure in
test 'refuses source conversion absent application facts', fails at 5e1bde2d
before any of this). main untouched.
