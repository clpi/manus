# Pass 11 — Canonical Compiler Closure & Release Proof

> **Date:** 2026-08-04
> **Status:** Tracking. Build currently unstable (Cursor agent iterating on main.zig).
> **Mission:** Convert known architecture into one honest, releasable compiler.

---

## Resolved Baseline (honest)

| Fact | Status |
| --- | --- |
| Implementation language | Zig (not self-hosted) |
| Canonical backend | Generated C → Clang/zig cc |
| Direct backend | ARM64 Mach-O (restricted scalar subset) |
| Boxing | 1,135 lua_Value refs (dynamic path only) |
| Benchmark mode | Forces boxing (bench_mode blocks native_scalar) |
| Self-hosting | None |
| Semantic graph | Experimental tooling (not canonical compilation path) |
| Target coverage | macOS arm64 (direct), any clang target (C backend) |
| Release status | Not public-ready |

---

## Critical Work Packages (ordered by dependency)

### WP-01: Benchmark-path repair [HIGHEST PRIORITY]

**Problem:** `can_emit_native_scalar_module` returns false for `bench_mode`:
```zig
if (self.bench_mode) { return false; }
```
This forces ALL benchmarks through the boxed Lua path, making performance
claims dishonest — they measure the WEAKEST path, not the canonical one.

**Fix:** Remove the `bench_mode` guard. Let benchmark programs go through
the same native_scalar/mixed mode selection as any .duo file.

**Blocked by:** Cursor agent currently breaking the build.

### WP-02: Silent fallback elimination

**Problem:** No diagnostic when `--target native-exe` silently falls back
to "hint: program is outside the current direct object subset."

**Fix:** Replace hint with structured error: source span, construct, reason,
alternative (`--backend=c`).

### WP-03: ARM64 spills and stack frames

**Problem:** `RegisterExhausted` panic at >20 live values.

**Fix:** Stack-frame layout + spill/reload. Required for any non-trivial function.

### WP-04: Native sealed records (memory-based)

**Problem:** Only f64 records work (register-spread). No memory loads/stores.

**Fix:** Layout computation + ldr/str at field offsets. Required for Ward.

### WP-05: Native byte slices

**Problem:** Duo strings are null-terminated C strings. No binary data support.

**Fix:** Pointer+length type (`Slice[u8]`) with proper codegen. Required for Ward.

### WP-12: Repository sanitation

**Problem:** Root `-` file (1MB), 247 .out files, 40 tracked test_* scratch files,
18 pass-specific src files, agent coordination histories.

**Fix:** `git rm` tracked noise, consolidate docs, archive pass plans.

---

## Backend Identity (Pass 11 decision)

```
duo compile file.duo                    # C backend (default, portable)
duo compile file.duo --backend=direct   # Direct ARM64 (experimental)
duo compile file.duo --target=wasm32-wasi  # C→Wasm via zig cc
```

- C backend: default, honest, portable, well-tested
- Direct backend: experimental, ARM64-only, restricted subset, explicit errors
- No silent fallback between them

---

## Release Claims (what we CAN say honestly)

✅ "Ahead-of-time compiler that emits C, targeting any clang-supported platform"
✅ "Aggressive typed specialization eliminates boxing for fully-typed .duo programs"
✅ "Experimental direct ARM64 backend for restricted scalar subset"
✅ "40-benchmark suite verified against reference C"
✅ "Lua-shaped semantics with progressive native specialization"

❌ Cannot claim: "direct native compilation" (for general programs)
❌ Cannot claim: "faster than C" (benchmark forces boxing)
❌ Cannot claim: "self-hosted"
❌ Cannot claim: "zero runtime overhead" (closures/metatables still box)
❌ Cannot claim: "complete Lua 5.5 compatibility" (no differential test suite)

---

## Completion Criteria (what makes Pass 11 done)

1. Benchmark mode allows native_scalar path
2. Backend selection is explicit (no silent fallback)
3. Direct backend errors are precise (not generic "unsupported")
4. ARM64 supports spills (functions with >20 values)
5. ARM64 supports sealed record field access
6. Native byte slices exist (for Ward)
7. At least one Ward decoder component compiles without boxing
8. Repository root is clean
9. README claims match reality
10. CI pins toolchain version

---

*Pass 11 is not about adding architecture. It is about making the existing
compiler honest, complete, and releasable.*
