# Reduced fixtures — executable blocker theorems

Each fixture is a minimized program preserving one exact first failure
(predicate-stable, floor-controlled; see `tools/reduce/idol`). Controls in
the same family prove causality. Families map to the handoffs in
`.agents/MOP_HANDOFFS.md`.

| Family | Fixture | Control | Theorem |
|---|---|---|---|
| F1 | `graph/f64.id` | `graph/ctrl.id` | typed host pointer + `mem.write_f64` refuses `unresolved-application-facts` from the graph; `write_i64` compiles — the missing fact is f64-application-specific |
| F3a | `global/ctrl.id` | — | module-global read refuses with the bare name |
| F3b | `global/write.id` | `global/ctrl.id` | written module-global refuses `global-init-not-constant:<name>` — a distinct fact from F3a |
| F4 | `view/minimal.id` | `view/slice.id` | `missing: view` tracks the relation SHAPE (pack param + if/else over a pack field), reported by name |
| F4R | `result/pack.id` | — | array-bearing pack identity refuses `application-result-abi` |
| F5 | `crash/corpus.id` | `crash/ctrl.id` | SELF-RECURSION crashes `publishApplicationResultAggregate` (2 lines); renamed call target gives a clean diagnostic |
| H5 | `link/probe.id` | — | cross-module application from an exe entry does not pull the callee's object (3 lines) |

F2 is deliberately absent: graph.id is line-irreducible at 112 lines —
the operand-abi fact is module-granularity, not local (see handoffs).

Verify any fixture: `idol compile <fixture> --emit obj -o /tmp/f.o` and
match the refusal; controls must compile or diagnose cleanly.
