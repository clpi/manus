# Idol soundness projection

The supreme law is [`docs/spec/law.md`](law.md) and
[`docs/spec/constitution.md`](constitution.md) is its structured expansion. This
page projects its obligation, witness, failure, and evidence rules. It is not a
second specification, a fact registry, or an implementation pattern.

## Obligation handling

No correctness obligation may be silently assumed. The graph retains the
obligation and the facts supporting its handling. Current lawful handling
includes:

- a witness proves the required facts; the physical obligation may erase while
  its fact, witness, application, and provenance remain inspectable;
- when the relation, world, and contract admit it, realization selects an
  explicit guard whose failure is a semantic case and whose causal evidence
  remains inspectable;
- when neither proof nor a lawful guarded realization is available, compilation
  fails closed with a structured diagnostic naming the obligation, site, and
  missing fact.

Accepted but unproved, unguarded, and wrong is not a fourth outcome. Refusal is
always preferable to silently assigning meaning or assuming a missing fact.
These handling forms are not a closed semantic enum or a finite fact registry;
qualification remains in graph facts, worlds, contracts, demands, and
witnesses.

These outcomes are cases and facts, not `is`, `has`, `can`, `valid`, or
`supported` predicates. Unknown, absent, false, unresolved, and not applicable
remain distinct. A compiler budget may reduce proof precision and therefore
select a guard or diagnostic; it may never change program meaning or turn
unknown into success.

## Realization

A proven obligation need not produce machine work. A demanded guard may realize
as the cheapest lawful check for the selected target and world. A diagnostic
produces no accepted artifact. None of these outcomes creates a second relation
identity, and physical check shape never becomes semantic law.

Every accepted choice retains the source, graph identity, demanded facts,
witness or missing-fact evidence, transformation, realization, and machine or
diagnostic provenance needed to answer why it occurred.

## Current implementation boundary

[`GAP-064`](../../gaps/GAP-064.md) remains open because integer division by zero
can still reach a silent fourth state in current production paths. Its closed
subcases do not close that defect class. [`GAP-124`](../../gaps/GAP-124.md)
owns graph-derived world, subject, vocabulary, sentinel, and control
canonicality; textual scans are migration pressure, not soundness proof.

Closure requires production perturbation controls for each outcome, exact
run-to-evidence binding, and an aggregate result whose inner semantic outcome
is authoritative. A fixture, outer transport success, or prose claim is never
that evidence.
