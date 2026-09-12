| field | value |
|---|---|
| title | byteat — skeptical audit (user direction) |

| section |
|---|---|
| What it is |

| # | directive |
|---|---|
| 1 | The hex-transport shim: decode the n-th module byte from a hex-pair string. |
| 2 | Exists ONLY because H9 (binary ingress) is blocked — the declared deletion condition. |

| section |
|---|---|
| Skeptical findings |

| # | directive |
|---|---|
| 1 | **NAME VIOLATION**: byte+at is a mash by LAW-ONE. My own compound census misses it (function names, not paths) — the same blind spot the edgemax audit found for all 14 relations. |

| # | directive |
|---|---|
| 1 | **EDGE COLLISION**: the natural face — s:byte(n) — is TAKEN by str's existing byte edge (returns the ASCII char code). The shim cannot reuse the name without shadowing a builtin. This is the transport problem wearing a naming problem. |

| # | directive |
|---|---|
| 1 | **THE DEFECT SHIMMED A DEFECT**: byteat's body originally used the argument form (s:hex(s:byte(k))) which silently returns 0 — argform.defect.md. The workaround chains subject-first, but the correct reading is: the COMPILER DEFECT forced the body shape, and the relation's existence hides a transport that should not exist. |

| # | directive |
|---|---|
| 1 | **DELETION CONDITION**: H9 binary ingress. When the bytes face lands, byteat DELETES ENTIRELY — s:byte(n) becomes the module byte. Every call site is already subject-first; the swap is one relation body, not 50 call sites. |

| section |
|---|---|
| Verdict |

| # | directive |
|---|---|
| 1 | Keep as the single transport seam (50 call sites vs one body), with the mash debt RECORDED as the price of the H9 blocker. |
| 2 | Rename options blocked by the byte collision. |
| 3 | The honest name for the seam under LAW-ONE would be a world edge (hex:byte) — blocked by module-scope relations. |
| 4 | Deletion on H9 is the correct fix, not a rename. |
