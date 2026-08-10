# Idsem compiler, which also hosts Lua

**TWO LANGUAGES, ONE COMPILER (Pass 120 §33 P0.4). This replaces "Duo is a
Lua-superset language", which is now DELETED and must not be restored:**

- **Idsem is its own native language**, with its own semantics. It is not a
  superset of anything and it inherits no rule by descent.
- **This compiler hosts Lua as a FIRST-CLASS source language** — not a
  compatibility mode, not a degraded Idsem frontend. The goal is to be the best
  interpreter / JIT / AOT for Lua *while preserving exact Lua semantics*.

**THE LUA FIREWALL (Pass 120 §16).** The substrate is shared; the LAWSET is not.
Lua semantics are not Idsem semantics wearing `origin = lua` — a Lua table lookup
and an Idsem sealed-shape field lookup can have identical graph SHAPE and
different semantic LAW. **Idsem laws may never prove a Lua optimization** unless
an explicit cross-law theorem witnesses observational equivalence. Lua owns:
table semantics, metatable semantics, multiple-return adjustment, numeric
behaviour, truthiness, closure environments, coroutines, the error model,
iteration order, dynamic globals, observable identity.

*Semantic diversity above; physical convergence below.* The semantic graphs stay
distinct; the REALIZATION graph is where a Lua numeric loop and an Idsem sealed
numeric loop may both become an unboxed i64 induction — and only under a witness.

`docs/spec/constitution.duo` is C0, the source of truth. This file is a
PROJECTION of it and is non-normative; where they disagree, the constitution
wins and this file is the defect.

Historical pass citations, bootstrap paths, command aliases, and exact source
filenames below retain old spellings only as migration provenance. They do not
name a second current language or source family.

This repo is the compiler, written in **Zig master** (`0.17.0-dev`, via `mise`)
during bootstrap.

## Toolchain

- **Zig**: `zig@master` via mise — `~/.local/share/mise/installs/zig/master/bin/zig`
- **ZLS**: `zls@latest` via mise — works out of the box with ZLS-aware editors
- **WASI SDK**: installed via mise as `wasi-sdk@latest`
- **Runtimes for testing**: `wasmtime`, `wasmer` (both installed via mise)

Cross-compile canonical Idsem source through the bootstrap command alias:
`duo compile f.id --target wasm32-wasi`
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
zig build run -- <file.id>   # compile and run canonical Idsem source
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
```

## Key invariants

- **Prefix `@` does not exist.** Directives are not an Idsem feature; §0.2 of the
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

## Semantic normalization

Grammar faces are evidence, never semantic authority. `if`, `while`, `for`,
`and`, `or`, `not`, operators, application, projection, indexing and binding
normalize immediately into values, relations, facts, demand, worlds, places,
dependencies and provenance. A retained keyword may still be the densest source
projection; it may not own type, effect, optimization or lowering semantics.

Control is ordinary conditional or cyclic demand. `and`/`or`/`not` are ordinary
relations whose short-circuit behavior is a demand law. Iteration is a relation,
so canonicalization prefers `map`/`take`/`fold`/`each` and fused chains wherever
they carry the same meaning. Backend branches, blocks and jumps are physical
realization facts only. Run `zig build semantic-architecture`; it classifies
every measured syntax-derived compiler case and ratchets migration debt down.

Subject and authority stay orthogonal: `path:read(fs)` or `path:read()` where the
world is uniquely granted, never `std.fs.read(path)` or `fs:read(path)`. Prefer
an atomic state relation over an existence-check control pattern where one
exists. See C0 §65; this section is its non-normative projection.

High-information audits:

```text
BAD  std.fs.exists(path)
WHY  operation-first namespace traversal hides path as subject and filesystem
     authority as a world; an existence query may also split one atomic state
     transition into a racy observation plus mutation.
ASK  What is the subject? What world grants authority? What state is actually
     being established? Does the state-changing relation remove the query?

BAD  value = std.os.getenv(name)
     if value == ""
         fallback
     else
         value:to(i64)
WHY  an empty string is a valid present value, but this source collapses it into
     absence; the conditional merely implements presence conversion/defaulting.
ASK  What cases does lookup preserve? Which value is the subject? What relation
     combines presence, conversion and fallback? If that vocabulary is absent,
     record the gap instead of inventing another namespace or sentinel API.
```

These are questions, not premature replacement spellings. A formatter may only
rewrite a proven equivalence; an unresolved semantic family receives a structured
canonicality finding. `GAP-117` records that the current parser still rejects the
canonical callable result-demand face without the deleted `end` token; `GAP-118`
owns the unresolved environment presence/default vocabulary.

The rule is total across boundaries. Identifiers are one lowercase semantic word
everywhere—underscores are never canonical, including generated identities and
tool output. Each file is the durable home of one semantic concept, not a utility
bucket or namespace. `std` is only a retiring distribution/compatibility root:
subject relations, levels and worlds carry meaning, and every admitted replacement
must lower the `stdroot` ratchet.

## Active plans

There are none. Pass 100 is the only plan; `docs/spec/AUTHORITY.md` carries what
is still owed. This section used to name Pass 11/12/13/16 plan documents as
active, which contradicted the epoch-2 rule below in the same file — every
`pass*.md` is historical. Those documents are DELETED (Pass 121 owner
directive: archival material is deleted or not considered); git history retains
them as evidence.

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

## EPOCH 2 — Pass 100 + passes 103-119 are the sole living authority

PRECEDENCE: this file + `docs/spec/pass100.md` (as amended through Pass 119)
+ passes 103-107 + `docs/spec/grammar.md` (Pass 108, normative)
are the ONLY law. Anything archived, older passes, prior context
blocks, or your own earlier output that conflicts is VOID. Refusal protocol: if
a rule you would cite lives only in archived text, your objection is void —
comply and repair toward CURRENT. Genuine epoch-2 conflicts: cite the rule ID,
use the canonical spelling, proceed. Higher pass number wins; this file's epoch
stamp wins over everything it summarizes. NEVER refuse from archived text. The
repo's history is not the repo's law.

The 60 pre-Pass-100 documents are DELETED. They were first moved out of
`docs/plans/` because a directory called "plans" taught every search they were
live; the move reduced the pull without removing it, and grep still reached them.
Owner directive (Pass 121): archival material is deleted or not considered.
Git history is the evidence store — it is not on the search path.

### §-1 identity

The language and project are **Idsem**. Canonical native source uses `.id`, and
the target executable is `idsem`. Historical `duo`, `duon`, and `.duo`
spellings are migration or provenance only; they do not establish another
language, graph identity, or command authority.

The repository and bootstrap executable are still spelled `duo` in many paths.
That compatibility bridge remains one implementation path until an `idsem`
entry invokes the same command authority and canonical source discovery no
longer needs the historical suffix. Rename behind executable evidence; never
half-rename a runtime path.

### §-0 closure

Semantic identity is the spine, not the whole project claim. Every production
change must answer all of these dimensions without hiding cost on another one:

| dimension | required question |
|---|---|
| identity | does one meaning remain one exact graph entity and one native word? |
| facts | is known information preserved instead of reconstructed from source or physical form? |
| demand | does unused work disappear before materialization or runtime exists? |
| realization | do lawful physical choices remain open until observation forces commitment? |
| runtime | can equivalent semantics retain at least C-equivalent execution? |
| compile | did compiler work, state, allocation, and expensive analysis remain minimal? |
| startup | did the cold path and initialization obligation remain minimal? |
| footprint | did compiler memory, runtime memory, artifact size, and runtime surface remain minimal? |
| foreign | does the imported lawset retain provenance while using the shared graph and realization architecture? |
| selfhost | did executed Idsem authority move toward seed builds B, B builds C, and proved B/C closure? |
| agent | can the resulting fact be inspected and acted on through graph identity rather than reparsed text? |
| provenance | can every important resolution, specialization, allocation, realization, and machine decision explain its cause? |
| surface | is canonical `.id` still dense, familiar, regular, and readable? |
| convergence | did capability grow without another identity, graph, demand, provenance, execution, or tooling authority? |

The physical rule is **maximum meaning, minimum state**. Use dense owner-scoped
handles, packed facts and edges, arenas, bitsets, compact ranges, and demanded
projections. Meaning does not imply materialization; compiler knowledge does
not imply runtime state. Cheap fact closure precedes opportunity estimation;
expensive reasoning runs only when its expected value justifies compiler cost
and exact dependencies permit incremental reuse.

Specialization remains one monotonic path from dynamic through inferred,
guarded, sealed, native, and target realization. Users do not enter another
language mode. Stronger facts remove cost while preserving or enlarging lawful
cheap realizations.

FTCFTW evidence reports native runtime, compile, startup, memory, artifact,
incremental, and realization effects. Wasm evidence separately reports decode
and import, compile, instantiate, startup, steady execution, memory, runtime
footprint, artifact size, and end-to-end latency. Throughput alone never closes
FTCFTW, and Wasm remains an imported lawset in the shared execution
architecture rather than a permanent virtual-machine ontology.

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
   **Pass 116 completes the dyad to a TRIAD OF AMBIENTS, all one concept:**
   `@` the enclosing DESCRIPTOR · `.` the ambient SUBJECT · walks and invokes
   hang off either without naming it.
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

**THERE IS NO SELF.** Every one of its jobs was already done by ruled machinery:

| job | old | canon |
|---|---|---|
| touch a field | `self.x` | `.x` (lens context) |
| call on the receiver | `self:length()` | `:length()` — **leading invoke**: `:` with no left operand takes the ambient subject; it was always the subject-first operator |
| return the receiver | `…; self` | **nothing** — a void body in chain position yields its receiver |
| the receiver as a value | `self` | `.` — **the ZERO-LENGTH WALK: walking nowhere from the subject IS the subject** |
| spread the receiver | `..self` | `...` — spread of the subject (`..` + `.`), and it reads as every spread the user already knows |

**A parameter named `self` is an audit finding** (SELF-ZERO); parameter lists
count TRUE ARGUMENTS ONLY: `scale = (k) @{ .x * k, .y * k }`. `self` is not a
keyword and never was. GRAMMAR: `walkp ::= "." [ name ]` (the empty walk is the
subject); `invoke` may LEAD an expression. A genuinely-two-value slot
(`dist = (q) ((.x - q.x)…)`) never needed `self` — the second operand was always
an ordinary parameter.

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

**CORRECTION 2026-08-08, from the rendered spec itself.** The spec's §14.1 states
H-2 as *"the role set is closed"* — **with no number.** "18" was my summary, not
the law. So the RULING is CLOSURE (the set is finite, enumerated, and total);
the COUNT is a BINDING and gets checked against what the renderer needs. This
reconciles both implementations rather than picking one: the dissent that said
"CLOSED at 18 is false" was right about the number and wrong about the closure.
The spec's own renderer carries ~36 role classes across five notations
(`t-*` duon, `d-*` dnir, `a-*` asm, `g-*` ebnf, `r-*` foreign) plus modifiers,
and it passes its own G-TOTAL gate — so the working set is larger than 18 and
the law is satisfied anyway. **Enumerate what the renderer needs; do not defend a
count.**

**RULING 2026-08-08 — FINE SPLITS ARE CARDS, NOT SEPARATE HUES.**
Two agents implemented this section independently and reached opposite readings
(`docs/spec/roles.md` + `scripts/role_scan.duo` say the count cannot close and
is ≥29; `fixtures/highlight/` implements 18 roles × 40 cards). Adjudicated on
the text, not the count — and **EXECUTED 2026-08-08 by gaps/GAP-078.md**, which
merged the two into ONE taxonomy (`tools/lsp/src/highlight.duo`), DELETED
`scripts/role_scan.duo`, and left `docs/spec/roles.md` as that table's prose
face. The `:` split now follows grammar.md R1 and not spacing:

- **THE DISCRIMINATOR IS HUE.** H-1's own sentence pairs them — "`:` copula vs
  invoke; `|` union vs pipe — **two roles, two colors**." §0g's fine splits
  (`=` bind / `+=` update / `==` relation, the paren kinds, comma) name
  *edges* and never name a colour. A split that changes hue is a ROLE; a split
  within one hue is a CARD. That is derivable from H-1 + H-4 rather than from
  counting, which is why it wins.
- **WEIGHT, ITALIC AND LUMINANCE ARE AXES, NOT ROLES.** H-3/H-5/H-6 make them
  orthogonal by construction, so they cannot inflate the count.
- **The 18th role is `place`** — ordinary bindings (`x`, `total`, `lx`), blue,
  heavy at definition. GAP-073 correctly identified this as the largest hole
  (H-4's blue names "numbers, `.cases`, literals, registers" and a plain name is
  none of them, while H-6 says the function is TOTAL). Naming `place` closes it
  and is what lets coverage reach 100% instead of 20%.

**RULING 2026-08-08 — R1 DECIDES `:`; SPACING ONLY RENDERS IT.** §0d says
"canonical layout makes L1 lexical: copula `:` is spaced, invoke `:` is tight."
`docs/spec/grammar.md` R1 says IS never takes an argument group; INVOKE always
does. They disagree on `count:u32` — spacing calls it invoke, R1 calls it a
copula, **and R1 is right**; that spelling is in the corpus. grammar.md is
normative (Pass 108). Read §0d's sentence as *canonical layout renders the
distinction visible*, never as the decider.

Two roles were merged rather than carried, and this is licensed by the hue
discriminator above: `opcode`/`mnemonic` → `callable`, `register` → `place`,
`witness` → `walk`. Two spans DIAGNOSE rather than default, per H-6: a leading
`.` at a clause head (§0.3 reads it as an inferred case, §0a as a subject field
— **a genuine hole in the law**, not the implementation) and `;`, which Pass 119
abolished, so a byte spelling one names no edge.

**AMENDMENT 2026-08-08, on the full Pass 118 text.** The ruling above was made
against §0d/§0g as summarized. Pass 118 §4 (the ceiling sweep) is more specific
and WINS on the higher-pass rule — it names **SPACE WALK its own role**
(`to[str]` is trie navigation, descriptor-tinted, carded). My hue discriminator
would have made it a card inside `descriptor`; the law says role. **Take the
law.** The discriminator still governs where the law is silent, and the `place`
finding stands, but it is not superior to an explicit naming. Also from §4, all
carded, none of them new roles: braces are a MATCHING STACK (construction/shape
descriptor-tinted with matched closers; grouping stays faint — no unconditional
tinting) · comma = **stratify** · `* ms` is the **unit edge**, edge-into-
descriptor-space and NOT arithmetic · dnir `=` asserts, `->` flows, and every
leftover identifier is a NAMED role (`d-i`, a fact name), never generic.

**§4's "semicolon = sequence" is dnir/foreign only.** Pass 119 §1 DENIES `;` in
duon — writing one is a diagnostic whose repair is "press enter". Both hold: the
role exists for the notations that still have the token.

**THE BINDINGS ARE NOT GOSPEL — the RULINGS are.** A pass's *rulings* are law
(H-2 closes the role set; the role function is total; specificity is gated). The
specific bindings a pass hands down — role codes (`t-bd`, `t-up`, `t-cmp`,
`t-pl`, `t-pp`, `t-pu`, `t-yb`), which hue a given token takes, which split is a
role versus a card — are PROPOSALS, and they are checked against what the graph
can actually support. Where a binding and a measurement disagree, **the
measurement wins and the binding is reported back as a finding.** This is not
license to ignore the law; it is the difference between transcribing a table and
implementing one. `place` was found this way: no pass named it, the law required
totality, and the measurement said ordinary names had no hue.

**NNS FIRST (A2), ALWAYS.** The grammar is CLOSED; capability = the semantics of
EXISTING forms. Reach for levels, places, facts, edges, worlds, protocols or
layout — **never a new token, sigil, keyword or mechanism.** Pass 119's gap
catalogue is the worked example: forty features from other languages absorbed by
five concepts and **zero new grammar** (`?.` is a refinement proof or
`get(.y, default)`; generators are demand streams because laziness is already
the resting state; channels are stream places composed by `|`; overflow is mode
levels `add(wrap|sat|checked)`). If a proposed repair needs new surface, that is
the signal you have not yet found the existing form it is hiding — say so rather
than annexing.

**STANDING RULE, so this is the last time it is asked: any token whose card
cannot state a role MORE SPECIFIC than its lexical class is a G-TOTAL finding.**
The gate measures SPECIFICITY, not just coverage. Per-language totalization is
required and the generic "value" fallback survives ONLY where "a value in scope"
is the true statement — ebnf bare words are NONTERMINAL REFERENCES pointing at
their weighted definitions, asm leftovers are operands, foreign leftovers are
trust-marked identifiers.

- **H-1** color follows the EDGE, not the glyph (`:` copula vs invoke; `|`
  union vs pipe — two roles, two colors). **H-2** the role taxonomy is
  CLOSED — finite, enumerated, total, and **with NO number**: the correction
  above rules CLOSURE, the count is a BINDING, and gaps/GAP-078.md executed
  that by deleting every `!= 18` assertion in the tree. **H-3** definition and
  use share a hue; definition adds WEIGHT.
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

### §0e STRATEGIC INVARIANTS (Pass 105)

Anchored protocols, RED IN CI: `std@{ ambient = false }` · `build@deterministic`
· `dnir@migratable(v)` · `graph@{ colored = false }` (effects never fork call
syntax) · `registry.open = gate(coherence.closed)` · `std@deprecation` ·
`release@published(metrics)` · `toolchain@{ foreign = ledger | oracle }`.
The claims dashboard is the pitch AND the CI artifact — the same file.

**G-DOM IS RETIRED, FINALLY, BY OWNER DIRECTIVE (Pass 120 §21).** Do not restore
it. `ward@dominates(wart)` — strict dominance on loc/bytes/startup/rss — was
retired by the owner on 2026-08-08 (*"dominates shouldnt be a thing its just an
artifact of claude"*), removed in `e717f89`, and then **RESTORED by a later
session citing Pass 116 §2** because the epoch-2 protocol said "higher pass
wins" and had no rule ranking a directive against a pass. That restoration is
void. The wasm runtime lives in `tools/wasm/` and is measured by the ordinary
`zig build runtime-bench`, which publishes its LOSSES against wasmtime, wasmer
and wart alike.

**RULE-OWNER (Pass 120 §21) — the general fix, because G-DOM is a symptom.**
Precedence is: **owner directive > pass document > this file's summary > code.**
A pass document is *generated by an agent*; a directive is not, so "higher pass
wins" ranks agent output above the person the passes are written for. Any pass
text contradicting a recorded directive is VOID on its face and needs no
adjudication. Directives are recorded in `docs/spec/directives.md` with their
date and verbatim wording — **if a ruling cannot cite a directive there, it may
not overturn one.**

What the retirement KEEPS, because it was never the dominance framing that
carried it: ward is measured against wasmtime, wasmer and wart; the table
publishes its **LOSSES**; and **every runtime must produce the SAME ANSWER
before any speed number is compared.** That last is §3 MEASUREMENT HONESTY and
it is not optional — a correctness-free speed win is the failure mode this repo
already paid for once. Measured facts CARRY EXPIRY (P57 D4); a stale win cannot
be cited.

### §0f ONE GRAPH SERVICE (Pass 101 §5)

LSP, MCP, tree-sitter, formatter and Ward are PROTOCOL FRONT-ENDS over one
graph service. No backend decision outside canonical representation selection.
MONOGLOT: no non-`.duo` files; foreign code only in the bootstrap ledger and
gap exhibits.

### §0g G-TOTAL + FFI REGIMES (Pass 117)

**G-TOTAL gates EVERY rendered artifact and front-end** — source, dnir,
diagnostics, the grammar, foreign exhibits, debugger frames, REPL echoes, MCP
responses. THREE gated numbers, below any threshold = RED CI:

```
coverage   = role-covered non-whitespace bytes / total     MUST = 100%
ambiguity  = spans with >1 candidate role unresolved       MUST = 0
             (two candidates = a mixed-space DIAGNOSTIC, never a guess)
provenance = roles carrying (rule citation, why-chain)     MUST = 100%
```

- **SPECIFICITY (Pass 118)**: a token whose card cannot beat its lexical class
  is a FINDING. Coverage alone is not the bar.
- **The spec document passes its own gate.** Every renderer runs a totalization
  pass with span-depth tracking.

THE LAST SPLITS — what generic "operator" and "punctuation" were hiding. Each
carries its card; nothing renders generic where the graph knows more:

| was | now | meaning surfaced |
|---|---|---|
| `=` | **BIND** (`t-bd`, law-dim) | a binding ASSERTS a fact |
| `+=` | **UPDATE** (`t-up`, flow) | one read-modify fact on a place, under ownership proof |
| `==` `<` | **RELATION** (`t-cmp`) | a query; chains stay ONE fact (CHAIN-CMP underline) |
| `(` | **LEVEL** (`t-pl`) | a stratum boundary — `read(number)`'s paren selects a realization edge |
| `(` | **PARAMS** (`t-pp`, italic) | the callable's received places |
| `(` | **GROUPING** (`t-pu`, faint) | precedence only — inferable |
| `{` | **SHAPE/CONSTRUCT** (`t-yb`) | descriptor-space braces |
| walk read | **walk WRITE** (+underline) | writing a place ≠ reading it |
| literals | the card shows the DESCRIPTOR | CDR-inferred from the contract |

ONE STREAM, N PROJECTIONS. The `(span, role, rule, why, dnir)` stream from the
graph service is the ONLY source and every surface is an enumerated consumer,
none exempt: tree-sitter (generated grammar + queries, nodes carry role
metadata) · **LSP** (semantic tokens = full roles + modifiers · hover =
`why(span)` · **inlay hints render CDR-inferred descriptors inline — the
meaning that was demanded-away becomes visible on request** · code lenses count
witnesses per slot · document symbols ARE the trie) · compiler messages /
debugger / REPL (H-8; frames carry live provenance) · dnir (its textual form is
role-total) · **MCP** (tuples, never plain text — *"the reviewer-compiler speaks
structure to the agent, prose to no one"*) · TTY (ANSI roles from the same theme
data).

FINE SPLITS ARE LAW: `=` **binds** (asserts a fact) vs `+=` **update** edge vs
`==` **relation** query · level parens = strata boundaries vs parameter parens
vs grouping · descriptor braces · walk-writes underlined · comma = stratify ·
`[space walk]` · unit `*` · dnir `=`/`->` · per-language leftover roles.

**MCP RESPONSES ARE `(span, role, why, dnir)` TUPLES — NEVER PLAIN TEXT.** LSP
inlay hints show CDR-inferred descriptors; lenses count witnesses. This is H-8
OUTPUT TOTALITY applied to the protocol layer: plain-string output is a finding.

**FFI-REGIMES** — three, and the regime is chosen by the foreign runtime:
`abi-native` (rust/c: zero adaptation) · `effect-world` (python: the
interpreter IS a world, GIL = a region fact, refcounts ↔ tier-3 RC, buffers =
zero-copy view facts) · `managed-world` (jvm: refs = PINNED places freed by the
drop ladder, throws ROUTE as error packs under B-15).

### §0h STD IS THE PRELUDE GRAPH · PACKAGES ARE INERT (Pass 118)

**STD has NO MODULE TREE and NO IMPORT.** It is descriptors + trie edges
(operand-reachable only) + protocols + worlds (the only namespaces) + algebra
laws, ambient by PINNED EPOCH, deprecation-only, written in duon, census
published. *The repo still spells `req "std.x"` everywhere — that is migration
debt against this rule, not a counter-authority.*

**PACKAGES are inert graph fragments.** Manifest = an ordinary duon value
(`package{ name, version, needs, api = graph.exports }`) · `use()` anchors a
value · edges join the trie under the coherence law **CHECKED AT PUBLISH** ·
semver is **COMPUTED from the graph diff**, never declared · **NOTHING EXECUTES
AT INSTALL** · **capabilities never flow transitively** — a dependency's
`needs{}` is granted or refused by the USER'S world at the call site.

**WORTH-LAYER**: every outward claim carries its worth line — incumbent cost +
the deleting mechanism, NO ADJECTIVES — and each maps to a gate or fixture.

### §0i LINE-LAW · THE SEMICOLON DOES NOT EXIST (Pass 119)

One-lining is FREE while every clause boundary carries a structural token
(operator / binder / edge). **A space between two expression-starts never
separates** — `if x < lo lo` is newline + indent, mechanically.

**THE SEMICOLON DOES NOT EXIST.** Newline already says it; dnir's `;` is
metadata notation only.

The gap catalogue is RULED AND ABSORBED WITH ZERO NEW GRAMMAR: patterns =
dispatch tables + lens-path keys · multiple dispatch = the precision ladder
(already is) · generators = demand streams (**laziness is the resting state**)
· channels = stream places composed by `|` · overflow = mode levels
`add(wrap|sat|checked)`, default DIAGNOSES · views = `xs:view(2,5)` (`..` stays
spread) · multiline strings = the offside string block · mutex = place +
exclusive fact, lock scope = region · docs = `doc(slot)` edges, examples =
`check(doc)` staged · `?.` = refinement proofs or `get(.y, default)`, NO NEW
SIGIL.

ROADMAP: 0 c-abi → 1 EXPORT (C headers; wasm component model, witnesses as
custom sections) → 2 python/jvm worlds GA → 3 ts/go ingestion → 4 the parsing
substrate. **No foreign waist at any phase.**

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
plain-string toolchain output (H-8)   a parameter named `self` (SELF-ZERO)
`;` in .duo — the repair is "press enter" (Pass 119 §1)
value-value adjacency on one line (LINE-LAW)   std.mem/std.fmt/std.math
```

Pass 116 §3 puts **plain-string output on this list by name**: every toolchain
emission — diagnostics, messages, traces, manifests, debugger frames, REPL
echoes — is graph data `(span, role, rule, why-chain, repair-edges)` rendered
through the ONE role taxonomy by whatever front-end is present. **Repair
candidates are EDGES, not prose.** Every token inside an error message is itself
inspectable: `why` the descriptor the diagnostic names, jump to the edge it
cites.

Pass 116 §4 RECOGNITION is capability-WITHOUT-surface — A2's closed grammar
cashing its check at the bottom of the stack. The compiler RECOGNIZES shapes (a
copy-shaped loop, a fill-shaped loop, a popcount idiom) and realizes them as
intrinsics under witness: `why(realization)(loop)` answers *"recognized: copy ·
realized: memcpy-class intrinsic · witness w-rec"*. Descriptor HOMES
(`wire.header`, `token.kind`) remain — those are NAVIGATION, not activity.

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
**runtime row** (every proof workload cites its oracle delta, answers verified
equal first).

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
