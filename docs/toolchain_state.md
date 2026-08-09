# Toolchain state — audit against Pass 101 §3

**Status:** measured audit, 2026-08-08. **Audience:** anyone sequencing the
"one graph service, N protocol front-ends" work.

Pass 101 §3 (`docs/spec/pass100.md:551-558`) rules that the whole toolchain is
ONE program:

> one graph service, N protocol front-ends — a single `duo` toolchain owning the
> graph store, query engine, witnesses, canonicalizer; LSP = queries (hover=why,
> references=dependents, diagnostics=the audit), MCP = the same queries + the
> `add` family, tree-sitter = a generated grammar projection (output, never
> authored), fmt = the canonicalizer's face, Ward = the in-repo proof
> application. Sequencing: graph core → fmt → LSP read-only → MCP → tree-sitter
> → Ward, each stage dogfooding the last.

## Method — what was actually run

Everything below is either a file citation or a command whose output is quoted.
Commands run against `zig-out/bin/duo` (17 MB, built 2026-08-08 02:56):

- `duo graph <file>` on a 9-line probe — output quoted in §3.1.
- `duo check --plain-diagnostics` on all 8 tool sources — all 8 clean (§1.3).
- `duo run tools/lsp/build.duo` — builds `tools/lsp/duo-lsp` (387 KB).
- `duo run tools/lsp/test/smoke.duo` — quoted in §2.4.
- `duo explain`, `duo fmt`, `@comp.catalog()` — reachable, quoted inline.

Not run: the MCP servers end-to-end (they block on stdin), and `tree-sitter
generate`. Claims about tree-sitter are read off `grammar.js` rules, not a parse.

## 0. Verdict

**The graph service that Pass 101 asks for largely EXISTS, in Zig, and no
front-end uses it.** `duo graph` already emits, as JSON, exactly the facts
hover/definition/references/documentSymbol need — per-node kind, name, `line`,
`col`, `stable_id`, call shapes, table/enum shapes. The LSP does not call it
once. The MCP calls it once, for one tool. Both then re-derive the same facts
with line scanners and `string.find` over compiler *text* output.

So the dominant gap is not "build a graph store". It is **stop re-deriving**.
Four of the six components are closer to Pass 101 than the plan assumes; the two
that are furthest (tree-sitter, the canonicalizer) are furthest for a reason the
repo has already written down and filed.

## 1. Component table

| Component | What exists today | What Pass 101 requires | The specific gap | Smallest next step |
| --- | --- | --- | --- | --- |
| **Graph store + query core** | `src/semantic_graph.zig` (1877 L): 16 `NodeKind`s (`:48-67`), 7 `EdgeKind`s (`:69-77`), `SpanRef{file,start,end}` (`:79-83`), per-node `why` (`:99`), `stable_id`, `semantic_fingerprint`. Queries: `findByName` (`:213`), `usersOf` (`:222`), `defsOf` (`:230`), `containingFuncId` (`:889`), `findCallsByCallee` (`:875`). `src/graph_query.zig` (187 L) header already reads *"bounded facts for compiler, LSP, and MCP projections"* (`:1-3`). `duo graph <file>` (`src/main.zig:689`, `do_graph` at `:1484`) emits it as JSON; `--write` persists `.duo/graph/<stem>.json` (`semantic_graph.zig:1443`). | The single service every front-end queries. | Three real holes, all small: (a) **one file per invocation** — no workspace/multi-file lift, so cross-file references are impossible from the graph; (b) **`param` nodes carry no span** — measured: every `param` emits `"line":0,"col":0` (§3.1), so definition-on-a-parameter cannot work; (c) **no socket/daemon** — every query is a process spawn + full reparse. `graph_query.zig` is imported only by `pass22_gate.zig`, `region_graph.zig`, `tests.zig` — **no front-end imports it.** | Give `param` nodes their real span in `liftFunctionBindings`, then have the LSP call `duo graph` for `documentSymbol` and delete `scan_symbols_lo`. Daemonising can wait; a spawn per save is already what `run_check` does. |
| **Canonicalizer / fmt** | `duo fmt` works (`src/main.zig:903` → `src/pretty.zig`, 1171 L). Duo-side seed `lib/std/compiler/fmt.duo` (56 L) applies **exactly one rule** — file ends in one newline — and says so at `:18-26`, having deliberately REMOVED tab expansion and trailing-space stripping because the fixpoint negative control showed they edit data. | fmt = the canonicalizer's CLI face; L2 structural erasure (MOD-1, faces, `end`/ceremony deletion) *applied, not reported*. | `duo fmt` is a **pretty-printer, not a canonicalizer**: it does not apply MOD-1, does not rewrite `..` chains, does not touch the `fun` keyword it emits a hint about. The two halves are also unconnected — `pretty.zig` and `fmt.duo` share no rule set. Matrix row SH-05 (`src/selfhosting_matrix.zig:75-82`) still says `duo_impl = null` and `host_impl = "src/fmt.zig"`; **`src/fmt.zig` does not exist**. | Fix the SH-05 row to name `src/pretty.zig` + `lib/std/compiler/fmt.duo`, then move ONE rule that the compiler already diagnoses (`hint: 'fun' is unnecessary here` — reproduced §1.3) from hint to rewrite, behind `duo fmt --canonical`. One rule, one fixpoint proof, per `fmt.duo`'s own discipline. |
| **LSP (read-only: hover / why / diagnostics)** | `tools/lsp/src/server.duo` — 2343 L of pure Duo, builds to a 387 KB self-contained binary. Implements 12 LSP methods (dispatch `:2274-2319`): initialize, didOpen/Change/Close/Save, documentSymbol, hover, definition, references, rename, foldingRange, documentHighlight, workspaceSymbol, completion. Diagnostics shell out to `duo check --plain-diagnostics` on a temp file (`:1358`) and text-parse the result (`:1190-1338`). | Hover = `why`; references = dependents; diagnostics = the audit. All of it graph queries. | **The entire symbol layer is a parallel implementation.** `scan_symbols_lo` (`:601-694`) is a line-oriented keyword scanner; `find_refs_in_text` (`:727-787`) and `find_rename_edits_in_text` (`:790-850`) are **byte-identical word-boundary scanners differing only in what they append** — 120 duplicated lines, in one file, doing what `semantic_graph.usersOf` does. Hover (`:2064-2096`) returns the raw declaration LINE as a string; the graph's `why` field is never read. `scan_workspace` (`:1413-1452`) shells out to `find ... \| head -200` and re-scans up to 200 files by hand. | Replace `handle_document_symbol` with a `duo graph` call. It is the smallest possible dogfood: the JSON already carries `name`/`kind`/`line`/`col` for every func, and it deletes the largest hand-written scanner. Do this before touching hover. |
| **MCP (same queries + `add`)** | `tools/mcp/duo_lsp.duo` (760 L, 32 tools) and `tools/mcp/duo_bench.duo` (540 L, 33 tools) over `tools/mcp/duo_shared.duo` (998 L). ~20 shared functions are already thin projections that shell to the compiler's own control plane: `duo dev claim/session/integration`, `duo semantic claims/preview/validate` (`duo_shared.duo:138-200`). | The same queries as LSP, plus the `add` family. The agent surface IS the emission API. | (a) **16 of 33 tools are registered in BOTH servers** (§2.1) and both are configured simultaneously — the agent sees each twice. (b) **`META_CATALOG` is a hand-copy** (`duo_lsp.duo:13-54`, 40 entries) of `src/meta_module.zig`, which owns **174 distinct `comp.*` paths** across 627 alias rows — 23 % coverage, and the file's own comment at `:12` says *"should be auto-generated"*. (c) Diagnostics are text-parsed **twice inside one file** — `duo_diagnostics` (`:64-85`) and `duo_compile_check` (`:96-115`) are the same code, and neither passes `--plain-diagnostics`. (d) No `add` family at all — every tool is read-only or a gate runner. | Delete the 16 duplicates from one server (bench keeps the gates, lsp keeps the language surface). Then replace `META_CATALOG` with a `@comp.catalog()` call — verified reachable: `duo run` on a file calling `print(@comp.catalog())` compiles and runs clean. |
| **tree-sitter** | `ext/tree-sitter-duo/grammar.js` — **804 lines of hand-authored JavaScript**, last touched 2026-07-12. Header line 7: *"Based on the lexer tokens from src/lexer.zig and AST from src/ast.zig."* Generated `src/grammar.json` (87 KB) is committed. | A GENERATED artifact projected from grammar descriptors. Output, never authored. | Hand-maintained, and **already wrong** — see §4. It is also the only non-Duo, non-generated source in the toolchain, so it is a live MONOGLOT violation. The compiler has already filed this: `src/pass21_catalog.zig:68` — *"P21-G13 parser/formatter/treesitter/LSP/MCP grammar agreement — status: open"*. | `duo grammar emit` following the **existing two-instance precedent**: `duo token-tables emit` and `duo wasm-tables emit` (`src/main.zig:814-844`) already project Zig descriptors into checked-in artifacts. Emit `grammar.js` from `src/pass21_keyword_registry.zig` + the parser's rule set the same way. |
| **Ward** | `tools/wasm/` — 6791 L of Duo. Working WASM runtime; `hash.wasm` in 0.45 s JIT vs wasmtime 0.436 s (`tools/wasm/HANDOFF.md:249-256`). | The in-repo proof application, built on the finished loop. | Ward is ahead of the loop it is supposed to prove, not behind it — see §5. Its ARM64 emitter is a **donor for SH-11**, and the stated reason it was not one has expired. | See §5. |

## 2. Duplication ledger

### 2.1 MCP tools registered twice

`duo_bench.duo` registers 33 tools, `duo_lsp.duo` registers 32. Sixteen are the
same name in both:

```
duo_agent_canonical_index   duo_agent_gaps_update    duo_agent_session_start
duo_agent_smoke             duo_audit_metaprogramming_smokes
duo_audit_native_boxing     duo_directive_hierarchy_read
duo_file_finding            duo_foreign_import_preview
duo_grammar_spec_read       duo_grammar_spec_update
duo_pass5_catalog           duo_pass6_catalog        duo_repo_tooling
duo_semantic_snapshot       duo_session_log
```

Both servers are configured at once (`~/.claude/settings.json` → `duo-bench`,
`duo-lsp`), so 16 tool names are ambiguous at every agent session start. This is
ONE EDGE violated inside the surface whose whole job is to be the one edge.

### 2.2 Diagnostics parsed in three places, from text

| Site | Input | Passes `--plain-diagnostics`? |
| --- | --- | --- |
| `tools/lsp/src/server.duo:1190-1338` | `duo check --plain-diagnostics` | yes (`:1358`) |
| `tools/mcp/duo_lsp.duo:64-85` (`duo_diagnostics`) | `duo check` | **no** |
| `tools/mcp/duo_lsp.duo:96-115` (`duo_compile_check`) | `duo check` | **no** |

The last two are the same code in the same file under two tool names. Both split
on `:` with `string.gmatch(line, "[^:]+")`, so any message containing a colon —
or any absolute path on a machine where a directory has one — mis-slices. The
LSP's parser is the only one that handles severities and the legacy debug form,
and it is 148 lines that a structured `--json-diagnostics` flag would delete
entirely.

### 2.3 Symbol resolution, re-implemented

| Fact | Compiler owns it | Front-end re-derives it |
| --- | --- | --- |
| top-level symbols + kind + position | `semantic_graph.liftModuleFull` → `duo graph` JSON | `server.duo:601-694` line scanner |
| references / dependents | `semantic_graph.usersOf` (`:222`) | `server.duo:727-787` word scanner |
| call sites / callees | `graph_query.calleesOf` (`:18`), `callsIn` (`:44`) | not used at all |
| rename edit set | same `usersOf` | `server.duo:790-850` — *identical scanner, different append* |
| document highlight | same | `server.duo:990-1060` — **third copy of the same scanner** |
| keyword inventory | `src/pass21_keyword_registry.zig:40` (44 entries, with lifecycle) | `server.duo:1646-1742` hardcoded (30 entries) |
| `@comp.*` catalog | `src/meta_module.zig` (174 `comp.*` paths) | `duo_lsp.duo:13-54` hardcoded (40) |

`src/token_semantic.zig:4` already declares the intended shape:
*"Projections: compiler metadata, classifier, spelling, formatter, LSP, MCP,
tests."* Nothing projects.

**Measured drift from that non-projection** (LSP completion list vs the registry):

- In the registry, missing from LSP completions: `await by concept continue enum
  extends function then` (8 real keywords; `bool str void` are offered
  separately as types, and `comptime`/`macro` are correctly absent — the
  registry marks them `.remove`).
- Offered by the LSP, absent from the registry: `case`, `type`.
- **Offered by the LSP while the registry marks them `.deprecated` with a
  canonical replacement: `alias`, `match`.** The editor actively completes
  grammar the compiler is retiring.

### 2.4 The LSP's only end-to-end test does not run, and exits 0

`tools/lsp/test/smoke.duo` was written when the LSP lived in a sibling repo, so
its paths are `../duo/...`. After the subtree merge they should be `../../...`:

```
$ duo run test/smoke.duo
  ok compile (1771 ms — ./smoke.out)
smoke: corpus file not found at ../duo/examples/agent_hooks_showcase.duo
exit=0
```

The file exists at `examples/agent_hooks_showcase.duo`. The guard at `:99-102`
does `return 2`, but `main`'s return is not propagated to the exit status, so a
CI runner reads **0**. `:78` has the same stale `../duo/zig-out/bin/duo`, masked
only because `DUO_LSP_DUO_BIN` is set. Two characters (`../` → `../../`) restore
the gate.

### 2.5 Stale surface docs

- `tools/lsp/README.md:127` — *"No rename support yet."* Rename has been
  implemented since `server.duo:2151-2198`, workspace-wide.
- `tools/lsp/CLAUDE.md` editor snippet says `"args": ["lsp"]`. **There is no
  `lsp` subcommand** — `grep -n '"lsp"' src/main.zig` returns nothing; the
  server is a separate binary built by `tools/lsp/build.duo`.
- `docs/tooling.md:31,35` still routes readers to "companion repo **duo-lsp**"
  and "companion repo **duo-mcp**". Both are `tools/` now.
- `docs/tooling.md` CLI table omits `symbols`, `graph`, `sim`, `dev`,
  `semantic`, `selfhost`, `token-tables` — i.e. most of the query surface Pass
  101 wants projected.

### 2.6 `tools/mcp/zls.duo` cannot work

`zls_request` (`:26-41`) writes one bare JSON object to a file and pipes it into
`zls --stdio`. LSP requires `Content-Length` framing and an `initialize`
handshake, and each call spawns a fresh `zls` with no session. `ensure_zls`
(`:16-22`) never spawns anything — it sets `ZLS = {}` if `which zls` succeeds.
`zig_diagnostics` (`:43-64`) builds `diags = {}` and returns it unconditionally:
a **confident empty result**, not an error. Only `zig_format` (shells `zig fmt`)
can succeed. It is also outside Pass 101's scope entirely — it is a Zig tool in
the Duo toolchain.

### 2.7 Repository hygiene in `tools/mcp/`

RESOLVED 2026-08-08. 36 of the 58 files under `tools/` were `eval_probe*.duo` —
one-off scratch probes (`eval_probe.duo`, `eval_probe2.duo` … `eval_probe35.duo`),
e.g. `eval_probe17.duo` was three prints testing whether `string.gmatch` returns
a callable. They were committed alongside the servers and are now deleted: a
`git grep` found no reference from `build.zig`, from any gate, or from any
script, so nothing consumed them. `tools/mcp/duo_shared.duo:5` also opens with
`M = {}` and closes with `M` at `:1002` — the M pattern that the HOT LIST calls
dead, in the file that every MCP tool routes through.

Also observed, and worth a hygiene ticket: running `duo run tools/lsp/build.duo`
left an untracked `tools/lsp/src/duo_keyword_classify.c`, byte-identical to
`src/duo_keyword_classify.c`. Compiling a `.duo` file in a bare directory does
not reproduce it, so the trigger is narrower than "any build" and is not
isolated here — but a build that writes generated C into a source tree it does
not own is the kind of spill `zig build repo-hygiene` exists to catch. The copy
was removed; the mechanism is unfiled.

## 3. Where the target is closer than expected

### 3.1 `duo graph` already emits the LSP's data model

Probe (`add`/`main`, 9 lines), abridged — every field the LSP hand-derives is
here:

```json
{"schema":"sim-v0","file":"probe.duo","source_hash":18125155095603727817,
 "nodes":[
  {"id":1,"kind":"func","name":"add","stable_id":"c3f86ac1ef05408a","line":1,"col":1},
  {"id":2,"kind":"param","name":"a","stable_id":"12ed491062d927fa","line":0,"col":0},
  {"id":4,"kind":"func","name":"main","stable_id":"606d7d9532cfebc8","line":5,"col":1},
  {"id":6,"kind":"call","name":"add","callee_kind":"direct","arg_count":2,
   "specializable":true,"call_shape_id":13217435596508685387,"line":6,"col":10}],
 "table_shapes":[],"enum_shapes":[],
 "call_shapes":[{"name":"add",...,"line":6,"col":10},{"name":"print",...}]}
```

`func` and `call` nodes carry real `line`/`col`. `param` nodes carry `0,0` —
that is the one blocking hole, and it is one lift site.

There is also already a **content-addressed cache** keyed by source hash
(`semantic_graph.zig:1451 writeSidecar` → `.duo/graph/<stem>.json`), which is
the invalidation half of a graph service. Caveat: the path uses `basename` only
(`:1443`), so `a/mod.duo` and `b/mod.duo` collide in one sidecar.

### 3.2 The generated-projection pattern is already built, twice

Pass 101 treats "tree-sitter = generated projection" as new machinery. It is not
— `src/main.zig` already ships two instances of exactly this:

| Command | Descriptor (source of truth) | Emitted artifact |
| --- | --- | --- |
| `duo token-tables emit` (`:830-845`) | `src/token_semantic.zig` | `lib/std/token/classify.duo`, `src/duo_keyword_classify.c` |
| `duo wasm-tables emit` (`:814-828`) | `src/wasm_semantic.zig` | `lib/std/wasm/opcode_lookup.duo`, `lib/std/wasm/ward_mvp_opcodes.duo` |

And it has produced the matrix's only `duo_canonical` rows (SH-02, SH-03). A
third instance for grammar is a copy of a working pattern, not a design problem.

### 3.3 The MCP coordination surface is already a projection

`duo_shared.duo:138-200` — `dev_session_start`, `dev_claim_acquire`,
`dev_claim_list`, `dev_coordination_export`, `dev_validate_plan`,
`dev_integration_list/submit`, `dev_validate_run`, `semantic_claims`,
`semantic_transaction_preview/validate` are all one-line shells into
`duo dev …` / `duo semantic …`. That half is Pass-101-shaped already; the
compiler owns the state and MCP is a face.

The half that is not: `coordination_read` (`:30`), `session_log` (`:53`),
`file_finding` (`:908`) and `agent_gaps_update` (`:939`) read-modify-write
markdown by string surgery — `string.find(content, marker, 1, true)` then
splice. Same control plane, two mechanisms.

### 3.4 The compiler already knows about the gap

- `src/graph_query.zig:1-3` — *"bounded facts for compiler, LSP, and MCP
  projections."*
- `src/token_semantic.zig:4` — *"Projections: … formatter, LSP, MCP, tests."*
- `src/pass21_keyword_registry.zig:3-5` — *"Compiler-owned grammar facts
  consumed by catalog, gates, LSP, and MCP."*
- `src/pass21_catalog.zig:68` — P21-G13, *"parser/formatter/treesitter/LSP/MCP
  grammar agreement"*, **open**.
- `src/pass21_catalog.zig:75` — P21-G20, *"one compact grammar over one semantic
  system"*, **open**.

Pass 101 §3 is not a new ruling. It is P21-G13/G20 restated with a sequence.

## 4. tree-sitter: hand-maintained, and demonstrably behind

`ext/tree-sitter-duo/grammar.js` is hand-authored JS. Evidence, then consequence.

**It is hand-authored.** No generator anywhere in the repo writes it (`grep -rn
"grammar.js"` over `*.zig`/`*.duo` returns nothing). Its own header (`:7`) says
it was transcribed *"Based on the lexer tokens from `src/lexer.zig` and AST from
`src/ast.zig`"* — a transcription, which is the parallel-renderer form ONE EDGE
forbids. Git history is 4 commits, all human-message (`lots`, `f`, `m`, `m`).

**It is already wrong.** Three measured divergences:

1. **The canonical declaration form does not parse.** `function_declaration`
   (`:215-228`) requires `choice('function', 'fun')`, and its only return-type
   spelling is `optional(seq(':', $.type))`. Canonical Duo — the form the
   compiler *tells you to write* — is `add(a: i64) -> i64 … end`. Measured:

   ```
   $ duo check --plain-diagnostics probe.duo
   probe.duo:1:1: hint: 'fun' is unnecessary here; bare function syntax works:
                        name(params) body end
   ```

   `'->'` appears exactly once in `grammar.js`, at `:552`, inside `function_type`
   (the type `(i64) -> i64`), never in a declaration. So the grammar cannot see a
   function in most of `lib/std`.

2. **Dotted directives stop at two segments.** `attribute` (`:67-73`) admits
   `@name` and `@name.name` only. `CLAUDE.md` makes `@comp.foo.bar` canonical,
   and `src/meta_module.zig` registers three-segment paths (`comp.derive.product`,
   `comp.agent.catalog`, `comp.str.join`). Those lex as an attribute followed by
   loose tokens.

3. **The keyword set diverges from the registry.** `grammar.js` is missing
   `async`, `await`, `by`, `continue`; it still carries `comptime`, which
   `pass21_keyword_registry.zig` classifies `.remove` / `.error_with_fix`.

**Consequence for sequencing.** Pass 101 puts tree-sitter fifth, after MCP. That
ordering is right, but note the grammar is not merely un-projected — it is
actively wrong today, so highlighting/`tags.scm` in every editor under `ext/` is
mis-scoping canonical files right now. The projection is a fix, not only a
refactor.

## 5. Ward's ARM64 JIT — verifying the donor claim

**The claim as posed:** `tools/wasm/src/wasm/jit_arm64.duo` is ~701 lines of ARM64
emitter in Duo while `lib/std/compiler/arm64.duo` is ~222 and
`src/native_backend.zig` is ~5113 Zig, so ward's JIT is a donor for SH-11.

**The line counts hold** (5138 for `native_backend.zig`, not 5113). **The
conclusion holds, and is stronger than posed — but the specific file named is
not the one that works.** Corrections, measured:

**(a) There are two ARM64 emitters in ward, and the shipping one is the other.**
`jit_arm64.duo` is not imported by `tools/wasm/src/engine.duo`, by `tools/wasm/build.duo`,
or by anything else in the repo — `grep -rn "jit_arm64"` over `*.duo`/`*.zig`
matches only its own first line. The emitter that actually runs is
`ward.duo:2712-4404` — **`jit_compile`, a single 1693-line function** with 151
inline `jitm.w32(code, n, 0x…)` raw-hex sites, selected at `ward.duo:4427-4469`
via `DUO_WASM_ENGINE`. This is the same trap `tools/wasm/HANDOFF.md:255-257` already
records for `src/wasm/op.duo` ("separate 8398-line tree, not what builds").

**(b) The measurement belongs to `jit_compile`, not to `jit_arm64.duo`.**
`HANDOFF.md:249-256`: ward `jit-arm64` 0.45 s vs wasmtime 0.436 s vs ward
interpreter 5.26 s on `hash.wasm`. A Duo-authored ARM64 machine-code emitter
within 3 % of wasmtime is real and is the load-bearing evidence — it is just
evidence about the 1693-line function.

**(c) `jit_arm64.duo` is nonetheless the better donor**, because it is the
*shape* SH-11 needs. It factors the emitter the way `lib/std/compiler/arm64.duo`
would have to: 20 encoder functions (`:41-110` — `dp3`, `ldr_imm`/`str_imm`,
`ldr_reg`/`str_reg`, `add_imm`/`sub_imm`, `movz`/`movk`, `sxtw`/`uxtw`, `cset`,
`b_imm`, `cbz`/`cbnz`, `msub`, `csel`, `mem_rr`, `stp_pre`/`ldp_post`) plus five
pure selection *tables* (`:112-175` — `BIN` 20 rows, `CMP` 20, `MEM` 10, `CONV`
8, `LEB1`), then a code buffer with branch patching (`:176-192`), a virtual
operand stack with register allocation and spilling (`:201-303`), and
prologue/epilogue (`:335-355`). Its own header states the principle Pass 101
would state: *"the whole instruction selector is a table, not a switch: adding
an opcode is one row."*

Against that, `lib/std/compiler/arm64.duo` has **9 encoders total**
(`encode_add_reg`, `sub`, `mul`, `and`, `orr`, `eor`, `mov`, `movz`, `ret`), no
buffer, no register allocator, no branch patching — the rest of its 222 lines is
the comment explaining its assembler-differential proof, which is excellent and
should be kept.

**(d) The stated reason not to reuse it has expired.** `lib/std/compiler/arm64.duo:3-6`:

> SH-11 is the direct native backend row. It has no Duo implementation; ward's
> JIT proves the approach works, but ward is a WASM runtime, not the compiler's
> backend, and **its encoder is not reusable from here.**

That was a repository-boundary argument written when ward lived at `~/x/ward`.
Ward is now `tools/wasm/` in this repo. The sentence is now false as stated —
whatever remains is a design argument about coupling to `WardRT`/`WardFrame`
offsets (`jit_arm64.duo:19-23`), which is confined to the memory ops and the
prologue, not to the ~70 lines of pure encoders that have no runtime dependency
at all.

**(e) The matrix has not noticed any of this.** `src/selfhosting_matrix.zig`
records `duo_impl = null` for SH-05 through SH-13 — but every one of those rows
has a Duo seed on disk today:

| Row | Matrix `duo_impl` | Actually on disk |
| --- | --- | --- |
| SH-05 canonicalizer | `null` (host: `src/fmt.zig`, **does not exist**) | `lib/std/compiler/fmt.duo` |
| SH-06 binding/scopes | `null` | `lib/std/compiler/bind.duo` (194 L) |
| SH-07 semantic graph | `null` | `lib/std/compiler/graph.duo` (140 L) |
| SH-08 comptime eval | `null` | `lib/std/compiler/comptime.duo` (269 L) |
| SH-09 transform registry | `null` | `lib/std/compiler/rewrite.duo` (193 L) |
| SH-10 C backend | `null` | `lib/std/compiler/emit_c.duo` (130 L) |
| SH-11 native backend | `null` | `lib/std/compiler/arm64.duo` (222 L) |
| SH-12 object writers | `null` | `lib/std/compiler/macho.duo` (165 L) |
| SH-13 runtime profile | `null` | `lib/std/compiler/profile.duo` (78 L) |

Each seed names its own row in its first line. Nine stale rows in the artifact
that is supposed to be the honest ownership map — the self-hosting number is
understated, and `WITNESS` says read your manifest delta.

**Smallest next step for SH-11:** lift `jit_arm64.duo`'s runtime-independent
encoders (`:41-110`, minus `mem_rr`) into `lib/std/compiler/arm64.duo`, one at a
time, each admitted only by the assembler differential that file already
defines. That takes SH-11 from 9 encoders to ~19 with a machine-checked oracle
per instruction, and it is the first time ward pays back into the compiler
rather than only consuming it.

## 6. Ordered next steps

Following Pass 101's own sequencing (graph → fmt → LSP → MCP → tree-sitter →
Ward), smallest-first, each one dogfooding the last:

1. **Graph core.** Give `param` nodes a real span in
   `semantic_graph.liftFunctionBindings`. One lift site; unblocks
   definition-on-parameter for every front-end.
2. **Graph core.** Key the sidecar on the full relative path, not `basename`
   (`semantic_graph.zig:1443`).
3. **LSP.** `handle_document_symbol` calls `duo graph` and drops
   `scan_symbols_lo` (94 lines). This is the dogfood gate for stage 1.
4. **LSP.** Fix `test/smoke.duo:78,99` (`../duo/` → `../../`) so the gate stops
   reporting a confident 0, and make `main`'s failure path use `os.exit`.
5. **LSP/registry.** Project the completion keyword list from
   `pass21_keyword_registry.zig` — deletes 30 hardcoded calls and stops
   completing `alias`/`match`.
6. **MCP.** Delete the 16 duplicated registrations from one server.
7. **MCP.** Replace `META_CATALOG` (40 hand-copied rows) with `@comp.catalog()`;
   verified reachable.
8. **MCP.** Collapse `duo_diagnostics`/`duo_compile_check` into one tool that
   calls the same code path the LSP does.
9. **fmt.** Correct the SH-05 matrix row, then move the `fun` hint from
   diagnostic to `duo fmt --canonical` rewrite with a fixpoint proof.
10. **tree-sitter.** `duo grammar emit`, modelled on `duo token-tables emit`;
    close P21-G13.
11. **Ward → SH-11.** Lift the runtime-independent encoders per §5.
12. **Housekeeping.** ~~Retire `tools/mcp/eval_probe*.duo`~~ — DONE 2026-08-08,
    36 files deleted. Still open: decide whether `zls.duo` belongs in a Duo
    toolchain at all, given §2.6.

## Appendix — measurements taken

| Check | Result |
| --- | --- |
| `duo check --plain-diagnostics` on all 8 tool sources | 8/8 clean |
| `duo run tools/lsp/build.duo` | builds `duo-lsp`, 387 KB |
| `duo run tools/lsp/test/smoke.duo` | skips on stale path, **exit 0** |
| `duo graph` on 9-line probe | JSON with line/col on `func`/`call`, `0,0` on `param` |
| `duo explain` / `duo fmt` / `@comp.catalog()` | all reachable |
| MCP tool-name overlap | 16 shared / 33 bench / 32 lsp |
| `comp.*` paths: compiler vs MCP catalog | 174 vs 40 |
| Keywords: registry vs LSP completions | 44 vs 30; 2 deprecated still offered |
| `grep -rn jit_arm64` outside its own file | 0 hits in tracked source |
| Matrix rows with `duo_impl = null` but a seed on disk | 9 (SH-05…SH-13) |
