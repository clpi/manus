# Idol text and bytes

| # | directive |
|---|---|
| 1 | The supreme law is [`docs/spec/law.md`](law.md) and [`docs/spec/constitution.md`](constitution.md) is its structured expansion. |
| 2 | This page projects its text, bytes, source-face, demand, and realization facts. |
| 3 | It is not a second vocabulary or an implementation catalog. |

## Meaning

| # | directive |
|---|---|
| 1 | Text and bytes are distinct semantic domains. |
| 2 | Text carries an admitted encoding law and its validity witness. |
| 3 | Bytes carry exact octets without inheriting a text encoding. |
| 4 | Conversion between them is a relation with explicit law, failure, and provenance; representation similarity never proves equivalence. |

| # | directive |
|---|---|
| 1 | Canonical source exposes that distinction directly: |

- double quotes delimit text;
- single quotes delimit bytes;
- compatibility literals retain their foreign lawset and provenance until a
  witnessed canonical rewrite;
- backtick is reserved and never executes a process.

| # | directive |
|---|---|
| 1 | [`GAP-145`](../../gaps/GAP-145.md) owns the distinct production lexical identities still required for those facts to survive the token boundary. |

## Relations and projection

| # | directive |
|---|---|
| 1 | Operations begin from the possessed value and resolve one semantic relation. |
| 2 | Length is the subject relation `len`; package location and historical helper names do not create another identity. |
| 3 | Encoding, normalization, segmentation, comparison, search, and conversion qualifications belong in descriptor and law facts rather than relation-name variants. |

| # | directive |
|---|---|
| 1 | Ordinary application supplies a genuinely computed projection: `text(key)`. |
| 2 | A statically known identity uses named projection. |
| 3 | Neither source face determines whether realization uses an offset, view, scan, table, SIMD operation, foreign routine, or no runtime work. |

| # | directive |
|---|---|
| 1 | Positions, ranges, and iteration units must remain explicit semantic facts when observable. |
| 2 | A byte offset, scalar position, and grapheme position are not interchangeable merely because one host API represents each as an integer. |
| 3 | Unknown or absent projection results remain semantic cases and never become an ordinary sentinel. |

## Demand and realization

| # | directive |
|---|---|
| 1 | Demand may erase unused decoding, validation, iteration, allocation, copying, or materialization. |
| 2 | A known literal may realize as static data or disappear; a view need not allocate; a demanded foreign ABI may constrain layout. |
| 3 | These choices preserve the original value, relation, application, laws, witnesses, and transformation provenance. |

| # | directive |
|---|---|
| 1 | An optimizer may reuse an encoding witness across many operations. |
| 2 | It may not assume validity, flatten incompatible foreign text laws, or convert an unknown fact to false. |
| 3 | If required text vocabulary or law is absent from the graph, the source is `SEMANTIC-VOCABULARY-BLOCKED` rather than expressed through a helper predicate or namespace. |

## Current implementation boundary

| # | directive |
|---|---|
| 1 | Current host and SOURCE-ZERO paths still contain string-specific namespaces, sentinel behavior, boxed fallback, and backend disagreements. |
| 2 | They are implementation debt, not canonical semantics. |
| 3 | Current claims require exact production evidence for the selected frontend and backend; a parse result, fixture, or stale measurement does not prove text realization. |

| # | directive |
|---|---|
| 1 | Closure requires lexical identity from `GAP-145`, graph-owned text and bytes facts, demanded checks and cases, C/direct/Wasm differential evidence where applicable, and exact source-to-machine lineage. |
