# Pass 11 — Canonical Compiler Closure & Release Proof

> **Date:** 2026-08-04  
> **Status:** **CLOSED** (Profile A — C-backend default release)  
> **Mission:** Convert known architecture into one honest, releasable compiler.  
> **Catalog:** `duo catalog | jq '.pass11'`  
> **Gate:** `bash scripts/pass11_gate.sh` or `zig build pass11-gate`

---

## Closure summary (2026-08-04)

Profile **A** is closed: the compiler’s default path is generated C, backend selection is explicit, CI is pinned, repository hygiene is enforced, and direct-backend proofs exist for the documented subset.

| Evidence | Command |
| --- | --- |
| Full gate | `zig build pass11-gate` |
| Hygiene | `zig build repo-hygiene` |
| Reproducibility | `zig build reproducibility-smoke` |
| Direct ARM64 proof | `zig build pass11-direct-smoke` |
| Byte blob substrate | `zig build pass11-blob-object-smoke` |
| Catalog | `duo catalog \| jq '.pass11.readiness_summary'` |

**Deferred to post–Pass 11** (honest `open` in catalog): WP-06/07 return-packs/closures, WP-08 ELF, WP-09 machine IR, WP-11 runtime partitioning, WP-16 Lua differential, WP-17 library API, full Ward no-boxing (WP-15), self-hosting.

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
| WP-01 | Benchmark-path repair | done |
| WP-02 | Explicit backend + no silent fallback | done — `--backend`, DNB diagnostics, no C fallback on direct failure |
| WP-03 | ARM64 spills / stack frames | done — spill/reload for >20 live locals; `examples/pass11_spill_proof.duo` |
| WP-04 | Native sealed records | done — f64 kernels + stack locals + i64 field assign (`examples/pass11_record_proof.duo`) |
| WP-05 | Native byte slices (Ward) | done — blobs + `__native_load_u8` + blob object smoke |
| WP-12 | Repository sanitation | done — `scripts/repo_hygiene.sh` |
| WP-13 | Reproducible CI + pinned toolchain | done — pin + smokes + CI jobs |
| WP-18 | Target triple + emit kind | partial — `src/target_model.zig` wired |

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
zig build pass11-gate              # full Profile A closure gate
bash scripts/repo_hygiene.sh
bash scripts/ci_zig_version.sh   # must match .github/workflows/ci.yml ZIG_VERSION
zig build reproducibility-smoke  # Pass 11 WP-13
zig build pass11-module-smoke   # barrier checks + target model (any host)
zig build pass11-direct-smoke    # macOS AArch64 only
zig build pass11-blob-object-smoke  # macOS AArch64 WP-05
zig build pass11-spill-smoke       # macOS AArch64 WP-03
duo catalog | jq '.pass11.readiness_summary'
duo catalog | jq '.pass11.closure_status'
zig test src/native_backend.zig --test-filter "Pass 11"
duo compile examples/table_shape_smoke.duo --backend=c
duo compile examples/native_exe_smoke.duo --backend=direct --target native-exe
duo compile examples/pass11_record_proof.duo --backend=direct --target aarch64-macos --emit exe
duo compile examples/pass11_wasm_blob_direct.duo --backend=direct --target aarch64-macos --emit exe
```

---

*Pass 11 success = the released compiler demonstrably uses its intended architecture — not how many experimental subsystems exist in source.*
