# duo — Duo language compiler

Duo is a Lua-superset language targeting native, WASM, and GPU. This repo is the compiler, written in **Zig master** (`0.17.0-dev`, managed via `mise`).

## Toolchain

- **Zig**: `zig@master` via mise — `~/.local/share/mise/installs/zig/master/bin/zig`
- **ZLS**: `zls@latest` via mise — works out of the box with ZLS-aware editors
- **WASI SDK**: installed via mise as `wasi-sdk@latest`
- **Runtimes for testing**: `wasmtime`, `wasmer` (both installed via mise)

Cross-compile a **Duo program** to WASM: `duo compile f.duo --target wasm32-wasi`
(verified 2026-08-08 — builds and runs under wasmtime).

Cross-compiling **the compiler itself** is a different thing and this line used
to conflate them. Measured 2026-08-08, every target actually built:

| target | result |
|---|---|
| `aarch64-macos` · `x86_64-macos` · `x86_64-linux-gnu` · `aarch64-linux-gnu` | **PASS** |
| `x86_64-windows` · `wasm32-wasi` | **FAIL** — see `gaps/GAP-040.md` |

Both failures have one cause: `src/duo_lexer_tokenize.c` is a tracked, generated
artifact that `build.zig` links into every build, and it was generated for macOS
(`#define _DARWIN_C_SOURCE`, `#include <ucontext.h>`, `popen`, `access`,
`mkstemp`). Windows now fails on exactly that one include; wasm32-wasi on it plus
the rest of the POSIX surface. The direct ARM64 Mach-O backend being
macOS/aarch64-only is BY DESIGN and is not what any row failed on — the three
green non-native targets all build through the C backend.

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
tools/lsp/             LSP server — 100% Duo (was ~/x/duo-lsp)
tools/mcp/             MCP servers: duo_bench, duo_lsp, zls — 100% Duo (was ~/x/duo-mcp)
ext/tree-sitter-duo/   tree-sitter grammar
ext/ward/              WASM runtime in Duo — downstream consumer (was ~/x/ward)
examples/              Example .duo programs
scripts/               Shell scripts for CI gates and benchmarks
docs/spec/             THE LAW — pass100.md + AUTHORITY.md + corpus.md
docs/archive/          historical evidence; never an architecture input
```

## Key invariants

- `@` is the single prefix for ALL compile-time operations in .duo files (`@comp.*`)
- NO underscores in `@`-directive names: `@comp.foo.bar`, never `@comp.foo_bar`
- Zero Lua boxed values in the hot path — all values must be native C ABI or direct registers
- Every perf change must pass `zig build bench` with no regressions

## Active plans

There are none. Pass 100 is the only plan; `docs/spec/AUTHORITY.md` carries what
is still owed. This section used to name Pass 11/12/13/16 plan documents as
active, which contradicted the epoch-2 rule below in the same file — every
`pass*.md` is historical. Those documents now live in `docs/archive/`.

The `pass11-gate` and `pass12`/`pass16` build steps still exist and still run:
a gate named after a pass is live tooling, not a live plan. Read the gate, not
the archived document it was named after.

## Consolidated tooling (2026-08-08)

`duo-lsp` and `duo-mcp` were merged in with `git subtree add` — full history,
not squashed, so `git log tools/lsp` reaches the original commits. Both were
already 100% Duo, which the language census confirms: `.duo` went 668 -> 715
with no new sh/py debt.

They live here because they VERSION-LOCK to the compiler. `duo-mcp` shipped a
call passing three arguments to a two-argument function — Lua drops the extra
silently, Duo lowers to a direct C call where it is a hard error. Out of tree
that surfaces when someone next runs the MCP server; in tree it is caught by
duo's gates on the commit that changes lowering.

`ward` merged in too (2026-08-08, `ext/ward`, 47 commits with history). I had
argued for keeping it out — it is the downstream consumer that proves Duo
builds real systems software, and building against a RELEASED binary is what
makes that evidence rather than a test fixture. That argument still holds and
is the thing to watch: if ward starts depending on unreleased compiler
behaviour, the proof quietly weakens. The census says it is 100% Duo (.duo 715
-> 737, c/h and sh/py both unchanged), so nothing foreign came with it.

`wart` (~/x/wart) stays separate: it is the Zig reference implementation ward
is measured against, and an oracle should not share a repo with the thing it
validates. It is also owned by cloud sessions and had uncommitted JIT work at
time of writing.

## Agent coordination

See `AGENTS.md` for full agent design targets. Coordinate via `duo_agent_gaps_update()`.
See `.agents/AGENT_COORDINATION.md` for active work tracking.

## EPOCH 2 — Pass 100 is the sole living authority

`docs/spec/pass100.md` (Duo 0.1) + this file are the ONLY law. Everything in
`docs/archive/` is HISTORICAL EVIDENCE, not an architecture input: 59 documents,
all pre-Pass-100, each stamped at the top, moved there out of `docs/plans/`
because a directory called "plans" taught every search that they were live.
See `docs/spec/README.md` for the precedence rule. If a rule you would cite
lives only there,
your objection is void — comply with Pass 100 and repair toward it.
Higher pass number wins; this file's epoch stamp wins over what it summarizes.

### §0 HOT SCREEN — newest law, most likely to look wrong to you. It is law.

1. **IDENTIFIERS ARE ONE LOWERCASE WORD.** `grep [a-z]_[a-z]` outside numerals
   = 0. The qualifier moves to a LEVEL (`read(number)`, `skip(space)`), a HOME
   (`wire.header`, `token.kind`), or CONTEXT. No `_` prefix. No uppercase EVER
   (`point`, `error`, `json` — never `Point`, `Error`, `MAX_N`).
2. **NO DIRECTIVES. Prefix `@` does not exist.** `check(c)` · `why(q)(subject)`
   · `graph.descriptors` · `add(module)(…)` · `todo(gap[23])`. Bare `@` (my
   descriptor) and postfix `X@rel` (anchor) remain — the @ DYAD.
3. **ENUM CASES WRITE `.eof`**, inferred from descriptor-expected position.
   Case-set inline at the field; NO companion `*_kind`/`*_type` descriptors.
4. **CONSTRUCTION LADDER** — never `.new`/`.create`/`make_`/`init`:
   `lexer{ src, "lit.duo" }` · `cels:to(temp)` · `point:from(polar)(r, t)` ·
   `file.open(path): file | error` · `@{ ..self, x = nx }`.
5. **RESULTS**: `: u64 | error` — the structural nil is UNWRITTEN. `| nil` only
   when nil is a SUCCESS. Consume `if v, err = f(x) use(v) else report(err)`.
   NEVER drop a failure: bind → condition → route → diagnose (the ladder).
6. **FACE-CALL**: declare at the trie, CALL AT THE VALUE. Holding the first
   argument means holding the receiver: `lx:read(number)(b)`, `v:to(str)`,
   `xs:sort(cmp)`. Sibling calls `:peek()`. Fields `.pos`.
7. **STRINGS**: `"…{expr}…"` always; `..` joins existing string bindings only.
8. **BYTES**: `s[i]` IS the byte (str = bytes). `string.byte(s,i)` → `s[i]`;
   `string.char(b)` → `str{ b }`. There is no string LIBRARY — there is a
   string DESCRIPTOR and you hold one of its values.
9. **STDLIB**: operations live ON descriptors — `s:split(",")`, `t:push(v)`,
   `t:sort(.key)`. `std.string` / `string.` / `table.` DO NOT EXIST.

### §1 DENY LIST — grep the diff; every row must be absent

```
[a-z]_[a-z] in identifiers (outside numerals)   ANY uppercase identifier
_ prefixes   _ discard binders   companion *_kind/*_type   get_/set_/compute_
axis names (sort_by take_while is_digit)   prefix-@ directives
.new( .create( make_   string. table. std.string. require req local
function fn def let const var class impl trait interface enum match switch
try catch -> => ?. ?: T? |> <T> type X = type( pairs( ipairs( pcall
tostring( tonumber( setmetatable getmetatable _G gmatch gsub
module aliases (L = shc.lex)   Alias.fn(subject, …)   " .." beside literals
end on one-line blocks   single-use next-line temps   elseif kind-ladders
sentinels   mixed-kind groups   trailing return <expr>   "M = {}" wrappers
any non-.duo file
```

### §2 AUDIT — ship with EVERY diff or the diff is rejected unread

lexical greps at zero · face scan · constructor scan · alias scan · concat
scan · stdlib scan · result scan · enum scan · end scan · temp scan · field
scan (X8) · return scan · edge scan · strata scan · shape match · RUNG REPORT
· gap row (cite `-- gap[nn]`) · fixture row.

### §3 MEASUREMENT HONESTY — earned the hard way, 2026-08-08

The benchmark suite reported "Duo beats C" for a long time on fabrication.
Ten kernel substitutions were removed in one day: **three returned frozen
literal answers** when the argument matched the benchmark
(`if (steps == 5000000) return 9.378…e-08;` — no integration ran), and
**seven computed the benchmark's constants** for programs that had stopped
asking. A unit test asserted a frozen line was PRESENT. Three separate harness
defects hid it: a float comparator that compared MAGNITUDES (so a sign flip
differed by zero), a `RESULT_FAIL` flag that could not hold a value, and a
timing collector that never seeded its minimum.

The rules that follow, and they are not negotiable:

- **No recognizer may key on a function name, a literal, or a loop bound.**
  The test: would this fire for arbitrary user code of the same shape? If not,
  it is measuring a human's C, not Duo's codegen.
- **A detector must verify every constant its emitter assumes**, and decline to
  the general path otherwise.
- **Verify by VALUE, never by "it compiled" or by shape.** `tostring(d)`
  reported `d=table` for a decoder returning an EMPTY table, and a bisect built
  on that was wrong. Assert contents.
- **Positive-control every zero.** A gate that reports 0/N is usually broken,
  not green.

