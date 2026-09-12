| field | value |
|---|---|
| title | Idol numeric meaning |

| # | directive |
|---|---|
| 1 | This page is a projection of [`docs/spec/constitution.md`](constitution.md), not a second numeric specification or a primitive-type catalog. |

| section |
|---|---|
| Primitive-zero |

| # | directive |
|---|---|
| 1 | Representation-qualified source faces such as `i8`, `u64`, `f32`, and `f64` remain compact canonical ways to state facts a program actually observes. |
| 2 | They are not unrelated semantic kingdoms and do not mint distinct relation identities merely because their source or ABI faces differ. |

| # | directive |
|---|---|
| 1 | Numeric meaning consists of one numeric value or relation plus demanded facts, including where observable: |

| # | directive |
|---|---|
| 1 | exact value, range, and cardinality; |
| 2 | integral, rational, real, or other admitted numeric law; |
| 3 | signedness, width, radix, precision, and floating format; |
| 4 | overflow, rounding, exceptional-value, and comparison laws; |
| 5 | bit, serialization, ABI, foreign-lawset, and target obligations; |
| 6 | provenance, proof, demand, and result correspondence. |

| # | directive |
|---|---|
| 1 | Qualification belongs in those facts. |
| 2 | Native relation identity does not encode `i64`, `u32`, `f64`, ABI class, register class, or target spelling. |

| section |
|---|---|
| Literals and demand |

| # | directive |
|---|---|
| 1 | An unqualified numeric literal preserves its exact mathematical information until context and demand require an observable numeric law. |
| 2 | The compiler must not turn an implementation default into semantic identity. |
| 3 | A fixed-width face is canonical when width or format is actually demanded, for example: |

```id
count: u64 = 0
ratio: f32 = input
```

| # | directive |
|---|---|
| 1 | Whether a conversion, overflow case, comparison, or mixed operation is lawful comes from the admitted descriptor and relation facts. |
| 2 | Do not reconstruct it from a source enum or copy a host promotion table. |
| 3 | If the required numeric law is absent from the authoritative graph vocabulary, the result is `SEMANTIC-VOCABULARY-BLOCKED`. |

| section |
|---|---|
| Realization freedom |

| # | directive |
|---|---|
| 1 | The same numeric meaning may lawfully realize as nothing, a constant, an immediate, a narrower scalar, a vector lane, a register, memory, a foreign ABI value, a GPU value, or another proven form. |
| 2 | Source width does not by itself force storage width when the program cannot observe that choice; observable width, bit behavior, ABI, serialization, and foreign laws remain constraints. |

| # | directive |
|---|---|
| 1 | Demand should erase unused numeric work before materialization. |
| 2 | Range and exact value facts may erase checks, narrow physical operations, fold relations, or select stronger algorithms while preserving the original relation, application, value, and transformation lineage. |

| section |
|---|---|
| Current implementation boundary |

| # | directive |
|---|---|
| 1 | `GAP-149` owns the remaining primitive-zero transfer. |
| 2 | Current host enums, DNIR operation names, ABI maps, and backend categories still conflate numeric meaning with representation. |
| 3 | They are migration debt and must not be copied into canonical `.id`. |

| # | directive |
|---|---|
| 1 | An unqualified numeric literal's default descriptor is one derived fact, `types.literalDefaultDescriptor`, read by every literal-typing site. |
| 2 | At an annotated binding the default no longer becomes the literal's identity BEFORE demand: `sema` records the pre-demand default when the literal is checked, then supersedes it with the demanded descriptor once the annotation is known and has been checked to accept the literal (`Sema.deferLiteralDefaultToDemand`), so `n: u8 = 3` records the literal `3` as `u8` rather than the eager `i64`. |
| 3 | A literal the demand does not accept keeps its default and is diagnosed by the mismatch and range checks, never silently re-recorded. |
| 4 | The default itself is unchanged; only when it is superseded by demand moved. |
| 5 | The ordering is still eager where no annotation supplies demand at the checking site — that remaining default-before-demand carrier stays `GAP-149` migration debt. |

| # | directive |
|---|---|
| 1 | zig build unit-test |

| # | directive |
|---|---|
| 1 | and read `sema: the bare-numeric-literal default is superseded by demand, after demand`. |

| # | directive |
|---|---|
| 1 | Numeric acceptance requires graph-owned facts to survive source, demand, realization, machine, and object lineage. |
| 2 | Tests vary legal realization width without changing semantic identity, vary an observable numeric law and require the graph facts to change, and compare exact values and failures against an identified oracle. |
| 3 | A source spelling, enum match, or machine opcode is never that proof. |
