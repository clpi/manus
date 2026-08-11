# Descriptors, laws, and semantic requirements

This page is a current architectural projection, not a syntax specification.
The sole law is [`docs/spec/constitution.md`](../spec/constitution.md), and
canonical source uses `.id`.

Idsem describes a value through graph-owned identity plus facts. A descriptor
can state the laws and structure demanded of a subject without creating a
parallel interface, trait, host-tagged-union, or reflection namespace.

## Requirements

A semantic requirement preserves:

- the exact subject and relation identities;
- required operand and result facts;
- descriptor laws and proven correspondences;
- worlds and effects where authority is observable;
- provenance and evidence supporting satisfaction;
- demand and the lawful realization set.

Structural similarity, a source name, a package path, or a hash does not prove
semantic identity. Where equivalence or satisfaction is required, establish it
from authoritative graph facts. Unknown remains unknown.

Descriptor, shape, identity, world, capability, demand, and refinement facts
are structural knowledge, not `has`, `is`, `can`, or `exists` predicates.
Absence and failure remain semantic cases rather than sentinel values, and an
immediate state change uses the admitted transition instead of query, boolean,
branch, and mutation plumbing.

## Source and realization

Source faces provide compact recognition and provenance, then erase into graph
facts. A statically known field uses named projection; square brackets are for a
genuinely computed key. Neither face chooses storage or dispatch.

Descriptor knowledge must preserve realization freedom. It may permit
specialization, devirtualization, scalarization, fusion, or complete erasure,
but it does not imply an object, vtable, boxed value, allocated record, or
runtime reflection structure.
