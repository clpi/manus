# gate migration inventory

| validated at | tip |
|---|---|
| 2026-09-12 | 2ff7b683 |

## counts
| scope | count |
|---|---|
| gate scripts (gate/**/*.sh, tracked) | 101 |
| eligible for migration | 93 |
| excluded | 8 |
| tracked *.sh, repo-wide, at tip | 134 |
| tracked *.sh before migrations began | 140 |
| tracked *.py | 21 |
| tracked *.c | 96 |
| native .id drivers (gate/**/*.id) | 33 |
| registered in IDOL_GATES | 16 |
| migrations completed (commits below) | 6 |

## completed migrations
| .id gate | .sh removed | commit |
|---|---|---|
| gate/delimiter-projection-law.id | gate/delimiter-projection-law.sh | 764b138a |
| gate/gap-114-boxed-len.id | gate/gap-114-boxed-len.sh | 1ce39658 |
| gate/gap-121-module-init.id | gate/gap-121-module-init.sh | 725cb769 |
| gate/architecture-roadmap.id | gate/architecture-roadmap.sh | 4cfe3685 |
| gate/public-safety.id | gate/public-safety.sh | 87da2514 |
| gate/module-zero-precheck.id | gate/module-zero-precheck.sh | 155e30cc |

## exclusions
| file | lines | reason |
|---|---|---|
| gate/all.sh | 344 | runner: enumerates and executes every gate, sh and .id; the enumerator cannot be enumerated |
| gate/attribution.sh | 188 | analysis report: ranks first blocking edge per corpus program; optional budget ratchet, not a pass/fail verdict gate |
| gate/coverage.sh | 590 | report-only publisher: emits the coverage-by-construction aggregate report, not a pass/fail verdict |
| gate/differential.sh | 1498 | parameterized tool: takes compiler arms as CLI arguments; driven by CI, not a self-contained verdict |
| gate/lock.sh | 335 | concurrency harness: background children, kill/wait, traps, timing loops for idol-lock; shell process orchestration |
| gate/realization/direct.sh | 96 | sourced library: declares # gate-role: library; not a gate |
| gate/taint.sh | 134 | host interposition: Darwin dyld-interposition counterfactual; host dynamic-linker machinery |
| gate/vacuity.sh | 578 | meta-harness: measures gates under plants; must stay outside the measured population |

## ranked queue
| rank | file | lines | status |
|---|---|---|---|
| 1 | gate/wasm/engine.sh | 37 | queued |
| 2 | gate/treesitter/agreement.sh | 54 | batch-1 |
| 3 | gate/grammar/spec.sh | 74 | queued |
| 4 | gate/directive.sh | 91 | queued |
| 5 | gate/wasm/global.sh | 93 | queued |
| 6 | gate/realization/direct.sh | 96 | excluded |
| 7 | gate/artifact-equality.sh | 114 | queued |
| 8 | gate/wasm/local.sh | 114 | queued |
| 9 | gate/foreign-symbol-quarantine.sh | 124 | batch-1 |
| 10 | gate/native-call.sh | 124 | queued |
| 11 | gate/agentlaw.sh | 125 | queued |
| 12 | gate/corpus-status.sh | 131 | queued |
| 13 | gate/researchgap.sh | 134 | batch-1 |
| 14 | gate/taint.sh | 134 | excluded |
| 15 | gate/posix.sh | 136 | queued |
| 16 | gate/any.sh | 140 | queued |
| 17 | gate/gap-115-evidence.sh | 140 | batch-1 |
| 18 | gate/architecture-companion.sh | 144 | queued |
| 19 | gate/gap-141-runtime-temp.sh | 145 | queued |
| 20 | gate/decimal.sh | 161 | queued |
| 21 | gate/realize/indexwrite.sh | 163 | queued |
| 22 | gate/world/stage.sh | 170 | queued |
| 23 | gate/node.sh | 173 | queued |
| 24 | gate/semantic-graph-authority.sh | 185 | queued |
| 25 | gate/ftcftw/hotloop.sh | 187 | queued |
| 26 | gate/attribution.sh | 188 | excluded |
| 27 | gate/architecture-negative.sh | 190 | queued |
| 28 | gate/docs.sh | 191 | queued |
| 29 | gate/explain.sh | 193 | queued |
| 30 | gate/parser/slice.sh | 195 | queued |
| 31 | gate/ftcftw/stage.sh | 196 | queued |
| 32 | gate/refuse.sh | 196 | queued |
| 33 | gate/divsign.sh | 197 | queued |
| 34 | gate/placefacts.sh | 200 | queued |
| 35 | gate/concept.sh | 206 | queued |
| 36 | gate/realize/statement.sh | 212 | queued |
| 37 | gate/branch/census.sh | 213 | queued |
| 38 | gate/converge.sh | 220 | queued |
| 39 | gate/width.sh | 222 | queued |
| 40 | gate/world-launch.sh | 222 | queued |
| 41 | gate/subject.sh | 226 | queued |
| 42 | gate/byte/stable.sh | 227 | queued |
| 43 | gate/world/access.sh | 229 | queued |
| 44 | gate/alignment-projection.sh | 240 | queued |
| 45 | gate/identity/retired.sh | 240 | queued |
| 46 | gate/occurrence/copy.sh | 240 | queued |
| 47 | gate/cache-home.sh | 242 | queued |
| 48 | gate/admission-controls.sh | 244 | queued |
| 49 | gate/summary.sh | 246 | queued |
| 50 | gate/gap-221-shadowstore.sh | 247 | queued |
| 51 | gate/index.sh | 247 | queued |
| 52 | gate/cachepublish.sh | 253 | queued |
| 53 | gate/outcome.sh | 264 | queued |
| 54 | gate/ftcftw/width.sh | 266 | queued |
| 55 | gate/effect.sh | 268 | queued |
| 56 | gate/page.sh | 273 | queued |
| 57 | gate/ftcftw/wrap.sh | 275 | queued |
| 58 | gate/realize/census.sh | 278 | queued |
| 59 | gate/cachedeps.sh | 286 | queued |
| 60 | gate/world/face.sh | 289 | queued |
| 61 | gate/callfold.sh | 291 | queued |
| 62 | gate/accord.sh | 313 | queued |
| 63 | gate/defaults.sh | 315 | queued |
| 64 | gate/layering.sh | 321 | queued |
| 65 | gate/divisor.sh | 323 | queued |
| 66 | gate/table-projection.sh | 323 | queued |
| 67 | gate/pull.sh | 327 | queued |
| 68 | gate/site.sh | 328 | queued |
| 69 | gate/vocabulary-controls.sh | 334 | queued |
| 70 | gate/lock.sh | 335 | excluded |
| 71 | gate/all.sh | 344 | excluded |
| 72 | gate/mcp.sh | 359 | queued |
| 73 | gate/treesitter/literal.sh | 368 | queued |
| 74 | gate/directive/authority.sh | 372 | queued |
| 75 | gate/layout.sh | 373 | queued |
| 76 | gate/admission.sh | 376 | queued |
| 77 | gate/layering/control.sh | 387 | queued |
| 78 | gate/speculation.sh | 405 | queued |
| 79 | gate/conversion.sh | 431 | queued |
| 80 | gate/place/existence.sh | 442 | queued |
| 81 | gate/lower/cost.sh | 444 | queued |
| 82 | gate/application.sh | 459 | queued |
| 83 | gate/pack.sh | 467 | queued |
| 84 | gate/nul.sh | 493 | queued |
| 85 | gate/projection.sh | 508 | queued |
| 86 | gate/lower/fallback.sh | 520 | queued |
| 87 | gate/envcache.sh | 525 | queued |
| 88 | gate/lsp.sh | 525 | queued |
| 89 | gate/authority/law.sh | 530 | queued |
| 90 | gate/surface/reach.sh | 546 | queued |
| 91 | gate/vacuity.sh | 578 | excluded |
| 92 | gate/coverage.sh | 590 | excluded |
| 93 | gate/byte/face.sh | 681 | queued |
| 94 | gate/gap-145-identity-producer.sh | 689 | queued |
| 95 | gate/vocabulary.sh | 692 | queued |
| 96 | gate/gap-144-table-identity.sh | 696 | queued |
| 97 | gate/authority.sh | 787 | queued |
| 98 | gate/frontier.sh | 802 | queued |
| 99 | gate/crosspartition.sh | 1215 | queued |
| 100 | gate/differential.sh | 1498 | excluded |
| 101 | gate/token/read.sh | 5517 | queued |
