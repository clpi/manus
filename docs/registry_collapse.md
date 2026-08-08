# Registry collapse — survey

**Status:** survey only. No source file was modified to produce this.
**Verified against:** clean detached worktree at `489bc1b` (`git worktree add
--detach /tmp/rc HEAD`), because the shared tree carries uncommitted work from
several sessions. Every `file:line` below is a `489bc1b` line number.

This answers the two unchecked P0 rows in `docs/spec/AUTHORITY.md:57` and
`docs/spec/AUTHORITY.md:60`:

> - [ ] stable semantic identity across scope/module/codegen — textual names are
>       still doing semantic-identity work, which is the root of a whole family
>       of current bugs
> - [ ] concept/generic/overload/method registries collapsed into trie + relations

## What "registry" means here

A field on `Sema` or `CodeGen` that stores a semantic fact keyed by something
other than a node identity — almost always a textual name. `src/sema.zig` has
**14** `StringHashMapUnmanaged` fields; `src/codegen.zig` has **48**
(measured: `grep -c 'std\.StringHashMapUnmanaged'`). This document does not try
to cover all 62. It covers the ones that store *semantic* facts — facts that
Pass 100 says belong on the graph as a relation — and reports honestly on the
several that turn out to be dead or already-derived.

## The measured table

Writer/reader counts are call sites, not dynamic frequency, and exclude
`deinit`/`clearRetainingCapacity`. Test-only sites are excluded from the reader
column and called out in Notes.

| # | Registry | Declared | Stores | Writers | Readers | The ONE EDGE underneath |
|---|---|---|---|---|---|---|
| 1 | `Sema.alias_defs` | `src/sema.zig:229` | name → `*const ast.AliasDef` | `sema.zig:1379` | `sema.zig:1551`, `4318`, `4343`, `8920` | `name --is--> descriptor`. Semantic identity/equivalence, not "alias" as a language concept. |
| 2 | `CodeGen.alias_defs` | `src/codegen.zig:294` | same thing, second copy | `codegen.zig:6432` | `codegen.zig:1360`, `2765`, `2911`, `2919`, `6441`, `14847`, `16936`, `17034`, `17099`, `17156` | **Same edge as #1, stored twice.** Ten readers in codegen that never see sema's copy. |
| 3 | `Sema.concepts` | `src/sema.zig:224` | name → `ConceptInfo` (9 fields across 3 structs, `sema.zig:175-191`) | `sema.zig:3924`, `3953`, `3955` | `sema.zig:4165`, `4217`, `4336`, `4403` | `descriptor --requires--> member`. A protocol is a set of required-member edges. |
| 4 | `Sema.table_methods` | `src/sema.zig:243` | table name → list of **method names only** (signature dropped) | `sema.zig:3348` | `sema.zig:4364`, `4407` | `descriptor --has-callable-member--> func`. Exactly the audit's guess. |
| 5 | `Sema.overloads` | `src/sema.zig:227` | name → `ArrayList(FuncSignature)` | `sema.zig:3312` | `sema.zig:2655` (+ in-place rewrite at `3557`) | Trie strata. One name, N strata; the list *is* a degenerate trie with no path. |
| 6 | `Sema.enum_types` | `src/sema.zig:222` | name → `RT` | `sema.zig:3850` | `sema.zig:2255`, `3600`, `3612`, `types.zig:1150` | `descriptor --case--> name`. Descriptor case population. |
| 7 | `Sema.table_field_types` | `src/sema.zig:237` | **string-concatenated** `"{func}.{table}.{field}"` → `RT` | `sema.zig:2180`, `2186`, `2191` | `sema.zig:2176`, `2198` | `binding --field--> type`, at a scope. See §"the smoking gun". |
| 8 | `Sema.generic_func_arities` | `src/sema.zig:232` | name → `?usize` | `sema.zig:1375` | `sema.zig:1745` — **one reader** | Nothing. See §DELETE. |
| 9 | `Sema.instantiation_sites` | `src/sema.zig:234` | `InstantiationRecord` (4 fields, `sema.zig:201-210`) | `sema.zig:4185` | `sema.zig:1408-1409` — **a count in an info message** | Nothing live. See §dead. |
| 10 | `Sema.metatable_types` | `src/sema.zig:241` | name → `RT`, always the literal `.any` | `sema.zig:2559` | **none** | Nothing. See §dead. |
| 11 | `CodeGen.enum_defs` / `enum_has_payload` | `src/codegen.zig:293`, `:292` | third and fourth copies of enum case facts | 2 / 1 | 4 / 9 | Same edge as #6. |
| 12 | `CodeGen.alias_methods` | `src/codegen.zig:299` | alias name → method name list | 1 | 4 | Same edge as #4, second copy. |
| 13 | `SemanticGraph.func_decls` | `src/semantic_graph.zig:147` | name → `*const ast.FuncDecl` | — | — | The graph's own name-keyed side table, on the very structure that is supposed to replace name-keyed side tables. |
| 14 | `pass26_descriptor_intern.Registry` | `src/pass26_descriptor_intern.zig:237` | fingerprint → slot, decl-identity, state | `semantic_graph.zig:430` | `semantic_graph.zig` alias lift | **Not a collapse target — a collapse *tool*.** See §the seed. |

### Registries that are already-derived or dead — the honest subtractions

**#10 `metatable_types` is dead.** Four mentions exist in all of `src/`
(`sema.zig:241` decl, `:411` init, `:524` deinit, `:2559` the single `put`).
The `put` stores the constant `.any` for every key. Nothing reads it. It is
also gated on `setmetatable`, which Pass 100 §1 denies outright. Delete it;
there is no edge to preserve.

**#9 `instantiation_sites` is dead for its stated purpose.** Its doc comment
says "tracked for the monomorphizer (Requirement 4.1, 4.3)". The monomorphizer
is `src/mono.zig`, which maintains its own `generics` / `specializations` /
`requested` / `order` / `pending` set (`mono.zig:176-184`) and never reads
`instantiation_sites` — `grep -rn "instantiation_sites" src/*.zig` returns hits
only inside `sema.zig`. The only read is `.items.len` for an `--info` line at
`sema.zig:1408-1409`. The 4-field `InstantiationRecord` and the key-hashing
loop at `sema.zig:4178-4184` computes a `specialization_key` that no consumer
ever receives.

**#8 `generic_func_arities` — DELETE, as the audit guessed, and for a sharper
reason than "strata/call shapes".** Its sole reader is
`check_specialize_directive` (`sema.zig:1745`), reached only from
`sema.zig:2052-2053`, a `.directive` statement whose name is `"specialize"` —
a prefix-`@` directive. Pass 100 §0.2 says *"NO DIRECTIVES. Prefix `@` does not
exist."* This registry exists to validate the arity of a construct the spec
deletes. It also has a latent correctness bug: it is keyed on `fd.path[0]` for
**every** func decl including methods (`sema.zig:1374-1375`), so `Point:add`
registers the key `"Point"` with the method's type-param count.

**#13 is worth stating plainly:** `SemanticGraph` — the replacement — carries
its own `StringHashMapUnmanaged` name index (`semantic_graph.zig:147`, `:149`).
The new ontology inherited the old one's keying.

## The smoking gun for "textual names as semantic identity"

Two artifacts, both measurable.

### 1. The O(n) lookup the audit asked for

`src/semantic_graph.zig:209-220`:

```zig
    /// Find the first node with a given name. O(n) scan.
    /// NOTE: duplicate names exist (locals in different scopes). This returns
    /// the first match. For production scale, replace with a scope-qualified
    /// index (e.g. HashMap([]const u8, ArrayList(NodeId))).
    pub fn findByName(self: *const SemanticGraph, name: []const u8) ?NodeId {
        for (self.nodes.items, 0..) |node, i| {
            if (node.name) |n| {
                if (std.mem.eql(u8, n, name)) return NodeId{ .index = @intCast(i) };
            }
        }
        return null;
    }
```

The comment records the causation the audit described: locals in different
scopes share textual names, so the hash index was wrong, so it was replaced by
a linear scan that returns *the first match* — which is not wrong-but-slow, it
is **silently wrong**, and the linear scan hides that by never surfacing the
collision.

**14 non-test call sites** depend on it: `dnir_lower.zig:284`,
`graph_query.zig:28`, `:58`, `:106`, `region_graph.zig:88`, `:147`,
`semantic_graph.zig:231` (`defsOf` is a pure delegation), `:529`, `:612`,
`:633`, `:655`, `:861`, `:1031`, `:1039`. Two of those —
`semantic_graph.zig:633` and `:612` — are the graph resolving a function's own
node by name during its own lift, so a shadowing local corrupts the graph as it
is built. A further **8 non-test sites** go through the same scan via
`findTableShape` / `findEnumShape` (`semantic_graph.zig:1030-1043`).

### 2. Hand-built string scope paths

`src/sema.zig:2127-2138` builds the key for `table_field_types` by
`bufPrint`ing `"{func}.{table}.{field}"`, falling back to `"{table}.{field}"`
at module scope. That is a poor-man's scope-qualified identity, spelled in
`u8`, allocated per write (`table_field_owned_key`, `sema.zig:2134`), and
truncated at a 384-byte buffer. It exists because there is no node identity to
key on. It is the same fix as #1.

### The second-ontology risk is already realized

The audit warned against adding adapters and calling that convergence. One
adapter-shaped divergence already exists: `CodeGen` does not read
`Sema.concepts` at all. `codegen.zig:16705 find_current_concept_def` re-derives
concept membership with its **own linear scan over module statements**, and
`codegen.zig:16873` uses that AST-derived result. So `concepts` (#3) is
answered twice by two different mechanisms — a registry in sema and a rescan in
codegen — with no shared record. The same duplication holds for aliases (#1 vs
#2) and enums (#6 vs #11). Collapsing sema's copy while leaving codegen's
rescan in place is exactly the two-ontology outcome the audit forbade; each row
must land in **both** consumers or in neither.

### The graph declares slots it never fills

`NodeKind` (`semantic_graph.zig:48-67`) declares 15 kinds; **9** are ever
produced (`.call`, `.enum_shape`, `.func`, `.local`, `.module`, `.param`,
`.pipeline`, `.table_shape`, `.transform_app`). Never produced:
`.source_file`, `.type_node`, `.directive`, `.concept`, `.comptime_value`,
`.emit_artifact`. `EdgeKind` (`:69-77`) declares 7; **5** are emitted —
`.def` and `.provenance` are never constructed.

So `NodeKind.concept` exists, unfilled, while `Sema.concepts` holds the facts
that would fill it. That is not a missing design. It is a design that was drawn
and then not wired, and the registries are the un-wired half.

## Ranking by collapse value

**This ranking is a judgement, not a measurement.** The reader/writer counts in
the table are measured. The ordering below multiplies "readers eliminated" by
"concepts deleted" — the second factor is my estimate of how many distinct
things stop needing to exist, and reasonable people would reorder rows 3-5.
What is *not* judgement: row 0 is a strict prerequisite for every other row,
because every other row's replacement is an edge, and an edge needs two stable
endpoints.

| Rank | Target | Readers eliminated | Concepts deleted | Why here |
|---|---|---|---|---|
| **0** | **Stable semantic identity** (`findByName` + the string scope keys) | 22 (14 `findByName` + 8 shape-find) | The whole "name = identity" assumption | Not ranked *against* the others — it is under them. Nothing below can be an edge until a node has an identity that survives shadowing. |
| 1 | `alias_defs` ×2 (#1, #2) | 14 (4 sema + 10 codegen) | "alias" as a language concept; the sema/codegen fork | Highest measured reader count of any row, and it is the row where the two-ontology split is widest. Collapsing it forces the shared-record discipline that every later row needs. |
| 2 | `concepts` + `table_methods` + `alias_methods` (#3, #4, #12) | 10 | `ConceptInfo` (3 structs, 9 fields), `find_current_concept_def`'s rescan, the hand-joined satisfaction check | `type_satisfies_concept` (`sema.zig:4334`) hand-joins **four** sources — `concepts`, `alias_defs`, `table_methods`, and `RT.table_type.fields` — to answer one question: *does this descriptor have a member named X?* One `member` edge answers it. Collapse these three together or not at all. |
| 3 | `enum_types` + `enum_defs` + `enum_has_payload` (#6, #11) | 17 | Three parallel spellings of case population | Highest raw reader count after #1/#2, but lowest conceptual payoff: `enum_shape` nodes are **already lifted** (`semantic_graph.zig:469`), so the graph half exists. This is wiring, not design. |
| 4 | `overloads` (#5) | 1 | Overloading as a distinct resolution mechanism | Only one real reader (`sema.zig:2655`), so the mechanical payoff is small. Ranked here because it is where Pass 100 §0.6's trie has to actually land: `resolve_overload` (`sema.zig:4077-4127`) is trie descent written as a linear match-and-tiebreak. |
| 5 | `table_field_types` (#7) | 2 | The string scope path | Falls out of rank 0 almost for free. Keep it on the list so it is not forgotten. |
| — | `generic_func_arities` (#8) | 1 | — | **Delete.** Its reader validates a prefix-`@` directive Pass 100 removes. |
| — | `instantiation_sites` (#9) | 0 | `InstantiationRecord` | **Delete.** `mono.zig` never reads it. |
| — | `metatable_types` (#10) | 0 | — | **Delete.** Written with a constant, read by nobody. |

Three of ten rows are deletions with no replacement edge. That is the shortest
true version of the list, and it is a real reduction in the survey's own scope.

## The seed for step 1 — it already exists

Do not design a new identity scheme. Two are already in the tree and are close:

- `SemanticGraph.StableId.compute` (`semantic_graph.zig:31`) hashes
  `module_path | kind | stable_path | generation`. Its weakness is
  `stablePathForNode` (`:175-182`): **if the node has a name, the name IS the
  stable path**. So two locals named `i` in sibling scopes of one module get
  the *same* `StableId`. The span fallback at `:177` is only used for anonymous
  nodes — the fix is to make the enclosing-scope chain part of the path for
  *named* nodes too, which is a change to one function.
- `pass26_descriptor_intern.declarationIdentityHash`
  (`pass26_descriptor_intern.zig:40-52`) hashes `module_path | name | span.line
  | span.col` and is documented as *"never merged across bindings"*
  (`semantic_graph.zig:108`). This is the right shape. It is currently applied
  to aliases only (`semantic_graph.zig:430`).

Step 1 is generalizing the second to all node kinds and routing the first
through it — not inventing a third.

## Sequenced plan

Each step is separately shippable and separately provable. No step adds an
adapter from graph semantics into a name-keyed registry.

**Step 1 — stable semantic identity (prerequisite, blocks everything).**
Give every graph node a declaration identity that a shadowing name cannot
collide: generalize `declarationIdentityHash` beyond aliases, and make
`stablePathForNode` include the enclosing scope chain so a named node's path is
not just its name. Then add the scope-qualified index the `findByName` comment
itself asks for (`StringHashMap → ArrayList(NodeId)` plus a scope filter), and
convert the 14 `findByName` sites to resolve *within a scope*.
*Proof:* a fixture with two same-named locals in sibling scopes must produce
two distinct `StableId`s and two distinct `findByName`-successor resolutions.
Positive-control it — per CLAUDE.md §3, a gate reporting 0 collisions is
usually broken, so assert the collision count is nonzero *before* the fix.

**Step 2 — delete the three dead rows.** `metatable_types`,
`instantiation_sites`, `generic_func_arities`, plus `InstantiationRecord` and
`check_specialize_directive`. No replacement edge, no behaviour change beyond
one `--info` line and one directive diagnostic. Do this second because it
shrinks the surface every later step has to reason about, and because it is the
one step that cannot regress anything.

**Step 3 — `member` edge, and the alias collapse (#1, #2).** Introduce the
missing relation and fill the declared-but-empty `EdgeKind.def`. Move
`alias_defs` to graph queries in **both** sema and codegen in the same change —
`codegen.zig`'s ten readers are the point of the exercise; leaving them is the
two-ontology failure. Delete `find_current_concept_def`'s sibling pattern where
it appears.

**Step 4 — concepts + methods (#3, #4, #12).** With `member` edges present,
`type_satisfies_concept`'s four-way hand-join becomes one edge query.
`ConceptInfo` disappears; `NodeKind.concept` gets produced for the first time.
`codegen.zig:16705`'s rescan is deleted, not adapted.

**Step 5 — enums (#6, #11).** Wire the four readers of `enum_types` and the
thirteen of `enum_defs`/`enum_has_payload` to the `enum_shape` nodes that are
already being lifted.

**Step 6 — overloads → trie strata (#5).** Last, because it is the only row
that needs the trie to exist as a first-class structure rather than as a query
over edges, and because its single reader means nothing else is waiting on it.

**Step 7 — `table_field_types` (#7).** Retire the string scope keys once step 1
has made node identity available at the field-tracking sites.

## The one-line answer

**Collapse `alias_defs` first — but only after step 1, and only in sema and
codegen simultaneously.** It has the most measured readers (14), it is the row
where the sema/codegen ontology fork is widest, and `type_satisfies_concept`
(`sema.zig:4343`) already reaches into `alias_defs` to answer a *concept*
question and into `table_methods` to answer a *method* question — meaning the
alias record is the join key those two rows are secretly sharing. Give aliases
a real identity and a real `member` edge and rows 2 and 3 stop being separate
problems.

The prerequisite is not negotiable, and it is not really a ranking entry:
without stable semantic identity every "edge" is a pair of strings, and a pair
of strings is what we already have, spread across 62 hash maps.
