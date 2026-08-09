# Agent Instructions

## THE LAW HAS ONE HOME — READ IT BEFORE YOU WRITE ONE CHARACTER OF `.duo`

**`CLAUDE.md` + `docs/spec/` ARE THE LAW.** This file is a POINTER plus the
mechanical checks. It is not a second copy of the law, because a second copy is
exactly what broke: this file taught `snake_case`, `end`, `@comp.*` and
`M = {}` for months after `CLAUDE.md` retired all four, and every agent that
read only this file wrote epoch-1 duon in good faith. **If this file and
`CLAUDE.md` ever disagree, `CLAUDE.md` wins and the disagreement is a bug in
this file — report it.**

Everything below the line in the old version of this file — `@`-directive
syntax, "Duo Grammar Rules", "Duo Language Conventions", "Syntax Semantics",
the `snake_case` naming rule, the File-as-`M` pattern — is **VOID** under the
epoch-2 precedence rule. It has been deleted. If you have it in context from
an earlier session or from training, **it is not law and never applies.**

## THE LANGUAGE IS `duon`. FILES STAY `.duo`.

## MECHANICAL DENY LIST — a diff containing any row is REJECTED UNREAD

You do not have to remember to run this. `.githooks/pre-commit` runs
`scripts/idiomgate.duo` over your staged diff on EVERY commit, for every agent,
and a finding EXITS NONZERO AND BLOCKS THE COMMIT. To check before you stage:

    DUOGATEFILES="$(git ls-files -m '*.duo')" duo run scripts/idiomgate.duo

(`zig build idiom-gate` is a DIFFERENT, narrower step: it covers 4 files while
its description claims every one. Do not rely on it.)

| you wrote | it is denied because | write instead |
|---|---|---|
| `is_digit`, `do_retry`, `dt_pad2` | **LAW-ONE**: identifiers are ONE lowercase word. `grep [a-z]_[a-z]` outside numerals = 0 | `digit`, `retry`, a LEVEL `pad(2)`, or a HOME `date.pad` |
| `Point`, `Error`, `MAX_N` | no uppercase in identifiers, EVER | `point`, `error`, `max` |
| `end` | **`end` is DELETED.** A body is an offside expression sequence | outdent |
| `;` | the semicolon DOES NOT EXIST (Pass 119) | press enter |
| `then`, `do` | not duon | outdent |
| `@comp.*`, any new `@` spelling | prefix `@` does not exist. Existing `@` spellings are frozen COMPATIBILITY — do not add, do not delete | see `docs/directive_erasure.md` |
| `string.sub`, `string.byte`, `table.insert` | no Lua module idioms; **worlds are the only namespaces** | `s:sub(i,j)`, `s[i]` IS the byte, `xs:push(v)` |
| `std.mem`, `std.fmt`, `std.math`, bare `math.` | RECOGNITION: pure ops are VALUE EDGES | `x:abs()`, `s:copy()` |
| `require`, `local`, `function`, `fn`, `class`, `match`, `switch`, `type` | not duon | bare decl; `type` is denied outright |
| `M = {}` … `return M` | the file IS its scope | declare at file scope |
| `L.next(lex)` — ALIAS-CALL | **FACE-CALL**: if you hold the first argument you hold the RECEIVER | `lex:next()` |
| `.new(`, `.create(`, `make_*`, `init` | the CONSTRUCTOR LADDER | `desc{…}` · `x:to(desc)` · `p:from(polar)(r,t)` · `file.open` |
| `self` as a parameter | **SELF-ZERO** — there is no self | `.x` · leading `:length()` · `.` is the subject · `...` spreads it |
| `if err return nil, err` | zero forwarding plumbing exists in duon | `t \| error`; an unbound failure ROUTES (B-15) |
| `"a" .. x:to(str)` | no concat chains | `"{x}"` |
| `tostring(`, `tonumber(`, `pairs(`, `pcall(`, `setmetatable(` | Lua runtime globals | `:to(str)`, `:to(i64)`, iterate the value |
| plain-string diagnostic / MCP / REPL output | **H-8 OUTPUT TOTALITY** | `(span, role, why, dnir)` tuples |
| any non-`.duo` file | **§0f MONOGLOT** | write duon. No python, no bash, no zig |

## THE FIVE FORMS THAT REPLACE EVERYTHING YOU MISS

You will reach for a keyword duon does not have. **The grammar is CLOSED — NNS
FIRST: capability is the semantics of EXISTING forms, never a new token.** If a
repair seems to need new surface, you have not yet found the form it is hiding.

1. **LEVELS** — the qualifier moves into a paren: `read(number)`, `skip(space)`,
   `add(wrap|sat|checked)`, `any(i64, f64)`.
2. **HOMES** — navigation, not activity: `wire.header`, `token.kind`, `utf8.valid`.
3. **THE AMBIENT TRIAD** — `@` is the enclosing DESCRIPTOR, `.` is the ambient
   SUBJECT, and a walk hangs off either without naming it. `.` alone is the
   zero-length walk and IS the subject.
4. **DEMAND STREAMS** — laziness is the RESTING STATE, so there is no
   comprehension syntax and never will be: `xs:take(odd):map(f)` fuses.
5. **WORLDS** — the only capability namespaces. `std@{ ambient = false }`.

Inferred cases (`tok.kind == .eof`), interpolation (`"{x}"`), and offside layout
are the defaults. Reach for them before anything else.

## THE CORPUS IS NOT THE LAW

**756 `.duo` files still contain bare `end` and 227 contain `string.`.** That is
MIGRATION DEBT, not permission. Do not imitate the file you are editing — check
it against the table above and repair what you touch. The repo's history is not
the repo's law.

---

### 1. The Aha Moment Target
Every feature must create "discoverability moments" — the feeling when Zig's comptime made generics click, when Rust's traits made metaprogramming extensible. Duo features should compose intuitively so developers have revelations about what's possible. Features should be discoverable through common-sense semantics and produce outsized results from minimal input.

### 3. AI/ML-Native (Better Than Mojo)
- `Tensor[dims, dtype]` compile-time shape checking
- `@comp.device(.auto)` — one function targets CPU/CUDA/Metal/WebGPU/WASM
- `@comp.autodiff` — differentiation as compile-time transform
- Kernel fusion via user-definable rewrite rules
- Sub-millisecond startup, <1MB binary (vs PyTorch's 2GB)
- See `docs/ai_ml_native.md` for full design

### 4. Semantic Graph Architecture (THE Meta-Priority)
**This overrides all other priorities.** As of 2026-08-04, Duo's ultimate goal is:

> "A compact language for defining computations, transformations, constraints, and objectives over a persistent semantic universe—where humans, compilers, libraries, and agents all manipulate the same program model at different levels of authority."

**Key pillars (in order of importance):**
1. **Persistent semantic graph with durable identities** — Everything is a graph node
2. **Unified transformation engine** — every transformation is an EDGE carrying its legality as DATA, with contracts and provenance
3. **First-class staging + budgeted partial evaluation** — Agents can reason about computation exposure
4. **Effects and capabilities** — Basis for builds, plugins, agents
5. **Transactional semantic editing** — Safe agent collaboration

**All agents:** See `.agents/AGENT_COORDINATION.md` for the detailed implementation plan. Coordinate via `duo_agent_gaps_update()` rather than duplicating work.

### 5. Performance Guarantee
- Duo MUST beat or tie hand-written C on ALL 40 benchmarks
- Every change MUST be verified against `zig build bench`
- NO performance regressions are acceptable
- Benchmarks must cover: dispatch loops, memory access patterns, SIMD, string ops, table ops, recursion, iteration
- **ALL agents MUST read and update `docs/performance.md`** before and after any performance-affecting change (see *Agent Performance Protocol* in that file)

### 6. NO LUA BOXED VALUES (Critical Rule)

**ALL typed and comptime paths MUST lower to native C scalars and structs. lua_Value intermediaries are NEVER acceptable on any typed/comptime path.**

- Typed function parameters and return values become C types directly (e.g. `i64` → `int64_t`, `float` → `double`, `str` → `const char*`).
- Comptime-evaluated expressions must fold to C literals or typed struct initializers.
- Introducing a `lua_Value` (tagged union / boxed value) on a typed path is a correctness AND performance bug. Reject any codegen change that does this.
- Literal metaprogramming helper calls (`std.pipeline.fuse_*`) MUST fold in codegen when inputs are compile-time strings; do not route proven generator calls through `req` tables, `lua_Value`, or `lua_invoke`.
- Untyped/dynamic paths may still use lua_Value — this is expected for fully dynamic Lua-compatible code.
- When adding features: prefer `native_scalar_mode` eligibility, typed params, and `@comp.c.emit`/`@comp.asm` over dynamic table/string APIs.
- Backfill legacy paths that still box as appropriate to maximize performance.

## Ultimate Lowering Goal

Duo lowers to WHATEVER native format achieves maximum performance — C, assembly, machine code, GPU kernels (CUDA/Metal/WebGPU), SIMD intrinsics, or WASM. The output is NOT limited to C. C emission is the default fallback; specialized backends target asm, SIMD, and GPU kernels where they outperform C.

Duo MUST achieve compile, runtime, and startup speeds that are better than ANY programming language maxed out at the absolute limit by any means necessary.

## Semantic Universe (architectural north star — all agents)

**Read first:** [`docs/AGENT_ALIGNMENT.md`](docs/AGENT_ALIGNMENT.md) (2-min compass).

**Full plan:** [`(archived, deleted — git history)`]((archived, deleted — git history)).

**Architecture passes (read in order):**
- Pass 2: [`(archived, deleted — git history)`]((archived, deleted — git history)) — 8 algebras
- Pass 3: [`(archived, deleted — git history)`]((archived, deleted — git history)) — grammar/directives
- Pass 4: [`(archived, deleted — git history)`]((archived, deleted — git history)) — native backend
- Pass 5: [`(archived, deleted — git history)`]((archived, deleted — git history)) — cross-language
- Pass 6: [`(archived, deleted — git history)`]((archived, deleted — git history)) — architectural reconciliation
- Pass 7: [`(archived, deleted — git history)`]((archived, deleted — git history)) — AI-native compilation
- Pass 8: [`(archived, deleted — git history)`]((archived, deleted — git history)) — persistent semantic computing
- Pass 9: [`(archived, deleted — git history)`]((archived, deleted — git history)) — Ward readiness & runtime supremacy

**Catalogs:** [`docs/catalogs/keywords.md`](docs/catalogs/keywords.md) | [`docs/catalogs/directives.md`](docs/catalogs/directives.md) | [`docs/catalogs/grammar_compactness.md`](docs/catalogs/grammar_compactness.md) | [`docs/catalogs/native_barriers.md`](docs/catalogs/native_barriers.md)

Duo’s long-term shape is not “Lua with every advanced feature.” It is a **compact
language for computations, transformations, constraints, and objectives over a
persistent semantic program model** — humans, compilers, libraries, and agents
manipulate the **same graph** at different capability levels.

**Foundational priorities (Tier A):** (1) persistent semantic graph + durable IDs,
(2) unified transformation engine + contracts + provenance, (3) first-class staging
+ budgeted partial eval, (4) effects/capabilities for builds/plugins/agents,
(5) transactional semantic editing for agent workflows.

**Do not** add new surface — NNS FIRST (A2): the grammar is CLOSED, and capability
is the semantics of EXISTING forms. New capability arrives as an EDGE admitted
under a witness (propose, prove, measure), never as a token, sigil or keyword.
**Predictable composition** is the advantage; a closed grammar is how we keep it.

This plan **preserves** performance gate, Lua superset, native lowering, and
minimum-syntax ergonomics — see §11 of the semantic graph architecture doc.

### Agent documentation protocol

1. **Before any work:** read `.agents/AGENT_COORDINATION.md` and `AGENTS.md`; for perf/codegen also `docs/performance.md`.
2. **Claim** your area in the untracked `.agents/session/` before editing shared surfaces, and name it in the commit message either way.
3. **After** performance or codegen work: append a dated section to `docs/performance.md` with commands run, files touched, measured ratios, and rejected experiments.
4. **After** syntax/semantic fixes: update the semantics table if status changes.
5. **Hardware / low-level**: prefer `.duo` + `@comp.c.emit` / `@comp.asm` / `@comp.device` in `lib/std/hardware.duo` and `lib/std/ml/device.duo` when Lua grammar blocks optimization; do not add Lua-only benchmark gaming.

## Performance Work

**Canonical reference:** `docs/performance.md` — the performance ledger, gap analysis, benchmark inventory, and modification roadmap. Read it at the start of any performance task; append a dated entry after every benchmark-affecting change (including rejected experiments).

- Do not game the benchmark suite. Do not hard-code benchmark outputs, fixed seeds, fixed iteration counts, or one-off literals just to improve a row in `zig build bench`.
- Optimizations should improve a general runtime path, codegen pattern, data structure, or recognizable algorithm family that would transfer to user programs beyond `examples/benchmark.lua` and `examples/benchmark.duo`.
- Benchmark-specific recognizers are acceptable only when they preserve a general algorithmic identity, such as replacing dense Eratosthenes storage with odd-only storage or eliminating redundant work that is provably invariant for the recognized source shape.
- If an optimization only improves one benchmark input and would not apply to nearby programs, reject or revert it and document that decision in `docs/performance.md`.
- Keep quantitative before/after data in `docs/performance.md` for benchmark-affecting changes, including rejected experiments.
- Performance-sensitive changes must still clear correctness first: `zig fmt src/codegen.zig --check`, `zig build unit-test --summary all` when codegen/runtime tests are affected, `zig build`, `zig build test`, and `zig build bench`.

## Known Parallel Agents

Duo is actively developed by 5+ concurrent agents working in parallel. Known agents include:

- devin
- oh-my-pi
- codex
- claude-code
- agy
- ollama
- hermes
- kiro-cli
- cursor/agent
- opencode
- pool
- kilo (npm @kilocode/cli)
- kimi-code (`kimi` binary — `sudo npm install -g kimi-code --allow-scripts=keytar`)
- junie
- trae
- qodercli (@qoder-ai/qodercli)

NOTE on Serena: if Serena appears in a Cursor session it is a project-plugin cache artefact from the wax workspace — not a Duo MCP tool. Dismiss it.

All agents must follow the rules in this file. Before starting work, read the full AGENTS.md and the relevant docs. Coordinate via git commits and docs/performance.md entries to avoid conflicts.

**NEVER `git stash` work away.** Do not stash to reach a "clean tree", dodge a
conflict, or clear the tree for a parallel agent — the stash hides work from
`git status`, all other agents keep building against stale copies, and it caused
one full 23-file rescue (2026-08-01). Commit early on a branch, coordinate via
claims in `.agents/session/`, or export a visible `.patch` file.
`git stash list` must stay EMPTY.

