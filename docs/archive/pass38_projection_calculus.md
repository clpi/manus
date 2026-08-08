> **HISTORICAL — superseded by `docs/spec/pass100.md`. Not an architecture input.**

# Pass 38 — Maximum Projection Calculus (operational projection)

> **Renumbered 2026-08-05** from "Pass 36" to match Pass 40's S5 supersession
> chain. **Surface superseded by Pass 40**; the Phase 1 "retire infix `@` matmul"
> step below is **dissolved** — see the S1 note.

Operational projection of the canonical projection calculus.

- Canonical spec: [`duo_projection_calculus.md`](duo_projection_calculus.md)
- Machine-readable catalog: `src/pass36_catalog.zig` (`pass36-semantic-access-catalog-v1`)
- Gate: `zig build pass36-gate` (aliases: `semantic-access-gate`, `projection-gate`)
- Query: `duo catalog audit gate pass36`

## Phase 0 exit gate

- All 7 grammar forms (§13) recorded with precedence band and parse shape
- All 10 resolution levels (§7) recorded in strict order, each mapping to a semantic level
- All 10 semantic-call-object fields recorded
- All 27 projection families (§8.1–8.19, §10.1–10.8) recorded with demand-driven and materializing flags
- All 12 operator projections (§8.4) and 10 Lua metamethod projections (§8.5) recorded
- All 8 conflict classes (§15.2) recorded with a deterministic resolution outcome
- All 9 projection authority classes (§15.5) recorded and totally ordered
- All 9 demand sources (§9.1) recorded
- All 20 completion gates (§16) recorded, each with an evidence surface
- Every access form's desugaring names a form that exists in the catalog
- `expr@name` grammar recorded as **blocked** behind the infix-matmul supersession
- Zero parser/sema change in Phase 0

## The blocking supersession — DISSOLVED by Pass 40

> **S1 no longer blocks anything.** S1 exists because postfix `point@eq` collides
> with infix `a @ b`. Pass 40 spells semantic access `point.@eq`, so `@` is never
> in infix position and **the matmul arm can stay**. Phase 1 below — deleting
> `infix_prec(.at)`, dropping the `.matmul` sema arm, migrating six tests — is
> unnecessary work on a breaking change.
>
> Measured against the built binary (`duo check`, 2026-08-05), the real blockers
> for the Pass 40 surface are different and smaller:
>
> | Form | Today | Actual blocker |
> | --- | --- | --- |
> | `point.@eq` | `error: expected 'name', got '@'` | postfix field-access path demands a `name` token after `.` |
> | `meta(instance)(p).@eq` | `error: expected 'name', got '@'` | same path |
> | `@eq(a, b)` | `macro expansion error: UnknownMacro` | `@name(...)` is owned by the macro/directive expander |
> | `{ @eq = f }` | `error: expected '(', got '='` | table-literal `@name` parsed as a directive call |
> | `a @ b` | parses as matmul + non-canonical warning | **not a blocker** |
>
> None of these touch `infix_prec`. The `@name(...)` row is *convergent* rather
> than conflicting: Pass 38 §12 already rules that directives are entries in the
> `@` world, so the macro namespace absorbing semantic lookup is the intended end
> state — that, not matmul, is the supersession worth recording.

## The blocking supersession (as originally recorded — superseded)

`src/parser.zig:3282` maps `.at` to `BinOp.matmul` (precedence 19/20). `point@eq`
therefore parses today as `point matmul eq`, and `src/sema.zig:2759` type-checks
that operator against tensor shapes. Two line-based heuristics
(`parser.zig:3227`, `parser.zig:3349` — "`@` on a later line is an attribute
prefix") already paper over the resulting ambiguity, and the parser emits a
non-canonical warning for infix `@` in `duo_mode` (`parser.zig:3359`).

Per the Pass 34 convergence rule, a supersession closes **only when the incumbent
is deleted**. `S1` in the catalog records this: while `S1` is open, the matmul
arm must still be present; once `S1` reaches `adopted`, `infix_prec` must no
longer return `.matmul` for `.at`. The gate checks both directions.

Tensor products move to explicit APIs (`Tensor.matmul(a, b)`), which
`lib/std/ml/nn.duo:100` and `lib/std/simd.duo` already use.

## Cross-links

| Item | Related artifact |
| --- | --- |
| Grammar forms | `parser.zig` `infix_prec` / `parse_one_attribute`, `pass21_canonical_grammar_closure.md` |
| Resolution order | `sema.zig`, `semantic_graph.zig`, Pass 26 operation identity |
| Semantic call object | Pass 24 unified call algebra (`docs/archive/pass24_unified_calls_concurrency_constitution.md`) |
| Projection provenance (§15.1) | Pass 34 `C2` descriptor identity, `C1` location |
| Projection invalidation (§15.3) | Pass 34 `E10` incremental semantic invalidation |
| Projection budget (§15.4) | Pass 34 `U10` compile budget planner, `E4` compile-time cost |
| Projection authority (§15.5) | Pass 34 `U1` verified agent hints, `U14` proof minimization |
| Demand/erasure (§9) | Pass 34 `L12` effect elimination, `L7` metamethod dispatch |
| Gate 13 (no unobserved metatables) | Pass 34 `L6` representation manifest |
| Gate 20 (zero dynamic dispatch) | Pass 34 `L1` module sealing, `U5` closed world, `L6` manifest |
| Reverse edits (§8.19) | Pass 34 `U15` semantic diff/patch/merge |
| Cross-language (§8.16) | `foreign_adapter.zig`, `foreign_transpile.zig`, `compat_layer_projection.zig` |
| Lua compatibility (§8.5, gate 19) | `lua_superset_gate.zig`, `lua_readiness.zig` |

## Execution phases

| Phase | ID | Focus | Exit gate |
| --- | --- | --- | --- |
| 0 | P36-PH0 | Record the calculus | catalog queryable, every desugaring resolves, zero compiler change |
| 1 | P36-PH1 | Retire infix `@` matmul | `S1` adopted: `infix_prec(.at)` returns null, tensor tests moved to `Tensor.matmul` |
| 2 | P36-PH2 | Grammar: `expr@name`, `expr@name(args)`, `@name` | gates 1–4, formatter + Tree-sitter fixtures stable |
| 3 | P36-PH3 | Resolution order + semantic call object | gates 5, 7, 9; one call identity across all five spellings |
| 4 | P36-PH4 | Level selection `expr@(level)@name` | gate 8; assignment default is instance-local |
| 5 | P36-PH5 | Endpoint + operator + Lua projections | gates 6, 19; `Point@to(str)` ≡ `str@from(Point)` shares one edge ID |
| 6 | P36-PH6 | Demand analysis and erasure | gates 10, 12, 13, 14 via `L6` manifest deltas |
| 7 | P36-PH7 | Provenance, conflicts, authority, budgets | gates 11, 16, 17 |
| 8 | P36-PH8 | Directive reinterpretation under `@` namespace | gate 18; `@comp` / `@(expr)` / `@{}` unified |
| 9 | P36-PH9 | Prove it on Ward + self-hosted compiler | gate 20: zero dynamic semantic dispatch on hot paths |

## Non-goals for Phase 0

- No parser change. `expr@name` does not parse in Phase 0 and must not be made to
  "work alongside" matmul — that is exactly the dual-mechanism entropy the
  convergence rule forbids.
- No eager projection generation. §9 is normative from the start: an unconsumed
  projection is a graph fact, never an emitted symbol.
- No capitalization-based role inference. §2.3 and §3.2 are explicit that
  descriptor-vs-instance role comes from the semantic graph.
