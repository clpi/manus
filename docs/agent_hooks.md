# Agent Hooks Architecture

## Exponential Dividend Design

Every agent action (one MCP tool call, one `@comp.*` construct) should produce
multiplicative output. This mirrors the `@comp.*` framework's core design:
**O(1) author input → O(n^k) output**.

Agents MUST prefer metaprogramming constructs over manual code generation.

## Hook Points

### For Duo Compiler Development (agents working ON Duo)

| Tool | What it does | Why it matters |
|------|-------------|----------------|
| `duo_meta_catalog()` | Discover all ~200+ @comp.* constructs | Know the full surface before writing code |
| `duo_meta_ladder()` | Understand output scaling (O(n) → O(n!)) | Choose the right multiplier |
| `duo_language_features()` | Know syntax/types/directives implemented | Don't invent what exists |
| `duo_compile_check(path)` | Verify code correctness instantly | Iterate fast |
| `duo_bench_run(name)` | Run benchmarks with structured output | Catch regressions |
| `duo_bench_regressions()` | Compare vs baseline | Performance gate |
| `duo_coordination_buffer()` | Read agent coordination buffer | Never collide |
| `duo_coordination_update(...)` | Claim/release files | Coordinate with 5+ agents |

### For Duo End-User Development (agents writing IN Duo)

| Construct | What it does | Output scaling |
|-----------|-------------|----------------|
| `@comp.catalog()` | Self-documenting language features | O(1) discovery |
| `@comp.ladder()` | Choose right output scaling | O(1) decision |
| `@comp.derive.bundle("Numeric")` | One annotation → 8 trait impls | O(1)→O(8) |
| `@comp.map(types, fn)` | Type sweep with callback | O(types) |
| `@comp.product(A, B, fn)` | Cartesian product | O(n²) |
| `@comp.tensor(A, B, C, fn)` | 3-way tensor sweep | O(n³) |
| `@comp.nfold(concepts, k, fn)` | N-concept sweep | O(n^k) |
| `@comp.ceiling(...)` | Derive sweep + product | O(n×f)+O(n²×f) |
| `@comp.omni(...)` | Ceiling + optional sweep | stacked |
| `@comp.burst` | derive.all + quadratic emit | O(n²×f) |
| `@comp.transcend` | 3-concept derive + map | O(n³×f) |
| `@comp.infinity` | transcend + nfold(4) | O(n⁴×f) |
| `@comp.hyper` | transcend + nfold(5) | O(n⁵×f) |
| `@comp.tower` | nfold with dynamic k (≤16) | O(n^k×f) |
| `@comp.power` / `@comp.powerset` | O(2^n) expansion | truly exponential |
| `@comp.choose` | Fixed-size subset expansion | O(n choose k) |
| `@comp.permute` | O(n!) expansion | factorial |
| `@comp.compile.cached` | Memoize comptime eval | N→1 computation |
| `@comp.embed.file` | Write generated code to disk | reuse across builds |
| `@comp.pipeline({...})` | One descriptor → N fused kernels | multiplicative |

## Workflow: How an Agent Uses Hooks

### Step 1: Discover
```
duo_meta_catalog("grouped")  →  all @comp.* constructs organized by category
```

### Step 2: Choose scaling
```
@comp.ladder()  →  map:O(n), product:O(n²), nfold:O(n^k), power:O(2^n), choose:O(n choose k), permute:O(n!)
```

### Step 3: Apply multiplier
Instead of writing N functions manually:
```duo
-- O(1) input → O(n²) output
@comp.product({"i64", "f64", "str"}, {"json", "binary"}, fun(a, b) ... end)
```

### Step 4: Verify
```
duo_compile_check("output.duo")
duo_bench_run("bench")  # if performance-sensitive
```

## Multi-Agent Coordination Protocol

With 5+ agents active simultaneously:

1. **Read `.agents/AGENT_CANONICAL.md`** at session start (via MCP `duo_agent_session_start` or `duo_agent_canonical_index`)
2. **Claim files** before editing
3. **Serialize builds** (only one `zig build` at a time)
4. **Release files** when done
5. **Log blockers** immediately

## Performance Enforcement

Every codegen or runtime change must:
1. Maintain or improve all 40 benchmarks
2. Eliminate Lua boxed values from hot paths
3. Prefer native lowering (C scalars, SIMD intrinsics, direct asm/object emission where available; C is an intermediate, not the ceiling)
4. Be verified with `zig build bench`

## Duo as Scripting Language

For any scripting task, prefer Duo over Python/bash:
- `std.fs` for filesystem ops
- `std.proc` for subprocess
- `std.env` for environment variables
- `std.argparse` for CLI argument parsing
- `std.json`, `std.yaml`, `std.toml` for data formats
- `std.net.http` for HTTP
- Shebang support: `#!/usr/bin/env duo`

The `@comp.run("cmd")` directive executes shell commands at compile time.
The `std.agent` module provides recipes, build gates, multiplier selection,
and smoke targets for agentic workflows.
