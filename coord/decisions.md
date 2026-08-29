# Idol kernel decisions (Idol-0 freeze candidate)

Date: 2026-08-29
Authority: derived from the foundational audit of 2026-08-29. Each
decision must be ratified by the human before it is applied to the
corpus. Decisions are versioned corpus changes, not silent
reinterpretations.

The fifteen decisions below cover the hazards in §2.3 of the audit.
Each decision is a one-sentence rule. A positive fixture and a
negative fixture make the rule testable.

## Delimiter disambiguation (1-3)

D1. `x : point = { ... }` means **subject declaration** of `x` as a
    `point`. Descriptor annotations on bindings are dropped from the
    Idol-0 kernel. Positive: `a : i64 = 5`. Negative: `a : i64 = 5`
    treats the `i64` as anything other than the subject.

D2. Line-leading infix continuation: a deeper-indented line that
    begins with an infix operator (any of `+ - * / % ^ # & | < > = ~ ; :
    , .`), `.`, `:`, `(`, or `[` continues the previous expression.
    Unary prefix at continuation position is parsed as binary.
    Positive: `x = 1\n+ 2` parses as `x = 1 + 2`. Negative: a
    leading `-` at continuation is unary minus on a fresh expression.

D3. Application requires no whitespace between callee and `(`.
    Space before `(` after a control head begins the parameter pack.
    Positive: `f(x)` is a call. Negative: `f (x)` after `for(...)`
    begins the pack, not a call.

## Declaration head (4)

D4. `codec.encode = ...` as a declaration head is **forbidden** in
    Idol-0 with a diagnostic. Members are declared inside `{}`.
    Positive: `codec { encode = ... }` is valid. Negative:
    `codec.encode = ...` outside `{}` is rejected.

## Result packs and error idiom (5)

D5. Functions return a single value; multi-return is a `(value, error)`
    pack. No try/catch, no exceptions. `return (x, nil)` for success,
    `return (nil, e)` for failure. The error is checked with pattern
    match, never with `pcall`. Positive: `v, e = read(p); if e ...`.
    Negative: `pcall(read, p)` is rejected.

## Forbidden tokens (6)

D6. `match`, `try`, `catch`, `defer`, `async`, `await`, `FFI syntax`
    are deleted from Idol-0. `if/else` chains only. Positive:
    `if cond ... else ...`. Negative: `match v { ... }` is rejected
    with a diagnostic.

## Typing (7)

D7. Idol-0 and Idol-1 use one uniform tagged representation:
    `i64`, `f64`, `text`, `table`, `callable`, `nil`. Descriptor
    annotations are parsed and minimally checked. Static inference
    is Idol-1. Positive: `x : i64 = 5`. Negative: `x : {i64, f64}`
    is rejected (record types are Idol-1).

## Memory (8)

D8. Arena per compilation, never free, for Idol-0 and Idol-1. A
    compiler is a batch process. Real ownership or GC is a
    post-fixed-point decision. If Idol-0 emits C, Boehm GC is an
    acceptable stopgap. Positive: `arena:alloc()`. Negative:
    `free(arena:alloc())` is rejected.

## Table iteration (9)

D9. Insertion-ordered tables. Non-negotiable for self-host
    verification (byte-identical stage 2 and stage 3 outputs).
    Positive: `t = {1, 2, 3}; t:each()` yields `[1, 2, 3]`.
    Negative: `t` with hash-keyed iteration is rejected.

## Modules and reach (10)

D10. Idol-0: all `.id` files in one directory form one home. A
    subdirectory `x/` is reachable as `x.name`. Duplicate names
    across files in one home are an error. Positive: `a.id` with
    `a.foo = 5` reachable as `a.foo`. Negative: two `.id` files in
    one directory both defining `foo` is an error.

## Worlds (11)

D11. Idol-0 has one implicit root world. Builtins `read`, `write`,
    `args`, `exit`, `env`. The `@` grammar is Idol-1. Positive:
    `stdout:write("hi")`. Negative: `@io` is rejected.

## Specialization (12)

D12. Idol-0 keeps `subject:relation = (params)` and ambient
    `:relation()` because they are the method mechanism. The
    `relation(levels) =` and `.field` section syntax are Idol-1.
    Positive: `p:from(mode)(...)` is valid. Negative:
    `r(2) = ...` is rejected.

## Numerics (13)

D13. i64 wrapping arithmetic. f64 IEEE-754. `text` is UTF-8 and the
    only string type. Table equality is identity. Positive:
    `9223372036854775807 + 1` wraps. Negative: arbitrary-precision
    integers are Idol-1.

## Idioms still in force

The remaining spec rules (one lowercase word, no mashed compounds,
no underscores, native uppercase zero, no second IR, no boolean
mirrors, no bridges/adapters/registries) continue to apply. The
Idol-0 freeze ratifies the kernel decisions above; the migration of
the existing `lib/compiler/token.id` to one-word names is a
multi-ticket workstream tracked separately.


## Pre-freeze debt inventory

The repo as of `237b25b5` carries the following spec debt. Each
entry names the file, the mashed word, and the proposed
decomposition. The migration is **not** a single PR — it is
versioned corpus changes per the foundational audit, not silent
reinterpretation.

| File | Word | Decomposition |
|---|---|---|
| `lib/compiler/token.id` | `idbody` | `id` + `body` (separate relation + fact) |
| `lib/compiler/token.id` | `zigbody` | `zig` + `body` |
| `lib/compiler/token.id` | `tabletext` | `table` + `text` |
| `lib/compiler/token.id` | `roleassoc` | `role` + `assoc` |
| `lib/compiler/token.id` | `rolebit` | `role` + `bit` |
| `lib/compiler/token.id` | `roleprefix` | `role` + `prefix` |
| `lib/compiler/token.id` | `roleprojection` | `role` + `projection` |
| `lib/compiler/token.id` | `roleliteral` | `role` + `literal` |
| `lib/compiler/token.id` | `roleparameter` | `role` + `parameter` |
| `lib/compiler/token.id` | `rolepattern` | `role` + `pattern` |
| `lib/compiler/token.id` | `rolepostfix` | `role` + `postfix` |
| `lib/compiler/token.id` | `roleprecedence` | `role` + `precedence` |
| `lib/compiler/token.id` | `rolequoted` | `role` + `quoted` |
| `lib/compiler/token.id` | `roledescriptor` | `role` + `descriptor` |
| `lib/compiler/token.id` | `rolebodystart` | `role` + `bodystart` |
| `lib/compiler/token.id` | `rolecompatonly` | `role` + `compatonly` |
| `lib/compiler/token.id` | `rolebeginexpr` | `role` + `beginexpr` |
| `lib/compiler/token.id` | `assocname` | `assoc` + `name` |
| `lib/compiler/token.id` | `_nametext` | `_` + `name` + `text` |
| `lib/compiler/token.id` | `_relationname` | `_` + `relation` + `name` |
| `lib/compiler/token.id` | `_unaryname` | `_` + `unary` + `name` |
| `lib/compiler/token.id` | `_zigenum` | `_` + `zig` + `enum` |
| `lib/compiler/token.id` | `_zigescape` | `_` + `zig` + `escape` |
| `lib/compiler/token.id` | `_zigname` | `_` + `zig` + `name` |
| `lib/compiler/token.id` | `_wordcount` | `_` + `word` + `count` |
| `lib/compiler/token.id` | `kindalias`..`kindawait` (90+ entries) | `kind` + word (per-token decomposition) |
| `lib/compiler/token.id` | `kindeof` (output projection) | `kind` + `eof` -> split into kind index + is_eof fact |
| `lib/compiler/token.id` | `beginexpr` (output projection) | `begin` + `expr` -> split into begin index + is_begin_expr fact |
| `gate/idiom.id` | `checkns`, `checkpred` | decompose: `check` + namespace concept; `check` + predicate concept |
| `gate/idiom.id` | `nspace`, `consumerules`, `graphrules`, `badstem`, `boundface`, `cardinalstem`, `collisionstem`, `commentline`, `compound`, `consumer`, `digitonly`, `docline` | per-id decomposition |
| `gate/host.id` | `hostr`, `scandr` | `host` + rule, `scan` + dryrun concept |
| `gate/census.id` | `filescan` | `file` + `scan` |
| All gate `*.id` | `audit`, `scan`, `rule`, `edge`, `home`, `adj`, `route` | conformant single words |
| `scripts/ingress/*` (pre-fix) | `endpointwrite`, `endpointread` | decomposed to `say`, `fetch` (commit `1080cbd9`) |
| `tools/wasm/ingest.id` | `emit` | conformant single word |

The migration is large. Per the foundational audit, the approach is
"expect two or three amendments to the freeze and treat each as a
versioned corpus change with a reason, not a silent reinterpretation."

The first migration ticket is `coord/tasks.jsonl` `migrate-token-id-body-2026-08-29`
(decomposing `idbody` and `zigbody` in `lib/compiler/token.id` while
preserving the byte-identical grammar projection gate via the C
backend). It is a self-contained one-week workstream that exercises
the full freeze/fix/ratify loop with a real downstream consumer.


## Ratification log

- 2026-08-29: D1-D13 drafted from the foundational audit. Awaiting
  human ratification.
