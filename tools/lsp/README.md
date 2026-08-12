# Idol language server

This directory contains the Language Server Protocol projection for Idol.
Start at [`../../AGENTS.md`](../../AGENTS.md); the sole semantic law is
[`../../docs/spec/constitution.md`](../../docs/spec/constitution.md), and the
current executed compiler frontier is
[`../../docs/bootstrap.md`](../../docs/bootstrap.md).

The target server projects the compiler's semantic graph over LSP. The current
tracked `.id` server still carries a private scanner, handwritten roles and
worlds, standard-root completion, retired snippets, and string-shaped semantic
decisions. That is SOURCE-ZERO and duplicate-authority debt, not proof of the
target architecture. After migration, the server defines no keywords,
relations, descriptors, canonical source, diagnostic meaning, completion
vocabulary, or semantic-token roles; those facts come from the one graph and
the generated projections of the one grammar authority.

User-facing features should therefore answer semantic questions:

- what identity is at this span;
- which relations apply to the possessed subject;
- which descriptor, world, law, effect, and demand qualify the result;
- where an identity is defined and used;
- which canonicality finding or realization decision explains an outcome.

Missing graph coverage is a compiler/tooling gap, not permission to grow a
second parser or word scanner. Protocol strings and integer token encodings are
renderings only and must retain a route back to structured facts.

ROOT-ZERO and FACE-ZERO apply to all results. Completion is subject-oriented,
package paths grant no authority, and the standard distribution owns no native
namespace. Named identities look static; `[]` is suggested only for genuinely
computed keys; neither face selects a representation.

PREDICATE-ZERO also applies. Completion, diagnostics, and code actions expose
semantic facts, cases, refinements, and transitions rather than teaching
boolean `has`/`is`/`can`/`exists` helpers or sentinel checks. Unknown, absent,
false, and unresolved remain distinct.

Canonical project source uses `.id`. Any tracked project-owned `.id`
implementation here is SOURCE-ZERO debt and must be semantically migrated or
deleted, never copied as an example. Physical launcher and environment names
containing `duo` are bootstrap aliases and deletion targets, not current
language identity.

Validate the live implementation with the repository `lsp-gate` build step
under the shared build lock. Evidence must come from real protocol traffic,
value assertions, lifecycle coverage, and a control that demonstrates failure.
Record the exact tree and known aggregate state; do not infer capability from a
successful handshake or from stale counts in documentation.
