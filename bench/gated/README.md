| field | value |
|---|---|
| title | gated |

| section |
|---|---|
| categories |

| program | stresses | gated on |
|---|---|---|
| fp_dot | float multiply-add 1m elements | float type plus float arithmetic |
| indirect | indirect calls 4-entry table | function definitions plus indirect calls |
| strops | byte strlen strcpy 1mb | byte-addressable memory |
| traverse | linked-list walk 1m nodes | memory plus pointers |
| cache_seq | stride-1 walk 64mb | memory array indexing |
| cache_stride | stride-64 walk 64mb | memory array indexing |

| section |
|---|---|
| files |

| suffix | content |
|---|---|
| .c | c oracle runnable semantics frozen |
| .id.future | intended idol proposed syntax not compiling |

| section |
|---|---|
| adopt |

| step | act |
|---|---|
| 1 | land gating compiler feature |
| 2 | write bench/programs/<name>.id; verify vs c oracle |
| 3 | move row to suite table; run |
| 4 | update optimum.md per-benchmark optimum |
