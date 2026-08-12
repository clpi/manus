# Idol source / home / package / world closure

Apply this immediately to every active agent and every future agent.

This closes the native source-distribution architecture.

Do not introduce a conventional module system while implementing it.

Repository state may contain historical mechanisms.

Historical machinery is migration provenance, not architectural authority.

## Law

Idol has no native semantic concept corresponding to:

- module
- namespace
- import
- require
- req
- include
- package loader
- module registry
- module object
- runtime package table
- standard library namespace

Native Idol has:

```text
value
table
binding
home
relation
world
fact
demand
witness
provenance
realization
```

Source organization projects onto those existing semantics.

Nothing else is required.

## File

A canonical `.id` file is a source partition.

It is not a module.

When a file supplies one naturally named table/home, its stem projects that ordinary binding into its enclosing home.

Given:

```text
app/
  main.id
  parser.id
  lexer.id
```

the semantic topology is approximately:

```text
app
  main
  parser
  lexer
```

These are ordinary table/home bindings.

Inside `main.id`, sibling semantic references may therefore be ordinary:

```id
tree = parser:parse(source)
tokens = lexer:scan(source)
```

Do not write:

```id
req parser
require parser
import parser
module parser
std.parser
```

The reference itself is the dependency.

## Directory

A semantic directory may project an enclosing ordinary home.

Given:

```text
compiler/
  parser.id
  lexer.id
  graph.id
```

the source graph may expose:

```text
compiler.parser
compiler.lexer
compiler.graph
```

where each component is an ordinary semantic binding/home.

The directory is not a namespace object.

The directory does not grant authority.

The directory does not require runtime materialization.

The directory does not imply a runtime table unless demanded.

## Physical topology is provenance

The physical path exists initially as discovery/provenance.

After semantic resolution, downstream architecture must not reconstruct meaning from:

- filename
- directory string
- source suffix
- package path
- module spelling
- filesystem location

Semantic identity persists independently.

Moving `compiler/parser.id` without changing the semantic owner does not inherently create another parser identity.

Path changes provenance.

Semantic continuity is preserved through identity/witness correspondence.

## Source projection

Do not create a special semantic edge family for files.

Do not create:

- filebind
- modulebind
- packagebind
- sourcebind

The source partition projects ordinary declarations/bindings into an ordinary home.

Conceptually:

```text
source
  provenance path
  projects home content
```

where `projects`, if represented explicitly, is an existing ordinary relation/fact rather than a privileged module edge.

Inside that projection:

```text
home
  binding parser
```

remains the ordinary binding architecture.

Source syntax and source topology disappear into graph facts plus provenance/witness.

## Package

A package is distribution/provenance for an anchored root table.

It is not a separate semantic kind in native code.

Suppose a project is provided external dependency `http`.

The build/source environment may anchor:

```text
http
```

as an ordinary table/home.

Ordinary code can then reference:

```id
client = http.client:new()
```

if that root is visible in the compilation context.

There is no import operation.

There is no loader call.

There is no package object required at runtime.

The package manager/build environment establishes:

- source provenance
- dependency provenance
- root table identity
- available graph content

Ordinary semantic resolution handles the rest.

## Anchor

Use anchor as architectural description only where needed.

An anchor associates an externally supplied semantic value/home with a root-resolution context.

It does not create another value.

It does not create authority.

It does not become semantic identity.

Examples of externally anchored values may include:

| anchor   | kind        |
|----------|-------------|
| project  | table/home  |
| http     | table/home  |
| sqlite   | table/home  |
| fs       | world       |
| net      | world       |
| process  | world       |
| clock    | world       |

The anchor supplies reachability from the execution/compilation context.

The anchored value retains its own identity and law.

Do not create an anchor runtime object unless realization actually demands one.

## Package is not world

Absolute:

```text
package != world
home != world
table != world
source != world
path != world
```

Dependency possession does not imply authority possession.

A package may expose a relation requiring filesystem authority.

Having that package available does not grant filesystem authority.

This negative control is permanent.

## Package dependency

Dependency is not declared twice.

When code references:

```id
json:parse(text)
```

and `json` belongs to an externally anchored dependency, that resolved reference itself contributes the dependency edge.

Do not separately require:

```id
import json
dependency json
require json
```

merely to restate something the graph already knows.

Build dependency information should be derivable from actual semantic reachability wherever possible.

Declarative build/package configuration may still establish which external roots are available, versions, provenance, trust, policy and acquisition.

It does not need to be repeated inside every source partition.

## Decisive distinction

Three questions must never be conflated:

| question | answers |
|---|---|
| home | where does this meaning live? |
| reach | can this scope resolve this meaning? |
| world | what authority can this application exercise? |

A package may establish home/reach. It does not establish world authority.

A world may satisfy authority. It does not establish package identity.

A source path may establish provenance. It establishes neither semantic identity
nor authority.

## Projection

Projection is not a module mechanism.

Projection means one already-known semantic value/home makes some facts or values
observable through its ordinary law.

Canonical named projection remains `user.name`.

Canonical computed projection remains `table[key]` where grammar permits.

A package table behaves exactly like any other table.

There is no special package projection syntax.

### Direct projection

Given anchored root `codec` exposing `json`, `text`, `binary`:

```id
value = codec.json:parse(source)
```

Resolution is:

```text
root codec → projection json → relation parse → application
```

not package load → export table → member lookup → call.

After semantic resolution, runtime need not contain a codec object at all.

### Sibling projection

Given `codec/parse.id` and `codec/encode.id`, sibling source under the same
home may resolve `parse(source)` and `encode(value)` directly when ordinary
home reachability makes those bindings visible. No package syntax. No file
loading.

### Cross projection

Given roots `app`, `codec`, `net`:

```id
value = codec.json:parse(source)
reply = net.client:send(value)
```

The graph records exact dependencies on `codec.json.parse` and
`net.client.send`, not merely coarse dependencies on `codec` or `net`, unless
broader demand genuinely exists.

### Bare projection

A child scope may project bindings directly:

```text
parse → codec.json.parse
encode → codec.json.encode
```

Source then sees `parse(source)` with no source statement requesting visibility.
The witness records where the binding came from.

### Selective projection

Selection is scope construction, not source ceremony.

A child scope may expose only `parse` and `encode` while `debug` and `internal`
remain unreachable unless another reachability fact exists.

There is no selective import, `use only`, `using only`, `expose`, or `open`.

### Projection preserves identity

If `parse → codec.parse`, bare `parse` and qualified `codec.parse` resolve to the
same semantic identity when proven equivalent. The witness differs; the relation
does not.

There must not be local parse identity, imported parse identity, or standard
parse identity for the same meaning. One identity. Many projections.

Ordinary rebinding such as `decode = codec.parse` does not mint another semantic
relation unless a genuinely different operation is being defined.

## No admission operation

Absolutely no native operation may mean “add x to the current environment.”

Forbid semantic architecture corresponding to:

```text
use using import inject admit open include bring provide register install mount expose
```

when its purpose is merely visibility.

Visibility is already a graph fact. Authority is already a graph fact. Home is
already a graph fact. Projection is already a graph fact. Dependency is already
a graph fact.

Change scope facts at the owner boundary instead of writing admission syntax in
source.

## Scope

A scope is the currently relevant semantic reachability context: local bindings,
reachable homes, reachable root bindings, world grants, descriptor context,
subject context, stage facts, and target facts.

Do not represent scope as one heap object whose maps become authority. Scope is
logically composed from compact graph facts and indexes.

Lexical resolution consumes ordinary scope/home facts. It never invokes a module
loader. Ambiguity fails closed — never choose by load order, package order,
filesystem order, hash order, last wins, or first wins.

## World resolution

Authority operand resolution remains:

```text
explicit compatible world
→ unique compatible reachable world
→ lawful captured world
→ failure
```

with an exact witness.

Never package → authority. Never global object → authority. Never `std` →
authority. Never operating system exists → authority.

A package may expose a relation requiring filesystem authority. Having that
package available does not grant filesystem authority.

Worlds are shared by semantic identity across call boundaries. Do not create
`appfs`, `codecfs`, or per-module world wrappers for identical authority.

Derive a new world only when authority genuinely changes, for example
`cache = fs:at(path)` when `at` is the admitted narrowing relation.

Closures capture/reach worlds under ordinary value/lifetime law. Do not silently
box authority or fall back to global process state.

## Capability matrix

World selection consumes ordinary world/capability facts. The matrix describes
the relation space; do not implement it as a giant hardcoded table if existing
descriptor/world relations can derive compatibility.

| application demand | reachable world | result |
|---|---|---|
| no authority required | none | proceed |
| fs required | exactly one compatible fs world | infer with witness |
| fs required | zero compatible worlds | fail |
| fs required | several equally compatible worlds | ambiguity |
| fs explicitly supplied | supplied world compatible | use exact world |
| fs explicitly supplied | supplied world incompatible | fail |
| fs + net required | compatible fs and net reachable | satisfy both |
| fs + net required | one absent | fail |
| net required | build used net but program has no net world | fail |

Vocabulary reach ≠ authority reach. `read` may resolve while `path:read()` fails
because no compatible filesystem world is reachable.

## Algebraic projection

Do not create package algebra. Ordinary table/home/value algebra is sufficient.

If table composition is admitted, `tools = a + b` may produce another ordinary
table when the `+` relation law genuinely means composition.

Never `PackageUnion`, `ImportMerge`, or `ModuleOverlay`. If no admitted relation
expresses the required composition: `SEMANTIC-VOCABULARY-BLOCKED`.

Conditional visibility is ordinary control/value semantics at scope construction
time, not conditional import syntax.

## Standard vocabulary

There is no `std`.

Canonical vocabulary is the compiler-owned set of admitted semantic identities
that participate in initial resolution — for example `len`, `iter`, `find`, `at`,
`read`, `write`, `run`, `to`, `from` only where current vocabulary authority
admits them.

The initial source context has canonical vocabulary reach directly:

```text
canonical identity len   reachable
canonical identity iter  reachable
canonical identity read  reachable
```

Do not model startup as inject standard. Do not create independent standard
registries for compiler, formatter, LSP, MCP, shell, or docs.

User packages project the same classes of semantic things as the standard
environment. The difference is provenance and initial reachability, not semantic
law.

## Build composition

The build system constructs root reachability and program worlds. Same source may
run under different contexts. Build files do not create a second language
ontology.

Build-time acquisition (find, fetch, verify, cache, compile) belongs to the
build world. It does not grant those capabilities to the compiled program.

## Foreign systems

Foreign module/package systems remain foreign. Lua `require`, Wasm imports,
Python imports remain foreign-law provenance. When semantics correspond, project
them into the same idol graph. Do not assimilate their module ontology into
native Idol.

Native `.id` resolution must never semantically become name → Lua require → Lua
table → string lookup → native relation.

## req closure

`req` is migration only.

Targets:

```text
new req source = 0
new req compiler semantic authority = 0
new req optimization = 0
new req positive teaching fixtures = 0
```

Decompose existing req machinery into source provenance, root reachability,
binding resolution, dependency demand, and realization. Do not rename req
machinery to package or projection. Delete the separate ontology.

## Agent architecture prohibition

Agents must not introduce host-shaped concepts such as `Module`, `ModuleMap`,
`Import`, `Namespace`, `PackageLoader`, `ExportTable`, `DependencyContainer`,
`ServiceLocator`, `Provider`, `CapabilityInjector`, `WorldRegistry`,
`PreludeTable`, or `StdTable` simply because host convention suggests them.

Before creating any host structure ask what idol semantic facts this projects. If
existing facts suffice, use/project them. If no admitted fact expresses the
needed meaning: `SEMANTIC-VOCABULARY-BLOCKED`.

## Ratchets

Measured zero-new-debt gates on every added canonical line:

```text
new req = 0
new native require = 0
new import = 0
new use = 0
new using = 0
new module ontology = 0
new namespace ontology = 0
new package runtime = 0
new injection framework = 0
new package-grants-world = 0
new duplicated world wrapper = 0
new path-as-identity = 0
new runtime standard table = 0
new compound semantic filenames = 0
```

`gates/path.id` enforces LAW-ONE path names on staged paths and the tracked tree.
`scripts/idiomgate.id` remains a lexical migration preflight on added lines only;
it must not be reported as semantic canonicality. Closure, namespace, length,
cast, world, and relation identity verdicts belong to production parse → resolve
→ graph → obligation query (`GAP-124`, `scripts/canon.id`). Delete idiomgate
semantic substring detectors as each graph obligation executes on staged diffs.

## FTCFTW

Graph-first compilation:

```text
.id → graph → demand → realization → machine
```

Never `.id → module loader → namespace graph → runtime module tables → graph`.

For equivalent semantics, idol must not pay for package abstraction, scope
abstraction, statically settled world abstraction, standard vocabulary lookup, or
source-file boundaries unless observation demands them.

Sealed programs target zero runtime module initialization, zero standard namespace
initialization, zero package registry, zero import string lookup, zero capability
registry, and zero unused world setup.

## Absolute law

- Idol has no native module system, import system, namespace system, dependency
  injection system, capability injection system, or standard library object.
- Files are source partitions. Directories may project homes.
- Packages are distribution provenance for anchored ordinary tables/homes.
- Tables project ordinary semantic values. Scopes contain reachability facts.
  Worlds contain authority facts.
- References establish dependency. Selectivity is narrower reachability.
- Cross projection is ordinary projection across homes.
- Algebraic projection is ordinary value/table algebra.
- Conditional projection is ordinary control/value semantics.
- Standard vocabulary is initial canonical semantic reachability; it is not `std`.
- A package never grants a world. A world never creates a package.
- A path never creates semantic identity. A projection never duplicates semantic
  identity. A witness explains every omitted or recovered fact.
- Demand decides physical existence. Realization chooses the cheapest lawful
  machine form.
