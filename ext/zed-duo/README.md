# Zed Extension for Duo

Duo language support for the Zed editor — syntax highlighting, outline, and bracket matching via tree-sitter.

## Installation

Clone this extension into your Zed extensions directory:

```sh
# macOS
git clone <this-repo> ~/.config/zed/extensions/work/duo

# Linux
git clone <this-repo> ~/.config/zed/extensions/work/duo
```

Or symlink it:

```sh
ln -s /path/to/duo/ext/zed-duo ~/.config/zed/extensions/work/duo
```

Restart Zed. Open any `.id` file to activate.

## Features

- Syntax highlighting via tree-sitter
- Symbol outline (functions, enums, concepts, aliases, locals)
- Bracket matching and autoclosing
- Block and line comment toggling
- Configured for `duo-lsp` language server and `duo fmt` formatter
