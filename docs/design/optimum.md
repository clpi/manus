# optimum

## levels

| level | name | basis | literal |
|---|---|---|---|
| L1 | idiom | best production compiler output | no |
| L2 | hand | expert assembly plus written argument plus review | yes |
| L3 | super | exhaustive search to length n | yes |
| L4 | bound | analytic or checked lower bound | yes |

## beats

| criterion | rule |
|---|---|
| correctness | identical observable behavior first |
| warmup | 3 untimed runs per binary |
| interleave | alternate binaries per round |
| rounds | 21 minimum |
| metric | median primary; mean stddev min max p95 disclosed |
| significance | welch t-test p below 0.05 |
| margin | (oracle minus idol) over oracle on medians |
| floor | margin must exceed oracle self variation |
| rerun | win reproduces on fresh protocol run |
| disasm | hot loop difference explainable |

## revision

| step | name | act |
|---|---|---|
| 1 | freeze | freeze binary oracle machine environment |
| 2 | rerun | rerun stats protocol; idol median below oracle median; p below 0.05; margin above floor |
| 3 | hypothesis | default: oracle was not optimal; claimant finds why |
| 4 | revise | revise oracle; bump version; rerun |
| 5 | stand | claim exceeds only if oracle stands under l3 or l4; publish version argument technique correction |

## platform

| rule | value |
|---|---|
| scope | per-platform only |
| oracle | one per platform |
| disclose | cpu cores os toolchain power shim |
| rounds | scale with timer granularity; 21 floor |
| timer | prefer os counter over tsc |

## threats

| threat | mitigation |
|---|---|
| thermal throttling | interleaved rounds; medians; disclose power |
| aslr alignment | a/a floor test |
| background load | interleaving; outlier disclosure; rerun |
| page-cache warmth | cold-start protocol |
| oracle blind spots | second-person review; l3 cross-check |
| p-hacking | fixed 21-round protocol; disclose reruns |
