# frontier-loop

## loop

| stage | act |
|---|---|
| scan | weekly sweep sources for new or missed items |
| evaluate | verdict within 48h per candidate |
| decide | integrate watch reject |
| log | append dated entry to frontier-log.md |

## cadence

| rhythm | what | owner |
|---|---|---|
| weekly | scan sweep dedupe draft | scan job |
| 48h | evaluate candidates | loop agent |
| monthly | deep scan proceedings | loop agent |
| continuous | watchlist triggers | coordinator |

## sources

| class | items |
|---|---|
| conferences | pldi popl asplos micro hpca isca cgo oopsla icfp eurosys osdi atc |
| preprints | arxiv cs.pl cs.pf cs.ar |
| industry | llvm gcc apple arm nvidia amd google modular meta |
| formal | lean rocq smt z3 cvc5 verus |
| hardware | apple silicon intel amd risc-v cheri |
| trackers | llvm egglog cranelift verus kleidiai riscv |

## decide

| outcome | meaning |
|---|---|
| integrate | enters p0 p1 p2 plan |
| watch | logged with revisit trigger |
| reject | logged with reason; not rescanned |

## escalate

| condition | act |
|---|---|
| beats p0 on axis | flag p0-candidate; notify coordinator |
