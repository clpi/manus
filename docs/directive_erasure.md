# Directive erasure — survey and repair order

Status: SURVEY + one landed step. **Step 3 (group C, record layout) is done** —
see "Step 3 landed" below. Everything else is still plan.

Pass 100 says: *there is no prefix `@`; directives do not exist.* The compiler
still has an `ast.Attribute` system, a `--- @hint` comment channel, a
module-level directive statement kind, and roughly fifty attribute names spread
across parser, sema, codegen and six satellite modules. A Pass 100 audit called
this the clearest implementation-level contradiction in the tree and rated it
P1.

This file inventories what actually survives, says what single edge fact each
directive is secretly storing, and sequences the removal. It is deliberately
conservative: the erasure touches `parser.zig`, `sema.zig`, `codegen.zig` and
`types.zig`, and a wrong plan there is worse than no plan.

## Method, and what "consumed" means here

A directive being *mentioned* is not evidence it does anything. Three distinct
things get confused in this codebase and are separated throughout the table
below:

- **recognized** — `parser.zig:723 is_known_attribute` accepts the token, so
  `@foo` parses instead of erroring.
- **permitted** — `directives.zig validateFuncAttrs` / `validateModuleDirective`
  allow-list the name, so sema does not reject it. This is a *negative*
  behaviour: it only prevents a diagnostic.
- **consumed** — some pass reads the attribute and changes its output.

An attribute can be recognized and permitted while being consumed by nothing.
Several are. Those are not "features to migrate", they are dead syntax with a
grammar slot, and they should be deleted rather than given a graph home.

Every row below was traced to a consumer or shown to have none. Counts in this
document were produced by grep over `src/*.zig` and over `.duo` sources in
`lib/ examples/ tools/ ext/ tests/`; where a number appears, it came from a
command, not from reading.

## Where attributes enter the compiler

There are three entry paths, and they matter because they get erased at
different times.

1. **Attribute syntax on a declaration** — `parser.zig:814
   parse_attributed_decl`, args slurped raw as text by `parser.zig:1036
   parse_attribute_args`. Lands in `ast.Attribute { name, args: ?[]const u8 }`
   (`ast.zig:539`). Note `args` is an **unparsed string**; every consumer
   re-parses it ad hoc. That is why the fact has no type today.
2. **`--- @hint` comments** — the lexer accumulates them
   (`lexer.zig:211 pending_hints`, `lexer.zig:262 consumeHints`), the parser
   turns them into real attributes (`parser.zig:99 consumeLexerHints`) and
   either emits them as module directive statements or defers them onto the next
   declaration (`parser.zig:124 flush_module_hint_directives`,
   `parser.zig:163 merge_deferred_hints`). **This is the worst offender**: a
   comment silently becomes language semantics. Pass 100 wants hint comments to
   be tooling metadata only.
3. **Module-level directive statements** — `ast.zig:680
   Stmt.directive { loc, attr }`, validated at `sema.zig:2050`, routed to
   `sem.build_directives` / `sem.debug_directives`.

`ast.Attribute` is carried on five nodes: `FuncDecl` (`ast.zig:557`),
`LocalName` (`ast.zig:590`), `AliasDef` (`ast.zig:700`), `EnumDef`
(`ast.zig:529`), `ConceptDef` (`ast.zig:605`).

## The inventory

The **edge fact** column is the point of the table: it names the one thing the
directive is actually storing, which is what has to exist in the graph before
the syntax can go.

### A. Effect / contract facts on a function

| Directive | Parsed | Consumed | The one edge fact | Class |
|---|---|---|---|---|
| `@nopanic` |  `parser.zig:749` | `sema.zig:59 has_nopanic_attr` → `sema.zig:3398 current_nopanic`; rejects `!` at `sema.zig:2747` | `fn --failure-set--> empty` — a contract fact about the callee's failure set | (b) |
| `@noalloc` | known-attr list | `codegen.zig:367` via `semantic_algebra.effectSetFromAttributes`; guarded at `codegen.zig:371 guardNoAlloc` | `fn --effect--> ¬heap` | (a) |
| `@pure` | `parser.zig:753` | `semantic_algebra.zig:454`; `codegen.zig:7623` | `fn --effect--> {}` (empty effect set) | (a) |
| `@arc(false)` | `parser.zig:726` | `arc.zig:422 hasArcFalse`; `sema.zig:82 validate_arc_attr`, `sema.zig:1312`, `sema.zig:3334` | `binding --ownership--> manual` — a world/ownership fact, not an annotation | (b) |
| `@noreturn` | known-attr list | `codegen.zig:7625` → C attribute | `fn --returns--> ⊥` — a *type* fact wearing an attribute costume | (b) |

`@nopanic`, `@pure` and `@noalloc` are three spellings of one relation:
`fn --effect--> EffectSet`. `semantic_algebra.zig:449 effectSetFromAttributes`
already computes exactly that lattice and already handles `pure` and `noalloc`
— but **not** `nopanic`, which sema tracks separately through a bool on the Sema
struct. That split is the whole problem in miniature.

### B. Codegen preference facts (no semantics, only C output)

| Directive | Consumed | The one edge fact | Class |
|---|---|---|---|
| `@inline` / `@noinline` | `codegen.zig:7618`, `7619` | `fn --inline-preference--> {force, forbid}` | (a) |
| `@hot` / `@cold` | `codegen.zig:7621`, `7620` | `fn --call-frequency--> {hot, cold}` — a *profile* fact, and the graph should get it from measurement, not a human | (b) |
| `@flatten` | `codegen.zig:7624` | `fn --inline-preference--> transitive` | (a) |
| `@consteval` | `codegen.zig:7626` | `fn --stage--> compile` | (b) |
| `@target(...)` | `codegen.zig:7627 func_attr_args` | `fn --requires--> isa-feature` | (b) |
| `@section(...)` | `codegen.zig:7628` | `fn --placement--> link-section` | (c) |
| `@raw` | `codegen.zig:7622` | `fn --abi--> unwrapped` | (b) |

These are the *easy* ones. They carry no semantics — every one is a preference
handed to the C backend. They belong in a single `world/contract` fact per
function that codegen queries once, not eight `func_has_attr` calls in a row at
`codegen.zig:7618-7628`.

### C. Descriptor refinement facts (record layout)

| Directive | Consumed | The one edge fact | Class |
|---|---|---|---|
| `@packed` | `types.zig:69` via `applyTableShapeAttrs`; enum path `sema.zig:3832` | `descriptor --layout--> packed` | (a) |
| `@align(N)` | `types.zig:72`; enum path `sema.zig:3833` | `descriptor --alignment--> N` | (a) |
| `@ffi("name")` | `types.zig:76`; `codegen.zig:6879`, `7556`; `dnir_lower.zig:320` | `descriptor --foreign-name--> str` | (a) |
| `@sealed` | `types.zig:84` | `descriptor --storage--> sealed` | (a) |
| `@native` | `types.zig:87` | `descriptor --storage--> native` | (a) |
| `@guarded` | `types.zig:89` | `descriptor --storage--> guarded` | (a) |

**This group is nearly erased already and almost nobody noticed.**
`types.zig:51 inferStorageClass` is a real lattice — `dynamic → guarded →
sealed → native` — *inferred from field types*. The attributes are only an
`explicit` override threaded into that inference (`types.zig:65-93`). The
relation exists; the descriptor already carries the fact; the attribute is a
manual thumb on an inference that runs anyway. Erasing `@sealed`/`@native`/
`@guarded` costs nothing but the override path.

Applied at `sema.zig:76 apply_record_layout_attrs`, called from `sema.zig:1799`
and `sema.zig:1858`.

### D. Facts that already have a home elsewhere

| Directive | Consumed | The one edge fact | Class |
|---|---|---|---|
| `@derive(...)` | `derive_bundles.zig:201,220,228`; `codegen.zig:6834,12421,12437,12490`; `meta_codegen.zig:2672` | `descriptor --derives--> trait` | (b) |
| `@implements(C)` | `sema.zig:1322` | `descriptor --satisfies--> concept` — the concept system already answers this | (a) |
| `@export` / `@c.export` | `codegen.zig:7600`, `21999` | `fn --visibility--> external` | (b) |
| `@device(.metal)` | `directives.zig applyMlFuncAttrs` → `ast.FuncBody.device_target`; `codegen.zig:7718` | `fn --executes-on--> device` | (b) |
| `@autodiff` / `@differentiable` | `applyMlFuncAttrs` → FuncBody flags | `fn --differentiable--> true` | (b) |
| `@unroll(N)` | `applyMlFuncAttrs` → `fb.unroll_count` | `loop --unroll-factor--> N` — note it is stored on the *function*, which is already wrong; the fact belongs on the loop | (b) |
| `@profile` | `applyMlFuncAttrs` → `fb.profile_attr` | `fn --instrumented--> true` | (b) |
| `@specialize(f, T)` | `parser.zig:159,915`; `sema.zig:1728 check_specialize_directive` | `fn --instantiate-at--> type-args` — a request for a graph node to exist | (b) |
| `@deprecated("msg")` | recognized `parser.zig:738`, permitted `directives.zig`; **no consumer found** | `decl --lifecycle--> deprecated` | see below |

### E. Tooling channels that are not language semantics

| Directive | Consumed | The one edge fact | Class |
|---|---|---|---|
| `@test`, `@test.*` | `directives.zig attrsMarkTest/parseTestOptions` → `sema.zig:3373`; codegen bails at `codegen.zig:3114,3371,3403` | `fn --is--> test-case` | (c) |
| `@bench`, `@time` | same path | `fn --is--> benchmark` | (c) |
| `@build.*` | `sema.zig:2054` → `sem.build_directives` → `build_framework.zig:518` | `module --builds--> target` — a build-system fact that should not be in the language at all | (c) |
| `@debug.*`, `@trace.*` | `sema.zig:2056`; `debug_trace.zig:207,219` | `module --traces--> channel` | (c) |
| `@c.emit` / `@c.include` / `@c.import` / `@c.type` / `@c.call` | `directives.zig isCInterfaceDirective` → `sema.zig:2049` bypass; `codegen.zig:5444,10762,22627` | `module --emits--> foreign-text` — genuine bootstrap escape hatch, 188 + 33 uses in `.duo` | (c) |

### F. Dead — recognized and/or permitted, consumed by nothing

Traced repo-wide; each has zero consumer.

| Name | Recognized | Permitted | `.duo` uses | Verdict |
|---|---|---|---|---|
| `@repr` | `parser.zig:755` | no | 0 | parse-accepted then **rejected** by `validateFuncAttrs`. Pure grammar debt. |
| `@dispatch` | `parser.zig:769` | no | 0 | same |
| `@concurrent` | via `startsWith` at `directives.zig` | yes | 1 | permitted and silently ignored — the worst kind: it looks like it works |
| `@restrict` | `parser.zig:756` | yes | 0 | permitted, ignored |
| `@bitfield` | `parser.zig:729` | no | 0 | superseded by `comp.bit.field` in `legacy_directives.zig:52` |
| `@volatile` | `parser.zig:768` | no | 0 | superseded by `comp.hint.volatile` |
| `@deprecated` | `parser.zig:738` | yes | 0 | permitted, ignored — no diagnostic is ever emitted |
| `@asm`, `@simd`, `@sealed`(fn position), `@prefetch`, `@likely`, `@unlikely` | yes | partly | 2, 0, —, 0, 2, 2 | consumed only in *expression* position via `legacy_directives` internal names, never as declaration attributes |

`@concurrent` and `@deprecated` are the dangerous entries: they are on the
allow-list, so a user writes them, gets no error, and gets no behaviour.

## What is already dead and was deleted

Inside the two files this survey owns, four items had zero callers repo-wide
(verified by grep across `*.zig`, `*.duo`, `*.md`, `*.sh`, `*.c`) and were
removed:

- `directives.attrNameEq` — helper, never called.
- `directives.DebugOptions` + `directives.parseDebugOptions` — a full
  `@debug({channels=…, scopes=…, depth=…})` option parser with no caller.
  `debug_trace.zig:207` re-implements this against `parseAttrArgs` directly, so
  the typed version lost and was never wired.
- `directives.attrsWantTiming` — never called; `attrsWantBench` is the one used.
- `directives.registry_json` — a hand-maintained JSON catalog of every supported
  directive, documented as being "for docs / `--help`", referenced by nothing.
  It had already drifted: it lists `debug.sema`, `trace.mono` and
  `time(label="...")`, none of which any consumer implements.

`legacy_directives.zig` was checked the same way and **nothing in it is dead**.
All 57 entries resolve through `parser.zig:4239` / `parser.zig:4247`, and every
`internal` name (`__comptimeif`, `__bitfield`, `__popcount`, …) has live
consumers downstream. It is a working alias table, not debt, and it should be
erased *last* — it is the deprecation ramp that lets the old spellings warn
rather than break.

## Classification summary

- **(a) erasable now** — the fact already has a relation in the graph:
  `@noalloc`, `@pure`, `@inline`/`@noinline`, `@flatten`, `@implements`, and the
  whole layout group `@packed`/`@align`/`@ffi`/`@sealed`/`@native`/`@guarded`.
- **(b) erasable after a named capability lands** — see below.
- **(c) load-bearing bootstrap** — `@c.*` (320 uses across `.duo`; nothing
  replaces it until Pass 100 has its own foreign-text story), `@test`/`@bench`
  (the test harness is the gate that proves the rest), `@build.*`
  (`build_framework.zig` is a real build system with no replacement),
  `@debug`/`@trace`, `@section`.

### The capabilities that gate group (b)

Named, so nobody has to guess:

1. **`fn --effect--> EffectSet` as a queryable relation.** Exists in
   `semantic_algebra.zig:449` but is computed *from attributes* on demand and
   never stored. It must become a fact the graph holds, and it must absorb
   `nopanic`, which today lives on a Sema field (`sema.zig:251
   current_nopanic`).
2. **Per-function contract records that sema and codegen both query.**
   `contract_model.zig` looks like this and is **not** — see the warning below.
3. **A loop-level fact carrier.** `@unroll` is stored on `FuncBody`
   (`fb.unroll_count`); until loops can carry facts, the migration has nowhere
   correct to put it.
4. **Typed attribute arguments.** `ast.Attribute.args` is `?[]const u8`, raw
   source text, re-parsed by hand in at least six places
   (`directives.parseAttrArgs`, `types.zig:72`, `arc.zig:425`,
   `semantic_algebra.zig:457`, `codegen.zig:7594`, `build_framework.zig:213`).
   No fact can be reliably extracted until this is a value.
5. **A measurement source for `@hot`/`@cold`.** These are profile facts. Taking
   them from a human is the same category of error the benchmark suite was
   caught in (CLAUDE.md §MEASUREMENT HONESTY).

## The trap: two ontologies

`contract_model.zig` is a catalog of exactly the facts this migration needs —
`contract.nopanic`, `contract.noalloc`, `contract.pure`, `contract.sealed`,
with `Hardness` (preference / expectation / requirement / assertion / budget)
and `ValidationStage`. It declares each one `wired = true`.

**It is not wired to anything.** Its only importers are `pass7_catalog.zig:4`
(a documentation catalog) and `tests.zig:44` (which merely pulls in its unit
tests). No pass queries it. Nothing in sema, codegen, parser or dnir_lower reads
it. `contract_model.zig:143 "contract_model: noalloc enforced at codegen"` is a
test that asserts a *field of a struct literal in the same file*, not that
codegen enforces anything — it is a green test that proves nothing, and it is
the reason the second ontology was not noticed.

So the tree already contains the failure the audit warned about: a Pass-100-
shaped registry sitting beside the legacy one, agreeing with nobody. The repair
is **not** to teach `directives.zig` to consult `contract_model.zig`. That
would be the adapter the audit forbids and would make the split permanent. The
repair is to make the graph the single owner and delete both.

`contract_model.zig`'s `wired` column should be corrected to `false` for every
row as a first, cheap, honest step. That is outside this survey's file
ownership; it is listed in the repair order below.

## Repair order

Sequenced so each step is independently verifiable and nothing is left in a
half-migrated state.

**0. Tell the truth about `contract_model.zig`.** Flip `wired` to `false`
(9 rows) or delete the field. Fix or delete the two tests that assert wiring
that does not exist. Cheap, and it stops the second ontology from being cited as
evidence of progress. *Blocks nothing; unblocks honest measurement.*

**1. Delete group F.** `@repr`, `@dispatch`, `@bitfield`, `@volatile` from
`parser.zig:723 is_known_attribute`; `@concurrent`, `@restrict`, `@deprecated`
from the `validateFuncAttrs` allow-list. Two of these have `.duo` uses
(`@concurrent` ×1, and `@deprecated` ×0 but it is in the allow-list) — those
call sites must be removed in the same change or the build breaks. This is pure
subtraction and removes ~8 names from the surface with no migration cost.

**2. Type `ast.Attribute.args`.** Capability (4) above. Every later step needs
it, and it is the change that converts "a string a pass re-parses" into "a value
the graph can hold". Doing this before any fact migration means each migration
is a move, not a rewrite.

**3. Migrate group C (layout) into the descriptor relation.** ✅ **LANDED** —
see "Step 3 landed" below. It went ahead of step 2 because the layout facts are
the one group whose payload was *already* typed at the destination
(`table_type.is_packed`, `.align_n`, `.storage_class`), so it did not need the
`ast.Attribute.args` typing that steps 4/5/7 do.

**4. Unify the effect set.** Capability (1). Fold `nopanic` into
`semantic_algebra.EffectSet`, delete `sema.zig:59 has_nopanic_attr` and
`sema.zig:251 current_nopanic`, have `sema.zig:2747` ask the effect set. Then
`@pure`/`@noalloc`/`@nopanic` are one relation with three legacy spellings.

**5. Collapse group B into one contract fact per function.** Replace the eight
consecutive `func_has_attr` calls at `codegen.zig:7618-7628` with a single
query. `@hot`/`@cold` become measured, not declared, or they are demoted to
group F and deleted.

**6. Demote the `--- @hint` comment channel to tooling metadata.** Delete
`parser.zig:99 consumeLexerHints`, `parser.zig:124
flush_module_hint_directives`, `parser.zig:163 merge_deferred_hints`,
`parser.zig:89 deferred_hint_attrs`, and `lexer.zig:211 pending_hints`. A
comment must stop being able to change codegen. **This is the step that most
directly satisfies the Pass 100 sentence about hint comments**, and it is
deliberately late because module-level `@build.*` and `@c.*` currently arrive
through it.

**7. Migrate group D.** `@derive` → `descriptor --derives--> trait` (the
`derive_bundles.zig` machinery is close already); `@implements` → the concept
relation; `@specialize` → an instantiation request node; `@device`/`@autodiff`/
`@unroll`/`@profile` → world facts, once (3) exists for `@unroll`.

**8. Retire group E's language status.** `@test`/`@bench`/`@build.*`/`@debug.*`
stop being attributes and become tooling declarations outside the language.
Requires a replacement test-declaration surface, which does not exist yet.

**9. Delete `legacy_directives.zig`, then `directives.zig`, then
`ast.Attribute`.** Only after 1-8. `legacy_directives.zig` is the deprecation
ramp and must outlive the things it warns about.

**10. `@c.*` last, or never.** It is the foreign-text escape hatch with 142
`.duo` call sites. Pass 100 needs its own answer here before this can move; this
survey does not have one.

## The single highest-leverage erasure

**Typing `ast.Attribute.args` (step 2).**

Not the most visible, but it unblocks the most. Today the fact carried by an
attribute is a raw source substring, re-parsed independently in at least six
places with six different notions of what the syntax is — `types.zig:72` does
`parseInt` on it, `arc.zig:425` does `mem.eql(args, "false")`,
`semantic_algebra.zig:457` does `indexOf(args, "cuda")`, `directives.zig`
`parseDeviceTarget` does `indexOf(raw, ".metal")`. Every one of those is a
substring search standing in for a typed value.

No fact can move into the graph while its payload is untyped text, because
there is nothing to move — the "fact" only exists at the moment some consumer
guesses at the string. Steps 3, 4, 5 and 7 each depend on it. It is also the
step with the clearest test: after it, `grep -n 'attr.args' src/*.zig` should
show parsing in exactly one place.

Runner-up, and the better first *commit* because it is pure subtraction with no
design risk: **step 1**, deleting group F.

## What could not be determined

- Whether `@asm` (2 `.duo` uses) reaches a declaration-attribute consumer at
  all, or only the expression-position `legacy_directives` path. The two uses
  were not traced to a codegen site.
- Whether any `.duo` file outside the searched roots uses the group F names.
  The census covered `lib/ examples/ tools/ ext/ tests/`.
- Whether the `@location` / `@group` / `@vertex` / `@fragment` / `@schema` /
  `@foreign` / `@lua` / `@run` / `@pipeline` names seen in `.duo` sources
  (12, 5, 2, 2, 3, 7, 2, 39, 9 occurrences respectively) are attributes at all — none appear in
  `parser.zig:723 is_known_attribute`, so they reach the compiler by some other
  route (likely `meta_module` module-directive handling or plain expression
  parsing). They are not in the table above because their path was not
  confirmed, and they should be resolved before step 1 in case any is another
  silently-ignored name.
- Whether `@sealed` in *function* position (permitted at `directives.zig`) does
  anything; only the *type* position consumer at `types.zig:84` was found.

---

# The surface this survey does not cover: `@comp.*` is not an attribute

Everything above is the **`ast.Attribute`** surface — 46 recognized names, one
`Attribute { name, args }` record, ~70 `std.mem.eql` reads. That is the surface
the audit read, and it is the one worth migrating first.

It is not the largest `@` population in `.duo` source. Counted at `489bc1b`:

| surface | spellings | representation | consumers |
|---|---|---|---|
| **A** declaration attributes (this survey) | 46 | `ast.Attribute` | 19 `.zig` files |
| **B** meta-module expression builtins | **556** public paths | rewritten to `__comptime*` **call expressions** — never `ast.Attribute` | `comptime.zig`, `codegen.zig` |
| **C** module-level directive statements | `@build.*` `@debug.*` `@c.include` `@c.emit` | `ast.Stmt.directive` (wraps an `Attribute`) | 10 switch sites |
| **D** `--- @hint` comments | any of A | lexer `pending_hints` → `Attribute` | `lexer.zig`, `parser.zig` |
| **E** legacy underscore aliases | 55 | parser-only rename into B | `legacy_directives.zig` |

Surface **B is the large number and the small problem.** Those 556 public paths
in `meta_module.zig` collapse to **193 canonical paths** — `meta.` / `comp.` /
`compiler.` are three spellings of one thing — and then to **144 internal
targets**. They are already *call expressions* in the AST, not annotations. So
migrating B is a **re-homing** job, not a representation change: `@comp.map(…)`
is a call whose callee is resolved by a static table instead of by the trie.
Pass 100 §17 names the destination — `check`, `why(q)(subject)`, `graph.*`, the
`add` family — and §19 says that lives behind one graph service, which does not
exist yet.

**Consequence for sequencing:** nothing in steps 1-9 above reduces the
`@comp.*` count, and that is correct. Renaming 193 paths off the sigil while
they are still resolved by the same static table would be cosmetic conformance
and would leave exactly the two-ontology state this document's "The trap"
section warns about. B moves when the graph service lands, and E dies with it.

Reproduce the counts:

```
grep -c '\.public = ' src/meta_module.zig                       # 627 rows
grep -oE '\.public = "[a-z0-9._]+"' src/meta_module.zig \
  | sed 's/.*"\(.*\)"/\1/' | sort -u | wc -l                    # 556 public
... | sed -E 's/^(meta|comp|compiler)\.//' | sort -u | wc -l    # 193 canonical
grep -oE '\.internal = "[a-z0-9_]+"' src/meta_module.zig | sort -u | wc -l   # 144
```

---

# Step 3 landed — record layout is a refinement edge

Pass 100 §11 calls packed/aligned/endian/at-address **layout facts**, and
LAW-STRATA makes `&` the refinement edge that carries them. The group C
attributes were storing exactly those facts through a string-keyed detour into
fields that already existed on the resolved type.

```
@packed                                    global gp: { x: i8, y: i64 }
@align(16)                          →          & packed & align(16)
global gp: { x: i8, y: i64 }                   = { x = 1, y = 2 }
    = { x = 1, y = 2 }
```

## What changed

| file | change |
|---|---|
| `src/ast.zig` | `TypeExpr.Layout` + `TypeExpr.StorageWord`; `RecordType.layout` |
| `src/parser.zig` | `parse_layout_refinements()` — `&` refinements after a record type |
| `src/types.zig` | `layoutFromAttrs(base, attrs)` + `applyLayout(t, layout)`; `applyTableShapeAttrs` rewritten as a two-line call through them; `resolve`'s `.record` branch reads `rec.layout` |
| `src/codegen.zig` | `alias_record_type`'s record branch merges `target.record.layout` with `ad.attributes` in **one** application |

`Layout` is now the single home for the fact. `applyTableShapeAttrs` is the
adapter **in the permitted direction only**: `ast.Attribute` → `Layout`.
Nothing converts a refinement back into an attribute — which is precisely the
"two ontologies" trap this document warns about, and the reason the adapter
runs one way.

Accepted refinements: `packed`, `align(n)`, `sealed`, `native`, `guarded`,
`ffi("name")` — exactly the set `applyTableShapeAttrs` handled, so the collapse
is total for records rather than partial. `sema.zig:76
apply_record_layout_attrs` needed no change: it resolves the annotation through
`types.resolve` first, so refinement facts already reach it.

## Why it cannot change existing behaviour

`&` after a type was a syntax error before this, so no existing program can be
re-interpreted. An unrecognised name after `&` restores the lexer and leaves
the `&` unconsumed, producing the same diagnostic as before. Refinements whose
fact has **no home yet** — `& le`, `& be`, `& at(a)`, `& volatile`,
`& positive` — are therefore *rejected*, not silently accepted and ignored:

```
$ duo check le.duo          # 'Pt: { x: i8, y: i64 } & le'
error: parse failed: ExpectedToken
```

That is deliberate. `ResolvedType` has no endian, address or volatility fact,
and accepting the syntax without the fact would be a silent lie of exactly the
kind group F above is condemned for.

`Layout.align_given` exists because the attribute path treats `@align(garbage)`
as *clear to null*, not as *leave alone*. A plain `?usize` would have silently
changed that.

## Proof

Both spellings compiled and their emitted C diffed:

```
$ diff /tmp/duo_attr.c  /tmp/duo_refine.c    # binding form     → empty
$ diff /tmp/duo_aattr.c /tmp/duo_arefine.c   # descriptor form  → empty
```

**Byte-identical C**, including
`typedef struct __attribute__((packed)) __attribute__((aligned(16)))`, and the
same program output. Verified by value, not by "it compiled".

Gates, measured at the same HEAD with and without the change:

| gate | before | after |
|---|---|---|
| `agent-smoke` | exit 0 | exit 0 |
| `repo-hygiene` | exit 0 | exit 0 |
| `pass16_lexer_fingerprint_differential` | exit 0 | exit 0 |
| `pass16_lexer_text_differential` | exit 0 | exit 0 |
| `run_compile_fail_tests` FAIL set | 11 | **same 11**, name-for-name |
| `unit-test` | 1244/1302, 54 fail 4 crash | 1246/1304, 54 fail 4 crash — **identical failing name set** |

The unit suite is red at this HEAD for unrelated reasons, so the evidence is
the failing *name set*, not the count. Two tests were added and both pass, one
of them a positive control against `applyLayout` being a no-op.

Fixture: `examples/layout_refinements_test.duo`, gated by
`scripts/run_compile_fail_tests.duo` (run by `zig build test`).
Positive-controlled: changing its expected output to `999` produces
`FAIL: examples/layout_refinements_test.duo output mismatch`, so the row
genuinely executes.

> Found while positive-controlling, and worth fixing separately:
> `run_compile_fail_tests.duo` prints its `FAIL:` lines but **never prints its
> `OK:` lines** — `grep -c '^OK:'` is 0 while 100+ rows pass. The assertions do
> run. But nobody should read that script's output as a pass count.

## The old spelling was not deleted

`@packed` / `@align` / `@sealed` / `@native` / `@guarded` still parse and still
work, and `examples/layout_attrs_test.duo` still proves it. Pass 100 forbids
the directive, not the fact, and removing a working spelling to move a grep
count is not the goal — ontology collapse is, and the ontology is now one.

**Real corpus cost of retiring the spelling later: zero.** `@packed` / `@align`
on a *record* have **no uses in `lib/`, `tools/` or `ext/`** — the two
`lib/tools/ext` grep hits are an LSP completion snippet string
(`tools/lsp/src/server.duo:1767`). The only writers are
`examples/layout_attrs_test.duo` and a raw-string test module in
`scripts/test_property_11.duo:129`.

## What step 3 did NOT cover

**Enum layout.** `@packed` / `@align` / `@ffi` on an `enum_def` store the same
facts into `enum_type.is_packed/.align_n/.ffi_name`, but the code is duplicated
three times by hand — `sema.zig:3832`, `codegen.zig:6104`, `codegen.zig:6847` —
and none of it routes through `types.zig`. It is the obvious next slice: the
three hand-rolled loops collapse onto `Layout` the same way. Left out to keep
this hunk minimal, and because both `codegen.zig` sites sit inside enum
emission another session is editing.
