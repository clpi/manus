| field | value |
|---|---|
| title | Graph-shape audit — wasm ingest evidence vs compiler sim-v0 (measured) |

| # | directive |
|---|---|
| 1 | Compiler graph of ingest.id itself: 741 nodes, 1,105 edges, 95 published applications (of 113 candidates, 17 bootstrap, 1 blocking), 15 bodies with recurrence regions, 2 worlds. |

| section |
|---|---|
| Field-level delta (my records vs the compiler's applications[]) |

| Missing from my records (compiler HAS) | Fix |
|---|---|
| `caller` (enclosing relation id) | emit fn index — already known (fi) |
| `arguments` / `results` as NODE references | my `operands` are app numbers; the graph uses node ids — switch to per-body node allocation or keep app-refs and document the projection |
| `provenance` {file, start, end} | byte offsets — available at read time (at) |
| `applied` card {one/none/unknown + id} | emit card:"one" + relation number for calls; "unknown" for binops until published |
| `effect` / `authority` / `witness` / `realization` cards | emit explicit card:"unknown" — presence proves schema coverage only; the fact remains unresolved |

| My fields the compiler LACKS (wasm-native) | Ruling |
|---|---|
| `width`, `overflow`, `origin`, `determinacy` | keep — foreign-law inputs the graph should admit as descriptor/provenance facts (fact-separation ruling: separate families, not bundled) |

| section |
|---|---|
| Conformance verdict |

| # | directive |
|---|---|
| 1 | Records are shape-adjacent evidence, not semantic graph applications. |
| 2 | The sequential application counter, Wasm function index, operand counter, and local relation label are provenance/classification data; they are not substitutes for exact graph identities. |
| 3 | The wasm-native fields (width/overflow/origin/determinacy) are foreign-law inputs and must not be flattened away. |
| 4 | Closure requires the Wasm-law producer to publish exact shared graph ids and facts, not a consumer-side renumbering. |

| section |
|---|---|
| Performance opportunities identified this audit |

| # | directive |
|---|---|
| 1 | **app-refs → node-ids**: emitting node-id references enables the graph's demand pass to consume records without renumbering. |
| 2 | **provenance byte offsets**: enable incremental re-ingest (edit → local invalidation — exploit-10 of the directive). |
| 3 | **The ?? families (2.3%)**: sign-ext/conversions/floats need exact bounds — mapping them unlocks constant-folding input for f32/f64 regions (exploit-4 prerequisite). |
| 4 | **caller field**: enables per-relation fact_coverage on the wasm side — the ingest's OWN blocker meter, mirroring the compiler's. |
| 5 | **IPC speedup**: the ingest currently writes JSONL to stdout. The line-oriented serve prototype is not JSON-RPC or MCP. A real tool face must use the existing checked MCP/JSON-RPC semantic boundary; compiler-internal use can consume published graph facts directly without serialization. |
| 6 | **Instruction minimization in the ingest itself**: slebsign/ulebval each re-walk the LEB from scratch; a single walk returning value+ end (tail pack — blocked by subset) would halve byte reads per immediate. Current: 53K records / 17s corpus = O(n) with ~2x read amplification. Deletion condition: packs as first-class returns. |
