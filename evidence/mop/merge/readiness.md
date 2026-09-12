# Merge-readiness — reconcile/idol-canonical-all-work-20260817 vs codex/next-semantic-slice

| # | directive |
|---|---|
| 1 | Measured 2026-08-17 in a detached worktree at ae859638 (their tip), their compiler built clean (22s). |
| 2 | Fork point: c6d039f5 (they lack the last six commits of this line: LAW-ONE renames/census, H4, H5/F5 finals, parity extension, remeasure). |

## Their tip (21 commits): home resolution by actual file identity,
| # | directive |
|---|---|
| 1 | lexical parent homes, source-law/world-authority separation, orphaned bootstrap transport deletion, grammar parity made FAIL-CLOSED, evidence subjects on clean trees. |

## Compatibility verdicts (their binary, their tree)

| Check | Result |
|---|---|
| Their build | clean |
| Their reduce selftest | PASS |
| Their parity (fail-closed evolution) | PASS — "generated grammar role agrees with canonical token identity" |
| MCP manifest | identical (idol, idol-native) |
| F1 theorem | unchanged (unresolved-application-facts; negative control compiles) |
| F3b theorem | unchanged (global-init-not-constant) |
| H5 theorem | STILL PRESENT (ld: symbol — cross-module exe-link gap) |
| **F5 theorem** | **FIXED ON THEIR LINE** — self-recursion now yields classified DNB001 `missing: parse_expr` (dnir lower) instead of the InvalidAggregateFact internal crash |

## Merge implications

- Their line SUPERSEDES the F5 crash: the 2-line fixture becomes a
  regression guard (must refuse classified, never crash).
- Conflicts expected: tools/reduce/idol (this line renamed idol-reduce ->
  idol for LAW-ONE; their tree kept idol-reduce), fixture renames into
  family hierarchies, census/compound (theirs lacks it), H4 wrapper in
  main.zig vs their main.zig changes.
- Their fail-closed parity adopts this line's report-only stance as a
  gate — keep theirs.
- Recommended order: merge their line first (semantic substance), then
  re-apply this line's tooling deltas (renames + census + H4) on top,
  re-running compound-census baseline after the merge tree settles.

## Post-merge window (added after checking overlap)

| # | directive |
|---|---|
| 1 | Their line touches main.zig, native_backend.zig, home_resolve.zig, build.zig — the C-ABI duo-symbol rename (duo_lexer_*, duo_keyword_classify, duo_lexer_host_stride) is therefore DEFERRED to immediately after the merge: claims are empty and files clean on both sides, so the rename gets one conflict-free window right after their merge lands. |
