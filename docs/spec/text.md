# Idol text and bytes

The sole semantic law is [`docs/spec/constitution.md`](constitution.md). This
page projects its text, bytes, source-face, demand, and realization facts. It is
not a second vocabulary or an implementation catalog.

## Meaning

Text and bytes are distinct semantic domains. Text carries an admitted encoding
law and its validity witness. Bytes carry exact octets without inheriting a text
encoding. Conversion between them is a relation with explicit law, failure,
and provenance; representation similarity never proves equivalence.

Canonical source exposes that distinction directly:

- double quotes delimit text;
- single quotes delimit bytes;
- compatibility literals retain their foreign lawset and provenance until a
  witnessed canonical rewrite;
- backtick is reserved and never executes a process.

[`GAP-145`](../../gaps/GAP-145.md) owns the distinct production lexical
identities still required for those facts to survive the token boundary.

## Relations and projection

Operations begin from the possessed value and resolve one semantic relation.
Length is the subject relation `len`; package location and historical helper
names do not create another identity. Encoding, normalization, segmentation,
comparison, search, and conversion qualifications belong in descriptor and law
facts rather than relation-name variants.

Square brackets remain only for a genuinely computed projection. A statically
known identity uses a named projection. Neither source face determines whether
realization uses an offset, view, scan, table, SIMD operation, foreign routine,
or no runtime work.

Positions, ranges, and iteration units must remain explicit semantic facts when
observable. A byte offset, scalar position, and grapheme position are not
interchangeable merely because one host API represents each as an integer.
Unknown or absent projection results remain semantic cases and never become an
ordinary sentinel.

## Demand and realization

Demand may erase unused decoding, validation, iteration, allocation, copying,
or materialization. A known literal may realize as static data or disappear; a
view need not allocate; a demanded foreign ABI may constrain layout. These
choices preserve the original value, relation, application, laws, witnesses,
and transformation provenance.

An optimizer may reuse an encoding witness across many operations. It may not
assume validity, flatten incompatible foreign text laws, or convert an unknown
fact to false. If required text vocabulary or law is absent from the graph, the
source is `SEMANTIC-VOCABULARY-BLOCKED` rather than expressed through a helper
predicate or namespace.

## Current implementation boundary

Current host and SOURCE-ZERO paths still contain string-specific namespaces,
sentinel behavior, boxed fallback, and backend disagreements. They are
implementation debt, not canonical semantics. Current claims require exact
production evidence for the selected frontend and backend; a parse result,
fixture, or stale measurement does not prove text realization.

Closure requires lexical identity from `GAP-145`, graph-owned text and bytes
facts, demanded checks and cases, C/direct/Wasm differential evidence where
applicable, and exact source-to-machine lineage.
