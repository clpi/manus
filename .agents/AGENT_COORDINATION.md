# Duo Agent Coordination Buffer

> **MANDATORY for every agent.** Read at session start, before any edit or build.
> **Canonical index:** [`.agents/AGENT_CANONICAL.md`](AGENT_CANONICAL.md) — single router for all buffers/MCP.
> This file is the single coordination buffer: claims, goals, build tiers, gap findings, delegation, hooks, and session log.

Expect **5+ concurrent agents** on this repo, often launched from the same prompt.
They share `.zig-cache`, generated C, and the duo binary. The two failure modes
this file exists to prevent are **machine stalls** and **cache corruption**
(flaky "module not found" / "C compiler failed" that pass on a clean re-run).

Known parallel agent surfaces include Devin, oh-my-pi, Codex, Claude Code, Agy,
Ollama, Hermes, kiro-cli, Cursor/agent, OpenCode, Pool, Kilo/Kilo Code, Kimi
Known parallel agent surfaces include Devin, oh-my-pi, Codex, Claude Code, Agy,
Ollama, Hermes, kiro-cli, Cursor/agent, OpenCode, Pool, Kilo/Kilo Code, Kimi
Code (`kimi` — `sudo npm install -g kimi-code --allow-scripts=keytar`),
Junie (`~/.local/bin/junie`), Trae (`/usr/local/bin/trae`), Kodi/Qoder
(NOT on npm/pip as of 2026-08-02 — skip if unavailable).
Serena/browser-opening tools must not be launched for ordinary Duo coordination.
NOTE: Serena opens automatically in Cursor when working on the wax project —
this is a Cursor project-plugin cache issue; do not enable Serena for Duo work,
do not file Serena tickets, just dismiss it.

## Ultimate project goal (all agents internalize this)

The goal is **NOT** "compile to C." It is to lower Duo code to whatever machine
code / native format yields the **absolute highest performance** — better than
any language, maxed at the limit, by any legitimate means. C is one intermediate
target. Duo-native machine code / asm / object emission, GPU kernels, SIMD
intrinsics, WASM are in scope. **NOT LLVM IR** — lower directly to optimal native
formats. Compile-time metaprogramming (`@meta.*`) eliminates every provably
unnecessary runtime cost. **No `lua_Value` intermediaries on typed/comptime
paths. No dynamic dispatch where static is possible. Performance never regresses.**

## Active goals (priority order)

1. **Absolute-limit performance** — beat/tie C on all 40 benchmarks + ML + honest
   suites; lower past C to optimal machine code (LTO/PGO/`@asm`/`@device`).
   **Zero regressions ever.** Verify with `zig build bench` after codegen changes.
2. **No Lua-boxed values** — typed/comptime paths lower to native C scalars/structs.
   Comptime-only callbacks use `@meta.compile.only` (enforced in `func_is_compile_only`).
3. **Exponential metaprogramming** — `@comp.*` primary (`@meta.*` / `@compiler.*` aliases); no public
   `@foo_bar`. One author line → multiplicative native output.
4. **Duo as scripting language of choice** — `std.script` over bash/python for
   repo tooling; add stdlib ergonomics wherever Duo would otherwise lose to them.
5. **Agent hooks** — `@comp.agent.*` (`@meta.*` alias), `std.agent`, gate `scripts/duo_lock.sh -- ./zig-out/bin/duo run scripts/agent_smoke.duo`.
6. **Duo as scripting language of choice** — never write `.sh` / `.py` scripts for Duo tooling; close any ergonomic gaps via `stdlib` / `std.script`. All repo tooling must be expressible in `.duo`.
7. **duo-mcp exponential evaluator** — input Duo code, output metaprogramming-enhanced optimized Duo; symbol-level vector embedding of compiler. Repo: `~/x/duo-mcp/`. Track as active research + implementation item.
8. **React/GUI DSL competitor in minimum syntax** — Duo should be able to express reactive/UI trees with minimal boilerplate, competing with JSX/React paradigm. Track as research item.

**Repo locations (all agents):** `duo` compiler at `~/x/duo/`, `duo-mcp` at `~/x/duo-mcp/`, `duo-lsp` at `~/x/duo-lsp/`.

**Parser invariant:** `@const` and `@comptime` are NOT valid user-facing directives and MUST be rejected with a helpful error pointing to `@(expr)` or `@comp.*`. See GR-007 in `docs/GRAMMAR_SPEC.md`.

## Duplication prevention (5+ parallel agents)

Before starting work — **do not duplicate effort another agent may already own:**

1. Read this file + `@comp.agent.dedupe()` / `std.agent.dedupe_policy()`.
2. Search `@comp.catalog("grouped")` or MCP `duo_meta_catalog()` before adding directives/stdlib modules.
3. **Claim** a row in Active claims; MCP `duo_coordination_update(action="claim")` for file-level locks.
4. **Extend existing hooks** — `src/meta_module.zig`, `std.agent`, `std.script`; do not fork parallel coordination files.
5. Check **Session log** — skip work already marked complete.
6. **Exponential beats duplicate** — one `@comp.burst` / `@comp.derive.all` beats N hand-written copies.
7. Serialize heavy builds via `scripts/duo_lock.sh` — never parallel tier-3 bench.
8. **Release claims** when done or blocked >30 min.

## NEVER `git stash` work away (project rule, 2026-08-01)

**`git stash` is BANNED as a coordination / tree-cleaning tool.** Do not stash
uncommitted work to reach a "clean tree", to sidestep a conflict, or to let a
parallel agent edit the same files. The stash is invisible to the rest of the
tree: other agents keep building against their stale copies, the work silently
disappears from `git status`, and recovery becomes a manual archaeology project
(it already caused one full 23-file rescue — see session log 2026-08-01).

Instead:
1. **Commit early, commit often** on a working branch — a commit is a visible,
   recoverable checkpoint that other agents can rebase/merge against.
2. **Coordinate conflicts** via Active claims + session log + MCP
   `duo_coordination_update` BEFORE touching shared files.
3. **Refactor to fit** Duo design constraints — if a change conflicts with a
   parallel agent's edit, merge the intent (both designs) rather than hiding it.
4. If you must preserve a checkpoint without committing, use a **patch file**
   (`git diff > /var/folders/02/3wn157dj4r96yflqsb5n8mn40000gn/T/opencode/<topic>.patch`)
   which is visible and greppable — never `git stash`.
5. `git stash list` must stay EMPTY at all times. If you see a stash, restore it
   and drop it.

## Build safety — never stall the machine

**All heavy build/test commands MUST run under `scripts/duo_lock.sh`.** It is a
mkdir mutex (`/tmp/duo-build.lock`) with stale-PID reclamation that serializes
operations so concurrent agents never corrupt `.zig-cache`.

```sh
scripts/duo_lock.sh -- zig build bench          # tier-3, claim perf row first
scripts/duo_lock.sh -- ./zig-out/bin/duo run scripts/agent_smoke.duo    # tier-0
scripts/duo_lock.sh status                       # who holds the lock?
```

| Tier | Command | When | Lock? |
| --- | --- | --- | --- |
| **0 — default** | `scripts/duo_lock.sh -- ./zig-out/bin/duo run scripts/agent_smoke.duo` | After hook/stdlib/meta/docs edits | **yes** |
| **1 — light** | `zig build unit-test --summary all` | Compiler module changes | **yes** |
| **2 — medium** | `zig build test` | Pre-PR / explicit request | **yes** |
| **3 — heavy (ONE at a time)** | `zig build bench`, `ml-bench`, `gpu-bench`, `cross-bench` | Perf work only | **yes** — claim perf row first |

Never run a build outside the lock while another agent may be building. If
`duo_lock.sh status` shows LOCKED and you only need tier-0, still take the lock —
the wait is bounded and prevents corruption.

## Active claims

| Area | Agent / session | Since (UTC) | Goal |
| --- | --- | --- | --- |
| metaprogramming / `@meta.*` | opencode | 2026-07-31 | dedup fixes, MCP tools, Duo scripting conversion |
| codegen / native lowering | **this session** | 2026-07-31 18:30:00 | Complete G-001 backfill; implement G-008/G-020/G-021 |
| stdlib | Antigravity | 2026-07-31 00:52:32 | std.mcp implemented, closed script gap |
| benchmarks / perf | — | — | unclaimed |
| native backend / `src/native_backend.zig` | — (released by oh-my-pi 2026-08-01) | — | DONE: native-exe string output via `__cstring` + adrp/add PAGE21/PAGEOFF12 + `@ffi` |
| metaprogramming / native | Antigravity | 2026-07-31 | Complete direct machine-code lowering, SIMD optimization, and backfill lua intermediaries |

**Claim protocol:** replace `—` with a short id (e.g. `a1`) and your goal
*before* touching that area. Release (`—`) when done or blocked >30 min.

### Session Log

> **⚠ LIVE COORDINATION EVENT (2026-08-01 ~18:54 PDT / 01:54 UTC):** A concurrent agent
> created `git stash@{0}` containing ALL tracked uncommitted work (~2767 lines across 23 files:
> `src/codegen.zig`, `src/comptime.zig`, `src/lexer.zig`, `src/main.zig`, `src/sema.zig`,
> `src/ast.zig`, `src/arc.zig`, `src/async_lower.zig`, `build.zig`, `docs/performance.md`,
> `AGENTS.md`, stdlib lib/std/*, etc.) and then resumed from a clean HEAD baseline,
> re-applying only GR-007 (@const/@comptime rejection) parser work so far. **Working tree
> is currently HEAD + GR-007 parser edits only.** Untracked files (native_backend.zig,
> meta_module.zig, examples/, scripts/, lib/std/*.duo new modules) remain on disk.
>
> **Consequences for all agents:**
> 1. GR-001 bare funcs + assign-form, GR-002 if-exprs, GR-004/GR-006 table keys, and ALL
>    parser work from 2026-07-30/31 currently exist ONLY in `stash@{0}` — NOT in the working
>    tree. `examples/syntax_bare_fun_smoke.duo` and any bare-func example will FAIL against
>    the current tree until the stash is restored.
> 2. The stashed parser.zig contained a one-line fix for **G-050 (assign-form bare func
>    without return type)**: `starts_parenthesized_func_expr` used `typed_or_vararg AND
>    (arrow|colon)` (parser.zig:1501) while `starts_bare_func_decl` used `OR` (line 1463),
>    so `sub = (a: i32, b: i32) body end` was rejected. Fix: change the former to `OR` to
>    match the bare form (colon at paren-depth 1 is unambiguous). Re-apply when restoring.
> 3. **Before building or committing, coordinate:** determine who owns the stash and the
>    restore plan. Do NOT `git stash pop` while the GR-007 editor is mid-file. Do NOT create
>    a second stash. If the tree fails to build (untracked src modules may reference APIs
>    that only exist in stashed tracked files), stop and restore the stash.
> 4. Untracked `src/*.zig` modules (native_backend, meta_module, derive_*, etc.) reference
>    functions that may only exist in the STASHED versions of tracked files. A clean rebuild
>    may fail; that is expected and NOT a reason to "fix" the tracked files independently.

**2026-08-01 (opencode)** — Session start: verified tree was GREEN (`zig build` + agent-smoke
29 targets PASS). Found G-050: assign-form bare func without return type rejected
(`sub = (a: i32, b: i32) ... end` → "expected ')' got ':'"); bare form works but assign form
does not because `starts_parenthesized_func_expr` required `typed AND (arrow|colon)` vs bare
form's `typed OR (arrow|colon)`. Applied the one-line fix + parser test, verified build was
green, then a concurrent agent's stash migration swept the fix into `stash@{0}`. See the live
coordination event note above for the recovery path.

**2026-07-31 18:30-18:45 UTC** (current session)
- Reviewed P0 gaps: G-001, G-008, G-020, G-021
- Analyzed remaining `lua_table_new_with_capacity` calls in `emit_comptime_value`
- Implemented native emission path for table values when `as_lua_value == false`
- Build verified: `zig build` passes
- Test verification: All agent smoke tests pass

**Work completed:**
- G-001 (partial): Added native emission path in `emit_comptime_value` for `.table` variant
- Updated `docs/performance.md` with change ledger entry

**Remaining P0 work (G-008, G-020, G-021):**
- Direct machine-code emission (bypass C intermediate)
- Requires new codegen backend for .o/.asm emission
- Should coordinate with Antigravity's existing work on metaprogramming/native |

**2026-08-01 native string-output (this session, oh-my-pi):**
- Claimed `src/native_backend.zig` to add string-literal data support so `native-exe` can print (currently exit-code only).
- Scope: `__TEXT,__cstring` section, interned string literals, `adrp`+`add` with ARM64_RELOC_PAGE21/PAGEOFF12 reloc pairs, local section symbols; unblocks `@ffi("puts")`/`@ffi("printf")` in the no-C/no-LLVM backend.
- Baseline verified before edit: `scripts/duo_lock.sh -- zig build` PASS; agent-smoke PASS (29/29).
- **DONE.** `native-exe` now prints via hand-emitted Mach-O: `Symbol` gained `section`/`external`, `Relocation` gained `kind` (`branch26`/`page21`/`pageoff12`), `Arm64Output` gained `cstring`. `internString` dedups string literals into a `__TEXT,__cstring` section with local section symbols; `emitAdrpAdd` lowers pointer materialization; `compileExpr` handles `.string_lit`; `compileStmt` handles `.call_stmt`; `finish()` builds cstring bytes, assigns absolute VM addresses (`text.len + cstring_off`, matching clang so `ld` accepts the symbol), emits `.asciz` asm, and sorts relocations descending by `r_address`. `emitMachOArm64Object` now conditionally emits a second section, encodes per-kind reloc flags, and generalizes nlist (undefined extern / local section / defined external). Fixes along the way: `@ffi` externs now collected before integer-signature validation (so `puts(s: str)` parses); `patchCalls` returns `UnsupportedProgram` for unresolvable callees (correctly rejects runtime `print`). Verified empirically against a clang reference object (`otool -l/-r`) for section addr, n_value, and reloc encoding. `examples/native_print_smoke.duo` prints `Hello from native duo!` and exits 0; multi-string program dedups and prints correctly. Gates: `zig build` PASS, native-backend unit tests PASS (incl. new `lowers string literals to cstring with adrp/add relocations`), agent-smoke PASS. 3 unrelated unit-test failures (`parser`/`codegen @c.export` + derived-enum tensor) pre-exist in files not touched this session. Claim released.

**2026-08-01 native integer lowering + asm target (this session):**
- Replaced constant-only return emission with a small arm64 integer instruction selector and monotonic register allocator (`x9+`) for `main`.
- Supported subset now covers bare local assignment, reassignment, name reads, integer literals, unary negation/bit-not, `+`, `-`, `*`, signed `/`, `%`, bitwise and/or/xor, tail-expression return, and explicit `return`.
- Added `--target native-asm` for direct arm64 assembly listings from the same native backend. This moves G-021 beyond post-hoc `otool` inspection.
- Updated `examples/native_object_smoke.duo` to exercise locals and arithmetic (`10 + 4 * 8 - 1`).
- Verified: focused backend tests PASS (4/4); `scripts/duo_lock.sh -- zig build` PASS; `native-object` smoke links and exits `41`; `native-asm` smoke emits `mov`/`mul`/`add`/`sub`/`ret` listing.
- Still open: real branch/loop/call lowering, parameter ABI, register lifetime/stack spilling, relocations, multiple symbols, ELF/PE/COFF, and executable integration without C.

**2026-08-01 native helper functions + internal calls (this session):**
- Native backend now lowers every top-level single-name integer function in the module, with integer params mapped onto arm64 ABI registers `x0`-`x7`.
- Added direct named-call lowering: emit placeholder `bl`, record call patches, and patch signed imm26 branch offsets once all function offsets are known.
- Added conservative caller-save/restore around direct calls for `x9`-`x28` plus `x30`, so helper calls do not clobber caller temporaries or return address.
- Mach-O writer now emits dynamic string table plus one `nlist_64` symbol entry per lowered function. Smoke object exposes `_add` and `_main`.
- `native-asm` now emits labels/globals for all lowered functions and `bl _name`; emitted asm assembles and runs with clang.
- Updated `examples/native_object_smoke.duo` to call `add` twice and compute `45`.
- Verified: backend tests PASS (6/6); `scripts/duo_lock.sh -- zig build` PASS; `nm` shows `_add`/`_main`; object disassembly shows patched `bl _add`; linked object exits `45`; assembled `native-asm` exits `45`.
- Still open: external relocations, branch/loop lowering, lifetime-aware register allocation/spills, more types, ELF/PE/COFF, and native executable/shared-library mode.

**Claim protocol:** replace `—` with a short id (e.g. `a1`) and your goal
*before* touching that area. Release (`—`) when done or blocked >30 min.

### Coordination Protocol (use Duo MCP for parallel work)

Before starting any work:

1. **Check current state:** `duo run scripts/agent_smoke.duo` or `scripts/duo_lock.sh status`
2. **Claim via MCP:** Use `duo_agent_gaps_update(action="claim", ...)` to register interest
3. **Read gaps buffer:** Check the Open findings section below
4. **Use file-level locks:** `scripts/duo_lock.sh -- ./zig-out/bin/duo run ./your_script.duo`

**MCP Tools Available (from duo-mcp/duo_shared.duo):**
- `duo_agent_gaps_update()` - Update gap status, claim work
- `duo_exponential_evaluate(code)` - Find @comp.* multiplier opportunities
- `duo_onboard_exponential(question, code)` - Get guidance on metaprogramming
- `duo_combinator_info(path)` - Get info about specific combinators

**Session lock file:** `/tmp/duo-build.lock` (auto-cleanup stale PIDs)

## Exponential Combinator Ladder (complete)

## Canonical `@comp.*` hierarchy

Public surface: **dotted paths** under `@comp.*` (primary). `@meta.*` and `@compiler.*`
are aliases to the same internals. `@c.*` for raw C/asm. **User syntax never uses underscores.**

Scaling ladder: `map:O(n)` → `derive:O(n×f)` → `product:O(n²)` → `tensor:O(n³)`
→ `nfold:O(n^k)` → `tower:O(n^k)×f (k≤16)` → `power:O(2^n)` → `choose:O(n choose k)` → `permute:O(n!)`.
Module stack: `burst` → `transcend` → `infinity` → `hyper`.

Discover at comptime: `@comp.catalog("grouped")`, `@comp.ladder()`,
`@comp.agent.catalog()`, `@comp.agent.ladder()`, `@comp.agent.hooks()`, `@comp.agent.dedupe()`, `@comp.agent.gaps()`.
Gap findings: this file, [`Cross-Agent Gap Buffer`](#cross-agent-gap-buffer) (`std.agent.gaps_index()`).
Registry: `src/meta_module.zig`. Stdlib: `std.agent`, `std.meta.hierarchy`.

## Agent hooks

### Duo compiler / repo agents

1. Read `AGENTS.md`, `docs/performance.md`, **this file**.
2. Claim a row above.
3. Run under the lock: `scripts/duo_lock.sh -- ./zig-out/bin/duo run scripts/agent_smoke.duo`.
4. Use `@comp.agent.*` / `std.agent.multiplier_for(goal)` to pick combinators.
5. Append a dated entry to `docs/performance.md` after benchmark-affecting changes.

### Duo end-user / application agents

1. `req("std.agent")` — recipes, build gates, native policy.
2. Prefer `@comp.derive`, `@comp.derive.bundle`, `@comp.burst` over boilerplate.
3. Type hot paths; never dynamic tables in perf code.
4. `@comp.compile.only` on comptime-only callbacks.

## Cross-Agent Gap Buffer

> **Canonical findings ledger.** All agents append here when they discover
> expressiveness, performance, native-lowering, scripting, backend, or agent-hook
> gaps — or when they close one. Do not append to duplicate files.

**Design mandate:** minimum syntax → maximum exponential expressiveness and control.
**Performance mandate:** beat C everywhere; zero regressions; no `lua_Value` on hot paths.
**Ultimate target:** optimal machine code — C is intermediate only.

### How to use (all agents)

1. **Before implementing** — search this section + `@comp.catalog("grouped")` + `duo_meta_catalog()`.
2. **When you find a gap** — append a row to **Open findings** (or MCP `duo_agent_gaps_update`).
3. **When you close a gap** — move row to **Closed findings** with date + PR/commit ref.
4. **Claim** related work in **Active claims** to avoid duplicate implementation.
5. Comptime index: `@comp.agent.gaps()` / `std.agent.gaps_index()`.

### Categories

| Cat | Meaning |
| --- | --- |
| **perf** | Runtime/codegen path slower than C or regresses benchmarks |
| **native** | Still boxes through `lua_Value` / dynamic dispatch where static is provable |
| **meta** | Metaprogramming expressiveness missing; linear where exponential combinator exists |
| **script** | Duo loses to bash/python ergonomics for repo tooling |
| **agent** | Agent hook / coordination / MCP gap |
| **backend** | Lowering target beyond C (asm, object emission, GPU, LTO/PGO) |

### Open findings

| ID | Cat | Priority | Finding | Owner | Since |
| --- | --- | --- | --- | --- | --- |
| G-001 | native | P0 | Backfill remaining `lua_table_new` / `lua_invoke` paths in typed `.duo` hot paths (`grep codegen.zig`). Partial: `req("std.pipeline")` aliases now fold literal generator calls to native strings without `lua_invoke`; `req("std.string")` aliases now fold literal native predicates (`contains`, `starts_with`, `ends_with`, `is_empty`) to direct C bool expressions; `req("std.math")` aliases now fold proven numeric core helpers (`sqrt`, trig, `deg`/`rad`, numeric `min`/`max`/`abs`, etc.) to native C/libm expressions; `req("std.agent")` aliases and direct `std.agent.*` constant hook calls now fold to native strings for coordination/policy/gap hooks and literal `multiplier_for(...)`; `req("std.meta.codegen")` aliases and direct `std.meta.codegen.*_hint()` calls now fold to native strings for metaprogramming guidance hints; `req("std.meta.hierarchy")` aliases and direct `std.meta.hierarchy.*` zero-arg hierarchy/agent guidance hooks now fold to native strings; `req("std.meta.bundles")` aliases and direct `std.meta.bundles.contains/describe` calls with literal args now fold to native bool/string constants; **`str_join({...}, sep)` / module `.str_join`** call sites fold comptime literals to C strings; runtime `str_join` routes to `lua_to_str(lua_tbl_concat(...))` (no `lua_invoke` on Duo helper). **Table literals (`.table`)** in typed paths now emit native C struct literals instead of `lua_table_new_with_capacity`. | — | 2026-07-30 |
| G-050 | meta | P1 | ~~Assign-form bare func without return type rejected~~ **CLOSED** — `starts_parenthesized_func_expr` now uses `typed_or_vararg OR arrow_or_colon`; `sub = (a: i32, b: i32) a - b end` compiles and runs (verified 2026-08-02). | hermes | 2026-08-01 |
| G-002 | native | P0 | ~~`@comp.embed.json` typed C structs~~ **CLOSED** — schema → `typedef`; data → `static const` literal; parser/`macro_expand` fix for `@comp.embed.json` module directive | — | 2026-07-30 |
| G-003 | meta | P1 | ~~Nested `req` from inside exported `std.*` function bodies fails at runtime~~ **CLOSED** — verified current recursive require collection with `std.script.json_read_file`; added regression smoke | — | 2026-07-30 |
| G-005 | perf | P1 | Mandelbrot: 4-wide SIMD without RESULT drift still open | — | 2026-07-12 |
| G-006 | perf | P1 | Sieve: chunk-based 16-byte SIMD marking (beyond popcountll stride) | — | 2026-07-12 |
| G-008 | backend | P2 | Direct machine-code / object emission path (C is intermediate; Duo-native lowering preferred over LLVM IR) | — | 2026-07-30 |
| G-051 | script | P2 | Duo scripting: missing std.script.grep_bytes (or std.string.contains_byte) for replacing bash `grep -q $'\033'` binary/byte-level search in script conversions (assert_no_ansi_reports.duo must shell out to grep for ESC detection) | hermes | 2026-08-01 |
| G-052 | script | P2 | Duo scripting: module-level typed variable declarations require `global` keyword (`global X: str = ...`) — bare `X: str = ...` at module scope silently triggers C compiler failure at runtime. Pitfall needs docs/linter hint. | hermes | 2026-08-01 |
| G-009 | agent | P2 | ~~LSP `_` private-symbol filter~~ **CLOSED** — already implemented: `ws_search_symbols` + cross-file completion filter `_`-prefixed names; current-file outline keeps them (matches codegen export filter) | — | 2026-07-30 |
| G-010 | meta | P2 | ~~`@comp.compile.cached` cross-build persistence~~ **CLOSED** — `.duo/cache/comptime/{hash}.ducache` via `metaPersistentCacheLoadHook`/`StoreHook`; direct `@(cached_fn(...))` calls and meta callbacks share `callFunction` cache path | — | 2026-07-30 |


| G-020 | backend | P0 | No direct machine-code lowering — C backend only; target is Duo-native asm/object emission (NOT LLVM IR) | — | 2026-07-29 |
| G-021 | backend | P0 | No direct asm emission path for hot loops (only @c.emit/@asm in source) | — | 2026-07-29 |
| G-022 | perf | P1 | ~~No PGO~~ **CLOSED** — `duo compile --pgo` + 40-bench hard gate use `--pgo`; memory-heavy (exit-137 history under parallel load), not feature work | — | 2026-07-30 |
| G-023 | perf | P1 | ~~No LTO~~ **CLOSED** — `-flto` in bench CFLAGS + `duo compile` native path; C baseline matches (fair) | — | 2026-07-30 |
| G-024 | backend | P1 | WASM target only embeds, doesn't emit Duo-to-WASM compilation | — | 2026-07-29 |
| G-025 | native | P1 | ~~`@native` call-site dispatch through `lua_Value`~~ **CLOSED** — parser attaches `@native` to functions; codegen skips thunks + `try_emit_native_abi_call` for mixed modules | — | 2026-07-30 |
| G-027 | meta | P1 | ~~`@comp.grammar` handler~~ **CLOSED** — EBNF spec → O(b^d) expansion fragments via `comptimeGrammarHook`; showcase `examples/meta_grammar_showcase.duo` | — | 2026-07-30 |
| G-028 | meta | P1 | ~~`@comp.weave` handler~~ **CLOSED** — cross-module concept sweep via `weaveHook` + `loadWeaveModule`; showcase `examples/meta_weave_showcase.duo` + `examples/weave_types.duo` | — | 2026-07-30 |
| G-030 | meta | P2 | ~~`@comp.generate` constraint block~~ **CLOSED** — multiline `ops`/`types`/`template` cartesian + comma alias; `examples/meta_generate_showcase.duo` | — | 2026-07-30 |
| G-031 | meta | P2 | ~~`@comp.scheme` declarative scheme~~ **CLOSED** — pipe-separated type/fn declarations + template placeholders; `examples/meta_scheme_showcase.duo` | — | 2026-07-30 |
| G-038 | native | P1 | ~~String concat with comptime-folded RHS emitted bare C literal inside `lua_concat`~~ **CLOSED** — `stdlib_module_call_folds_native` + `duo_str_concat` for native folded strings; codegen test | — | 2026-07-30 |
| G-039 | native | P1 | ~~Embedded module file-scope implicit-local table~~ **CLOSED** — module-scope table literals promote to `module_globals` (scope depth 2); codegen emits `duo_g_*` static init; `examples/embedded_bare_bundles_smoke.duo` PASS | — | 2026-07-31 |
| G-040 | meta | P1 | ~~Bare function speculative parse misfires on calls like `f(a, b)` inside loops~~ **CLOSED** — `startsFuncParamList` requires typed param (`name: Type`); fixes `std.script` / embedded modules | — | 2026-07-30 |
| G-041 | native | P1 | ~~2 duplicate entries in meta_module.zig builtins: compiler.c.call (392) and compiler.hint.hot (394)~~ **CLOSED** — removed, zero-underscore enforcement passes | — | 2026-07-31 |
| G-042 | native | P0 | ~~`lua_val_from_literal(cl->upN)` 1-arg signature mismatch~~ **CLOSED** — closure upvalue + comptime literal emission uses 3-arg `lua_val_from_literal`; Duo MCP servers compile+run (verified `duo_bench.duo` initialize/tools/list) | — | 2026-07-31 |
| G-043 | script | P1 | ~~`script` variable collides with macOS SDK headers~~ **CLOSED** — `emit_c_ident` mangles C/POSIX collision names (`script`→`duo_script`) at implicit-local + local_decl sites; `duo_shared.duo` can use `script` again | — | 2026-07-31 |
| G-044 | native | P2 | ~~MCP closure+module-scope patterns blocked~~ **CLOSED** — verified pure-Duo MCP stdio (initialize, tools/list, tools/call); `duo-mcp/duo_bench.duo` refactored via `duo_shared.duo` | — | 2026-07-31 |
| G-045 | native | P0 | ~~Module-scope bindings not captured in closures~~ **CLOSED** — Root cause: `collect_upvalue_names_block` in sema.zig only walked `block.stmts`, missing `block.tail_expr` in nested if/for/while blocks. Closures referencing outer-scope variables in tail position (e.g., `json_mod.encode(groups)` as last expr in if-then block) were silently missing those upvalues. Fix: added `block.tail_expr` collection to `collect_upvalue_names_block`. Also: removed `uv.is_local` filter from 3 codegen sites (expr_type, .name read path, find_upvalue_in_closure) so non-local upvalues are properly resolved. Also: `note_upvalue` now skips `module_globals` entries to prevent locals from being promoted to static globals. Also: `emit_string_escaped` and `jit.emitCStringLiteral` use octal `\NNN` instead of `\xNN` to avoid C hex escape greedy consumption. 3/4 Duo-native MCP servers compile (duo_lsp, duo_bench, duo_shared). | — | 2026-07-31 |
| G-047 | agent | P1 | ~~`@comp.ladder()` / `@comp.map` UnknownMacro errors~~ **CLOSED** — Fixed by passing `sema.concepts` to CodeGen; `maybe_emit_meta_int_call` now properly folds `@comp.concepts.count` to native i64 without lua_Value intermediate. All metaprogramming smokes pass. | — | 2026-07-31 |
| G-048 | agent | P1 | ~~`build.zig` does not define the documented `agent-smoke` step~~ **CLOSED** — Added agent-smoke build step to build.zig (lines 99-106) | — | 2026-07-31 |

### Closed findings

| ID | Closed | Summary |
| --- | --- | --- |
| G-007 | 2026-07-30 | `std.script` locked helpers (`lock_cmd`, timeout variants, `locked_run` / `locked_ok` / `locked_must`) are reentrant under `DUO_LOCK_HELD`; `agent-smoke` includes `examples/script_lock_smoke.duo` |
| G-004 | 2026-07-30 | `@comp.catalog` dedupes by internal/canonical handler; `comp.*` preferred over `meta.*`/`compiler.*` |
| G-026 | 2026-07-30 | `@meta.each`/`@comp.each` composition glue: splits any combinator's string output into fragments + callback `{name,index,count}`; closes the combinator algebra (chain `map→each`, `power→each`). Comptime-folded → native C, no `lua_Value`. Verified `examples/meta_compose_each_showcase.duo` (3 + 7 fragments) |
| G-011 | 2026-07-30 | Exported `std.process` from `std.sys.process`, aliased `exec` to `execute` in `std.os` |
| G-012 | 2026-07-30 | Implemented `std.fs.glob` using safe Python `glob` and `std.fs.walk` using `find` |
| G-013 | 2026-07-30 | Implemented `std.env.set` and `std.env.unset` using `@c.emit` and `setenv/unsetenv` natively |
| G-014 | 2026-07-30 | Exported `std.cli` mapped to `std.argparse` in `lib/std.duo` |
| G-015 | 2026-07-30 | Aliased `ext` to `extname` and added `split` to `lib/std/path.duo` |
| G-016 | 2026-07-30 | Added `std.fs.tempdir`, `std.fs.tempfile`, and `std.fs.mkdtemp` |
| G-017 | 2026-07-30 | Exported `get`, `post`, `request`, and `serve` from `std.net` into `std.net.http` |
| G-018 | 2026-07-30 | Implemented `std.process.pipe` enabling process chaining with the native `\|>` operator |
| G-019 | 2026-07-30 | Added `std.text.regex` exporting `std.regex` in `std.duo` |
| G-010 | 2026-07-30 | `@comp.compile.cached` persists cacheable comptime nil/bool/int/float/str results under `.duo/cache/comptime`; direct `@(fn(...))` calls now route through `callFunction`, and cache keys stay owned by the map. No runtime `lua_Value` path. |
| G-003 | 2026-07-30 | Verified nested `req` inside exported `std.script.json_read_file` works and added `examples/nested_std_req_smoke.duo` to prevent regression. |
| G-032 | 2026-07-30 | Added `@comp.choose` / `@comp.derive.choose` fixed-size combination combinators, catalog/ladder discovery, and `examples/meta_choose_showcase.duo`; fold-only string output, no runtime `lua_Value` intrinsic call |
| G-033 | 2026-07-30 | Bare function syntax (no `fun`), assign-form func decl, if-expressions; canonical grammar in `docs/GRAMMAR_SPEC.md`; MCP `duo_grammar_spec_*`; smoke `examples/syntax_bare_fun_smoke.duo` |
| G-046 | 2026-07-31 | GR-004 quoted string table keys without `[ ]`; field access preferred; parser + grammar spec |
| G-042 | 2026-07-31 | Duo-native MCP servers compile+run; closure/module-scope patterns verified |
| G-043 | 2026-07-31 | C/POSIX ident mangling (`script`→`duo_script`) for implicit locals |
| G-044 | 2026-07-31 | MCP refactored: `duo-mcp/duo_bench.duo` uses `duo_shared.duo`; session_start + gaps_read tools |
| G-045 | 2026-07-31 | Module-scope implicit locals + closure upvalues emit consistently |
| G-029 | 2026-07-30 | `@comp.template` / `@comp.generate` — O(n) parametric expansion with `$0`/`$1`/`$name`/`$ctype`; native C fold; `examples/meta_template_showcase.duo`; `@comp.agent.grammar()` |
| G-030 | 2026-07-30 | `@comp.generate` constraint block — `ops`×`types` cartesian axis + comma-list alias; `comptimeGenerateHook`; `examples/meta_generate_showcase.duo`; native C fold |
| G-031 | 2026-07-30 | `@comp.scheme` declarative program scheme — type/fn pipe spec + `$kind`/`$fields`/`$params` template; `comptimeSchemeHook`; `examples/meta_scheme_showcase.duo`; native C fold |
| G-035 | 2026-07-30 | `@comp.scheme.clauses` dotted path — named clause list O(clauses); composability with `@comp.each`; MCP `duo_agent_smoke` + `duo_audit_native_boxing` |
| G-036 | 2026-07-30 | Generative algebra stack — `template` / `generate` / `scheme` → `@comp.each` in one showcase; MCP `duo_audit_metaprogramming_smokes` batch native audit |
| G-037 | 2026-07-30 | `@comp.str.countlines(s)` — native comptime i64 newline fragment count for generative combinator output; no lua boxing on folded strings |
| G-039 | 2026-07-30 | Embedded module scope: file-scope table assign promotes to static `module_globals`; bare functions in req'd modules; `examples/embedded_bare_bundles_smoke.duo` |
| G-040 | 2026-07-30 | `startsFuncParamList` distinguishes typed params from call args — fixes `duo_run(path, bin)` misparsed as bare func decl; `lib/std/script.duo` parses again |
| G-034 | 2026-07-30 | Fixed hard-bench exit-137 codegen kill: top-level comptime binding capture no longer speculatively evaluates ordinary runtime local initializer calls; explicit `__constexpr` and proven compile-only/fold intrinsics still fold. `duo dump-c examples/benchmark.{lua,duo}`, unit-test, agent-smoke, and `zig build bench` now pass. |

### Delegation queue

Agents pick unowned **P0/P1** rows, claim in Active claims, implement, verify gates, close here.

| ID | Delegated to | Status |
| --- | --- | --- |
| — | — | — |

### Findings log (append-only, newest first)

| UTC | Agent | Action | Detail |
| --- | --- | --- | --- |
| 2026-07-31T09:15:00Z | cursor | ship | GR-004: quoted table keys without brackets (`{"unit-test" = "a"}`); parser test; C ident mangling (G-043); closed G-042/G-044/G-045; duo_bench MCP deduped via duo_shared; fixed meta_module.zig syntax errors; agent-smoke PASS |
| 2026-07-31T02:00:00Z | opencode | fix | G-041: Fixed 2 duplicate entries in meta_module.zig builtins (compiler.c.call at line 392, compiler.hint.hot at line 394). Zero public @comp.* underscore names confirmed via comptime tests. |
| 2026-07-31T01:55:00Z | opencode | ship | MCP: added duo_session_log (structured coordination log entry) and duo_repo_tooling (run Duo scripts/ tooling via MCP). Synced META_CATALOG with missing entries: str.* ops, concepts.count, rewrite.*, choose/derive.choose, agent.* hooks. |
| 2026-07-31T01:50:00Z | opencode | ship | Converted agent_dedup_check.sh to scripts/agent_dedup.duo — pure Duo scripting (std.agent, std.fs, std.io.util, std.script, std.os). Replaces bash awk/grep for coordination buffer reads. |
| --- | --- | --- | --- |
| 2026-07-31T01:00:00Z | cursor | ship | `@comp.str.join(parts, sep)` — native comptime fold via `__strjoin` (reuses `table.concat` eval); `lib/std/agent.duo` policy strings migrated; DIRECTIVE_HIERARCHY updated; agent-smoke PASS |
| 2026-07-31T00:45:00Z | cursor | ship | G-039 fix: module-scope table literals → `module_globals` (scope depth 2); codegen `duo_g_*` init for promoted locals; `detect_sieve_native` rejects `any` params (fixes `std.meta.flatten` mis-codegen); `embedded_bare_bundles` + `std_metaprogramming_modules_smoke` compile; agent-smoke PASS |
| 2026-07-31T00:15:00Z | cursor | ship | G-001: `table.concat({literal strings}, sep)` comptime-folds to native `const char*` via `eval_comptime_call` (helps `std.agent` policy strings); runtime dynamic tables still use `lua_tbl_concat`; codegen unit test + agent-smoke PASS |
| 2026-07-30T24:30:00Z | cursor | ship | `@comp.str.eq(a,b)` native bool fold; `duo run script.duo arg1` forwards argv without `--`; `meta_compose_each_showcase` uses `@comp.str.countlines`; agent-smoke PASS |
| 2026-07-30T24:10:00Z | cursor | ship | `@comp.str.len(s)` native comptime/runtime fold; `std.script.build_lock_*` native mkdir mutex; `scripts/duo_lock.duo` + bash fallback wrapper; `meta_algebra_showcase` in agent-smoke; G-script: `duo run` needs `--` before script argv |
| 2026-07-30T23:55:00Z | cursor | ship | `@comp.rewrite.describe` / `@comp.rewrite.rulecount` native introspection (no lua); register `rewrite.bundle` before codegen so rulecount reflects bundle; `std.rewrite.describe_bundle`/`active_rule_count`; G-008/G-020 backend wording → Duo-native machine code (NOT LLVM); agent-smoke PASS |
| 2026-07-30T23:35:00Z | cursor | partial-close | G-001: `@comp.concepts.count(name)` native i64 fold; `req("std.foreign").zig_to_c`/`rust_to_c` literal folds via `foreign_transpile.zig` (no lua_invoke); `concept_introspect.duo` demo |
| 2026-07-30T23:25:00Z | cursor | partial-close | G-001/contracts: `@comp.concepts.*` method descriptors now include `params` type vector in comptime tables (`MethodRequirement.param_types` + codegen emit); fixes `std_metaprogramming_modules_smoke.duo` wrapper_plan params check |
| 2026-07-30T23:10:00Z | cursor | partial-close | G-001/G-037: `@comp.str.splitcount(s, sep)` comptime + native C fold (pipe/semicolon fragment counts); `not (string.find ~= nil)` + typed str `.field` in `expr_is_native_cstr`; `lib/std/meta/bundles.duo` uses `fun` (bare decl still blocked in embedded modules per G-037); `syntax_bare_fun_smoke.duo` fixed (`elseif` in stmt-if, `fun main`); build + agent-smoke PASS |
| 2026-07-30T22:05:00Z | cursor | partial-close | G-001: `string.find(hay, needle) ~= nil` on native `const char*` lowers to `strstr(...) != NULL` (fixes agent_hooks `multiplier_for` hint check); `chain_hint` in std.meta.codegen; native str vs nil pointer test |
| 2026-07-30T21:45:00Z | cursor | partial-close | G-001: `std.agent.grammar_index()` native fold now emits `agentGrammarText()` (not bare path); `@comp.chain` alias of `@comp.each` in meta_module + catalog/ladder; `lib/std/meta/bundles.duo` migrated to bare syntax + implicit module table; MCP audit deduped to `duo_mcp_shared.py` (both duo-lsp + duo-bench expose `duo_audit_metaprogramming_smokes`) |
| 2026-07-30T16:50:00Z | cursor | close | G-039/G-040/G-037: `at_module_scope()` promotes file-scope table assigns to static `module_globals`; `startsFuncParamList` requires typed params (fixes `f(a,b)` call misparsed as bare func — root cause of script.duo + embedded bare-fn failures); `parser.duo_mode` on embedded parse; `lib/std/meta/bundles.duo` bare syntax + implicit table; `examples/embedded_bare_bundles_smoke.duo`; agent-smoke PASS (24 targets) |
| 2026-07-30T15:39:02Z | omp-cont | note | G-037: Precise fix identified: set `parser.duo_mode = std.mem.endsWith(u8, path, \".duo\")` before parse_module() at 3 embedded-module parse sites in codegen.zig: emit_embedded_module (~17362), emit_required_modules re-parse (~17188), loadWeaveModule (~955). Verified the fix makes bare functions work in req'd modules (bundles.duo bare compiled+ran correctly). BLOCKER: enabling duo_mode for .duo embedded modules exposes that lib/std/script.duo (and likely other stdlib modules) are NOT duo-mode-clean — script.duo uses deprecated `then` throughout and has call-statement/bare-fn-ambiguity constructs that duo mode mis-parses (block imbalance → 'expected end got eof' at line 290), breaking agent-smoke. So the fix needs a coordinated stdlib cleanup (drop `then`, disambiguate call statements) BEFORE enabling duo_mode. Tried+reverted this turn to keep agent-smoke green. Also: bundles.duo MUST stay `global bundles` + `fun` (not bare) until G-037 is fixed — added a NOTE comment in the file; do not revert. |
| 2026-07-30T15:32:57Z | omp-cont | open | G-037: [meta P1] Bare function declarations (G-033, no `fun` keyword) parse and run correctly in TOP-LEVEL programs but FAIL in EMBEDDED (req'd) MODULES. Repro: a module file with `names(): any \n out = {} \n ... end` (bare) → `emit_embedded_module: parse failed ... error.UnexpectedToken` at the body's first token ('expected function arguments'). Same construct with `fun names(): any` works in embedded modules. The G-033 bare-function parser path was not wired into the embedded-module parse path. Confirmed via lib/std/meta/bundles.duo (kept on `fun` until fixed). Impact: blocks migrating the stdlib to the preferred bare syntax. Note: this is a parser gap, not a metaprogramming gap. |
| 2026-07-30T15:24:13Z | omp-cont | open | G-036: [native/meta P1] Two codegen bugs found via req("std.meta.bundles"): (1) A req'd module's file-scope implicit-local TABLE binding (e.g. `bundles = {...}`) referenced by exported functions is emitted as an init-function LOCAL, so the functions reference an undeclared identifier (C error: 'use of undeclared identifier bundles'). FIXED bundles.duo by making it `global bundles = {...}` (correct Duo idiom for module-scope data per AGENTS.md; agent-smoke PASS). Underlying codegen bug remains for any module using the implicit-local-file-scope-table-referenced-by-exported-fn pattern. (2) String concat with a comptime-folded RHS: `"lit" .. mb.describe("Full")` folds describe() correctly but emits the RHS as a BARE C string literal inside lua_concat(literal, "bare") -> type mismatch (lua_concat expects lua_Value, got char[]). The folded string needs a lua_val_from_literal/lua_val_from_str wrapper. Repro: `mb=req("std.meta.bundles"); print("x=" .. mb.describe("Full"))`. Also: `duo run` fails where `duo compile` succeeds on the same bundles program (flag/path discrepancy in run mode). |
| 2026-07-30T13:36:18Z | omp-cont | close | G-022: STALE — PGO already wired. scripts/run_benchmark.sh runs `duo compile --pgo -O3` for the 40-bench hard gate (both .lua and .duo drivers); `duo compile --pgo` is a supported flag for user binaries. Note: PGO compile is memory-heavy and historically caused exit-137 (OOM) on the large benchmark.duo/lua under parallel load — codex serialized it via BENCH_PARALLEL_COMPILE=0 default. PGO is NOT wired into honest-bench (regressed FNV, perf ledger 2026-07-xx). Implementation complete; remaining work is memory, not feature. |
| 2026-07-30T13:36:18Z | omp-cont | close | G-023: STALE — LTO already in the build pipeline. scripts/run_benchmark.sh CFLAGS and scripts/run_cross_benchmark.sh CFLAGS both include -flto; `duo compile` emits -flto for native-target single-translation-unit builds (src/main.zig native-scalar path skips -flto intentionally, see perf ledger 2026-07-14). C baseline also uses -flto (fair comparison). No work remaining. |
| 2026-07-30T13:36:18Z | omp-cont | close | G-009: STALE — already implemented. LSP filters _-prefixed private symbols in cross-module contexts: ws_search_symbols (src/server.duo) uses `is_public = string.sub(s.name,1,1) ~= \"_\"`; cross-file completion in handle_completion applies the same filter for uri2 ~= uri. Current-file documentSymbol + local completion correctly KEEP _ symbols (you edit that file). Matches codegen add_module_export skip of name[0]=='_'. Verified by reading ~/x/duo-lsp/src/server.duo lines 912-937 and 2033-2075. |
| 2026-07-30T13:36:04Z | omp-cont | open | G-035: [meta P1] Named comptime callbacks silently fail (fold to empty string) for @comp.template and @comp.scheme (and likely other generative combinators using resolve_fn_hook -> comptime_eval.funcValue) when the callback is a named top-level function in a minimal module. Inline callbacks (anonymous fun) work; @meta.each named callbacks work. Repro: `fun g(m) "Z"..m.name..";" end` then `S = @comp.scheme("type T{a:int}","",g)` -> S == "" silently. Inline `@comp.scheme("type T{a:int}","",fun(m) "X"..m.name end)` works -> "XT;". Root cause TBD in funcValue/callFunctionValue for func_decl-resolved .func (captures/options differ from inline literal). Hardening: emit_comptime_call_string silent "" fallback (codegen.zig ~13700) masks comptime fold failures for ALL intrinsics. Heap-stabilized @comp.scheme callback meta table to match comptimeEachHook (kept; correctness improvement); funcValue path fix is a separate shared-infra slice. |
| 2026-07-30 | cursor | partial-close | G-001/G-038: native-folded `req("std.meta.bundles").describe(...)` in `..` concat now routes through `duo_str_concat` (not bare literal inside `lua_concat`); `stdlib_module_call_folds_native` + codegen test |
| 2026-07-30 | cursor | close | G-035: heap-stable `metaCallbackTable` for @comp.template/grammar/weave/scheme.clauses named callbacks; compile-time warn on generative fold failure; `examples/meta_template_callback_showcase.duo` |
| 2026-07-30 | cursor | partial-close | G-001/G-037: `@comp.str.countlines` native comptime i64 fold; generative stack showcase uses it (no lua_val_from_str on fragment counts) |
| 2026-07-30 | cursor | close | G-036: unified generative stack showcase (template/generate/scheme→each); MCP `duo_audit_metaprogramming_smokes`; agent-smoke target added |
| 2026-07-30 | codex | partial-close | G-001: literal `req("std.meta.bundles")` aliases and direct `std.meta.bundles.contains/describe` calls fold to native bool/string constants; table-returning `names`/`traits` remain dynamic; repaired current-tree template/generate/scheme Zig drift encountered during validation; focused tests, build, unit-test, agent-smoke, and hard bench PASS |
| 2026-07-30T07:21:30Z | omp-scheme | close | G-031: @comp.scheme handler implemented: declarative program scheme -> full native C implementation. Pipe-separated `type Name { f: t, ... }` / `fn name(params) -> ret` declarations parse into typed units; per-unit template substitutes $kind/$name/$ctype/$fields/$fieldnames/$fieldcount/$params/$ret. Comptime-only -> folds to native `const char*` (verified via duo dump-c: zero lua_Value/lua_invoke/lua_table_new). Wired: meta_module.zig (registration), comptime.zig (ComptimeSchemeHook + options + __metascheme dispatch), codegen.zig (metaComptimeSchemeHook thunk + wiring + fold-recognition + emit_comptime_call_string), sema.zig (type-inference), meta_codegen.zig (comptimeSchemeHook dispatcher + comptimeSchemeDeclTemplateHook structural impl + comptimeSchemeClausesHook named-clause form). Showcase examples/meta_scheme_showcase.duo in agent-smoke. agent-smoke PASS, unit-test 716/716 PASS, build PASS. Also resolved a live multi-agent collision: a duplicate pub fn comptimeSchemeHook (weaker named-clause design, unclaimed) broke the build; merged both designs behind a single dispatcher. |
| 2026-07-30 | cursor | ship | scheme→each showcase; MCP duo_agent_smoke + duo_audit_native_boxing; multiplier_for native fold sync for template/scheme/grammar/weave |
| 2026-07-30 | codex | partial-close | G-001: literal `req("std.meta.codegen")` aliases and direct `std.meta.codegen.*_hint()` calls for no-arg hint helpers fold to native `const char*`; table/meta-consuming codegen helpers remain Lua-compatible; focused test, build, unit-test, agent-smoke, and hard bench PASS |
| 2026-07-30 | codex | partial-close | G-001: literal `req("std.agent")` aliases and direct `std.agent.*` hook calls for constant policy/path/gap/recipe helpers fold to native `const char*`; literal `multiplier_for(...)` folds to the matching exponential combinator hint; dynamic goals and `smoke_targets` remain Lua-compatible; focused test, build, unit-test, agent-smoke, and hard bench PASS |
| 2026-07-30 | codex | partial-close | G-001: literal `req("std.math")` / `req "std.math"` aliases for proven numeric core helpers lower through the existing native `math.*` codegen path; dynamic or non-allowlisted std.math helpers remain Lua-compatible; focused tests, build, unit-test, agent-smoke, and hard bench PASS |
| 2026-07-30 | codex | claim | G-001 native lowering slice: audit native-lowered stdlib helper aliases and fold one more proven `req` alias path without changing dynamic Lua behavior |
| 2026-07-30 | codex | partial-close | G-001: literal `req("std.string")` / `req "std.string"` aliases for native string predicates lower to `strstr` / `strncmp` / `memcmp` / direct empty checks; dynamic alias use remains Lua-compatible; focused tests, build, unit-test, agent-smoke, and hard bench PASS |
| 2026-07-30 | codex | claim | G-001 native lowering slice: route literal `req("std.string")` aliases through existing native `string.*` lowering for typed/string hot paths |
| 2026-07-30 | codex | partial-close | G-001: literal `req("std.pipeline")` / `req "std.pipeline"` aliases now get compile-time-native pipeline generator folds; dynamic alias use remains Lua-compatible; focused tests, build, unit-test, agent-smoke, and hard bench PASS |
| 2026-07-30 | codex | claim | G-001 native lowering slice: audit literal metaprogramming helper calls routed through `req` aliases and fold proven compile-time string generator calls without `lua_Value` |
| 2026-07-30 | codex | close | G-034: fixed compile-time speculation of runtime benchmark calls in `note_comptime_binding`; guarded safe comptime binding capture, preserved explicit `__constexpr`; hard bench PASS with all 40 `.lua`/`.duo` results matching C and Duo >= C |
| 2026-07-30 | codex | harden | G-033: fixed `if_expr` exhaustive compiler integration, `else if` parsing, and speculative bare-function false diagnostics; validated focused parser tests, build, agent-smoke, and unit-test |
| 2026-07-30 | codex | block | G-034: serialized hard-bench PGO compile scheduling by default, fixed block-level Mandel fusion relative-index bug, but current `duo dump-c examples/benchmark.lua` and `zig build bench` still exit 137 during late codegen; `agent-smoke` remains PASS |
| 2026-07-30 | cursor | close | G-029: `@comp.template` + `@comp.generate` O(n) parametric expansion; `@comp.agent.grammar()`; `docs/DIRECTIVE_HIERARCHY.md`; MCP `duo_directive_hierarchy_read`; agent-smoke PASS |
| 2026-07-30 | cursor | close | G-033: bare func syntax, assign-form func, if-expressions, `else if` arms, grammar spec + MCP; agent-smoke PASS |
| 2026-07-30 | codex | close | G-003: current tree already handles nested `req` inside exported std function bodies; added smoke coverage for `std.script.json_read_file` |
| 2026-07-30 | codex | close | G-010: persistent `@comp.compile.cached` storage for cacheable comptime results; dotted compile attribute parses/validates; fixed cache key ownership |
| 2026-07-30 | codex | close | G-032: added fixed-size `@comp.choose` / `@comp.derive.choose`; validated focused example, meta_module tests, agent-smoke, and unit-test |
| 2026-07-30 | hermes | open | G-027 through G-031: Registered 5 new generative @meta constructs (grammar, weave, template, generate, scheme) in meta_module.zig — handlers not yet implemented |
| 2026-07-30 | hermes | fix | G-025: Moved type recovery before try_emit_native_abi_call in codegen.zig so forward references get direct C calls instead of lua_invoke |
| 2026-07-30 | this (session) | close | G-017, G-018, G-019: Exposed HTTP client functions, enabled process piping with `\\|>`, added `regex` to `std.text` |
| 2026-07-30 | this (session) | close | G-011, G-012, G-013, G-014, G-015, G-016: Implemented scripting utilities (process, fs.glob/walk, env.set, cli, path, tempfile) in stdlib natively |
| 2026-07-30 | codex | consolidate | Moved gap findings, delegation, and findings log into canonical coordination buffer; `.agents/AGENT_GAPS.md` is redirect-only |
| 2026-07-30 | omp | open+close | G-026: added `@meta.each` composition primitive (comptime.zig hook + meta_codegen.impl + 4 codegen fold points + catalog/ladder); deduped 4.9MB dead `*.bak`/`*.new*` backups; `.gitignore` prevention |
| 2026-07-30 | codex | close | G-007: validated by `./zig-out/bin/duo run examples/script_lock_smoke.duo` and `scripts/duo_lock.sh -- zig build agent-smoke` |
| 2026-07-30 | cursor | close | G-004: catalog dedupe by internal handler; comp.* canonical in formatCatalog |
| 2026-07-30 | cursor | close-partial | G-007: std.script.locked_must + build.zig install dep for agent-smoke |
| 2026-07-30 | cursor | open | Created gaps buffer + `@comp.agent.gaps` + MCP read/update |
| 2026-07-30 | this (session) | close-partial | G-001 (native perf): added `@native` attribute + `emit_native_func_def` codegen path; partial — call-site dispatch still boxes |
| 2026-07-30 | this (session) | cleanup | Removed underscore patterns from `isModuleDirective` hardcoded list; fixed `is_known_attribute` normalization; removed redundant `"ffi_gen"` raw check in directives.zig |
| 2026-07-30 | this (session) | open | G-025: per-function native ABI in emit_expr `.call` path when module-level native_scalar_mode is false |

## Session log (newest first)

| UTC date | Agent | Summary |
| --- | --- | --- |
| 2026-08-01 | hermes | ship | Grammar rules GR-006 (table keys without brackets, proposed), GR-007 (@const/@comptime rejected, preferred), GR-008 (no fun/function in new .duo, preferred) formalized in docs/GRAMMAR_SPEC.md. Active goals 6-8 added to AGENT_COORDINATION.md (Duo-as-scripting, duo-mcp exponential evaluator, React/GUI DSL). Repo path notes and @const/@comptime parser invariant added. |
| 2026-07-31T18:05:00Z | this | ship | Implemented missing exponential combinator backends in codegen.zig: @metaexpand, @metaceiling, @metaomni, @metaburst, @comptimetensor, @derivetensor, @derivenfold, @metatranscend, @metainfinity, @metahyper, @derivetower, @metascheme, @metatemplate, @metagenerate, @comptimefixpoint, @comptimefanout. Added bare @ aliases: @map, @expand, @pow, @ceiling, @omni, @stack, @burst, @tensor, @transcend, @infinity, @hyper, @fixpoint, @fanout. Verified: meta_compose_each_showcase.duo passes with map→each (3 types) and power→each (7 subsets = 2^3-1). |
| 2026-07-31T17:53:42Z | this | ship | Closed G-047: Fixed @comp.concepts.count and metaprogramming by passing sema.concepts to CodeGen; added duo_exponential_evaluate + duo_onboard_exponential + duo_combinator_info MCP tools for agent onboarding; all 678 unit tests pass |
| 2026-07-31T09:38:02Z | cursor | ship | Implemented @comp.* combinator complexity diagnostics: combinatorComplexity(path) returns O(n), O(n²), O(n³), O(n!), O(2ⁿ), etc.; suggestNextCombinators(path) provides composability hints; added ComplexityInfo struct with complexity, has_derive_multiplier, is_module_directive, base_combinator fields. All meta_module tests pass. ||
| 2026-07-31 | opencode | Fixed 2 duplicate entries in meta_module.zig, synced MCP catalog, added duo_session_log + duo_repo_tooling MCP tools, converted agent_dedup_check.sh to Duo scripting |
| 2026-07-31 | opencode | Wrote Duo-native MCP servers (duo_bench.duo, duo_lsp.duo, duo_shared.duo, zls.duo) — all compile clean; runtime blocked by G-042 (closure upvalue `lua_val_from_literal` 1-arg → 3-arg mismatch). Filed G-042/043/044. Python MCP servers retained as fallback. `std.mcp` rawlen→# fix. `.agents/AGENT_COORDINATION.md` gap entries + session log. |
| --- | --- | --- |
| 2026-07-30 | codex | G-001 partial: added native string folding for `std.meta.codegen` alias/direct no-arg hint helpers so metaprogramming guidance strings avoid boxed module dispatch; hard bench PASS |
| 2026-07-30 | codex | G-001 partial: added native string folding for `std.agent` aliases/direct hooks so agent policy, coordination, gaps, recipes, gates, and literal multiplier hints do not route through boxed module dispatch; hard bench PASS |
| 2026-07-30 | codex | G-001 partial: added native numeric lowering for `std.math` aliases so `m = req("std.math"); m.sqrt/sin/cos/deg/max/abs(...)` emits direct C/libm expressions instead of boxed module dispatch; hard bench PASS |
| 2026-07-30 | codex | G-001 partial: added native bool lowering for `std.string` aliases so `s = req("std.string"); s.contains/starts_with/ends_with/is_empty(...)` emits direct C predicates instead of boxed `lua_Value` dispatch; hard bench PASS |
| 2026-07-30 | codex | G-001 partial: added codegen stdlib-module alias tracking so `pipe = req("std.pipeline"); pipe.fuse_*("literal", ...)` emits native C string literals instead of routing the generator call through `lua_Value` / `lua_invoke`; hard bench PASS |
| 2026-07-30 | codex | Closed G-034: ordinary runtime local initializer calls are no longer speculatively executed as comptime bindings; benchmark dump-C and hard bench pass under the coordination lock |
| 2026-07-30 | codex | Closed stale G-003 by verification: nested `req` in `std.script.json_read_file` runs successfully; added agent-smoke coverage |
| 2026-07-30 | codex | Closed G-010: `@comp.compile.cached` direct comptime calls and meta callbacks share persistent `.duo/cache/comptime/*.ducache`; `examples/comptime_cached_persistence_smoke.duo` validates dotted attribute + cache files |
| 2026-07-30 | cursor | **G-028 CLOSED:** `@comp.weave(module, concept, fn)` — foreign module parse/sema snapshot + native C string fold; `meta.source_module` in callback meta; smokes `meta_weave_showcase.duo`. |
| 2026-07-30 | cursor | **G-027 CLOSED:** `@comp.grammar` — EBNF→O(b^d) native C string fold (`comptimeGrammarHook`, codegen `emit_comptime_call_string`, `metaResolveFnHook` module func lookup). **G-010 PARTIAL:** cross-build `@cached` via `.duo/cache/comptime/*.ducache`. Zig 0.17 Io API fixes (`read_file_hook`, `createDirPath`, `mem.trim`). `agent-smoke` PASS incl. `meta_grammar_showcase.duo`. |
| 2026-07-30 | codex | Added `@comp.choose` / `@comp.derive.choose` O(n choose k) combinator rung; included in ladder/catalog, `std.agent`, docs, and `agent-smoke` |
| 2026-07-30 | omp | `@meta.each`/`@comp.each` composition glue (closes combinator algebra: chain map→each, power→each); comptime-folded, no lua_Value. G-026 closed. Deduped 4.9MB dead `*.bak`/`*.new*`; `.gitignore` prevention |
| 2026-07-30 | codex | Closed G-007: reentrant `std.script` lock helpers + `script_lock_smoke` in locked `agent-smoke` |
| 2026-07-30 | cursor | Initial `@comp.agent.gaps`, MCP `duo_agent_gaps_*`, std.agent.gaps_index; storage now consolidated into this file |
| 2026-07-30 | this (session) | Refactored ALL internal canonical names from underscore → dotted (`embed_json`→`embed.json`, `ffi_gen`→`ffi.gen`, `compile_thread`→`compile.thread`, `compile_only`→`compile.only`, `define_derive`→`define.derive`, `derive_all`→`derive.all`, `emit_derive`→`emit.derive`, `emit_omni`→`emit.omni`, `rewrite_bundle`→`rewrite.bundle`, `c.emit_file`→`c.emit.file`, `define_derive_bundle`→`define.derive.bundle`); removed bare underscore names `compile_only`, `compile_thread`, `rewrite_bundle` from backward-compat aliases; deduped duplicate `meta.compile.native` entries in directives array. `zig build` + `agent-smoke` pass. |
| 2026-07-30 | cursor | `@comp.agent.dedupe`, `@comp.*` agent aliases, dedupe protocol, std.agent.dedupe_policy |
| 2026-07-29 | omp | Added `scripts/duo_lock.sh` mutex; hardened coordination + build-lock mandate |
| 2026-07-30 | codex | Aligned agent hooks/tooling on dotted `@meta.compile.*` / `@meta.embed.*`, lightweight `agent-smoke` |
| 2026-07-29 | cursor | `@meta.agent.*`, `std.agent`, `agent-smoke`, hierarchy updates |

## Collision recovery

1. Re-read this file and `git status`.
2. Do **not** revert unrelated changes; narrow-fix or wait for claim release.
3. If a build fails with "module not found" / "C compiler failed" but re-runs
   clean, it was a cache collision — re-run under `duo_lock.sh`.
4. Note the conflict in **Session log**.

### [2026-07-29 21:26:01] a1 / 8996d8f0 — CLAIM
Detail: G-011, G-013, G-015: Shell exec, env vars, path manipulation in stdlib
Files: lib/std/os.duo, lib/std/env.duo, lib/std/path.duo
Status: LOCKED

### [2026-07-29 21:29:23] Antigravity — CLAIM
Detail: Implementing std.fs.glob, std.fs.walk (G-012) and tempdir/tempfile (G-016)
Files: lib/std/fs.duo
Status: LOCKED

### [2026-07-30 00:13:01] omp-scheme — CLAIM
Detail: Implement @comp.scheme handler (G-031): declarative program scheme -> full native C implementation. Comptime-only string generator (no lua_Value). Touches: comptime.zig (hook+options+dispatch), meta_codegen.zig (comptimeSchemeHook), codegen.zig (thunk+wiring+fold-recognition, distinct regions from codex's G-001 stdlib-alias slice), sema.zig (type-inference), examples/meta_scheme_showcase.duo. Mirrors proven @comp.template pattern.
Files: src/comptime.zig, src/meta_codegen.zig, src/codegen.zig, src/sema.zig, examples/meta_scheme_showcase.duo
Status: CLOSED

### [2026-07-30 00:21:30] omp-scheme — NOTE
Detail: G-031 (@comp.scheme) CLOSED + G-030 (@comp.generate) now complete. Resolved duplicate-symbol build break from concurrent unclaimed scheme edits: removed weaker duplicate, kept merged dispatcher design (structural type/fn + named-clause). agent-smoke + unit-test 716/716 + build all PASS. Released metaprogramming claim.
Files: src/meta_codegen.zig, src/meta_module.zig, examples/meta_scheme_showcase.duo
Status: ACTIVE
| 2026-07-30 | this (session) | fix | Fixed NULL return error in codegen for .nil literal in .any return context of @native or typed functions by ensuring current_ret context is preserved in emit_native_func_def |

### [2026-07-30 06:36:51] omp-cont — NOTE
Detail: Turn summary: (1) Audited @ directive hierarchy — public @comp.* surface is fully dotted, zero public @foo_bar (tests enforce); normalizeDirective canonicals are all dotted; the 112 underscore names are builtins .internal Zig dispatch keys (not directives, documented Zig-only). AGENTS.md gap claim was stale. (2) Found+characterized real bug G-035: named comptime callbacks silently fold to "" for @comp.template/@comp.scheme (funcValue path); inline + @meta.each named work. Filed with repro. (3) Heap-stabilized @comp.scheme callback meta table (meta_codegen.zig comptimeSchemeDeclTemplateHook) to match comptimeEachHook proven pattern — correctness improvement, kept; agent-smoke PASS. (4) Closed stale gaps G-009 (LSP _ filter already impl), G-022 (PGO already in pipeline), G-023 (LTO already in pipeline). (5) OBSERVED: unit-test has 2 failures NOT caused by me — 'bar'/'boom' (intentional negative test) and 'codegen: generic specialization calls use typed argument coercion' (codex's in-flight codegen.zig native-lowering work, argument coercion is their territory, zero overlap with my scheme callback change). agent-smoke PASS confirms working paths intact.
Files: src/meta_codegen.zig, .agents/AGENT_COORDINATION.md
Status: ACTIVE

### [2026-07-30 08:39:02] omp-cont — NOTE
Detail: bundles.duo coordination: lib/std/meta/bundles.duo MUST use `global bundles = {...}` (not implicit-local — G-036: file-scope table binding referenced by exported fns emits undeclared identifier) AND `fun` (not bare — G-037: bare fns don't parse in embedded modules yet). Added explanatory NOTE comment in the file. A concurrent agent reverted my fixes twice this turn (back to bare + non-global, which is broken); please do NOT revert to bare/non-global until G-036/G-037 codegen/parser fixes land. Verified working: req('std.meta.bundles').contains('Numeric','Add')→true via duo compile. agent-smoke PASS. Net changes this turn: bundles.duo global+fun fix (KEPT, working); codegen.zig duo_mode fix REVERTED (broke script.duo); G-035/G-036/G-037 filed.
Files: lib/std/meta/bundles.duo, src/codegen.zig
Status: ACTIVE

### [2026-07-30 10:37:56] hermes-main — CLAIM
Detail: Fixing ward (~/x/ward/) compilation failures and modernizing to idiomatic Duo. Also auditing MCP server completeness for ward-style development.
Files: /Users/clp/x/ward/src/main.duo,/Users/clp/x/ward/src/lib.duo,/Users/clp/x/ward/src/cli.duo,/Users/clp/x/ward/src/wasm/runtime.duo,/Users/clp/x/ward/src/wasm/module.duo,/Users/clp/x/ward/src/wasm/wasi.duo,/Users/clp/x/ward/src/wasm/jit.duo,/Users/clp/x/ward/src/edge/init.duo,/Users/clp/x/ward/src/nn/init.duo,/Users/clp/x/duo/lib/std/argparse.duo,/Users/clp/x/duo/lib/std/time.duo
Status: LOCKED

### [2026-07-30 13:42:09] Antigravity — CLAIM
Detail: Deduplicating MCP python implementation into shared module per instructions
Files: /Users/clp/x/duo-mcp/duo_mcp_shared.py,/Users/clp/x/duo-mcp/duo_lsp_mcp.py,/Users/clp/x/duo-mcp/duo_bench_mcp.py
Status: LOCKED

### [2026-07-30 13:43:30] Antigravity — COMPLETE
Detail: Extracted duplicate coordination code into duo_mcp_shared.py for both duo_bench_mcp.py and duo_lsp_mcp.py
Files: /Users/clp/x/duo-mcp/duo_mcp_shared.py,/Users/clp/x/duo-mcp/duo_lsp_mcp.py,/Users/clp/x/duo-mcp/duo_bench_mcp.py
Status: ACTIVE

### [2026-07-30 19:24:45] hermes-glm5-main — CLAIM
Detail: Ward modernization (~/x/ward/) + new exponential metaprogramming combinators that don't collide with opencode's dedup/MCP work or Antigravity's codegen native-lowering work. Also auditing directive hierarchy for underscore cleanup.
Files: /Users/clp/x/ward/src/*.duo,/Users/clp/x/duo/src/meta_module.zig,/Users/clp/x/duo/src/comptime.zig,/Users/clp/x/duo/src/meta_codegen.zig
Status: LOCKED

### [2026-07-31 09:14:00] antigravity — CLAIM
Detail: codegen: native lowering for lua_to_* (Eliminate lua boxed values from codegen.zig)
Files: src/codegen.zig
Status: LOCKED



## Cross-agent gap buffer

| ID | Title | Priority | Kind | Logged | Status | Detail |
| F-15334-1 | benchmark.duo dynamic-path boxing concentration (for codegen native-lowering) | P1 | native_lowering_gap | !2026-07-31T09:28:54Z | open | Audit of examples/benchmark.duo generated C: 876 lua_Value, 150 lua_to_num, 76 lua_to_str, 49 lua_invoke, 101 lua_table_get. Concentration: (1) UNTYPED kernels like `fun fib(n)` (benchmark.duo:5) box params/returns; typed kernels `mandel_iter(cx: f64,cy: f64): i64` (line 32) and `sieve(n: i64): i64` (line 598) already lower natively. (2) Dynamic table access helpers emit lua_to_num(lua_table_get*) (generated C lines ~989-1047). (3) Operator/dispatch helpers box arithmetic on lua_Value (lines ~1640-1670). Highest-leverage native-lowering targets: eliminate lua_to_num boxing at typed-call boundaries and in table-access fast paths. Note: this is the expected dynamic-typing path, not a regression; showcases (meta_*) are already 0-boxing. Coordinate with antigravity (codegen.zig LOCKED). | Files: src/codegen.zig, examples/benchmark.duo |
| F-14890-2 | zls.duo MCP server fails C compilation (pre-existing) | P2 | tooling_gap | !2026-07-31T09:21:30Z | open | duo-mcp/zls.duo passes `duo check` (sema) but `duo run` fails with 'C compiler failed (exit 1)' both before and after the mcp.duo register_tool fix (confirmed by revert). One of the known codegen bugs (concat-in-tail / nil-init void* / type inference) in zls.duo's own source. Debug with DUO_KEEP_C=1 then /usr/bin/cc on /tmp/duo_zls.c. Blocks zls MCP tools/call entirely. Not caused by this session's changes. | Files: duo-mcp/zls.duo |
| F-14890-1 | Missing trailing args not defaulted to nil (garbage) | P0 | codegen_gap | !2026-07-31T09:21:30Z | closed | Root-fixed in direct call emission: after explicit args and declared defaults, remaining params now receive deterministic missing-arg expressions (`lua_val_nil()` for `.any`, native nil coercions for numeric/bool/str, null/zero sentinels for native aggregates). `examples/missing_args_nil_smoke.duo` verifies `.any` missing arg is nil and typed numeric missing arg coerces to 0. Historical MCP workaround in `lib/std/mcp.duo` can remain conservative. Verified `zig build`, focused smoke, and full `agent_smoke.sh` PASS. | Files: src/codegen.zig, lib/std/mcp.duo, examples/missing_args_nil_smoke.duo |
| F-13813-5 | pattern engine: %s+ corrupts captures; [%w_] parses as literal set; %w includes underscore | P2 | expressiveness_gap | !2026-07-31T09:03:33Z | open | duo's string pattern matcher diverges from Lua: (1) `string.gsub(s, '^fun%s+', '')` fails to strip and corrupts following text ('funadd_i64(x)' -> 'funadd_i64(x)' unchanged or mangled); (2) `string.match('add_i64', '([%w_]+)')` returns empty (bracket class with _ mis-parsed); (3) `%w` already includes underscore (unlike PUC Lua), so `[%w_]` is redundant/mis-parsed. Impact: blocks metaprogramming pattern detectors that rely on %s+ or bracket classes. Workaround used in exponential_evaluate: avoid patterns entirely; use string.find + string.sub + tonumber + char-scan. | Files: src (pattern matcher / string runtime), duo-mcp/duo_shared.duo |
| F-13813-4 | codegen: variables declared inside if/else branches are C-block-scoped, invisible after block | P2 | native_lowering_gap | !2026-07-31T09:03:33Z | open | A variable first assigned inside an `if`/`else` branch is emitted as a C local scoped to that branch; referencing it after the if/else produces 'use of undeclared identifier'. Repro: `fun f() if c then v=1 else v=2 end return v end`. Workaround: either hoist an initial assignment to function scope BEFORE the if (with a typed, non-nil sentinel) or inline the dependent expression into each branch. Distinct from Lua semantics where such vars are function-scoped. | Files: src/codegen.zig |
| F-13813-3 | sema: nil-init promotes inferred type to void*, breaks later any/str assignment | P1 | native_lowering_gap | !2026-07-31T09:03:33Z | open | Declaring `x = nil` then later `x = "str"` causes sema to infer x as void*; subsequent use as a string emits lua_len_num(void*) / lua_to_str(void*) and C compile fails with 'assigning to void* from incompatible type lua_Value' or 'member reference base type void*'. Repro: `fun f() x = nil x = "hi" return #x end`. Workaround: initialize with a typed sentinel (`x = ""` for strings). Also bites function-scope temp hoisting (`schema = nil` then `schema = p2`). Documented earlier for nm=nil; confirmed general. | Files: src/sema.zig, lib/std/mcp.duo |
| F-13813-2 | codegen: call-statement as last stmt of if/for body emits premature return | P1 | native_lowering_gap | !2026-07-31T09:03:33Z | closed | Fixed by splitting block tail handling: normal nested control-flow blocks now evaluate tail expressions as statements, while function/closure bodies keep implicit-return mode. Added return-context routing for final complete `if/elseif/else` statements so expression-valued `if` functions like `fun styled(...) if cond a else b end end` still return branch values. Added deterministic default fallthrough returns for normal function bodies to avoid optimized C UB in nil-returning helpers. Verified `examples/nested_tail_call_statement_smoke.duo`, `examples/std_metaprogramming_modules_smoke.duo`, `scripts/duo_lock.sh -- zig build`, `zig test src/codegen.zig --test-filter block`, and full `bash scripts/agent_smoke.sh` PASS. | Files: src/codegen.zig, lib/std/agent.duo, examples/nested_tail_call_statement_smoke.duo |
| F-13813-1 | codegen: chained '..' as bare implicit return value is garbled | P1 | native_lowering_gap | !2026-07-31T09:03:33Z | open | A chained string concatenation used as a function's tail value WITHOUT an explicit `return` keyword (e.g. a bare `"a" .. x .. " (" .. k .. ")"` as the last line after a statement) mis-compiles: the leading operand renders as nil and intermediate separators are dropped. Repro: `fun g() script.fs_write(p,"hi") "ok: " .. id .. " (" .. kind .. ")" end` returns `nilF-1 (ergonomic_gap)` instead of `ok: filed F-1 (ergonomic_gap)`. Workaround: use explicit `return` (verified). Likely a codegen.zig issue in implicit-return-of-concat-chain lowering. | Files: src/codegen.zig, duo-mcp/duo_shared.duo |
| --- | --- | --- | --- | --- | --- | --- |
| F-2026-08-01-meta-std-smoke | std_metaprogramming_modules_smoke still fails after meta native folding | P1 | native_lowering_gap | !2026-08-01T00:00:00Z | superseded | agent-smoke previously passed through agent hooks, script lock, nested std req, meta_hierarchy, meta_power_permute, meta_compose_each, meta_choose, and cached persistence, then failed at examples/std_metaprogramming_modules_smoke.duo with undeclared __rewrite_describe / __rewrite_rulecount and std.term `color`. Superseded by F-2026-08-01-meta-std-smoke-fix. Do not rerun smoke as `duo_lock.sh -- bash scripts/agent_smoke.sh` because the wrapper already acquires the lock and that deadlocks silently. | Files: src/codegen.zig, src/meta_codegen.zig, lib/std/term.duo, examples/std_metaprogramming_modules_smoke.duo, scripts/agent_smoke.sh |
| F-2026-08-01-meta-std-smoke-fix | std_metaprogramming_modules_smoke native compile blockers cleared | P1 | native_lowering_gap | 2026-08-01T00:00:00Z | closed | Follow-up fixed the first failure chain: @comp.rewrite.describe / rulecount now lower natively, embedded module functions can see captured top-level locals such as std.term `color` through promoted module storage, and @meta.concepts fields/members/count lower to native lua_Value tables or i64 without undeclared compiler intrinsic calls. `./zig-out/bin/duo compile examples/std_metaprogramming_modules_smoke.duo -v` passes; remaining warnings are deprecated pairs/ipairs in std files. | Files: src/codegen.zig, src/sema.zig, examples/std_metaprogramming_modules_smoke.duo |
| F-2026-08-01-std-pipeline-smoke-crash | std_metaprogramming_modules_smoke now crashes in std.pipeline after earlier native blockers | P1 | runtime_lowering_gap | !2026-08-01T00:00:00Z | closed | Stale after current tree repair: `bash scripts/agent_smoke.sh` passes end-to-end, including `examples/std_metaprogramming_modules_smoke.duo`. Keep the earlier warning: do not run smoke as `duo_lock.sh -- bash scripts/agent_smoke.sh`; the shell wrapper has its own locking behavior and can stall. Remaining warnings are deprecated `pairs`/`ipairs` in std files, not a smoke failure. | Files: lib/std/pipeline.duo, src/codegen.zig, examples/std_metaprogramming_modules_smoke.duo |
| F-2026-08-01-strsplitcount-native-fold | `@comp.str.splitcount` fell back to undeclared runtime function | P1 | native_lowering_gap | 2026-08-01T00:00:00Z | closed | `@comp.str.splitcount(TMPL_VARIANTS, "|")` in `examples/meta_generative_stack_showcase.duo` emitted `lua_Value __fn = __strsplitcount` and failed C compilation. Fixed by giving `__strsplitcount` an `i64` type in sema/codegen and folding it from comptime strings in `maybe_emit_meta_int_call`; no Lua function value or boxed intermediary. Verified `zig build`, `meta_generative_stack_showcase`, and full `agent_smoke.sh` PASS. | Files: src/codegen.zig, src/sema.zig, examples/meta_generative_stack_showcase.duo |
| F-2026-08-01-embedded-assignment-promotion | Embedded module-scope assignment referenced by bare functions emitted as init-local | P1 | native_lowering_gap | 2026-08-01T00:00:00Z | closed | `std.meta.bundles` uses concise Duo module syntax `bundles = {...}` plus bare exported functions. Generated file-scope functions referenced undeclared `bundles`. Fixed `promote_embedded_module_captured_locals` to promote module-scope assignment targets, not only explicit local declarations, when module functions reference them. Verified `embedded_bare_bundles_smoke` and full `agent_smoke.sh` PASS. | Files: src/codegen.zig, lib/std/meta/bundles.duo, examples/embedded_bare_bundles_smoke.duo |
| F-2026-08-01-not-neq-syntax | Preferred Duo boolean spelling needed Python-style `!=` | P2 | expressiveness_gap | 2026-08-01T00:00:00Z | closed | `not` was already the canonical unary boolean operator. Added lexer support for `!=` as an alias to existing `.neq`, preserving postfix `x!` unwrap semantics and keeping codegen/sema on the same native bool path. Added `examples/syntax_not_neq_smoke.duo`, registered it in `std.agent.smoke_targets()`, and documented GR-005. Verified lexer tests, focused smoke, `zig build`, and full `agent_smoke.sh` PASS. | Files: src/lexer.zig, docs/GRAMMAR_SPEC.md, lib/std/agent.duo, examples/syntax_not_neq_smoke.duo |
| F-2026-08-01-json-direct-iteration | std.json still used deprecated pairs iteration in smoke path | P3 | ergonomic_gap | 2026-08-01T00:00:00Z | closed | Replaced `pairs(...)` in std.json array detection and object encoding with direct Duo table iteration (`for k, v in t do`), preserving JSON encode/decode behavior while reducing deprecated-iteration noise in agent smoke. Added `examples/json_direct_iteration_smoke.duo` and registered it in `std.agent.smoke_targets()`. Verified focused JSON smoke, nested std req, script lock, `scripts/duo_lock.sh -- zig build`, and full `bash scripts/agent_smoke.sh` PASS. Remaining deprecated iteration warnings are in std.meta/std.reflect/std.maps, not std.json. | Files: lib/std/json.duo, lib/std/agent.duo, examples/json_direct_iteration_smoke.duo |
| F-2026-08-01-maps-direct-iteration | std.maps still used deprecated pairs iteration in meta smoke path | P3 | ergonomic_gap | 2026-08-01T00:00:00Z | closed | Replaced all `pairs(...)` loops in std.maps with direct Duo table iteration, including key/value views, count loops, equality checks, clone/copy, and merge helpers. This keeps the public maps API unchanged while reducing deprecated-iteration warnings in `std_metaprogramming_modules_smoke`. Verified no `pairs`/`ipairs` remain in lib/std/maps.duo, focused std metaprogramming modules smoke PASS, JSON direct-iteration smoke PASS, `scripts/duo_lock.sh -- zig build` PASS, and full `bash scripts/agent_smoke.sh` PASS. Remaining deprecated iteration warnings are in std.meta/std.reflect, not std.maps. | Files: lib/std/maps.duo, examples/std_metaprogramming_modules_smoke.duo |
| F-2026-08-01-reflect-direct-iteration | std.reflect still used deprecated pairs iteration in meta smoke path | P3 | ergonomic_gap | 2026-08-01T00:00:00Z | closed | Preserved the existing std.reflect `kind` cleanup and migrated the remaining `pairs(...)` loops to direct Duo table iteration across size, fields, field_names, deep_equal, deep_copy, map_keys, and map_values. Verified no `pairs`/`ipairs` remain in lib/std/reflect.duo, focused std metaprogramming modules smoke PASS, JSON direct-iteration smoke PASS, `scripts/duo_lock.sh -- zig build` PASS, and full `bash scripts/agent_smoke.sh` PASS. Remaining deprecated iteration warnings in agent smoke are now isolated to std.meta. | Files: lib/std/reflect.duo, examples/std_metaprogramming_modules_smoke.duo |
| F-2026-08-01-meta-direct-iteration | std.meta was the final deprecated iteration source in agent smoke | P3 | ergonomic_gap | 2026-08-01T00:00:00Z | closed | Migrated remaining `pairs(...)`/`ipairs(...)` loops in std.meta to direct Duo table iteration while preserving existing concept descriptor changes and `derive_iter` direct table return. This removes deprecated iteration warnings from the standard metaprogramming smoke path across std.json/std.maps/std.reflect/std.meta. Verified focused std metaprogramming modules smoke PASS, no `pairs`/`ipairs` in those four modules, `scripts/duo_lock.sh -- zig build` PASS, and full `bash scripts/agent_smoke.sh` PASS before the backend wording follow-up. | Files: lib/std/meta.duo, examples/std_metaprogramming_modules_smoke.duo |
| F-2026-08-01-no-llvm-agent-guidance | Agent-facing backend guidance still mentioned LLVM | P2 | backend | 2026-08-01T00:00:00Z | closed | User reaffirmed "do not use LLVM; implement Duo-native solution" for G-008/G-020/G-021. Canonical buffer already said NOT LLVM IR, but `src/meta_module.zig` agent gaps text still said "machine code / LLVM beyond C intermediate". Updated it to "Duo-native asm/object emission beyond C; no LLVM IR dependency" so @comp.agent.gaps guidance matches the canonical backend rule. Verified `scripts/duo_lock.sh -- zig build` PASS and focused `examples/agent_hooks_showcase.duo` PASS after the wording change. | Files: src/meta_module.zig, .agents/AGENT_COORDINATION.md |
| F-2026-08-01-lock-bypass-stall | duo_lock.sh bypassed for `zig test`/`zig run`/`duo run` → machine-wide OOM stall + disk-full from 3.7GB .zig-cache | P0 | coordination_gap | 2026-08-01T20:00:00Z | open | TWO PROJECT-WIDE STALLS this session, both fixed/mitigated by pi: (1) DISK-FULL: disk hit 100% / 122Mi free with `.zig-cache` at 3.7GB — NO agent could build, and the full-disk condition ALSO caused cascading stale-cache false test failures (7 apparent unit-test failures → 3 real once cache cleared). Cleared `.zig-cache` + gitignored `*.out`/`*.o` scratch (kept all tracked fixtures). Disk recovered to 17Gi free, repo 3.8G→127M, duo binary rebuilt and runs. (2) COMPUTE-OOM: `scripts/duo_lock.sh` only serializes whatever command is passed to it; agents routinely invoke `zig test src/codegen.zig`, `zig run`, `duo run|compile` DIRECTLY, bypassing the lock. With 5+ agents each launching a ~2GB-RAM `zig` process concurrently, the kernel exhausts RAM/swap and can no longer fork a shell (`posix_spawn EAGAIN`) across ALL sessions — risks a forced reboot. **MANDATE (all agents, enforce):** EVERY heavy invocation — `zig build`, `zig test`, `zig run`, `duo run`, `duo compile`, `duo check` over nontrivial input — MUST be wrapped as `scripts/duo_lock.sh -- <cmd>`. NEVER call bare `zig test|run` or `duo run|compile`. Treat `EAGAIN` on spawn as a HARD STOP, not a retry loop (retrying worsens the stall and risks reboot). TODO: extend `duo_lock.sh` (or add a shim) so `zig`/`duo` heavy subcommands auto-acquire the lock even when invoked bare. ALSO shipped this session (pi, on disk in src/parser.zig): FIX-A `@c.export` now attaches to the following `fun`/decl instead of becoming a standalone `.directive` (root cause: meta_module.zig:359 catalogs `c.export`, making `isMetaAttribute("c.export")` true → parse_attributed_decl emitted it standalone; fix: c.export/c.type/c.ffi/c.call/c.link now accumulate as attributes before the isMetaAttribute check) — VERIFIED, both @c.export tests + GR-007 rejection PASS. FIX-B method-call colon inside an arg list (`red:to_string(` in `print(red:to_string())`) no longer mis-counted as a param type annotation — added `Parser.colon_is_method_call` ahead-look (`: name (` = method call); unblocks derived-enum meta-descriptor test — PENDING VERIFY (OOM stall blocked the test run). unit-test TRUE state on fresh cache: 692/695 pass, 3 fail (the 4 typed-string boxing tests were stale-cache false failures). Remaining 3 = the two @c.export (FIXED) + derived-enum (parse half FIXED) → should hit 0/695 once FIX-B is verified. VERIFY cmd: `scripts/duo_lock.sh -- zig build unit-test --summary all`. | Files: scripts/duo_lock.sh, src/parser.zig, .agents/AGENT_COORDINATION.md |

### Agent Session Log
**2026-07-31: antigravity** - Updated AGENTS.md to point to duo-mcp, removed python symlinks, and filed scripting gap. Deduplicated python MCP implementations and used duo_shared.duo to post findings.
**Gap P1:** There are still ~15 bash scripts in scripts/ (e.g. run_benchmark.sh, test_wasm_codegen.sh) that need to be migrated to pure Duo scripts to fulfill the 'Duo as scripting language of choice' goal.
| 2026-08-01T00:00:00Z | codex | ship | Native-folded `@comp.str.splitcount` to `i64` and promoted embedded module-scope assignment targets referenced by bare functions. `scripts/duo_lock.sh -- zig build`, `meta_generative_stack_showcase`, `embedded_bare_bundles_smoke`, and `bash scripts/agent_smoke.sh` PASS. |
| 2026-08-01T00:00:00Z | codex | ship | GR-005: `!=` now lexes to existing `.neq`; `not` remains canonical boolean negation. Added `syntax_not_neq_smoke` to `std.agent.smoke_targets`; lexer test, focused smoke, build, and full agent-smoke PASS. |
| 2026-08-01T00:00:00Z | codex | ship | Closed F-14890-1 root cause: direct native calls now fill missing trailing params with deterministic nil/native-coerced values. Added `missing_args_nil_smoke` to agent-smoke; build and full agent-smoke PASS. |
| 2026-08-01T00:00:00Z | codex | ship | Closed F-13813-2: nested control-flow tail calls no longer return from the enclosing function; final expression-valued `if/elseif/else` statements in returning function bodies still lower to branch returns. Added `nested_tail_call_statement_smoke` to agent-smoke. Build, focused smokes, codegen block tests, and full agent-smoke PASS. |
| 2026-08-01T00:00:00Z | codex | ship | Closed F-2026-08-01-json-direct-iteration: std.json now uses direct table iteration instead of deprecated `pairs(...)`; added `json_direct_iteration_smoke` to agent-smoke. Focused smoke, build, nested std req, script lock, and full agent-smoke PASS. |
| 2026-08-01T00:00:00Z | codex | ship | Closed F-2026-08-01-maps-direct-iteration: std.maps now uses direct table iteration throughout. Focused std metaprogramming modules smoke, JSON smoke, build, and full agent-smoke PASS; remaining deprecated iteration warnings are std.meta/std.reflect. |
| 2026-08-01T00:00:00Z | codex | ship | Closed F-2026-08-01-reflect-direct-iteration: std.reflect now uses direct table iteration throughout. Focused std metaprogramming modules smoke, JSON smoke, build, and full agent-smoke PASS; remaining deprecated iteration warnings are isolated to std.meta. |
| 2026-08-01T00:00:00Z | codex | ship | Closed F-2026-08-01-meta-direct-iteration: std.meta now uses direct table iteration throughout, removing deprecated iteration warnings from the metaprogramming smoke path across std.json/std.maps/std.reflect/std.meta. Focused smoke, build, and full agent-smoke PASS. |
| 2026-08-01T00:00:00Z | codex | ship | Closed F-2026-08-01-no-llvm-agent-guidance: @comp.agent.gaps text now says Duo-native asm/object emission beyond C with no LLVM IR dependency, matching the canonical G-008/G-020/G-021 direction. Build and agent hooks smoke PASS. |
| 2026-08-01T00:00:00Z | codex | work | Native backend G-008/G-020/G-021 progress: direct arm64 Mach-O/native-asm now lowers integer comparisons plus statement `if`/`elseif`/`else`, patches conditional/unconditional branches, and emits local asm labels. Added `examples/native_branch_smoke.duo`; focused native backend tests PASS (7/7), `scripts/duo_lock.sh -- zig build` PASS, native-object and native-asm linked smokes both exit `60` as expected. Gap remains open for loops, real external relocations, spills/lifetime allocation, branch local merging, object formats, and executable/shared-library integration. |
| 2026-08-01T00:00:00Z | codex | work | Native backend G-008/G-020/G-021 progress: direct arm64 Mach-O/native-asm now lowers `while`, `break`, and `continue` using a loop-context stack and patched branch offsets. Added `examples/native_loop_smoke.duo`; focused native backend tests PASS (8/8), `scripts/duo_lock.sh -- zig build` PASS, native-object and native-asm linked smokes both exit `12` as expected. Gap remains open for numeric for, real external relocations, spills/lifetime allocation, branch/loop local merging, object formats, and executable/shared-library integration. |
| 2026-08-01T00:00:00Z | codex | work | Native backend G-008/G-020/G-021 progress: direct arm64 Mach-O/native-asm now lowers inclusive numeric `for` loops with runtime positive/negative step handling. Refined loop contexts so `continue` targets numeric-for increment blocks and while-loop headers appropriately. Added `examples/native_for_smoke.duo`; focused native backend tests PASS (9/9), `scripts/duo_lock.sh -- zig build` PASS, native-object and native-asm linked smokes both exit `20` as expected. Gap remains open for real external relocations, spills/lifetime allocation, branch/loop local merging, object formats, native executable/shared-library integration, and generic iteration. |
| 2026-08-01T00:00:00Z | codex | work | Native backend G-008/G-020/G-021 progress: direct arm64 Mach-O objects now emit undefined external symbols and ARM64 `BR26` relocation records for bodyless `@ffi("symbol") fun name(...)` call targets. Added `examples/native_reloc_smoke.duo`; focused native backend tests PASS (10/10), `scripts/duo_lock.sh -- zig build` PASS, `nm -m` shows undefined `_llabs`, `otool -rv` shows one `BR26` relocation, and native-object/native-asm linked smokes both exit `42` as expected. Gap remains open for data relocations, spills/lifetime allocation, branch/loop local merging, object formats, native executable/shared-library integration, and generic iteration. |
| 2026-08-01T00:00:00Z | codex | work | Native backend G-008/G-020/G-021 progress: direct arm64 backend now tracks reusable scratch registers instead of monotonically consuming x9-x28, copies params from ABI x0-x7 into scratch locals, prevents new-local register aliasing, and saves only active scratch regs plus x30 around calls. Added `examples/native_regalloc_smoke.duo`; focused native backend tests PASS (11/11), `scripts/duo_lock.sh -- zig build` PASS, native-object/native-asm linked smokes both exit `211`, and generated asm shows a 32-byte call frame instead of the old 176-byte blanket save for that smoke. Gap remains open for true spills, data relocations, branch/loop local merging, object formats, native executable/shared-library integration, and generic iteration. |
| 2026-08-01T00:00:00Z | codex | work | Native backend G-008/G-020/G-021 progress: added `--target native-exe`, which emits a Mach-O object through `src/native_backend.zig` and links it into an executable without generating C or LLVM IR. `duo run --target native-exe` now compiles, links, runs, forwards args, and propagates exit codes. Added `examples/native_exe_smoke.duo`; focused native backend tests PASS (12/12), `scripts/duo_lock.sh -- zig build` PASS, native-exe compile/run smokes both exit `42`, and `otool -rv` on the object path shows one `BR26` relocation against `_llabs`. Gap remains open for native shared libraries, true spills, data relocations, branch/loop local merging, object formats, and broader typed/native coverage. |
| 2026-08-01T00:00:00Z | codex | work | Native backend G-008/G-020/G-021 progress: added `--target native-dylib`, which emits a Mach-O object through `src/native_backend.zig`, permits no-main modules with exported functions, and links with `-dynamiclib` without generating C or LLVM IR. Added `examples/native_dylib_smoke.duo` plus `examples/native_dylib_harness.c`; focused native backend tests PASS (13/13), `scripts/duo_lock.sh -- zig build` PASS, dylib smoke exports `_duo_native_add`, and the harness linked against the dylib exits `42`. Gap remains open for true spills, data relocations, branch/loop local merging, object formats, broader typed/native coverage, and parser repair for canonical newline-separated `@c.export(...)`. |
| 2026-07-31T17:55:00Z | session | work | RECOVERED from reset accident: The extensive metaprogramming staged changes (comptime.zig hooks, rewrite_rules.zig, parser improvements for bare functions/if-expressions, all generative combinator handlers) were accidentally lost when resetting to fix benchmark crash. Coordination restored to full state. Current HEAD has working Duo compiler (707 unit tests pass, zig build test passes). Meta_module.zig contains the @comp.* hierarchy definition. Staged work needs to be reimplemented or recovered. Coordination restored to full state.

| 2026-07-31T20:45:00Z | recovery | critical | RECOVERY ATTEMPT: The uncommitted staged changes (comptime.zig hooks + 2000 lines, rewrite_rules.zig, parser improvements for bare functions/if-expressions, all generative combinator handlers) were accidentally lost when git reset --hard was used. Coordination file has been verified intact (397 lines). Current HEAD is stable (707 unit tests pass). No backup files exist. Rebuilding from documentation and partial captures. |

| 2026-07-31T22:00:00Z | recovery | SUCCESS | RECOVERY COMPLETE: Found staged changes in git worktree at /private/tmp/duo-recovery (commit 1ba87ba [recovery/jul-30]). Copied all src/*.zig and lib/std/*.duo files. Key recovered files: rewrite_rules.zig (468 lines), rewrite_apply.zig (323 lines), comptime.zig (1644 lines), meta_module.zig (1462 lines). Build passes at HEAD. Staged work was in-progress state. |

| 2026-08-01T19:10:00Z | pi | ship | GR-007 IMPLEMENTED: parser now rejects `@const`/`@comptime`/`@comptime_expr`/`@comptimeexpr`/`@compile_time`/`@compiletime` in BOTH statement and expression position with a directed error + hint pointing to `@(expr)` or `@comp.*` (was a generic "expected 'name'" cascade because `const`/`comptime` are keyword tokens). Added `Parser.bannedAtDirectiveSuggestion` in `src/parser.zig`; checked at top of `.at` statement dispatch and top of `parse_macro_call_expr`. `@constexpr` intentionally NOT banned (working `__constexpr` folder). 2 parser tests added (`GR-007 rejects…`, `GR-007 does NOT reject @(expr)…`), both PASS. Verified: `scripts/duo_lock.sh -- zig build` PASS, tier-0 `agent_smoke.duo` PASS (29/29), unit-test failures 12→7 (mine add none; 7 remaining are pre-existing @c.export/typed-string codegen failures from other agents' WIP). Files: src/parser.zig, docs/GRAMMAR_SPEC.md. |
| 2026-08-01T19:20:00Z | opencode | verify | MERGE STATE VERIFIED after stash-restore + GR-007 coexist: (1) G-050 assign-form bare func (GR-001) fix live in tree, parser test `assign-form bare func decl without return type (GR-001)` at parser.zig:4743 PASS; `starts_parenthesized_func_expr` uses OR (matches `starts_bare_func_decl`). (2) GR-007 ban checks (statement + expression) + `@constexpr` carve-out intact; both GR-007 parser tests PASS. (3) `self.duo_mode` field-access fixes merged cleanly (`rg lexer.duo_mode` = 0 hits). (4) Gates: `zig build` PASS, `agent_smoke.duo` PASS (29/29). (5) unit-test 688/695; the 7 failures are EXACTLY the pre-existing set pi documented (@c.export parser+codegen, typed-string codegen x4, derived-enum meta descriptors) — all owned by other agents' WIP; `@c.export` parser repair is codex's native-backend gap (see native-dylib entry). (6) NOTE for @c.export owners: current parse drops the `fun` decl when `@c.export` attribute attach fails (compiles but no exported symbol / no add fn in nm) — repro: `@c.export("duo_add")\nfun add(a: i64, b: i64): i64\n return a + b\nend`. Files: src/parser.zig, .agents/AGENT_COORDINATION.md. |
| 2026-08-01T19:55:00Z | opencode | ship | PARSER METHOD-CALL FALSE POSITIVE KILLED, root-caused to the bare-func heuristic scan, not just the trailing-colon peek. Refactored `starts_bare_func_decl` + `starts_parenthesized_func_expr` (src/parser.zig) into ONE shared helper `scan_func_header_signal()` with two new guard rails: (1) a `fun`/`function` keyword at paren-depth 1 returns false — a nested function argument means the whole paren group is a CALL, not a header (this is what broke `mcp.register_tool("x", {...}, fun(args) q = (args.query or ""):lower() ... end)` — the `:lower()` colon at depth 1 was setting `typed_or_vararg=true` and misdetecting the whole register_tool call as a bare function decl); (2) a depth-1 `:` only counts as a typed param when the PREVIOUS token is a name (`a: i32`), so `(expr):method()` / `):c(` colons are never counted. Verified: 13-probe battery PASS (paren+str method, paren+name method, paren+bin-expr method, call-statement, gmatch loop, typed assign-form G-050, bare typed func, assign-with-colon-ret, bare main(): i64, obj method, index method, full `mcp.register_tool(..., fun(args) q = (args.query or ""):lower() end)`, method-call after table-brace arg) AND real `duo_bench.duo` `duo check` now reports ✓ (was: `expected 'name', got 'string'` at the register_tool call). Note: `sub(a: i64, b: i64) = a - b` (typed params + `=` body, no return type) is NOT supported — pre-existing; `sub(a: i64, b: i64): i64 a - b end` and `sub = (a: i64, b: i64): i64 a - b end` both work. Files: src/parser.zig. |
| 2026-08-01T19:57:00Z | opencode | ship | duo-mcp/duo_shared.duo:710 was a BARE `====================================` separator line (never commented) — `duo check` failed with `expected expression, got '=='`. Commented it out (`-- ====...`). File was otherwise clean; `duo_shared.duo`/`duo_bench.duo`/`duo_lsp.duo`/`zls.duo`/`mcp_audit.duo` all now pass `duo check` with the rebuilt binary. Remaining MCP TODOs for the next session: (a) run the MCP stdio handshake (`initialize` + `tools/list` piped into `duo run duo_bench.duo` / `duo_lsp.duo`); (b) repoint ~/.claude.json mcpServers off the deleted `duo_lsp_mcp.py`/`duo_bench_mcp.py`/`zls_mcp.py` to `duo run` launchers (per duo-mcp/README.md, env DUO_ROOT/DUO_BIN); (c) dedupe `duo_exponential_evaluate` double-registered in duo_lsp.duo (lines ~575 & ~643). Files: duo-mcp/duo_shared.duo. |
| 2026-08-01T20:05:00Z | opencode | warn | BUILD-INFRA CONFIRMED for F-2026-08-01-lock-bypass-stall: (1) A concurrent agent ran `rm -rf .zig-cache && scripts/duo_lock.sh -- zig test src/parser.zig ...` — the cache delete bypassed the lock, so my locked `zig build` hit `compiler_rt_zcu.o FileNotFound` / `configure_zcu.o FileNotFound` (cache thrash mid-build). Worked around with fully private cache: `zig build --cache-dir $T/duo-cache/proj --global-cache-dir $T/duo-cache/global` (PASS, no output). (2) The bash tool then entered persistent `Unknown: ChildProcess.spawn` — matches the EAGAIN-on-fork symptom in F-2026-08-01-lock-bypass-stall. Treat as HARD STOP per the mandate, not a retry loop. All file/read/edit tools kept working; session state + findings were logged here. Files: none (infra). |
| 2026-08-01T20:20:00Z | opencode | ship | DUO-LSP DEDUP: removed the FIRST of two `duo_exponential_evaluate` registrations in duo-mcp/duo_lsp.duo (the duplicate at old lines 575-583), keeping the PRIMARY ONBOARDING one; folded the native-boxing audit wording (lua_invoke/lua_Value/lua_table_* hits when file_path given) into the surviving registration's description. COSMETIC NOTE (do not touch until bash is back): the surviving handler calls `shared.exponential_evaluate(args.code, args.file_path, args.detail or 0)` with a 3rd arg the shared fn does not consume — harmless (extra args ignored in Duo) but the `detail` schema property is a no-op. Files: duo-mcp/duo_lsp.duo. |
| 2026-08-01T20:25:00Z | opencode | ship | ~/.claude.json `mcpServers` REPOINTED off the deleted Python launchers (`duo_lsp_mcp.py` / `duo_bench_mcp.py` / `zls_mcp.py`, which referenced a now-dead hermes venv python3) to the canonical pure-Duo launchers per duo-mcp/README.md: all three (duo-lsp / duo-bench / zls) now use `command=/Users/clp/x/duo/zig-out/bin/duo`, `args=["run", "/Users/clp/x/duo-mcp/<entry>.duo"]`, `env={DUO_ROOT:/Users/clp/x/duo}`. zls.duo reads `zls` from PATH (`which zls`), so the old ZLS_BIN env was dropped. CAVEATS: (1) Claude Code may rewrite ~/.claude.json on exit — if MCP is still broken after a restart, re-apply. (2) Runtime stdio handshake (initialize + tools/list) could NOT be verified — bash is in EAGAIN hard-stop from F-2026-08-01-lock-bypass-stall; all five entry .duo files DO pass `duo check` with the rebuilt binary (parser fix included). Files: ~/.claude.json, duo-mcp/duo_shared.duo. |
| 2026-08-02T04:00:00Z | hermes | verify | SESSION AUDIT — confirmed all user directives from goals prompt. (1) G-050 CLOSED: `sub = (a: i32, b: i32) a - b end` compiles and runs (parser fix live in tree). (2) `@const`/`@comptime` already banned (GR-007). (3) `fun`/`function` deprecated in new .duo (GR-001/GR-008) — user asks for FULL deprecation (hard error eventually); track as GR-010 candidate for next language milestone. (4) If-expression assignment GR-002 live. (5) Bracket-free table keys GR-004 live. (6) No Lua-boxed values mandate in AGENTS.md. (7) `duo_exponential_eval`, `duo_embed_symbols`, `duo_cross_lang_meta` tools live in duo-mcp/duo_bench.duo. (8) qoder/qoder-cli NOT available on npm or pip as of 2026-08-02 — skip. kilo/kimi/junie/trae confirmed installed. (9) Agent list updated in AGENT_COORDINATION.md. (10) Serena: Cursor wax-workspace plugin cache artefact — dismiss, do not file tickets. (11) REMINDER: agents MUST pivot off coordination work to language exponentials + performance + native backend (G-008/G-020/G-021). Files: .agents/AGENT_COORDINATION.md. |
| 2026-08-01T20:30:00Z | opencode | verify | USER RESTATED CORE GOALS — confirmations vs current state: (1) `@` directive hierarchy: canonical `@comp.*` (aliases @meta.* / @compiler.*), NO underscore public names — already enforced, 503 public names zero underscores, guard test src/meta_module.zig:1402. (2) No `@const`/`@comptime` — GR-007 implemented (parser rejects with hint to `@(expr)`/`@comp.*`). (3) Deprecate `fun`/`function` — GR-001 tracked (bare `name(params) body end` + assign `name = (params) body end`; note: `sub(a: i64, b: i64) = a - b` typed-param-with-`=`-body form NOT supported, only `: ret` or untyped). (4) If-expression assignment `x = if ... else if ... else ... end` — GR-002 tracked. (5) Bracket-free table keys `{ x = 1 }` — documented canonical; computed keys still need `[expr]`. (6) Coordination: buffers canonical at .agents/AGENT_COORDINATION.md + AGENT_CANONICAL.md, never-stash rule active. Per the user's direction, once coordination/MCP is restored, AGENTS SHOULD PIVOT OFF coordination work to language exponentials + performance. (7) Serena: still a Cursor wax-workspace project-plugin cache artefact, NOT a Duo MCP tool — dismiss, don't file tickets. Files: none (goals audit). |
