#!/bin/sh
# delete-reconciled-branches.sh — remove remote branches verified reconciled.
#
# VERIFICATION BASIS (2026-08-25, main = 7b025afe "sema: an aggregate wearing
# parens refuses at check, mirroring law.brace (#163)"):
#
#   gate/branch/census.sh at that head examined 162 origin refs besides main:
#     70  contained            — ancestors of origin/main, zero delta
#     78  landed-by-subject    — every commit subject in main AND every patch
#                               upstream by patch id (`git cherry` printed no
#                               `+` for any of them; subject-only count was 0)
#     14  carried an unlanded subject and were read individually:
#       - cursor/reconcile-main-surface-000b and land/retpack-20260823:
#         `git merge-tree --write-tree origin/main <ref>` reproduces main's
#         tree exactly — merging them is a no-op (the cursor branch is the
#         squash source of #154).
#       - sound16/place-and-cache-contract: BuildDependencies/buildCacheKey
#         landed in src/main.zig; GAP-230 (CLOSED) records it as the survivor.
#       - land/homeclosure-20260823, wip/crossmodule-20260823,
#         wip/wasmconv-20260823, wip/worldstage-20260823,
#         codex/pretty-runner-direct-spawn-20260821: every function their
#         deltas add exists on main by name (git grep against origin/main).
#       - land/generators-20260823, wip/generators-20260823: main's
#         lib/token/classify.id and gate/table-projection.sh carry their
#         changes in stronger form (bracket projection, `i += 1`, §3
#         byte-identical regeneration) — the #155 reconciliation landed them.
#       - lane/xmod-realize-20260823: superseded by main 1ec8850e
#         "codegen: refuse unrealized cross-home calls".
#       - codex/foreign-symbol-quarantine-20260821: main's src/sema.zig owns
#         the malformed-foreign-home refusal and its test.
#     This matches the #155 ledger (0bc03d26): "All 13 are now resolved:
#     5 landed, 8 established as superseded."
#
# EXCLUDED (not deleted by this script):
#   main                                    — the base branch
#   claude/reconcile-semantic-graph-088dg0  — live session branch
#   audit/macmini-live-20260820             — the ONE ref whose content is
#     absent from main: 5 temporary Mac mini CI-audit files whose own note
#     says "Do not merge". Obsolete scaffolding, but it carries unlanded
#     bytes, so its deletion stays a human decision. Delete manually with:
#       git push origin --delete audit/macmini-live-20260820
#
# Run from any clone with push access:  sh delete-reconciled-branches.sh
# Each deletion is independent; a failure on one does not stop the rest.

set -u

git push origin --delete audit/metrics-current-head
git push origin --delete census/falsesurface
git push origin --delete census/recon2-final
git push origin --delete codex/ast-sovereignty-20260823
git push origin --delete codex/authority-edition-20260823
git push origin --delete codex/authority-projection-repair-20260818
git push origin --delete codex/b0-frontier-20260817
git push origin --delete codex/canonical-closure-20260818
git push origin --delete codex/canonical-integration-20260818
git push origin --delete codex/constant-answer-sovereignty-20260823
git push origin --delete codex/delete-session-state-20260818
git push origin --delete codex/delete-source-family-scenery-20260817
git push origin --delete codex/foreign-symbol-quarantine-20260821
git push origin --delete codex/gap-104-20260818
git push origin --delete codex/grammar-authority-integration-20260818
git push origin --delete codex/grammar-parity-meta-20260818
git push origin --delete codex/graph-spine-next-20260823
git push origin --delete codex/integrate-worlds-and-totality
git push origin --delete codex/latest-canonical-20260818
git push origin --delete codex/lexer-host-retirement-20260817
git push origin --delete codex/lexer-regen-ratchet-20260817
git push origin --delete codex/lexer-regen-ratchet-review-20260818
git push origin --delete codex/module-binding-20260823-55193
git push origin --delete codex/next-semantic-slice
git push origin --delete codex/parser-gate-refresh-20260824
git push origin --delete codex/parser-real-decision-20260823
git push origin --delete codex/parser-slice-transfer-20260823
git push origin --delete codex/parser-token-view-20260818
git push origin --delete codex/path-write-vertical-20260818
git push origin --delete codex/pretty-runner-direct-spawn-20260821
git push origin --delete codex/reconcile-codegen-law-20260817
git push origin --delete codex/self-zero-production-20260818
git push origin --delete codex/self-zero-size-final
git push origin --delete codex/source-admission-20260817
git push origin --delete codex/source-law-frontier-20260817
git push origin --delete codex/source-realization-repair-20260817
git push origin --delete codex/sovereignty-ledger-20260823
git push origin --delete codex/tail-sovereignty-20260823
git push origin --delete codex/treesitter-role-consumer-20260818
git push origin --delete codex/wasm-bridge-open-world-repair-20260818
git push origin --delete codex/wasm-observer-elision-20260817
git push origin --delete codex/wasm-status-truth-20260818
git push origin --delete codex/xmodule-body-20260823
git push origin --delete codex/xmodule-graph-realization-20260823
git push origin --delete codex/xmodule-lib-20260823
git push origin --delete cursor/reconcile-main-surface-000b
git push origin --delete fix/application-continuity
git push origin --delete fix/cache-env-closure
git push origin --delete fix/directive-ratchet
git push origin --delete fix/divisor-one-producer
git push origin --delete fix/divisor-refusal-reaches-exit
git push origin --delete fix/effect-one-and-range
git push origin --delete fix/gap134-binop-owner
git push origin --delete fix/gap145-observers
git push origin --delete fix/intmin-one-producer
git push origin --delete fix/invalid-trailing-zero
git push origin --delete fix/oracle-string-order-unsigned
git push origin --delete fix/spine-law-root
git push origin --delete fix/std-code-position-budget
git push origin --delete fix/world-face-zero
git push origin --delete gaps/224-correction
git push origin --delete gaps/declare-kind-218-222
git push origin --delete gaps/vocabulary-law-conflict
git push origin --delete gate/application-subject
git push origin --delete gate/astpoison
git push origin --delete gate/authority-law
git push origin --delete gate/bytestable
git push origin --delete land/directivedel-20260823
git push origin --delete land/generators-20260823
git push origin --delete land/homeclosure-20260823
git push origin --delete land/retpack-20260823
git push origin --delete lane/gap145zero-20260823
git push origin --delete lane/gapcompact-classify-20260823
git push origin --delete lane/gapcompact-frontier-20260823
git push origin --delete lane/mutation-20260823
git push origin --delete lane/nulrep
git push origin --delete lane/occurrence-determinism-20260823
git push origin --delete lane/occurrence-identity-20260823
git push origin --delete lane/termination-consumer-census
git push origin --delete lane/vacuity-20260823
git push origin --delete lane/worldstage
git push origin --delete lane/wrongans-invalid-exit-20260823
git push origin --delete lane/xmod-crosshome-20260823
git push origin --delete lane/xmod-realize-20260823
git push origin --delete mbp-archive/bails-aa6
git push origin --delete mbp-archive/capability-std-gaps
git push origin --delete mbp-archive/codex-agent-readiness-20260810
git push origin --delete mbp-archive/codex-application-authority-20260810
git push origin --delete mbp-archive/codex-integration-gap141
git push origin --delete mbp-archive/codex/application-outcome
git push origin --delete mbp-archive/codex/assumption-graph-required
git push origin --delete mbp-archive/codex/c-law-projection-fix
git push origin --delete mbp-archive/codex/cache-home-fix
git push origin --delete mbp-archive/codex/default-capability-census
git push origin --delete mbp-archive/codex/descriptor-default-roundtrip
git push origin --delete mbp-archive/codex/final-integrate
git push origin --delete mbp-archive/codex/graph-applications-and-wasm-evidence
git push origin --delete mbp-archive/codex/home-parent-fix
git push origin --delete mbp-archive/codex/home-parent-merge
git push origin --delete mbp-archive/codex/knowledge-graph-required
git push origin --delete mbp-archive/codex/module-aggregate-fullslice
git push origin --delete mbp-archive/codex/next-semantic-slice-20260818
git push origin --delete mbp-archive/codex/result-member-demand
git push origin --delete mbp-archive/codex/result-member-demand-integrate
git push origin --delete mbp-archive/codex/semantic-transaction-safe
git push origin --delete mbp-archive/codex/unit-graph-facts-expectation
git push origin --delete mbp-archive/main
git push origin --delete mbp-archive/native-gaps-a8dc
git push origin --delete mbp-archive/nominal-093-canonical
git push origin --delete mbp-archive/worktree-agent-a088a4253eb6a6c26
git push origin --delete mbp-archive/worktree-agent-a1c356ea19f50bbd6
git push origin --delete mbp-archive/worktree-agent-a3e43a721419bf110
git push origin --delete mbp-archive/worktree-agent-a3f71305bd3b266af
git push origin --delete mbp-archive/worktree-agent-a64f1d0f2e26f5539
git push origin --delete mbp-archive/worktree-agent-a6c3c9cca66f48b3e
git push origin --delete mbp-archive/worktree-agent-a75e97b1687f2eb2f
git push origin --delete mbp-archive/worktree-agent-a7d7cbaf162f74e01
git push origin --delete mbp-archive/worktree-agent-ac31cbe2ea7754a92
git push origin --delete mbp-archive/worktree-pass81-family-registry
git push origin --delete mbp-archive/worktree-perf-losing-rows
git push origin --delete reconcile/admission-20260822
git push origin --delete reconcile/admission-clean-20260822
git push origin --delete reconcile/bindorigin-20260822
git push origin --delete reconcile/buildtest-20260822
git push origin --delete reconcile/c0-gap-alignment-20260818
git push origin --delete reconcile/canonical-gates-20260817
git push origin --delete reconcile/compose-20260823
git push origin --delete reconcile/evidence-repair-20260822
git push origin --delete reconcile/fieldread-20260822
git push origin --delete reconcile/floorfix-20260822
git push origin --delete reconcile/gap221-20260822
git push origin --delete reconcile/gap222-20260822
git push origin --delete reconcile/graph-id-realization-20260817
git push origin --delete reconcile/idol-canonical-all-work-20260817
git push origin --delete reconcile/idol-token-switch-zero-20260817
git push origin --delete reconcile/ifconv-20260822
git push origin --delete reconcile/magicdiv-20260822
git push origin --delete reconcile/modpromote-20260822
git push origin --delete reconcile/placefacts-20260822
git push origin --delete reconcile/scalarplace-20260823
git push origin --delete reconcile/semantic-transport-20260822
git push origin --delete reconcile/shadow-clean-20260822
git push origin --delete reconcile/shadow-identity-20260822
git push origin --delete reconcile/source-law-ingress-20260817
git push origin --delete reconcile/stdcensus-20260822
git push origin --delete slot-role-graph-facts
git push origin --delete sound16/place-and-cache-contract
git push origin --delete vacuity/zero
git push origin --delete wip/astpoison-20260823
git push origin --delete wip/crossmodule-20260823
git push origin --delete wip/directivedel-20260823
git push origin --delete wip/gapcompact-20260823
git push origin --delete wip/generators-20260823
git push origin --delete wip/metrics-20260823
git push origin --delete wip/nulrep-20260823
git push origin --delete wip/reachability-20260823
git push origin --delete wip/textrep-20260823
git push origin --delete wip/vacuityzero-20260823
git push origin --delete wip/wasmconv-20260823
git push origin --delete wip/worldstage-20260823
