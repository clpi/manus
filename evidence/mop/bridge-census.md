# Bridge census — measured 2026-08-17 (GLM-C)

Against bridge_census.md (2026-08-14) and bridge_audit.md at HEAD ed3cb305.

## Verdict: records current; no drift found

- All 6 documented .zig bridges exist with live consumers:
  foreign_adapter (5), host_run (7), keyword_bridge (8), lexer_bridge (16),
  shell_host (3), shell_session (2).
- Zero zero-consumer bridges (no silent deaths).
- Zero undocumented bridge-named files in src/.
- Section-4 .id debt targets all present: lib/os/process.id, lib/fs.id,
  lib/script.id, lib/env.id.
- Today's deletions (MCP trio, gate.id, generators) were NOT bridge
  records and do not appear in the census — the 2026-08-14 records
  survive the purge unchanged.

## Deletion conditions

Per bridge_census.md; none measured as satisfied today (all consumers
live). Re-run this census (source: evidence/mop/bridge-census.md method
above) after the reconcile merge — the 21-commit line deletes orphaned
bootstrap transports and may satisfy conditions.
