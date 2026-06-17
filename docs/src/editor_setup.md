# Editor Setup

Because Duo's syntax is heavily inspired by Lua, the easiest way to get editor support (such as syntax highlighting, auto-indentation, and bracket matching) is to configure your editor to treat `.duo` files as Lua files.

## Visual Studio Code (VS Code)

To automatically get syntax highlighting for `.duo` files in VS Code:

1. Open your settings using the Command Palette (`Ctrl+Shift+P` or `Cmd+Shift+P`) and type `Preferences: Open User Settings (JSON)`.
2. Add the following file association mapping to your configuration:

```json
{
    "files.associations": {
        "*.duo": "lua"
    }
}
```

## Neovim / Vim

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

## Other Text Editors

For most other text editors or IDEs, look for "File Associations" or "Language Settings" and map the `.duo` extension to the Lua language. Alternatively, you can often manually set the language mode to "Lua" when opening a `.duo` file.
