# Path migration ledger (PATH-ONE)

Projection of C0 `law.path.name` and GAP-163. Not semantic law.

## Rule

Project-controlled semantic paths obey the same lowercase one-word law as source
identifiers. Forbidden on **new** paths: underscores, compounds, numeric taxonomy
suffixes, mashed abbreviations.

Renaming without semantic decomposition is forbidden (`abi_matrix` → `abimatrix`).

## Classification

| Path | Class | Target / gate |
|---|---|---|
| `scripts/abi_matrix.id` | tool/workflow | decompose ABI matrix concern or relocate under `tools/` with one irreducible name |
| `scripts/bootstrap_scan.id` | bootstrap | ledger until Idol bootstrap scan owns fact; ratchet |
| `scripts/parser_corpus_coverage.id` | compound | `scripts/corpus/` home + `coverage.id` or merge into census owner |
| `scripts/language_census2.id` | numeric suffix | merge into `scripts/language_census.id` or rename without suffix |
| `scripts/idiomgate.id` | deleted | authority is `gate/idiom.id` |
| `scripts/duo_idiom_gate.id` | deleted | `gate/idiom.id` + `gate/build.id` own transport |
| `scripts/semanticgate.id` | bootstrap census | delete when GAP-124 graph gate owns staged verdicts |
| `scripts/module_surface_gate.id` | bootstrap smoke | keep until module privacy is graph fact |
| `scripts/stdlib_embed_gate.id` | bootstrap embed | delete under GAP-157 std home migration |
| `scripts/stdlib_correctness_gate.id` | bootstrap embed | delete under GAP-157 |
| `scripts/run_wasm_benchmark.id` | workflow | `tools/wasm/bench/` or single operational name |
| `scripts/run_cross_benchmark.id` | workflow | `tools/bench/` or single operational name |
| `src/benchmark_evidence.zig` | foreign bootstrap | delete when benchmark evidence executes in Idol (GAP-090 ledger) |
| `src/assumption_guard.zig` | foreign bootstrap | delete when profile guard is graph fact (GAP-085) |

## Enforcement

- **New paths:** `gate/path.id` on staged added/renamed paths — zero violations.
- **Existing debt:** ratchet via `gate/census.id`; classify before rename.
- **Agents:** record `PATH-SEMANTICS-BLOCKED` when decomposition is unclear; do not mint compound filenames.

## Census

```bash
git ls-files | rg '(^|/)[^/]*[_0-9][^/]*\.(id|zig)$' | head
```

Full census is gate-owned; this ledger is the migration schedule.
