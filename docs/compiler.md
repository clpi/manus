# Duo compiler architecture

**Status:** Pass 11 canonical closure (2026-08-04). Machine-readable: `duo catalog | jq '.pass11'`.

## What Duo is

Duo is a **Zig-hosted** ahead-of-time compiler. It is **not self-hosted**. The bootstrap chain is:

```
Zig (seed) → zig build → zig-out/bin/duo → user programs
```

## Canonical compile path (Profile A — default release)

```
Duo/Lua source → lexer → parser → AST → sema → (mono / arc / async_lower) → codegen → generated C → clang|zig cc → artifact
```

This is the **default** path. It is **not** direct machine-code generation.

| Flag | Effect |
| --- | --- |
| `--backend=c` (default) | Generated C → external C compiler |
| `--target native` | Host executable via C backend |
| `--target wasm32-wasi` | Wasm via C → `zig cc` |

## Experimental direct backend (Profile B)

```
--backend=direct --target native-exe   # or: --target aarch64-macos --emit exe
```

Implemented in `src/native_backend.zig`. Restrictions:

- macOS AArch64 host only (Mach-O)
- Scalar integer/float functions; sealed f64 records + i64 stack records (subset)
- ≤8 parameters; no varargs; no default parameters
- No general closures or multi-return in direct path yet
- **Never silent:** unsupported programs fail with DNB diagnostics; use `--backend=c`

Structured targets (`src/target_model.zig`):

```bash
duo compile file.duo --backend=direct --target aarch64-macos --emit exe
duo compile file.duo --backend=direct --target aarch64-macos --emit obj
```

Legacy aliases (`native-exe`, `native-object`, …) remain for compatibility.

## Backend / representation / runtime axes

Recorded in artifact manifests (`src/backend_identity.zig`):

| Axis | Values |
| --- | --- |
| Backend | `c`, `direct`, `wasm` |
| Representation | `generic`, `specialized`, `sealed`, `native` |
| Runtime | `full`, `dynamic`, `minimal`, `freestanding` |

Benchmark profiles (`--bench-backend`):

- `c-specialized` (default) — strongest generally supported C path
- `c-dynamic` — explicit boxed/Lua-compatible path
- `direct` — direct backend timing (subset only)

## Module ownership

| Module | Role | Classification |
| --- | --- | --- |
| `lexer.zig`, `parser.zig`, `sema.zig` | Frontend | CANONICAL |
| `codegen.zig` | C emission (primary backend) | CANONICAL |
| `native_backend.zig` | Direct ARM64 Mach-O | PARTIAL |
| `mono.zig`, `arc.zig`, `comptime.zig` | Lowering passes | CANONICAL |
| `meta_module.zig`, `meta_codegen.zig` | `@comp.*` registry | CANONICAL |
| `semantic_graph.zig` | Graph lift | EXPERIMENTAL (CLI only) |
| `realization.zig` | Representation plans | EXPERIMENTAL (CLI only) |
| `transform_engine.zig` | Transform registry | PARTIAL |

Full audit: `duo catalog | jq '.pass11.semantic_ownership'`.

## Native barrier checks

Executable assertions on compiler artifacts (`src/native_barrier_checks.zig`):

- `@assert.no_boxing` — scan generated C for `lua_Value` / `lua_invoke`
- `@assert.backend(direct)` — verify Mach-O object, no embedded C strings
- `@assert.no_generated_c` — direct path only

Catalog: `docs/catalogs/native_barriers.md`.

## Validation

```bash
zig build
zig build unit-test
zig build repo-hygiene
duo catalog | jq '.pass11.readiness_summary'
duo compile examples/hello.duo                    # C backend
duo compile examples/native_exe_smoke.duo --backend=direct --target aarch64-macos --emit exe
```

## Windows / Linux / x86-64 status

| Target | Status |
| --- | --- |
| aarch64-macos (direct) | Experimental subset |
| x86_64-linux-gnu (direct) | Planned — ELF writer open |
| x86_64-macos (direct) | Planned |
| x86_64-windows-msvc | Planned (COFF not in first release) |

See `duo catalog | jq '.pass11.target_model'`.

## Further reading

- [Pass 11 release proof](plans/pass11_release_proof.md)
- [Language reference](language.md)
- [Bootstrap](bootstrap.md)
- [Performance ledger](performance.md)
