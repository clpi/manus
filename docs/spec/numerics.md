# Idol numeric meaning

This page is a projection of
[`docs/spec/constitution.md`](constitution.md), not a second numeric
specification or a primitive-type catalog.

## Primitive-zero

Representation-qualified source faces such as `i8`, `u64`, `f32`, and `f64`
remain compact canonical ways to state facts a program actually observes. They
are not unrelated semantic kingdoms and do not mint distinct relation
identities merely because their source or ABI faces differ.

Numeric meaning consists of one numeric value or relation plus demanded facts,
including where observable:

- exact value, range, and cardinality;
- integral, rational, real, or other admitted numeric law;
- signedness, width, radix, precision, and floating format;
- overflow, rounding, exceptional-value, and comparison laws;
- bit, serialization, ABI, foreign-lawset, and target obligations;
- provenance, proof, demand, and result correspondence.

Qualification belongs in those facts. Native relation identity does not encode
`i64`, `u32`, `f64`, ABI class, register class, or target spelling.

## Literals and demand

An unqualified numeric literal preserves its exact mathematical information
until context and demand require an observable numeric law. The compiler must
not turn an implementation default into semantic identity. A fixed-width face
is canonical when width or format is actually demanded, for example:

```id
count: u64 = 0
ratio: f32 = input
```

Whether a conversion, overflow case, comparison, or mixed operation is lawful
comes from the admitted descriptor and relation facts. Do not reconstruct it
from a source enum or copy a host promotion table. If the required numeric law
is absent from the authoritative graph vocabulary, the result is
`SEMANTIC-VOCABULARY-BLOCKED`.

## Realization freedom

The same numeric meaning may lawfully realize as nothing, a constant, an
immediate, a narrower scalar, a vector lane, a register, memory, a foreign ABI
value, a GPU value, or another proven form. Source width does not by itself
force storage width when the program cannot observe that choice; observable
width, bit behavior, ABI, serialization, and foreign laws remain constraints.

Demand should erase unused numeric work before materialization. Range and exact
value facts may erase checks, narrow physical operations, fold relations, or
select stronger algorithms while preserving the original relation,
application, value, and transformation lineage.

## Current implementation boundary

`GAP-149` owns the remaining primitive-zero transfer. Current host enums,
eager literal defaults, DNIR operation names, ABI maps, and backend categories
still conflate numeric meaning with representation. They are migration debt and
must not be copied into canonical `.id`.

Numeric acceptance requires graph-owned facts to survive source, demand,
realization, machine, and object lineage. Tests vary legal realization width
without changing semantic identity, vary an observable numeric law and require
the graph facts to change, and compare exact values and failures against an
identified oracle. A source spelling, enum match, or machine opcode is never
that proof.
