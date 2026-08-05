# Architectural Convergence Catalog

> **Pass 3 reference.** Duplicated mechanisms → unified foundations.  
> **Pass 6 audit:** [`docs/plans/pass6_architectural_reconciliation.md`](../plans/pass6_architectural_reconciliation.md)  
> **JSON:** `duo catalog` → `pass6` + `duo algebra` (`convergence` array)

| Duplicated Today | Unified Foundation | Status |
| --- | --- | --- |
| `enum` / `concept` / `alias` / `extends` keywords | Descriptor algebra (`@{}`, `+`, `~`) | 🔄 partial |
| `native_scalar_mode` + scattered type checks | Knowledge lattice | 🔄 partial |
| `lua_invoke` vs direct C call | Call algebra (`CallSite` transforms) | 🔄 partial (Pass 2.5) |
| Meta fold paths (3+ dispatch sites) | Transformation registry | 🔄 partial — P6-07 gate wired |
| Parser flat `@` aliases + `meta_module` | Single directive catalog | 🔄 Pass 3 |
| LSP reimplemented sema | Semantic graph / SIM queries | 🔄 partial (P5-09) |
| MCP text scraping | `duo catalog` / graph / SIM API | 🔄 Pass 3/5 |
| Separate type vs descriptor AST | DescriptorExpr graph nodes | 🔄 partial |
| C header → native call | `c_frontend` → `c_sim_import` → `foreign_adapter` | ✅ Pass 5 P5-M1 |
| `@comp.c.import` vs `@c.import` | `meta_module` canonical `@comp.c.*` | ✅ Pass 5 |
| Graph JSON vs SIM JSON | SIM projection from graph lift (R-02) | 🔄 partial (DUP-001) |
| Pipeline `\|>` as chained calls only | Pipeline graph IR + fusion | 🔄 partial (all `pipeline.*` registered) |
| Call transforms provenance-only | `call.memo`/`inline`/`specialize` dispatch | ✅ Pass 2.5 |
| `@comp.product` registered, unwired | Transform registry + P6-07 dispatch | ⬜ open |

**Dependency order:** knowledge lattice → shape facts → descriptors → call specialization → representation → explanations.

See also: [`docs/plans/pass2_foundational_convergence.md`](../plans/pass2_foundational_convergence.md)
