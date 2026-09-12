| field | value |
|---|---|
| title | Compiler defect: application faces lack one relation-role authority |

| # | directive |
|---|---|
| 1 | Measured on exact `80fbdb85` (2026-08-18) with isolated programs, semantic-graph dumps, emitted AArch64, and process results. |

| section |
|---|---|
| The earlier wrong-answer claim was wrong |

| # | directive |
|---|---|
| 1 | For this declaration: |

```
hex: i64 = (c: i64)
  if c >= 48 and c <= 57
    c - 48
  ...
```

| # | directive |
|---|---|
| 1 | `c` is the semantic subject slot. |
| 2 | Therefore these are equivalent: |

```
hex(b)
b:hex()
```

| # | directive |
|---|---|
| 1 | Both execute with result 6 when `b = 54`. |

| # | directive |
|---|---|
| 1 | This is a different application: |

```
x:hex(b)
```

| # | directive |
|---|---|
| 1 | It supplies subject `x` and an additional ordinary operand `b`. |
| 2 | The relation declares no ordinary operand. |
| 3 | Returning 0 is not evidence that the backend lost `b`: the emitted call passes `x` in `x0` and `b` in `x1`, and the declared subject slot reads `x0`. |
| 4 | The compiler defect is accepting the excess operand rather than refusing the invalid relation application. |

| section |
|---|---|
| The real graph-ownership defect |

| # | directive |
|---|---|
| 1 | The two equivalent faces currently execute alike but publish different graph facts: |

| source face | relation | subject | arguments |
|---|---:|---|---|
| `hex(b)` | same exact id | absent | `[b]` |
| `b:hex()` | same exact id | `b` | `[]` |

| # | directive |
|---|---|
| 1 | That means source syntax still decides subject/operand roles. |
| 2 | The first semantic divergence occurs before realization; register allocation and machine argument passing are downstream witnesses, not the producer. |

| section |
|---|---|
| Required closure |

| # | directive |
|---|---|
| 1 | The relation declaration must publish one ordered slot-role fact. |
| 2 | Both accepted source faces then normalize to the same application facts: |

```
relation = hex
subject = b
arguments = []
result demand = single
```

| # | directive |
|---|---|
| 1 | Required controls: |

| # | directive |
|---|---|
| 1 | `hex(b)` and `b:hex()` publish identical relation, subject, operand, result, and demand ids and execute identically. |
| 2 | `x:hex(b)` fails closed as an excess-operand application. |
| 3 | Poisoning source face, parameter spelling, or AST provenance after graph closure does not change realization. |
| 4 | Deleting or corrupting the relation-role fact makes the graph refuse; no consumer reconstructs roles from argument order or spelling. |

| # | directive |
|---|---|
| 1 | Owner: resolver/Sema relation-role publication and the shared semantic graph. |
| 2 | DNIR/native lowering consumes the normalized graph application; it must not repair source-form ambiguity. |

| section |
|---|---|
| Ingest consequence |

| # | directive |
|---|---|
| 1 | The ingest spelling `s:byte(k):hex()` is canonical because the byte result is the semantic subject of `hex`. |
| 2 | It is not a backend workaround. |
