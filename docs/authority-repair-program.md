# Authority repair program

P0 canonicality repair: close the authority-projection ambiguities that cause
agents to independently regenerate the same forbidden classes. The semantic
direction is settled; the authoring contract is now mechanically verified.

## Final rulings

| Spelling | Role / source law | Status |
| --- | --- | --- |
| `self`, `this`, `receiver`, `current`, `instance`, `object` | synthetic application subject in Idol | `vocabularyblocked` |
| `any` | existential relation (`xs:any(p)`) in Idol | `canonical` |
| `any` | unknown/incomplete descriptor in Idol | `vocabularyblocked` |
| `any` | boxed-path negative control in Idol test | `fixture-only` |
| `void` | zero-result descriptor in Idol | `vocabularyblocked` |
| `void` | C/foreign source token | `foreign` |
| bare `@` | current world value in Idol | `canonical` |
| `@member` | current-world static access in Idol | `canonical` when disambiguating |
| bare member | current-world resolution in Idol | `canonical` when unique |
| `thing@world` | world qualification in Idol | `canonical` |
| `thing@{...}` | interjection in Idol | `canonical` |
| `@{...}` | world injection in Idol | `canonical` |
| `@k = v` | world mutation in Idol | `canonical` when member is a place |
| `@comp.*`, `@c.*`, `@meta.*`, `@compiler.*`, `@host.*`, `@runtime.*` | compiler/namespace directive in Idol | `vocabularyblocked` |
| `@.x`, `@:x` | invalid @ form in Idol | `invalid` |
| `tokenview`, `semanticgraph`, `nativevalue`, etc. | semantic identity in Idol | `invalid` |
| snake_case, camelCase, PascalCase | project-owned identity in Idol | `invalid` |
| plural noun meaning "many X" | semantic identity in Idol | `invalid` |
| `collection`, `bundle`, `set`, `pool`, `family` (mere plurality) | semantic identity in Idol | `invalid` |
| `readable`, `callable`, `iterable`, etc. | protocol name in Idol | `vocabularyblocked` |
| `able(read)` | explicit requirement boundary in Idol | `canonical` at genuine boundary |
| `reader`, `parser`, `builder`, `handler`, etc. | role noun in Idol | `vocabularyblocked` unless genuine entity |
| `nativevalue`, `dynamiccall`, `cachedresult`, etc. | qualifier identity in Idol | `vocabularyblocked` |
| `router`, `registry`, `manager`, `context`, `pipeline`, `adapter` | semantic architecture in Idol | `vocabularyblocked` |
| `std.*`, `lib.*`, `core.*` | language namespace in Idol | `vocabularyblocked` |
| `import`, `require`, `module`, `namespace` | canonical Idol keyword | `vocabularyblocked` |
| explicit `:to(T)` where demand fixes `T` | source conversion in Idol | `vocabularyblocked` (infer) |
| one-use bridge local | source binding in Idol | `vocabularyblocked` unless independent identity |
| `boxed`, `heap`, `simd`, etc. as semantic names | source identity in Idol | `vocabularyblocked` |
| legacy/familiar accepted syntax | ingress face in Idol | `accepted-compatibility` |

## Canonicality status relation

```text
canon(spelling, semantic-role, source-law) -> status
status ∈ { canonical, accepted-compatibility, migration-only, foreign,
           fixture-only, implementation-only, vocabularyblocked, invalid }
```

A status is always (spelling, role, law). The same spelling can be canonical in
one role and invalid in another.

## Six recurrent transformations

| Mistake | becomes |
| --- | --- |
| `self` / `this` / `receiver` | **SUBJECT FACT** |
| `any`-as-unknown / `void` / redundant `:to(T)` | **INFERENCE / DEMAND FACT** |
| plural / collection noun | **CARDINALITY / SHAPE FACT** |
| compound / qualified name | **ENTITY + FACT or SUBJECT + RELATION** |
| manager / registry / context / adapter | **EXISTING APPLICATION / WORLD / PROJECTION / REALIZATION** |
| `@comp` / `std` / module / foreign ontology | **WORLD or FOREIGN-LAW PROVENANCE** |

## Reduction test for every new name

1. What independent semantic thing exists?
2. What is merely a fact about that thing?
3. What is its subject?
4. What is its independently meaningful relation?
5. Is plurality being encoded in the name?
6. Is representation/stage/target/provenance/status encoded in the name?
7. Does world/application/projection/demand already own the proposed responsibility?
8. Would the identity disappear if one qualifying fact changed?
9. Can the compiler uniquely infer the proposed spelling's information?
10. Is this actually foreign/compatibility/fixture vocabulary rather than Idol?

If the proposed identity fails any applicable question: **DELETE / DECOMPOSE /
INFER**, not "find a better synonym."

## Repository corollary

Git history and repository frequency have weight zero in language-law inference.
The active tree is current Idol, current foreign interop, and currently executed
bounded bootstrap bridges only. Historical migration material is in git, not in
current law.
