# Should the IR be Idol? — measured, and the answer relocates the problem

| # | directive |
|---|---|
| 1 | **The question:** if the semantic graph is already the most compact meaningful form, is DNIR a duplicate ontology that should be deleted? |

| # | directive |
|---|---|
| 1 | **The instinct is right and the target is right. |
| 2 | But DNIR is not the duplicate, and deleting it would not make the graph authoritative.** Measured at idol `5b5ef9dd`. |

| # | directive |
|---|---|

## §1 DNIR BARELY EXISTS AS AN IR

| # | directive |
|---|---|
| 1 | src/native/ir.zig 618 lines the actual IR (Op enum, Instr struct) src/dnir_lower.zig 9,946 lines the lowering PASS src/dnir_hardware.zig 318 lines |

| # | directive |
|---|---|
| 1 | **The IR is 618 lines.** It is not a parallel ontology by size — 16x smaller than the pass that writes it. |
| 2 | Deleting it removes a data structure, not an authority. |

## §2 THE SHADOW AUTHORITY IS THE AST, NOT THE IR

| # | directive |
|---|---|
| 1 | `dnir_lower.zig` references `ast.` **189 times** and `semantic_graph.` **73 times**, and — decisively — it DISPATCHES ON SYNTAX KINDS: |

| # | directive |
|---|---|
| 1 | .call 47 .method_call 31 .if_stmt 8 .num_for 7 .gen_for 6 .literal 4 .brk 2 versus .application 42 ApplicationFact 8 |

| # | directive |
|---|---|
| 1 | **Control flow is read from the AST.** `if_stmt`, `num_for`, `gen_for` and `brk` have no other source, because `semantic_graph.NodeKind` has **no iteration, recurrence, refinement, region or exit kind at all.** The graph cannot answer "what loop is this", so the lowering asks the tree. |

| # | directive |
|---|---|
| 1 | **Therefore deleting DNIR yields `AST -> machine` with no name for the middle.** The duplicate ontology is the AST surviving as a semantic authority — which is exactly what `law C0 §19` forbids and what SOURCE-CONTROL-ONE §11 pins at 0 and finds TOTAL. |

## §3 THE REAL DEFECT IS SMALL, AND IT IS IN THE IR'S CONTENT

| # | directive |
|---|---|
| 1 | A realization form is **legitimate and necessary**. |
| 2 | Ladder rungs 10-12 — ABI and register movement, instruction selection, microarchitecture — operate on facts the semantic graph MUST NOT hold, because representation independence is law. **Delete the realization form and register assignment migrates INTO the graph, which is strictly worse:** that is how a graph stops being representation-independent. |

| # | directive |
|---|---|
| 1 | So the test is not "how many forms" but **"does any form below the graph hold semantic identity?"** `native_ir.zig` FAILS it today: |

| # | directive |
|---|---|
| 1 | SEMANTIC relation 13 subject 4 descriptor 1 home 1 = 19 REALIZE reg 3 slot 3 frame 1 = 7 |

| # | directive |
|---|---|
| 1 | **The IR carries more semantic identity than realization facts.** That is the duplication — 19 mentions in 618 lines, not a 10,264-line subsystem. |

## §4 DOES ELIMINATING IT SERVE FTCFTW? — NOT DIRECTLY

| # | directive |
|---|---|
| 1 | **Eliminating a form is not a performance win. |
| 2 | Eliminating FACT LOSS is.** And every measured loss in this tree is at the graph/AST boundary, not at the IR: |

| # | directive |
|---|---|
| 1 | gen_for refused by every live backend 612 statements, 158 files, 52.8% of corpus `for` subject-first record result REFUSED (`checkedScalarResult`) subject-first mutual recursion REFUSED (declaration order) bootstrap spelling-lowered applications 36 spellings, no ApplicationFact break exit target rebuilt from an AST nesting stack |

| # | directive |
|---|---|
| 1 | None of those is caused by having an IR. |
| 2 | All are caused by a fact never reaching the lowering — or never existing in the graph to reach it. **A single form cannot lose facts at a boundary that does not exist, but the boundary losing them here is graph<->AST.** |

## §5 THE RULING

> **ONE SEMANTIC AUTHORITY — the graph. ONE REALIZATION FORM — holding ZERO
> semantic identity. And a falsifiable test: NO SEMANTIC FACT MAY BE
> RECONSTRUCTIBLE ONLY BELOW THE GRAPH.**

| # | directive |
|---|---|
| 1 | That is stronger than "delete DNIR" and weaker than "keep two ontologies". |
| 2 | It is also gateable: for each of `relation`, `subject`, `descriptor`, `home`, `world`, `applied`, either the graph answers it or the program is refused — the lowering may never be the only place it exists. |

| # | directive |
|---|---|
| 1 | **The executable order, and it is NOT "delete the IR first":** |

1. Give the graph what lowering currently gets from the AST — control regions,
   iteration, exact exit targets, world, applied identity. **Until then the AST
   cannot be demoted, and deleting the IR only hides the dependency.**
2. Move the 19 semantic mentions out of `native_ir.zig`. Small and tractable.
3. Re-point lowering at the graph, dispatch site by dispatch site, with the
   corpus differential as the gate. `.if_stmt`/`.num_for`/`.gen_for`/`.brk` are
   23 of the sites and are the ones that matter.
4. **Then** ask whether the residual realization form deserves a name. By that
   point the question answers itself, because what remains will hold nothing but
   registers, slots and frames — and that is not Idol, it is a machine.

| # | directive |
|---|---|
| 1 | **Step 4 is where "the IR is Idol" becomes true**, and it is true by subtraction rather than by deletion: not because the IR was removed, but because everything semantic left it. |
