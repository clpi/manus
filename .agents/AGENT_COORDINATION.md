# Idol agent coordination

This file is a durable ownership and gate map. It is not language law, a live
control plane, or a current-status ledger. Any line likely to drift belongs in
the ignored `.agents/session/` state or in evidence from an exact run.

## State and evidence

| Purpose | Owner |
|---|---|
| Semantic law | `docs/spec/constitution.md` only |
| Executed compiler frontier | `docs/bootstrap.md`, verified against production dispatch |
| Live claims and leases | `.agents/session/`, accessed through MCP claim tools |
| Open obligations | `gaps/GAP-0NN.md`; session-start census remains `GAP-131` debt |
| Performance evidence | `docs/performance.md` |
| Source-family classification | `docs/spec/corpus.md` |
| Source/home/package/world closure | `docs/spec/source.md` |
| Historical changes | Git history |

## Implementation owners

Owner means the boundary that currently decides. Existing Zig and `.id`
paths are bootstrap or compatibility debt, not destination architecture. A
suffix-only `.id` rename is not canonicality or self-host transfer.

| Boundary | Current implementation owner |
|---|---|
| Driver and production dispatch | `src/main.zig` |
| Lexer bridge | `src/duo_lexer_bridge.zig`, `src/duo_lexer_dispatch.zig` |
| Lexer source and generated physical projection | `lib/std/compiler/lexer.id`, `src/duo_lexer_tokenize.c` |
| Grammar and parser | `docs/spec/grammar.md`, `src/parser.zig`, `src/pass3*.zig` |
| Binding and semantic production | `src/sema.zig`, `src/semantic_context.zig`, `src/semantic_graph.zig` |
| Realization scheduling | `src/dnir_lower.zig`, `src/duo_native_ir.zig`, `src/region_graph.zig` |
| Direct machine and object emission | `src/native_backend.zig` |
| Generated-C bootstrap backend | `src/codegen.zig` |
| Token and Wasm generated projections | `src/token_classify_gen.zig`, `src/wasm_semantic_gen.zig` |
| LSP and MCP | `tools/lsp/`, `tools/mcp/` |
| Wasm consumer | `ext/ward/` |

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
   `"$repo/zig-out/bin/duo" run --backend=c "$repo/scripts/duo_lock.id" -- <command>`.
4. Positive-control every zero and report the inner requested outcome.
5. Never repair an integration failure by restoring a shadow authority another
   owner removed.
