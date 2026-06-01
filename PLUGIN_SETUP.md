# Duo Neovim/Vim Plugin Setup

## Plugin Structure

The Duo plugin follows the standard Vim plugin structure:

```
duo/
├── ftdetect/
│   └── duo.vim          # Filetype detection for .duo files
├── syntax/
│   └── duo.vim          # Syntax highlighting rules
├── plugin/
│   └── duo.vim          # Plugin initialization
└── lua/
    └── duo/
        └── init.lua     # Lua API for Neovim
```

## Installation

### Using lazy.nvim (Recommended for Neovim)

Add to your `~/.config/nvim/init.lua`:

```lua
{
    "clpi/duo",
    lazy = false, -- Load immediately for filetype detection
}
```

Or with configuration:

```lua
{
    "clpi/duo",
    lazy = false,
    config = function()
        require("duo").setup({
            tabstop = 4,
            shiftwidth = 4,
        })
    end
}
```

### Using packer.nvim (Neovim)

```lua
use {
    "clpi/duo",
    config = function()
        -- Plugin loads automatically
    end
}
```

### Using vim-plug (Vim/Neovim)

Add to your `.vimrc` or `init.vim`:

```vim
Plug 'clpi/duo'
```

Then run `:PlugInstall`

### Manual Installation

For Neovim:
```bash
git clone https://github.com/clpi/duo.git ~/.local/share/nvim/site/pack/duo/start/duo
```

For Vim:
```bash
git clone https://github.com/clpi/duo.git ~/.vim/pack/duo/start/duo
```

## Features

### Syntax Highlighting

The plugin provides syntax highlighting for:

- **Keywords**: `fun`, `function`, `req`, `global`, `local`, `const`, `struct`
- **Control Flow**: `if`, `then`, `elseif`, `else`, `while`, `repeat`, `until`, `for`, `in`, `do`, `break`
- **Values**: `true`, `false`, `nil`
- **Operators**: `and`, `or`, `not`, `##` (metaprogramming), `+`, `-`, `*`, `/`, etc.
- **Type Annotations**: `: i64`, `: f64`, `: str`, `: bool`, `: void`, `<T>`
- **Strings**: Single quotes, double quotes, multi-line `[[...]]`
- **Numbers**: Integers, floats, hexadecimal, scientific notation
- **Comments**: `--` single-line comments
- **Standard Library**: `print`, `math`, `string`, `table`, etc.

### Automatic Configuration

The plugin automatically sets:
- `tabstop=4`
- `shiftwidth=4`
- `expandtab=true`
- `commentstring=--%s`

## Testing

To test the plugin locally:

```bash
./test_plugin.sh
```

Or manually:
```bash
nvim --cmd 'set rtp+=.' examples/syntax_test.duo
```

## Example

```duo
-- Syntax highlighting example
fun greet(name: str): str
    return "Hello, " .. name
end

fun add<T>(a: T, b: T): T
    return a + b
end

local result: i64 = ##1 + 2
global counter: i64 = 0

struct Point
    x: f64
    y: f64
end

print greet "World"
print add 5 3
```

## Filetype Detection

The plugin automatically detects `.duo` files and sets the filetype to `duo`, which enables syntax highlighting and Duo-specific configurations.

## Troubleshooting

If syntax highlighting doesn't work:

1. Ensure the plugin is in your runtimepath (`:echo &rtp`)
2. Check filetype detection: `:set filetype?` (should be `duo`)
3. Manually set filetype: `:set filetype=duo`
4. Check for syntax errors: `:syntax`

## License

Same as the Duo compiler project.