# Compiler defect: application faces lack one relation-role authority

Measured on exact `80fbdb85` (2026-08-18) with isolated programs,
semantic-graph dumps, emitted AArch64, and process results.

## The earlier wrong-answer claim was wrong

For this declaration:

```
hex: i64 = (c: i64)
  if c >= 48 and c <= 57
    c - 48
  ...
```

`c` is the semantic subject slot. Therefore these are equivalent:

```
hex(b)
b:hex()
```

Both execute with result 6 when `b = 54`.

This is a different application:

```
x:hex(b)
```

It supplies subject `x` and an additional ordinary operand `b`. The
relation declares no ordinary operand. Returning 0 is not evidence that
the backend lost `b`: the emitted call passes `x` in `x0` and `b` in
`x1`, and the declared subject slot reads `x0`. The compiler defect is
accepting the excess operand rather than refusing the invalid relation
application.

## The real graph-ownership defect

The two equivalent faces currently execute alike but publish different
graph facts:

| source face | relation | subject | arguments |
|---|---:|---|---|
| `hex(b)` | same exact id | absent | `[b]` |
| `b:hex()` | same exact id | `b` | `[]` |

That means source syntax still decides subject/operand roles. The first
semantic divergence occurs before realization; register allocation and
machine argument passing are downstream witnesses, not the producer.

## Required closure

The relation declaration must publish one ordered slot-role fact. Both
accepted source faces then normalize to the same application facts:

```
relation = hex
subject = b
arguments = []
result demand = single
```

Required controls:

1. `hex(b)` and `b:hex()` publish identical relation, subject, operand,
   result, and demand ids and execute identically.
2. `x:hex(b)` fails closed as an excess-operand application.
3. Poisoning source face, parameter spelling, or AST provenance after
   graph closure does not change realization.
4. Deleting or corrupting the relation-role fact makes the graph refuse;
   no consumer reconstructs roles from argument order or spelling.

Owner: resolver/Sema relation-role publication and the shared semantic
graph. DNIR/native lowering consumes the normalized graph application;
it must not repair source-form ambiguity.

## Ingest consequence

The ingest spelling `s:byte(k):hex()` is canonical because the byte
result is the semantic subject of `hex`. It is not a backend workaround.
