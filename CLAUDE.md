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

## Duo — agent contract (Pass 64, supersedes 59/60/61)

Pass 64 is the canon. Where any prior pass disagrees, Pass 64 wins (AR-1:
the canon is queried live; archives are history).

```
0. MONOGLOT     Never create a non-Duo file. Build, CI, benchmarks, tooling —
                all Duo. A gap is a GAP record, never a .c/.py/.sh file.
                "C would be faster" = fact-loss ledger row, not code.
1. NO FOREIGN   Duo has NO function/class/import/match/try/trait/macro syntax.
                Lua is foreign too: no require, no local, no M = {} pattern,
                no table.*/string.*/pairs/pcall/setmetatable.
2. QUERY FIRST  Before writing any function/table/branch/helper, run the
                leverage ladder (Pass 64 Part VI). Query rewrite[idiom],
                derive[...], the tries. Stopping early is the violation.
                Never invent — no answer = spec gap = report it.
3. DEMAND       The last expression is the result. return = early exit or
                contract only. Nothing physical without consumption.
4. ONE EDGE     Declare once; project everywhere. Never implement both ends,
                parallel renderers, hand dispatch, or foreign twins.
5. COMPACT      One-liners where one semantic unit fits. Emit canonical
                layout; fighting the formatter means your FORM is wrong.
6. PIPELINES    map/filter/fold/find with sections and lenses. Loops only for
                cursors, cross-iteration state, effect ordering, exit
                protocols beyond find/take.
7. SUBJECT      subject:member(args); operators over explicit relations;
                strata always: store(i32)("x"), never store(i32, "x").
8. STRINGS      "{expr}" interpolation always; format(sink) on hot paths;
                .. only concatenates strings that already exist.
9. WITNESS      Every claim measured or marked. Read your manifest delta.
```

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
- **GAP-16 (STR-1) — interpolation has NO ESCAPE.** There is no way to spell a
  literal `{name}` in a Duo string. Any program whose DATA is Duo source
  containing holes — a code generator, a conformance corpus, a doc example —
  has its own data rewritten by the compiler. Not hypothetical: the first run
  of `scripts/spec_conformance.duo` failed with "use of undeclared identifier
  'x'" because the STR-1 row's test PROGRAM was interpolated as if it were the
  harness's own source. Interim: build the brace (`"{" .. "x}"`). This is the
  same class as the blanket `~=` pass that once rewrote a lexer's own corpus
  data — a brace inside a string a program means to EMIT is not a hole, and
  nothing in the language currently lets you say so.
- **GAP-14 (Pass 61 LV-4..7, PIPE-1) — DO NOT APPLY THE LV SEQUENCE ROWS YET.**
  The pinned sequence surface (`map filter fold each find any all count take
  drop sort sort_by max_by min_by join push pop sum`) is **not implemented**.
  Measured 2026-08-07, all 15 probed resolve to nothing. Two of them fail
  SILENTLY, which is why this is a stop-work item rather than a note:
  - `a:push(5); a:push(6)` compiles clean and leaves `#a == 0` — **data loss,
    no diagnostic**.
  - `c:join(", ")` returns **nil**, not the joined string.
  - `vs:map(.name)` is a compile error (the honest failure of the three).
  Meanwhile the vestiges those rows tell you to delete WORK: `table.concat(c,
  ", ")` returns `"x, y"`. So applying LV-4/LV-6 today replaces correct code
  with silently wrong code, and PIPE-1 has no surface to stand on.
  Interim: keep `table.insert`/`table.concat`/`table.sort` and manual loops
  until the surface lands. LV-8 (`for v in t`), LV-10 (`x:to(str)`) and LV-13
  (`#s`) are verified working — those rows are safe to apply now.

  **Do not fix this the obvious way — it was tried and reverted 2026-08-07.**
  Projecting `t:push(v)` onto `table.insert(t, v)` in codegen's `.method_call`
  arm (mirroring how `p:to(str)` projects onto `to(str)(p)`) makes all three
  work — `push` appends, `join` joins, `pop` pops, verified — but it **breaks
  LAW-CALL**. A table carrying its own member,
  `t = { push = mypush }; t:push(9)`, is hijacked by the projection: the
  generated C emits `lua_tbl_insert(t, 9, nil)` on the line after
  `lua_table_set_raw_lit(t, "push", ...)`, and the user's function is never
  called. That trades silent data loss for silent member hijacking, which is
  not an improvement. Guarding with `user_owns_name` is NOT sufficient — that
  sees free functions and locals, not table MEMBERS.
  A correct fix needs one of: receiver-shape knowledge proving the member is
  absent, or a runtime-guarded dispatch (member if present, else project).
  The real fix is probably to implement the surface as actual members rather
  than a codegen projection, so data-wins holds by construction.
- **GAP-15 (SH-03 production dispatch)** — `duo compile --emit obj` and
  `--emit dylib` both produce a Mach-O **executable**, and every `@c.export`
  symbol is emitted with INTERNAL linkage (`nm` shows `t`, not `T`) despite
  the generated C declaring `visibility("default")`. So the Duo lexer cannot
  be linked into the host at all, which is the real blocker under "SH-03
  needs production dispatch" — one level deeper than the matrix records.
- **GAP-12 (rule 1 / FF-1)** — `@comp.c.export` does not attach to a
  value-form binding; it degrades into a call to an undefined `__c_export`.
  Interim: the one exported declaration per module stays bare, commented.
- **GAP-13 (FF-10 / "no req")** — ambient `std.str.sub(...)` and
  `{ sub } = std.str` on a native-direct module **crash at startup**: exit 128,
  no output, before `main` runs. Interim: `global x = req "std.mod"`.
- **GAP-16 (SH-04 parser non-termination) — FIXED 2026-08-07.** The walk of
  `lib/std/**.duo` spun forever. Cause: loops that could iterate without
  consuming a token (a sub-parser returning at EOF, or on a token no arm
  handles), so `join(acc, "")` made no progress. Fixed structurally with a
  `stalled(lx, before)` cursor check on the six accumulating loops rather than
  by hunting triggers — no single construct reproduced it in isolation, only
  the accumulated 750-line prefix did. Corpus walk went 7 files -> 245.
  **First SH-04 coverage number: 44/245 lib/std files parse clean (18%).**
  `scripts/parser_corpus_coverage.duo` is the tool; it terminates, so it is
  committed.
- **GAP-17 (lexer error aborts the process)** — `UnterminatedString` in
  `lib/std/os/linux.duo` kills the whole run instead of returning a rejection,
  so one bad file truncates any corpus walk and silently shrinks the
  denominator. The coverage tool skips that file visibly rather than absorbing
  the loss. A lexer error should be a rejection the caller can count.