#!/bin/sh
# Idol main repo MCP server wrapper — ensures correct working directory
cd /Users/clp/x/idol
exec /Users/clp/x/idol/zig-out/bin/idol run --backend=native tools/mcp/native.id