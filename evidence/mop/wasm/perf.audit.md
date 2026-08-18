# Performance audit of the ingest itself — graph facts, fold space, opt inventory

Measured on the compiler's own graph of tools/wasm/ingest.id
(117 candidates, 99 published, 17 bootstrap, 1 blocking).

## Where the work is

main = 67 applications (the walk loops), appfact = 17, slebsign = 5.
The LEB readers (ulebval/ulebafter/slebend/slebsign) dominate inner
loops — consistent with the measured 2x read amplification.

## Fold space (exploit-4 in miniature — measured, not assumed)

60 of 99 applications are PURE (effect: none) — fold candidates. Their
relations: 19 (17x), 4 (14x), 1 (11x), 22 (6x). Every one currently
executes at runtime. With whole-relation folding (pure + exact
operands + closed + completing → exact result), the pure subset of the
ingest collapses at compile time. That is the compiler-lane exploit,
but the ingest's own graph DEMONSTRATES the input: exact fold
candidates enumerated by the graph itself.

## Witness cards: 99 of 99 unknown

No application carries a proof witness. This is the single largest
fact hole in the ingest's own graph — and the prerequisite for every
higher rung (bounds checks, devirtualization, representation choice).

## Instruction-minimization inventory (the ingest, measured)

1. LEB read amplification: ulebval + ulebafter each walk the same
   bytes (2x). Fix: single-walk returning value+end. Blocked by:
   first-class pack returns. THE deletion condition for the subset.
2. byteat O(1) but hex-pair decode re-runs hexdigit twice per byte —
   foldable constant table (blocked by: module globals, H8-adjacent).
3. immclass deep else-chain: 8 comparisons worst case per op — a
   dispatch on ranges compiles to a jump table when the compiler
   publishes switch facts (currently refinement chains).
4. appfact string building: head/tail concatenated per record — 17K
   records x 2 concat = 34K allocations. Fix: emit parts separately
   (stdout:write x3) or the pointer+extent view (directive priority 2).
5. The ?? check in binname: reached 393x per fib run — map the exact
   op bounds (sign-ext/conversions/floats) to delete the fallthrough.

## IPC/streaming inventory

1. Records to stdout as JSONL: parseable by any consumer (jq, python,
   the graph builder) — current path.
2. MCP streaming: native.id's newline JSON-RPC pattern carries the
   same records with ZERO format change — the idol MCP server face.
3. Compiler-internal: the record stream consumed at graph-build time
   (no serialization, no parse) — the realization-lane integration.
4. Provenance byte offsets in every record: incremental re-ingest
   (edit → local invalidation) — exploit-10 input, already live.
