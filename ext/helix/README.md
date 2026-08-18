# Idol for Helix

This bootstrap registration associates `.id` files with Idol and starts
`idol-lsp`. The current server supplies diagnostics and document symbols.

No Tree-sitter grammar or query set is installed here. Highlighting, syntax
text objects, formatter integration, completion, go-to-definition, and semantic
tokens remain withheld until they are projected from the shared grammar or
semantic authority that owns them.

Append the `[language-server.idol-lsp]` and `[[language]]` entries from
`languages.toml` to the Helix language configuration. Install
`idol-native/bin/idol-lsp` on `PATH`; Helix then starts it for `.id` buffers.
