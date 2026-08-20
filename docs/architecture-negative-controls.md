[~/x/idol/docs/architecture-negative-controls.md#1436]
1:# Architecture-negative controls (manifest)
2:
3:**Disposition:** agent/gate law — not semantic law. Authority chain:
4:`docs/spec/law.md` → `gaps/` → `evidence/` → this manifest.
5:
6:**Run:** `sh gate/architecture-negative.sh` (static + debt ratchets + companions).
7:**Roadmap:** `sh gate/architecture-roadmap.sh` (planned behavioral gates; informational).
8:
9:## Central overnight rule
10:
11:Every time a blocker disappears, ask **what authority you added**.
12:
13:- **Bad:** "the backend now recognizes another source/AST/storage pattern"
14:- **Good:** "the graph now knows an exact fact earlier and downstream code became simpler"
15:
16:## Review question (required before every commit)
17:
18:If I deleted all source spelling, AST shape, filesystem names, and host-local
19:variable names after resolution, would my new code still know enough to make this
20:decision? If no, the change is almost certainly at the wrong layer.
21:
22:---
23:
24:## Control inventory
25:
26:| Control | Intent | Status |
27:|---|---|---|
28:| **GRAPH-FACT-TRUST** | Lowering may not filter/correct authoritative application facts | debt ratchet (`@debt GRAPH-ARG-EXACT`) |
29:| **GRAPH-ARG-EXACT** | `graph.application.arguments` == resolved operands exactly | debt ratchet (goal: 0 filters) |
30:| **GRAPH-ONLY-REALIZATION** | Poison AST after graph closure; supported path still emits | planned behavioral |
31:| **GRAPH-ONLY-LOWERING** | No meaning recovery from AST after resolution | debt + planned |
32:| **RESOLUTION-PERMUTATION** | Reorder home/file enumeration → semantics unchanged | planned behavioral |
33:| **RESOLUTION-AMBIGUITY** / **AMBIGUITY-FAILS** | Equal candidates → explicit ambiguity | **live** (`gap-111-map-ambiguity.sh`) |
34:| **RESOLUTION-ORDER-INDEPENDENT** | Home order must not decide meaning | doc law + `@debt AMBIGUITY-FAILS` |
35:| **HOME-MOVE** | Move relation physically → application unchanged | planned behavioral |
36:| **MODULE-TOPOLOGY** | Path perturbation after ingress → graph identity unchanged | planned behavioral |
37:| **NO-HOME-SEMANTIC-PRIORITY** | Filesystem home is provenance, not dispatch | doc law + home-list debt |
38:| **NO-FIRST-WINS-SEMANTICS** | No "first home wins" comments or logic | **live** (static absent) |
39:| **NO-DNIR-AST-FILTER** | No `filterCheckedCallOperands` on supported path | debt ratchet (goal: 0) |
40:| **NO-NAME-RECORD-INFERENCE** | No `name.field` local scanning for record shape | debt ratchet (goal: 0) |
41:| **NO-DNIR-SECOND-TYPECHECK** | No `exprIsStr`-style semantic guessing in DNIR | debt ratchet |
| **NO-SOURCE-IO-BELOW-GRAPH** | DNIR must not read/lex/parse sibling source | **live** (static zero) |
| **DELIMITER-PROJECTION-LAW** | `[]` indexes; `()` is application only | **live** (`delimiter-projection-law.sh`) |
| **GRAPH-RECORD-RETURN-BARRIER** | No export-map record return when graph required | **live** (static) |
| **LINKAGE-DOES-NOT-DEFINE-MEANING** | Export names must not infer semantic return shape on graph path | **live** (barrier + debt) |
| **NO-SOURCE-IO-BELOW-GRAPH** | DNIR must not read/lex/parse sibling source | **live** (static zero) |
| **DELIMITER-PROJECTION-LAW** | `[]` indexes; `()` is application only | **live** (`delimiter-projection-law.sh`) |
| **GRAPH-RECORD-RETURN-BARRIER** | No export-map record return when graph required | **live** (static) |
| **LINKAGE-DOES-NOT-DEFINE-MEANING** | Export names must not infer semantic return shape on graph path | **live** (barrier + debt) |
42:| **REPRESENTATION-HISTORY** | Same semantic value via exploded vs aggregate → same legal realizations | planned behavioral |
43:| **ZERO-TEXT-SEMANTICS** | Rename locals after resolution → machine result unchanged | planned behavioral |
44:| **EFFECT-NO-RESULT** | Result unused + effect demanded → application remains | planned behavioral |
45:| **RESULT-NO-EFFECT** | Result unused + pure → application may disappear | planned behavioral |
46:| **FORMAT-FIXPOINT** | canonical → fmt → parse → fmt fixed point; no retired faces | planned behavioral |
47:| **B-USES-REAL-COMPOSITION** | Monolith probe cannot satisfy compiler-B acceptance | **live** (monolith label) |
48:| **MONOLITH-PROBE-LABELED** | `monolith.id` is capability probe only | **live** (static) |
49:| **SCOREBOARD-HISTORICAL-LABEL** | Static scoreboard not live counts | **live** (idol-native banner) |
50:| **CANONICAL-SOURCE-DEBT** | Every `lib/compiler/**` construct classified | **live** (projection doc) |
51:| **IDOL-NATIVE-MEASURE-ONLY** | Native repo measures/falsifies; idol owns meaning | doc law |
52:
53:See `docs/AGENT_ALIGNMENT.md` § Systemic misunderstandings for the full 30-point audit.