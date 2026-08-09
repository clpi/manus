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
| `x86_64-windows` · `wasm32-wasi` | **PASS** as of 2026-08-08 — GAP-040 closed |

Both used to fail for one reason: `src/duo_lexer_tokenize.c` is a tracked,
generated artifact that `build.zig` links into every build, and it was generated
on macOS, so its prelude froze with the POSIX arm taken. The generator now emits
the UNION of the arms under `#ifdef __wasm__` / `#elif defined(_WIN32)` /
`#else`, so the arm is chosen by the compiler that consumes the file rather than
by the target the generator was pointed at. **Regenerate the artifact whenever
you change the prelude emitter or `lib/std/compiler/host.duo`** — editing
`lib/std/compiler/lexer.duo` alone does nothing, the compiler links the
generated C:

```bash
duo compile lib/std/compiler/host.duo --backend=c --lib -o /tmp/h.o
cp /tmp/duo_host.c src/duo_lexer_tokenize.c   # the C is a side effect in /tmp
```

then re-run both lexer differentials and `agent-smoke`.

The direct ARM64 Mach-O backend being macOS/aarch64-only is BY DESIGN and was
never what a row failed on — every non-native target builds through the C
backend.

Building is not running. `wasm32-wasi` links and `duo check` answers correctly
under wasmtime, but it needs `--dir` preopens (without them WASI answers errno 8
= EBADF at startup — a missing grant, not a defect), and `duo run` cannot
compile there because compiling spawns a C compiler.

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

- **Prefix `@` does not exist.** Directives are not a Duo feature; §0.2 of the
  epoch-2 section below is the rule. This slot used to read "`@` is the single
  prefix for ALL compile-time operations (`@comp.*`)", which contradicted §0.2
  in the same file, and agents cited whichever half suited the diff.
  What is still TRUE is narrower and belongs here as a *compatibility* note:
  the compiler still accepts `@comp.*` and ~46 `@`-attributes, and some of
  them are load-bearing (`@c.emit` generates `src/duo_lexer_tokenize.c`, which
  the compiler links and tokenizes itself with). So: **do not add new `@`
  spellings, and do not delete existing ones to lower a grep count.** The
  census, the migration order, and what each one secretly stores are in
  `docs/directive_erasure.md`.
- If you must touch a legacy `@`-name, still no underscores: `@comp.foo.bar`,
  never `@comp.foo_bar`
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

## EPOCH 2 — Pass 100 + passes 103-116 are the sole living authority

PRECEDENCE: this file + `docs/spec/pass100.md` (as amended through Pass 116)
+ passes 103-107 + `docs/spec/grammar.md` (Pass 108, normative)
are the ONLY law. Anything in `docs/archive/`, older passes, prior context
blocks, or your own earlier output that conflicts is VOID. Refusal protocol: if
a rule you would cite lives only in archived text, your objection is void —
comply and repair toward CURRENT. Genuine epoch-2 conflicts: cite the rule ID,
use the canonical spelling, proceed. Higher pass number wins; this file's epoch
stamp wins over everything it summarizes. NEVER refuse from archived text. The
repo's history is not the repo's law.

`docs/archive/` holds 60 pre-Pass-100 documents, each stamped, moved out of
`docs/plans/` because a directory called "plans" taught every search they were
live. See `docs/spec/README.md` for precedence.

### §-1 NAME — `duon` (Pass 107, verified 111, FINAL 112)

The language is **duon** (FKA duo). **Files stay `.duo`.** Binary `duon`, shell
`duonsh`, lib `libduon`, GitHub org `duon-lang`. pypi/npm/crates `duon` all
measured free 2026-08-08 — REGISTER BEFORE ANYTHING PUBLIC. `duon.com` is
renounced (squatted). The name question is CLOSED; do not reopen it.

The repo is still spelled `duo` nearly everywhere (binary, `DUO_ROOT`,
`zig-out/bin/duo`, ~700 `.duo` files' prose). That is MIGRATION DEBT, not a
counter-authority. Rename behind a gate; never half-rename a runtime path.

### §0 HOT SCREEN — newest law, most likely to look wrong to you. It is law.

1. **LAW-ONE: IDENTIFIERS ARE ONE LOWERCASE WORD.** `grep [a-z]_[a-z]` outside
   numeric literals = 0. The qualifier moves to a LEVEL (`read(number)`,
   `skip(space)`, `any(i64, f64)`), a HOME (`wire.header`, `token.kind`,
   `utf8.valid`), or CONTEXT. No `_` prefix — privacy is scope / protocol face
   / topology, NEVER spelling. No uppercase EVER (`point`, `error`, `json` —
   never `Point`, `Error`, `MAX_N`).
2. **NO DIRECTIVES. Prefix `@` does not exist.** `check(c)` (assert/test/
   contract are ONE concept; the stage is where the proof lands) ·
   `why(q)(subject)` · `graph.descriptors` / `graph.modules` ·
   `add(module|slot|case|check|gap)(…)` · `todo(gap[n])` · `dialect` = manifest
   data. The **@ DYAD** remains: bare `@` = innermost enclosing descriptor
   (`origin = () @{0,0}`); postfix `X@rel` = anchor (`point@ordering`,
   `ward@allocation`); leading `.` = walk from the anchor.
3. **INFERRED CASES**: `tok.kind == .eof` · `token{ kind = .eof }` ·
   `s: shape = .circle(3.0)`. Case-sets INLINE at the field
   (`kind: { name, number, eof }`); NO companion `*_kind`/`*_type` descriptors.
   Literal unions ONLY for wire strings: `method: "get" | "post"`.
4. **CONSTRUCTOR LADDER** — `.new`/`.create`/`make_*`/`init` are BANNED:
   (a) `desc{…}` · (b) conversion edges `x:to(desc)` · (c) `from(mode)` LEVELS
   (`point:from(polar)(r,t)` ≡ `polar{r,t}:to(point)`) · (d) action-named
   acquisition (`file.open`, `task.spawn`). `from_polar`, `of_hex`, `new_ms`
   are LAW-STRATA-2 violations.
5. **FACE-CALL**: declare at the trie **operation-first** (`read(number) =
   (lx,b)…`); CALL AT THE VALUE **subject-first**, MANDATORY:
   `lx:read(number)(b)`, `v:to(str)`, `xs:sort(cmp)`. **ALIAS-CALL is banned**:
   `L.next(lex)` → `lex:next()`. Op-first at call sites ONLY as callable-value
   in pass position (`map(to(str))`) or world actions (`sh(cmd)`, `print(x)`).
   If you are holding the first argument, you are holding the receiver.
6. **RESULTS**: the union is `t | error` — structural nil is UNWRITTEN (B-12).
   CDR (B-13): a declared contract directs realization; restated conversions
   ERASE. OBLIGATION (B-14): an unconsumed failure position DIAGNOSES — bind,
   route, or drop BY NAME; silent loss is unexpressible. DEMAND-ROUTE (B-15):
   inside a declared failure contract an unbound failure position routes and
   early-exits with the pack (`tok = lx:token()`). **Zero forwarding plumbing
   exists in duon** — no `if err return nil, err`, EVER.
7. **LAYOUT**: offside, canonical, verified rendering. **`end` is DELETED**
   (accepted-and-removed under the retirement gate only). A body is an
   expression sequence; its value is its final expression's; demand alone
   materializes (DEMAND-RETURN); in `:`-chain position a void realization
   yields its RECEIVER (chain threading).
8. **STRINGS**: interpolation `"{x}"` always. No concat + `to(str)` chains. No
   Lua string idioms (`string.byte` etc.) — `scan`/`take`/`until` families.
   `s[i]` IS the byte (str = bytes); `string.char(b)` → `str{ b }`.
9. **THE CALLABLE is one concept**: a closure is a non-empty world-fragment;
   function and table unify on the ENUMERABILITY axis. `and`/`or` are
   operand-returning — re-justified, not inherited from Lua.

### §0a SELF-ZERO · CHAIN-CMP · RECOGNITION (Pass 115-116)

**THERE IS NO SELF.** `.x` reads the subject's fields · leading `:name()`
invokes on it · a void body in chain position RETURNS it · bare `.` is its
value · `...` spreads it. **A parameter named `self` is an audit finding**;
parameter lists count TRUE ARGUMENTS ONLY.

**CHAIN-CMP**: `a < b < c` is ONE fact — a conjunctive chain with a single
evaluation of shared operands. `(0 < x) < 10` is a mixed-space diagnostic.

**NO COMPREHENSION SYNTAX, EVER.** The demand pipeline IS the comprehension:
`xs:take(odd):map(f)` fuses, streams, and never materializes unless demanded;
nested = join.

**RECOGNITION**: no `std.mem` / `std.fmt` / `std.math`. Pure ops are VALUE
EDGES (`x:abs()`, `s:copy()`); **worlds are the only capability namespaces**.
Idiom recognition lowers to intrinsics UNDER WITNESS — `why(realization)`
answers. (Measured 2026-08-08: `math.` appears in 79 `lib/std` files, and the
capability scan's `rand` class is 50 `math.random(` sites. That is the debt.)

**FAMILIARITY LAW**: every surface must explain itself through reflexes the
reader already has; only foreign source may feel foreign — and it is italic.

### §0c MEMORY · BORING RULINGS · SHELL (Passes 107, 110)

**MEMORY (DECIDED — the E1 bridge is retired).** tier 1 PROVEN DROPS (static
frees under ownership/last-use facts) · tier 2 REGIONS (effect-scoped arenas,
bulk free, allocation-free steady states PROVABLE) · tier 3 MANAGED RC
(precise counts only where sharing facts require; Perceus-class elision/reuse;
cycles = deferred trial-deletion confined to cycle-POSSIBLE shapes).
**NEVER a tracing stop-the-world collector — latency is a language property.**
Weak refs are non-owning places with invalidation facts (they read `t | nil`,
honestly). Finalization is deterministic at last drop. `why(free)(x)` explains
every deallocation.

**BORING RULINGS.** Keyed deterministic hashing (SipHash-class, key = a world
fact) · **NO PANICS** (diagnose / route / FAULT = world teardown; `abort` is a
capability) · metered recursion depth routed as `error.depth` · shortest-
round-trip float rendering. *Measured 2026-08-08 and CONTRADICTED: non-tail
recursion SIGSEGVs, and floats render 17 digits. Both are open.*

**SHELL.** Shell scripts ARE duon scripts — **never emit bash**. `sh "cmd" |
grep("x")` pipes stream by demand; a failing command's unconsumed failure
DIAGNOSES (B-14); env is a world; `ls():to(seq(entry))` types output; glob is
a function; job control is task scopes (leaving the scope reaps).

### §0d HIGHLIGHTING IS A PROJECTION OF THE GRAPH (Passes 113-115)

THEME: **github dark (Primer)**, role-mapped — the canonical docs/site theme.

- **H-1** color follows the EDGE, not the glyph (`:` copula vs invoke; `|`
  union vs pipe — two roles, two colors). **H-2** the 18-role taxonomy is
  CLOSED. **H-3** definition and use share a hue; definition adds WEIGHT.
- **H-4** hue = semantic SPACE: red law (keywords + copula `:`) · orange
  descriptor (+ `@` + union edges) · purple callable (+ invoke `:` + world
  actions italic + dnir opcodes + asm mnemonics) · blue value-at-rest (numbers,
  `.cases`, literals, registers) · green data-flow (field walks, pipes,
  witness refs).
- **H-5** weight = DEFINITION everywhere; italic = AMBIENT/FOREIGN — **all
  foreign source is italic; the trust boundary is typographic.**
- **H-6** the role function is TOTAL: every character has a role; luminance =
  surprisal (faint = inferable, never absent). **H-7** every (span, role)
  carries a rule citation + dnir correspondence; `why(span)` IS the LSP hover;
  provenance maps are bidirectional DATA. **H-8 OUTPUT TOTALITY**: every
  emission (diagnostic, trace, manifest, debugger frame, REPL echo) is graph
  data rendered through the role taxonomy — **plain-string output is a
  finding**; repairs are edges.

Canonical layout makes L1 lexical: copula `:` is SPACED (`x: f64`), invoke `:`
is TIGHT (`lx:read`). `highlights.scm` and the LSP legend are **GENERATED**
from the graph service — hand edits are an H-1 drift finding. The golden token
corpus (`fixtures/highlight/*.duo` + `*.roles`) convicts any front-end that
diverges.

### §0e STRATEGIC INVARIANTS + DOMINANCE (Passes 105, 116)

Anchored protocols, RED IN CI: `std@{ ambient = false }` · `build@deterministic`
· `dnir@migratable(v)` · `graph@{ colored = false }` (effects never fork call
syntax) · `registry.open = gate(coherence.closed)` · `std@deprecation` ·
`release@published(metrics)` · `toolchain@{ foreign = ledger | oracle }`.
The claims dashboard is the pitch AND the CI artifact — the same file.

**G-DOM**: `ward@dominates(wart)` on loc / bytes / startup / rss — STRICT, red
in CI on regression, published each release. **Every proof workload gets a
dominance row against its oracle.**

### §0f ONE GRAPH SERVICE (Pass 101 §5)

LSP, MCP, tree-sitter, formatter and Ward are PROTOCOL FRONT-ENDS over one
graph service. No backend decision outside canonical representation selection.
MONOGLOT: no non-`.duo` files; foreign code only in the bootstrap ledger and
gap exhibits.

### §0b THE DESCENT IS DUO TO THE BYTE (Pass 103 — NO FOREIGN WAIST)

```
graph → realize → flow → lower(target) → encode(target) → encode(elf…) → link
```

all DNIR, all family edges. The ISA is **descriptors with layout facts**;
registers are **places**; the linker is **graph merge**. **NO C intermediary, NO
LLVM, no runtime host.** Foreign compilers are **CI ORACLES ONLY**; emitting
C/TS is an interop **EXPORT**, never a stage. **Performance work is edge
ADMISSION — propose, prove (legality data + witness), measure (Ward delta);
never hand-tune without a witness** (Pass 104).

**Why the descent is weeks-class, not decades-class (Pass 104).** Their
optimizer INFERS; ours READS. The incumbent decades went to four sinks: semantics
archaeology (alias/UB/idiom/devirt — reconstructing facts the source discarded;
Duo never discards them, so it is not a task), mutable-IR pass coupling
(N passes × M invariants × K targets; here a transformation is an edge with its
legality as DATA, so multiplicative becomes additive), the compatibility museum
(dialects × flags × legacy — not maintained faster, NOT BUILT), and serial human
lore (the one that remains, and it becomes search under gates: a peephole is an
edge-shaped, law-bounded, oracle-checkable unit — **Duo is an admission gate
with a language attached**). The falsifier is
**REWRITES-ADMITTED-PER-WEEK** (G-D5): if that number is low the thesis is
wrong and the ledger must say so.

What this means for THIS repository, concretely:

- `--backend=direct` is not an alternative backend, it IS the path. The native
  census measures ATTAINMENT, not an optimization; 100% is the fixed point.
- `--backend=c` as a FALLBACK mid-compile is the foreign waist by name.
  `emitReqModuleC` + `directLinkInputs` (compiling `req`'d modules to C objects
  and linking them) are that waist; `spliceReqModules` — absorbing a module into
  the program's own native object — is the aligned repair and should grow until
  the C path is unnecessary.
- The differential harness comparing `--backend=direct` against `--backend=c`
  is EXPLICITLY LICENSED (Pass 103 §5): C is the oracle, test equipment, never
  the shipping path. `zig build abi-matrix` and the native differential stay.
- `src/*.zig` is the bootstrap ledger (G9), the licensed exception with a
  termination condition. It shrinks toward the fixed point; it is not a
  violation.

### §0g G-TOTAL · REGIMES · STD-GRAPH · PKG-GRAPH · LINE-LAW (Passes 117-119)

**G-TOTAL** gates EVERY rendered artifact and front-end — docs, tree-sitter,
LSP, TTY, dnir, diagnostics, MCP: role coverage = **100% of non-whitespace
bytes** · unresolved-ambiguity spans = **0** (two candidates is a mixed-space
diagnostic, never a guess) · every role carries rule + why-chain. Fine splits
are law: `=` BINDS (asserts a fact) vs `+=` UPDATE edge vs `==` RELATION query;
level parens vs parameter parens vs grouping; walk-writes underlined. MCP
responses are `(span, role, why, dnir)` tuples — **never plain text**. G-TOTAL
also measures SPECIFICITY: a token whose card cannot beat its lexical class is a
finding.

**FFI-REGIMES**: abi-native (rust/c — zero adaptation) · effect-world (python —
the interpreter is a world, GIL = region fact, refcounts ↔ tier-3 RC, buffers =
zero-copy view facts) · managed-world (jvm — refs are PINNED places freed by the
drop ladder, throws ROUTE as error packs under B-15).

**STD IS THE PRELUDE GRAPH** — no module tree, no import. Descriptors + trie
edges (operand-reachable only) + protocols + worlds (the only namespaces) +
algebra laws, ambient by pinned EPOCH, deprecation-only, written in duon, census
published.

**PACKAGES ARE INERT GRAPH FRAGMENTS**: the manifest is an ordinary duon value;
`use()` anchors a value; edges join the trie under the coherence law CHECKED AT
PUBLISH; semver is COMPUTED from the graph diff; **NOTHING EXECUTES AT INSTALL**;
capabilities never flow transitively — a dep's `needs{}` is granted or refused by
the user's world at the call site.

**WORTH-LAYER**: every outward claim carries its worth line — incumbent cost +
the deleting mechanism, no adjectives — each mapping to a gate or fixture.

**LINE-LAW**: one-lining is free while every clause boundary carries a structural
token (operator / binder / edge); a space between two expression-starts
(`if x < lo lo`) NEVER separates — newline + indent, mechanically.
**THE SEMICOLON DOES NOT EXIST** (Pass 119; this RETIRES Pass 100 §4's
"one-line induction tail", and §4 is amended in the same commit).

Gap catalogue absorbed with ZERO new grammar: patterns = dispatch tables +
lens-path keys · multiple dispatch = the precision ladder · generators = demand
streams (laziness is the resting state) · channels = stream places composed by
`|` · overflow = mode levels `add(wrap|sat|checked)` · views = `xs:view(2,5)` ·
multiline strings = the offside string block · mutex = place + exclusive fact ·
docs = `doc(slot)` edges · `?.` = refinement proofs or `get(.y, default)`, no new
sigil.

**Roadmap**: 0 c-abi → 1 EXPORT (C headers; wasm component model, witnesses as
custom sections) → 2 python/jvm worlds GA → 3 ts/go ingestion → 4 the parsing
substrate. **No foreign waist at any phase.**

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
sentinels   mixed-kind groups   trailing return <expr>   ANY `;`
plain-text MCP/diagnostic output (H-8, G-TOTAL)   std module tree / import   "M = {}" wrappers
C-as-intermediary   LLVM-as-dependency   runtime-hosted execution
any non-.duo file
```

### §2 AUDIT v4 — ship with EVERY diff or the diff is rejected unread

**THE AUDIT RUNNER IS `zig build audit100` (`scripts/audit100.duo`).** Pass 116
§7 spells it `duon_audit.py`; that spelling is void twice over by this file's
own law and is recorded here rather than obeyed: a `.py` file contradicts §0f
MONOGLOT ("no non-`.duo` files"), and `duon_audit` contradicts §0.1 LAW-ONE
(`[a-z]_[a-z]` = 0). The canonical spelling of the runner's name is one word.
Per the epoch-2 protocol: rule cited, canonical spelling used, proceed. The
requirement it carries — **nonzero exit blocks the commit** — is law and is in
force.

New v4 rows, additive to v3: **self scan** (a parameter named `self` is a
finding, §0a) · **recognition scan** (`std.mem`/`std.fmt`/`std.math` and bare
`math.` = findings) · **role scan** (plain-string output is an H-8 finding) ·
**dominance row** (every proof workload cites its oracle delta, G-DOM).

lexical greps at zero · uppercase 0 · prefix-@ 0 · face scan (receiver forms,
ARG-1) · constructor scan (ladder) · alias scan · concat scan · stdlib scan ·
result scan (B-12) · enum scan · end scan · temp scan (TMP-1) · field scan (X8)
· return scan · edge scan · strata scan · shape match · RUNG REPORT · gap row
(cite `-- gap[nn]`) · **capability scan** (`std@{ ambient = false }` — Pass 105
U1, effective immediately: no std module gains ambient fs/net/clock/rand reach.
RUN IT: `zig build capability-scan`, which ratchets. Measured 2026-08-08 at
878e0d1: **278 ambient sites across 53 of 257 modules**, not the 46 gap[061]
recorded — that grep missed `math.random(` entirely, missed `net`'s bodyless
declarations, and could not see the libc inside `@c.emit` payloads. gap[061]) ·
fixture row. Every ruling
regenerates THIS FILE in the same commit — a ruling without regeneration is
unshipped.

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
  the general path otherwise. This is the RULE, not the state: measured
  2026-08-08, **46 `use_*` flags reach codegen and 7 carry a `verify_*`**.
  Known-unverified include `use_dot_product_identity` (emits n(n+1)(n+2)/6
  verifying NOTHING about the fill -- the identical defect that made
  `detect_binary_search_dense` answer 200000 where C answered 100000),
  `use_xor_fold_inline` (0 of 1 constants), `use_filter_count_mod` (1 of 3), and
  `detect_naive_fib_pattern`, whose `is_fib_call` requires the callee to be
  SPELLED `fib` -- keying on a function name, which rule 1 above forbids
  outright. Inventory in docs/RELEASE_STATUS.md. Treat any `use_*` row as
  suspect until its detector is read.
- **Verify by VALUE, never by "it compiled" or by shape.** `tostring(d)`
  reported `d=table` for a decoder returning an EMPTY table, and a bisect built
  on that was wrong. Assert contents.
- **Positive-control every zero.** A gate that reports 0/N is usually broken,
  not green.

