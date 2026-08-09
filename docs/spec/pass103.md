# Pass 103 — The Native Descent: No Foreign Waist

**Epoch 2 · Amends Pass 100 §13, §15, §18, §22 · Higher pass number wins.**

Pass 102's "lowering to C" quietly installed a foreign language at the narrowest
point of the pipeline. That contradicts the project's own axis (A7 NATIVE-FIRST,
G11 monoglot) one level below where the monoglot mandate had been looking.

## The ruling

> **NO FOREIGN WAIST.** The end-to-end path — source → graph → realization →
> flow → instruction selection → machine encoding → container → executable — is
> Duo data transformed by Duo edges at every stage. **C is never an
> intermediary; LLVM is never a dependency; WASM is a *target* (bytes we emit),
> never a runtime we stand on.** Foreign *code* appears in exactly two places,
> both already licensed and both shrinking: the bootstrap ledger (until the
> fixed point, G9) and the differential harness (foreign toolchains as
> comparison *oracles* in CI — test equipment, never the shipping path).
> Emitting C/TS/Rust remains available as an **export projection** for interop
> consumers — a product feature at the edge, not a stage in the middle.

## 1. The pipeline, entirely as families

Every stage is DNIR nodes in, DNIR nodes out, transformed by browsable,
overridable relation edges — the compiler's spine is the same trie machinery as
everything else:

```
graph        DNIR as shown in Pass 102 (descriptors, edges, facts, checks)
realize      demand resolves faces, selects representations, spends facts;
             obligations discharged; witnesses deposited
flow         .flow nodes: the dataflow/control form — still tables (blocks,
             values, places, effects as node kinds; facts still attached)
lower(t)     instruction selection PER TARGET as edges:
             lower(arm64)(sub) = … · lower(x64)(sub) = … · lower(wasm)(sub) = …
             rewrite edges do peephole/scheduling; registers are PLACES and
             allocation is realization over place facts
encode(t)    instruction → bytes: encode(arm64)(instr) = bitfield assembly
             over the instruction DESCRIPTORS
encode(fmt)  container emission: encode(elf) · encode(macho) · encode(pe) ·
             encode(wasm) — file formats are shape declarations with layout
             facts; writing them is the codec matrix (N6) doing its day job
link         semantic linking (T2) natively: artifact@surface at compose time;
             the "linker" is graph merge + fingerprint resolution + relocation
             edges — a Duo program like everything else
```

The compiler has no phase that is not a family; extending a target, overriding a
lowering, or asking `why` about an instruction choice is the same act at every
altitude.

## 2. The worked example (span width to bytes, no C anywhere)

```
-- flow node (post-realization; facts spent are recorded on the witness)
{ kind = .flow, fn = width, blocks = {
    entry = { args = { s = place(span & reg_pair) }
              body = { r = { op = sub, of = u32, args = { s.stop, s.start } } }
              exit = { op = ret, val = r } } } }

-- instruction selection: one edge, target-keyed
lower(arm64)(sub) = (n) instr{ mnem = .sub, w = 32, dst = n.place,
                               lhs = n.args[0], rhs = n.args[1] }

-- the instruction set is DATA: descriptors with encoding layouts
arm64.sub: {
    mnem: .sub
    w: 32 | 64
    layout = bits{ [31] = w == 64, [30, 24] = 0b1001011,
                   [20, 16] = .rhs, [9, 5] = .lhs, [4, 0] = .dst }
}

-- encoding = the layout fact consumed by the codec machinery
encode(arm64)(i: instr): u32 = i:to(arm64[i.mnem])      -- CDR + layout facts

-- result: one u32 in the .text section node, witness attached
{ kind = .code, target = arm64, bytes = { 0x4b000020 },
  witness = { spent = { sealed, bounded }, chose = { reg_pair, no_check } } }
```

**The instruction set is a descriptor family with layout facts, so machine
encoding is the same codec derivation that encodes wire structs** —
`encode(arm64)` is not a special engine, it is N6 pointed at silicon. Register
allocation is place realization. Peephole is `rewrite`. The backend is small
because it is mostly *reuse*.

## 3. Machine specifications: ingested as data

Instruction descriptors are authored or **generated from vendor
machine-readable specs** (ARM MRS XML, riscv-opcodes, x86 SDM tables) by
ingestion — arriving as rung-6 *data* with `trust = .declared`, promoted
per-instruction as differential execution against hardware validates them.
Ingesting a spec sheet is reading the world, not standing on a foreign language:
the monoglot line is drawn at *code in the pipeline*, and a table of bit layouts
is data on either side of it.

## 4. Execution during compilation, and the fixed point

Staged evaluation (constant folding as facts, `check` at compile stage, graph
iteration) requires running Duo bodies — so the graph engine contains **the Duo
evaluator, in Duo**: bodies are tables; evaluating tables is a fold; it is the
least exotic component in the system. The bootstrap story is exactly G9,
sharpened: the S0 host implements *only* enough evaluation to run the evaluator;
the evaluator runs the realizer; the realizer + backend emit the toolchain; the
toolchain rebuilds itself byte-identically (the fixed point); the ledger hits
zero and **native attainment is total** — at which point "no foreign waist" is
not a policy but a measurement.

## 5. The honest bill (what refusing LLVM costs)

> **SUPERSEDED BY PASS 104.** The bill exists; the CURRENCY CHANGED. This
> section prices the backend in engineer-decades, which is the incumbent's
> unit and the wrong one: the decades went to semantics archaeology, mutable-IR
> pass coupling, and a compatibility museum — three sinks Duo deletes by
> construction — plus serial lore accumulation, which becomes search under
> gates. See `docs/spec/pass104.md`; the argument below is kept for its
> reasoning, not its estimate.

Owning the descent means owning what LLVM gave for free: decades of instruction
scheduling, allocation heuristics, and peephole lore. Three reasons the bill is
payable, stated as claims that pay the toll like all others:

1. **The leverage lives above.** Fact-driven wins (demand erasure, upgraded
   asymptotics, fusion, sealed dispatch, layout) are graph-level and survive a
   modest backend; a simple, *witnessed* backend under a knowledge-rich middle
   beats a brilliant backend under an amnesiac one for exactly the workloads Duo
   targets, and Ward-vs-wart is the referee.
2. **The surface is smaller than it looks** — selection + allocation + peephole
   over a data-described ISA, with the codec matrix and place machinery already
   built.
3. **The harness keeps us honest** — foreign compilers remain as *oracles*
   (differential output, performance baselines), so parity is measured
   per-workload, and any gap is a ranked worklist of rewrite edges, not a leap
   of faith.

The ledger takes the residue: backend maturity is the longest line item in §22
and is now labeled as such.

## 6. Amendments

- **Pass 100 §13** gains the waist clause: the descent is Duo to the byte;
  foreign toolchains are oracles; C emission is an export product.
- **Pass 100 §18**'s emission line is reframed: projection pairs = *interop
  exports* + ingestion — never the compile path.
- **Pass 100 §22** ledger adds **backend maturity** as the marquee line item and
  the evaluator as owed.
- **Pass 102**'s C block is re-captioned as the export projection it should
  always have been, with §1 above as the native path beside it.
- **Graveyard**: C-as-intermediary, LLVM-as-dependency, runtime-hosted
  execution.
- `CLAUDE.md` regenerated in the same commit (§19 epoch protocol: a ruling
  without regeneration is unshipped).

## 7. What this repository must now repair toward

Recorded here because the ruling has immediate, measurable consequences in the
tree as it stands:

- `--backend=c` used as a FALLBACK in the middle of a compile is the foreign
  waist, by name. `--backend=direct` is not an alternative backend; it is the
  path. The native census is therefore not an optimization metric — it measures
  attainment, and 100% is the fixed point, not a stretch goal.
- `emitReqModuleC` + `directLinkInputs` compile `req`'d Duo modules to C objects
  and link them. That is a foreign waist in the middle. `spliceReqModules`
  (absorbing a module into the program's own native object) is the
  Pass-103-aligned repair and should grow until the C path is unnecessary.
- The differential harness comparing `--backend=direct` against `--backend=c` is
  EXPLICITLY LICENSED by §5 above: C is the oracle, test equipment, never the
  shipping path. `zig build abi-matrix` and the native differential stay.
- `src/*.zig` is the bootstrap ledger (G9) and shrinks toward the fixed point;
  it is not a violation, it is the licensed exception with a termination
  condition.
