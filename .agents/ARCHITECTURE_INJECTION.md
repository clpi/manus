[/Volumes/d 1/x/idol/.agents/ARCHITECTURE_INJECTION.md#B2D6]
1:# Idol architecture injection — agent orientation
2:
3:**Status:** durable agent orientation only. **Not language law.** If this file
4:conflicts with `docs/spec/law.md` or `docs/spec/constitution.md`, stop and repair
5:this projection.
6:
7:## Preserve the strongest fact already known

If an earlier stage knows token identity, relation identity, subject,
descriptor, pack correspondence, world, effect, witness, demand, or source span,
then a later stage **consumes** that fact. It does not reconstruct it.

A missing fact is preferable to a guessed fact. Fail closed and identify its
missing producer.

**Paste at the top of every agent session (short form):**

Do not port the host compiler. Reduce the required observation to Idol semantics.
Preserve every exact fact already known. One meaning has one id; facts qualify it;
realization carries physical choice. Source syntax, AST kinds, paths, names,
hashes, opcodes, storage classes and backend distinctions are never semantic
authority. A value is not a place. A binding is not storage. A pack is not an
aggregate. A call is not an ABI. A table is not a hash table. A closure is not
a heap object. Unknown is not absent. Demand determines what exists physically.
Prefer no execution, no allocation, no copy, no representation, no runtime and
no instruction whenever semantics permit. Never reconstruct downstream what
upstream already knew. Never add a parallel semantic taxonomy. Never self-host
host implementation patterns merely because they exist. Semantic graph work must
maximize facts while physically using dense ids, packed ranges, columns, views
and exact dependencies. Every transformation preserves application/value lineage
and witness. Every performance change preserves or expands lawful realizations
and accounts for compile cost as well as runtime. Every SHC claim names the
exact production decision that moved from host ownership to executed Idol
ownership. If a required canonical relation/fact is missing, stop and identify
the missing authority rather than inventing a helper or fallback.

---

## Mental model shift
8:
9:Idol is **not** a conventional multi-pass compiler with a pile of named IRs.
10:
11:Idol is an **information-propagation system**:
12:
13:```text
14:observations → identities + facts → demand → lawful realization space → minimum physical work
15:```
16:
17:Stages exist only as **realization choices** over the same semantic graph. A new
18:stage is admissible only when irreducibility is proved; otherwise the capability
19:belongs as relations, facts, observations, demands, laws, witnesses,
20:transformations, worlds, or realizations in the one graph.
21:
22:## Universal optimization state
23:
24:Extend the working state beyond the early tuple:
25:
26:| Dimension | Question |
27:|---|---|
28:| **identity** | What semantic thing is this? |
29:| **facts** | What is known? |
30:| **observations** | What differences can matter? |
31:| **demand** | Which portions/qualities are required? |
32:| **laws** | What transformations/compositions are valid? |
33:| **change** | How do facts/outputs respond to input changes? |
34:| **correspondence** | What is equivalent across transformations/incarnations? |
35:| **search** | What alternative solutions are discoverable? |
36:| **proof** | Which alternatives are actually lawful? |
37:| **cost** | What physical resources does each consume? |
38:| **world** | Under what target/authority/deployment constraints? |
39:| **realization** | Which lawful physical choice wins? |
40:
41:**Directionality is not a second relation identity.** Solving mode
42:(forward/inverse/partial) is a fact over the same semantic relation.
43:
44:## Interoperable algebras (the moat)
45:
46:Make these **interoperable algebras over the same identities**:
47:
48:- relational composition
49:- observation projection
50:- world injection
51:- demand propagation
52:- change propagation
53:- equivalence
54:- realization selection
55:
56:Then compiler optimization, query planning, partial evaluation, incremental
57:computation, automatic differentiation, program synthesis, hardware synthesis,
58:distributed placement, and foreign adaptation become **different queries over the
59:same graph**, not separate semantic kingdoms.
60:
61:## Diagnostic and refusal shape (target)
62:
63:Failures should surface **explanation-minimal** missing or conflicting facts —
64:not cascades of parser/backend symptoms. Optimization refusals likewise: the
65:smallest fact blocking realization R (`alias(x,y) unknown`, not forty downstream
66:reasons). Negative knowledge, exclusion sets, and contradiction as unreachable
67:region are first-class graph facts (see census § XXXV).
68:
69:## Hard rules for agents
70:
71:1. **Do not filter semantic facts at DNIR.** DNIR is a realization artifact;
72:   facts lost there must be justified by demand, not backend convenience.
73:2. **Do not choose relations by hard-coded names in Sema.** Names are subjects;
74:   meaning is relation identity + facts.
75:3. **Do not alter canonical source for immature backends.** Fix realization or
76:   add facts; do not weaken law-facing source to silence a backend.
77:4. **Plugins may propose realization; they may not define meaning.** External
78:   providers supply candidates, laws, witnesses, costs, and applicability — not
79:   identities or relation semantics.
80:5. **Trusted core stays small.** Expensive or learned machinery sits outside;
81:   certificates refine into a small checker (eBPF/Kops/Jitterbug pattern).
82:6. **Boundary contraction is generic.** When an intermediate representation is
83:   unobserved, optimize `g ∘ f` as one semantic unit; cancellation and adjoint
84:   pairs are relation-algebra laws, not ad hoc peephole rules.
85:7. **Observation-relative equivalence is first-class.** Two states may differ in
86:   full value but coincide for the demanded observation (`x ≡_demand y`); this
87:   extends recurrence quotient and supercompilation generalization.
88:
89:## Supercompilation-shaped engine (target shape)
90:
91:Over any demanded graph region:
92:
93:```text
94:observe region
95:→ unfold semantic relations
96:→ propagate exact facts
97:→ recognize recurring semantic state
98:→ generalize when growth threatens (whistle / homeomorphic embedding)
99:→ fold equivalent state
100:→ residualize only demanded semantics
101:```
102:
103:Homeomorphic embedding, memoized configurations, constructor specialization,
104:deforestation-as-consequence, interprocedural fusion, and demand-aware
105:equivalence are **one engine**, not named passes.
106:
107:The same engine admits a **generalize ↔ specialize** axis (anti-unification upward,
108:specialization downward) and **semantic factoring** — store `common skeleton +
109:varying facts` instead of N expanded copies. Re-generalization is a first-class
110:response to specialization explosion and code-size FTCFTW, not an afterthought.
111:
112:## Relational solving (target shape)
113:
114:Same relation, multiple solving modes as facts:
115:
116:- known inputs → outputs
117:- known output → possible inputs
118:- partial input + constraint → complete value
119:- relation + desired property → synthesize witness
120:- “what fact is missing to make this application legal?”
121:
122:## Realization below the binary
123:
124:World/effect facts may select realization at:
125:
126:```text
127:process · unikernel · WASI component · eBPF · firmware · bare-metal · kernel module · GPU · FPGA
128:```
129:
130:Same semantics; different deployment realization. Syscall elimination/fusion,
131:storage topology, network protocol choice, and NUMA/device placement are ordinary
132:physical domains — not new source APIs.
133:
134:
135:## Tonight's priority injection (supersedes fixture-chasing)
136:
137:Read this before any code change. A **passing fixture is not the objective.**
138:
139:**Never repair a downstream consumer when its upstream authoritative fact is wrong.**
140:If lowering needs to filter, reinterpret, recover, or correct graph facts, stop and
141:move the missing fact upstream.
142:
143:| Anti-pattern | Required response |
144:|---|---|
145:| `filterCheckedCallOperands` / AST call recovery in DNIR | Fix `graph.application.arguments` producer; DNIR must trust the pack |
146:| Hard-coded home priority (`iter` before `table`) | Exact descriptor/world/relation facts, or **ambiguous** — never first-match |
147:| `expandableRecordForName` / local-name record inference | Structured value id + descriptor + field facts from the graph |
148:| Shaping canonical `.id` for immature direct lowering | Fix realization unless source violates current law |
149:| Expanding `lib/compiler/monolith.id` toward compiler B | Probe only — B must exercise real home/module composition |
150:| Self-host score green without authority gain | Name the semantic fact gained, not merely the DNB removed |
151:
152:**Commit review question (mandatory before push):**
153:
154:> If I deleted all source spelling, AST shape, filesystem names, and host-local
155:> variable names after resolution, would my change still know enough to make this
156:> decision?
157:
158:If **no**, the change is almost certainly at the wrong layer.
159:
160:**Scoreboard discipline:** treat `gate/selfhost.sh` as a coarse probe with two
161:dimensions — physical reach **and** semantic authority quality. Never copy counts
162:from static reports; use executable ledgers only.
163:
164:**Focused experiment ≠ aggregate evidence.** A gate success on a dirty tree is not
165:proof of incarnation closure.
166:
167:**Central overnight rule (mandatory):** every time a blocker disappears, ask what
168:authority you added. If the answer is "the backend now recognizes another
169:source/AST/storage pattern," the architecture got worse. If the answer is "the
170:graph now knows an exact fact earlier and downstream code became simpler," you
171:are moving toward Idol. Pipeline traversal success is not progress; removing the
172:need for pipeline stages is.
173:
174:See `docs/architecture-negative-controls.md` for the full systemic-misunderstanding
175:catalog and companion gate IDs.
176:
177:## Where to look next
178:
179:- **Negative controls:** `docs/architecture-negative-controls.md` · `gate/architecture-negative.sh` · `gate/architecture-companion.sh`
180:- **Canonical source debt:** `docs/projections/canonical-source-debt.md`
181:- **Capability map:** `docs/history/optimization-frontier-census.md`
182:- **Priority compass:** `docs/AGENT_ALIGNMENT.md`
183:- **Open obligations:** exact current `gaps/GAP-*.md` files
184:- **Supreme law:** `docs/spec/law.md` then `docs/spec/constitution.md`