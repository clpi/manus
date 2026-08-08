# Pass 86 — Modes Are Descriptors: `from(mode)` Replaces Compound Names

> **Status:** canon (amends Pass 85 Rung 3 in place).
> **Measured against the compiler 2026-08-07** by `scripts/census/modes.duo`.
> **5 of 18 rows implemented, two of which are the `to(str)` controls.**
> **`from` does not exist in any spelling. Neither does the ladder's first rung.**
> The naming rule is therefore correct and **currently unapplicable** — see §5.

---

## 1. The ruling

The objection is correct and it is a LAW-STRATA-2 violation hiding in *name
space*: `from_polar`, `of_hex`, `new_ms` smuggle a semantic parameter into an
identifier — **name mangling is flattening**. "Polar" is a decision; decisions
are levels; a level fused into a name can't be passed, enumerated, composed,
refined, or lifted. The litmus convicts it directly: `point:from(polar)` — the
prefix means something, so it's a level.

> **Constructor modes are descriptors, and the mode is a curry level of the
> `from` family: `target:from(mode)(args…)`, dual `mode_value:to(target)`.**
> Compound mode names (`from_x`, `of_x`, `new_x`, `with_x`-as-mode) are denied;
> only genuinely atomic nouns (`identity`, `origin`, `zero`, `unit`) remain as
> plain statics, because they name a *value*, not a smuggled parameter.

## 2. The table, corrected (Pass 85 Rung 3 superseded)

```
✗ point.from_polar(r, t)       ✓ polar{ r, t }:to(point)        -- polar is a TYPE
                               ✓ point:from(polar)(r, t)        -- mode is a LEVEL
✗ color.of_hex("#fa0")         ✓ color:from(hex)("#fa0")        -- hex = str & hex_valid
                               ✓ h:to(color)   -- where h: hex  -- mode is a REFINEMENT
✗ Duration.new_ms(n)           ✓ 150 * ms                       -- units won this already
                               ✓ duration:from(ms)(150)         -- ms IS a descriptor
✗ Matrix.new_identity(n)       ✓ matrix.identity(n)             -- atomic noun: names a value
```

Both faces are the same edge (`from` with source-descriptor level ≡ `to` with the
operand constructed) — declare either orientation once, get both, plus the
inverse (`p:to(polar)`) where round-trip evidence holds.

**Measured:**

| Row | Form | State |
| --- | --- | --- |
| `P86-C1` | `to(str)(42)` — section face | **LIVE** |
| `P86-C2` | `(42):to(str)` — subject face | **LIVE** |
| `P86-6` | `matrix.identity(n)` — the permitted atomic noun | **LIVE** |
| `P86-11` | `hex = str & hex_valid` — refinement type declares | **LIVE** |
| `P86-16` | `@{ ..self, x = 9 }` — spread revision | **LIVE** |
| `P86-1` | `polar{ r, t }:to(point)` | SPEC |
| `P86-2` | `point:from(polar)(r, t)` | SPEC |
| `P86-3` | `color:from(hex)("#fa0")` | SPEC |
| `P86-4` | `duration:from(ms)(150)` | SPEC |
| `P86-5` | `150 * ms` | SPEC |
| `P86-14` | `c:to(temp)` — conversion to a *user descriptor* | SPEC |

The `to`/`from` asymmetry is the headline. Pass 86 rules them **one edge,
oriented**. `to` works in both faces — but only against **primitives**.
`c:to(temp)` where `temp` is a user descriptor does not resolve, and `from` does
not resolve in any spelling. So of the "one edge, declare either orientation and
get both", what exists today is one orientation against one kind of target.

## 3. What decomposition buys — measured

The argument for Pass 86 is algebraic: decomposing the mode is worth doing
because sections, enumeration, refinement and lifting all open up. That argument
is sound, and **none of those surfaces exist yet**. A `from(mode)` that parsed
but could not be partially applied would satisfy the letter of the ruling and
none of its reason, so these rows matter more than `P86-2` does.

| Surface | Form | State |
| --- | --- | --- |
| Sections | `pairs:map(point:from(polar))` | SPEC (`P86-8`; `map` is itself missing) |
| Enumeration | `point@from` as a browsable subtree | SPEC (`P86-9`) |
| Composition | `from(polar & normalized)` | SPEC (`P86-10`) |
| Refinement | `hex = str & hex_valid` | **LIVE** (`P86-11`) |
| Lifting | `lift(seq)` | SPEC (`P86-12`) |

Refinement declaring is the one real foothold: `hex = str & hex_valid` resolves
today, so the *mode type* half of the ruling is buildable even though the `from`
level that consumes it is not. That is the cheapest place to start.

## 4. The complete constructor ladder — measured

```
parts in hand         →  desc{ positional }                      lexer{ src, "lit.duo" }
one source value      →  the conversion edge                     cels:to(temp)
a MODE of sources     →  the mode is a descriptor at a LEVEL:    point:from(polar)(r, t)
                         target:from(mode)(args) ≡                polar{ r, t }:to(point)
                         mode_value:to(target)
atomic named values   →  noun statics                            matrix.identity(n)
world involved        →  action-named + pack                     file.open(path): file | Error
copy-with-changes     →  spread revision                         @{ ..self, x = nx }
```

| Rung | State | Measured |
| --- | --- | --- |
| parts in hand | **BROKEN** | `lexer{ "a", "lit.duo" }` emits `lexer(...)` and never defines it |
| one source value | **SPEC** for user descriptors | `to(str)` LIVE; `c:to(temp)` unresolved |
| a mode of sources | **SPEC** | `from` unresolved in every spelling |
| atomic named values | **LIVE** | `m.identity(3)` → `3` |
| world involved | **SPEC** | `f(): T \| nil` does not compile (`P86-15`; = `FF-17`) |
| copy-with-changes | **LIVE** | `@{ ..self, x = 9 }` → `9` |

**The ladder's first rung does not compile.** Positional descriptor fill —
`lexer{ src, "lit.duo" }`, named in Pass 83 §0 as "POSITIONAL fill is canon" —
fails with `call to undeclared function 'lexer'`, byte-identical to the named-
field form. This is the same defect as Pass 81's `CALL-1` and
`spec_conformance.duo`'s `FF-13`: a descriptor has no default construction
realization, so codegen emits a call to a symbol nothing defines. Two of the six
rungs work; the two that the HOT SCREEN puts first do not.

## 5. The corpus, and why the repair is blocked

Pass 86 §4 asks codex to gain a recognizer: a static whose name embeds a
descriptor-like suffix → the `from(mode)` repair. Measured, `lib/std` carries
**24 Duo-authored declaration sites** in the banned shape:

- **10 bare `from_*`** — `from_header`, `from_source` (`ffi_gen.duo`),
  `from_json_schema_string`, `from_protobuf_string` (`schema_gen.duo`),
  `from_string` (`bytes.duo`), `from_timestamp` (`datetime.duo`), `from_pairs`
  (`table.duo`, `ml/data.duo`), `from_name` (`os/signal.duo`), `from_array`
  (`ml/vision.duo`).
- **14 `X_from_Y`** — `color_from_hsv`, `key_from_bytes`, `f64_from_bits`,
  `f32_from_bits`, `wide_from_bytes`, `flags_from_mask`, `type_from_name`,
  `line_from_points`, `plane_from_points`, `tensor_from_fp16`,
  `sample_from_probs`, `texture_from_data`, `concept_contract_from_checks`,
  `proj_params_from_lparen`.

Out of scope, counted separately and deliberately not repaired: FFI symbol names
(`lua_val_from_int`, `pcre2_match_data_create_from_pattern_8`) are foreign ABI
spellings, not Duo constructors. Also excluded: `_ms`/`_ns`/`_sec` **field** names
(`timeout_ms`, `elapsed_ms`, `now_ns`) — 14 of them, all fields or locals rather
than constructor modes. Whether a unit smuggled into a *field* name is the same
violation as one smuggled into a *constructor* name is a live question the ruling
does not answer; it is left open rather than guessed.

**The repair cannot be applied to any of the 24.** Every one would move to
`target:from(mode)(args)`, which does not resolve, or to `mode{...}:to(target)`,
which needs both descriptor construction (broken) and `to` against a user
descriptor (missing). Applying Pass 86 today replaces working code with code that
does not compile.

This is the GAP-14 pattern exactly — a canonical form ruled in, with the vestige
it replaces still being the only thing that works — and it is recorded as a
stop-work item for the same reason.

## 6. What an agent should write today

- **Do not repair `from_*` names.** The target form does not exist. The 24 sites
  stay as they are until `from` resolves; the recognizer can be *written* now but
  must not *auto-repair*.
- **Do not write `desc{ ... }` against a declared descriptor**, positional or
  named. It compiles to a call to an undefined symbol. Brace application against
  a **function** works and is the only live brace-call.
- **Do not write `x:to(UserDescriptor)`.** `to` resolves against primitives only.
- **Atomic noun statics are correct and safe** — `matrix.identity(n)`,
  `point.origin()`. This is the one rung of the ladder that fully works. Annotate
  the lambda (`(n: i64): i64`) or you hit the GR-001 bare-function trap, which is
  not a Pass 86 failure.
- **`@{ ..self, x = nx }` works.** Copy-with-changes is safe to write today.
- **Refinement types declare** — `hex = str & hex_valid` resolves. Mode *types*
  can be built ahead of the `from` level that will consume them.

Run `duo run scripts/census/modes.duo` before trusting any row.

## 7. Related

- `scripts/census/modes.duo` — the gate, floor pinned at 5/18.
- `docs/plans/pass81_family_registry.md` §2.6 — `from` as the missing half of the
  `to`/`from` edge, measured there as `FROM-1`.
- `GAP-035` — descriptor bodies accept type slots only. Blocks the `call` edge
  that construction (rung 1) is defined in terms of.
- `GAP-029` — no legal spelling for a string built from a call result. Filed from
  this diff; §1's concat ban and TMP-1 are jointly unsatisfiable while expression
  holes stay literal.
- `spec_conformance.duo` `FF-13`, `FF-17` — rung 1 and the result pack, measured
  independently and agreeing.
