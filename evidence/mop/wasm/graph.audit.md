# Graph-conformance audit — wasm ingest records vs compiler sim-v0 (measured)

Compiler graph of ingest.id itself: 741 nodes, 1,105 edges, 95 published
applications (of 113 candidates, 17 bootstrap, 1 blocking), 15 bodies with
recurrence regions, 2 worlds.

## Field-level delta (my records vs the compiler's applications[])

| Missing from my records (compiler HAS) | Fix |
|---|---|
| `caller` (enclosing relation id) | emit fn index — already known (fi) |
| `arguments` / `results` as NODE references | my `operands` are app numbers; the graph uses node ids — switch to per-body node allocation or keep app-refs and document the projection |
| `provenance` {file, start, end} | byte offsets — available at read time (at) |
| `applied` card {one/none/unknown + id} | emit card:"one" + relation number for calls; "unknown" for binops until published |
| `effect` / `authority` / `witness` / `realization` cards | emit explicit card:"unknown" — presence IS the conformance (facts publish later) |

| My fields the compiler LACKS (wasm-native) | Ruling |
|---|---|
| `width`, `overflow`, `origin`, `determinacy` | keep — foreign-law inputs the graph should admit as descriptor/provenance facts (fact-separation ruling: separate families, not bundled) |

## Conformance verdict

Records are shape-ADJACENT, not yet shape-IDENTICAL. The missing card
fields are mechanical (values known at emission); the node-id vs app-ref
difference is a projection decision for the graph lane. The wasm-native
fields (width/overflow/origin/determinacy) are the foreign-law payload
per the separation ruling — they must NOT be flattened away.

## Performance opportunities identified this audit

1. **app-refs → node-ids**: emitting node-id references enables the
   graph's demand pass to consume records without renumbering.
2. **provenance byte offsets**: enable incremental re-ingest (edit →
   local invalidation — exploit-10 of the directive).
3. **The ?? families (2.3%)**: sign-ext/conversions/floats need exact
   bounds — mapping them unlocks constant-folding input for f32/f64
   regions (exploit-4 prerequisite).
4. **caller field**: enables per-relation fact_coverage on the wasm
   side — the ingest's OWN blocker meter, mirroring the compiler's.
5. **IPC speedup**: the ingest currently writes JSONL to stdout — for
   the idol MCP path, the same records can stream over the newline
   JSON-RPC transport (native.id pattern) with zero format change;
   for compiler-internal use, the record stream can be consumed
   directly at graph-build time (no serialization at all).
6. **Instruction minimization in the ingest itself**: slebsign/ulebval
   each re-walk the LEB from scratch; a single walk returning value+
   end (tail pack — blocked by subset) would halve byte reads per
   immediate. Current: 53K records / 17s corpus = O(n) with ~2x read
   amplification. Deletion condition: packs as first-class returns.
