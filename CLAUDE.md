# duo — Duo language compiler

Duo is a Lua-superset language targeting native, WASM, and GPU. This repo is the compiler, written in **Zig master** (`0.17.0-dev`, managed via `mise`).

## Toolchain

- **Zig**: `zig@master` via mise — `~/.local/share/mise/installs/zig/master/bin/zig`
- **ZLS**: `zls@latest` via mise — works out of the box with ZLS-aware editors
- **WASI SDK**: installed via mise as `wasi-sdk@latest`
- **Runtimes for testing**: `wasmtime`, `wasmer` (both installed via mise)

Cross-compile to WASM: `zig build -Dtarget=wasm32-wasi` or `wasm32-wasip2`.

## Build commands

```bash
zig build                    # debug build → zig-out/bin/duo
zig build -Doptimize=ReleaseFast   # release build
zig build run -- <file.duo>  # compile and run a .duo file
zig build test               # all tests (unit + compile-fail)
zig build unit-test          # Zig unit tests only
zig build agent-smoke        # tier-0 gate (hygiene + stdlib + meta)
zig build pass11-gate        # Pass 11 profile A closure gate
zig build bench              # Duo vs C benchmark suite
zig build wasm-bench         # WASM runtime benchmark
zig build repo-hygiene       # check for forbidden root artifacts
zig fmt src/                 # format Zig source
```

## Source layout

```
src/
  main.zig              CLI entry point
  codegen.zig           Code generation
  semantic_context.zig  Semantic analysis context
  native_backend.zig    ARM64 native backend
  pass*.zig             Compiler passes (pass3 = parse, pass4 = boxed IR, pass11 = native, pass12 = semantic)
  tests.zig             Test harness
lib/std/               Duo standard library (.duo files)
examples/              Example .duo programs
scripts/               Shell scripts for CI gates and benchmarks
docs/plans/            Active implementation plans (passN_*.md)
```

## Key invariants

- `@` is the single prefix for ALL compile-time operations in .duo files (`@comp.*`)
- NO underscores in `@`-directive names: `@comp.foo.bar`, never `@comp.foo_bar`
- Zero Lua boxed values in the hot path — all values must be native C ABI or direct registers
- Every perf change must pass `zig build bench` with no regressions

## Active plans

- Pass 11: `docs/plans/pass11_release_proof.md` — native ARM64 codegen
- Pass 12: `docs/plans/pass12_semantic_autonomy.md` — semantic autonomy
- Pass 13: `docs/plans/pass13_development_control_plane.md` — dev control plane
- Pass 16: `docs/plans/pass16_self_hosted_compiler.md` — self-hosted compiler supremacy

## Agent coordination

See `AGENTS.md` for full agent design targets. Coordinate via `duo_agent_gaps_update()`.
See `.agents/AGENT_COORDINATION.md` for active work tracking.

## Duo — agent contract (Pass 59/60)
0. MONOGLOT (Pass 60): you may NEVER create a non-Duo file. Build scripts,
   CI, benchmarks, tooling — all Duo. If Duo can't do it, that is a GAP
   record (Pass 60 §2), not a .c/.py/.sh file. Generated artifacts are
   outputs, never edited. "C would be faster" = fact-loss ledger row, not code.
1. Duo has NO function/class/import/match/try syntax. Functions are values:
   `f = (x: t): r ...`. Firewall table FF-1..21 is total — if your habit is
   from Rust/TS/Python/Lua/Zig, look it up before writing.
2. Strings: `"{expr}"` interpolation always; `format(sink)` on hot paths;
   never build with `..` chains.
3. Before writing ANY function/table/branch: run the leverage checklist
   (Pass 55 §4) — edge? derived? hook? projection? bundle? section? dispatch
   table? erased by demand? Query `rewrite[idiom]`, `derive[...]`, the tries.
   Stopping early is the violation.
4. Calls: subject-first when the subject is in hand (`writer:write(x)`,
   `p:to(str)`); operators over explicit relations; strata always
   (`store(i32)("x")`, never `store(i32, "x")`).
5. Control: binding conditions for every lookup/parse/consume; endless
   one-liners; guards `if c return ...`; ranges own counting; demand returns —
   the last expression is the result, no plumbing.
6. Pattern-match ONLY from the golden corpus (Pass 59 §3) and Pass 48 VII.
   Emit canonical layout; your diff is post-canonical; a fight with the
   formatter means your FORM is wrong.
7. When unsure: query, never invent. No answer = spec gap = report it.

### Rules that the compiler cannot honour yet — measured, filed, not guessed

Rule 7 says report gaps rather than invent. These three are filed in
`docs/plans/pass60_gap_register.duo` with minimal repros. Until they close,
the canonical form named by the rule produces **silently wrong output or a
crash**, so the listed interim spelling is the correct one to write.

- **GAP-11 (rule 2 / STR-1)** — MOSTLY CLOSED 2026-08-07 (commit 8ced8f8).
  Re-measured after the fix, so the interim advice below is narrower than it
  was: **write interpolation, not `..` chains, for names and fields.**
  - `"{x}"` single-character hole — **works**. The root cause was a guard
    requiring "not every character the same", which one character trivially
    is, so every single-letter hole was skipped. `{i}`, `{n}`, `{b}` are the
    common case in exactly the loops interpolation is for.
  - `"{p.x}"`, `"{d.inner.z}"` dotted paths — **work** (added in the same
    commit). This covers the golden corpus's `"{p.x}, {p.y}"` and
    `"line {lx.line}"`.
  - `"{count}"` on an i64, and f64/str — **work**, in `main` and in typed
    `: str` functions alike. Verified; the earlier "fails to compile" note
    did not reproduce.
  - STILL LITERAL, no diagnostic: **expression holes** — `"{i + 1}"`,
    `"{to(str)(i)}"`. Also leading-`.` lens holes `"{.kind}"` (STR-4), which
    need an ambient subject and are deliberately unclaimed rather than
    misread as a name.
  - Malformed holes stay literal by design: `{a.}`, `{.x}`, `{a..b}`, `{1x}`.
  Interim: `..` chains ONLY for expression holes.
- **GAP-12 (rule 1 / FF-1)** — `@comp.c.export` does not attach to a
  value-form binding; it degrades into a call to an undefined `__c_export`.
  Interim: the one exported declaration per module stays bare, commented.
- **GAP-13 (FF-10 / "no req")** — ambient `std.str.sub(...)` and
  `{ sub } = std.str` on a native-direct module **crash at startup**: exit 128,
  no output, before `main` runs. Interim: `global x = req "std.mod"`.
