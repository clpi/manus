# Pass 36/40/41 — Final semantic access (operational projection)

Operational projection of the final semantic-access and projection calculus.

- Canonical spec: [`duo_universal_semantic_access.md`](duo_universal_semantic_access.md)
- Machine-readable catalog: `src/pass36_catalog.zig` (`pass40-semantic-access-catalog-v2`)
- Gate: `zig build pass36-gate` (aliases: `semantic-access-gate`, `projection-gate`)
- Query: `duo catalog audit gate pass36`

## Pass history carried by these artifacts

| Pass | Contribution | Status here |
| --- | --- | --- |
| 36 | Unified algebra: edge, identity, inverse, implication, hierarchy, application schema | Retained; the algebra is the substrate |
| 38 | Projection closure (§§8–10, §15), demand/erasure, user control, directive unification | §§4–5, 7–12, 14–16 retained in full (S5); §§1–3, 6, 13 superseded |
| 39 | Reconciliation rulings R1–R6 and the governance rule | R1 dissolves (S6); R2–R6 carry forward; governance rule stands |
| 40 | Surface ruling: prefix `@` only, `meta` as a curried value | **Canon** (S4) |
| 41 | Native-first amendment: compat removed, ladder 10→8, `__` deleted | **Canon** (S7) |

## Phase 0 exit gate

- All 18 access forms recorded; every desugaring resolves to an existing form and every chain terminates
- All 11 grammar rules recorded; every one is prefix-`@`, `.@`, or `{ @` — none postfix
- All 14 graveyard entries recorded with a reason; no access form or grammar rule spells one
- **No access form is receiver-bound** — the executable form of the S6 dissolution
- Ladder recorded as 8 resolving rungs + structured failure, strict total order, `lexical` first, `descriptor` third
- No Lua-specific rung; `dynamic` is the last resolving layer
- `__` names appear only in `lua_adapter_targets` and graveyard reasons
- `!=` present and marked chosen-over-inherited; `~=` buried
- All 27 projection families recorded; non-demand-driven families cannot materialize
- All 8 conflict classes decidable; ambiguity rejects rather than falling through to the dynamic layer
- All 4 slot states recorded (implementation / `false` / `nil` / absent)
- All 20 completion gates route to a real execution phase
- Sealed-world conditions and guarantees recorded so G5 has something to check
- All 4 supersessions (S4–S7) recorded with ruling, supersedes, and rationale
- Zero parser/sema behavior change in Phase 0

## Current compiler state

`src/ast.zig` carries the Pass 40-shaped nodes:

| Node | Grammar rule | Shape |
| --- | --- | --- |
| `Expr.semantic` | G1 `@name` | `{ loc, op }` — no `obj`, no `level` |
| `Expr.semantic_scope` | G2 `@` | `Loc` |
| `TableField.semantic` | G8 `{ @eq = impl }` | `{ op, param, val }` |

The absent `obj` and `level` fields *are* the S4/S5 rulings landing in the AST:
under a postfix surface both would be required; under this one neither can exist.

No parser production constructs these nodes yet, so every consumer arm is
unreachable. `macro_expand.zig` reconstructs them on the clone path only. `sema`
refuses with a diagnostic, `codegen` emits a refusal comment — neither invents a
lowering before the resolution ladder exists.

## Measured blockers

`duo check` against `zig-out/bin/duo`, re-verified 2026-08-05 22:41 against the
current binary. This is what §1 of the canonical spec actually does today.

| Form | Today | Blocker |
| --- | --- | --- |
| `point.@eq` | `error: expected 'name', got '@'` | postfix field-access path demands a `name` token after `.` |
| `meta(instance)(p).@eq` | `error: expected 'name', got '@'` | same path |
| `@eq(a, b)` | `macro expansion error: UnknownMacro` | `@name(...)` is owned by the macro/directive expander |
| `{ @eq = f }` | `error: expected '(', got '='` | table-literal `@name` parsed as a directive call |
| `a @ b` | parses as matmul + non-canonical warning | **not a blocker** |
| `1 != 2` | checks clean | **already works** |
| `1 ~= 2` | checks clean | must be **deleted** (A5) |

### The infix-`@` supersession dissolves rather than executes

Earlier drafts recorded "retire infix `@` matmul" as the supersession blocking
the access grammar, with a whole phase for deleting `infix_prec(.at) => .matmul`
and migrating six pinning tests. Under the final surface `point.@eq` never places
`@` in infix position, so **the matmul arm may stay**, and none of the measured
blockers touch `infix_prec`. Tensor products keep using explicit APIs
(`Tensor.matmul`, `simd.matmul_f32/f64`).

### The supersession that does matter

`@eq(a, b)` failing with `UnknownMacro` means `@name(...)` in expression position
is already owned by the macro/directive expander. This is *convergent*, not
conflicting: the canon already rules that directives (`@comp`, `@target`,
`@stage`) are entries in the `@` world. The macro namespace absorbing semantic
lookup is the intended end state — that, not matmul, is the real supersession,
and it lands in phase P36-PH8.

## Measured purification surface (Pass 41)

Grep-level inventory of what A1/A2/A8 touch today — scope, not a fix estimate.

| Ruling | Surface | Measure |
| --- | --- | --- |
| A2 | Lua metamethod names in `src/*.zig` + `lib/std/*.duo` | 19 distinct names, 128 references — `__tostring` 23, `__add` 16, `__index` 15, `__len` 10 |
| A8 | `getmetatable` / `setmetatable` sites | `codegen.zig` 14, `sema.zig` 6, `lib/std/meta.duo` 4 |
| A1 | Lua-as-invariant machinery to reclassify as adapter | `lua_superset_catalog.zig` 223, `compat_layer_projection.zig` 139, `lua_superset_gate.zig` 132, `lua_superset_corpus.zig` 131, `lua_readiness.zig` 101 = **726 lines** |
| A5 | `~=` deletion | `src/lexer.zig:163` (`.neq => "~="`); `!=` already parses |

A1's 726 lines are **reclassified, not deleted** — the gate becomes an `@lua`
adapter parity suite rather than a language-identity requirement. That is a
change of *meaning* on a currently-passing gate, which under the convergence rule
needs its own supersession record rather than a silent edit.

## Pass lineage

Pass 40 cites Passes 35, 36 (Unified Algebra), and 39. **None are in this
repository.** Its citations of "Pass 38 §§1–3, 6, 13", "§§4–5, 7–12, 14–16",
"§16's twenty gates", and "§15.7 `run(world)(input)`" match the spec originally
drafted here as "Pass 36" section-for-section, which is why that document is
preserved under the Pass 38 name at
[`duo_projection_calculus.md`](duo_projection_calculus.md) /
[`pass38_projection_calculus.md`](pass38_projection_calculus.md).

Absent documents are recorded as **cited-but-absent** rather than reconstructed;
clauses depending on them stay `UNRESOLVED` rather than guessed.

## Cross-links

| Item | Related artifact |
| --- | --- |
| Grammar corpus | `parser.zig`, `pass21_canonical_grammar_closure.md`, Tree-sitter fixtures |
| Resolution ladder | `sema.zig`, `semantic_graph.zig`, Pass 26 operation identity |
| Semantic call object | `pass24_unified_calls_concurrency_constitution.md` |
| Sealed-world collapse (G5) | Pass 34 `L1` module sealing, `U5` closed world, `L6` manifest |
| Projection provenance | Pass 34 `C2` descriptor identity, `C1` location |
| Projection invalidation | Pass 34 `E10` incremental semantic invalidation |
| Projection budget | Pass 34 `U10` compile budget planner, `E4` compile-time cost |
| Demand / erasure | Pass 34 `L12` effect elimination, `L7` dispatch |
| `@lua` adapter | `foreign_adapter.zig`, `compat_layer_projection.zig`, `lua_superset_gate.zig` |
| Cross-language projections | `foreign_transpile.zig` |
| Reverse edits | Pass 34 `U15` semantic diff/patch/merge |

## Execution phases

| Phase | ID | Focus | Exit gate |
| --- | --- | --- | --- |
| 0 | P36-PH0 | Record the calculus | catalog queryable, every desugaring resolves, zero compiler change |
| 1 | P36-PH1 | Bury the graveyard in the grammar corpus | every rejected form is a parse error with a named reason |
| 2 | P36-PH2 | Semantic access grammar | gates 1–3; formatter + Tree-sitter fixtures stable |
| 3 | P36-PH3 | Application normalization and ladder | gates 4, 5, 7, 9; one call identity across all spellings |
| 4 | P36-PH4 | `meta` and `meta(level)` | gate 8; exact-level read and write |
| 5 | P36-PH5 | Endpoint, operator and foreign projections | gates 6, 15, 19; one shared edge id |
| 6 | P36-PH6 | Demand analysis and erasure | gates 10, 12, 13, 14 via L6 manifest deltas |
| 7 | P36-PH7 | Provenance, conflicts, authority, budgets | gates 11, 16, 17 |
| 8 | P36-PH8 | Directives as world entries | gate 18; `@comp`, `@(expr)`, `@{}` unified |
| 9 | P36-PH9 | Prove on Ward and the self-hosted compiler | gate 20; rung-3 resolution on hot paths |

Phase 1 comes *before* Phase 2 deliberately. Burying the rejected forms first
means no window exists in which two access mechanisms both parse — the
dual-mechanism entropy the convergence rule forbids.

## Non-goals for Phase 0

- No parser change. No form in §1 of the canonical spec parses yet.
- No eager projection generation. An unconsumed projection is a graph fact,
  never an emitted symbol.
- No capitalization-based role inference. Descriptor-vs-instance role comes from
  the semantic graph — and under S6 the question mostly stops being asked,
  because retrieval is never receiver-bound.
- No re-litigating S4. The scorecard that produced it was already scored on the
  criteria Pass 41 left in force; compat was not a decisive input to any row.
