# The WASM runtime becomes duon's wasm capability — the shape, measured

**Filed:** 2026-08-08 · **Baseline commit:** `0e4eb29` · **Gap:** gap[072] (perf), this doc (shape)

## The directive

> "specifically ward, the duo native compact as possible fastest wasm version of
> wart (zig implementation) should be natively integrated into the duon
> toolchain, not called 'ward' but just being the wasm part of the duon
> toolchain."

So the product named `ward` stops existing. What it *does* — decode, validate,
interpret and JIT WebAssembly — becomes a capability of the duon toolchain with
no separate identity. `wart` stays external: it is the oracle, and an oracle
that lives inside the thing it validates has stopped being one
(`docs/wart-integration.md` §5).

Nothing below is taken on a label. Every placement claim has the command that
falsified the alternative.

---

## 1. What exists today, measured

Two wasm surfaces, and they are not two halves of one thing — they are a
library face and a program that share a subject.

```
ext/ward/            28 tracked .duo · 11,350 lines · 51 tracked non-.duo (47 .wasm, 2 .wat, .json, .gitignore)
  src/ward.duo       6,312 lines — THE RUNTIME. decoder + interpreter + ARM64 JIT, one file.
  src/wasm/*.duo     1,802 lines — a parallel modular tree. DEAD: nothing reqs it (§1.2).
  src/nn*.duo        370 lines — a tensor/NN library. Nothing to do with wasm.
  bench/             9 .duo harnesses + 47 .wasm fixtures
  test/conform.duo   480 lines — the conformance differential (`zig build wasm-test`)
  test/main.duo      108 lines — BROKEN: reqs src.wasm, src.edge, src.nn; two do not exist
  tools/opcodes.duo  551 lines — the opcode-table projector
  examples/          showcase.duo — BROKEN: reqs src.lib, which does not exist
  my-ward-app/       one scaffold .wat, no consumer

lib/std/wasm/        6 .duo · 1,433 lines — the LIBRARY face, `req "std.wasm.*"`
  decode.duo · instruction.duo · opcodes.duo · wasi.duo
  opcode_lookup.duo        (generated — `duo wasm-tables emit`)
  ward_mvp_opcodes.duo     (generated — same)
```

There is **no `duon wasm` subcommand**. `src/main.zig`'s dispatch list has
`wasm-tables` (a table generator) and nothing else wasm-shaped.

### 1.1 The runtime is one file, and that is load-bearing, not laziness

`src/ward.duo`'s header records six codegen constraints that forced the
monolith, of which two forbid decomposition outright:

- **BUG B** — pointer locals must not cross a function boundary → one function.
- **BUG C** — `req "std.mem"` fails (export table references DCE'd symbols), so
  the opcode constants are inlined rather than required.

And the file's own tail comment records why `main()` is wrapped rather than
bare: a bare module tail makes `can_emit_native_scalar_module` reject the WHOLE
file, every value transits a boxed `lua_Value` whose numeric payload is a
`double`, and that is what rounded `f64.const` bit patterns above 2^53 and cost
the low byte.

**Any plan that starts by splitting the 6,312 lines into modules is a plan to
lose the 29× JIT and re-earn the f64 bug.** The move below does not split it.

### 1.2 `src/wasm/*.duo` is dead, and one of its files is the foreign waist by name

`src/ward.duo` reqs exactly two modules: `std.jit` and `std.io`. Nothing in the
repository reqs `src.wasm.op`, `.simd`, `.stack`, `.table`, `.value`, `.memory`,
`.jit`, `.jit_arm64` or `.aot` except `test/main.duo`, which does not parse.

```
$ grep -rn 'req "' ext/ward --include=*.duo | grep -v src/ward.duo
```

`src/wasm/jit.duo:2` reads *"Strategy: emit C and invoke clang -O2 to produce a
shared library."* That is the C-as-intermediary waist Pass 103 §0b names as
banned, sitting in dead code. `src/wasm/aot.duo` is 10 lines and its `compile()`
returns `""`.

`src/wasm/jit_arm64.duo` (701 lines) is the exception: it is dead as a *module*
but it is cited as the source of truth by two live files —
`lib/std/compiler/arm64.duo` and `lib/std/compiler/arm64check.duo` — and
`docs/toolchain_state.md` names it a donor for SH-11. It stays.

---

## 2. Where the runtime lives — `tools/wasm/`, and the alternative is measurably fatal

### The obvious answer is `lib/std/wasm/**`. It is wrong, and a gate says so.

`scripts/capability_scan.duo` (Pass 105 U1, `zig build capability-scan`) counts
ambient `fs`/`net`/`clock`/`rand`/`proc`/`fault` reach across
`git ls-files 'lib/std/*.duo'` — a pathspec that recurses. Measured at baseline:

```
capability_scan: PASS — 278 sites (budget 278, slack 0), 53 modules (budget 53, slack 0)
  modules   258 tracked lib/std/**/*.duo
```

**Slack zero on both ratchets.** The engine is a program: `src/ward.duo` alone
carries 28 `os.getenv` / `io.open` / `os.clock` / `os.exit` sites, and seven
more ward files carry another 12. Moving the tree under `lib/std/` adds ~28
modules to a 258-module denominator and at least 40 sites to a 278-site budget
with zero slack. It is not a close call; it is an instant, hard red.

`scripts/stdlib_embed_gate.duo` says the same thing from the other side: it
does `find lib/std -name '*.duo'` and asserts every hit is `req`-able from a
fresh program. A monolith whose tail is `main()` would *execute* on `req`.
`lib/std/**` is, by construction, the home of modules you can require. The
engine is not one.

### The right answer is `tools/wasm/`, and the precedent is in CLAUDE.md

CLAUDE.md's "Consolidated tooling" section describes exactly this migration,
already performed twice:

> They live here because they VERSION-LOCK to the compiler. […] Out of tree
> that surfaces when someone next runs the MCP server; in tree it is caught by
> duo's gates on the commit that changes lowering.

`tools/lsp/` and `tools/mcp/` were separate products (`~/x/duo-lsp`,
`~/x/duo-mcp`) that became parts of the toolchain. `tools/lsp/src/server.duo`
is a program-shaped Duo file that an external driver invokes; so is the wasm
engine. `docs/spec/corpus.md` already carries `canonical tools/`, so the moved
files keep their partition and no deny-row moves.

**The shape:**

| | path | kind | surface |
|---|---|---|---|
| library face | `lib/std/wasm/**` | `req`-able modules | `req "std.wasm.decode"` — tables, decoder, WASI constants |
| engine | `tools/wasm/**` | a program the toolchain drives | `duon wasm run x.wasm` (owed, §3) |

Two directories, but now split by **kind** rather than by history. That is the
same split `tools/lsp` has against whatever LSP types live in `lib/std`, and it
is the split the gates already enforce.

### Rejected, with the reason

| option | why not |
|---|---|
| `lib/std/wasm/**` (all of it) | capability-scan slack is 0 on two ratchets; embed-gate requires `req`-ability. Measured, §2. |
| `lib/wasm/**` (sibling of std) | Avoids the gates, but invents a third top-level meaning for `lib/` and needs a new `docs/spec/corpus.md` prefix row. `tools/` needs none. |
| new top-level `wasm/` | Same corpus.md cost, plus it reads as a subproject — the exact framing the directive removes. |
| stay at `ext/ward/` | `ext/` is where vendored and external things live (7 of its 8 entries are submodules). Keeping the runtime there is keeping it external, which is the thing being undone. |

---

## 3. The user-facing surface — both, and the subcommand is handed back

**A library face already exists** and stays: `req "std.wasm.decode"`,
`std.wasm.opcodes`, `std.wasm.wasi`. `lib/std.duo` registers them; the ambient
`std.wasm.SECTION.CODE` path is checked by
`scripts/stdlib_correctness_gate.duo`. Nothing here changes except one filename
(§4).

**A subcommand is owed.** Today the engine is invoked by *environment
variable*, because compiled duon binaries do not populate Lua's `arg`:

```
DUO_WASM_MODULE=hot.wasm DUO_WASM_INVOKE=_start ./duo-wasm
```

That is not a toolchain surface, it is a workaround, and it has already faked
two benchmark sweeps (`bench/run.duo` header). The target:

```
duon wasm run <module.wasm> [--invoke <export>] [--engine interp|jit]
duon wasm check <module.wasm>          # header + section walk, no execution
duon wasm conform                      # the differential suite
```

**This is `src/main.zig`, which this work does not own.** The hand-back,
concretely:

1. `src/main.zig` ~line 469: add `"wasm"` to the subcommand-recognition list
   beside `"wasm-tables"`.
2. `src/main.zig` ~line 846 (next to the `wasm-tables` handler): add a `wasm`
   handler that resolves `tools/wasm/src/engine.duo`, compiles-or-caches it, and
   execs it with argv mapped onto the env contract in §4.
3. `src/main.zig` ~line 398 (usage text): one line,
   `wasm run|check|conform   run a WebAssembly module`.

Until (1)–(3) land the engine is reachable as `duo run tools/wasm/src/engine.duo`
and as the built binary, and the env contract remains the interface. **Do not
delete the env contract when the subcommand lands** — `test/conform.duo` and
every bench harness drive the binary directly, and argv still does not reach a
compiled binary (`docs/…duo-argv-reads-nil`).

---

## 4. The name map

`ward` is one word and lowercase, so LAW-ONE never flagged it; it is going away
for the reason the directive gives, not for a spelling violation. Several of the
*compound* spellings violate LAW-ONE twice over and are named as such.

### Executed here (owned)

| today | becomes | note |
|---|---|---|
| `ext/ward/` | `tools/wasm/` | `git mv` — subtree history preserved |
| `ext/ward/src/ward.duo` | `tools/wasm/src/engine.duo` | the runtime |
| `ext/ward/my-ward-app/` | deleted | one orphan `.wat`, no consumer, no reference |
| `zig build wasm-test` | `zig build wasm-test` | step name |
| `zig-out/bin/ward-conform` | `zig-out/bin/wasm-conform` | build artifact |
| `WARD_WASM` | `DUO_WASM_MODULE` | the old name read as "the ward wasm"; the value is a module path |
| `WARD_INVOKE` | `DUO_WASM_INVOKE` | |
| `WARD_ENGINE` | `DUO_WASM_ENGINE` | |
| `WARD_PHASES` | `DUO_WASM_PHASES` | |
| `WARD_DUMP` | `DUO_WASM_DUMP` | |
| `WARD_JIT_TRACE` | `DUO_WASM_JIT_TRACE` | |
| `WARD_BIN` | `DUO_WASM_BIN` | |
| `WARD_DERIVE_CHECK` | `DUO_WASM_DERIVE` | |
| `WARD_TIMEOUT` · `WARD_FIXTURES{,2,3}` · `WARD_UNSUPPORTED_BUDGET` · `WARD_TRACE_FD` · `WARD_JIT_DUMP` | `DUO_WASM_*` | harness-local |
| `ward_bin` (22 sites, Duo) | `binary` | LAW-ONE: `ward_bin` has an underscore |
| `_ward_run` · `_ward_assert` · `ward_wart_diff` · `ward_cmd` | `engine.run` · `check` · `diff` · `cmd` | LAW-ONE |
| `-- derived(ward.opcodes.*)` regions | `-- derived(wasm.opcodes.*)` | in `engine.duo` + `tools/opcodes.duo` |
| `ward:` diagnostic prefix (every `iom.err`) | `wasm:` | user-visible strings |
| `ext/ward/README.md` · `CLAUDE.md` · `HANDOFF.md` · `OPCODE_PLAN.md` | rewritten in place | the README's architecture section describes six files that do not exist |
| 25 `bench/ward_*.wasm` fixtures | `bench/jit/*.wasm`, `bench/simd/*.wasm` | fixture names, not identifiers; `nonduo` count unchanged by a move |

### Handed back — cannot be done from this ownership

| today | proposed | owner / why |
|---|---|---|
| `lib/std/wasm/ward_mvp_opcodes.duo` | `lib/std/wasm/mvp.duo` (`std.wasm.mvp`) | **Four-file atomic rename.** The file is `generated` in `docs/spec/corpus.md`, which exempts it from the audit100 deny table; rename it without moving that row and its 73 lines of `OP_i32_add = 106` land in the `canonical` partition and pay `snake` + `upper` in full on a table whose `upper` row is already 32 over. Touches `src/wasm_semantic_gen.zig:239`, `src/main.zig:{398,856,858}`, `src/semantic_compression_report.zig:39`, `src/ward_readiness.zig:70`, `docs/spec/corpus.md`, `lib/std.duo:213`, `examples/pass9/ward_mvp_opcodes_smoke.duo`. LAW-ONE violation twice over today. |
| `ward@allocation` / `ward@allocation_free` | `wasm@allocation` | `docs/spec/**` — a protocol anchor in the spec. The anchor names the *capability*, and the capability is now `wasm`. |
| `canonical ext/ward/` row | `canonical tools/wasm/` — or just delete it | `docs/spec/corpus.md`. `canonical tools/` already covers the new path, so the row is inert after the move, not wrong. Deleting it is cleanup, not a fix. |
| `src/ward_readiness.zig` | `src/wasm_readiness.zig` | `src/**`. Also its `ward_consumers` field → `consumers`. |
| `src/pass11_ward_barrier_tests.zig` | `src/pass11_wasm_barrier_tests.zig` | `src/**`, plus `build.zig:470` which this work *does* own — hand back as one commit so the build never names a missing file. |
| `scripts/pass11_ward_no_boxing_smoke.duo` | `scripts/pass11_wasm_no_boxing_smoke.duo` | `scripts/` — not in this ownership. |
| `duon wasm` subcommand | §3 (1)–(3) | `src/main.zig`. |

### Deliberately NOT renamed

- `wart`, `wart_*.wasm` fixtures, `bench/wart.duo` — wart is a different
  project and keeps its name.
- `forward` / `backward` / `toward` / `transformer_forward` in `src/nn/init.duo`
  — they contain the letters, not the name.

---

## 5. What happens to `bench/`, `examples/`, and the `nn`/AOT pieces

**`bench/` moves and stays.** It is the only harness that has ever produced a
ward number, and its header records why: the engine reads an env var, not argv,
so passing a module as an argument measures nothing. Two defects get fixed on
the way (`docs/wart-integration.md` §5 asked for both):

- `bench/run.duo:87` special-cases exit 132 (`128+SIGILL`) as wart's expected
  failure. wart does not SIGILL — measured 2026-08-08, it builds and JITs
  correctly on this machine. **Dead arm, removed.**
- `bench/run.duo:103` resolves wart through `$WART` / `$HOME/x/wart/...` — an
  unpinned path into an uncommitted working tree, so no published number records
  which wart it ran against. **The harness now prints the wart commit and
  dirty-state beside every wart row**, so an unpinned comparison announces
  itself instead of being quoted.

**`examples/` — `showcase.duo` is deleted.** It reqs `src.lib`, `std.ml.tensor`,
`std.ml.nn` and `std.ml.device`; `src/lib.duo` does not exist and has not for
long enough that nothing noticed. A 119-line example that cannot parse is not
documentation. `examples/hello.wasm` and `heavy_compute.wasm|wat` stay — they
are fixtures the conformance suite reads.

**`test/main.duo` is deleted.** `build.zig:221` already records that it "required
four modules that had been deleted and did not parse", which is why
`test/conform.duo` was written. Keeping a second, non-parsing test file next to
the real one is how a suite gets skipped.

**`src/nn*.duo` moves to `tools/wasm/…` for now and should not stay.** 370 lines
of tensors, layers and a transformer forward pass have nothing to do with
WebAssembly; they are there because ward's README promised "AI-native". Nothing
requires them except the deleted `test/main.duo`. **Proposal: they belong in
`lib/std/ml/` beside the existing `std.ml.*` family, or they should be deleted.**
Not decided here — `lib/std/ml/` is outside this ownership and a 368-line module
that no gate exercises should not be added to the capability-scan denominator
without someone owning the answer. Filed, not done.

**`src/wasm/aot.duo` and `src/wasm/jit.duo` should be deleted.** Both are dead
(§1.2). `jit.duo` is a C-emitting JIT — the foreign waist Pass 103 §0b bans by
name — and `aot.duo` is a 10-line stub returning `""`. They are cited by
`gaps/GAP-049.md` and `gaps/GAP-046.md` as live evidence, so deleting them
without updating those gap files would silently invalidate two citations.
**Proposal, not executed here**: delete both, and amend GAP-049/GAP-046 in the
same commit.

**`src/wasm/jit_arm64.duo` stays** — dead as a module, live as the source of
truth for `lib/std/compiler/arm64.duo` and `arm64check.duo`, and a named donor
for SH-11.

---

## 6. Gate exposure of the move — what can move and what cannot

| gate | baseline | exposure to a `git mv ext/ward → tools/wasm` |
|---|---|---|
| `language-census` | duo 790 · zig 237 · sh/py 0 · js 2 — PASS | **None.** Counts by extension over `git ls-files`; a move changes no extension. |
| `audit100` `nonduo` | 537 / 537, **slack 0** | **None from a move** — every file stays tracked and stays non-`.duo`. A single *added* non-`.duo` file fails it. Deleting `my-ward-app/main.wat` takes it to 536. |
| `audit100` deny rows | `snake` 14040/14121 · `upper` 2287/2255 ✗ · `trailret` 3472/3441 ✗ | **None from a move.** `docs/spec/corpus.md` classifies both `ext/ward/` and `tools/` as `canonical`, so the partition is identical. |
| `capability-scan` | 278 sites / 53 modules of 258, **slack 0 on both** | **None** — scans `lib/std/**` only. This is the gate that vetoes `lib/std/wasm/**` as the engine's home. |
| `native-census` | 119 native / 176 reachable — PASS | **None** — scans `examples/` only. |
| `unit-test` | 1341/1341 | **None** unless `src/**` or `build.zig`'s test targets move. |
| `wasm-test` (`wasm-test`) | rows 130 · PASS 126 · DIFF 0 · OK(void) 4 · jit 49/65 | **Total.** Every path in the step is relative to the old cwd. This is the gate that proves the move did not break the runtime, and it must be re-run after every batch. |

Two gates are **already red at baseline**, both from other sessions'
uncommitted work, and neither is caused by or fixed by this work:

- `audit100`: `upper` 32 over (traced to `lib/std/crypto/sha.duo`), `trailret`
  31 over. Both drift run-to-run while other agents edit.
- `agent-smoke`: `public_safety_scan` flagged
  `docs/wart-integration.md:25` for an absolute `/Users/...` path. That file is
  in this ownership and **is fixed here** (`~/x/wart`).

---

## 7. The order of execution

Smallest coherent steps, `zig build wasm-test` between each, and the answer
verified by value — a rename that leaves the runtime unrunnable is worse than no
rename.

1. **This document.** No code.
2. `git mv ext/ward tools/wasm`; retarget the `build.zig` step; delete
   `my-ward-app/`. Gate: the conformance suite reproduces 130/126/0 exactly.
3. `git mv src/ward.duo src/engine.duo`; rename the step to `wasm-test` and the
   artifact to `wasm-conform`. Gate: same.
4. Env contract: all `WARD_*` → `DUO_WASM_*`, **producer and consumer in one
   step**. A half-applied env rename does not error — the engine reads an unset
   variable and the harness reports a confident wrong thing. Gate: same, plus a
   negative control (unset the module var, require a non-zero exit).
5. `bench/run.duo`: dead SIGILL arm out, wart provenance in.
6. Prose: README/CLAUDE/HANDOFF rewritten; delete `showcase.duo` and
   `test/main.duo`.
7. Hand back §4's second table and §3's subcommand.

---

## 8. Execution record — 2026-08-08, steps 1–6 done, NOT committed

§1's tree listing above describes the state this work started from and is
deliberately left in the past tense. What is on disk now:

| step | done | evidence |
|---|---|---|
| 1 · this document | ✅ | |
| 2 · `git mv ext/ward tools/wasm`, build.zig retargeted | ✅ | 83 entries moved, subtree history intact |
| 3 · `src/ward.duo` → `src/engine.duo`, step → `wasm-test`, artifact → `wasm-conform` | ✅ | |
| 4 · `WARD_*` → `DUO_WASM_*`, producer + consumers together | ✅ | see the controls below |
| 5 · `bench/run.duo` SIGILL arm out, wart provenance in | ✅ | prints `wart at ad10076+3 uncommitted — NOT REPRODUCIBLE` |
| 6 · README rewritten, `showcase.duo` deleted, `my-ward-app/` deleted | ✅ | |
| 6b · `test/main.duo` deleted | ❌ **BLOCKED** | it carries another session's uncommitted edits; deleting it would destroy work this session does not own. Left in place. |

**Conformance is byte-identical across the whole move.** Before
(`ext/ward`, `ward-test`) and after (`tools/wasm`, `wasm-test`):

```
rows 130   PASS 126   DIFF 0   UNSUPPORTED 0   BAIL 0   NORESULT 0   OK(void) 4
jit asked 65, jit actually compiled 49
ok   68 fixture module(s) found
```

**The env rename was controlled, not assumed.** `UNSUPPORTED` reads 0 both
before and after, so the suite's refusal-matcher path never fired on its own —
a green there proves nothing. Three controls, run directly:

```
$ ./zig-out/bin/wasm-conform                                  # no module named
wasm: set DUO_WASM_MODULE=<module.wasm> …            exit 1   NEGATIVE control
$ WARD_WASM=bench/fib.wasm ./zig-out/bin/wasm-conform          # OLD name
wasm: set DUO_WASM_MODULE=<module.wasm> …            exit 1   old name is DEAD
$ DUO_WASM_MODULE=bench/fib.wasm ./zig-out/bin/wasm-conform
engine=jit-arm64 · result=2178309                    exit 0   BY VALUE (fib 32)
```

The third is the one that matters: a half-applied env rename does not error, it
reads an unset variable and reports a confident wrong thing. The second proves
the old name cannot answer, so nothing is silently reading it.

### Gates, before → after

| gate | before | after |
|---|---|---|
| `wasm-test` (`ward-test`) | 130 rows · 126 PASS · 0 DIFF · 49/65 jit | **identical** |
| `language-census` | sh/py 0 · js 2 · zig 237 — PASS | sh/py 0 · js 2 · zig 237 — **PASS** |
| `capability-scan` | 278 sites / 53 modules of 258 — PASS | **identical** — PASS |
| `native-census` | 119 native / 176 reachable — PASS | **identical** — PASS |
| `unit-test` | 1341/1341 (binary run, not the cached step) | **1341/1341** |
| `agent-smoke` | **FAIL** — `public_safety_scan` on an absolute `/Users/…` path | **PASS** — fixed here |
| `audit100` | **FAIL**, `upper` +32 · `trailret` +31 | **FAIL**, `accessor` +2 · `arrow` +11 · `trailret` +21 |

`audit100` was red before this work and is red after it, on rows the per-diff
report attributes to no file in this ownership; the tree moves under concurrent
sessions and these numbers drift run to run. What this work costs, by its own
delta report, is:

```
snake       -20     row is at or under budget
concatlit   +2      row is at or under budget
```

`snake -20` is the LAW-ONE repair (`ward_bin` → `binary`, `_ward_run` →
`_engine`, `_ward_assert` → `_expect`, `ward_cmd` → `invocation`). Three rows
it first cost — `underprefix +2`, `mwrapper +1`, `trailret +1`, all in newly
written code — were paid rather than budgeted: `_wartstamp` became
`provenance` (no `_` prefix), the early `return`s became a single implicit
tail, and `build.duo`'s `deps = {}` was deleted rather than left in the shape
the `M = {}` row matches.

`nonduo` went **537 → 536**: `my-ward-app/main.wat` deleted. That row's budget
had zero slack in the other direction, so this is the only safe direction to
move it.

### Known breakage this work causes outside its ownership

`scripts/runtime_bench.duo` is untracked, belongs to a concurrent session, and
hard-codes seven `ext/ward/...` paths (`ext/ward/bench/*.wasm`,
`ext/ward/src/*.duo`, `ext/ward/src/wasm/*.duo`). **Those paths no longer
exist.** It was not edited — it is not in this ownership and editing another
session's uncommitted file is how work gets lost — but it will report confident
zeros until its owner retargets them to `tools/wasm/`.

Stale `ext/ward/` paths also remain in files outside this ownership, all in
comments: `lib/std/compiler/arm64.duo`, `lib/std/compiler/arm64check.duo`,
`lib/std/io.duo`, `scripts/audit100.duo`, `scripts/capability_scan.duo`,
`gaps/GAP-041.md`, `GAP-046.md`, `GAP-049.md`, `GAP-072.md`, `AGENTS.md`,
`CLAUDE.md`, `.agents/AGENT_COORDINATION.md`, and `docs/spec/corpus.md`'s
`canonical ext/ward/` rule row.
