# Duo MCP Tools — Quick Reference

All tools are served by MCP servers implemented in pure Duo.
Shared implementation lives in `duo_shared.duo`.

---

## Filing (Bug, Exponential opportunity, Ergonomic gap, Regression)

| Tool | Server | Description |
| --- | --- | --- |
| `duo_file_finding` | duo-bench | File a finding (bug\|exponential_opportunity\|ergonomic_gap\|regression) to the coordination buffer |
| `duo_agent_gaps_update` | duo-bench | Open or log updates for canonical gap findings (open\|claim\|delegate\|close\|note) |

**Parameters (duo_file_finding):** `kind`, `title`, `detail`, `priority` (P0\|P1\|P2), `file_path`
**Parameters (duo_agent_gaps_update):** `action`, `agent_id`, `gap_id`, `kind`, `title`, `detail`, `priority`, `files`

---

## Bench / Regression

| Tool | Server | Description |
| --- | --- | --- |
| `duo_bench_run` | duo-bench | Run a benchmark suite under build lock (bench\|ml-bench\|honest-bench\|cross-bench) |
| `duo_bench_regressions` | duo-bench | Detect benchmark regressions: compare Duo RESULT/timing vs reference C |
| `duo_perf_gaps` | duo-bench | List open performance / native-lowering / codegen gaps from coordination buffer |
| `duo_perf_ledger` | duo-bench | Read the performance ledger summary (first 10k chars of docs/performance.md) |

**Parameters (duo_bench_run):** `bench_type`, `timeout`
**Parameters (duo_bench_regressions):** `bench_output` (optional captured stdout), `bench_type`

---

## Test / Build

| Tool | Server | Description |
| --- | --- | --- |
| `duo_build_run` | duo-bench | Run build/test gates (build\|test\|unit-test\|fmt-check\|agent-smoke) |
| `duo_agent_smoke` | duo-bench, duo-lsp | Run tier-0 agent-smoke gate under lock |

**Parameters (duo_build_run):** `gate`, `timeout`
**Parameters (duo_agent_smoke):** `timeout`

---

## Coordination / Manage

| Tool | Server | Description |
| --- | --- | --- |
| `duo_coordination_read` | duo-bench, duo-lsp | Read the shared agent coordination buffer |
| `duo_coordination_update` | duo-bench | Update coordination buffer (claim\|release\|note) |
| `duo_session_log` | duo-bench, duo-lsp | Append structured session log entry |
| `duo_agent_session_start` | duo-bench, duo-lsp | Session bootstrap: loads coordination + gaps + canonical index |
| `duo_agent_canonical_index` | duo-bench, duo-lsp | Read the canonical agent index router |

**Parameters (duo_coordination_update):** `action`, `agent_id`, `detail`, `files`
**Parameters (duo_session_log):** `agent_id`, `summary`, `detail`
**Parameters (duo_agent_session_start):** `agent_id`

---

## Language Intelligence

| Tool | Server | Description |
| --- | --- | --- |
| `duo_diagnostics` | duo-lsp | Get compiler diagnostics for a .duo file |
| `duo_compile_check` | duo-lsp | Run `duo check` and return parsed diagnostics |
| `duo_meta_catalog` | duo-lsp | List all @comp.* / @meta.* constructs |
| `duo_meta_ladder` | duo-lsp | Show the @comp.* scaling ladder O(types) → O(n!) |
| `duo_language_features` | duo-lsp | List all implemented Duo language features |

**Parameters (duo_diagnostics):** `file_path`
**Parameters (duo_compile_check):** `file_path`

---

## Exponential Evaluator

| Tool | Server | Description |
| --- | --- | --- |
| `duo_exponential_eval` | duo-bench | Analyze Duo source for metaprogramming opportunities; returns @comp.* suggestions, native-boxing audit, and LOC metrics |

**Parameters:** `source` (Duo source code), `goal` (optional description)

---

## Embedding / Search

| Tool | Server | Description |
| --- | --- | --- |
| `duo_embed_symbols` | duo-bench | Symbol-level vector embedding search over compiler+stdlib (bag-of-n-grams + cosine similarity) |

**Parameters:** `query`, `top_k` (default 10), `scope` (compiler\|stdlib\|all), `force_rebuild`

---

## Cross-Language

| Tool | Server | Description |
| --- | --- | --- |
| `duo_cross_lang_meta` | duo-bench | Guide for injecting Duo @comp.* exponential metaprogramming into any host language project |

**Parameters:** `host_lang` (python\|rust\|zig\|c\|js\|ts\|go\|any), `goal`

---

## Pass 5 — Semantic Interchange (SIM)

| Tool | Server | Description |
| --- | --- | --- |
| `duo_semantic_snapshot` | duo-bench, duo-lsp | Export SIM v0 JSON for a native `.duo` module (`duo sim <file>`) |
| `duo_foreign_import_preview` | duo-bench, duo-lsp | Preview C header → SIM entities with `abi.specialize` (`duo sim --import-c`) |
| `duo_pass5_catalog` | duo-bench, duo-lsp | Pass 5 workstreams + P5-M1 milestone from `duo catalog` |
| `duo_pass6_catalog` | duo-bench, duo-lsp | Pass 6 duplication matrix, risks, scorecard, dependency DAG |
| `duo_foreign_entity_lookup` | duo-lsp | Resolve foreign type/function via `@c.import` headers in a `.duo` file |

**Parameters (duo_semantic_snapshot):** `file_path`  
**Parameters (duo_foreign_import_preview):** `header_path`, `source_dir` (optional)  
**Parameters (duo_foreign_entity_lookup):** `file_path`, `symbol`

---

## Grammar / Directives

| Tool | Server | Description |
| --- | --- | --- |
| `duo_grammar_spec_read` | duo-bench, duo-lsp | Read the canonical Duo grammar spec (docs/GRAMMAR_SPEC.md) |
| `duo_grammar_spec_update` | duo-bench, duo-lsp | Append a grammar rule to the canonical spec |
| `duo_directive_hierarchy_read` | duo-bench, duo-lsp | Read the @comp.* directive hierarchy documentation |

**Parameters (duo_grammar_spec_update):** `rule_id`, `status` (preferred\|accepted\|deprecated\|removed), `title`, `content`

---

## Audit

| Tool | Server | Description |
| --- | --- | --- |
| `duo_audit_native_boxing` | duo-bench, duo-lsp | Dump C for a .duo file and flag lua_Value boxing patterns |
| `duo_audit_metaprogramming_smokes` | duo-bench, duo-lsp | Batch native-boxing audit on generative showcases |
| `duo_audit_codegen_boxing` | duo-lsp | Static-scan a .duo file for known codegen pitfalls (call-as-tail premature return, nil-init void* inference) |

**Parameters (duo_audit_native_boxing):** `file_path`
**Parameters (duo_audit_codegen_boxing):** `file_path`

> **Note:** `duo_audit_codegen_boxing` is registered as `duo_audit_codegen_pitfalls` in the current `duo_lsp.duo` implementation. Both names refer to the same functionality.

---

## Zig Language (zls bridge)

| Tool | Server | Description |
| --- | --- | --- |
| `zig_diagnostics` | zls | LSP diagnostics for a .zig file via zls |
| `zig_hover` | zls | Hover/type info for a symbol |
| `zig_definition` | zls | Go-to-definition |
| `zig_format` | zls | Format with `zig fmt` |

---

## Session Workflow

Typical agent session:

1. `duo_agent_session_start` — bootstrap (loads coordination, gaps, canonical index)
2. `duo_coordination_update(action="claim", ...)` — claim area before shared edits
3. `duo_agent_smoke` — tier-0 gate (parallel-safe)
4. `duo_audit_native_boxing` — G-001 native backfill audit
5. `duo_bench_run(bench_type="bench")` — full perf gate (claim first)
6. `duo_file_finding(kind=..., ...)` — file any discovered issues
7. `duo_session_log` — record session summary

---

## Servers at a Glance

| Server | Entry point | Tool count | Focus |
| --- | --- | --- | --- |
| **duo-bench** | `duo_bench.duo` | 23 | Benchmarks, build gates, coordination, audit, eval |
| **duo-lsp** | `duo_lsp.duo` | 26 | Language intelligence, diagnostics, @comp.* catalog |
| **zls** | `zls.duo` | 4 | Zig source navigation via zls subprocess |

Shared logic: `duo_shared.duo` (coordination, build gates, native audit, perf analysis, exponential evaluator)
