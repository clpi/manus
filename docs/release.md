# Release Proof

**Status:** Implemented proof-bundle v0; all seven public proof domains remain
release blockers. **Audience:** maintainers and release auditors.

The release contract has one public entry point:

```sh
duo prove
```

It enters the repository workspace, runs each live supporting gate once, and
writes `.duo/proof/release-0.1/summary.json` plus one log per gate. The summary
records the source revision, complete worktree status, exact commands, declared
readiness, gate results, and the verdict for each proof domain.

`duo prove` exits nonzero when the worktree is dirty, a gate fails, a gate cannot
run, or any domain is still partial or planned. Passing a supporting gate does
not promote a domain.
Promotion to `supported` is a reviewed change to the canonical domain data in
`src/proof_carrying.zig`, backed by evidence that satisfies the complete answer
below.

## Seven proofs

| Domain | Readiness | Current supporting gates | Complete release answer |
| --- | --- | --- | --- |
| Performance | partial | `zig build bench-proof-gate` | Equivalent algorithms and semantics, hostile workloads, inspected artifacts, and honestly reported losses |
| Compression | planned | none | Measured deletion of duplicated semantic authorities and generated residue from one canonical source |
| Dynamicity | partial | `zig build semantics-gate`, `zig build native-differential` | One source demonstrated across open, guarded, sealed, native, and vector realizations without semantic rewriting |
| Metaprogramming | partial | `zig build meta-gate` | One ordinary semantic program derives implementation, tests, documentation, tooling, and foreign projections |
| Foreign leverage | partial | `zig build test`, `zig build abi-matrix` | An untouched foreign project receives useful, deterministic projections from imported semantics |
| Systems credibility | partial | `zig build native-differential`, `zig build wasm-test` | Ward and bootstrap stages work through the released compiler with explicit, measured fallbacks |
| Trust | partial | `zig build test`, `zig build repo-hygiene`, `zig build public-safety`, `zig build reproducibility-smoke` | Every public claim resolves from source and revision to commands, artifacts, raw evidence, and a reproducible verdict |

The v0 bundle proves orchestration, source revision and worktree state, exact
commands, ordered gate results, and raw logs. It does not yet claim
artifact-level links for every binary, IR, assembly listing, benchmark sample,
or release statement. Those are requirements for promoting the trust domain,
not implied capabilities of v0.

## Focused gates

Use these while repairing one proof domain; use `duo prove` for the release
verdict.

| Concern | Command |
| --- | --- |
| Build and correctness | `zig build test` |
| Repository hygiene | `zig build repo-hygiene` |
| Public safety | `zig build public-safety` |
| Toolchain pin | `duo run scripts/ci_zig_version.duo` |
| Reproducible compiler | `zig build reproducibility-smoke` |
| Direct ARM64 proof | `zig build pass11-direct-smoke` |
| Native module barriers | `zig build pass11-module-smoke` |
| Native differential corpus | `zig build native-differential` |
| Wasm conformance | `zig build wasm-test` |
| Benchmark proof matrix | `zig build bench-proof-gate` |
| Full benchmark suite | `zig build bench` |
| Agent-facing tier zero | `zig build agent-smoke` |
| Canonical corpus deny table | `zig build audit100` |

The release proof runs sequentially and ends with
`reproducibility-smoke`, which intentionally removes and rebuilds `zig-out`.
Run it from an otherwise idle release checkout.

## Artifacts

| Artifact | Command |
| --- | --- |
| Compiler binary | `zig build` -> `zig-out/bin/duo` |
| Release proof summary | `duo prove` -> `.duo/proof/release-0.1/summary.json` |
| Release source state | `duo prove` -> `.duo/proof/release-0.1/worktree.txt` |
| Release proof logs | `duo prove` -> `.duo/proof/release-0.1/<gate>.log` |
| Wasm module | `duo compile file.duo --target wasm32-wasi -o out.wasm` |
| Generated Wasm tables | `duo wasm-tables emit` -> `lib/std/wasm/opcode_lookup.duo` |

Commit generated Wasm lookup tables when `wasm_semantic.zig` changes.

## Versioning

Release tags are cut from `main`. `CHANGELOG.md`, when present, is the release
history. Historical pass plans are deleted architecture records in git history;
they are not release commands.

The toolchain pin authority is `build.zig.zon` `minimum_zig_version`, mirrored
by the CI `ZIG_VERSION` environment value and checked by
`scripts/ci_zig_version.duo`.
