# Bootstrap & Dependency Catalog (Pass 4)

> Track every dependency that influences Duo semantics, representation, optimization, or self-hosting.
> **Plan:** [`docs/plans/pass4_native_end_to_end.md`](../plans/pass4_native_end_to_end.md)

| ID | Dependency | Version | Classification | Build/Runtime | Purpose | Semantic influence | Replacement stage | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BD-001 | Zig | 0.17.0-dev nightly | Bootstrap | Build | Host compiler implementation | Host AST/objects leak if unguarded | Stage 8+ (self-host) | ✅ active |
| BD-002 | clang | system | Bootstrap / optional backend | Build | Compile generated C | C types must not define Duo semantics | Stage 6–8 (direct backend) | ✅ active |
| BD-003 | Generated C (`codegen.zig`) | — | Bootstrap backend | Build | Primary lowering today | Risk: treated as semantic IR | Stage 6 (Duo LLIR) | 🔄 transitional |
| BD-004 | `duo_runtime` C preamble | embedded | Runtime | Runtime | Dynamic Lua-compatible values | Boxes dynamic paths | Stage 7 (Duo runtime) | 🔄 modularizing |
| BD-005 | macOS ld / Mach-O | system | Bootstrap | Build | Link objects | None if Duo owns object format | Stage 6 | 🔄 via `native_backend.zig` |
| BD-006 | `native_backend.zig` | in-tree | Direct backend | Build | arm64 Mach-O emission | Duo-owned lowering (bounded) | Stage 6 canonical | 🔄 partial |
| BD-007 | zig cc (WASM) | via Zig | Optional backend | Build | wasm32-wasi targets | Wasm ABI adapter only | Optional permanent | ✅ optional |
| BD-008 | Lua 5.x (reference) | external | Validation | Test | Cross-bench / compat | None (validation only) | Indefinite | ✅ validation |
| BD-009 | Tree-sitter grammar (`ext/`) | in-tree | Tooling | Build | Parsing for editors | None | Indefinite | ✅ tooling |
| BD-010 | duo-lsp / duo-mcp | sibling repos | Tooling | External | IDE/agent integration | Must query compiler facts | Stage 4+ | 🔄 planned |

## Classification key

- **Bootstrap:** required to build the current compiler; must have a replacement plan.
- **Validation:** differential testing / benchmarking; may remain indefinitely.
- **Optional backend:** portability or comparison; not architectural truth.
- **Tooling:** LSP/MCP/formatter; must not reimplement semantics.

## Host-language leakage watchlist

| Leak | Location | Mitigation |
| --- | --- | --- |
| Zig hash maps as permanent table model | `sema.zig`, graph | Duo-owned shape/descriptor IDs |
| Host AST as sole semantic graph | `ast.zig` | `semantic_graph.zig` lift + durable IDs |
| C struct names as descriptor identity | `codegen.zig` `duo_rec_*` | Stable descriptor hashing + explanation |
| clang optimization as "Duo optimization" | bench via C | Direct backend + disassembly tests |

**Export:** `duo catalog` → `pass4.bootstrap_dependencies` JSON array.
