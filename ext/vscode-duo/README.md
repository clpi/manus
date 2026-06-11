# Duo — VSCode Extension

Syntax highlighting, snippets, and language server integration for the [Duo](https://github.com/duo-lang/duo) programming language.

## Features

- **Syntax highlighting** — Full TextMate grammar covering all Duo tokens: keywords, type keywords, comments (line and block), strings (single/double/long), numbers (integers, floats, hex), attributes, operators, and type annotations.
- **Snippets** — 18 snippets for common constructs: typed/untyped functions, control flow, match, enum, concept, alias, try/catch, defer, local/const bindings, and test blocks.
- **Language server integration** — Connects to `duo-lsp` for diagnostics, completion, and go-to-definition when the binary is available.
- **Language configuration** — Bracket matching, auto-closing pairs, comment toggling, folding markers, and indentation rules.

## Installation

### From VSIX

```bash
code --install-extension duo-0.1.0.vsix
```

### From Marketplace

Search for **"Duo"** in the Extensions panel and click Install.

### Manual

Copy this directory into your VSCode extensions folder:

- **macOS**: `~/.vscode/extensions/duo-lang-duo-0.1.0/`
- **Linux**: `~/.vscode/extensions/duo-lang-duo-0.1.0/`
- **Windows**: `%USERPROFILE%\.vscode\extensions\duo-lang-duo-0.1.0\`

## Configuration

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `duo-lsp.enable` | `boolean` | `true` | Enable the Duo language server |
| `duo-lsp.path` | `string` | `"duo-lsp"` | Path to the Duo language server binary |
| `duo-lsp.trace` | `string` | `"off"` | LSP trace level: `off`, `messages`, or `verbose` |

## Snippets

| Prefix | Expands to |
|--------|------------|
| `fun` | Typed function |
| `fn` | Untyped function |
| `if` | If statement |
| `ifel` | If-else statement |
| `for` | For-in loop |
| `fori` | Numeric for loop |
| `while` | While loop |
| `match` | Match expression |
| `enum` | Enum definition |
| `concept` | Concept definition |
| `alias` | Type alias |
| `try` | Try-catch block |
| `catch` | Catch clause |
| `defer` | Defer block |
| `local` | Local typed binding |
| `const` | Constant binding |
| `test` | Test function |
