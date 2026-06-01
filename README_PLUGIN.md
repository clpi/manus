# Duo Neovim/Vim Plugin

Syntax highlighting for the Duo programming language in Neovim and Vim.

## Installation

### Using lazy.nvim (Neovim)

Add this to your Neovim configuration (typically `~/.config/nvim/init.lua`):

```lua
{
    "clpi/duo",
    lazy = false, -- Load immediately to enable syntax detection
}
```

### Using packer.nvim (Neovim)

```lua
use {
    "clpi/duo",
    config = function()
        -- Plugin is loaded automatically
    end
}
```

### Using vim-plug (Vim/Neovim)

Add to your `.vimrc` or `init.vim`:

```vim
Plug 'clpi/duo'
```

### Manual Installation

1. Clone this repository:
```bash
git clone https://github.com/clpi/duo.git ~/.local/share/nvim/site/pack/duo/start/duo
```

2. For Vim, clone to:
```bash
git clone https://github.com/clpi/duo.git ~/.vim/pack/duo/start/duo
```

## Features

- **Syntax highlighting** for `.duo` files
- **Keyword highlighting** for Duo-specific keywords (`fun`, `req`, `global`, `struct`, etc.)
- **Type annotation highlighting** for type signatures (`: i64`, `: f64`, `: str`, etc.)
- **Operator highlighting** including metaprogramming operator (`##`)
- **Comment highlighting** for `--` comments
- **String and number literals** highlighting
- **Standard library function** highlighting

## Duo Language Features Highlighted

### Keywords
- `fun`, `function` - Function declaration
- `req` - Shorthand for require
- `global` - Global variable declaration
- `local` - Local variable declaration
- `const` - Constant declaration
- `struct` - Struct definition

### Type Annotations
- `: i64` - 64-bit integer
- `: f64` - 64-bit float
- `: str` - String
- `: bool` - Boolean
- `: void` - Void/nil return type
- `<T>` - Generic type parameter

### Operators
- `##` - Compile-time evaluation
- `+`, `-`, `*`, `/`, `%`, `^` - Arithmetic
- `==`, `~=`, `<`, `>`, `<=`, `>=` - Comparison
- `and`, `or`, `not` - Logical
- `..` - String concatenation

### Example

```duo
fun greet(name: str): str
    return "Hello, " .. name
end

fun add<T>(a: T, b: T): T
    return a + b
end

local result: i64 = ##1 + 2
print greet "World"
```

## Configuration

The plugin automatically configures:
- `tabstop=4`
- `shiftwidth=4`
- `expandtab=true`
- `commentstring=--%s`

You can override these in your configuration:

```vim
autocmd FileType duo setlocal tabstop=2
autocmd FileType duo setlocal shiftwidth=2
```

## License

Same as the Duo compiler project.