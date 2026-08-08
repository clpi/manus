# Pass 23 — Unified Metaprogramming, Native Metaprogramming, Function Compression, Conversion, Lifecycle, and Semantic Closure

**Status:** M0 tracking (2026-08-05)  
**Mission:** One compact, Lua-native semantic architecture for functions, methods, assignment values, conversion, formatting, operators, construction, lifecycle, borrowing, references, protocols, reflection, compile-time execution, derivation, foreign adaptation, and custom compiler-visible behavior.

**Governing principle:** Ordinary Duo values and functions express semantics. Compiler knowledge progressively removes their representation and dispatch cost.

## Repository owners

| Area | Files |
| --- | --- |
| Protocol kernel + Lua aliases | `src/pass23_protocol_registry.zig` |
| Catalog + migration/deferred registry | `src/pass23_catalog.zig` |
| Gate proofs (M0) | `src/pass23_gate.zig` |
| Parser (function syntax) | `src/parser.zig` |
| Semantic lowering | `src/sema.zig`, `src/semantic_graph.zig` |
| Codegen / native paths | `src/codegen.zig`, `src/dnir_lower.zig` |
| Metaprogramming | `src/comptime.zig`, `@comp.*`, `src/transform_engine.zig` |
| Tooling | `~/x/duo-lsp`, `~/x/duo-mcp` |

## Validate

```bash
zig build pass23-gate
duo catalog | jq '.pass23'
```

### Parser (canonical syntax smoke)

- `add = (a, b) a + b` — single-expression body, no `end`
- `Person:greet = (other) …` — colon method assign, implicit `self` prepended
- `math.add = (a, b) a + b` — dot static member assign
- `add_named = (a, b): i64` / `sum = a + b` / `end` — trailing assignment is implicit return
- `double = (x): i64` / `x *= 2` / `end` — compound assign yields updated value

## Architecture invariants (do not break)

- **No shadow ASTs** for protocols, conversions, methods, or reflection — lower to assignment + func_expr + descriptors + semantic graph facts.
- **One function representation** — name from binding, receiver from `:` policy, static member from `.`.
- **`@` is explicit compiler authority** — not required for naturally compile-time descriptor construction.
- **Progressive erasure** — dynamic lookup → sealed/specialized → inline graph → native elimination.
- **No `lua_Value` on typed/comptime paths** (inherits Pass 4/22 rules).
- **Do not delete legacy paths** before migration parity (ConceptDef, macros, method flags, `__*` names).

## Workstreams (P23-WS0 … P23-WS15)

See `src/pass23_catalog.zig` — tracked in `duo catalog` JSON under `"pass23"`.

| WS | Title | Status |
| --- | --- | --- |
| P23-WS0 | Repository truth map | partial |
| P23-WS1 | Protocol identity registry | partial |
| P23-WS2 | Canonical function syntax | partial |
| P23-WS3 | Methods/receiver policy | partial |
| P23-WS4 | Assignment expression semantics | partial |
| P23-WS5 | Return consumption specialization | partial |
| P23-WS6 | Descriptor-first types | open |
| P23-WS7 | Concept → descriptor migration | open |
| P23-WS8 | Unified conversion graph | partial |
| P23-WS9 | Formatting + interpolation | partial |
| P23-WS10 | Metaprotocol laws + resolution | open |
| P23-WS11 | Lifecycle + borrowing | open |
| P23-WS12 | Native metaprogramming + derivation | partial |
| P23-WS13 | Legacy migration | open |
| P23-WS14 | LSP/MCP exposure | open |
| P23-WS15 | Ward proof workload | open |

## Exit gates (§27)

Twenty completion gates tracked in `pass23_catalog.completion_gates` (P23-G01 … P23-G20). M0 proves:

- **G01/G05** — assign-form multiline function parse smoke
- **G02/G03/G04** — compound assign, trailing assign return, colon/dot method assign
- **G09** — `{ident}` string interpolation parse desugar + sema
- **G10** — Lua alias registry (+ `protocol_kernel` compat shim)
- **G15** — return consumption (semantic graph + DNIR discard)
- **G19** — factorial accumulator explicitly deferred (P23-D01)
- **G16** — migration targets registered

## Explicitly deferred (§5)

**P23-D01:** ~~Implicit accumulator return / live-out inference deferred~~ **Superseded by Pass 25 §5.1** — tail-demand propagation through result lineage (loop/branch phi), not backward local search.

**Rejected:** `@return`, named return bindings, live-local guessing (P23-D02).

## Prohibited outcomes (§26)

Catalog gate **P23-G20** tracks prohibited patterns: no `@return`, no bracket/angle generics canonically, no separate concept/trait AST, no user-visible `$discard` clone names, no indentation-as-semantics globally, etc. Full list in agent spec §26.

## Canonical examples (target syntax)

```duo
add = (a, b) a + b
Vec:xplus = (amt): i32 self.x += amt
Person:greet = (other) "Hey {other}, I’m {self}"
Comparable = @{ compare: (self, other): Ordering }
employee = person:to(Employee)
```

Single-expression bodies without `end` are **supported** for assign-form and parenthesized func-expr (P23-WS2); multiline assign-form with `end` remains required for statement bodies.

## Migration map (§21)

| Legacy | Canonical |
| --- | --- |
| `FuncDecl` / bare `fun` | assignment + func_expr |
| `ConceptDef` | descriptor of required members |
| Generic `<T>` / `[T]` | descriptor values + specialization |
| `__add` etc. | `pass23_protocol_registry` |
| `MacroDef` / quote | staged semantic functions |
| `method` flag | callable member + receiver policy |

## Next implementation priorities

1. **P23-WS2** — single-expression assign bodies without mandatory `end`
2. **P23-WS3** — `Type:method = (…) …` colon assignment + implicit `self`
3. **P23-WS4** — assignment expression value in sema/codegen (compound assign tail)
4. **Wire protocol registry** into codegen metamethod dispatch (replace scattered `__*` matching)
5. **P23-WS8** — conversion graph skeleton in semantic graph

## Relation to other passes

- **Pass 21** — grammar closure (keywords, dispatch tables) — Pass 23 builds semantic model on top
- **Pass 22** — region graph, realization, hardware — Pass 23 feeds call/protocol facts into graph
- **Pass 20** — foreign metaprogramming harness — Pass 23 unifies native + foreign protocol surface
- **Pass 25** — semantic unification (descriptors, lifetimes, views, bidirectional meta) — subsumes open P23-WS6 (descriptor-first) and P23-WS11 (lifecycle/borrow/view); see [`pass25_native_semantic_unification.md`](pass25_native_semantic_unification.md)
