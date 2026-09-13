| field | value |
|---|---|
| title | Idol MCP Tool Discovery |

| # | directive |
|---|---|
| 1 | This file intentionally contains no static tool census or copied schemas. |
| 2 | Discover the exact current surface through MCP `tools/list`; validate it with the locked `mcp-gate`. |

| # | directive |
|---|---|
| 1 | The current project server exposes exactly the manifest-gated orientation operations `status`, `head`, `orient`, plus the GAP-120 `concept` tool whose production contract is held by `tools/concept/tool.sh` and `gate/mcp.sh`. |
| 2 | The sibling `idol-native` server owns its separately gated compiler and LSP queries. |
| 3 | There are no `duo_*` aliases and no hidden benchmark, claim, build, gap, or zls tools. |

| # | directive |
|---|---|
| 1 | `concept` is not a separate command: it is the served arm of the produced concept finding. `idol` makes `idol explain` available as a CLI; the MCP `concept` tool is the same projection exposed as a tool. |
| 2 | Its input schema is `{"file": "<subject .id>"}`; its output is the rendered verdict (REFUSED with the produced reason or HELD one concept) carried as `result.content [0].text` exactly as `gate/mcp.sh` holds for `tools/concept/tool.sh`. |

| # | directive |
|---|---|
| 1 | Claims, gap reservations, and locked execution are explicit repository commands. |
| 2 | Do not reintroduce them through raw JSON substring dispatch or model their outcomes as successful text payloads. |

| # | directive |
|---|---|
| 1 | MCP does not own semantics. |
| 2 | It projects graph identity, facts, demand, realization, provenance, evidence, and current repository state. |
| 3 | It must fail closed when a projection cannot be produced. |

| # | directive |
|---|---|
| 1 | No tool or example may teach universal namespace dispatch as native meaning. |
| 2 | Package location is provenance, relations are identity, subjects orient application, worlds grant authority, and realization selects physical implementation with zero runtime catalog obligation for sealed programs. |

| # | directive |
|---|---|
| 1 | The `world` tool binds one request to its actual execution world: `tools/mcp/world.id` via `tools/mcp/native.id` dispatch. |
| 2 | Input schema is `{"subject": "concept|sibling", "file": "<subject .id>"}`; output is `result.content [0].text` carrying the world-bound verdict or structured refusal, held by `gate/mcp-world.sh`. |
| 3 | World identity is launcher-observed at server start: `IDOL_WORLD_BIN`, `binhash` (SHA-256), `revision` (git HEAD), sidecar `<bin>.buildid`; the launcher `bin/idol-main-mcp.sh` is the trust root. |
| 4 | Refusals carry `reason`, `next`, `producer`, `not-performed`; no verdict is emitted when any face disagrees or the world cannot be bound. |

| # | directive |
|---|---|
| 1 | The `frontier` tool queries the semantic frontier (GAP-181): `tools/mcp/frontier.id` via `tools/mcp/native.id` dispatch. |
| 2 | Input schema is `{"file": "<subject .id>", "region": "<optional>"}`; output is `result.content [0].text` carrying known/unknown facts, blocker counts, highest value-of-information, and the acquire/decline decision, held by `gate/mcp-frontier.sh`. |
| 3 | Value-of-information is `payoff_cents - acquisition_cost_cents`; the tool recommends the cheapest acquisition with positive VoI or `decline`/`nothing-to-learn`. |


| # | directive |
|---|---|
| 1 | The `contrast` tool turns unresolved intent into a minimal behavioral question: `tools/mcp/contrast.id` via `tools/mcp/native.id` dispatch, held by `gate/mcp-contrast.sh`. |
| 2 | Question-mode input is `{"file": "<subject .id>", "ambiguity": {"kind": "tiebreak", "region": "<region>", "candidates": ["keep-first", "keep-last", "report-conflict"]}}`; answer-mode input is `{"file": "<subject .id>", "answer": {"question_id": "<hex>", "candidate": "<name>", "candidates": [...], "region": "<region>", "kind": "tiebreak"}}`; output is `result.content [0].text`. |
| 3 | The tool is stateless: `question_id` is the SHA-256 of `subject_hash|region|kind|candidates`, recomputed on answer; a mismatch is the `subject-changed` refusal naming re-derivation as the next action. |
| 4 | `unsupported-ambiguity` (any kind but `tiebreak`) is a tool limitation with next "supply kind tiebreak", not a user question; unreadable subjects and hash failures are refusals, never questions. |

| # | directive |
|---|---|
| 1 | The `preview` tool produces checked semantic-change proposals for projection edits: `tools/mcp/preview.id` via `tools/mcp/native.id` dispatch, held by `gate/mcp-preview.sh`. |
| 2 | Edit-mode input is `{"file": "<subject .id>", "projection": "frontier", "edit": {"kind": "acquire", "unknown": "<stable-id>", "decision": "acquire\|decline"}}`; identify-mode input is `{"file": "<subject .id>", "projection": "concept", "edit": {"kind": "identify", "a": "<rowkey>", "b": "<rowkey>"}}`; output is `result.content [0].text`. |
| 3 | Acquire proposals re-derive the frontier and refuse `projection-stale` when the unknown is gone; identify proposals require explain/graph face agreement and emit `ambiguous` with differing facets and explicit options, or the `unknown-concept` / `contradictory` / `face-disagreement` refusals. |
| 4 | Every proposal carries `checks`, `affected_region`, `voi_basis`, and `provenance` (subject SHA-256, world binary hash, revision); refusals carry `reason`, `next`, `producer`, `not-performed`. |
