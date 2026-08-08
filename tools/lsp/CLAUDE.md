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
- Hover documentation

## Editor setup

Add to your editor's LSP config:
```json
{
  "duo": {
    "command": "/Users/clp/x/duo/zig-out/bin/duo",
    "args": ["lsp"],
    "filetypes": ["duo"]
  }
}
```
