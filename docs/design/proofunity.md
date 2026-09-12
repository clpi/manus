# proofunity

## identity

| concept | form |
|---|---|
| proposition | value |
| proof | value |
| tactic | relation |
| checking | application |

## vocab

| word |
|---|
| span |
| first |
| rest |
| nth |
| push |
| num |
| of |
| check |
| term |
| holes |
| ctx |
| prop |
| head |
| tail |
| plug |
| goal |
| intro |
| exact |
| apply |
| split |
| left |
| right |
| qed |

## props

| spelling | meaning |
|---|---|
| a | atom |
| >ab | a implies b |
| &ab | a and b |
| \|ab | a or b |

## terms

| spelling | rule |
|---|---|
| 1-9 | hypothesis index |
| !n! | hypothesis index 10 plus |
| Lx | implication intro |
| Axy | implication elim |
| Pxy | conjunction intro |
| Fx | conjunction elim first |
| Sx | conjunction elim second |
| Ixb | disjunction intro left |
| Jxa | disjunction intro right |
| Cxyz | disjunction elim |

## tactics

| tactic | input | output |
|---|---|---|
| goal | proposition | one hole |
| intro | >ab | b under extended context |
| exact | term checks vs goal | hole filled |
| apply | u proves arg to goal | new goal arg |
| split | &ab | goals a b |
| left | \|ab | goal a |
| right | \|ab | goal b |
| qed | no holes | term else empty |

## measure

| language | identity | composition | chain20 | file |
|---|---|---|---|---|
| coq | 5 / 79 | 8 / 141 | 14 / 705 | 27 / 926 |
| lean | 1 / 55 | 2 / 105 | 10 / 625 | 13 / 786 |
| agda | 2 / 46 | 2 / 90 | 10 / 609 | 14 / 746 |
| haskell | 2 / 24 | 2 / 60 | — | — |
| rust | 3 / 31 | 3 / 101 | — | — |
| idol | 1 / 26 | 1 / 40 | 1 / 202 | 3 / 268 |

## pymeasure

| language | chain20 |
|---|---|
| python z3 | 11 / 524 |
| idol | 1 / 201 |

## density

| language | bytes | facts | ratio |
|---|---|---|---|
| idol | 201 | 145 | 1.4 |
| coq | 705 | 145 | 4.9 |
| lean | 625 | 145 | 4.3 |
| python z3 | 524 | 145 | 3.6 |

## phases

| phase | scope | status |
|---|---|---|
| 1 | kernel: strings check tactics | spec |
| 2 | descriptor-native propositions | planned |
| 3 | dependent types | planned |
| 4 | automation | planned |
| 5 | extraction erasure | planned |
| 6 | compiler integration | planned |
