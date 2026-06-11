# vim-duo

Vim and Neovim support for the [Duo](https://github.com/duo-lang/duo) programming language.

## Features

- File type detection for `.duo` files (and `.lua` with Duo extensions)
- Syntax highlighting (all Lua + Duo keywords, types, attributes, operators)
- Indentation rules (handles `fun`/`enum`/`concept`/`alias`/`match`/`try`/`defer`/`catch` blocks)
- File type plugin (comment formatting, tabs, suffixes)

## Tree-sitter support

For richer highlighting, incremental parsing, and text objects, use the
[tree-sitter-duo](../tree-sitter-duo/) grammar with Neovim's built-in
tree-sitter integration. The Vim syntax file here serves as a complete fallback
for non-tree-sitter Vim.

## Installation

### [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'duo-lang/duo', { 'rtp': 'ext/vim-duo' }
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use { 'duo-lang/duo', rtp = 'ext/vim-duo' }
```

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{ 'duo-lang/duo', ft = 'duo', config = function()
  vim.opt.rtp:append('ext/vim-duo')
end }
```

Or with `dir` pointing to a local clone:

```lua
{ dir = '/path/to/duo/ext/vim-duo', ft = 'duo' }
```

### Manual

Copy or symlink the directories into your runtime path:

```sh
cp -r ext/vim-duo/* ~/.vim/
# or for Neovim:
cp -r ext/vim-duo/* ~/.config/nvim/
```

Then restart Vim/Neovim or run `:filetype detect`.
