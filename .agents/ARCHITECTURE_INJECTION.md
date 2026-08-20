# Idol night-shift architecture injection

**Paste at the top of every agent session (short form):**

Do not port the host compiler. Reduce the required observation to Idol semantics.
Preserve every exact fact already known. One meaning has one id; facts qualify it;
realization carries physical choice. Source syntax, AST kinds, paths, names,
hashes, opcodes, storage classes and backend distinctions are never semantic
authority. A value is not a place. A binding is not storage. A pack is not an
aggregate. A call is not an ABI. A table is not a hash table. A closure is not
a heap object. Unknown is not absent. Demand determines what exists physically.
Prefer no execution, no allocation, no copy, no representation, no runtime and
no instruction whenever semantics permit. Never reconstruct downstream what
upstream already knew. Never add a parallel semantic taxonomy. Never self-host
host implementation patterns merely because they exist. Semantic graph work must
maximize facts while physically using dense ids, packed ranges, columns, views
and exact dependencies. Every transformation preserves application/value lineage
and witness. Every performance change preserves or expands lawful realizations
and accounts for compile cost as well as runtime. Every SHC claim names the
exact production decision that moved from host ownership to executed Idol
ownership. If a required canonical relation/fact is missing, stop and identify
the missing authority rather than inventing a helper or fallback.

---

## Core pipeline

Idol is **not** source → AST → IR → optimized IR → backend.

Idol is:

```text
observations → identities + facts → demand → lawful realization space → minimum physical work
```

## Preserve the strongest fact already known

If an earlier stage knows token identity, relation identity, subject,
descriptor, pack correspondence, world, effect, witness, demand, or source span,
then a later stage **consumes** that fact. It does not reconstruct it.

A missing fact is preferable to a guessed fact. Fail closed and identify its
missing producer.

## Demand before representation; none is best

Ask which observations require which portions of a value before choosing
representation. Prefer no execution, no allocation, no copy, no representation,
no runtime, and no instruction whenever semantics permit.

## Unit of progress

Semantic authority moved upward, information loss reduced, physical commitment
moved later, and work disappeared — not "code added."
