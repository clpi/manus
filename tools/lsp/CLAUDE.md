# duo-lsp — Duo Language Server

LSP server for the Duo language, implemented in **Duo**. Depends on the `duo`
compiler from `~/x/duo`.

## Dependency

```bash
cd ~/x/duo && zig build -Doptimize=ReleaseFast
# duo binary: ~/x/duo/zig-out/bin/duo
```

## Build & run

```bash
duo run build.duo       # builds the LSP server binary using duo
duo run src/server.duo  # run directly with duo (dev mode; speaks stdio LSP)
```

The build script uses `DUO_LSP_DUO_BIN` to locate the `duo` binary, falling back
to `../../zig-out/bin/duo` then `$(which duo)`.

## The gate — read this first

`zig build lsp-gate`, wired into `agent-smoke` (tier 0). Until 2026-08-08 there
was **no gate for this server at all**, which is the position all three MCP
servers were in when they turned out to be dead for an unknown period and
nothing noticed.

It was carrying the defect that position produces. **`textDocument/didClose`
SEGFAULTED the server** — exit 139, no diagnostic, no partial answer, no reply
to anything afterwards. `t[k] = nil` does not remove a key in Duo; it stores nil
at it, and every later `for k, v in t` still yields that key. `flush_dirty` runs
after EVERY message, so it walked the docs table, found the nil and
dereferenced it. **Every editor closes documents.** Nobody had ever run one.

The repair is `forget(t, key)` in `src/server.duo` — removal is a REBUILD that
returns the new table — plus a nil guard at every site that iterates `docs` or
`ws.entries`. The same nil-key hazard killed `workspace/symbol` and
`textDocument/completion` after any close, through `rawlen(nil)`.

The gate speaks real LSP framing (`Content-Length: N\r\n\r\n{…}`) and asserts
response BYTES. **Everything it scores happens AFTER a document has been opened
and CLOSED**, so a server that dies mid-session cannot score. It is
positive-controlled by `LSPGATE_SERVER`, which points it at a corrupted copy;
three runs are recorded in the file header, and the sharp one is that deciding
the copula/invoke split by SPACING instead of grammar.md R1 moves exactly one
integer in the asserted token array and turns exactly one row red.

## The traps this file is one bug away from at all times

Inherited from `tools/mcp/CLAUDE.md`, which paid for them, plus the one this
server paid for itself.

1. **`t[k] = nil` DOES NOT REMOVE THE KEY.** Use `forget`. Any loop over a table
   a key was ever nil'd out of must guard `v ~= nil`. This is the didClose
   segfault above and it is invisible until you run it.
2. **Every `req` at FILE SCOPE**, and project modules spelled from the project
   root (`req "tools.lsp.src.x"`, never a bare name). A `req` inside a handler
   binds a local the handler's closures try to capture; Duo has no closure
   capture, so lowering emits an undeclared `duo_make_closure_N` and the server
   fails to BUILD while still passing `duo check`.
3. **No file-scope FUNCTION calls from inside a tool handler** in the MCP sense.
   This server's handlers are called from `handle_message`, which is itself file
   scope, so the shape is fine here — but do not introduce a nested-closure
   layer without re-checking it.
4. **A Duo script's `main` return value is DROPPED.** Gates must `std.os.exit(1)`
   or they exit 0 while printing failures, and `zig build` reads that as success.
5. **`"{expr}"` interpolation only substitutes plain bindings and field walks.**
   `"{#xs}"` stays literal. Bind the length first.

## Pass 117 §0g — the three methods, and what each actually does

- **`textDocument/semanticTokens/full`** — the legend is **GENERATED** by
  `tools/lsp/legend.duo` from `docs/spec/roles.md` §2 (the closed 17) and §3
  (the roles the law requires and gives no hue). Hand edits to the marked block
  in `src/server.duo` are an H-1 drift finding and `lsp-gate` re-derives the
  block on every run. Spans with two live roles and no rule between them emit
  **NO token** — "two candidates is a MIXED-SPACE DIAGNOSTIC, never a guess",
  and a fallback role would be the guess wearing a hat.
- **`textDocument/inlayHint`** — CDR-inferred descriptors (B-13). The inference
  is **`duo sim`'s**, not this server's: sim-v0 reports a resolved
  `return_type` where the source declared none. The C→duon spelling map is
  exhaustive over what sim emits and DECLINES on anything else. Module bindings
  are the literal's own descriptor, read from grammar.md §1, because sim lifts
  no entity for `total = 7`.
- **`textDocument/codeLens`** — lenses count witnesses. Stated plainly because
  the number would otherwise be read as more than it is: **Pass 104 admission
  witnesses have no surface in this tree** (`witness` is role 17 in roles.md §2
  with an empty decider; `why` is undeclared, gap[064]). What the lenses count
  is the evidence that exists and is named on each lens — the G-TOTAL role
  census for the file, and the use sites for each top-level binding.

**`why(span)` IS the hover (H-7).** Hover now carries the role at the cursor,
whether that role is in the closed 17 or unhued, and the rule that decided it.

## GAP-078 — there are TWO role taxonomies in this directory

`tools/lsp/src/highlight.duo` landed the same day with an **18**-member closed
set, `place` where roles.md §2 says `name`, `text` where it says `literal`, the
§0g fine splits demoted to "cards", no `ambiguous` member — and it decides the
copula/invoke split by **SPACING** where roles.md §5.1 decides it by
**grammar.md R1**. On `count:u32` they answer differently, and both corpora
under `fixtures/highlight/` are golden.

`src/server.duo` and `legend.duo` follow roles.md and R1, because that is the
tracked spec in `docs/spec/`. **That is not a ruling.** Read `gaps/GAP-078.md`
before reconciling them, and never publish a G-TOTAL percentage from either
side without naming which taxonomy produced it.

## G-TOTAL baseline for the LSP front end (Pass 117, measured 2026-08-08)

H-8 OUTPUT TOTALITY: every emission is graph data rendered through the role
taxonomy, and **plain-string output is a finding**. The baseline, so the
migration has a number to move:

| | methods |
|---|---|
| dispatch arms in `src/server.duo` | **21** (20 distinct; `semanticTokens` has two spellings) |
| emit a response body | **13** |
| emit **at least one human string with no role and no why** (H-8 finding) | **5** |
| carry a `(span, role, why, dnir)` tuple | **3** |

The five findings are `textDocument/publishDiagnostics` (the compiler's
`message` prose, passed through untyped), `textDocument/completion`
(`label`/`detail`), `textDocument/documentSymbol` (`name`/`detail`),
`workspace/symbol` (`name`/`containerName`), and `textDocument/hover` — hover is
listed **despite** now carrying its why-chain, because LSP delivers it inside
`MarkupContent.value`, which is one string by protocol. That is a finding this
front end cannot repair alone and it should stay counted until the protocol
layer carries the tuple.

The three compliant are `codeLens` and `inlayHint`, which put the tuple in the
LSP `data` field beside the rendered title, and `semanticTokens`, whose payload
is nothing but integers indexed into the generated role legend — the only
emission in the server that is role-typed all the way down.

`definition`, `references`, `rename`, `foldingRange`, `documentHighlight` and
`initialize` carry no prose at all, so they are neither findings nor tuples.

## Pass 101 §3: this server is a PROJECTION, not a second compiler

One graph service, N protocol front-ends. When a fact about the code is needed,
ASK THE COMPILER — `duo graph`, `duo sim`, `duo check --plain-diagnostics` — and
do not grow another line scanner beside it.

Three scanners still exist and are NOT licence to add a fourth:

- the top-level symbol scanner (the graph lifts no node for module bindings —
  measured, and it also **misses `ratio = 1.5`**, so a float-literal binding is
  invisible to documentSymbol, hover, hints and lenses alike);
- the word-boundary reference scanner (`duo graph` emits nodes but no edges, so
  `usersOf` is unreachable from the CLI);
- the **role scanner** added for `semanticTokens`, which exists only because the
  graph service answers no role queries at all. It is convicted against
  `fixtures/highlight/*.roles.duo` by `lsp-gate`. When the graph answers roles,
  delete it and ask.

Close the gap in the compiler, then delete the scanner — not the other way
round.

## Editor setup

The server is its OWN binary, built by `build.duo`. There is no `duo lsp`
subcommand. Point your editor at the built binary:

```json
{
  "duo": {
    "command": "<DUO_ROOT>/tools/lsp/duo-lsp",
    "filetypes": ["duo", "lua"]
  }
}
```

## Files

```
src/server.duo   the LSP server — protocol, diagnostics, symbols, sync, roles
src/highlight.duo  a SECOND role taxonomy and projection — see GAP-078
gate.duo         zig build lsp-gate — the proof any of this works
legend.duo       generates the semantic-token legend from docs/spec/roles.md
build.duo        build script
test/smoke.duo   end-to-end handshake against the real duo binary
vendor → ~/x/duo/lib   Symlink to duo stdlib
```

`src/duo_keyword_classify.c` is a generated artifact and is **untracked**
(`tools/lsp/.gitignore`), so MONOGLOT and `zig build foreign-census` are
satisfied by construction — the census reports it nowhere because there is
nothing tracked to classify.
