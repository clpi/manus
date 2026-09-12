| field | value |
|---|---|
| title | Idol — Authoritative Language and Architecture Specification |
| status | SOLE NEW-AGENT BOOTSTRAP |
| purpose | LANGUAGE LAW + COMPILER LAW + REPOSITORY LAW + CONVERGENCE LAW |
| mode | FAIL CLOSED |

| # | directive |
|---|---|
| 1 | This document describes the intended language and architecture, not merely the current implementation. |
| 2 | Implementation conflicts are implementation defects. |
| 3 | Historical source, old examples, migration code, stale documentation, host language patterns, agent output, and repository accidents do not override this specification. |

| # | directive |
|---|---|
| 1 | Conflict rule: `docs/spec/law.md` is the SUPREME one-page law and is authoritative over every document. `docs/spec/constitution.md` (C0) is the structured long-form expansion of `docs/spec/law.md` and the home of the `law.*` identities. |
| 2 | This file is constitutional interpretation for new agents. |
| 3 | If this file conflicts with `docs/spec/law.md` or C0, the higher authority wins and this file must be repaired; where C0 itself diverges from `docs/spec/law.md`, C0 is corrected to match `docs/spec/law.md`. |

| section |
|---|---|
| I. Primary Principle |

| # | directive |
|---|---|
| 1 | Idol is: ordinary semantic values progressively becoming more precisely known. |
| 2 | The specialization ladder is: dynamic → inferred → guarded → sealed → representation selected → target specialized The programmer should normally not rewrite a program merely to move upward on this ladder. |
| 3 | The compiler learns. |
| 4 | The program remains semantically the same. |
| 5 | Fundamental invariant: SEMANTIC IDENTITY PERSISTS. |
| 6 | REPRESENTATION CHANGES. |
| 7 | Every language feature must strengthen this progression rather than introduce a parallel system. |

| section |
|---|---|
| II. Priorities |

| # | directive |
|---|---|
| 1 | Optimize in this order: runtime performance semantic architecture compile-time performance syntax density semantic expressiveness metaprogramming power agent comprehensibility future extensibility Do not improve superficial familiarity by sacrificing optimization or semantic convergence. |
| 2 | Prefer: one mechanism → many capabilities over: many mechanisms → one capability each Canonical convergence targets: one id system one graph one descriptor/fact system one table/home model one application algebra one projection algebra one conversion relation one staging model one transformation model one world/universe algebra one realization model |

| section |
|---|---|
| III. Identity |

| # | directive |
|---|---|
| 1 | There is exactly one semantic identity concept: id Do not create semantic identity kingdoms such as: StableId SemanticIdentity EntityId ModuleId TypeId ValueId CallId RegionId InstructionId when they mean independent semantic identity. |
| 2 | Dense graph indexes, slots, handles, machine ranges, and internal integers may physically encode/reference ids. |
| 3 | They are representations of identity, not new identities. |
| 4 | The following never establish semantic identity: name path source spelling span hash fingerprint pointer address intern slot opcode symbol linkage name declaration order Distinct semantic occurrences retain distinct ids even if all visible facts are equal. |
| 5 | Cross-edit or cross-build continuity is an explicit correspondence relation between ids. |
| 6 | It is never guessed from path/name/hash equality. |

| section |
|---|---|
| IV. Fact Ownership |

| # | directive |
|---|---|
| 1 | Each authoritative semantic fact has exactly one producer. |
| 2 | Examples: lexical identity lexical authority syntactic structure grammar/parser home provenance source projection relation semantic resolution subject semantic resolution application semantic graph producer world requirement resolved relation/application world witness authority satisfaction demand demand analysis representation realization selected machine target realization machine range machine producer A downstream stage must never reconstruct an upstream fact from: source text function name path AST shape opcode method flag host type string symbol If the fact is missing: fix the producer or edge OR fail closed Never rediscover it. |
| 3 | One fact with multiple authoritative producers is a language fork. |

| section |
|---|---|
| V. Unknown |

| # | directive |
|---|---|
| 1 | Unknown compiler knowledge is not a language value. |
| 2 | Never represent unknown with: 0 false "" nil empty pack fake id placeholder enum default relation default world Distinguish: unknown compiler fact nil language value false zero empty string empty table absent demand not applicable Unknown remains unknown until proven. |

| section |
|---|---|
| VI. Nil |

| # | directive |
|---|---|
| 1 | Nil is Idol's native ordinary absence value. |
| 2 | Do not create wrapper ontologies: absent present maybe option none some for ordinary lookup/search absence. |
| 3 | Example: home = env["HOME"] may produce: text \| nil Missing: nil Present but empty: "" These remain distinct. |
| 4 | Do not collapse: nil → "" nil → false nil → 0 Language refinement may narrow: text \| nil to: text inside a branch proving non-nil. |

| section |
|---|---|
| VII. Naming — General |

| # | directive |
|---|---|
| 1 | A project-owned semantic identity must name exactly one irreducible semantic thing. |
| 2 | Canonical semantic names are: lowercase singular one irreducible word Do not encode in the identity name: cardinality protocol satisfaction ability representation transformation target stage provenance demand optimization state world authority implementation strategy pipeline phase historical state evidence state Do not use: underscores camelCase PascalCase kebab-case mashed compounds numeric taxonomy arbitrary abbreviations Delete before rename. |
| 3 | Decompose before rename. |
| 4 | Rehome before rename. |
| 5 | A lowercase one-token spelling is NOT enough. |
| 6 | Examples of still-invalid names: scanfiles canonicalid tokenview arm64check perfledger because they contain more than one semantic axis. |

| section |
|---|---|
| VIII. SINGULAR-ONE |

| # | directive |
|---|---|
| 1 | Grammatical plurality never encodes semantic identity. |
| 2 | A table already represents zero, one, or many members. |
| 3 | Therefore: gates invalid → gate tests invalid → test fixtures invalid → fixture relations invalid → relation descriptors invalid → descriptor when the plural merely means "a collection of X." Cardinality belongs in facts: count(table) pack cardinality member count union cardinality Never in the name. |
| 4 | Do not evade this with collective nouns merely meaning "many X": collection bundle suite catalog group set container pool family unless the collective behavior is genuinely the independent semantic concept. |
| 5 | Do not blindly rename: scripts → script examples → example tools → tool docs → doc First determine whether the organizational root should exist at all. |
| 6 | Prefer semantic rehoming. |

| section |
|---|---|
| IX. IDENTITY-IRREDUCIBILITY TEST |

| # | directive |
|---|---|
| 1 | For every new binding, table, file, directory, function, descriptor, or compiler object ask: What independently observable entity does this identify? |
| 2 | Which facts qualify it? |
| 3 | Would the identity still exist if one of those facts changed? |
| 4 | Is the name describing a fact rather than an entity? |
| 5 | Does Idol already have machinery that owns the implied behavior? |
| 6 | If the identity disappears merely because a qualifying fact changes, the name probably encoded the fact. |
| 7 | Example: an application witness disappears when the subject no longer admits that relation application. |
| 8 | Therefore *able protocol names are not identities — they illegitimately encode relation satisfaction. |
| 9 | Canonical representation is the application/relation fact. |

| section |
|---|---|
| X. PROTOCOL-NAME-ZERO |

| # | directive |
|---|---|
| 1 | Never create identities encoding "can do X." Presumptively invalid: callable readable writable iterable indexable hashable comparable equatable serializable encodable decodable parseable printable formattable executable runnable cloneable copyable movable awaitable seekable and generally project-owned: *able *ible when they mean relation/application satisfaction. |
| 2 | Replace with the actual fact: admits application admits read admits write admits iter admits to(format) No adjective protocol object. |
| 3 | Exception: the bare boundary keyword `able(...)` is NOT an adjective identity — it is the ONE explicit protocol/requirement boundary (`docs/spec/law.md` §9), e.g. `able(eq)`, `able(read)`, `able(to(str))`. |
| 4 | It is normally inferred and spelled only at a real boundary; it mints no trait, dictionary, or vtable. |
| 5 | A name ending in `able`/`ible` (`readable`, `iterable`) remains forbidden. |

| section |
|---|---|
| XI. ROLE-NOUN-ZERO |

| # | directive |
|---|---|
| 1 | Banning adjectives is insufficient. |
| 2 | Also distrust role nouns that merely mean "thing that performs relation X": reader writer runner parser encoder decoder serializer formatter validator checker builder emitter generator renderer collector walker scanner evaluator interpreter provider consumer producer receiver sender Such a noun is valid only if the domain contains a genuinely observable entity with that identity. |
| 3 | Otherwise: subject + relation already expresses the semantics. |

| section |
|---|---|
| XII. QUALIFIER-ZERO |

| # | directive |
|---|---|
| 1 | Do not mint identities from qualifiers or states such as: active ready valid invalid resolved unresolved known unknown sealed dynamic static native foreign cached dirty clean pending partial complete mutable immutable shared local global pure impure hot cold used unused materialized boxed unboxed inlined folded vectorized These are facts about something else. |
| 2 | Never: nativevalue dynamiccall boxedvalue validtype specializedfunction as separate semantic identity classes. |

| section |
|---|---|
| XIII. REDUNDANT QUALIFIER ZERO |

| # | directive |
|---|---|
| 1 | Avoid prefixes such as: semantic* idol* native* meta* when the underlying concept is already inherently semantic/native/Idol. |
| 2 | Examples: semanticgraph should normally just be: graph Likewise: semanticcontext semanticalgebra semantictransaction must prove irreducibility or be decomposed. |
| 3 | "Application algebra" may be an explanatory phrase. |
| 4 | It does not imply an Algebra object. |

| section |
|---|---|
| XIV. META-NOUN-ZERO |

| # | directive |
|---|---|
| 1 | Architectural explanatory words do not automatically deserve program identities: algebra calculus lattice framework system model mechanism architecture subsystem layer schema Use them in prose when useful. |
| 2 | Do not create semantic subsystems merely because the architecture can be described with that word. |

| section |
|---|---|
| XV. ORGANIZATIONAL-ESCAPE-ZERO |

| # | directive |
|---|---|
| 1 | Do not hide unclear semantic ownership under generic organizational names: core base common shared util utility helper support misc internal foundation platform system default general generic A name like "helper" means ownership has not been resolved. |
| 2 | Rehome to the actual semantic owner. |

| section |
|---|---|
| XVI. COLLISION-ZERO |

| # | directive |
|---|---|
| 1 | Never create a semantic object whose role duplicates Idol's native machinery. |
| 2 | Presumptively forbidden when used as compiler/language architecture: router gateway dispatcher registry manager factory adapter broker mediator controller coordinator orchestrator handler executor runner engine pipeline scheduler loader bridge shim proxy wrapper frontend backend context session service provider framework container The ROLE is forbidden, not only the spelling. |
| 3 | Renaming: router → broker → manager → service does not fix it. |

| section |
|---|---|
| XVII. Existing Machinery Owns These Responsibilities |

| # | directive |
|---|---|
| 1 | Routing: application resolution Dispatch: application resolution + realization selection Registration: anchored facts Adaptation: foreign/realization projection Context: current fact/reachability set Execution selection: demand + realization Protocol satisfaction: relation/application facts Transformation selection: transformation dependencies + demand Therefore no second owner object is required. |

| section |
|---|---|
| XVIII. KEY→HANDLER ZERO |

| # | directive |
|---|---|
| 1 | A structure equivalent to: name → function kind → callback opcode → handler directive → implementation type → implementation format → encoder is presumptively a second semantic dispatcher. |
| 2 | Meaning belongs in anchored graph facts. |
| 3 | A physical lookup index may exist only as acceleration. |
| 4 | Deleting the index must not alter semantic behavior. |

| section |
|---|---|
| XIX. RESPONSIBILITY-BAG ZERO |

| # | directive |
|---|---|
| 1 | An object that owns several of: relation selection world selection target selection source reachability stage transformation diagnostics runtime state is presumptively wrong. |
| 2 | Do not create Context/Session/Manager objects that make facts true merely by containing them. |
| 3 | Split facts by their real owners. |

| section |
|---|---|
| XX. Filesystem Semantics |

| # | directive |
|---|---|
| 1 | Filesystem has exactly one language job: **at ingestion**, paths establish initial stable names and home/member topology for source bodies. |
| 2 | After that, paths are **provenance only** — not scope, not module identity, not lookup. |

| # | directive |
|---|---|
| 1 | Every admitted directory implies an ordinary table/home. |
| 2 | A same-name root `.id` file is optional. |

| # | directive |
|---|---|
| 1 | Example: test/ smoke.id initially tells the compiler: home test member smoke |

| # | directive |
|---|---|
| 1 | Then the filesystem is forgotten except as origin/provenance. |

| # | directive |
|---|---|
| 1 | No language operation means: go to parent directory look in sibling file search root import module load package |

| # | directive |
|---|---|
| 1 | Prefer ordinary qualification when a binding is not ambient: gate.census test.smoke app.limit |

| # | directive |
|---|---|
| 1 | The textual qualifier resolves **once** at source resolution. |
| 2 | The graph sees ids. |
| 3 | Filesystem does not survive into graph resolution or realization. |

| # | directive |
|---|---|
| 1 | If both exist: test.id test/ they contribute to the SAME test table/home. |
| 2 | The file contributes root-body semantics; the directory contributes members. |
| 3 | No file/module distinction. |

| section |
|---|---|
| XXI. File Is Body |

| # | directive |
|---|---|
| 1 | For: gate/census.id filesystem already supplies: home gate member census Inside the file do NOT repeat: census = ... census: {...} gate.census = ... gate = { census = ... } The file contents are the member body. |
| 2 | Home/member identity is supplied exactly once. |

| section |
|---|---|
| XXII. Root Execution |

| # | directive |
|---|---|
| 1 | There is no canonical: main entry init start wrapper merely to execute a file. |
| 2 | A file's root expression sequence IS its execution/result. |
| 3 | Example scriptlike body: value = compute() value:print() 0 No main. |
| 4 | If a file is root-callable: (x) y = transform(x) y No same-name function wrapper. |

| section |
|---|---|
| XXIII. Child Relations |

| # | directive |
|---|---|
| 1 | A callable child file is normally a relation on its parent table when the parent is its semantic subject. |
| 2 | Given: gate/idiom.id with root: (diff) ... canonical invocation: gate:idiom(diff) not: gate.idiom(diff) Graph: relation = idiom subject = gate operands = diff home = gate origin = gate/idiom.id Nested example: test/compiler/smoke.id canonical: test.compiler:smoke(...) `.` projects compiler statically. `:` invokes smoke on compiler. |

| section |
|---|---|
| XXIV. DOT-STRICT |

| # | directive |
|---|---|
| 1 | `.` means static named member projection only. |
| 2 | A call: x.y(...) is canonical only if: y is genuinely a static projected callable/accessor VALUE x is not the semantic subject of relation y Example allowed: env["HOME"] if `env` is uniquely reachable and human-obvious. |
| 3 | Keep static qualification only when it disambiguates actual semantic identity: os.env["HOME"] Example forbidden: gate.idiom(diff) when gate is the subject. |
| 4 | Use: gate:idiom(diff) Never use dot merely because another language would call something a static method/module function. |

| section |
|---|---|
| XXV. SUBJECT-FIRST |

| # | directive |
|---|---|
| 1 | If an operation belongs semantically to a possessed value, orient the relation on that value: source:read() path:open() stdout:write(text) command:run() text:find(pattern) text:sub(a,b) Avoid: read(source) open(path) write(stdout,text) find(text,pattern) unless the relation genuinely has no natural semantic subject. |

| section |
|---|---|
| XXVI. APPLICATION-ONE |

| # | directive |
|---|---|
| 1 | All ordinary application participates in one semantic algebra: relation projection facts subject operand pack result demand descriptor law world requirement world witness effect stage origin provenance demand Parser preserves structure. |
| 2 | Resolver determines semantic application. |
| 3 | Do not create independent semantic call kingdoms for: function call method call accessor call protocol call generic call projected call after resolution. |

| section |
|---|---|
| XXVII. PAREN-ONE |

| # | directive |
|---|---|
| 1 | `()` is the ordinary canonical application/accessor delimiter. |
| 2 | The resolver determines whether: f(x) is: callable application keyed access ordinal access place-producing access another admitted application shape Punctuation itself does not mint semantic identity. |

| section |
|---|---|
| XXVIII. HUMAN-UNAMBIGUOUS ELISION |

| # | directive |
|---|---|
| 1 | Do NOT hide meaningful actions merely because the compiler could infer them. |
| 2 | Relation-name elision requires BOTH: compiler uniqueness human obviousness Good: f(x) env["HOME"] args[1] row[column] because the application/access intent is obvious. |
| 3 | Normally prefer explicit: source:read() path:open() command:run() stdout:write(text) text:parse(json) rather than: source() path() command() stdout(text) text(json) when the omitted relation would force a human reader to guess. |
| 4 | Syntax density must not reduce semantic clarity. |

| section |
|---|---|
| XXIX. ACCESS-ONE |

| # | directive |
|---|---|
| 1 | Canonical computed projection: env["HOME"] args[1] table[key] row[column] These are computed/indexed projections — not ordinary application. |
| 2 | Aggregate lookup uses `env["HOME"]`, `args[1]`, `table[key]`, `row[column]` and never application. `env("HOME")`, `args(1)`, `table(key)`, and `row(column)` are ordinary application only when the subject is genuinely callable. |
| 3 | Do not use: x:get(k) x:set(k,v) x:call(...) These duplicate projection/application semantics. |
| 4 | Long-term place-producing projection may support: x[k] = value when `x[k]` resolves to a place. |

| section |
|---|---|
| XXX. PROJECTION-AND-APPLICATION-ONE |

| # | directive |
|---|---|
| 1 | Computed aggregate access uses brackets `table[key]` — computed projection. |
| 2 | Application `table(key)` applies the value; it never indexes. |
| 3 | Whether the projection yields a value or place is resolved from demand and facts rather than punctuation. |
| 4 | A foreign source law may recognize foreign bracket or parenthesis indexing only inside that law-qualified source projection. |
| 5 | The spelling remains source provenance and never becomes Idol grammar or semantic authority. |

| section |
|---|---|
| XXXI. HAS-ZERO |

| # | directive |
|---|---|
| 1 | Do not reify presence into: has contains exists includes present member when ordinary lookup/search already returns value-or-nil. |
| 2 | Bad: if table:has(key) Prefer: value = table[key] if value ... |
| 3 | Bad: code:has(pattern) Prefer an irreducible search: pos = code:find(pattern) if pos ... |
| 4 | Boolean presence should exist only if the bool itself is genuinely demanded. |

| section |
|---|---|
| XXXII. TO-ONE |

| # | directive |
|---|---|
| 1 | There is one semantic descriptor-conversion relation: to Do not create generic conversion synonyms: char cast coerce convert stringify into as encode when the actual semantics are descriptor conversion. |

| section |
|---|---|
| XXXIII. Conversion Inference (SOURCE-INFER-ONE / FACT-COMPOSITION-INFER-ONE) |

| # | directive |
|---|---|
| 1 | No source spelling should survive merely to restate a semantic fact the compiler can already recover uniquely. |
| 2 | This applies uniformly to bindings, relation/method names, static projections, conversion, target descriptors, protocol/world satisfaction, capture, and projection/injection composition. |

| # | directive |
|---|---|
| 1 | Every source token must contribute semantic information not already uniquely recoverable from: subject; operands; result demand; descriptor demand; reachable exact facts; relation constraints; world/effect requirements; stage; provenance; control-flow refinement. |

| # | directive |
|---|---|
| 1 | If a spelling contributes no new information: omit it. |
| 2 | If omission leaves multiple lawful solutions: spell the minimum disambiguating fact. |
| 3 | If omission is compiler-unique but human-ambiguous: retain the irreducible meaningful relation (`source:read()` may remain; `source()` alone does not). |

| # | directive |
|---|---|
| 1 | FACT-COMPOSITION-INFER-ONE: projection, injection, capture, protocol/world satisfaction, and target selection are graph facts — normally zero source syntax. |
| 2 | Usage derives dependencies (`stdout:write(env["HOME"])`, not `@{ os.env io.stdout }`). |

| # | directive |
|---|---|
| 1 | Case A — satisfaction: c: char = 10 If exact literal facts already satisfy char, no conversion exists. |
| 2 | Case B — inferred conversion: c: char = value If the unique lawful path requires conversion, graph records: value:to(char) without source spelling. |
| 3 | Case C — explicit target: value:to(char) only if the target is not otherwise recoverable from demand/context. |
| 4 | There is no canonical `value:to()` rung. |

| # | directive |
|---|---|
| 1 | Preference (source-density order): omit redundant binding → omit redundant relation/projection/conversion/world composition → value:to(target) only when target is not inferable → retain minimum spelling for uniqueness + human meaning |

| # | directive |
|---|---|
| 1 | Never: string.char(10) char(10) 10:char() If the desired value is simply newline text: "\n" Use the literal. |

| # | directive |
|---|---|
| 1 | INTERMEDIATE-ZERO: chain relations directly when identity is preserved. |
| 2 | Retain a named intermediate only when the name contributes semantic information the chain does not (multiple consumers, or human-clarity place identity). |

| section |
|---|---|
| XXXIV. Satisfaction / Conversion / Parse / Realization |

| # | directive |
|---|---|
| 1 | These are distinct: SATISFACTION value already obeys demanded descriptor CONVERSION semantic domain/law transformation through to PARSE interpretation under syntax/format law, possibly failing REALIZATION same semantic value receives another physical representation Do not use conversion to model machine width/layout. |
| 2 | Do not use parse as a synonym for conversion. |
| 3 | Do not use realization as semantic conversion. |

| section |
|---|---|
| XXXV. ENCODE-ZERO |

| # | directive |
|---|---|
| 1 | `encode` and `decode` are presumptively noncanonical generic bindings. |
| 2 | Likewise: encoding codec encoder decoder serialize deserialize serializer deserializer marshal unmarshal transcode must prove irreducible semantics. |
| 3 | For each site determine whether it is actually: satisfaction to(format) parse(format) emission/output foreign realization Formats themselves may survive as descriptors: json cbor protobuf pem varint if they represent irreducible observable format laws. |
| 4 | Do not create: encoding/json codec/json jsonencoder encodable hierarchies. |
| 5 | A format is a descriptor. |
| 6 | The transformation is a relation. |

| section |
|---|---|
| XXXVI. Format Examples |

| # | directive |
|---|---|
| 1 | If JSON representation is semantically conversion: out: json = value or explicitly: out = value:to(json) If text must be interpreted as JSON syntax: value = text:parse(json) If emission has independently observable semantics distinct from `to`, an explicit relation may survive only after proof. |
| 2 | Never invent `encode` merely because ecosystem libraries use that vocabulary. |

| section |
|---|---|
| XXXVII. @ — Current-world accessor |

| # | directive |
|---|---|
| 1 | `@` IS THE CURRENT-WORLD ACCESSOR (`docs/spec/law.md` §4). |
| 2 | Canonical meanings: bare @ the current world value @member access a static member of the current world: @target @env (@ is the accessor itself; @member.child is one access then one ordinary static projection) @member = v mutate a current-world member place, when it is a place thing@world interpret/project thing in world (postfix); thing@ is current-world qualification, normally redundant @{ k = v } derive the current world by injection (exact fact deltas); thing@{ k = v } is scoped interjection; @( … ) is eval INVALID: @.member and @:member — @ already accesses, so there is no `@.` projection step and no `@:` subject dispatch. |
| 3 | Prefix compiler-namespace directives are denied. |
| 4 | Never: @comp.* @host.* @runtime.* @ffi.* as generic source APIs. `@` does not mean import. `@` does not mean generic injection. `@` does not call compiler implementation. |

| section |
|---|---|
| XXXVIII. @{} |

| # | directive |
|---|---|
| 1 | `@{ k = v }` derives the current world by **injection** — a new closed world with exact fact deltas over the enclosing world. `thing@{ k = v }` is **interjection**: `thing` evaluated under that derived world. `@{}` is the single face for world derivation; it is **not** a descriptor sigil. |

| # | directive |
|---|---|
| 1 | A **descriptor is an ordinary table** whose values are descriptor constraints — no sigil is required: |

| # | directive |
|---|---|
| 1 | point = { x: f64 y: f64 } |

| # | directive |
|---|---|
| 1 | It is **not**: import use include universe declaration scope declaration a descriptor literal |

| # | directive |
|---|---|
| 1 | **`@{}` is world derivation, never import/dependency ceremony.** Injection normally has **zero** source syntax — usage derives exact world/protocol dependencies. |
| 2 | Writing: |

| # | directive |
|---|---|
| 1 | @{ os.env io.stdout } |

| # | directive |
|---|---|
| 1 | just to use environment variables and stdout is forbidden surface plumbing. |
| 2 | Source names what it uses; execution supplies authority witnesses. |
| 3 | Explicit `@{ k = v }` injection exists only when fact composition is not uniquely inferable from use. |

| # | directive |
|---|---|
| 1 | When projected fact/table expressions occur in an anchored descriptor body, their normalized fact closure contributes coherently to that anchor. |
| 2 | The compiler may describe that algebraically as fact composition. |
| 3 | There is no `inject` language construct and no user-facing `interjection` syntax. |

| section |
|---|---|
| XXXIX. Descriptors |

| # | directive |
|---|---|
| 1 | Descriptors unify constraints/facts traditionally represented as: types concepts enum-like domains protocols schemas build targets stages hardware descriptions runtime descriptions Do not reintroduce separate: type concept trait interface impl class struct protocol-object kingdoms. |
| 2 | A descriptor is semantic facts/constraints. |
| 3 | Physical representation is not chosen merely because a descriptor exists. |

| section |
|---|---|
| XL. TABLE-ONE |

| # | directive |
|---|---|
| 1 | Ordinary tables remain the foundational semantic aggregation mechanism. |
| 2 | A table can play roles such as: home descriptor structured value world universe source root compile-time value without changing semantic kind. |
| 3 | Role is a fact. |
| 4 | Do not create a separate object model for each role. |

| section |
|---|---|
| XLI. World |

| # | directive |
|---|---|
| 1 | World is an ordinary closed semantic table (`docs/spec/law.md` §3 + World+projection add-on), not a class/kind/keyword. `@` is the current world. |
| 2 | A world may contain values, relations, descriptors, other worlds, stage/target facts, and authority facts. |
| 3 | Authority is ONE class of fact within a world — a world is not synonymous with authority. |
| 4 | An ordinary table/value plays the world role when facts reachable from it satisfy the authority requirements of effectful applications. |
| 5 | World means: a closed semantic table whose facts (including, but not limited to, authority facts) resolve meaning not: authority object namespace service API module runtime object Do not define: World FileWorld ReadWorld SandboxWorld readonly writable privileged restricted merely to group permission sets. |
| 6 | Presence/absence of actual authority facts is sufficient. |

| section |
|---|---|
| XLII. OS World |

| # | directive |
|---|---|
| 1 | A platform may provide an ordinary world-role table: os env args cwd These semantic values are supplied by execution ingress/realization. |
| 2 | Canonical ambient access: env["HOME"] args[1] when uniquely reachable and human-obvious. |
| 3 | Explicit static projection only when qualification disambiguates: os.env["HOME"] os.args[1] `env` and `args` are accessors. |
| 4 | Do not implement them in canonical Idol source using: getenv @comp.host.env host.env API runtime.env Physical realization belongs below the graph. |

| section |
|---|---|
| XLIII. IO World |

| # | directive |
|---|---|
| 1 | A platform may provide: io stdin stdout stderr These are ordinary endpoint values. |
| 2 | Meaningful operations orient on the actual endpoint: stdin:read() stdout:write(text) Never: io.read() io.write() because io is not the true subject. |

| section |
|---|---|
| XLIV. USER-DEFINED FIXTURE TABLES |

| # | directive |
|---|---|
| 1 | A fixture is an ordinary table whose bindings can satisfy authority at the execution boundary: |

| # | directive |
|---|---|
| 1 | mock = { env = { HOME = "/tmp/idol" } stdout = output } |

| # | directive |
|---|---|
| 1 | Nothing marks it as a `world`. |
| 2 | At run/compile configuration, the caller chooses projected bindings from it — conceptually: |

| # | directive |
|---|---|
| 1 | run program with env = mock.env stdout = mock.stdout |

| # | directive |
|---|---|
| 1 | Do not rush source syntax for this. |
| 2 | It may initially be a compiler/run descriptor or API operation (deployment configuration, not application semantics). |
| 3 | If Idol source eventually expresses it, use ordinary table construction — not a world DSL. |

| # | directive |
|---|---|
| 1 | Explicit qualification in source remains valid when ambiguity must be avoided: mock.env["HOME"] |

| section |
|---|---|
| XLV. ESSENTIAL MODEL |

| # | directive |
|---|---|
| 1 | **Universe** is compiler vocabulary for the closed fact set used while resolving one body or application. |
| 2 | Users write programs; they do not define universes in source. |
| 3 | Injection/interjection are internal terms for adding fact edges — not user syntax. |

| # | directive |
|---|---|
| 1 | For users, three things matter: |

| # | directive |
|---|---|
| 1 | value relation authority |

| # | directive |
|---|---|
| 1 | Everything else is compiler bookkeeping. |

| # | directive |
|---|---|
| 1 | Example source: |

| # | directive |
|---|---|
| 1 | home = env["HOME"] text = path:read() stdout:write(text) |

| # | directive |
|---|---|
| 1 | The compiler already knows the complete semantic requirements: |

| # | directive |
|---|---|
| 1 | env accessor file read relation stdout write relation |

| # | directive |
|---|---|
| 1 | Source must **not** redundantly declare: |

| # | directive |
|---|---|
| 1 | inject os.env project io.stdout include filesystem |

| # | directive |
|---|---|
| 1 | **Rule (INFER-ONE for world):** if a dependency can be uniquely inferred from an actual semantic use, never require a declaration of that dependency. |

| section |
|---|---|
| XLVI. RESOLVE ONCE — NEVER SEARCH LATER |

| # | directive |
|---|---|
| 1 | Each name and reference resolves **exactly once** to a semantic id and facts. |

| # | directive |
|---|---|
| 1 | Lexical structure and layout-projected home topology may assist that initial resolution. |
| 2 | After resolution: |

```text
no parent scope lookup
no filesystem lookup
no global fallback
no namespace lookup
no module lookup
```

| # | directive |
|---|---|
| 1 | Free lexical references become explicit **capture** edges — not runtime parent-environment lookup. |

```id
outer = 4
f = (x)
    x + outer
```

| # | directive |
|---|---|
| 1 | The resolver binds `outer` to one exact id. |
| 2 | The graph records `f capture → outer-id`. |
| 3 | From that point forward, no parent scope exists semantically. |

| # | directive |
|---|---|
| 1 | Prefer ordinary static qualification: |

```id
if x > app.limit
    ...
```

| # | directive |
|---|---|
| 1 | Local naming is ordinary binding: `limit = app.limit`. |
| 2 | Do not require `@{}` projection blocks or import ceremony for sibling/home members the layout model already makes referable. |

| section |
|---|---|
| XLVII. FILESYSTEM INGEST ONLY |

| # | directive |
|---|---|
| 1 | Filesystem semantics narrow to one job: |

| # | directive |
|---|---|
| 1 | **At ingestion**, paths establish initial stable names and home structure. |
| 2 | After that, paths are **provenance only**. |

```text
test/smoke.id  →  test · test.smoke  →  filesystem forgotten except origin
```

| # | directive |
|---|---|
| 1 | No language operation means: parent directory walk, sibling file search, root search, import module, load package. |

| section |
|---|---|
| XLVIII. @{} IS WORLD DERIVATION, NOT CEREMONY |

| # | directive |
|---|---|
| 1 | `@{ k = v }` is the single face for world derivation by injection; `thing@{ k = v }` is interjection. |
| 2 | It is **not** a descriptor sigil — descriptors are ordinary tables `{ x: f64 }`. |
| 3 | It is **not** import/dependency ceremony. |

| # | directive |
|---|---|
| 1 | Injection normally has **zero** source syntax — usage derives exact world authority, inferred from use and supplied at execution. |
| 2 | Never write: |

```id
@{
    os.env
    io.stdout
}
```

| # | directive |
|---|---|
| 1 | just to use environment variables and output. |
| 2 | Dot, colon, call, binding, and ordinary tables already supply projection. |
| 3 | Explicit `@{ k = v }` injection exists only when fact composition is not uniquely inferable from use. |

| # | directive |
|---|---|
| 1 | Forbidden source ceremony (non-exhaustive): |

```text
import · require · use · include
universe declaration · world declaration · scope declaration
```

| section |
|---|---|
| XLIX. WORLDS AS EXECUTION INPUTS |

| # | directive |
|---|---|
| 1 | Programs run under different worlds **without changing source**. |

| # | directive |
|---|---|
| 1 | Real execution supplies platform `env` and `stdout`. |
| 2 | Test execution supplies fixtures and captured output. |
| 3 | Same source — no `@{ mock.os.env }` inside the program. |

| # | directive |
|---|---|
| 1 | World composition at the run/compile boundary is ordinary table data: |

```id
world = {
    env = mock.env
    args = os.args
    stdout = io.stdout
}
```

| # | directive |
|---|---|
| 1 | Cross-origin selection (args from platform, env from mock) is a **configuration** fact at execution — not source-level `@{ os.args mock.os.env }` blocks. |
| 2 | Origin/authority lineage is preserved in graph witnesses; no CombinedWorld object. |

| section |
|---|---|
| L. World Ambiguity |

| # | directive |
|---|---|
| 1 | If two observably distinct witnesses could satisfy the same authority demand, unqualified `env["HOME"]` is **ambiguous** — fail. |

| # | directive |
|---|---|
| 1 | Never choose by declaration order, nearest declaration, test preference, default world, path, or namespace priority. |
| 2 | Select explicitly: |

```id
mock.env["HOME"]
```

| # | directive |
|---|---|
| 1 | or supply a unique execution configuration. |
| 2 | Rejecting OS/IO is witness omission at the boundary — not a negative-capability language in source. |

| section |
|---|---|
| LI. Projection Algebra |

| # | directive |
|---|---|
| 1 | For a table/world T: F(T) = normalized semantic fact closure Static projection (one static step, always): T.member selects member facts. `@` is the current world and is itself the accessor; `@member` accesses it (never `@.member` or `@:member`). |
| 2 | World qualification: T@world evaluates/projects T under world — postfix `@` carries a world, never a relation. |
| 3 | Subject-relation orientation is the colon face `T:relation` (`law.at.one`); `T@relation` anchoring is superseded. |
| 4 | Injection / interjection: @{ k = v } derive the current world with exact fact deltas x@{ k = v } scoped interjection x@(@{ k = v }) Projection: P(T,S) ⊆ F(T) preserves ids and origin. |
| 5 | Projection does not clone meaning. |

| section |
|---|---|
| LIII. Injection (internal) |

| # | directive |
|---|---|
| 1 | For a destination world D and projected fact set P, coherent composition is internal algebra: |

```text
F(D)' = coherent(F(D) ∪ P)
```

| # | directive |
|---|---|
| 1 | Same fact unifies; compatible facts conjoin; incomparable distinct witnesses → ambiguity. |
| 2 | Never last-wins. |

| # | directive |
|---|---|
| 1 | This is how the compiler records inferred authority and context facts. |
| 2 | It is **not** a separate source-language operation. |
| 3 | Do not expose `inject` or `interject` as user syntax. |

| section |
|---|---|
| LIV. Protocol |

| # | directive |
|---|---|
| 1 | A protocol is a projection/constraint over required relation/application facts. |
| 2 | Example: source:read() on unknown source establishes: source must admit read with the demanded shape Do not create: readable Readable reader protocol interface trait impl The relation/application constraint IS the requirement. |

| section |
|---|---|
| LIV. Protocol ≠ World |

| # | directive |
|---|---|
| 1 | Protocol satisfaction does not grant authority. |
| 2 | These may all satisfy `read`: memory file socket But: memory:read() may require no external authority file:read() may require file/path authority socket:read() may require network/socket authority Same relation. |
| 3 | Different subject/world facts. |
| 4 | Never merge into a generic "io capability." |

| section |
|---|---|
| LV. Conditional Authority |

| # | directive |
|---|---|
| 1 | For unresolved: file \| socket and relation: read retain alternative-specific authority requirements. |
| 2 | After refinement to file: network requirement disappears. |
| 3 | Do not eagerly combine authority into generic world categories. |

| section |
|---|---|
| LVI. Union |

| # | directive |
|---|---|
| 1 | Union means remaining semantic alternatives. |
| 2 | It does not imply a boxed tagged runtime object. |
| 3 | For: a \| b representation is chosen later. |
| 4 | If refinement leaves one live alternative: runtime tag cost should disappear unless the tag itself is independently observable. |

| section |
|---|---|
| LVII. Value ≠ Place |

| # | directive |
|---|---|
| 1 | A semantic value is not automatically storage. |
| 2 | A binding is not automatically a stack slot. |
| 3 | A table field is not automatically memory. |
| 4 | Place exists only if observable semantics demand: mutation aliasing address lifetime identity ABI persistent state No place requirement: no mandatory load/store/materialization. |

| section |
|---|---|
| LVIII. REPRESENTATION-NOUN-ZERO |

| # | directive |
|---|---|
| 1 | Do not turn physical storage choices into semantic identities: buffer box slot cell register stack heap lane bucket block page node handle pointer unless they are genuinely observable domain entities. |
| 2 | Representation belongs to realization. |

| section |
|---|---|
| LIX. PACK-ONE |

| # | directive |
|---|---|
| 1 | One pack model covers: operands results projections multiple returns ABI argument/result shapes Preserve: pack id value ids position/label descriptor demand provenance Do not invent separate: ArgList ReturnTuple ProjectionArgs semantic kingdoms. |

| section |
|---|---|
| LX. Multiple Returns |

| # | directive |
|---|---|
| 1 | Multiple returns are native semantic result packs. |
| 2 | Do not materialize a tuple merely because a backend representation prefers one. |
| 3 | If caller consumes values separately, realization may keep them separately in registers. |
| 4 | Unconsumed result slots should disappear physically. |

| section |
|---|---|
| LXI. Closures |

| # | directive |
|---|---|
| 1 | A closure has semantic facts: callable identity captures escape lifetime demand Possible realization: inline constant substitution direct specialized function registers stack heap Heap closure is last resort. |
| 2 | Source closure syntax never mandates heap allocation. |

| section |
|---|---|
| LXII. Curry |

| # | directive |
|---|---|
| 1 | Currying is genuine only when an application returns a callable value. |
| 2 | Example: scale = (k) (x) x * k double = scale(2) Missing arity does not magically curry arbitrary functions. |
| 3 | Projection forms are not currying. |

| section |
|---|---|
| LXIII. Functions |

| # | directive |
|---|---|
| 1 | Canonical compact function form: add = (a, b) a + b Multi-line: normalize = (value) value:validate():normalize() Tail expression returns. |
| 2 | No Nim-style `result`. |
| 3 | No named return binding solely for return machinery. |
| 4 | No mandatory `function`, `fun`, `fn` keyword. |
| 5 | No `end`. |
| 6 | No canonical `do`. |
| 7 | No canonical `then`. |

| section |
|---|---|
| LXIV. Methods / Relations |

| # | directive |
|---|---|
| 1 | There is no independent method object model. |
| 2 | Colon is subject relation orientation. |
| 3 | A relation whose semantic subject is a table/value uses: subject:relation(...) Do not introduce: method kind method registry method reference ontology impl block Relation identity remains relation identity. |

| section |
|---|---|
| LXV. DESCRIPTOR-LOCAL RELATIONS |

| # | directive |
|---|---|
| 1 | Relations naturally associated with a descriptor/home should be defined within that home's semantic topology rather than as operation-first free functions. |
| 2 | A relation can still be globally identified while its home supplies declaration context. |
| 3 | Home membership does not mint a new relation identity. |

| section |
|---|---|
| LXVI. Home |

| # | directive |
|---|---|
| 1 | Home is: declaration/reachability/context anchor It is NOT: namespace module protocol grant world grant Moving among equivalent homes must not change relation identity. |
| 2 | Path is provenance after source projection. |

| section |
|---|---|
| LXVII. MODULE-ZERO |

| # | directive |
|---|---|
| 1 | There is no native: module namespace import require req include package-loader semantic system. |
| 2 | Filesystem tables/homes + reachability already organize source. |
| 3 | Do not reconstruct module semantics later from paths. |

| section |
|---|---|
| LXVIII. STD-ZERO / LIB-ZERO |

| # | directive |
|---|---|
| 1 | No canonical: std.* lib.* semantic hop. |
| 2 | Standard functionality is simply ordinary reachable/admitted relations, descriptors, values, and laws. |
| 3 | Repository directories named `lib` must not become semantic roots merely because they exist physically. |
| 4 | Do not repair: std.* by changing it to: semantic.* core.* lib.* Delete the organizational semantic hop. |

| section |
|---|---|
| LXIX. META-ZERO |

| # | directive |
|---|---|
| 1 | Compile-time/staged behavior is ordinary Idol semantics plus stage/anchor facts. |
| 2 | Do not create a parallel `meta` namespace/system unless the value is genuinely external metadata. |
| 3 | No: metadispatch metaregistry metaobject system for ordinary staging. |

| section |
|---|---|
| LXX. Staging |

| # | directive |
|---|---|
| 1 | Compile-time execution operates on ordinary Idol semantics. |
| 2 | No separate macro language. |
| 3 | No derive DSL. |
| 4 | No build DSL if ordinary staged Idol can express it. |
| 5 | Stage is a fact. |
| 6 | Compile-time values are ordinary values. |

| section |
|---|---|
| LXXI. ARBITRARY COMPILE-TIME EXECUTION |

| # | directive |
|---|---|
| 1 | Compile-time execution may perform ordinary Idol computation subject to world, stage, and determinism constraints. |
| 2 | Cache by: semantic dependencies world observations target facts demand not merely timestamps. |

| section |
|---|---|
| LXXII. DERIVE-ZERO AS SUBSYSTEM |

| # | directive |
|---|---|
| 1 | Do not build: derive registry derive evaluator kingdom derive bundle ontology when behavior is expressible as: relation/descriptor facts stage transformation A physical lookup index may remain if nonauthoritative. |

| section |
|---|---|
| LXXIII. TRANSFORM-ONE |

| # | directive |
|---|---|
| 1 | One transformation model covers: constant folding specialization inlining vectorization fusion staging dead-code elimination target lowering Every transform records: input ids prerequisite facts produced facts eliminated alternatives provenance/lineage physical consequence No rewrite engine/transform engine semantic kingdom. |

| section |
|---|---|
| LXXIV. TRANSFORMATION-NAME-ZERO |

| # | directive |
|---|---|
| 1 | Do not turn generic transformation families into arbitrary semantic homes: encoding decoding conversion normalization canonicalization lowering rewriting expansion optimization generation emission unless the domain contains an independently observable entity with that name. |
| 2 | Usually these are relations/transformation records. |

| section |
|---|---|
| LXXV. Transformation Lineage |

| # | directive |
|---|---|
| 1 | Optimization does not erase semantic lineage. |
| 2 | Preserve: source → semantic id → application → relation → values → transformation → realization → instruction → byte range Constant folding does not erase the application. |
| 3 | Inlining does not erase call provenance. |
| 4 | Vectorization does not erase scalar relation identity. |

| section |
|---|---|
| LXXVI. GRAPH-ONE |

| # | directive |
|---|---|
| 1 | There is one primary semantic graph. |
| 2 | Secondary: call graph region graph dependency graph control graph may exist only as derived indexes/views. |
| 3 | They cannot own semantic facts unavailable from the primary graph. |

| section |
|---|---|
| LXXVII. AST Boundary |

| # | directive |
|---|---|
| 1 | AST owns syntax/provenance. |
| 2 | Parser may recognize: delimiters source home declared parameter shape spans syntax forms Parser does NOT authoritatively decide: subject world demand application role semantic projection relation identity Those belong to semantic resolution/graph. |
| 3 | Do not create hidden syntax bindings to manufacture semantic roles. |

| section |
|---|---|
| LXXVIII. DNIR |

| # | directive |
|---|---|
| 1 | DNIR is a realization projection. |
| 2 | It is not a second semantic language. |
| 3 | It must carry/consume graph facts such as: application id relation id selected target id subject id operand/result packs descriptors world/effect demand provenance Do not reconstruct semantics from: callee name source path symbol opcode host type method flag DNIR operation tags are physical encodings, not new semantic relation identities. |

| section |
|---|---|
| LXXIX. Relation ≠ Target |

| # | directive |
|---|---|
| 1 | One relation may have multiple lawful implementations. |
| 2 | Relation: validates semantic meaning Selected target: chooses a concrete implementation/realization Never assume: relation → exactly one physical function Carry selected target separately where needed. |

| section |
|---|---|
| LXXX. TARGET-ONE |

| # | directive |
|---|---|
| 1 | Do not create semantic target-qualified relation identities: armadd wasmadd gpuadd simdadd Semantic relation remains: add Target is a realization fact. |
| 2 | Architecture names such as: arm64 wasm macho may survive only where they genuinely identify foreign/target representation domains. |
| 3 | They must not qualify native semantic identities unnecessarily. |

| section |
|---|---|
| LXXXI. Foreign Boundary |

| # | directive |
|---|---|
| 1 | Foreign representations normalize exactly once. |
| 2 | Examples: C ABI Wasm OS handles foreign strings Lua compatibility process exit status Ingress: foreign facts → canonical semantic facts Egress: canonical semantic facts → required foreign representation No permanent adapter/bridge semantic ontology. |

| section |
|---|---|
| LXXXII. BRIDGE-DEATH |

| # | directive |
|---|---|
| 1 | A temporary physical bridge requires: exact responsibility exact facts crossing semantic authority classification replacement owner deletion prerequisite positive control negative control No deletion condition: invalid bridge. |
| 2 | Once replacement exists: delete bridge. |
| 3 | Never rename: bridge → adapter → gateway and preserve the same architecture. |

| section |
|---|---|
| LXXXIII. ZERO-COPY |

| # | directive |
|---|---|
| 1 | Zero-copy interop requires proof of: layout alignment ownership lifetime mutation law alias law encoding ABI compatibility Pointer compatibility alone is insufficient. |

| section |
|---|---|
| LXXXIV. WASM |

| # | directive |
|---|---|
| 1 | Wasm is a target/foreign realization over the same semantic graph. |
| 2 | No independent Wasm semantic universe. |
| 3 | Same semantic relation ids. |
| 4 | Same values where meaning persists. |
| 5 | Same application algebra. |
| 6 | Target-specific representation comes later. |
| 7 | Goal: Idol Wasm faster than Wasmtime smaller binaries faster startup equal semantic correctness But claims require evidence. |

| section |
|---|---|
| LXXXV. Numbers |

| # | directive |
|---|---|
| 1 | Compact source faces may remain: i8 i16 i32 i64 u8 u16 u32 u64 f32 f64 But they decompose semantically into facts: width signedness format precision overflow law rounding law Unannotated integer literals retain exact mathematical integer value until demand forces a narrower descriptor. |
| 2 | Physical register/lane width belongs to realization. |

| section |
|---|---|
| LXXXVI. Effects |

| # | directive |
|---|---|
| 1 | Do not reduce effects to a single pure/impure boolean. |
| 2 | Retain enough facts to determine: may reorder? may duplicate? may eliminate? may speculate? may fail? may allocate? may observe mutation? which world required? may fuse? may parallelize? |
| 3 | Optimization consumes effect facts. |

| section |
|---|---|
| LXXXVII. Order |

| # | directive |
|---|---|
| 1 | Source order is semantically binding only when observable dependencies/effects require it. |
| 2 | Independent work may: reorder fuse parallelize vectorize stage when facts prove equivalence. |

| section |
|---|---|
| LXXXVIII. Concurrency |

| # | directive |
|---|---|
| 1 | Do not create semantic kingdoms merely from concurrency strategy: Task Future Promise Actor AsyncFunction unless independently irreducible. |
| 2 | Semantic facts: dependency ordering sharing ownership transfer lifetime cancellation communication world Realization may choose: inline coroutine thread task SIMD GPU process Native coroutines should be first-class realization capability. |

| section |
|---|---|
| LXXXIX. Synchronization |

| # | directive |
|---|---|
| 1 | Do not introduce: lock atomic barrier refcount cost unless sharing/order semantics require it. |
| 2 | Isolation should remove synchronization costs. |

| section |
|---|---|
| XC. Ownership |

| # | directive |
|---|---|
| 1 | Do not import Rust's surface ownership model. |
| 2 | Keep semantic facts: alias lifetime unique escape mutation transfer address observation Representation follows those facts. |
| 3 | No ownership syntax required merely for compiler optimization. |

| section |
|---|---|
| XCI. Iteration |

| # | directive |
|---|---|
| 1 | One iteration semantic mechanism. |
| 2 | Do not create unrelated iterator kingdoms: pairs ipairs Iterator Enumerator Generator Range object unless a returned state machine itself is semantically observable. |
| 3 | Realization may choose: counted loop pointer walk hash walk SIMD coroutine/generator |

| section |
|---|---|
| XCII. Fusion |

| # | directive |
|---|---|
| 1 | Source chains such as: xs:map(f):filter(p):sum() should not force intermediate collections. |
| 2 | When facts allow: one fused loop zero intermediate allocation is preferred. |
| 3 | Semantic relation composition remains visible to graph/tooling. |

| section |
|---|---|
| XCIII. Vector |

| # | directive |
|---|---|
| 1 | SIMD is realization. |
| 2 | Infer vectorization from: independent iteration descriptor alias freedom alignment reduction law target capabilities Do not require a separate SIMD language. |

| section |
|---|---|
| XCIV. SHAPE-ONE |

| # | directive |
|---|---|
| 1 | Known table shape drives: field offsets scalar replacement register allocation stack layout hash elimination iteration strategy ABI layout vector layout Once shape is known, downstream may not forget it and fall back to generic hash semantics. |

| section |
|---|---|
| XCV. COST-ONE |

| # | directive |
|---|---|
| 1 | Every physical cost must identify the unresolved semantic possibility forcing it. |
| 2 | Audit: allocation copy box tag guard hash lookup indirect call heap closure materialized pack runtime descriptor runtime world object ABI shuffle spill lock atomic buffer conversion If no semantic uncertainty/observable law requires the cost: delete it. |

| section |
|---|---|
| XCVI. REQUIRED ZERO-COST CASES |

| # | directive |
|---|---|
| 1 | Known shape: generic hash lookup = 0 Sealed target: indirect call = 0 Nonescaping closure: heap allocation = 0 Singleton union: runtime tag = 0 Unused result: materialization = 0 Static protocol witness: runtime witness object = 0 Statically unique world witness: runtime world object = 0 Direct descriptor satisfaction: conversion = 0 |

| section |
|---|---|
| XCVII. Specialization |

| # | directive |
|---|---|
| 1 | Specialization accumulates facts over existing semantic applications. |
| 2 | Potential facts: subject relation descriptor exact value table shape result demand world stage target profile Do not create a separate generic/template semantic system. |

| section |
|---|---|
| XCVIII. Specialization Budget |

| # | directive |
|---|---|
| 1 | Semantic specialization does not imply code cloning. |
| 2 | Clone a physical implementation only when expected runtime benefit exceeds: compile time code size I-cache cost startup cost memory cost Profile may influence this decision. |
| 3 | Profile does not establish semantic truth. |

| section |
|---|---|
| XCIX. Guards |

| # | directive |
|---|---|
| 1 | Every speculative guard records: assumed fact evidence guard dependent realization failure/invalidation path No hidden assumptions. |
| 2 | No profile observation promoted directly to truth. |

| section |
|---|---|
| C. Runtime |

| # | directive |
|---|---|
| 1 | There is no mandatory monolithic Idol runtime. |
| 2 | A sealed native program that needs no: GC scheduler reflection dynamic tables coroutine machinery world adapter should link none. |
| 3 | Startup should approach: OS loader → entry with minimal language initialization. |

| section |
|---|---|
| CI. GC |

| # | directive |
|---|---|
| 1 | GC is a realization strategy. |
| 2 | A value may realize as: register stack static region arena isolated heap GC heap according to lifetime/escape/alias facts. |
| 3 | GC is not mandatory table semantics. |

| section |
|---|---|
| CII. COMPILE-TIME PERFORMANCE |

| # | directive |
|---|---|
| 1 | Semantic richness must not imply heap-object explosion. |
| 2 | Prefer: dense ids arenas contiguous fact storage bitsets packed facts compact spans lazy indexes Avoid: heap object per semantic fact string-key semantic maps everywhere duplicated complete IRs Derive secondary facts only when demanded or profitable to cache. |

| section |
|---|---|
| CIII. Cache |

| # | directive |
|---|---|
| 1 | Cache is acceleration. |
| 2 | Deleting all caches must preserve correctness. |
| 3 | Cache candidates may be found by: fingerprint path timestamp but semantic reuse must be verified by authoritative dependencies/facts. |
| 4 | A cache can never select meaning. |

| section |
|---|---|
| CIV. Incrementality |

| # | directive |
|---|---|
| 1 | Invalidation is fact-based: changed semantic fact → dependent semantic slice → dependent realization slice Do not make: file changed → rebuild module the fundamental architecture. |
| 2 | File is provenance partition, not semantic identity. |

| section |
|---|---|
| CV. Determinism |

| # | directive |
|---|---|
| 1 | Same: semantic source universe world observations target must produce deterministic semantic meaning. |
| 2 | These may not choose meaning: filesystem order hash iteration task scheduling pointer addresses agent order source discovery order Ambiguity must fail rather than resolve accidentally. |

| section |
|---|---|
| CVI. Source Syntax — Blocks |

| # | directive |
|---|---|
| 1 | Canonical blocks are offside/indentation-based. |
| 2 | No canonical: end then do semicolon Outdent closes the block. |
| 3 | Whitespace is syntactic layout but semantic identity must not depend on formatting details beyond the parsed structure. |

| section |
|---|---|
| CVII. Comments |

| # | directive |
|---|---|
| 1 | Canonical line comment: |

    # comment
| # | directive |
|---|---|
| 1 | Do not reintroduce Lua `--`. |
| 2 | Block-comment machinery should not create a second complex comment language unless independently justified. |
| 3 | Current source and tooling should consistently teach `#`. |

| section |
|---|---|
| CVIII. Strings |

| # | directive |
|---|---|
| 1 | Canonical ordinary text: "text" Interpolation: "hello {name}" Prefer interpolation over explicit concatenation. |
| 2 | Do not use Lua `..` as canonical concatenation. |
| 3 | Historical long-string syntax is not canonical. |
| 4 | Quote/byte semantics must remain consistent with the final lexical authority; do not invent additional string literal kingdoms ad hoc. |

| section |
|---|---|
| CIX. `!` |

| # | directive |
|---|---|
| 1 | Canonical boolean negation should use the compact native negation face where the grammar admits it. |
| 2 | Do not regress into stale Lua-style `not` patterns in canonical source if the current lexical authority has retired them. |
| 3 | This is surface syntax; semantic boolean negation remains one relation/law. |

| section |
|---|---|
| CX. Table Keys |

| # | directive |
|---|---|
| 1 | Prefer ordinary static member syntax for statically known keys. |
| 2 | Do not write computed bracket keys merely because Lua historically required them. |
| 3 | Use explicit computed projection only when the key genuinely is computed or the place semantics require it. |

| section |
|---|---|
| CXI. Generics |

| # | directive |
|---|---|
| 1 | Do not introduce bracket generic syntax: Slice[Byte] Foo[T] Types/descriptors are first-class semantic values. |
| 2 | Generic behavior comes from: ordinary parameters compile-time/stage facts descriptors application specialization No separate generic language. |

| section |
|---|---|
| CXII. Casts |

| # | directive |
|---|---|
| 1 | No C-style cast system. |
| 2 | Conversion: to Demand may eliminate source spelling entirely. |
| 3 | Representation reinterpretation is not necessarily semantic conversion and may require a view/realization law rather than `to`. |
| 4 | Do not conflate bit reinterpretation with semantic conversion. |

| section |
|---|---|
| CXIII. Shell |

| # | directive |
|---|---|
| 1 | Shell is interpretation law. |
| 2 | Command is a semantic value. |
| 3 | Process execution is authority/effectful relation. |
| 4 | Do not create: shell namespace process service command runner capture subsystem Canonical meaningful execution may be: command:run() Output capture is usually: run + output demand not a second relation. |
| 5 | Avoid textual shell pipelines for native compiler/gate logic when structured semantic operations can express the work. |
| 6 | Bootstrap shell use must have deletion debt. |

| section |
|---|---|
| CXIV. Status / Outcome |

| # | directive |
|---|---|
| 1 | Foreign process status is not automatically native semantic outcome. |
| 2 | Distinguish: process status transport completion semantic result evidence verdict Do not infer: status == 0 → semantic truth without an admitted boundary law. |

| section |
|---|---|
| CXV. PREDICATE-ZERO |

| # | directive |
|---|---|
| 1 | Be suspicious of boolean helpers: is* has* can* exists valid supported enabled when they merely rebox richer semantic facts. |
| 2 | Prefer direct refinement/consumption of the richer result. |
| 3 | A bool exists only when bool itself is demanded. |

| section |
|---|---|
| CXVI. MODE-ZERO |

| # | directive |
|---|---|
| 1 | Do not collapse independent semantic dimensions into: mode kind flavor style class category tag if those are merely discriminators selecting behavior. |
| 2 | Decompose into actual facts. |
| 3 | Example: mode = readonly is usually inferior to simply omitting write authority. |

| section |
|---|---|
| CXVII. KIND-TAXONOMY CAUTION |

| # | directive |
|---|---|
| 1 | Classification enums may exist as physical compact representations. |
| 2 | They may not replace decomposed semantic facts. |
| 3 | Dangerous: kind = callable kind = native kind = world kind = reader Prefer direct fact relations. |

| section |
|---|---|
| CXVIII. PROVENANCE-NAME-ZERO |

| # | directive |
|---|---|
| 1 | Do not create distinct semantic identity classes: generatedvalue sourcevalue nativevalue importedvalue syntheticvalue inferredvalue derivedvalue because origin/provenance differs. |
| 2 | Provenance is a fact on the same semantic identity where meaning persists. |

| section |
|---|---|
| CXIX. DEMAND-NAME-ZERO |

| # | directive |
|---|---|
| 1 | Do not mint identities from: used unused required optional consumed discarded retained requested These are demand facts. |
| 2 | Demand drives realization. |
| 3 | It does not rename the semantic value. |

| section |
|---|---|
| CXX. EVIDENCE-NO-AUTHORITY |

| # | directive |
|---|---|
| 1 | These may represent evidence records, but never independently establish semantics: status verdict proof report audit census metric benchmark profile trace log ledger Evidence validates claims. |
| 2 | It does not make language facts true. |
| 3 | Profile guides optimization only. |

| section |
|---|---|
| CXXI. PHASE-NO-AUTHORITY |

| # | directive |
|---|---|
| 1 | Implementation may be organized into phases such as: lexer parser resolver lowerer codegen but phase does not become semantic ownership merely because code runs there. |
| 2 | Facts remain owned according to semantic responsibility. |
| 3 | "Frontend" and "backend" must not become parallel semantic kingdoms. |

| section |
|---|---|
| CXXII. Source Order / File Path |

| # | directive |
|---|---|
| 1 | Filesystem topology supplies initial home/member projection. |
| 2 | After resolution, path becomes provenance. |
| 3 | Path never chooses: relation world target conversion protocol realization Move/rename with semantic correspondence must not silently change meaning. |

| section |
|---|---|
| CXXIII. LSP |

| # | directive |
|---|---|
| 1 | Every language feature must support: formatting completion hover semantic highlighting diagnostics navigation refactoring LSP consumes compiler semantic graph. |
| 2 | Do not create a second LSP semantic model. |

| section |
|---|---|
| CXXIV. MCP |

| # | directive |
|---|---|
| 1 | MCP should become the semantic API for agents. |
| 2 | Prefer stable semantic ids and graph queries over text search. |
| 3 | Useful queries: what relation is this? what is the subject? why this world? why this representation? what blocks scalarization? what prevents direct call? what transformation produced this instruction? what unknown fact caused this allocation? |
| 4 | Avoid text-based semantic workflows whenever graph facts are available. |

| section |
|---|---|
| CXXV. Repository Corpus |

| # | directive |
|---|---|
| 1 | Canonical agent training/reference source must contain only current canonical Idol. |
| 2 | Historical/negative/foreign syntax must not masquerade as canonical corpus. |
| 3 | Prefer: generated transient negative fixtures over permanently storing large searchable noncanonical source corpora. |
| 4 | If negative fixtures remain stored, their role must be mechanically explicit and excluded from canonical training/search projections. |

| section |
|---|---|
| CXXVI. ZERO-HISTORY |

| # | directive |
|---|---|
| 1 | Git is the history archive. |
| 2 | Active current-project source/docs should not preserve: old project names old syntax history Pass N migration chronology deprecated wording legacy architecture explanations unless required to describe a currently executed foreign/bootstrap boundary. |
| 3 | Current comments explain current truth. |
| 4 | Do not write: formerly... used to... release 0.1... migration from... into canonical source. |

| section |
|---|---|
| CXXVII. Current Identity |

| # | directive |
|---|---|
| 1 | Project/language: Idol Canonical source suffix: .id New canonical `.id` is admitted. |
| 2 | Retired suffixes `.duo`, `.duon`, `.idsem` are forbidden in the active tree. |
| 3 | Canonical executable/tool spelling: idol Do not reintroduce retired project identities or suffixes into active project source, paths, caches, generated files, or current teaching. |

| section |
|---|---|
| CXXVIII. Gate |

| # | directive |
|---|---|
| 1 | `gate` is singular. |
| 2 | C0/constitution owns law. |
| 3 | Gate members verify/projection-test the law. |
| 4 | Gate files must not independently invent or manually maintain a second copy of the language rules. |
| 5 | Generated verification from C0/graph is preferred. |
| 6 | Any temporary lexical detector must have a deletion condition once graph authority exists. |

| section |
|---|---|
| CXXIX. Manual Vocabulary Tables |

| # | directive |
|---|---|
| 1 | Do not maintain hand-authored tables such as: admitted words relation→world namespace map respelling map global map protocol registry when those facts already exist in grammar/C0/graph. |
| 2 | Gate queries the authoritative fact source. |
| 3 | It does not duplicate it. |

| section |
|---|---|
| CXXX. SELF-HOSTING |

| # | directive |
|---|---|
| 1 | Self-hosting means actual executed semantic authority moved into Idol. |
| 2 | It does not mean: .id file count source-line percentage wrappers around host APIs renamed foreign code Ask: what earliest production semantic fact is still owned outside Idol? |
| 3 | Move that authority. |
| 4 | Then delete the old owner/fallback. |
| 5 | Priority frontier: lexical identity → grammar role → parser recognition → semantic resolution → graph → demand → realization → machine |

| section |
|---|---|
| CXXXI. No Silent Fallback |

| # | directive |
|---|---|
| 1 | After semantic authority moves, old path may not silently answer. |
| 2 | Unsupported native behavior: diagnose/fail closed Do not silently: emit C call Lua invoke host helper use textual builtin query stale registry reconstruct from path unless explicitly performing an admitted foreign realization. |

| section |
|---|---|
| CXXXII. C Backend |

| # | directive |
|---|---|
| 1 | Generated C is an explicit orthogonal physical realization, not semantic authority and not a tier beneath direct native. |
| 2 | It consumes the same graph facts as every other backend. |
| 3 | Do not shape Idol semantics around ease of C emission. |

| # | directive |
|---|---|
| 1 | Direct native remains the default, self-host, release, correctness, and performance path. |
| 2 | It never emits C, invokes a C compiler, depends on a C artifact, or falls back to C. `auto` never selects C. |
| 3 | C-backend evidence proves only the C feature; it cannot certify direct native. |
| 4 | The `c` foreign world is an independent interop capability and does not select a backend. |

| section |
|---|---|
| CXXXIII. FTCFTW |

| # | directive |
|---|---|
| 1 | Goal: faster than C across equivalent semantics and: Idol Wasm faster than Wasmtime smaller binaries faster startup Claims require evidence. |
| 2 | Optimization principle: unresolved semantic possibility → physical cost As semantic uncertainty disappears: physical cost should disappear Track unknowns that force: allocation box tag hash indirect call guard copy runtime descriptor lock spill materialization |

| section |
|---|---|
| CXXXIV. Performance Evidence |

| # | directive |
|---|---|
| 1 | Every performance claim binds: exact revision dirty state exact input semantic result target CPU/features competitor version compile time startup execution time peak memory artifact size sample count variance Timing with incorrect/different semantics is invalid evidence. |

| section |
|---|---|
| CXXXV. Performance Damage Control |

| # | directive |
|---|---|
| 1 | Every benchmark must contain a positive observability control. |
| 2 | Intentionally worsen the measured dimension: add delay force allocation force hash force indirect call force copy disable vectorization The benchmark must measurably worsen. |
| 3 | Otherwise the measurement path is not trusted. |

| section |
|---|---|
| CXXXVI. FTCFTW DIMENSIONS |

| # | directive |
|---|---|
| 1 | Do not optimize runtime alone. |
| 2 | Track jointly: runtime startup compile time compiler memory runtime memory binary size linked runtime bytes I-cache impact No benchmark victory purchased by catastrophic size/startup/compile regressions without explicit tradeoff evidence. |

| section |
|---|---|
| CXXXVII. Agent Work Rule |

| # | directive |
|---|---|
| 1 | Before adding any language/compiler concept: identify existing semantic owner Before adding a name: prove identity irreducibility Before adding a wrapper: prove the wrapped relation cannot already express it Before adding a registry: prove graph facts cannot own it Before adding a module: stop; module semantics are denied Before adding *able: stop; protocol satisfaction is a fact Before adding encode/decode: classify satisfaction/to/parse/realization first Before adding plural table/root: stop; cardinality is a fact Before adding router/gateway/context/engine: stop; find the actual existing semantic machinery Before reconstructing information downstream: stop; fix the producer edge |

| section |
|---|---|
| CXXXVIII. Hard Stop Conditions |

| # | directive |
|---|---|
| 1 | Do not continue implementation when: semantic owner is unclear relation identity is unclear subject is unclear world authority is ambiguous application role is ambiguous upstream fact is missing easiest solution is a registry/context/router solution requires path/name semantic lookup solution requires semantic fallback new concept duplicates an existing mechanism Record the exact missing semantic fact/boundary. |
| 2 | Do not invent architecture to unblock yourself. |

| section |
|---|---|
| CXXXIX. Required Review For Every New Name |

| # | directive |
|---|---|
| 1 | Every new project-owned name must answer: What semantic entity exists independently of this spelling? |
| 2 | Is it singular? |
| 3 | Is the word irreducible? |
| 4 | Is it a noun for a real entity rather than an ability/role/state? |
| 5 | Does it encode cardinality? |
| 6 | Does it encode protocol satisfaction? |
| 7 | Does it encode transformation direction? |
| 8 | Does it encode representation? |
| 9 | Does it encode implementation phase? |
| 10 | Does it encode target? |
| 11 | Does it encode provenance? |
| 12 | Does it encode demand? |
| 13 | Does it collide with application/world/projection/realization machinery? |
| 14 | Would a fact change require renaming it? |
| 15 | Any bad answer: reject/decompose. |

| section |
|---|---|
| CXL. Required Review For Every Application |

| # | directive |
|---|---|
| 1 | For each application determine: relation subject operands result pack descriptor facts demand world requirement world witness effect stage origin provenance selected target when realized Then ask: which facts need source spelling? which are uniquely inferable? would elision confuse a human reader? |
| 2 | No spelling is omitted merely because compiler inference can guess it. |

| section |
|---|---|
| CXLI. Required Review For Every Compiler Structure |

| # | directive |
|---|---|
| 1 | Ask: Is this semantic or physical? |
| 2 | What authoritative fact does it contain? |
| 3 | Who produced that fact? |
| 4 | Is the fact duplicated elsewhere? |
| 5 | Can deleting this structure change semantics? |
| 6 | Is it an acceleration index? |
| 7 | Does it reconstruct from names/paths? |
| 8 | Does it create a second taxonomy? |
| 9 | Does representation leak upward into meaning? |
| 10 | If deleting a supposed cache/index changes meaning: it was illegally authoritative. |

| section |
|---|---|
| CXLII. Required Review For Every Physical Cost |

| # | directive |
|---|---|
| 1 | For: allocation copy box tag branch indirect call hash runtime metadata world object closure environment temporary pack synchronization answer: Which unresolved semantic possibility requires this? |
| 2 | No answer: delete the cost. |

| section |
|---|---|
| CXLIII. Required Review For Every Pr/Workstream |

| # | directive |
|---|---|
| 1 | Report: revision dirty state semantic boundary owned authority before authority after fact producer changed consumers changed ids preserved facts added facts removed reconstruction removed new concepts deleted concepts naming debt introduced naming debt removed bridges remaining bridge deletion condition SHC frontier before SHC frontier after physical delta: allocation copy box tag hash indirect call runtime bytes compile-time delta startup delta runtime delta memory delta size delta positive control negative control integrated result No "done" without this. |

| section |
|---|---|
| CXLIV. Negative Controls For Naming |

| # | directive |
|---|---|
| 1 | Must reject attempts to create semantic architecture called: callable reader serializable encoding codec router broker service registry manager context engine pipeline collection container nativevalue validtype semantictransaction when each merely reifies an existing fact/role. |
| 2 | Renaming to a synonym must still fail. |
| 3 | The gate is semantic-role based. |
| 4 | Not a word blacklist. |

| section |
|---|---|
| CXLV. Positive Domain Exceptions |

| # | directive |
|---|---|
| 1 | A normally suspicious word may be valid when it literally denotes an external observable domain entity. |
| 2 | Examples: network router HTTP gateway hardware driver external codec identifier But such a domain word may NOT be reused as compiler semantic machinery. |
| 3 | Likewise: json cbor protobuf wasm macho may identify real observable format/foreign domains. |
| 4 | Their associated operations still follow the common semantic algebra. |

| section |
|---|---|
| CXLVI. Current Canonical Style Examples |

| # | directive |
|---|---|
| 1 | Descriptor/table (ordinary table — no sigil): point = { x: f64 y: f64 } Compact function: add = (a, b) a + b Tail-return body: normalize = (value) value:validate():normalize() Accessor: home = env["HOME"] first = args[1] Meaningful relation: stdout:write(source:read()) Search + nil refinement: position = text:find("idol") if position print(position) Conversion inferred: count: i64 = text only when the compiler can prove the unique lawful to(i64) conversion and that conversion is actually the intended semantic operation. |
| 2 | Conversion explicit when necessary: count = text:to(i64) Static projection followed by accessor: home = mock.os.env["HOME"] Parent relation from child file: gate:idiom(diff) No: gate.idiom(diff) No: env["HOME"] No: source() when source() would obscure "read." No: code:has(pattern) No: encode(value) without proving encode is independently irreducible. |

| section |
|---|---|
| CXLVII. Current Canonical Topology Example |

| # | directive |
|---|---|
| 1 | gate/ census.id idiom.id test/ smoke.id mock/ os.id input.id input/ read.id output.id output/ write.id No root gate.id/test.id/mock.id is required for the directories to imply those tables. |
| 2 | If same-name root files exist, they contribute to the same homes. |

| section |
|---|---|
| CXLVIII. THINGS THAT MUST TREND TO ZERO |

| # | directive |
|---|---|
| 1 | retired project identities historical syntax pass-number source/comments module/import semantics std namespace lib semantic namespace semantic.* replacement namespace plural cardinality names *able/*ible identities role-noun protocol identities encode/decode generic systems codec systems router/gateway/dispatcher systems registry systems manager/factory systems context/session responsibility bags engine/pipeline systems bridge/shim/proxy layers main/entry wrappers redundant file self-bindings relation invocation through dot operation-first possessed-subject calls bracket ordinary access has/presence reboxing conversion synonyms explicit to when uniquely inferable world classes universe classes adjective capability worlds relation→world string maps protocol-granted authority host API wrappers compiler API namespaces downstream semantic reconstruction target-qualified semantic relations DNIR semantic duplication known-shape hash lookup sealed indirect calls nonescaping heap closures singleton-union tags undemanded result materialization undemanded runtime witness objects unexplained physical cost silent host/C/Lua fallback stale committed session state historical gap archive |

| section |
|---|---|
| CXLIX. Final Compression |

| # | directive |
|---|---|
| 1 | ONE MEANING → ONE ID. |
| 2 | FACTS QUALIFY IDENTITIES. |
| 3 | FACTS DO NOT BECOME EXTRA IDENTITIES. |
| 4 | CARDINALITY IS A FACT. |
| 5 | ABILITY IS A FACT. |
| 6 | ROLE IS A FACT. |
| 7 | STAGE IS A FACT. |
| 8 | TARGET IS A FACT. |
| 9 | PROVENANCE IS A FACT. |
| 10 | REPRESENTATION IS A FACT. |
| 11 | DEMAND IS A FACT. |
| 12 | AUTHORITY IS A FACT. |
| 13 | DIRECTORIES ARE TABLES. |
| 14 | FILES ARE TABLE/MEMBER BODIES. |
| 15 | ROOT EXPRESSIONS EXECUTE. |
| 16 | THERE IS NO MAIN. |
| 17 | DOT PROJECTS STATIC MEMBERS. |
| 18 | COLON ORIENTS MEANINGFUL RELATIONS. |
| 19 | PARENTHESES CALL/APPLY/ACCESS WHEN THAT IS HUMAN-OBVIOUS. |
| 20 | DO NOT HIDE MEANINGFUL READ/WRITE/OPEN/RUN/PARSE INTENT. |
| 21 | NIL IS ORDINARY ABSENCE. |
| 22 | DO NOT REIFY ABSENCE AGAIN. |
| 23 | HAS DOES NOT REBOX PRESENCE. |
| 24 | TO IS THE ONE CONVERSION RELATION. |
| 25 | TO DISAPPEARS WHEN SATISFACTION OR DEMAND MAKES IT REDUNDANT. |
| 26 | ENCODE/DECODE ARE NOT PRESUMED SEMANTIC RELATIONS. |
| 27 | FORMATS MAY BE DESCRIPTORS. @ IS THE CURRENT WORLD — NOT A COMPILER/HOST DIRECTIVE. @{} IS WORLD DERIVATION BY INJECTION — DESCRIPTORS ARE ORDINARY TABLES. |
| 28 | SOURCE NAMES USE |
| 29 | EXECUTION SUPPLIES WITNESSES — INFER-ONE FOR WORLD. |
| 30 | RESOLVE ONCE: LEXICAL/HOME ASSISTS INITIAL BINDING |
| 31 | NO LOOKUP AFTER RESOLUTION. |
| 32 | CAPTURE EDGES REPLACE RUNTIME PARENT SCOPE. |
| 33 | FILESYSTEM: INGEST TOPOLOGY ONLY — THEN PROVENANCE ONLY. |
| 34 | UNIVERSE IS COMPILER-INTERNAL — NOT USER SYNTAX. |
| 35 | FACT COMPOSITION IS INTERNAL — NOT inject/interject SOURCE CEREMONY. |
| 36 | WORLD IS EXECUTION INPUT — ORDINARY TABLES AT THE BOUNDARY. |
| 37 | PROJECTION IS `.` `:` AND APPLICATION — NO PROJECTION DSL. |
| 38 | PROTOCOL IS AN APPLICATION/RELATION CONSTRAINT. |
| 39 | PROTOCOL DOES NOT GRANT AUTHORITY. |
| 40 | MODULES DO NOT EXIST NATIVELY. |
| 41 | STD DOES NOT EXIST NATIVELY. |
| 42 | LIB DOES NOT EXIST SEMANTICALLY. |
| 43 | ROUTERS DO NOT OWN ROUTING. |
| 44 | REGISTRIES DO NOT OWN MEANING. |
| 45 | CONTEXT OBJECTS DO NOT MAKE FACTS TRUE. |
| 46 | ENGINES DO NOT OWN EXECUTION SEMANTICS. |
| 47 | BRIDGES MUST DIE. |
| 48 | THE GRAPH OWNS MEANING. |
| 49 | DEMAND OWNS NECESSITY. |
| 50 | REALIZATION OWNS PHYSICS. |
| 51 | EVERY PHYSICAL COST MUST IDENTIFY THE SEMANTIC UNCERTAINTY OR OBSERVABLE LAW THAT REQUIRES IT. |
| 52 | OPTIMIZATION IS THE DISAPPEARANCE OF PHYSICAL COST AS SEMANTIC UNCERTAINTY DISAPPEARS. |
| 53 | SELF-HOSTING IS EXECUTED SEMANTIC AUTHORITY TRANSFER. |
| 54 | FTCFTW CLAIMS REQUIRE SEMANTIC-EQUIVALENCE EVIDENCE. |
| 55 | IF A NAME MERELY RESTATES A FACT: DELETE THE NAME. |
| 56 | IF A NEW OBJECT DUPLICATES EXISTING LANGUAGE MACHINERY: DELETE THE OBJECT. |
| 57 | IF A DOWNSTREAM STAGE RECONSTRUCTS A FACT: FIX THE PRODUCER/EDGE. |
| 58 | IF A FALLBACK CAN SILENTLY REGAIN AUTHORITY: DELETE THE FALLBACK. |
| 59 | IF A PHYSICAL COST CANNOT EXPLAIN WHY SEMANTICS REQUIRE IT: DELETE THE COST. |
| 60 | THE TARGET END STATE IS: ONE LANGUAGE ONE GRAPH ONE APPLICATION ALGEBRA ONE FACT SYSTEM ONE SEMANTIC AUTHORITY ZERO SHADOW ONTOLOGY ZERO HISTORICAL DRIFT ZERO UNEXPLAINED PHYSICAL COST 100% IDOL SELF-HOSTED SEMANTIC AUTHORITY FTCFTW PROVEN BY EVIDENCE |

| # | directive |
|---|---|
| 1 | FTCFTW is not a checklist. |
| 2 | It is the whole frontier `R(S,W,T,E,P)` — every physically lawful realization preserving the required observations — searched to a verified Pareto frontier (`docs/spec/law.md` §107 OPTIMIZATION-SPACE-COMPLETE |
| 3 | C0 `law.optimization.space`). |
| 4 | It rests on: |

| # | directive |
|---|---|
| 1 | OBSERVATION-ONE (§104, law.observation.one) a program is required observable relationships, not steps; semantic time is not physical time; observability is world-dependent OBSERVATION-MINIMUM (§103, law.observation.minimum) preserve only what is observable; every accidental observable is a permanent optimization barrier PHYSICAL-SPACE-OPEN (§102, law.physical.open) realization is any physical strategy across the whole machine/OS/hardware stack, not code generation BOUNDARY-ONE (§105, folded in law.observation.one) representation is free except at irreversible boundaries; foreign representation has finite extent OBLIGATION-ONE (§109, law.obligation.one) semantics is allowed observations + required obligations (positive, negative, temporal, safety/liveness, progress, fairness, causality, noninterference); equivalence preserves hyperproperties over SETS of executions, not one trace — "same output" is not equivalence NINE-UNIVERSE (§110, law.realization.universe) the structural (non-enumerative) closure: meaning · observation · knowledge · demand · equivalence · realization · resource · search+proof · change; the supreme R equation; monotonic frontier (no knowing Pareto regression); value-of-information and contract-weakening debt; optimality gap = best-known − proven-lower-bound |

| # | directive |
|---|---|
| 1 | The frontier factors into the 24 axes of §107/§108 over these nine universes (§106/§110), with the foundational algebras law.equivalence.observation, law.demand.derivative, law.relation.property, law.change.delta, law.uncertainty.algebra, and law.optimizer.economy. |
| 2 | A candidate realization is admitted iff it preserves demanded observations under the current world, satisfies authority/effect/resource constraints, is verifiable, and improves the chosen Pareto frontier. |
| 3 | Individual optimizations are instances discovered inside `R`, never additions to the constitution. |
| 4 | The frontier is **machinery, not a list**: five graphs — A observation, B demand, C law, D frontier, E debt — feed a mechanical loop (measure → largest debt → classify cause → implement → validate → ratchet), with every case carrying a status in `{win, bound, open, unknownbound}` and no aggregate permitted to hide a loss. |
| 5 | Catalogue: `docs/performance.md`; obligations: `gaps/GAP-169.md`, `gaps/GAP-170.md`, `gaps/GAP-171.md`, `gaps/GAP-172.md` (frontier machinery / FTC-001…020). |

| # | directive |
|---|---|
| 1 | The most important instruction for the new agent is the one that prevents recurrence of nearly every recent mistake: |

| # | directive |
|---|---|
| 1 | Do not ask “what should I call this new thing?” until first proving that there is actually a new semantic thing. |
| 2 | Most apparent new types, protocols, managers, helpers, encoders, readers, registries, contexts, states, wrappers, and categories should instead disappear into existing relation/descriptor/fact/application/world/realization semantics. |

| # | directive |
|---|---|
| 1 | That is the difference between merely making the repo look Idollic and actually converging to the architecture. |
