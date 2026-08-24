# Architecture negative controls

**Status:** agent/projection documentation — not language law.

These controls catch architectural drift that local fixture greens hide. They
complement capability gates (`gate/selfhost.sh`, `gate/gap-*.sh`); they do not
replace them.

Run:

```sh
sh gate/architecture-negative.sh      # static anti-regression scans
sh gate/architecture-companion.sh     # runtime probes where implemented
```

## Central overnight rule

Every time a blocker disappears, ask **what authority you added**:

| Answer | Verdict |
|---|---|
| "The backend now recognizes another source/AST/storage pattern" | **Regression** — stop |
| "The graph now knows an exact fact earlier and downstream code became simpler" | **Progress** — continue |

Successful traversal of today's pipeline is **not** progress. The goal is to
**remove the need** for large parts of that pipeline.

## Control catalog (gates)

| ID | Intent | Enforcement | Status |
|---|---|---|---|
| **NO-SOURCE-IO-BELOW-GRAPH** | Post-graph lowering must not read/lex/parse sibling sources | Static ban on sibling loaders + `readFile*` / `parseFile` / `Lexer.init` in `dnir_lower.zig` | **enforced** |
| **GRAPH-RECORD-RETURN-ONE** | Graph-required paths must not fall back to export-name maps | `tryAssignRecordCallFromExportMap` returns false when `require_graph_facts` | **enforced** — static guard |
| **LINKAGE-DOES-NOT-DEFINE-MEANING** | Export/ABI symbols must not infer semantic result shape | Export map only when `!require_graph_facts`; graph publishes pack/descriptor facts | **partial** — guard present; pack facts still debt |
| **GRAPH-FACT-TRUST** | Lowering may not filter authoritative application facts | `verifyCheckedApplicationOperandPacks` in graph lift; no AST operand recovery in DNIR | **enforced** — static ban on `filter*Operands` / `callValueForApplication` |
| **GRAPH-ARG-EXACT** | Application operand packs = exactly resolved operands | Graph lift validation + `examples/bind_save_state.id` companion | **enforced** (lift); direct lowering still separate |
| **NO-DNIR-AST-FILTER** | Supported-path lowering must not recover call operands from AST | Static ban on `filterCheckedCallOperands` / `callValueForApplication` | **enforced** |
| **NO-NAME-RECORD-INFERENCE** | Record/ABI selection must not depend on `"name.field"` local keys | Static ban on `expandableRecordForName` | **enforced** — graph operand lookup; field slots still debt |
| **NO-RECORD-HISTORY-INFERENCE** | Same semantic structured value must not depend on prior field explosion | Static ban on `recordFieldsPresent` | **debt** — fails until pack facts authoritative |
| **NO-BACKEND-TYPE-GUESS** | Lowering must not re-derive string/record shape (`exprIsStr`, etc.) | Static debt marker on `fn exprIsStr` in `dnir_lower.zig` | **debt** — documented, not yet blocking |
| **RESOLUTION-ORDER-INDEPENDENT** | Reordering home declaration must not change meaning | Sema collects all matches; no first-wins; sorted `foreign_module_homes` | **enforced** — static + companion |
| **AMBIGUITY-FAILS** | Equal admissible relations → explicit ambiguity | Sema error + companion negative probe | **enforced** |
| **NO-HOME-SEMANTIC-PRIORITY** | Home placement is provenance, not dispatch order | Static ban on first-wins home lists | **enforced** |
| **NO-PROTO-CLASS-HOMES** | `iter`/`table`/`string`/`math` must not become trait registries | Facts/laws over subjects, not hard-coded home→method maps | **debt** — conformance still host-coded |
| **GRAPH-ONLY-REALIZATION** | Supported path emits from graph facts alone; AST poisoned after closure | Future companion + lowering audit | **planned** |
| **RESOLUTION-PERMUTATION** | Reorder home/file enumeration → semantics unchanged | Static sorted-home doc + unit test + AMBIGUITY-FAILS companion | **enforced** |
| **RESOLUTION-AMBIGUITY** | Equal admissible relations → explicit ambiguity | Sema error + companion negative probe | **enforced** (alias of AMBIGUITY-FAILS) |
| **HOME-MOVE** | Move relation physically → semantic application unchanged | Companion probe | **planned** |
| **ZERO-TEXT-SEMANTICS** | Rename locals after resolution → machine unchanged | Companion probe | **planned** |
| **EFFECT-NO-RESULT** | Result unused + effect demanded → application remains | Semantic demand facts + companion | **planned** |
| **RESULT-NO-EFFECT** | Result unused + proven pure → application may disappear | Demand/effect separation | **planned** |
| **VOID-IS-EMPTY-PACK** | No semantic "void function" kingdom — empty result pack | Realization chooses control edge | **planned** |
| **FORMAT-FIXPOINT** | canonical → fmt → parse/resolve → fmt fixed point; no retired faces | Companion: `idol fmt` must not emit `fun`/`end`/`then` | **enforced** (companion on `examples/bind_concat.id`) |
| **RETIRED-TYPE-ALIAS-PROJECTION** | No `typedecl`, `(type …)` wrappers, or `alias` keyword in lib/compiler | Static ban in `gate/architecture-negative.sh` | **enforced** |
| **CHECK-NOT-DIRECT-ADMISSION** | `idol check` success must not imply direct-native reach | Companion: sema-green probe may still refuse at `idol run` | **enforced (probe)** — documents debt until check includes direct path |
| **MODULE-TOPOLOGY** | Physical path perturbation after ingress → graph identity unchanged | Companion + negative control doc | **planned** |
| **MONOLITH-PROBE-ONLY** | `lib/compiler/monolith.id` is capability probe, not compiler B | Header marker + agent mandate | **enforced** |
| **B-USES-REAL-COMPOSITION** | Monolith symbol count does not satisfy compiler-B acceptance | Agent mandate; real homes/bindings/worlds required | **enforced (doc)** |
| **REPORT-PROVENANCE** | Durable reports label CURRENT PROJECTION vs HISTORICAL EVIDENCE | Agent routing; no static score copying | **enforced (doc)** |
| **CANONICAL-SOURCE-DEBT** | lib/compiler constructs tagged canonical / migratable / debt | `docs/projections/canonical-source-debt.md` | **partial** |
| **QUOTE-BOUNDARY-PRESERVE** | Quote/text/byte facts must survive to all lowering paths | GAP-145 audit; DNIR must not collapse to `.str` alone | **debt** |
| **STRUCTURED-REFUSAL** | Refusals name semantic entity, fact, producer, consumer, category | Target diagnostic shape | **planned** |
| **idol-native-MEASURES-ONLY** | Native repo may measure/falsify; idol owns meaning | AUTHORITY.md + agent mandate | **enforced (doc)** |

## Systemic misunderstandings → required correction

Map agent mistakes to the gate or doc that falsifies them:

1. **Module composition** — ingress topology → home identities → binding facts; no import/loader resurrection. See **MODULE-TOPOLOGY**, **B-USES-REAL-COMPOSITION**.
2. **Self-host corpus oracle** — green ≠ canonical. Three states per construct. See **CANONICAL-SOURCE-DEBT**.
3. **Formatter canonicality** — fmt follows graph/law, not the reverse. See **FORMAT-FIXPOINT**.
4. **Binding** — occurrence ids + defining semantic ids, not `set[str]` scans. See **ZERO-TEXT-SEMANTICS**, bind.id debt tags.
5. **Resolver ordering** — enumeration order never resolves ambiguity. See **RESOLUTION-ORDER-INDEPENDENT**, **AMBIGUITY-FAILS**.
6. **Proto-class homes** — capabilities from facts, not home name registries. See **NO-PROTO-CLASS-HOMES**.
7. **Conformance decomposition** — `.sequence`/`.text`/`.numeric` are host categories, not semantic identities. Infer compositionally.
8. **Global state** — demand/const/purity facts first; "global" is not a permanent machine category.
9. **Effect-only calls** — result demand ≠ application demand. See **EFFECT-NO-RESULT**.
10. **Void relations** — empty result pack, not backend special case. See **VOID-IS-EMPTY-PACK**.
11. **String concat** — boundary contraction before native concat opcode. See bind.id concat blocker notes.
12. **str privilege** — text/byte law; C string is physical realization only. See **QUOTE-BOUNDARY-PRESERVE**, GAP-145.
13. **Quote identity boundaries** — find every place early law disappears. See **QUOTE-BOUNDARY-PRESERVE**.
14. **Direct backend AST knowledge** — presumptively reject new AST helpers in lowering. See **GRAPH-ONLY-REALIZATION**.
15. **Backend as second type checker** — descriptor facts must precede lowering. See **NO-BACKEND-TYPE-GUESS**.
16. **recordFieldsPresent** — representation history ≠ semantic structure. See **NO-RECORD-HISTORY-INFERENCE**.
17. **Fixed ABI thresholds** — machine limits → candidate realization, not semantic invalidity.
18. **Refusal conflation** — semantic-invalid vs realization-unavailable vs candidate-too-expensive. See **STRUCTURED-REFUSAL**.
19. **check fail-open** — exit 0 ≠ validity unless gate proves path. Never trust process status alone.
20. **Implementation-coupled diagnostics** — DNB text parsing is debt; target structured outcomes.
21. **Native gates as shell ontology** — A–E must index one graph, not five shell interpretations.
22. **idol-native second architecture** — measure/falsify only. See AUTHORITY.md.
23. **Historical documents** — HISTORICAL header; live counts from executable ledgers only.
24. **Monolith hiding composition** — probe only. See **MONOLITH-PROBE-ONLY**.
25. **Cross-home resolution law** — fix generic law before expanding method surface.
26. **Sequence basis optimizer info** — `map`/`filter`/`take` must carry element/shape facts (GAP-111).
27. **Chain syntax** — must expose graph composition, not pretty surface only.
28. **Source density** — information density, not golf; named intermediates when they mark identity/effect.
29. **Accidental host names** — bind.id `prev_kind`/`refs`/`bound` are transcription debt.
30. **Bootstrap bridge death** — every bridge needs owner/replacement/deletion condition.

## Semantic family mapping (stop fixing symptoms)

Map blockers upward — one semantic family should retire many DNB cases:

- **Receiver descriptor propagation** → byte/len/sub/field receivers
- **Sequence relation resolution** → map/filter/take/iter/table ambiguity
- **Pack / structured application** → constructors, record assigns, unused results
- **Effect + demand** → void relations, diagnostics, concat sinks
- **Representation + place** → globals, strings, records

## Self-host score interpretation

Each ledger row needs:

1. **Physical reach** — does direct lowering run?
2. **Authority quality** — what graph fact became authoritative?

Green without (2) is **green and wrong** (historical precedent: `symbol.id`).

## Related

- `.agents/ARCHITECTURE_INJECTION.md` — agent orientation
- `docs/AGENT_ALIGNMENT.md` — priority router
- `docs/projections/canonical-source-debt.md` — compiler-source construct states
- `gate/architecture-negative.sh` — mechanical checks (this repo)
- `../idol-native/gate/architecture-negative.sh` — delegates here (if present)