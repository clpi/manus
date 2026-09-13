| field | value |
|---|---|
| title | Foreign implementation, tracked as unclosed obligation: `toolchain@{ foreign = obligation }` |
| supersedes | `docs/spec/foreign.md` two-class licence model for completion purposes |
| status | Active policy. The licence census remains as a debt inventory; it no longer qualifies tooling as complete. |

| # | directive |
|---|---|
| 1 | A classified foreign dependency is an **unclosed obligation**, not a completed state. |
| 2 | Adding a ledger entry records the obligation. It does not satisfy it. |
| 3 | No gate passes on the strength of classification alone. |

| section |
|---|
| Why the licence model is insufficient |

| # | directive |
|---|---|
| 1 | The prior model (`docs/spec/foreign.md`) licensed two classes: `ledger` (bootstrap debt with termination condition) and `oracle` (test equipment). |
| 2 | Its own PASS line stated the limit honestly: "PASS is !a claim that the foreign code is fine. It is a claim that every file has a licence on record and the debt did !grow." |
| 3 | Under the Idol-only toolchain requirement, that PASS is not completion. A toolchain whose build, linker, runtime, or verification machinery depends on another language is not the deliverable, however completely its foreign parts are catalogued. |
| 4 | The licence census is retained as a **debt inventory**. Its verdict answers "is the inventory complete and shrinking" — never "is the toolchain Idol-only". |

| section |
|---|
| What counts as foreign implementation |

| # | directive |
|---|---|
| 1 | Foreign implementation is any required behavior executed by a non-Idol implementation in the toolchain closure: compilation, realization, execution, delivery, verification, development. |
| 2 | The closure follows execution, generation, linking, loading, verification, and recovery — not directory boundaries. Moving a dependency outside the repository does not remove it. |
| 3 | The following are foreign implementation regardless of how they are labelled: |
| 4 | An Idol wrapper around foreign behavior (`gatecap`, shell-out, FFI call) is a foreign dependency. The wrapper does not convert the dependency. |
| 5 | Foreign code embedded in a string, compiled into a static library, hidden in a generated artifact, downloaded during installation, or executed through a remote service is a foreign dependency. |
| 6 | A failure-only fallback to foreign behavior is a foreign dependency. The fallback path is part of the closure whether or not it executes on the happy path. |
| 7 | An indirect foreign invocation (Idol calls A, A shells to foreign B) is a foreign dependency. Transitivity is not optional. |
| 8 | An artifact with missing origin (no canonical source, no production chain) is treated as foreign until its provenance is established. |

| # | directive |
|---|---|
| 1 | The following are **not** foreign implementation: |
| 2 | Foreign input: an Idol-written importer reading another language as explicitly identified input, preserving its laws and provenance. Reading is not implementing. |
| 3 | Foreign oracle: an external compiler or runtime measured as a competitor. Comparison is not dependency. Invoking the oracle's compiler or runtime to perform Idol's own work crosses the line from comparison to dependency. |
| 4 | Physical output: native instructions, object bytes, Wasm bytes produced by Idol are realizations of Idol code, not foreign implementations. The encodings, layouts, and interface requirements must be expressed as Idol facts consumed by Idol implementations. |
| 5 | The execution platform: kernel, driver, browser engine, editor host, firmware. These are the named platform, not the toolchain. A hosted milestone must not be presented as whole-system closure. |

| section |
|---|
| No permanent exemptions |

| # | directive |
|---|---|
| 1 | The following phrases do not terminate an obligation: "temporary", "generated", "only a helper", "only used during development", "only test equipment on the shipping path". |
| 2 | Each is a description of current state, not a completion claim. |
| 3 | A generated file names its generator and the condition under which the generator becomes Idol. Until then, the generator's language is the obligation. |
| 4 | A helper used only during development is part of the delivery closure (delivery includes verification). Its language is the obligation. |

| section |
|---|
| Obligation records |

| # | directive |
|---|---|
| 1 | Every foreign implementation in the closure carries an obligation record: |
| 2 | `obligation <path-or-capability> until:<Idol replacement> next:<exact next action> owner:<responsible party>` |
| 3 | `until:` names the Idol implementation that closes it. "When Idol can" is not a name. |
| 4 | `next:` names the single concrete action that advances closure. "Continue work" is not an action. |
| 5 | An obligation with no `next:` is stalled, not waiting. The gate reports it as stalled. |
| 6 | Closing an obligation means the Idol replacement executes the behavior and the foreign implementation is deleted from the closure — not wrapped, not kept as fallback. |

| section |
|---|
| The acceptance question |

| # | directive |
|---|---|
| 1 | For every implementation required to build, run, inspect, verify, update, or recover this deliverable: can the system establish its canonical Idol source and the complete chain that produced the executable behavior? |
| 2 | An incomplete answer does not become a pass. |
| 3 | The graph supplies identities, dependencies, source laws, producers, executions, outcomes, witnesses, and provenance. No parallel registry. No second database. Physical views derive from graph-owned meaning. |
| 4 | The verifier that answers this question must itself be Idol. A Python program certifying "everything is Idol" leaves the toolchain incomplete. An external solver cannot be the undisclosed implementation of Idol's proof capability. |

| section |
|---|
| Relation to bootstrap stages |

| # | directive |
|---|---|
| 1 | S0 (Zig seed produces host compiler) is an honest description of unfinished work. It is not a completion standard. |
| 2 | The bootstrap contract's separation of compiler B from backend sovereignty is retained as a work plan, not adopted as the finish line. |
| 3 | Compiler B acceptance additionally requires the B-production chain to satisfy this policy: B must be built by Idol-executed steps from canonical Idol source, or the remaining foreign steps are named obligations with next actions. |
