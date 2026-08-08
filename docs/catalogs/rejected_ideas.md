# Rejected Ideas Registry (Pass 6)

> Permanent catalog of architectural ideas considered and rejected.  
> **Machine-readable:** `duo catalog` → `pass6` (roadmap + duplications imply alternatives).  
> Do not re-propose without new evidence that addresses the rejection rationale.

| ID | Description | Rejection rationale | Preferred alternative | Date |
| --- | --- | --- | --- | --- |
| REJ-001 | LLVM IR as Duo interchange or backend | Adds permanent IR layer; violates direct-to-native goal; duplicates codegen ownership | C/asm/object + `native_backend.zig`; SIM for interchange | 2026-08-04 |
| REJ-002 | Universal AST as cross-language interchange | Too heavy; loses Duo descriptor/shape semantics; agent-unfriendly size | SIM v0 projection + bounded C frontend | 2026-08-04 |
| REJ-003 | LSP-only semantic model for foreign types | Creates MCP/LSP fork of compiler truth; not queryable from builds | SIM export + `duo_foreign_import_preview` MCP | 2026-08-04 |
| REJ-004 | MCP-only semantic records (no compiler export) | Agents cannot validate against compile; drift from repo | `duo sim`, `duo graph`, `duo catalog` CLI first | 2026-08-04 |
| REJ-005 | Merge `@foreign` text transpile into SIM import | Different contract (snippet paste vs declaration import); would duplicate foreign_adapter | Keep `@foreign` as `@comp.foreign` text path; C headers via Pass 5 pipeline | 2026-08-04 |
| REJ-006 | Replace semantic graph with SIM entirely | Graph is mutable internal lift; SIM is versioned boundary — roles differ | Graph internal; SIM projection for agents/foreign | 2026-08-04 |
| REJ-007 | New `@comp.*` combinator without transform registry | Causes G-060-class fragmentation; unpredictable composition | Register in `transform_engine.zig` + 3-site parity (G-061) | 2026-08-04 |
| REJ-008 | Parser-only `@` directives without sema/codegen contract | Directives become syntax sugar lies; breaks native lowering guarantees | `meta_module` + sema + codegen gate | 2026-08-04 |
| REJ-009 | Third C parser (full libclang binding) as default | Heavy bootstrap dep; duplicates bounded frontend goal | `c_frontend.zig` + optional `c_layout_verify` clang probe | 2026-08-04 |
| REJ-010 | Runtime reflection table parallel to compile-time types | Duplicates descriptor system; blocks native path | `types.ResolvedType` + SIM export + `@comp.type.*` | 2026-08-04 |
| REJ-011 | Separate "agent IR" JSON format | N+1 interchange formats; coordination cost | Extend SIM schema versions (`sim-v1`, …) | 2026-08-04 |
| REJ-012 | Bidirectional C→Duo source rewriting (Pass 5 scope) | Implementation import deferred; risks semantic loss | Foreign descriptors + direct native call (P5-M1) | 2026-08-04 |

**Process:** New rejections append rows here and reference in `docs/archive/pass6_architectural_reconciliation.md` session notes.

**Pass 26 extension:** Open architectural tensions and decision statuses live in `src/pass26_decision_registry.zig` (`P26-D*`). Query `duo catalog | jq '.pass26'` before proposing syntax variants. **Machine-readable decisions (statuses, superseded items):** `duo catalog` → `pass26` / `src/pass26_contradiction_registry.zig` (Pass 26 F5).
