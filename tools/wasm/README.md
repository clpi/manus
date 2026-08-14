# Idol WebAssembly

This directory contains Idol's WebAssembly foreign-lawset implementation and
evidence. Start at [`../../AGENTS.md`](../../AGENTS.md); the sole semantic law is
[`../../docs/spec/constitution.md`](../../docs/spec/constitution.md), the live
compiler frontier is [`../../docs/bootstrap.md`](../../docs/bootstrap.md), and
performance claims belong in
[`../../docs/performance.md`](../../docs/performance.md).

The current tracked `.id` engine remains a standalone interpreter/JIT with
private opcode and stack machinery, standard-root dependencies, and runtime
fallback. That is SOURCE-ZERO and convergence debt; it is not the architecture
described below.

The target imports WebAssembly into the same semantic graph as every other lawset.
Foreign origin, operations, descriptors, memory rules, imports, ABI, failures,
effects, worlds, and provenance remain exact. Demand selects what exists, and
realization selects the lawful physical form. An interpreter, native compiler,
foreign engine, opcode table, or target-specific code generator is an
implementation candidate—not a second semantic architecture.

The admitted public model follows ROOT-ZERO: package location is provenance and grants
no capability; the standard distribution owns no native namespace. It follows
FACE-ZERO: subject and static identities are exposed directly, computed keys use
`[]`, and source syntax never chooses storage or execution strategy.

PREDICATE-ZERO keeps capability, validation, presence, trap, and unknown states
as facts or cases. Foreign predicate spellings remain foreign provenance until
their mapping to native semantic facts is witnessed.

Canonical project-owned source uses `.id` and new canonical `.id` is freely
admitted. The tracked `.id` files under this directory currently carry
SOURCE-ZERO debt in their *noncanonical patterns* — not by virtue of being
`.id` — and serve as behavioral or differential evidence while that debt is
repaired in place into canonical source. They are not canonical implementation
templates. Foreign `.wasm` and `.wat` fixtures remain foreign inputs.

Current capability and performance are never taken from this README. Verify the
exact checkout with the repository `wasm-test` build step under the shared build
lock, then consult fresh private-run evidence. Conformance requires by-value
agreement with an identified oracle and controls that can make the gate fail.
Performance reporting follows correctness and separates decode/import, compile,
instantiate, startup, steady execution, memory, runtime footprint, artifact
size, and end-to-end latency. Always identify the selected realization and any
fallback.
