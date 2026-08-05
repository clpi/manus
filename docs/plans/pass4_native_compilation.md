# Pass 4 — Native End-to-End Compilation

> **Date:** 2026-08-04
> **Follows:** Pass 1 (direction), Pass 2 (convergence), Pass 3 (grammar/directives)
> **Mission:** Eliminate boxed architecture as Duo's center. Own the full compilation pipeline.

---

## A. Executive Findings

### 1. The native backend EXISTS and works for simple typed functions

`src/native_backend.zig` (1950 lines) emits arm64 Mach-O objects directly — no C, no LLVM.
It handles: integers, floats, comparisons, branches, loops, calls (intra-module + @ffi extern),
string literals, register allocation (20 scratch regs), caller-save. Output formats: `.o`, `.s`,
executable (via `clang -o`), `.dylib`.

**Pass 4 milestone for simple cases is ALREADY MET:** `add(a: i64, b: i64): i64 = a + b`
compiles to pure arm64 machine code with zero boxing.

### 2. The C backend has massive dual-path complexity

`src/codegen.zig` (27,783 lines) has 1,135 `lua_Value` references, 66 `lua_invoke` sites,
67 `lua_table_new` calls. For typed .duo modules, `native_scalar_mode` gates all boxing away
and output is 100% native C. For untyped/.lua, output is 100% boxed.

**The architecture is already split** — not "one boxed system with optimization." It's two
parallel emission paths gated by `moduleUsesFullNativeLowering()`.

### 3. MCP servers pass `duo check` and are globally configured

Both `duo_bench.duo` and `duo_lsp.duo` type-check clean. `~/.claude.json` has all three MCP
servers (duo-lsp, duo-bench, zls) configured to launch via `duo run`. Architecture: pure Duo
stdio servers, no Python dependency.

**However:** runtime execution (actual stdio JSON-RPC) was NOT verified — only type-checking.
The MCP servers may compile and run correctly, or may hit runtime codegen issues.

### 4. Native backend covers ~40% of the full "no C" path

What works: integer/float arithmetic, control flow, calls, strings (pointers only).
What's missing: struct/table field access, arrays, mixed int+float, spills (>20 regs),
closures, varargs, x86_64, ELF, optimization passes.

### 5. The Knowledge Lattice is already the gating mechanism

`native_scalar_mode` = knowledge ≥ `.native` at module level. `mixed_scalar_mode` = knowledge ≥
`.guarded`. The lattice from Pass 2 is the EXACT mechanism that gates boxing. Per-expression
knowledge would eliminate more boxing (currently only module-level and per-function).

### 6. Generated-C is currently the ONLY path for non-trivial programs

The native backend handles only simple typed functions. All benchmarks, all MCP servers,
all stdlib code routes through generated C. The C backend IS the production compilation
path and will remain so until the native backend covers struct access and memory.

### 7. The compilation pipeline is already mostly Duo-owned

```
Duo source → Lexer → Parser → AST → Sema → CodeGen → C file → Clang → Binary
                                              ↓ (alternative)
                                     NativeBackend → Mach-O .o → Clang linker → Binary
```

The only non-Duo components: Clang (C compilation + linking). The semantic model, IR,
specialization, and representation selection are all Duo-owned.

### 8. Self-hosting is far but the language can express compiler structures

Duo has typed records, native scalars, direct calls, compile-time evaluation, descriptors.
The missing pieces for self-hosting: byte slices, deterministic memory management, low-level
pointer operations, packed structures. These are achievable through `@comp.c.emit` and
descriptor extensions.

### 9. Runtime is already modular (pay-for-use)

When `native_scalar_mode = true`, the generated C has NO runtime — no GC, no lua_Value,
no generic tables. When `mixed_scalar_mode = true`, only needed runtime components link.
The full runtime only links for fully-dynamic .lua files.

### 10. The 40-benchmark suite validates correctness continuously

Every codegen change is gated by `zig build bench` — 40 benchmarks must match reference C.
This prevents boxing from silently returning to native paths.

---

## B. Current Compilation Pipeline

```
┌─────────────────────────────────────────────────────────────────┐
│ src/lexer.zig → src/parser.zig → src/ast.zig                   │
│                                                                 │
│ src/sema.zig (types, shapes, concepts, knowledge lattice)       │
│                                                                 │
│ ┌─────────────────────────┐  ┌────────────────────────────────┐ │
│ │ src/codegen.zig         │  │ src/native_backend.zig          │ │
│ │ (27,783 lines)          │  │ (1,950 lines)                   │ │
│ │                         │  │                                  │ │
│ │ native_scalar_mode:     │  │ Targets: arm64 macOS only        │ │
│ │   → pure native C      │  │ Emits: Mach-O .o / .s / exe      │ │
│ │                         │  │ Handles: int, float, branch,     │ │
│ │ mixed_scalar_mode:      │  │   loop, call, string literal     │ │
│ │   → per-function native │  │                                  │ │
│ │                         │  │ Missing: struct, array, closure,  │ │
│ │ dynamic mode:           │  │   spill, x86_64, ELF, optim     │ │
│ │   → full lua_Value      │  │                                  │ │
│ └───────────┬─────────────┘  └──────────────┬─────────────────┘ │
│             │                                │                   │
│             ▼                                ▼                   │
│     /tmp/duo_<name>.c               <name>.o (Mach-O arm64)     │
│             │                                │                   │
│             ▼                                ▼                   │
│     clang -O3 -flto                  clang -o <exe> (link only) │
│             │                                │                   │
│             ▼                                ▼                   │
│         executable                       executable              │
└─────────────────────────────────────────────────────────────────┘
```

---

## C. Boxing Inventory

| Category | Count | Where |
| --- | --- | --- |
| `lua_Value` references | 1,135 | codegen.zig (dual-path — only emitted for untyped) |
| `lua_invoke` calls | 66 | Dynamic dispatch when callee unknown |
| `lua_table_new` | 67 | Generic table construction |
| `lua_to_num/str/bool` | 373 | Unboxing at boundaries |
| Total boxing sites | ~1,641 | All gated by `!native_scalar_mode` |

**Key insight:** These are NOT bugs — they're the correct dynamic fallback path.
The native path has zero boxing. The issue is that many programs don't qualify for
`native_scalar_mode` because they mix typed and untyped code.

---

## D. Native Backend Capabilities (arm64 macOS)

| Feature | Status | Notes |
| --- | --- | --- |
| Integer arithmetic | ✅ | Full i64 ops via arm64 instructions |
| Float arithmetic | ✅ | f64 via NEON FP (pure-float fns only) |
| Comparisons | ✅ | `cmp` + `cset` |
| Local variables | ✅ | Scratch register allocation |
| Function calls | ✅ | Intra-module (`bl` patch) + extern (BR26 reloc) |
| String literals | ✅ | `__cstring` + adrp/add relocations |
| If/else/elseif | ✅ | Forward-patched conditional branches |
| While + break/continue | ✅ | Loop context stack |
| Numeric for | ✅ | Positive/negative step detection |
| Register allocation | ✅ | 20 scratch regs, reuse pool |
| Mach-O object emission | ✅ | Sections, symbols, relocations |
| Assembly output | ✅ | `--target native-asm` |
| Executable linking | ✅ | `--target native-exe` via clang |
| Dynamic library | ✅ | `--target native-dylib` |
| Struct/record fields | ❌ | No memory layout |
| Arrays | ❌ | No indexed access |
| Mixed int+float | ❌ | Only pure-int or pure-float fns |
| Register spills | ❌ | Panics at >20 live values |
| Closures | ❌ | No environment lowering |
| Varargs | ❌ | No variadic support |
| x86_64 | ❌ | arm64 only |
| ELF/PE | ❌ | Mach-O only |
| SIMD | ❌ | No NEON/SVE |
| Optimization | ❌ | No peephole/scheduling |

---

## E. MCP/LSP Status

| Component | File | `duo check` | Runtime | Notes |
| --- | --- | --- | --- | --- |
| duo-bench MCP | `~/x/duo-mcp/duo_bench.duo` | ✅ passes | ⚠️ unverified | JSON-RPC stdio server |
| duo-lsp MCP | `~/x/duo-mcp/duo_lsp.duo` | ✅ passes | ⚠️ unverified | Language intelligence tools |
| zls MCP | `~/x/duo-mcp/zls.duo` | ⚠️ unchecked | ⚠️ unverified | Bridges to zls subprocess |
| duo-lsp binary | `~/x/duo-lsp/duo-lsp` | N/A | ❓ | 312KB compiled binary |
| ~/.claude.json | — | ✅ configured | — | All 3 servers registered |

**Architecture:** Pure Duo stdio servers launched via `duo run`. No Python.

**Potential blockers for runtime:** The `duo run` path compiles to C then executes.
Known codegen issues (from coordination buffer) include the pattern-matcher rewrite
being mid-tree (affects `string.gmatch/match/find`), which would break JSON-RPC parsing.

---

## F. Ranked Pass 4 Implementation Plan

| Priority | Workstream | Leverage | Status |
| --- | --- | --- | --- |
| 1 | This document (barrier catalog, pipeline map) | Foundation | ✅ This session |
| 2 | Verify MCP runtime execution (`duo run duo_bench.duo`) | Unblocks agents | Next |
| 3 | Native backend: struct/record field access | Unlocks Pass 4 milestone | Open |
| 4 | Native backend: mixed int+float functions | Widens coverage | Open |
| 5 | Per-expression knowledge lattice in codegen | Eliminates more boxing | Open |
| 6 | Native backend: register spills | Handles complex functions | Open |
| 7 | Native backend: arrays/slices | Memory operations | Open |
| 8 | x86_64 backend | Cross-platform | Open |
| 9 | ELF object emission | Linux support | Open |
| 10 | Runtime component catalog + pay-for-use docs | Architecture | Open |
| 11 | Self-hosting: core data structures in Duo | Bootstrap Stage 2 | Future |
| 12 | Self-hosting: lexer in Duo | Bootstrap Stage 3 | Future |

---

## G. Self-Hosting Readiness

| Stage | Description | Status |
| --- | --- | --- |
| 0 | Bootstrap (Zig compiler exists) | ✅ Current |
| 1 | Compiler-capable Duo subset | 🔄 Typed .duo works for simple programs |
| 2 | Core libraries in Duo | ⬜ Need byte slices, hash maps, arenas |
| 3 | Front end in Duo | ⬜ Need string ops, state machines |
| 4 | Semantic core in Duo | ⬜ Need graphs, complex data structures |
| 5+ | Deeper porting | ⬜ Far future |

**Current blocker:** Duo can express typed scalar programs but lacks low-level
memory primitives (byte slices, pointer arithmetic, packed layouts) needed for
compiler data structures. These could come from `@comp.c.emit` + descriptors.

---

## H. Next Steps

1. **Verify MCP runtime** — `duo run duo_bench.duo` with JSON-RPC probe
2. **Native struct access** — add field-offset lowering to native_backend.zig
3. **Per-call knowledge** — use `exprKnowledge` in codegen call emission
4. **Mixed int+float** — extend native backend ABI to handle both
5. **Document runtime components** — catalog what links when

---

*Pass 4 is not about rewriting. It is about owning progressively more of the path
from source to machine code, removing the C intermediary one subsystem at a time.*
