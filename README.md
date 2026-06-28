# duo-lsp

A Language Server Protocol implementation for the [Duo](../..) language. It
wraps the `duo` compiler's `check` command for live diagnostics and ships a
best-effort top-level symbol outline, hover, go-to-definition, and completion — all over
stdio JSON-RPC. The server itself is written in Duo and compiled to a self-contained binary.

## Features

- **Diagnostics** — on open / change / save, the server writes the document to
  a temp file and runs `duo check`, then publishes parsed diagnostics. Both
  `.duo` and `.lua` documents are supported (the compiler selects the language
  mode by extension).
- **Document symbols** — a light line-scanner finds top-level `fun`/`function`,
  `enum`, `concept`, `alias`, `struct`, and variable declarations for the
  outline. Nested declarations (inside `fun`/`enum`/`match`/`{...}`) are
  excluded.
- **Hover** — returns the declaration line and kind of the top-level symbol at
  the cursor.
- **Go-to-definition** — jumps to the declaration of a top-level symbol.
- **Completions** — provides keyword completions, type names, builtin functions,
  std module names, and function/snippet templates.
- **Incremental text sync** — `textDocument/didChange` with range edits is
  applied in order; full-replace changes are handled too.

## Layout

```
duo-lsp            compiled binary (#!/usr/bin/env node not needed; self-contained)
src/server.duo     LSP server implementation in Duo
package.json       npm manifest (for tests)
test/run-tests.js  unit tests (parser, scanner, text sync)
test/smoke.js      end-to-end handshake against the real duo binary
build.sh           build script: `duo compile -o duo-lsp src/server.duo`
```

## Resolving the `duo` compiler

The server locates the `duo` binary in this order:

1. `DUO_LSP_DUO_BIN` env var (checked at startup) — or `DUO_BIN`.
2. `duo` sibling next to the `duo-lsp` launcher's parent's parent (`../../duo`),
   which matches the layout when both are installed in the same `bin` dir.
3. `duo` on `PATH`.

If none is found, the server starts but diagnostics are disabled (symbols and
hover still work).

## Running

```sh
# from the duo repo root, after `zig build`:
export DUO_LSP_DUO_BIN="$PWD/zig-out/bin/duo"
./ext/duo-lsp/duo-lsp           # speaks LSP on stdin/stdout
```

### Tests

```sh
cd ext/duo-lsp
npm test            # unit tests: diagnostic parser + symbol scanner + sync
npm run smoke       # full LSP handshake against the real duo binary
```

The smoke test opens a `.lua` document with an undeclared global, asserts a
diagnostic is published, requests document symbols / hover / completion, and shuts down
cleanly. It defaults to `../../zig-out/bin/duo`; override with
`DUO_LSP_DUO_BIN`.

## Editor integration

The sibling `ext/vscode-duo` extension already spawns a `duo-lsp` binary over
stdio (see its `extension.js`). To use this server in VS Code:

1. `zig build` the compiler.
2. Symlink or copy the duo-lsp binary onto `PATH`:
   ```sh
   ln -s "$PWD/ext/duo-lsp/duo-lsp" /usr/local/bin/duo-lsp
   ```
   …or set `duo-lsp.path` in VS Code settings to the absolute path of
   `ext/duo-lsp/duo-lsp`.
3. Reload the window; open a `.duo`/`.lua` file.

For Neovim, point an `lspconfig`/manual `vim.lsp.start` server entry at the
launcher with `cmd = { "duo-lsp" }` and `filetypes = { "duo", "lua" }`.

## Diagnostic format note

The Duo compiler (Zig 0.17-dev) currently emits locations as a debug struct
dump rather than the intended `path:line:col` form, e.g.:

```
.{ .file = { 47, 116, … }, .line = 2, .col = 1 }: error: attempt to assign to const variable 'x'
```

The LSP server parses both this debug-dump form **and** the clean
`path:line:col: error: msg` form, so diagnostics work correctly. The temp file
path is never reported to the client.

## Limitations

- The symbol scanner is line-oriented and best-effort; it does not run the
  parser, so deeply nested or unusual declaration shapes may be missed. It is
  intentionally scoped to top-level declarations.
- Hover/definition resolve only top-level declarations (no cross-file or
  type-aware resolution).
- No rename support yet.