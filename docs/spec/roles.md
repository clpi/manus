# Idol grammar-role projection

The sole semantic law is [`docs/spec/constitution.md`](constitution.md). This
page describes the role projection required by the production frontend; it is
not a role taxonomy or a second grammar authority.

## One owner

One machine-readable grammar must project every lexical and parser role needed
by the compiler, formatter, canonicalizer, Tree-sitter, LSP, MCP, tests, and
documentation. [`GAP-134`](../../gaps/GAP-134.md) owns that missing projection.
[`GAP-145`](../../gaps/GAP-145.md) owns the distinct lexical identities and
immutable token view it consumes.

The generated projection must include, as demanded:

- token identity and exact source span;
- canonical, compatibility, deprecated, and removed status;
- expression, binding, statement, and descriptor-member starts;
- prefix, postfix, delimiter, and offside capabilities;
- precedence and associativity;
- payload and source-law provenance.

No handwritten LSP table, parser switch, punctuation list, token text, or
highlight color may outrank or extend that owner. Protocol and editor classes
are renderings of generated roles, never semantic identities.

## Recognition boundary

Roles answer only what source structure can be recognized. They do not assign
relation, subject, application, descriptor, world, demand, case, value, or
realization identity. Resolution consumes the minimum recognized structure and
establishes those graph facts.

Current delimiter roles remain:

- `()` ordinary application and grouping;
- `{}` structured packs, descriptor application, and descriptor homes;
- `[]` genuinely computed projection;
- `.` statically named projection after an explicit subject;
- `:` admitted descriptor, subject, and home roles;
- `@` bare descriptor anchor or postfix relation anchor, never a directive.

An incompatible source face and resolved subject diagnose before lowering.
Parser acceptance never authorizes a backend fallback.

## Current implementation boundary

The tracked parser and tooling still contain handwritten role decisions and
string-shaped classification. They are duplicate-authority and SOURCE-ZERO
debt. Existing highlight corpora may serve as differential evidence, but they
cannot establish the canonical role set.

Closure requires one authority edit to regenerate every consumer, production
use of the immutable token view, an adversarial control that changes the
authority and observes every affected projection, and failure when any consumer
reconstructs a role from spelling.
