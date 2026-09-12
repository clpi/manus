| field | value |
|---|---|
| title | GAP-145 boundary measurement — .quoted consumer census (lane 8 evidence) |

| # | directive |
|---|---|
| 1 | Measured at 84c437f0 (canonical main). |
| 2 | This is a read-only census for the lexical-identity frontier; no source was modified. |

| section |
|---|---|
| Identity projection state (all agree) |

| # | directive |
|---|---|
| 1 | All ten GAP-145 crossed identities verified present and correctly numbered in lib/compiler/token.id (backtick 84, text_lit 105, bytes_lit 106, compat variants 107-108, EOF 109, shebang 110, comment 111-113). |
| 2 | Parity: generated grammar role agrees with canonical (113 identities, 114 physical slots — slot 3 unpublished by design). |
| 3 | Slot 3 correctly absent (comment "Not an identity. |
| 4 | Do not renumber"). |

| section |
|---|---|
| Remaining work census: .quoted → semantic consumers |

| # | directive |
|---|---|
| 1 | The gap's stated acceptance: "zero observers of the collapsed identity" — consumers that map every .quoted value directly to .str must instead consume the quote/source-law fact where the distinction is observable. |

| Consumer | .quoted sites | Class |
|---|---|---|
| src/codegen.zig | 154 | realization — most are structural checks (.quoted arm selection), not collapse-to-str |
| src/parser.zig | 48 | ingress — where quote is consumed during parse |
| src/sema.zig | 48 | semantic — the primary collapse candidates |
| src/comptime.zig | 15 | evaluation — folding sites |
| TOTAL | 265 | |

| # | directive |
|---|---|
| 1 | Not all 265 are collapse observations. |
| 2 | Many are the switch arm that SELECTS on .quoted (structural — correct). |
| 3 | The collapse class is the subset that READS .quoted text AS .str without consulting the quote fact (text vs bytes vs compat). |
| 4 | Distinguishing structural from collapsing per-site is the owning lane's work; this census is the map. |

| section |
|---|---|
| Source-law admission (crossed, verified) |

| # | directive |
|---|---|
| 1 | sourceform*/sourceentry*/sourcefact* now execute in the Idol producer (GAP-145 text confirms). |
| 2 | Zig supplies only filesystem normalization and temporary ABI binding. |
| 3 | The `suffix(file)` face is deleted. `ledger/shc` PASS on this transfer. |

| section |
|---|---|
| Assessment |

| # | directive |
|---|---|
| 1 | The identity projection is DONE (all crossed identities verified). |
| 2 | The remaining GAP-145 work is the consumer-side collapse: teaching 265 .quoted sites to consult the quote/source-law fact where the distinction is observable, starting with sema.zig (48 sites, the primary collapse candidates). |
| 3 | This is squarely the compiler lane. |
