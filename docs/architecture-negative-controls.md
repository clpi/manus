# Architecture-negative controls (manifest)

**Disposition:** agent/gate law — not semantic law. Authority chain:
`docs/spec/law.md` → `gaps/` → `evidence/` → this manifest.

**Run:** `sh gate/architecture-negative.sh` (static + debt ratchets + companions).
**Roadmap:** `sh gate/architecture-roadmap.sh` (planned behavioral gates; informational).

## Central overnight rule

Every time a blocker disappears, ask **what authority you added**.

- **Bad:** "the backend now recognizes another source/AST/storage pattern"
- **Good:** "the graph now knows an exact fact earlier and downstream code became simpler"

## Review question (required before every commit)

If I deleted all source spelling, AST shape, filesystem names, and host-local
variable names after resolution, would my new code still know enough to make this
decision? If no, the change is almost certainly at the wrong layer.

---

## Control inventory

| Control | Intent | Status |
|---|---|---|
| **GRAPH-FACT-TRUST** | Lowering may not filter/correct authoritative application facts | debt ratchet (`@debt GRAPH-ARG-EXACT`) |
| **GRAPH-ARG-EXACT** | `graph.application.arguments` == resolved operands exactly | debt ratchet (goal: 0 filters) |
| **GRAPH-ONLY-REALIZATION** | Poison AST after graph closure; supported path still emits | planned behavioral |
| **GRAPH-ONLY-LOWERING** | No meaning recovery from AST after resolution | debt + planned |
| **RESOLUTION-PERMUTATION** | Reorder home/file enumeration → semantics unchanged | planned behavioral |
| **RESOLUTION-AMBIGUITY** / **AMBIGUITY-FAILS** | Equal candidates → explicit ambiguity | **live** (`gap-111-map-ambiguity.sh`) |
| **RESOLUTION-ORDER-INDEPENDENT** | Home order must not decide meaning | doc law + `@debt AMBIGUITY-FAILS` |
| **HOME-MOVE** | Move relation physically → application unchanged | planned behavioral |
| **MODULE-TOPOLOGY** | Path perturbation after ingress → graph identity unchanged | planned behavioral |
| **NO-HOME-SEMANTIC-PRIORITY** | Filesystem home is provenance, not dispatch | doc law + home-list debt |
| **NO-FIRST-WINS-SEMANTICS** | No "first home wins" comments or logic | **live** (static absent) |
| **NO-DNIR-AST-FILTER** | No `filterCheckedCallOperands` on supported path | debt ratchet (goal: 0) |
| **NO-NAME-RECORD-INFERENCE** | No `name.field` local scanning for record shape | debt ratchet (goal: 0) |
| **NO-DNIR-SECOND-TYPECHECK** | No `exprIsStr`-style semantic guessing in DNIR | debt ratchet |
| **REPRESENTATION-HISTORY** | Same semantic value via exploded vs aggregate → same legal realizations | planned behavioral |
| **ZERO-TEXT-SEMANTICS** | Rename locals after resolution → machine result unchanged | planned behavioral |
| **EFFECT-NO-RESULT** | Result unused + effect demanded → application remains | planned behavioral |
| **RESULT-NO-EFFECT** | Result unused + pure → application may disappear | planned behavioral |
| **FORMAT-FIXPOINT** | canonical → fmt → parse → fmt fixed point; no retired faces | planned behavioral |
| **B-USES-REAL-COMPOSITION** | Monolith probe cannot satisfy compiler-B acceptance | **live** (monolith label) |
| **MONOLITH-PROBE-LABELED** | `monolith.id` is capability probe only | **live** (static) |
| **SCOREBOARD-HISTORICAL-LABEL** | Static scoreboard not live counts | **live** (idol-native banner) |
| **CANONICAL-SOURCE-DEBT** | Every `lib/compiler/**` construct classified | **live** (projection doc) |
| **IDOL-NATIVE-MEASURE-ONLY** | Native repo measures/falsifies; idol owns meaning | doc law |

See `docs/AGENT_ALIGNMENT.md` § Systemic misunderstandings for the full 30-point audit.
