[/Volumes/d 1/x/idol/docs/architecture-negative-controls.md#E5D4]
1:# Architecture negative controls
2:
3:**Status:** agent/projection documentation — not language law.
4:
5:These controls catch architectural drift that local fixture greens hide. They
6:complement capability gates (`gate/selfhost.sh`, `gate/gap-*.sh`); they do not
7:replace them.
8:
9:Run:
10:
11:```sh
12:sh gate/architecture-negative.sh      # static anti-regression scans
13:sh gate/architecture-companion.sh     # runtime probes where implemented
14:```
15:
16:## Central overnight rule
17:
18:Every time a blocker disappears, ask **what authority you added**:
19:
20:| Answer | Verdict |
21:|---|---|
22:| "The backend now recognizes another source/AST/storage pattern" | **Regression** — stop |
23:| "The graph now knows an exact fact earlier and downstream code became simpler" | **Progress** — continue |
24:
25:Successful traversal of today's pipeline is **not** progress. The goal is to
26:**remove the need** for large parts of that pipeline.
27:
28:## Control catalog (gates)
29:
30:| ID | Intent | Enforcement | Status |
31:|---|---|---|---|
32:| **NO-SOURCE-IO-BELOW-GRAPH** | Post-graph lowering must not read/lex/parse sibling sources | Static ban on sibling loaders + `readFile*` / `parseFile` / `Lexer.init` in `dnir_lower.zig` | **enforced** |
| **GRAPH-RECORD-RETURN-ONE** | Graph-required paths must not fall back to export-name maps | `tryAssignRecordCallFromExportMap` returns false when `require_graph_facts` | **enforced** — static guard |
| **LINKAGE-DOES-NOT-DEFINE-MEANING** | Export/ABI symbols must not infer semantic result shape | Export map only when `!require_graph_facts`; graph publishes pack/descriptor facts | **partial** — guard present; pack facts still debt |
| **GRAPH-FACT-TRUST** | Lowering may not filter authoritative application facts | `verifyCheckedApplicationOperandPacks` in graph lift; no AST operand recovery in DNIR | **enforced** — static ban on `filter*Operands` / `callValueForApplication` |
33:| **GRAPH-ARG-EXACT** | Application operand packs = exactly resolved operands | Graph lift validation + `examples/bind_save_state.id` companion | **enforced** (lift); direct lowering still separate |
34:| **NO-DNIR-AST-FILTER** | Supported-path lowering must not recover call operands from AST | Static ban on `filterCheckedCallOperands` / `callValueForApplication` | **enforced** |
35:| **NO-NAME-RECORD-INFERENCE** | Record/ABI selection must not depend on `"name.field"` local keys | Static ban on `expandableRecordForName` | **enforced** — graph operand lookup; field slots still debt |
36:| **NO-RECORD-HISTORY-INFERENCE** | Same semantic structured value must not depend on prior field explosion | Static ban on `recordFieldsPresent` | **debt** — fails until pack facts authoritative |
37:| **NO-BACKEND-TYPE-GUESS** | Lowering must not re-derive string/record shape (`exprIsStr`, etc.) | Static debt marker on `fn exprIsStr` in `dnir_lower.zig` | **debt** — documented, not yet blocking |
38:| **RESOLUTION-ORDER-INDEPENDENT** | Reordering home declaration must not change meaning | Sema collects all matches; no first-wins; sorted `foreign_module_homes` | **enforced** — static + companion |
39:| **AMBIGUITY-FAILS** | Equal admissible relations → explicit ambiguity | Sema error + companion negative probe | **enforced** |
40:| **NO-HOME-SEMANTIC-PRIORITY** | Home placement is provenance, not dispatch order | Static ban on first-wins home lists | **enforced** |
41:| **NO-PROTO-CLASS-HOMES** | `iter`/`table`/`string`/`math` must not become trait registries | Facts/laws over subjects, not hard-coded home→method maps | **debt** — conformance still host-coded |
42:| **GRAPH-ONLY-REALIZATION** | Supported path emits from graph facts alone; AST poisoned after closure | Future companion + lowering audit | **planned** |
43:| **RESOLUTION-PERMUTATION** | Reorder home/file enumeration → semantics unchanged | Static sorted-home doc + unit test + AMBIGUITY-FAILS companion | **enforced** |
44:| **RESOLUTION-AMBIGUITY** | Equal admissible relations → explicit ambiguity | Sema error + companion negative probe | **enforced** (alias of AMBIGUITY-FAILS) |
45:| **HOME-MOVE** | Move relation physically → semantic application unchanged | Companion probe | **planned** |
46:| **ZERO-TEXT-SEMANTICS** | Rename locals after resolution → machine unchanged | Companion probe | **planned** |
47:| **EFFECT-NO-RESULT** | Result unused + effect demanded → application remains | Semantic demand facts + companion | **planned** |
48:| **RESULT-NO-EFFECT** | Result unused + proven pure → application may disappear | Demand/effect separation | **planned** |
49:| **VOID-IS-EMPTY-PACK** | No semantic "void function" kingdom — empty result pack | Realization chooses control edge | **planned** |
50:| **FORMAT-FIXPOINT** | canonical → fmt → parse/resolve → fmt fixed point; no retired faces | Companion: `idol fmt` must not emit `fun`/`end`/`then` | **enforced** (companion on `examples/bind_concat.id`) |
51:| **RETIRED-TYPE-ALIAS-PROJECTION** | No `typedecl`, `(type …)` wrappers, or `alias` keyword in lib/compiler | Static ban in `gate/architecture-negative.sh` | **enforced** |
52:| **CHECK-NOT-DIRECT-ADMISSION** | `idol check` success must not imply direct-native reach | Companion: sema-green probe may still refuse at `idol run` | **enforced (probe)** — documents debt until check includes direct path |
53:| **MODULE-TOPOLOGY** | Physical path perturbation after ingress → graph identity unchanged | Companion + negative control doc | **planned** |
54:| **MONOLITH-PROBE-ONLY** | `lib/compiler/monolith.id` is capability probe, not compiler B | Header marker + agent mandate | **enforced** |
55:| **B-USES-REAL-COMPOSITION** | Monolith symbol count does not satisfy compiler-B acceptance | Agent mandate; real homes/bindings/worlds required | **enforced (doc)** |
56:| **REPORT-PROVENANCE** | Durable reports label CURRENT PROJECTION vs HISTORICAL EVIDENCE | Agent routing; no static score copying | **enforced (doc)** |
57:| **CANONICAL-SOURCE-DEBT** | lib/compiler constructs tagged canonical / migratable / debt | `docs/projections/canonical-source-debt.md` | **partial** |
58:| **QUOTE-BOUNDARY-PRESERVE** | Quote/text/byte facts must survive to all lowering paths | GAP-145 audit; DNIR must not collapse to `.str` alone | **debt** |
59:| **STRUCTURED-REFUSAL** | Refusals name semantic entity, fact, producer, consumer, category | Target diagnostic shape | **planned** |
60:| **idol-native-MEASURES-ONLY** | Native repo may measure/falsify; idol owns meaning | AUTHORITY.md + agent mandate | **enforced (doc)** |
61:
62:## Systemic misunderstandings → required correction
63:
64:Map agent mistakes to the gate or doc that falsifies them:
65:
66:1. **Module composition** — ingress topology → home identities → binding facts; no import/loader resurrection. See **MODULE-TOPOLOGY**, **B-USES-REAL-COMPOSITION**.
67:2. **Self-host corpus oracle** — green ≠ canonical. Three states per construct. See **CANONICAL-SOURCE-DEBT**.
68:3. **Formatter canonicality** — fmt follows graph/law, not the reverse. See **FORMAT-FIXPOINT**.
69:4. **Binding** — occurrence ids + defining semantic ids, not `set[str]` scans. See **ZERO-TEXT-SEMANTICS**, bind.id debt tags.
70:5. **Resolver ordering** — enumeration order never resolves ambiguity. See **RESOLUTION-ORDER-INDEPENDENT**, **AMBIGUITY-FAILS**.
71:6. **Proto-class homes** — capabilities from facts, not home name registries. See **NO-PROTO-CLASS-HOMES**.
72:7. **Conformance decomposition** — `.sequence`/`.text`/`.numeric` are host categories, not semantic identities. Infer compositionally.
73:8. **Global state** — demand/const/purity facts first; "global" is not a permanent machine category.
74:9. **Effect-only calls** — result demand ≠ application demand. See **EFFECT-NO-RESULT**.
75:10. **Void relations** — empty result pack, not backend special case. See **VOID-IS-EMPTY-PACK**.
76:11. **String concat** — boundary contraction before native concat opcode. See bind.id concat blocker notes.
77:12. **str privilege** — text/byte law; C string is physical realization only. See **QUOTE-BOUNDARY-PRESERVE**, GAP-145.
78:13. **Quote identity boundaries** — find every place early law disappears. See **QUOTE-BOUNDARY-PRESERVE**.
79:14. **Direct backend AST knowledge** — presumptively reject new AST helpers in lowering. See **GRAPH-ONLY-REALIZATION**.
80:15. **Backend as second type checker** — descriptor facts must precede lowering. See **NO-BACKEND-TYPE-GUESS**.
81:16. **recordFieldsPresent** — representation history ≠ semantic structure. See **NO-RECORD-HISTORY-INFERENCE**.
82:17. **Fixed ABI thresholds** — machine limits → candidate realization, not semantic invalidity.
83:18. **Refusal conflation** — semantic-invalid vs realization-unavailable vs candidate-too-expensive. See **STRUCTURED-REFUSAL**.
84:19. **check fail-open** — exit 0 ≠ validity unless gate proves path. Never trust process status alone.
85:20. **Implementation-coupled diagnostics** — DNB text parsing is debt; target structured outcomes.
86:21. **Native gates as shell ontology** — A–E must index one graph, not five shell interpretations.
87:22. **idol-native second architecture** — measure/falsify only. See AUTHORITY.md.
88:23. **Historical documents** — HISTORICAL header; live counts from executable ledgers only.
89:24. **Monolith hiding composition** — probe only. See **MONOLITH-PROBE-ONLY**.
90:25. **Cross-home resolution law** — fix generic law before expanding method surface.
91:26. **Sequence basis optimizer info** — `map`/`filter`/`take` must carry element/shape facts (GAP-111).
92:27. **Chain syntax** — must expose graph composition, not pretty surface only.
93:28. **Source density** — information density, not golf; named intermediates when they mark identity/effect.
94:29. **Accidental host names** — bind.id `prev_kind`/`refs`/`bound` are transcription debt.
95:30. **Bootstrap bridge death** — every bridge needs owner/replacement/deletion condition.
96:
97:## Semantic family mapping (stop fixing symptoms)
98:
99:Map blockers upward — one semantic family should retire many DNB cases:
100:
101:- **Receiver descriptor propagation** → byte/len/sub/field receivers
102:- **Sequence relation resolution** → map/filter/take/iter/table ambiguity
103:- **Pack / structured application** → constructors, record assigns, unused results
104:- **Effect + demand** → void relations, diagnostics, concat sinks
105:- **Representation + place** → globals, strings, records
106:
107:## Self-host score interpretation
108:
109:Each ledger row needs:
110:
111:1. **Physical reach** — does direct lowering run?
112:2. **Authority quality** — what graph fact became authoritative?
113:
114:Green without (2) is **green and wrong** (historical precedent: `symbol.id`).
115:
116:## Related
117:
118:- `.agents/ARCHITECTURE_INJECTION.md` — agent orientation
119:- `docs/AGENT_ALIGNMENT.md` — priority router
120:- `docs/projections/canonical-source-debt.md` — compiler-source construct states
121:- `gate/architecture-negative.sh` — mechanical checks (this repo)
122:- `../idol-native/gate/architecture-negative.sh` — delegates here (if present)