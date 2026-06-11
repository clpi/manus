# duo-lsp

Language Server Protocol implementation for the [Duo](https://github.com/clpi/luo-duo) programming language.

## Features

- **Completion** — Keywords, type keywords, built-in functions, attributes, and snippet templates
- **Document symbols** — Functions, enums, concepts, aliases, locals, and constants
- **Hover** — Documentation for keywords, types, and user-defined symbols
- **Go-to-definition** — Jump to function/enum/concept/alias declarations
- **Diagnostics** — Runs `duo check` on save and reports errors/warnings inline

## Installation

```bash
cd ext/duo-lsp
npm install
npm run build
npm link   # makes `duo-lsp` available globally
```

## Usage

The server communicates over stdio. Point your editor's LSP client at the `duo-lsp` binary.

### Neovim (via nvim-lspconfig)

```lua
local lspconfig = require('lspconfig')
local configs = require('lspconfig.configs')

configs.duo = {
  default_config = {
    cmd = { 'duo-lsp' },
    filetypes = { 'duo' },
    root_dir = lspconfig.util.root_pattern('build.duo', '.git'),
    settings = {},
  },
}

lspconfig.duo.setup({})
```

### Helix

Add to `~/.config/helix/languages.toml`:

```toml
[language-server.duo-lsp]
command = "duo-lsp"
```

### VSCode

Install the `vscode-duo` extension — it starts `duo-lsp` automatically.

### Zed

The `zed-duo` extension references `duo-lsp` as a language server.

## Configuration

The server accepts initialization options:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `duoBinary` | `string` | `"duo"` | Path to the Duo compiler binary |
