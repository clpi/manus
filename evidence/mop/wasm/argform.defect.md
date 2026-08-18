# Compiler subset defect found: argument-form method calls return 0

MEASURED (2026-08-18, isolated minimal repros, binary recomputed each run):

`x:hex(b)` where `b` is a pre-bound local — returns 0.
`x:byte(3):hex()` — returns 6. Same relation, same value.

The difference is the ARGUMENT FORM: when a user-declared relation is
invoked with an argument expression (vs the subject-first chain), the
argument arrives as 0/garbage under direct-native. This broke byteat
(`s:hex(s:byte(...))` — nested calls-as-arguments are the documented
GAP-155 refusal class, but THIS is the flat argument form, which
checks clean and silently mislowers).

## Minimal repro (two lines apart in the same program)

```
hex: i64 = (c: i64)
  if c >= 48 and c <= 57
    c - 48
  ...
main: i64 = ()
  x: str = "/tmp/fib.hex":read()
  b: i64 = x:byte(3)        # b = 54
  v1: i64 = x:hex(b)        # v1 = 0   ← WRONG (arg form)
  v2: i64 = x:byte(3):hex() # v2 = 6   ← RIGHT (subject chain)
```

## Impact

- The ingest's byteat broke silently after the EDGE-MAX renames moved
  every call to subject-first — but byteat's BODY still uses the arg
  form internally (`s:hex(s:byte(...))`). Output: all magic bytes = 0,
  "not a wasm module."
- This is also the root cause of the historical "7-arg call helper
  relieved register pressure" observation: argument-form calls with
  several locals may be the same defect presenting as register
  corruption.

## Workaround (applied)

Use subject-chain form at every call site: `s:byte(k):hex()` instead
of `s:hex(s:byte(k))`. byteat becomes:

```
byteat: i64 = (s: str, n: i64)
  s:byte(2 * n - 1):hex() * 16 + s:byte(2 * n):hex()
```

## Handoff

Owner: compiler lane (dnir_lower — argument passing for user relations
under direct-native). The repro is 8 lines. `idol check` accepts both
forms; only execution differs — a silent wrong-answer defect, the
worst class.
