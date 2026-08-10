# Agent Alignment Compass

This file is a short priority router. It is not language law and must not grow
into a second specification. Read `docs/spec/constitution.duo`, `CLAUDE.md`,
`AGENTS.md`, `.agents/AGENT_CANONICAL.md`, and
`.agents/AGENT_COORDINATION.md` before editing.

## One target

Move monotonically to:

```text
current canonical `.id` source
-> Idsem-owned semantic identities and facts
-> compiler B through the honest existing backend
-> B compiles C from the identical compiler source
-> B/C semantic and behavioral equivalence
-> progressively Idsem-owned realization and backend
-> Idsem Wasm faster than Wasmtime on equivalent semantics
```

The destination is 100% self-hosted canonical Idsem. A `.id` filename does not
transfer authority, and `.duo` remains historical source provenance during
migration. Generated projections, epoch-1 syntax, C-backed proofs, and Idsem
wrappers over Zig owners remain bootstrap debt.

Idsem and Lua are distinct lawsets hosted by one compiler. Idsem is not a Lua
superset, and Lua compatibility may not define Idsem semantics or architecture.

## Current phase

The language architecture is already specified. The work now is the minimum
closed semantic kernel, compiler B, bootstrap closure, and proof. Do not start another pass,
invent another semantic taxonomy, add surface syntax, or strengthen a bootstrap
subsystem that the constitution requires Idsem to replace.

Horizontal ports are useful only when they remove a dependency. They are not
self-hosting progress unless semantic and production authority move into Idsem.

## No New Zig

Do not add Zig files, Zig semantic owners, Zig gates, Zig classifiers, Zig
registries, or Zig reconstruction caches.

An edit to existing Zig is exceptional bootstrap wiring. It is admissible only
when all of these are true:

1. Canonical Idsem already owns the semantic fact or relation.
2. The edit only passes that authority into the current production path.
3. No decision is reconstructed from syntax, text, names, or backend shape.
4. Host semantic code is net negative, or the same change names the exact
   deletion trigger and the Idsem file that replaces it.
5. A focused direct-native value proof fails before the edit and passes after.

If those conditions do not hold, implement the missing authority in Idsem first.
Running the existing Zig bootstrap and its gates is validation, not permission
to expand it. Retain old host implementations as differential oracles until the
Idsem replacement is proven, then delete them.

## SHC Queue

Every implementation task belongs to one rung. Do not substitute another audit,
corpus sweep, backend target, or tool surface for the earliest open rung.

1. **SHC-00 bootstrap.** Freeze the minimum compiler-B subset and the B -> C
   acceptance contract in `lib/compiler/bootstrap.duo`.
2. **SHC-01 application.** Preserve relation, subject, arguments, result,
   descriptor, world, witness, provenance, and demand identity.
3. **SHC-02 evidence.** Make provenance and witnesses ordinary queryable Idsem
   facts so no consumer reconstructs them from syntax or names.
4. **SHC-03 substrate.** Finish bytes, views, strings, arenas, vectors, maps,
   interning, bitsets, source/span, filesystem read, and diagnostics. Nothing
   outside this compiler-critical basis blocks B.
5. **SHC-04 through SHC-10.** Move one thin production path through source,
   lexer, generated grammar/parser, binding, graph construction, relation
   resolution, and minimal lowering. Widen only after that path executes.
6. **SHC-11 through SHC-14.** Build compiler B with the existing honest backend;
   make B build C from identical source; prove semantic, diagnostic, behavioral,
   and artifact equivalence; then retire Zig semantic owners in dependency order.
7. **SHC-15 backend.** After B -> C, progressively transfer flow, allocation,
   encoding, object emission, and linking into Idsem.
8. **Wasm supremacy.** Reuse the same value, demand, liveness, allocation,
   encoding, and provenance substrate. Never create a Ward-only IR kingdom.

The first useful SHC slice is the smallest real compiler path that makes B
produce an executable. It may use the existing C/native bootstrap backend when
that path is explicit and attributable. That is valid B evidence, not backend
sovereignty. Do not shrink parser or semantic meaning merely to avoid tables,
iteration, worlds, or application identity.

## Evidence Labels

Every capability report keeps these facts separate:

```text
canonical source
Idsem semantic owner
direct execution
production dispatch
oracle identity
differential result
boxed values
generated C
external compiler
```

Only their required conjunction proves self-hosting. A gate may not consume an
untracked fixture, a noncanonical fixture, or a mutable shared artifact. A zero
requires a positive control. A named checker not reachable from an aggregate is
not release evidence.

## Semantic Discipline

- One relation has one identity from source through machine provenance.
- Worlds grant authority; homes only navigate identity.
- Work from the subject when the subject is held.
- `std` is a retiring distribution root, never semantic authority.
- `std.script` is migration debt and must not be replaced by an alias.
- If process, environment, filesystem, or result vocabulary is unresolved,
  record `SEMANTIC-VOCABULARY-BLOCKED`; do not invent a helper.
- Canonicality is part of correctness. Parser, tests, and performance passing do
  not excuse a weaker conventional spelling.
- One file owns one durable semantic boundary. Do not create `utils`, `types`,
  pass-number, migration, or agent-shaped homes.

## Coordination

Inspect the dirty tree and live claims before work. Claim exact paths through
the repository MCP, never overwrite another session, never stash, never hard
reset, and serialize heavy validation. Commit only explicit pathspecs when
requested.

Record architectural blockers in `gaps/GAP-0NN.md`. Record performance evidence
in `docs/performance.md`. Use the current checkout and fixed artifacts for every
claim; do not infer implementation state from historical pass documents.
