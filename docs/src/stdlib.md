# Standard implementation without a namespace

This page is a projection of the Idol constitution, not an API catalog or a
second source of language law. The sole semantic authority is
[`docs/spec/constitution.md`](../spec/constitution.md). Canonical project source
uses `.id`; every tracked project-owned `.id` file is SOURCE-ZERO debt that
must be semantically migrated or deleted.

Idol has no canonical semantic standard-library namespace. The repository's
physical standard distribution is migration and implementation provenance. Its
paths contribute no relation identity and grant no world authority.

## Root-zero

Canonical operations resolve by exact semantic facts:

- relation identity;
- subject and operand roles;
- descriptor and result laws;
- required worlds and effects;
- demand, stage, target, origin, and trust.

Packages contribute relations, descriptors, laws, world interfaces,
implementations, and realizations. They do not acquire semantic authority from
their path, and moving an equivalent implementation between packages does not
change program meaning.

Do not add a new canonical `std.*` call, API, or example. Do not replace `std`
with another universal root. If the required relation or world has not been
admitted, the honest state is `SEMANTIC-VOCABULARY-BLOCKED`.

Do not replace a namespace helper with a predicate helper. Membership,
presence, capability, descriptor knowledge, absence, and desired state remain
graph facts, cases, or transitions rather than `has`, `is`, `can`, `exists`, or
sentinel-shaped APIs.

## Discovery and realization

Discovery begins from the semantic subject and filters applicable relations by
descriptor, world, law, scope, and stage. Documentation, completion, tests,
foreign mappings, and implementation registration project from the same
graph-owned facts rather than independently maintained namespace tables.

Several implementations satisfying one relation and law are realization
candidates. Demand and cost may select a constant, scalar, vector, parallel,
foreign, GPU, or other lawful form. A sealed program pays no runtime registry,
package traversal, or dispatch cost for this discovery.

## Migration

Existing project-owned standard-distribution source is temporary SOURCE-ZERO
debt while compiler B directly depends on it. Migrate dependencies in the
compiler-B cone by identifying the actual relation, subject, world, law, and
demand; then delete the old source and namespace authority without weakening
machine realization. Compatibility inputs belong in generated, structured, or
external conformance material rather than an in-tree stale source library.

The executed frontier and next dependency are recorded in
[`docs/bootstrap.md`](../bootstrap.md). Historical API catalogs belong in Git
history and must not train new Idol source.
