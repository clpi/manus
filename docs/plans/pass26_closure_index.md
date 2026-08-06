# Pass 26 Closure Index

Quick reference for foundational semantic closure. Full constitution: `pass26_foundational_semantic_closure.md`.

## Two unifiers

1. **Semantic boundaries** — first-class values; eliminability, adapter fusion (`pass26_semantic_boundary.zig`)
2. **Semantic domains** — nine domain kinds; boundaries connect domains (`pass26_semantic_domain.zig`)

## Top-ten closure priorities (force first)

| Rank | Topic | Workstreams |
|------|-------|-------------|
| 1 | Descriptor normalization, identity, recursion | WS03–05, WS23 |
| 2 | Canonical dynamic representation | WS25 |
| 3 | Mutability + initialization | WS22, WS24 |
| 4 | GC/native ownership interop | WS26 |
| 5 | Semantic operation + protocol identity | WS01–02 |
| 6 | Semantic domains + boundaries | WS17, WS52 |
| 7 | Stage dependency + meta-circular convergence | WS06, WS30 |
| 8 | Evidence invalidation | WS32, WS51 |
| 9 | ABI/calling convention descriptors | WS35 |
| 10 | Resource + unwind semantics | WS36, WS45 |

## Original five foundations

| # | Topic | Schema |
|---|-------|--------|
| 1 | Semantic operation identity | `pass26_semantic_operation.zig` |
| 2 | Protocol attachment | `pass26_protocol_attachment.zig` |
| 3 | Descriptor identity | `pass26_descriptor_identity.zig` |
| 4 | Semantic boundaries | `pass26_semantic_boundary.zig` |
| 5 | Decision registry | `pass26_decision_registry.zig` |

## Extended schema modules (Part II)

| Module | Covers |
|--------|--------|
| `pass26_runtime_closure.zig` | Init, mutability, dynamic value, GC interop |
| `pass26_recursive_descriptor.zig` | Recursive fixed points |
| `pass26_hash_order.zig` | Hash kinds + iteration order |
| `pass26_evidence.zig` | Evidence invalidation + certainty terms |
| `pass26_abi_resource.zig` | ABI conventions, resources, unwind |
| `pass26_transform_meta.zig` | Transform composition + meta-circular control |

## Scale

- **52 workstreams** (P26-WS01–WS52)
- **28 completion gates** (P26-G01–G30, excluding G18–G19)
- **Flagship proof:** P26-WS21 / P26-G20

## CLI

```bash
zig build pass26-gate
duo catalog | jq '.pass26'
duo catalog audit gate pass26
```

**Agent rule:** query `pass26_decision_registry` and `ten_closure_priorities` before proposing syntax.
