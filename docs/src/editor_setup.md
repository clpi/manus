# Editor Setup

Duo has its own syntax highlighting, but because its grammar is a superset of Lua you can also fall back to Lua highlighting where a dedicated plugin is not available.

## Official Duo plugins / extensions

The repository contains editor support under `ext/`. These plugins provide full Duo syntax highlighting (including typed functions, type keywords, attributes, `match`, `async`/`await`, and more), file-type detection, indentation, and LSP integration.

- **VS Code**: `ext/vscode-duo/` — TextMate grammar, snippets, and `duo-lsp` integration.
- **Vim / Neovim**: `ext/vim-duo/` — syntax file, filetype detection, indent rules, and ftplugin.
- **Helix**: `ext/helix/` — language registration, tree-sitter queries, and LSP config.
- **Zed**: `ext/zed-duo/` — tree-sitter extension with outline, brackets, and LSP config.

For installation details, see each extension's own `README.md`.

## LSP Setup

The `duo-lsp` server (in `ext/duo-lsp/`) provides:

- **Diagnostics** — Type-checking errors from `duo check`
- **Document symbols** — Outline view of top-level declarations
- **Hover** — Symbol information on mouse-over
- **Go-to-definition** — Jump to declaration
- **Completions** — Keywords, types, builtins, std modules, and snippets

To use LSP manually:

```sh
# Build the LSP binary
duo compile ext/duo-lsp/src/server.duo -o duo-lsp
export DUO_LSP_DUO_BIN="$PWD/zig-out/bin/duo"

# Then configure your editor to spawn the `duo-lsp` binary
```

## Fallback: associate `.duo` with Lua

If you do not install an official plugin, configure your editor to treat `.duo` files as Lua. This gives you bracket matching, comments, strings, and most Lua keywords, but it will not highlight Duo-specific syntax such as `fun`, type annotations, `@attributes`, or `match`.

### Visual Studio Code (VS Code)

1. Open your settings using the Command Palette (`Ctrl+Shift+P` or `Cmd+Shift+P`) and type `Preferences: Open User Settings (JSON)`.
2. Add the following file association mapping to your configuration:

```json
{
    "files.associations": {
        "*.duo": "lua"
    }
}
```

### Neovim / Vim

Add the following to your Neovim or Vim configuration to detect `.duo` files as Lua.

**For Neovim (`init.lua`):**
```lua
vim.filetype.add({
  extension = {
    duo = 'lua',
  }
})
```

**For Vim / Neovim (`init.vim` / `.vimrc`):**
```vim
autocmd BufRead,BufNewFile *.duo set filetype=lua
```

### Other Text Editors

For most other text editors or IDEs, look for "File Associations" or "Language Settings" and map the `.duo` extension to the Lua language. Alternatively, you can often manually set the language mode to "Lua" when opening a `.duo` file.
