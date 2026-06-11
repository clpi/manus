# Helix editor support for Duo

## Installation

### 1. Register the language

Append the `[language-server.duo-lsp]`, `[[language]]`, and `[[grammar]]` entries
from `languages.toml` into your Helix languages config:

```sh
cat languages.toml >> ~/.config/helix/languages.toml
```

### 2. Copy queries

Copy the query files into Helix's runtime directory under `queries/duo/`:

```sh
HELIX_RUNTIME=$(helix --helix-runtime 2>/dev/null || echo "$HOME/.config/helix")
mkdir -p "$HELIX_RUNTIME/queries/duo"
cp queries/*.scm "$HELIX_RUNTIME/queries/duo/"
```

### 3. Build the tree-sitter grammar

Helix will compile the grammar from the `source.path` specified in
`languages.toml`. Make sure the relative path `../tree-sitter-duo` resolves
correctly from the `ext/helix/` directory, or adjust it to an absolute path.

```sh
# From the Duo repo root:
helix --grammar fetch
helix --grammar build
```

### 4. Language server (optional)

If you have `duo-lsp` installed and on your `PATH`, Helix will use it
automatically. Otherwise, remove `language-servers = ["duo-lsp"]` from the
`[[language]]` entry.

## File structure

```
ext/helix/
├── languages.toml          # Language + grammar registration
├── queries/
│   ├── highlights.scm      # Syntax highlighting
│   ├── injections.scm      # Embedded language injections
│   ├── locals.scm          # Scope and reference tracking
│   └── textobjects.scm     # Text object queries
└── README.md
```
