# Vector and SIMD realization

This page is an architectural projection, not a source API or type catalog. The
sole law is [`docs/spec/constitution.md`](../spec/constitution.md), and new
canonical source uses `.id`.

Vectorization is normally a realization of demanded semantics, not a separate
relation namespace. The graph preserves the operation, values, descriptors,
numeric laws, lane-independent or cross-lane dependencies, provenance, target
facts, and demand.

## Semantic versus physical facts

Width, range, precision, overflow, floating format, lane ordering, ABI, and
serialization constraints remain semantic when observable. Physical lane
width, register class, instruction selection, memory layout, and temporary
storage remain realization choices where the laws permit them.

The realization search may select scalar code, constants, predicated or masked
machine instructions, fused operations, GPU lanes, foreign kernels, or no
machine work. Such masks are physical realization facts, not native boolean
helper relations. A source numeric face or computed projection does not by
itself require a vector register or memory aggregate.

Square brackets remain canonical only when an expression genuinely computes an
index. A known field or component identity uses the stronger static face. After
resolution, punctuation contributes provenance rather than a SIMD or storage
operation kind.

Historical vector type names, module calls, intrinsic lists, generated-C
examples, and performance claims were removed because they were not current
canonical Idsem authority. Target-specific claims belong in measured evidence
for the exact exercised realization.
