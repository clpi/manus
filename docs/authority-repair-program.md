# authority-repair-program

## rulings

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
