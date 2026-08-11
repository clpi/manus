# Idsem and WebAssembly

This page projects current architecture without claiming an unverified command
surface. The sole law is
[`docs/spec/constitution.md`](../spec/constitution.md); canonical source uses
`.id`.

WebAssembly is an imported, law-bearing foreign format. Its numeric widths,
memory behavior, calls, traps, control rules, ABI, and other observable facts
remain explicit until equivalence is proved. Foreign spellings and module paths
are provenance, not native relation identity.

The target architecture is:

```text
wasm bytes
-> law-bearing import
-> shared semantic graph
-> demand
-> shared realization and machine selection
```

An imported operand stack does not require a permanent runtime stack, and Wasm
does not create a second optimizer or virtual-machine ontology. Sealed facts may
erase stack machinery, generic dispatch, unused runtime capabilities, adapters,
and undemanded memory state.

## FTCFTW evidence

Idsem-Wasm performance claims separately measure decode/import, compile,
instantiate, startup, steady execution, memory, artifact and runtime footprint,
and end-to-end latency from bytes available to useful completion. Generated-C
or isolated throughput evidence does not prove the whole envelope.

World authority is not granted by importing a package or by a legacy standard
distribution path. WASI and other host interfaces retain their foreign law,
origin, worlds, effects, outcomes, and evidence.

Verify the production frontier in [`docs/bootstrap.md`](../bootstrap.md) before
claiming native or Wasm ownership.
