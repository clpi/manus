# Pass 11 — Canonical Compiler Closure & Release Proof

> **Date:** 2026-08-04  
> **Mission:** Convert known architecture into one honest, releasable compiler.  
> **Catalog:** `duo catalog | jq '.pass11'`

---

## Resolved baseline (do not re-debate)

| Fact | Status |
| --- | --- |
| Implementation | Zig-hosted (`src/main.zig`), built via `zig build` → `zig-out/bin/duo` |
| Default backend | Generated C → Clang/`zig cc` (`--backend=c`) |
| Direct backend | Restricted ARM64 Mach-O (`--backend=direct`, macOS host only) |
| Self-hosting | None |
| Semantic graph | Experimental tooling (`duo graph`); not canonical compile path |
| Benchmark honesty | WP-01 removes forced boxing; use `--bench-backend` profiles |

---

## Release profile decision

**Profile A (selected):** C-backend first release — portable, semantically complete enough for Lua-shaped programs with typed `.duo` specialization.

**Profile B (experimental):** Direct backend — only when `--backend=direct` is explicit. Never silent.

```
duo compile file.duo                              # C → clang (default)
duo compile file.duo --backend=direct               # ARM64 Mach-O (subset)
duo compile file.duo --target wasm32-wasi           # C → zig cc → Wasm
```

---

## Work packages (track in `src/pass11_catalog.zig`)

| ID | Title | Status |
| --- | --- | --- |
| WP-01 | Benchmark-path repair | partial — `bench_mode` no longer forces boxing; `--bench-backend` added |
| WP-02 | Explicit backend + no silent fallback | partial — `--backend`, DNB diagnostics |
| WP-03 | ARM64 spills / stack frames | partial — scratch reuse + call frames; true spills still open (DNB003) |
| WP-04 | Native sealed records | open |
| WP-05 | Native byte slices (Ward) | partial |
| WP-10 | Semantic ownership audit | partial — `src/semantic_ownership.zig` |
| WP-12 | Repository sanitation | partial — `scripts/repo_hygiene.sh` passes locally; commit tracked removals |
| WP-14 | Bootstrap lexer in Duo | partial — M1 `token_semantic.zig` canonical keyword source |
| WP-15 | Ward decoder no-boxing proof | partial — Pass 9 smokes |

Full list: 18 work packages in catalog.

---

## Backend / representation / runtime axes

See `src/backend_identity.zig`:

- **Backend:** `c` | `direct` | `wasm`
- **Representation:** `generic` | `specialized` | `sealed` | `native`
- **Runtime:** `full` | `dynamic` | `minimal` | `freestanding`

Benchmark profiles: `c-dynamic`, `c-specialized` (default), `direct`.

---

## Honest public claims

**May claim:**

- AOT compiler emitting C for any Clang target
- Typed `.duo` paths avoid `lua_Value` when native-scalar proven
- Experimental direct ARM64 subset with structured DNB errors
- Progressive Lua semantics with static specialization

**May not claim until gated:**

- Self-hosted compiler
- Universal direct native compilation
- Globally faster than C (revalidate after WP-01 bench repair)
- Complete Lua 5.5 compatibility (no differential suite yet)
- Semantic graph as canonical compiler IR

---

## Validation

```bash
zig build
duo catalog | jq '.pass11.readiness_summary'
duo catalog | jq '.pass11.semantic_ownership.summary'
zig test src/pass11_catalog.zig
zig test src/backend_identity.zig
zig test src/semantic_ownership.zig
duo compile examples/table_shape_smoke.duo --backend=c
duo compile examples/native_exe_smoke.duo --backend=direct --target native-exe  # if smoke exists
```

---

*Pass 11 success = the released compiler demonstrably uses its intended architecture — not how many experimental subsystems exist in source.*
