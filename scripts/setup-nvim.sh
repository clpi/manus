#!/bin/bash
# Duo Neovim Integration Setup
# Run: bash scripts/setup-nvim.sh
#
# This script:
# 1. Builds duo-lsp if not already built
# 2. Symlinks the duo.nvim plugin into Neovim
# 3. Adds filetype and LSP config to Neovim
# 4. Installs tree-sitter grammar

set -e

DUO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NVIM_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
DUO_LSP_ROOT="$HOME/x/duo-lsp"

echo "╔══════════════════════════════════════════╗"
echo "║  Duo Neovim Setup                       ║"
echo "╚══════════════════════════════════════════╝"

# 1. Build duo compiler (needed for duo-lsp)
echo "→ Building duo compiler..."
if [ -f "$DUO_ROOT/zig-out/bin/duo" ]; then
    echo "  ✓ duo binary exists"
else
    echo "  Building..."
    cd "$DUO_ROOT" && zig build 2>/dev/null || echo "  ⚠ Build failed (may need zig 0.17)"
fi

# 2. Build duo-lsp
echo "→ Building duo-lsp..."
if [ -d "$DUO_LSP_ROOT" ]; then
    cd "$DUO_LSP_ROOT"
    if [ -f "duo-lsp" ]; then
        echo "  ✓ duo-lsp binary exists"
    else
        if [ -f "$DUO_ROOT/zig-out/bin/duo" ]; then
            "$DUO_ROOT/zig-out/bin/duo" compile src/server.duo -o duo-lsp 2>/dev/null && echo "  ✓ Built duo-lsp" || echo "  ⚠ Build failed"
        fi
    fi
else
    echo "  ⚠ ~/x/duo-lsp not found"
fi

# 3. Add duo.nvim to Neovim runtime path
echo "→ Setting up duo.nvim plugin..."
DUO_NVIM="$DUO_ROOT/ext/duo.nvim"
AFTER_DIR="$NVIM_CONFIG/after/plugin"
mkdir -p "$AFTER_DIR"

cat > "$AFTER_DIR/duo.lua" << 'NVIM_EOF'
-- Duo language support (auto-loaded by Neovim)
-- Source: ~/x/duo/ext/duo.nvim

-- Add duo.nvim to runtime path
local duo_nvim_path = vim.fn.expand("~/x/duo/ext/duo.nvim")
if vim.fn.isdirectory(duo_nvim_path) == 1 then
  vim.opt.runtimepath:append(duo_nvim_path)
end

-- Filetype detection
vim.filetype.add({
  extension = { duo = "duo" },
})

-- File settings
vim.api.nvim_create_autocmd("FileType", {
  pattern = "duo",
  callback = function()
    vim.bo.commentstring = "-- %s"
    vim.bo.tabstop = 2
    vim.bo.shiftwidth = 2
    vim.bo.expandtab = true
    vim.bo.smartindent = true
  end,
})

-- LSP setup
local duo_lsp_bin = vim.fn.expand("~/x/duo-lsp/duo-lsp")
if vim.fn.filereadable(duo_lsp_bin) == 1 then
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "duo",
    callback = function(args)
      vim.lsp.start({
        name = "duo-lsp",
        cmd = { duo_lsp_bin },
        root_dir = vim.fs.dirname(vim.fs.find({"build.duo", ".git"}, {
          upward = true,
          path = vim.fs.dirname(args.file),
        })[1] or args.file),
      })
    end,
  })
end

-- Key mappings for Duo
vim.api.nvim_create_autocmd("FileType", {
  pattern = "duo",
  callback = function()
    local opts = { buffer = true, silent = true }
    -- Run current file
    vim.keymap.set("n", "<leader>dr", ":!duo run %<CR>", opts)
    -- Check current file
    vim.keymap.set("n", "<leader>dc", ":!duo check %<CR>", opts)
    -- Dump generated C
    vim.keymap.set("n", "<leader>dd", ":!duo dump-c %<CR>", opts)
    -- Format
    vim.keymap.set("n", "<leader>df", ":!duo fmt %<CR>", opts)
  end,
})
NVIM_EOF

echo "  ✓ Created $AFTER_DIR/duo.lua"

# 4. Tree-sitter grammar
echo "→ Setting up tree-sitter-duo..."
TS_PARSERS="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/site/parser"
if command -v tree-sitter &> /dev/null; then
    cd "$DUO_ROOT/ext/tree-sitter-duo"
    tree-sitter generate 2>/dev/null && echo "  ✓ Grammar generated" || echo "  ⚠ tree-sitter generate failed (install tree-sitter-cli)"
else
    echo "  ⚠ tree-sitter-cli not found (npm i -g tree-sitter-cli)"
fi

# 5. Copy queries for Neovim
echo "→ Installing highlight queries..."
QUERIES_DIR="$NVIM_CONFIG/queries/duo"
mkdir -p "$QUERIES_DIR"
cp "$DUO_ROOT/ext/tree-sitter-duo/queries/highlights.scm" "$QUERIES_DIR/" 2>/dev/null && echo "  ✓ Highlights installed"
cp "$DUO_ROOT/ext/tree-sitter-duo/queries/locals.scm" "$QUERIES_DIR/" 2>/dev/null && echo "  ✓ Locals installed"
cp "$DUO_ROOT/ext/tree-sitter-duo/queries/injections.scm" "$QUERIES_DIR/" 2>/dev/null && echo "  ✓ Injections installed"

# 6. PATH setup hint
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  Setup Complete                          ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "Add to your shell profile:"
echo "  export PATH=\"\$HOME/x/duo/zig-out/bin:\$HOME/x/duo-lsp:\$PATH\""
echo ""
echo "Neovim keybindings (in .duo files):"
echo "  <leader>dr  — Run current file"
echo "  <leader>dc  — Check/lint current file"
echo "  <leader>dd  — Dump generated C"
echo "  <leader>df  — Format file"
echo ""
echo "LSP features: diagnostics, hover, go-to-definition, completions"
