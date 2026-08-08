# duo-lsp — Duo Language Server

LSP server for the Duo language, implemented in **Duo**. Depends on the `duo` compiler from `~/x/duo`.

## Dependency

```bash
cd ~/x/duo && zig build -Doptimize=ReleaseFast
# duo binary: ~/x/duo/zig-out/bin/duo
```

## Build & run

```bash
duo run build.duo   # builds the LSP server binary using duo
duo run src/main.duo  # run directly with duo (dev mode)
```

The build script uses `DUO_LSP_DUO_BIN` env var to locate the `duo` binary, falling back to `../../zig-out/bin/duo` then `$(which duo)`.

## Source layout

```
src/server.duo   the LSP server (protocol, diagnostics, symbols, sync)
build.duo        build script
test/smoke.duo   end-to-end handshake against the real duo binary
vendor → ~/x/duo/lib   Symlink to duo stdlib
```

This repo is 100% Duo. `lib/*.js` and the Node test harness were deleted — the
JS was a reimplementation of logic `src/server.duo` already owned, and nothing
shipped it.

## LSP features

- Go-to-definition for Duo symbols
- `@comp.*` directive catalog and completions
- Diagnostics from the Duo compiler
- Hover — a projection of `duo graph`, the compiler's semantic graph

## Pass 101 §3: this server is a PROJECTION, not a second compiler

The ruling is one graph service, N protocol front-ends. When a fact about the
code is needed, ASK THE COMPILER — `duo graph`, `duo check
--plain-diagnostics`, `duo sim --import-c` — and do not grow another line
scanner beside it. `graph_for` in `src/server.duo` is the query client; hover
goes through it.

Two scanners still exist and are NOT licence to add a third: the top-level
symbol scanner (the graph lifts no node for module bindings — measured) and the
word-boundary reference scanner (`duo graph` emits nodes but no edges, so
`usersOf` is unreachable from the CLI). Both are documented as gaps in
`README.md` with the measurement that keeps them. Close the gap in the
compiler, then delete the scanner — not the other way round.

## Editor setup

The server is its OWN binary, built by `build.duo`. There is no `duo lsp`
subcommand — measured: `grep -c '"lsp"' src/main.zig` is 0, and `duo help` does
not list one. Point your editor at the built binary:

```json
{
  "duo": {
    "command": "<DUO_ROOT>/tools/lsp/duo-lsp",
    "filetypes": ["duo", "lua"]
  }
}
```
