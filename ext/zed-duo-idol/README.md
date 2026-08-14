# Zed Extension for Idol

Idol language support for the Zed editor — syntax highlighting, outline, and bracket matching via tree-sitter.

## Installation

Clone this extension into your Zed extensions directory:

```sh
# macOS
git clone <this-repo> ~/.config/zed/extensions/work/idol

# Linux
git clone <this-repo> ~/.config/zed/extensions/work/idol
```

Or symlink it:

```sh
ln -s /path/to/idol/ext/zed-idol ~/.config/zed/extensions/work/idol
```

Restart Zed. Open any `.id` file to activate.

## Features

- Syntax highlighting via tree-sitter
- Symbol outline (functions, enums, concepts, aliases, locals)
- Bracket matching and autoclosing
- Block and line comment toggling
- Configured for `idol-lsp` language server and `idol fmt` formatter
