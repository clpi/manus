# Concurrency, effects, and worlds

This page states current Idsem architecture without admitting a source API. The
sole law is [`docs/spec/constitution.md`](../spec/constitution.md); canonical
source uses `.id`.

Concurrency is not owned by a library namespace. It is expressed through
semantic relations, dependencies, worlds, effects, values, demands, and
observable ordering laws.

## Semantic obligations

Concurrent work must preserve, where applicable:

- subject and application identity;
- dependency and completion ordering;
- carried values and result demand;
- cancellation, failure, and outcome as distinct cases;
- required process, thread, device, clock, network, or other world facts;
- provenance for scheduling and transformation decisions.

Importing a package grants no authority. A scheduler, channel, thread, process,
or atomic implementation may participate only under the required world and law.
Transport completion is not automatically the requested semantic outcome.
Readiness, capability, cancellation, failure, and availability remain semantic
facts or cases. Unknown is not false, and an immediate state change uses its
admitted transition rather than query, boolean, branch, and mutation plumbing.

## Realization

The same semantic dependency graph may lawfully realize as compile-time
evaluation, direct sequential code, a state machine, cooperative scheduling,
threads, processes, vector lanes, GPU work, foreign primitives, or no runtime
work. Source recognition must not force one of these forms.

Existing project-owned concurrency implementation is SOURCE-ZERO or host debt.
Do not preserve stale examples, add a replacement namespace, or infer canonical
spellings from the old API shape. Missing irreducible vocabulary is
`SEMANTIC-VOCABULARY-BLOCKED`.
