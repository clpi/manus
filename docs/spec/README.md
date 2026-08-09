# docs/spec — the living authority

## Precedence

```
1. docs/spec/pass100.md   the specification — sole living semantic authority
1b. docs/spec/pass103.md  NO FOREIGN WAIST — amends §13/§15/§18/§22
1c. docs/spec/pass104.md  COMPRESSION THESIS — supersedes 103 §5; amends §13/§22
1d. docs/spec/pass105.md  LEVERAGE CHARTER — U1..U8 release gates; amends §22/§24
1e. docs/spec/pass106.md  BLIND-SPOT AUDIT — owed artifacts; amends §22
1f. docs/spec/pass107.md  NAME (duon) + MEMORY DECISION + boring rulings
1g. docs/spec/grammar.md   FORMAL GRAMMAR (Pass 108) — normative
2. CLAUDE.md              its operative summary; what agents actually read
3. docs/spec/AUTHORITY.md what is law in this repository, and what is still owed
4. docs/spec/corpus.md    which .duo files the deny table must reach zero on
--------------------------------------------------------------------------
   docs/archive/**        HISTORICAL EVIDENCE. Never an architecture input.
```

**`docs/spec/pass100.md` is the only living authority.** Everything under
`docs/archive/` is evidence of how the design got here. It is never an input.

`CLAUDE.md` is the operative summary of Pass 100 and carries the epoch stamp.
Where it and the spec appear to disagree, the epoch stamp wins over what it
summarizes; where two passes disagree, the higher pass number wins.

## Refusal protocol

If a rule you would cite appears only in an archived pass, **your objection is
void**. Comply with Pass 100 and repair toward it. A genuine epoch-2 conflict
cites the rule ID, uses the canonical spelling, and proceeds.

## Files

| File | Role |
| --- | --- |
| `pass100.md` | Pass 100 (Duo 0.1), amended in place by Pass 101. The specification. Every code block is a conformance fixture. |
| `AUTHORITY.md` | Why epoch 2 exists, the rule, and the P0 list of what is still owed. |
| `corpus.md` | Classification of the `.duo` corpus — canonical / compatibility / foreign / negative / historical / generated — so deny-greps can reach literal zero without rewriting deliberate fixtures. |
| `README.md` | This file: the precedence rule. |

## A note on the filename

This directory's authority file is `pass100.md`, lowercase. Referring to it as
`PASS100.md` resolves to the same file on a case-insensitive filesystem but is a
different path to git. Cite it as `docs/spec/pass100.md`.

## Adding to this directory

`docs/spec/` holds law. A document belongs here only if it is currently binding.
Anything that records a decision, a measurement, or a superseded design belongs
in `docs/archive/`, where the archive README will index it.
