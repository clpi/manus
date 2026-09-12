# Bridge census — measured 2026-08-17 (GLM-C)

Against the root `bridge_census.md` (2026-08-14) and `bridge_audit.md` at HEAD
`ed3cb305`. Those two root documents were deleted on 2026-08-24 — analysis prose
at the repository root with `law.path.name`-violating names, whose rulings had
already been absorbed into `law.bridge.death` and `docs/spec/host.md`. Their
text is in git history; the inventory they baselined is re-measured below and
still holds, so nothing here depends on reading them.

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

Per the archived `bridge_census.md`; none measured as satisfied today (all
consumers live). Re-run this census (method above) after the reconcile merge —
the 21-commit line deletes orphaned bootstrap transports and may satisfy
conditions.

## Re-measured 2026-08-24 (reconcile)

The six-bridge inventory is unchanged: `src/foreign_adapter.zig`,
`src/host_run.zig`, `src/keyword_bridge.zig`, `src/lexer_bridge.zig`,
`src/shell_host.zig`, `src/shell_session.zig` all exist, and `src/` holds no
bridge-named file outside that set. So the 2026-08-17 verdict above is still the
current one, which is why deleting the two root baseline documents costs this
census nothing.
