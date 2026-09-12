| field | value |
|---|---|
| title | EDGE-MAX audit — ingest relations vs existing edges (measured) |

| # | directive |
|---|---|
| 1 | Existing str edges in the canonical corpus (native.id, comptime.id): `len`, `sub`, `byte`, `find`, `has`, `to`. |
| 2 | Plus `stdin:line`, `stdout:write`, `path:read`, `os.args`, `os.env`, `mem.*`. |

| section |
|---|---|
| Violations found (mashed compounds, not law-known, not edges) |

| My relation | Violation | Fix per EDGE-MAX |
|---|---|---|
| `ingestmain` | mashed compound (ingest+main) — user-flagged | decompose: the module-level entry already exists as `main`; the extracted body is the module INGEST face — rename to a single word or fold under an existing edge |
| `ulebval` / `ulebafter` | prefixed compounds (uleb+val/after) — foreign-term + noun mashes | `uleb` is the foreign provenance (Wasm spec term, like `f64`); the EDGE is `value`/`after`. Rename: `uleb:value` / `uleb:after` as world edges, or fold: the pair IS one walk — `s:uleb(i)` returning the pack (blocked by first-class packs, the named deletion condition) |
| `slebend` / `slebsign` | same pattern, sleb+end/sign | same fix |
| `byteat` / `bytecount` | byte+at, byte+count | byteat ≈ existing `:byte(i)` on a hex-decoded face — fold when H9 lands (the binary face replaces the accessor); bytecount = `s:len() / 2` — INLINE IT (one expression, not a relation) |
| `appfact` | app+fact mash | the relation emits a fact — under EDGE-MAX it's `src:fact(...)` or the emission folds into the walk (inline when register pressure allows) |
| `binname` | bin+name | it maps op→name: `op:name()` — `name` is a known law word |
| `immclass` | imm+class | `op:class()` — or inline the chain |
| `hexdigit` | hex+digit | `c:hex()` — hex is the encoding provenance |
| `pow2` | pow+2 — number-suffixed | inline: it exists because `pow2` has no arithmetic edge — fold when the compiler admits `1 << k` |

| section |
|---|---|
| Verdict |

| # | directive |
|---|---|
| 1 | 14 relations |
| 2 | NONE are law-known; the majority are foreign-term+noun mashes following the `ulebval` pattern I introduced. |
| 3 | The correct fixes: (1) inline the single-expression relations (bytecount, pow2) — zero new edges |
| 4 | (2) rename subject-first edge faces for the rest (op:name, c:hex) |
| 5 | (3) the LEB pair folds into ONE walk when packs land |
| 6 | (4) ingestmain folds back into main or becomes the module's declared entry under a single word. |
| 7 | The census/compound gate does NOT catch these (they're function names, not paths) — the gate needs a source-identifier pass (gate/idiom.id's compound() already exists for this; it just cannot execute yet). |
