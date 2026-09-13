| field | value |
|---|---|
| title | Obligation gate: Idol-only toolchain closure enforcement |
| policy | `docs/spec/foreign-obligation.md` |
| status | Design. Replaces the licence-census PASS as the completion gate. |

| section |
|---|
| What the gate establishes |

| # | directive |
|---|---|
| 1 | The gate answers: for every implementation in the toolchain closure, is there a canonical Idol source and a complete Idol-executed production chain, or a named open obligation with a next action? |
| 2 | The toolchain closure is: everything executed to build, link, run, inspect, verify, update, or recover the deliverable — including generators, test drivers, benchmark harnesses, statistical analyzers, proof checkers, admission gates, installers, and recovery tools. |
| 3 | The gate FAILS if any closure member has neither Idol source nor an open obligation record. Silence is not a pass. |
| 4 | The gate FAILS if any obligation record lacks `until:` (named Idol replacement) or `next:` (concrete next action). |
| 5 | The gate reports obligations as OPEN, STALLED (no next action), or CLOSED (Idol replacement executes, foreign deleted). It never reports "licensed" or "classified" as a terminal state. |

| section |
|---|
| How the gate sees |

| # | directive |
|---|---|
| 1 | The gate consumes graph-owned facts: implementation identities, dependency edges, source laws, producers, executions, outcomes, witnesses, provenance. |
| 2 | Dependency edges must be transitive: if Idol module M invokes capability C, and C executes foreign behavior F, the gate records M → F. One hop is not enough. |
| 3 | The gate detects: file-extension-visible foreign code, embedded foreign programs (strings, payloads, `@c.emit`-class sites), foreign static libraries linked into artifacts, shell-out and FFI call sites, network invocations of remote compilation or execution services, and artifacts whose provenance chain terminates without a source. |
| 4 | Renaming files does not pass. Moving files does not pass. Wrapping behavior in Idol does not pass. Unobserved dependency paths do not pass. |

| section |
|---|
| Discriminatory controls (negative) |

| # | control | planted violation | required gate verdict |
|---|---|---|---|
| 1 | Indirect foreign invocation | Idol module calls a helper that shells out to a foreign formatter. No direct foreign call site in the module. | FAIL: transitivity. The gate must follow the helper edge. |
| 2 | Embedded program | A Python program embedded as a string constant in an `.id` file, executed via a shell escape. No `.py` file on disk. | FAIL: embedded-site detection. Extension census alone must not pass. |
| 3 | Foreign static library | A `.a` archive linked into the final binary, containing foreign-compiled objects with no source in the tree. | FAIL: artifact provenance. The link inputs are part of the closure. |
| 4 | Failure-only fallback | Primary path is Idol; on error, execution falls back to a foreign implementation. Tests only exercise the happy path. | FAIL: fallback coverage. The fallback is in the closure whether or not it ran. |
| 5 | Remote compilation dependency | Build step uploads source to a remote service and downloads the compiled artifact. No foreign code in the repo. | FAIL: network edge. The closure follows execution, not directory boundaries. |
| 6 | Artifact with missing origin | A binary in the toolchain whose provenance chain ends at "downloaded" or "prebuilt" with no source and no production record. | FAIL: provenance termination. Treated as foreign until proven otherwise. |

| section |
|---|
| Positive control |

| # | directive |
|---|---|
| 1 | A corpus fixture containing foreign-language text, explicitly identified as input to an Idol-written importer that preserves the input's laws and provenance, must NOT be flagged as foreign implementation. |
| 2 | The gate distinguishes `input` (read, identified, provenance-preserving) from `implementation` (executed as part of the toolchain). |
| 3 | If the positive control is flagged, the gate is over-broad and fails its own acceptance. |

| section |
|---|
| The verifier satisfies the requirement |

| # | directive |
|---|---|
| 1 | The gate implementation is Idol source, executed by the Idol toolchain. No Python certifier. No shell-script driver. No `gatecap` escapes in the verdict path. |
| 2 | Filesystem enumeration, provenance-chain walking, and control evaluation are Idol capabilities or named obligations under this same policy. |
| 3 | The gate's own dependency closure is subject to the gate: it must establish its own Idol source and chain, or carry its own obligation records. A gate that cannot pass itself does not run. |
| 4 | Bootstrap sequencing: while the toolchain is not yet Idol-only, the gate runs in **inventory mode** — it reports the complete obligation list and fails any claim of Idol-only completion. It does not block development. It blocks the completion claim. |
| 5 | The inventory-mode report is the working backlog: every OPEN obligation with its `next:` action, ordered by closure impact (how much of the toolchain the obligation blocks). |

| section |
|---|
| Transition from the licence census |

| # | directive |
|---|---|
| 1 | `scripts/census/foreign.id` (`zig build foreign-census`) is retained as the debt inventory. Its PASS/FAIL answers inventory completeness only. |
| 2 | The inventory PASS line must state: "inventory complete" — never "toolchain complete", "Idol-only", or any completion claim. |
| 3 | The obligation gate consumes the inventory as one input among graph facts. It does not inherit the inventory's verdict. |
| 4 | `build.zig` gains an `obligation-gate` step. It is red until the closure is Idol-only or every remaining member carries an open obligation with a next action. Red here means "obligations remain", not "violation" — the distinction is that the work is named and owned. |
