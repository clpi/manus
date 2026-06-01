#!/bin/bash

# Test script to verify Duo plugin works locally

echo "Testing Duo Neovim plugin..."

# Create a temporary neovim config for testing
TEST_DIR="/tmp/duo_plugin_test"
mkdir -p "$TEST_DIR"

# Copy plugin files to test directory
mkdir -p "$TEST_DIR/ftdetect"
mkdir -p "$TEST_DIR/syntax"
mkdir -p "$TEST_DIR/plugin"
mkdir -p "$TEST_DIR/lua/duo"

cp /Users/clp/x/duo/ftdetect/duo.vim "$TEST_DIR/ftdetect/"
cp /Users/clp/x/duo/syntax/duo.vim "$TEST_DIR/syntax/"
cp /Users/clp/x/duo/plugin/duo.vim "$TEST_DIR/plugin/"
cp /Users/clp/x/duo/lua/duo/init.lua "$TEST_DIR/lua/duo/"

echo "Plugin files copied to $TEST_DIR"
echo ""
echo "Testing syntax highlighting..."
nvim --headless -c 'set rtp+=/tmp/duo_plugin_test' -c 'source /tmp/duo_plugin_test/ftdetect/duo.vim' -c 'e examples/syntax_test.duo' -c 'echo "Filetype: " . &filetype' -c 'syntax on' -c 'qa'

echo ""
echo "To test manually, run:"
echo "nvim --cmd 'set rtp+=$TEST_DIR' examples/syntax_test.duo"
echo ""
echo "Plugin structure:"
ls -la "$TEST_DIR"