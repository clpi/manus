"""Per-optimization differential test-case generators.

Contract for every opts/<name>.py module:
  - directed() -> list[case]: hand-written edge/adversarial cases.
  - gen(rng, n) -> list[case]: n randomized cases (seeded).
  - case = dict(id, idol, ret, cbody, cret, signed, full, note) where:
      idol   : full Idol source; LAST LINE must be the bare variable `ret`
               (required for --full byte-slice observability).
      ret    : observed variable name (Idol side).
      cbody  : C statements computing everything (declares all vars).
      cret   : C expression for the observed value.
      signed : True if the observed value is a signed long long.
      full   : True to run byte-slice (full 64-bit) observability.
      note   : free text; "known-..." buckets map to documented limitations.
  - Generators must not use the variable name `q` (reserved by common.py).
  - Idol subset reminder: one operator per line, no parens, no unary
    minus (write `0 - N`), while-loops only as `while var < bound`.
"""
