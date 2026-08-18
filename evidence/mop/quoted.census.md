# GAP-145 boundary measurement — .quoted consumer census (lane 8 evidence)

Measured at 84c437f0 (canonical main). This is a read-only census for
the lexical-identity frontier; no source was modified.

## Identity projection state (all agree)

All ten GAP-145 crossed identities verified present and correctly
numbered in lib/compiler/token.id (backtick 84, text_lit 105,
bytes_lit 106, compat variants 107-108, EOF 109, shebang 110,
comment 111-113). Parity: generated grammar role agrees with canonical
(113 identities, 114 physical slots — slot 3 unpublished by design).
Slot 3 correctly absent (comment "Not an identity. Do not renumber").

## Remaining work census: .quoted → semantic consumers

The gap's stated acceptance: "zero observers of the collapsed
identity" — consumers that map every .quoted value directly to .str
must instead consume the quote/source-law fact where the distinction
is observable.

| Consumer | .quoted sites | Class |
|---|---|---|
| src/codegen.zig | 154 | realization — most are structural checks (.quoted arm selection), not collapse-to-str |
| src/parser.zig | 48 | ingress — where quote is consumed during parse |
| src/sema.zig | 48 | semantic — the primary collapse candidates |
| src/comptime.zig | 15 | evaluation — folding sites |
| TOTAL | 265 | |

Not all 265 are collapse observations. Many are the switch arm that
SELECTS on .quoted (structural — correct). The collapse class is the
subset that READS .quoted text AS .str without consulting the quote
fact (text vs bytes vs compat). Distinguishing structural from
collapsing per-site is the owning lane's work; this census is the
map.

## Source-law admission (crossed, verified)

sourceform*/sourceentry*/sourcefact* now execute in the Idol producer
(GAP-145 text confirms). Zig supplies only filesystem normalization
and temporary ABI binding. The `suffix(file)` face is deleted.
`ledger/shc` PASS on this transfer.

## Assessment

The identity projection is DONE (all crossed identities verified).
The remaining GAP-145 work is the consumer-side collapse: teaching
265 .quoted sites to consult the quote/source-law fact where the
distinction is observable, starting with sema.zig (48 sites, the
primary collapse candidates). This is squarely the compiler lane.
