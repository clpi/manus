# Duo Standard Library Reorganization

## Goal
Reorganize Duo's standard library to be as comprehensive as Go's standard library while structured like Zig's (single `std` namespace with logical sub-namespaces).

## Progress

### Working (23 new modules)
- `std.cmp` — ordered comparison utilities
- `std.compress.flate` — DEFLATE (RLE) compression
- `std.compress.gzip` — gzip detection via `gzip -d`
- `std.compress.zlib` — zlib header detection + flate decompress
- `std.database.sql` — generic SQL driver registry
- `std.hash.adler32` — Adler-32 checksum
- `std.hash.crc32` — CRC-32 (stub)
- `std.hash.crc64` — CRC-64 (stub)
- `std.hash.fnv` — FNV hash (stub)
- `std.hash.maphash` — map hash (stub)
- `std.hash.sha1` — SHA-1 (stub)
- `std.hash.sha256` — SHA-256 (stub)
- `std.hash.sha512` — SHA-512 (stub)
- `std.crypto.tls` — TLS config stub
- `std.image.color` — color stub
- `std.image.png` — PNG stub
- `std.image.jpeg` — JPEG stub
- `std.image.gif` — GIF stub
- `std.mime.multipart` — MIME multipart parser
- `std.net.http` — HTTP sub-modules root
- `std.net.http.cgi` — CGI handler stub
- `std.net.http.httputil` — HTTP utilities stub
- `std.net.http.httptest` — HTTP test utilities stub
- `std.text.template.parse` — template AST parser

### Working (original, pre-existing)
- `std.log`, `std.json`, `std.fs`, `std.env`, `std.path`, `std.proc`, `std.fmt`, `std.hash`

### Pre-existing issues (broken before our changes)
- `std.time` — C name conflicts (`clock`, `difftime`, `sleep`)
- `std.os`, `std.io`, `std.crypto`, `std.mime` — C compiler failures
- `std.csv`, `std.xml` — parse errors
- `std.toml`, `std.yaml`, `std.ini`, `std.base32`, `std.sqlite`, `std.tar`, `std.zip`, `std.html` — `import()` calls where `req()` is needed
- `std.regex` — parse error
- `std.url` — undeclared global `default_port`

## Compiler Fixes
- `src/codegen.zig`: `__ack_impl` duplicate emission guard
- `src/codegen.zig`: recursive module dependency resolution (nested `req()` calls)
- `src/sema.zig`: _(no changes beyond original)_

## Design Constraints
- All `.duo` modules must use `local function` or `fun` (no `local` for module-level vars - they cause C code ordering issues)
- Function names in embedded modules become file-scoped C functions — they **must not** collide with C standard library names (`open`, `close`, `read`, `write`, `register`, `final`, `clock`, `difftime`, `sleep`, etc.) or with functions in other modules
- Pattern: use `local function modulename_functionname(...)` to prefix C names uniquely
- `_` as discard variable triggers C compiler errors — use named variables (`d1`, `d2`, etc.)
- End modules with bare `M` expression (not `return M`)
- `import()` is not defined — use `req()` or `require()`
- `local` inside typed `fun` functions generates broken C code — use `local function` (untyped)
- `req()` inside table literals fails — use field-assignment style
