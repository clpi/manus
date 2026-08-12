# Application record (PROJECTION-ONE step 4)

Projection of C0 `law.projection.pack`, `law.projection.census`, and
`law.projection.repair` step four. Not semantic law — the constitution owns
verdicts. This document is the resolver→graph contract until GAP-124 ingests
live graph queries.

## Purpose

Every resolved application must become one **application record** in the graph.
The record carries a **projection pack** as first-class facts — not curry stages,
not nested callable intermediates, not namespace-selected meaning.

Source elision (`value:to()` → graph-inferred target) must **not** erase
projection pack facts. Omitted syntax is provenance; the graph retains inferred
projection with causal link to demand and binding context.

## Record shape

Each application record is one graph entity with scalar ids and pack references:

| field | role | producer |
|---|---|---|
| `application` | unique application id in one graph incarnation | resolver |
| `relation` | admitted relation identity (not spelling, path, or home) | resolver |
| `projection` | relation projection pack — descriptor or constraint | resolver |
| `projectionexplicit` | whether projection was spelled in source | resolver |
| `projectioninferred` | inferred projection when source elided; empty when explicit | resolver |
| `subject` | semantic subject id — orientation, not argument zero | resolver |
| `operand` | operand pack id — ordered argument facts | resolver |
| `result` | result demand pack — binding, continuation, or void demand | resolver |
| `constraint` | protocol or conversion constraint witnesses | resolver |
| `worldneed` | world requirements for this application | resolver |
| `worldwitness` | injected or supplied world witnesses | resolution |
| `origin` | foreign or cross-boundary origin when applicable | resolver |
| `law` | conversion or protocol law edge when applicable | resolver |
| `provenance` | source span and elision witness chain | parser + resolver |

Packs (`operand`, `result`, `constraint`) are graph-owned structured values with
slot correspondence — not host arrays, not flattened argument lists recovered
from callee strings.

## Projection pack is not curry

Declaration:

```id
read(number) = (lx, b)
```

Graph record (conceptual):

```text
relation     read
projection   number          # relation parameter — not a callable type
subject      lx
operand      pack(b)
result       demand(void)
```

Invocation `lx:read(number)(b)` is **one** application with explicit projection
`number`. It is not `read(number)` returning a callable that is applied to `b`.

Declaration:

```id
to(str) = (value)
```

Graph record for `text:to(str)`:

```text
relation     to
projection   str             # explicit
subject      text
operand      pack()
result       demand(str)     # or continuation demand per binding site
```

Graph record for `n:to()` when `str` is uniquely demanded:

```text
relation     to
projection   str             # inferred — same field as explicit case
projectionexplicit false
projectioninferred str
subject      n
sourceelided to()
provenance   result demand on binding + direct bridge witness
```

## Tripartition in the record

| phase | what the record carries | what it must not carry |
|---|---|---|
| satisfaction | descriptor already matches — no `to` edge | conversion relation id |
| conversion | `to` relation + projection pack + law witnesses | machine representation choice |
| realization | deferred to demand→realization — DNIR reads graph ids | callee string, opcode tag |

Satisfaction is not “default type then convert.” `exact integer n i32 = 5` is
descriptor specialization on the binding, not `i64` plus hidden `to(i32)`.

## Resolver obligations (step 4 acceptance)

Before GAP-124 graph gates own verdicts, the resolver must:

1. Mint one application record per resolved application occurrence.
2. Split relation declaration parameters into **projection pack** vs **subject**
   vs **operand pack** roles per grammar role, never per nested call shape.
3. Record explicit vs inferred projection separately; inferred must cite demand
   or constraint witness ids.
4. Refuse to emit `methodcall`, `projectedcall`, `genericcall`, `protocolcall`,
   `worldcall`, or `curriedcall` semantic kinds — only normalized application
   records (`law.projection.one`).
5. Hand records to graph ingestion without reconstructing meaning from home path,
   `std`/`lib` prefix, or callee spelling.

## DNIR and tooling consumption

DNIR lowering reads **graph ids and facts** from the application record. It must
not recover projection from:

- nested call shape alone
- literal `"to"` string compares in codegen (GAP-082 debt)
- home path or module prefix
- type name or method flag

Tooling (LSP, MCP, diagnostics) displays inferred projection when source elided,
with provenance chain — same facts the graph retains (`law.infer.one`).

## Bootstrap catalog

Until graph ingestion executes live queries, the interim catalog lives at
`lib/semantic/application.id`. It documents sample records and pack roles for
Codex graph work and census alignment. Passing that gate proves schema presence
only — not graph enforcement.

## Census linkage

`scripts/projection_census.id` reports source-level debt classes. When step 4
lands in the resolver, `law.projection.census` requires a parallel **graph
census** counting:

- applications missing projection pack facts
- explicit projections redundant with inferred facts
- ambiguous inferred projections
- DNIR/codegen reconstruction sites

Text census classifies; graph census owns removal verdicts (GAP-165, GAP-124).

## Repair order context

| step | status |
|---|---|
| 1 reconcile C0 | done |
| 2 rewrite world.md | done |
| 3 eliminate `from` in canonical conversion fixture | done |
| **4 application record + projection pack in resolver→graph** | **this document + bootstrap catalog** |
| 5–15 inference, canonicalizer, codegen, DNIR, graph gates | blocked on GAP-124 implementation |

Do not bulk-rewrite `:to(` or `:from(` in source until per-site repair class
proof (`law.repair.infer`, `law.repair.class`).

## Step 5 — demand inference (preview)

When binding, parameter, field, or result **demand** uniquely determines
projection, the resolver records:

| field | role |
|---|---|
| `demandsource` | binding id, parameter slot, field key, or result binder |
| `demandeddescriptor` | descriptor the slot requires |
| `supplieddescriptor` | descriptor the value carries |
| `satisfaction` | direct match — no `to` edge |
| `bridge` | unique admitted direct bridge relation id, if any |
| `inferredprojection` | projection pack when elided in source |

Inference mints the same application record as step 4; it only populates
`projectioninferred` and provenance when source omits `:to()` or `:to(T)`.
See `examples/infer/direct.id` and `law.infer.one`.

Blocked on GAP-124 resolver implementation. Debt census:
`docs/spec/projection-debt.md`.
