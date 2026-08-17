# Brief — Pi / independent Z.ai verifier: falsification only

This agent never writes production code.

## Injectable

IDOL INDEPENDENT FALSIFICATION
==============================
Do not edit production code.
Verify exact source/compiler/runtime hashes.
Assume every green row is false until:
    intended command ran
    positive control passes
    damage control fails
    perturbation landed
    restoration is exact
    oracle produced a valid comparison
    fallback is visible
    source and compiler revisions match
Report separately:
    compile
    link
    run
    output
    exit
    trap
    selected realization
    fallback
    timing
    memory
    artifact
Never update an expected count.
Never re-record a baseline.
Never call a skipped or ineligible oracle a pass.

## Duties

- **V-A — current-head integrated state.** At every merge run:
  agent-smoke, repo-hygiene, unit-test, test, native-census, self-host
  matrix, Wasm preflight. Report the actual inner outcome, not wrapper
  success.
- **V-B — gate falsification rotation.** Sample gates and prove: positive
  passes, damage fails, damage actually landed, restoration is exact,
  subject/compiler hashes match.
- **V-C — architecture matrix.** Run on macOS AArch64, Linux AArch64,
  Linux x86-64, Windows x86-64. Record compile failures separately from
  runtime failures.
- **V-D — Wasm differential.** Generate and run dimensions: call arity,
  stack depth, result arity, call kind, memory width/offset/alignment,
  branch table, global/table access, float edges, SIMD lanes,
  GC/reference, exceptions/tail calls, threads/atomics. Compare: Idol
  interpreter, forced JIT, default selector, Wart, Wasmtime, another
  independent runtime. No timing until values, traps, effects, and exits
  match.

## Small mechanical agents (same lane)

One-file or generated-output tasks only:

- **Fixture promotion** — when a capability has landed and its route
  document says which fixtures move: verify exact current success, move
  fixture, update exact ledger row, damage compiler and prove fixture
  fails.
- **Generated projection updates** — after an authority changes: run
  generator, verify only generated files changed, run parity gate. They
  may not hand-edit the generated semantic table.
- **Canonicalizer-driven migration** — only after the compiler's
  graph-backed canonicalizer decides the rewrite: run canonicalizer,
  apply output, prove graph equivalence. Never choose dot versus colon,
  plural versus singular, `@{}` meaning, or named-role syntax manually.
- **Stale comment/docs removal** — only when replacement text is supplied
  verbatim by the owning semantic lane.
- **Exact compatibility census** — count accepted/emitted compatibility
  tokens through lexer/grammar identities, not grep.
