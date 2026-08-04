# duo-mcp — MCP servers for Duo (implemented in Duo)

**This directory is the single source of truth** for Duo MCP tooling.
All MCP servers are implemented in **pure Duo** — no Python dependency.

Implementation lives here; `duo/scripts/mcp/` is only a routing README.

## Servers

| Server | Entry point | Role |
| --- | --- | --- |
| **duo-bench** | `duo_bench.duo` | Benchmarks, build gates, perf audit, agent coordination |
| **duo-lsp** | `duo_lsp.duo` | Language intelligence, `@comp.*` catalog, diagnostics |
| **zls** | `zls.duo` | Zig compiler source navigation (bridges `zls` subprocess) |

## Usage

```json
{
  "mcpServers": {
    "duo-bench": {
      "command": "duo",
      "args": ["run", "/Users/clp/x/duo/scripts/mcp/duo_bench.duo"],
      "env": { "DUO_ROOT": "/Users/clp/x/duo" }
    },
    "duo-lsp": {
      "command": "duo",
      "args": ["run", "/Users/clp/x/duo/scripts/mcp/duo_lsp.duo"],
      "env": { "DUO_ROOT": "/Users/clp/x/duo" }
    },
    "zls": {
      "command": "duo",
      "args": ["run", "/Users/clp/x/duo/scripts/mcp/zls.duo"],
      "env": { "DUO_ROOT": "/Users/clp/x/duo" }
    }
  }
}
```

Or use the entry points here:
```json
{
  "duo-bench": { "command": "duo", "args": ["run", "/Users/clp/x/duo-mcp/duo_bench.duo"] },
  "duo-lsp":  { "command": "duo", "args": ["run", "/Users/clp/x/duo-mcp/duo_lsp.duo"] },
  "zls":      { "command": "duo", "args": ["run", "/Users/clp/x/duo-mcp/zls.duo"] }
}
```

## Tools

### duo-bench (`duo_bench.duo`)

| Tool | Description |
| --- | --- |
| `duo_bench_run` | Run benchmarks (bench/ml-bench/honest-bench/compile-size-bench/cross-bench) |
| `duo_build_run` | Run build gates (build/test/unit-test/fmt-check/agent-smoke) |
| `duo_agent_smoke` | Run tier-0 gate under build lock |
| `duo_audit_native_boxing` | Per-file C dump → lua_Value pattern audit |
| `duo_audit_metaprogramming_smokes` | Batch native audit on generative showcases |
| `duo_audit_codegen_boxing` | Scan codegen.zig for lua_invoke/lua_table_new patterns |
| `duo_coordination_read` | Read agent coordination buffer |
| `duo_coordination_update` | Update coordination buffer (claim/release/note) |
| `duo_agent_gaps_update` | Open or log updates for canonical gap findings |
| `duo_session_log` | Append structured session log entry |
| `duo_perf_ledger` | Read performance ledger |
| `duo_agent_canonical_index` | Read canonical agent router |
| `duo_repo_tooling` | Run a Duo repo script from scripts/ |
| `duo_agent_session_start` | Session bootstrap |
| `duo_bench_regressions` | Detect benchmark regressions: compare Duo RESULT/timing vs reference C |
| `duo_perf_gaps` | Read performance gaps from ledger |
| `duo_file_finding` | File a finding (bug\|exponential_opportunity\|ergonomic_gap\|regression) to coordination buffer |
| `duo_exponential_eval` | Exponential evaluator: input Duo code, output metaprogramming-enhanced optimized Duo |
| `duo_grammar_spec_read` | Read grammar spec (GR-* rules) |
| `duo_grammar_spec_update` | Append grammar rule changelog |
| `duo_directive_hierarchy_read` | Read @comp.* directive hierarchy |
| `duo_embed_symbols` | Symbol-level vector embedding search over compiler+stdlib |
| `duo_cross_lang_meta` | Guide for injecting Duo @comp.* exponential metaprogramming into any host language |
| `duo_agent_gaps_read` | Read gaps ledger |

### duo-lsp (`duo_lsp.duo`)

| Tool | Description |
| --- | --- |
| `duo_diagnostics` | Compiler diagnostics for a .duo file |
| `duo_compile_check` | Run `duo check` and return parsed errors |
| `duo_meta_catalog` | List all @meta.* constructs |
| `duo_meta_ladder` | Show scaling ladder (O(types) → O(n!)) |
| `duo_language_features` | All implemented language features |
| `duo_coordination_buffer` | Read agent coordination buffer |
| `duo_agent_gaps_buffer` | Read gaps ledger |
| `duo_agent_canonical_index` | Read canonical agent router |
| `duo_grammar_spec_read` | Read grammar spec (GR-*) |
| `duo_grammar_spec_update` | Append grammar rule changelog |
| `duo_directive_hierarchy_read` | Read @comp.* directive hierarchy |
| `duo_agent_smoke` | Run tier-0 gate under build lock |
| `duo_audit_native_boxing` | Per-file C dump → lua_Value pattern audit |
| `duo_audit_metaprogramming_smokes` | Batch native audit on generative showcases |
| `duo_session_log` | Append structured session log entry |
| `duo_repo_tooling` | Run a Duo repo script from scripts/ |
| `duo_agent_session_start` | Session bootstrap |

### zls (`zls.duo`)

| Tool | Description |
| --- | --- |
| `zig_diagnostics` | LSP diagnostics for a .zig file via `zls` |
| `zig_hover` | Hover/type info for a symbol |
| `zig_definition` | Go-to-definition |
| `zig_format` | Format with `zig fmt` |

## Key tools (session start)

1. `duo_agent_session_start` — load coordination + gaps + canonical index
2. `duo_coordination_update(action="claim", ...)` — before shared edits
3. `duo_agent_smoke` — tier-0 gate (parallel-safe)
4. `duo_audit_native_boxing` — G-001 native backfill audit
5. `duo_bench_run(bench_type="bench")` — full perf gate (claim first)

See `.agents/AGENT_CANONICAL.md` in the Duo repo for the full router.

## Development

All MCP servers are pure Duo. Add tools by registering them via `std.mcp.register_tool()`.
Shared coordination logic is in `scripts/mcp/duo_shared.duo`.
