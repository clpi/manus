# AI and ML semantic realization

This page records current Idsem architecture without proposing a surface DSL.
The sole semantic law is
[`docs/spec/constitution.md`](spec/constitution.md); canonical source uses
`.id`.

AI and ML workloads enter the same semantic graph as other Idsem and foreign
programs. Preserve exact values, shapes, numeric laws, precision requirements,
dependencies, worlds, effects, provenance, and result demand. Do not promote a
tensor spelling, device directive, kernel name, framework namespace, or host
API shape into native semantic identity.

## Realization freedom

Given sufficient facts and demand, the same semantic computation may realize
as compile-time evaluation, scalar code, SIMD, fused kernels, specialized
layouts, GPU work, foreign libraries, views, zero-copy boundaries, or no
runtime work. Layout, storage, device, and precision remain physical choices
unless the program law makes them observable.

Foreign frameworks and kernels keep their origin and lawset. They become
realization candidates for a native relation only when equivalence is witnessed
for the demanded domain. Their package and symbol names do not contaminate
native vocabulary.

Shape, capability, applicability, precision, and target knowledge remain graph
facts rather than `is`, `has`, `can`, `supports`, or `ready` predicates. Unknown
and unsupported are distinct cases, and realization decisions retain their
evidence instead of becoming optimization booleans.

## FTCFTW and priority

Performance evidence must bind to the exact exercised path and report compiler
work, startup, memory, artifact and support footprint, runtime, and relevant
transfer or initialization costs. A generated wrapper or named intrinsic is not
proof of direct realization.

Compiler B remains the project critical path. Read
[`docs/bootstrap.md`](bootstrap.md) before spending migration work on AI/ML
breadth.
