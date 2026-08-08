# Pass 3 — Directive Surface, Grammar Minimalism, and Convergence

> **Date:** 2026-08-04
> **Follows:** Pass 1 (unified philosophy), Pass 2 (convergence algebras)
> **Mission:** Operationalize Passes 1–2 across the directive surface, keyword retirement,
> declaration grammar, compact syntax, and the full toolchain.

---

## A. Executive Findings (ranked by leverage)

### 1. Duo has 53 keywords — target is 30

The lexer reserves 53 keyword tokens. Only 30 are semantically indispensable for canonical .duo.
23 are retirement candidates: 3 should be removed immediately (`macro`, `comptime`, `let`),
4 deprecated in formatter (`then`, `do`, `fun`, `private`), 5 migrated to descriptor syntax
(`enum`, `concept`, `alias`, `extends`, `match`), and the rest kept for .lua compatibility only.

**Catalog:** `docs/catalogs/keywords.md`

### 2. The directive surface is rich but inconsistent

~130 registered directives map to ~85 unique semantic operations. 65 have codegen handlers;
~20 are registered but unwired. The three-tier model (top-level / short alias / namespaced)
is conceptually sound but not explicitly tracked per-directive. Legacy flat/underscore aliases
(~52 entries in parser.zig) bypass the meta_module guard.

**Action:** Assign explicit tiers to every directive. Deprecate flat aliases with hints.

**Catalog:** `docs/catalogs/directives.md`

### 3. `@{}` descriptor syntax would retire 5 keywords at once

`enum`, `concept`, `alias`, `extends`, and potentially `match` can all collapse into
descriptor-shaped `@{}` declarations with the same underlying mechanism:

```duo
Color: @{ Red, Green, Blue }          -- replaces `enum Color`
Hashable: @{ hash(self): u64 }        -- replaces `concept Hashable`
Sprite = Named + Positioned           -- replaces `extends`
```

This is the highest-leverage grammar change: one mechanism replaces five keywords.

### 4. Field projections and method references are free wins (prefer call syntax)

`.name` and `:method` as callback shorthand require minimal parser work:

```duo
map(users, .name)
each(filter(users, .active), print)
```

**Canonical:** nested calls and `map(data, .field)` — not `|>` pipeline chains.
Projections lower to `(v) v.name` and `(v) v:method()` with no runtime cost.

### 4b. Deprioritize confusing symbolic operators

Surface operators that overload familiar tokens or mimic other languages are **implemented
for compatibility** but **not canonical** in `.duo`:

| Operator | Example | Prefer instead |
| --- | --- | --- |
| `\|>` | `x \|> f` | `f(x)` |
| `@` (infix) | `a @ b` | `duo_tensor_matmul(a, b)` or typed ML APIs |
| Chained `\|>` | `a \|> .x \|> .y` | `a.x.y` or explicit field access |

Parser emits warnings in `.duo` mode. See `docs/catalogs/grammar_compactness.md` §Deprioritized.
Pass 2 pipeline **graph IR** remains internal; do not expand `\|>` surface syntax.

### 5. Table spread (`..expr`) is the missing structural primitive

Without spread, every table merge requires imperative loops. With it:

```duo
merged = { ..defaults, ..config, override = true }
User: @{ ..Named, id: i64 }
```

This connects directly to Shape Algebra (`merge` operation) and descriptor composition.

### 6. Direct iteration protocol simplifies the most common loop pattern

```duo
for value in values    -- instead of: for _, value in ipairs(values)
```

One binding = value iteration. Two bindings = key + value. This retires `ipairs`/`pairs`
from idiomatic code without removing them.

### 7. The Knowledge Lattice is wired but underutilized

`Symbol.knowledge()`, `exprKnowledge()`, `symbolKnowledge()` exist in sema but are
not consumed by codegen decision points. The lattice determines native vs. boxed emission
at module level but not per-expression. Wiring per-call lattice queries into emission
would automatically eliminate more `lua_invoke` boxing.

### 8. 20 registered directives have no codegen handler

Including `comp.product`, `comp.derive.permute`, `comp.foreign`, `comp.schema`,
`comp.sql`, `comp.run`, and several `comp.str.*` and `comp.field.*` intrinsics.
These are registered promises without implementation — confusing for agents and users.

### 9. Pipeline graph IR (internal) — surface `|>` deprioritized

`transform_engine.zig` registers `pipeline.*` ops for the semantic graph and `@comp.pipeline`
module descriptors. **Do not promote** the `|>` infix operator as idiomatic `.duo` syntax;
prefer `f(x)` and `map(items, .field)`. Native lowering for legacy `|>` exists; fused
`pipeline_gen` backend is low priority vs knowledge lattice and descriptor grammar.

### 10. Formatter does not yet enforce deprecated keyword removal

`then` and `do` are deprecated but the formatter preserves them. A `--canonical` mode
that strips unnecessary keywords would make the deprecation actionable.

---

## B. Ranked Implementation Plan

| Priority | Workstream | Leverage | Prerequisite |
| --- | --- | --- | --- |
| 1 | Keyword + directive + grammar catalogs (this document) | Foundation | None |
| 2 | Formatter `--canonical` mode (strip then/do, normalize directives) | Visible | Catalogs |
| 3 | `@{}` descriptor grammar (keywordless enum/record/protocol) | 5 keywords retired | Parser |
| 4 | Field projections `.name` in call context | Pipeline ergonomics | Parser |
| 5 | Table spread `..expr` | Structural primitive | Parser + codegen |
| 6 | Direct iteration protocol | Loop ergonomics | Sema iterator dispatch |
| 7 | Wire per-call knowledge lattice into codegen decisions | Boxing elimination | Pass 2 spine |
| 8 | Deprecation hints for flat/underscore directive aliases | Consistency | Parser |
| 9 | Pipeline transform registration in transform_engine | Architecture | ✅ done (2026-08-04) |
| 10 | Method references `:name` in call context | Pipeline ergonomics | Projections first |
| 11 | Named destructuring `{ a, b } = t` | Ergonomics | Parser |
| 12 | Binding conditions `if x = expr` | Control flow | Parser |
| 13 | Wire unwired directives or remove registrations | Consistency | Audit (done) |
| 14 | Selective import `{ encode, decode } = req "std.json"` | Module ergonomics | Destructuring |
| 15 | `@export` as canonical visibility mechanism | Replaces `private` keyword | Parser |

---

## C. Architectural Convergence Map

| Duplicated Today | Target Unified Foundation |
| --- | --- |
| `enum` keyword + descriptor `@{}` | Descriptor algebra |
| `concept` keyword + structural satisfies | Descriptor algebra |
| `extends` keyword + `+` composition | Descriptor algebra |
| `alias` keyword + `=` binding | Ordinary typed binding |
| `match` keyword + table dispatch | Pattern recognition transform |
| `native_scalar_mode` + `module_knowledge` | Knowledge Lattice (unified) |
| `lua_invoke` vs direct call | Call Algebra (CallSite transform) |
| `fold_meta_string_expr` + `comptimeMetaHook` + `maybe_emit_meta_string_call` | Transformation Registry |
| Parser flat aliases + meta_module registry | Single directive catalog |
| LSP server reimplements sema logic | Shared semantic graph queries |
| MCP text scraping | Structured semantic API |

---

## D. Pass 3 Agent Protocol

Before implementing any workstream:

1. Read this document + `docs/catalogs/keywords.md` + `docs/catalogs/directives.md` + `docs/catalogs/grammar_compactness.md`
2. Check if the feature collapses multiple mechanisms (Pass 2 principle)
3. Claim in `.agents/AGENT_COORDINATION.md`
4. Implement the smallest durable prerequisite (not the full feature)
5. Add tests + update the relevant catalog
6. Verify: `zig build` + relevant unit tests

### Decision checklist (from prompt §44)

For every proposal:
- Can this be expressed as a descriptor?
- Can this be expressed as a shape operation?
- Can this be expressed as a directive?
- Does it reduce the number of core mechanisms?
- Will it still look coherent in ten years?

---

## E. Tooling Impact Summary

| Tool | Pass 3 Actions |
| --- | --- |
| **Formatter** | Add `--canonical` mode; strip `then`/`do`; normalize directive paths |
| **Tree-sitter** | Add bare function, if-expression, `@{}` descriptor nodes |
| **LSP** | Directive tier in completion; `@comp.why` hover; deprecated keyword hints |
| **MCP** | Expose keyword/directive/grammar catalogs as structured tools |
| **Migration** | `duo fmt --migrate` converts deprecated forms to canonical |

---

## F. Coordination

| Deliverable | File |
| --- | --- |
| Executive findings | `docs/plans/pass3_directive_grammar_convergence.md` (this) |
| Keyword catalog | `docs/catalogs/keywords.md` |
| Directive catalog | `docs/catalogs/directives.md` |
| Grammar catalog | `docs/catalogs/grammar_compactness.md` |
| Convergence map | `docs/catalogs/convergence.md` |
| Performance barriers | `docs/catalogs/performance_barriers.md` |
| Catalog index | `docs/catalogs/README.md` |
| **Machine-readable JSON** | `duo catalog` → `src/pass3_catalog.zig` |
| Pass 2 algebras JSON | `duo algebra` |
| Pass 2 convergence | `docs/plans/pass2_foundational_convergence.md` |
| Architecture plan | `docs/plans/semantic_graph_architecture.md` |
| Agent compass | `docs/AGENT_ALIGNMENT.md` |
| Coordination | `.agents/AGENT_COORDINATION.md` |

---

*Pass 3 is not about adding features. It is about making the existing architecture visible,
consistent, and actionable — so that every future addition collapses mechanisms instead of accumulating them.*

---

## Pass 3.0 progress (2026-08-04)

| Deliverable | Status |
| --- | --- |
| Keyword catalog (53 → target 30) | ✅ `docs/catalogs/keywords.md` |
| Directive tier catalog | ✅ `docs/catalogs/directives.md` |
| Grammar compactness catalog | ✅ `docs/catalogs/grammar_compactness.md` |
| Convergence + performance barrier maps | ✅ `docs/catalogs/convergence.md`, `performance_barriers.md` |
| Machine-readable export | ✅ `duo catalog` → `src/pass3_catalog.zig` |
| Workstream tracker (15 items) | ✅ JSON `workstreams` array |
| Transform registry summary | ✅ pipeline/call/shape counts in `duo catalog` |

## Pass 3.1 progress (2026-08-04)

| Workstream | Status |
| --- | --- |
| P3-03 `@{}` descriptor (enum, record, spread, payloads) | ✅ |
| Pass 2.5 pipeline chain fuse (`\|> .x \|> .y` → native field chain) | ✅ compat only; **deprioritized** |
| Symbolic operator policy (`\|>`, infix `@`) | ✅ catalog + parser warnings |
| P3-07 per-call knowledge lattice | 🔄 partial |
| P3-08 flat alias deprecation warnings | ✅ (legacy_directives + duo-mode warnings) |
| P3-13 unwired directives | 🔄 partial |
