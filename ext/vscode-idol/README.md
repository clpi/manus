# Idol for VS Code

This bootstrap extension associates `.id` files with Idol and starts
`idol-lsp`. The current server supplies diagnostics and document symbols.

Syntax highlighting and snippets are deliberately absent. They must be
generated from Idol's one law-qualified grammar authority; a handwritten
TextMate grammar or snippet catalogue would be a second source-language
authority. Formatting, completion, go-to-definition, and semantic tokens are
also not claimed because the current server does not implement them.

## Current surface

- `.id` file association;
- `#` line-comment toggling and neutral quote/bracket pairing;
- diagnostics from `idol-lsp`;
- document symbols from `idol-lsp`.

## Installation

This directory is a repository integration, not a Marketplace release. Install
its runtime dependency, then load the directory as a VS Code extension:

```sh
cd ext/vscode-idol
npm install --omit=dev
```

Install `idol-native/bin/idol-lsp` on `PATH`, or set `idol-lsp.path` to its
absolute path.

## Configuration

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `idol-lsp.enable` | `boolean` | `true` | Enable the Idol language server |
| `idol-lsp.path` | `string` | `"idol-lsp"` | Path to the Idol language server binary |
