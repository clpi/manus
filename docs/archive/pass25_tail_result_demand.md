# Pass 25 §5.1 — Tail-Demand Propagation and Result Lineage

**Status:** Adopted design (2026-08-05)  
**Authority:** extends [`pass25_native_semantic_unification.md`](pass25_native_semantic_unification.md) §5  
**Machine-readable:** `src/pass25_tail_result_model.zig`  
**Supersedes:** Pass 23 **P23-D01** naive live-out deferral (backward local search)

## Name this precisely

**Tail-demand propagation** or **result-demand inference** — **not** “return the last assigned variable.”

The latter sounds heuristic. The former is a compiler invariant: explicit **result demand** + **tail region** + **unique proven value lineage** + **control-flow proof**.

Pass 23 correctly rejected arbitrary unique live-out guessing (fragile under refactoring, ambiguous with multiple locals, dependent on heuristic intent). Pass 23 also established that assignments yield their assigned value and that return consumption belongs to the call shape. This document keeps those rules and extends them through tail control-flow regions.

---

## 1. Every value-producing operation has a result

These all produce semantic values:

```duo
x = expression
x += amount
object.field = value
function_call args
a, b = function_call args
```

| Operation | Semantic result |
| --- | --- |
| assignment | value assigned |
| compound assignment | updated value |
| call | return pack |

---

## 2. Only the tail result of a block is eligible as its implicit result

Do **not** infer from arbitrary earlier statements.

```duo
calculate = (x): i64
    value = expensive x
    log value
end
```

The tail statement is `log value`, not `value = expensive x`.

If `log` returns nothing, `calculate` does **not** search backward and return `value`. That would be refactoring-sensitive and surprising.

Instead: propagate **result demand** into the tail statement or tail control-flow region.

**Exception:** result-**transparent** trailing statements (§12) preserve an established lineage without stealing tail position.

---

## 3. Explicit return descriptors create result demand

```duo
double = (x): i64
    value = x * 2
end
```

The body must yield `i64`. The tail assignment yields the assigned `i64`. No redundant trailing `value` read.

Descriptor symmetry:

| Descriptor | Demand |
| --- | --- |
| `:i64` | one `i64` position |
| `:i64, Error` | two positions |
| `:void` | zero positions |

---

## 4. Caller consumption affects realization, not source meaning

```duo
double 10        -- discard consumption
x = double 10     -- single consumption
```

The semantic function still yields `i64` in both cases. Realizations differ:

| Context | Lowering |
| --- | --- |
| consumed call | compute → register return → bind |
| discarded call | preserve effects → discard value before ABI |
| discarded pure call | dead call elimination when legal |

`CallShape.return_consumption` and return-pack specialization select **representation**; they do **not** redefine the callable’s principal semantic pack.

---

## 5. Tail control-flow: loop-carried values (supersedes P23-D01)

```duo
factorial = (n): i64
    value = 1
    for i = 2, n
        value *= i
    end
end
```

- Result demand: one `i64`
- Tail region: the loop
- Unique loop-carried chain: `value₀ = 1` → `valueₙ₊₁ = valueₙ * i` → `phi(initial, updated)`
- Zero iterations → seed `1`

This is control-flow proof, not “guess the last local.”

### Ambiguity — diagnose, never guess

```duo
bad = (x): i64
    a = compute_a x
    b = compute_b x
    for item in items
        update item
    end
end
```

Diagnostic:

```
tail region does not determine one i64 result
available live-outs:
  a: i64
  b: i64
return one explicitly or make one the tail-carried value
```

---

## 6. Tail-demand rules A–H

| Rule | Pattern | Result |
| --- | --- | --- |
| **A** | tail assignment | assigned value |
| **B** | tail compound assignment | updated value (no reload) |
| **C** | tail call | return pack forwarded |
| **D** | tail branch | SSA phi of branch tails |
| **E** | tail if + unique carried assign | merged assigned value |
| **F** | tail loop + unique carried assign | final loop-carried value |
| **G** | multi-position loop-carried | one chain per demand position |
| **H** | unconsumed tail call | effects preserved, values discarded per demand |

### Rule B lowering example

```duo
Counter:increment = (): i64
    self.value += 1
end
```

```
old = load self.value
new = old + 1
store self.value, new
return new
```

### Rule G example

```duo
stats = (values): i64, i64
    total = 0
    count = 0
    for value in values
        total += value
        count += 1
    end
end
```

Two demand positions → two loop-carried chains → `total, count`.

---

## 7. Functions without explicit return descriptors

Latent tail result only when syntactically/structurally obvious:

- tail expression / assignment / compound assignment / call
- tail branch with compatible exits
- tail loop with one unambiguous carried result

**Conservative policy** when the function is exported, reflected, address-taken, crosses dynamic boundaries, or is stored in heterogeneous tables: record a stable **principal return pack**; do not change it because current callers discard results.

---

## 8. Consumer-directed specialization

Each callable has a **principal semantic result pack**. Each call declares expected/consumed positions. Realizations may omit unconsumed work:

```duo
analyze = (input)
    result, diagnostics, profile = analyze_impl input
end
```

| Call | Specialization |
| --- | --- |
| `result = analyze input` | first position only |
| `result, diagnostics = analyze input` | first two |
| `analyze input` | discard all positions |

Internal identities like `analyze$result`, `analyze$discard` are **conceptual** — not source syntax or user-facing API names.

---

## 9. Unconsumed assignments and calls

Distinguish:

- operation **effects**
- produced **semantic value**
- **storage** effect
- value **consumption**
- binding **liveness**

```duo
self.count = compute()
```

Store effect remains even when assignment result is unconsumed.

Pure dead binding + pure initializer → whole assignment may erase. Effectful initializer → read remains, binding/result may disappear.

### Unconsumed calls

| Case | Action |
| --- | --- |
| pure + unused | dead call elimination |
| effectful + unused | preserve effects, erase result handling |
| effectful + expensive unused return | omit return object construction when legal |

---

## 10. Void and discard semantics

```duo
notify = (message): void
    send message
end
```

Evaluate call, preserve effects, discard all returned values, reject forms that violate void demand. May specialize to effect-only callee path.

---

## 11. Transparent trailing statements

```duo
calculate = (x): i64
    value = expensive x
    debug value
end
```

May return `value` when `debug` is **result-transparent**:

- zero result positions
- does not alter demanded result value
- effects ordered after production
- all exits preserve same result
- not a control-flow terminator

Still ambiguous:

```duo
calculate = (x): i64
    a = expensive_a x
    b = expensive_b x
    debug x
end
```

Same-lineage update is allowed:

```duo
calculate = (x): i64
    value = expensive x
    value = alter value
    debug value
end
```

Returns latest node in the **same SSA lineage** — not “last matching assignment.”

---

## 12. Result lineage (SSA-native)

```duo
factorial = (n): i64
    value = 1
    for i = 2, n
        value *= i
    end
    trace value
end
```

Lineage graph:

```
demand: i64
value₀ = 1
valueᵢ₊₁ = valueᵢ * i
result = loop_phi(value₀, valueᵢ₊₁)
trace(result)   // transparent
return result
```

---

## 13. Dynamic, foreign, and reflection

- Dynamic calls: canonical principal pack + discard after return when unknown
- Exports: stable ABI from declared/inferred principal pack; internal clones may specialize
- Reflection exposes: semantic returns, available realizations, consumed positions at call, physical ABI

---

## 14. What not to do

| Rejected | Why |
| --- | --- |
| last compatible local backward search | fragile |
| `result =` magic binding | new category |
| name/capitalization magic | non-structural |
| caller redefines semantic returns | breaks principal pack |
| silent ambiguity resolution | unpredictable |
| forced unused tuple construction | performance + semantics |

Registry: `pass25_tail_result_model.rejected_heuristics`

---

## 15. Tooling (LSP / MCP)

Expose:

- semantic return pack
- result-demand graph
- result lineage nodes
- consumed positions at call
- discard specialization selection
- erased result computations
- transparent trailing statements
- ambiguity candidates
- physical ABI realization

---

## 16. Implementation order

| Phase | Work |
| --- | --- |
| **M0** | Constitution + schema + gates (this doc, `pass25_tail_result_model.zig`) |
| **M1** | Rules A–C in sema + DNIR (tail assign/call + consumption) |
| **M2** | Rules D–G: branch/loop phi, ambiguity diagnostics in sema |
| **M3** | Transparent trailers, export stability, reflection + LSP/MCP |

Gates: **P25-G15** (rules A–H schema), **P25-G16** (loop/branch phi + diagnostics)

---

## Governing principle

> A function body is analyzed under a **result demand**. Tail expressions, assignments, calls, branches, and control-flow regions may satisfy that demand through a **unique proven value lineage**. Call-site consumption then specializes how much of that semantic result is actually computed, represented, and returned.

This gives minimal syntax:

```duo
factorial = (n): i64
    value = 1
    for i = 2, n
        value *= i
    end
end
```

And maximum performance:

- result consumed → loop-carried value returned directly
- result discarded → no return ABI
- pure + discarded → entire call removed when legal
- effectful + discarded → effects only, return construction erased

Symmetric, SSA-native, return-pack-aware, consistent with Duo’s call algebra.
