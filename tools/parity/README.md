# parity — executable projection agreement

These tools prove that derived language projections still carry the exact
authority they claim. They never regenerate or repair a projection. Absence,
malformation, stale authority, and a zero-file census are failures.

## grammar

`tools/parity/grammar` reads the tracked byte authority
`lib/token/grammarrole.tsv`. Its format is closed:

1. `# schema<TAB>grammar-role-v2`
2. `# authority<TAB>fnv1a64:<16 lowercase hexadecimal digits>`
3. the exact 17-column TSV header
4. one complete row for every physical token slot

The FNV-1a digest covers the schema and semantic row serialization: u16 slot,
UTF-8 kind and spelling, then every remaining semantic field in exact TSV column
order, with precedence encoded as signed i8. The TSV spelling is also exact: the
gate validates metadata, header, line form, row widths, canonical and unique
contiguous slots, the unpublished slot, role domains, identity and EOF counts,
and the generated Idol vector width. It then requires both generated consumers
to embed the same schema and full tagged authority:

- `lib/token/grammarrole.id`
- `ext/tree-sitter-idol/grammar.js`

Retired grammar-role projection paths remain forbidden. Success reports the
number of projections and role rows examined. Every finding contributes to the
nonzero census exit status.

## grammar-selftest

`tools/parity/grammar-selftest` builds an isolated valid authority and damages
it nine ways. It proves rejection of a missing manifest or hash, exact payload
drift in ordinary, associativity, compatibility, and delimiter/projection
fields, stale Idol and Tree-sitter hashes, and a correctly hashed zero-row
manifest. The repository is never changed by the controls.
