# Pass 21 — Canonical Grammar Closure

Keyword retirement, table-native dispatch, and high-leverage syntax compression.

**Status:** M0 tracking + keyword registry (2026-08-05).  
**Mission:** One predictable parse, one canonical lowering, one formatter result, one semantic representation per accepted form.

## Governing thesis (§1)

Dispatch and control-flow ceremony should lower through semantics Duo already owns:

```
match/switch/case  →  table lookup + call  →  compiler-recognized dispatch
then/do/local      →  canonical blocks, scope, iteration (Lua forms remain valid per Pass 24)
```

## Grammar authority (§2)

| Owner | Consumers |
| --- | --- |
| Compiler (lexer/parser/sema/codegen) | Tree-sitter, LSP, MCP, docs, Ward |
| `src/pass21_keyword_registry.zig` | Machine-readable keyword lifecycle |
| `docs/GRAMMAR_SPEC.md` | Cross-session grammar ledger (GR-*) |

No tool may independently decide canonical vs deprecated syntax.

## Implementation phases (§46)

| WS | Phase | Status | Owner |
| --- | --- | --- | --- |
| P21-WS0 | Repository truth | partial | `parser.zig`, `GRAMMAR_SPEC.md` |
| P21-WS1 | Keyword registry | partial | `pass21_keyword_registry.zig` |
| P21-WS2 | Retire `then` / loop `do` | **superseded** | Pass 24: `supported_compatibility`; formatter may canonicalize |
| P21-WS3 | Scope + direct iteration | partial | `sema.zig`, GR-003 |
| P21-WS4 | Dispatch semantics | open | `sema.zig`, `codegen.zig` |
| P21-WS5 | Retire `match` | open | migration + exhaustiveness |
| P21-WS6 | Easy grammar wins | partial | projections, destructuring |
| P21-WS7 | Ecosystem closure | open | tree-sitter, LSP, MCP, Ward |
| P21-WS8 | Remove dead grammar | open | after migration |

## M0 delivered

- **Keyword registry** — 56 lexer keywords with classification + lifecycle
- **Parser** — `then`/`do` optional with duo_mode hints (existing)
- **Gates G01/G02 partial** — if/while/for parse without ceremonial tokens
- **Catalog** — audits A–G tracked; 20 success-criteria gates

## Completion gates (§48 subset)

Validate: `zig build pass21-gate`

| Gate | Title | M0 |
| --- | --- | --- |
| G01 | `then` removable | partial |
| G02 | loop `do` removable | partial |
| G04 | `match` noncanonical | partial (registry; still parses) |
| G08 | `local` unnecessary | partial (GR-003) |
| G10 | if-expressions | partial (GR-002) |

## Prohibited outcomes (§47)

No second pattern language; no match subsystem replacing tables; no indentation-only blocks; no blind match→table migration for nonlocal control flow.

## Commands

```bash
zig build pass21-gate
duo catalog audit gate pass21
duo catalog   # includes pass21 JSON
```

## Related

- [`docs/catalogs/keywords.md`](../catalogs/keywords.md) — Pass 3 inventory
- [`docs/GRAMMAR_SPEC.md`](../GRAMMAR_SPEC.md) — GR rules
- [`pass3_directive_grammar_convergence.md`](pass3_directive_grammar_convergence.md)
