# Duo Standard Library Reorganization

## Goal
- #p00 #important **Keep `lua5.5` superset status as much as possible**
  - #p0 only compromise where other priorities can make significant gains only compromising small edge cases

### Metaprogramming

- #p1 phase out #macro keuyword in favor of comptime handling with symbol or similar (like zig, with rust capabilities, but most compact verbose and sensible)

### Syntax and Grammar

> [!WARNING] If any of the below are deemed #impossible/#impractical
> or sacrifice #performance or any other top level goals, then 
> reconsider or simply do not implement.

- #p1 phase out `match` keyword in favor of more lua-like no-keyword approach
- #p1 `comptime` #maybe shouldnt be a keyword -- again just a symbol or something similar (like how @ is compiler diretives) to allow compile time signaling
- #p1 proper backcompatible/extensible closure handling and syntax
- #p99 Think about ways to make #enum, #derive, #metatable more ergonomic no keyword etc
- #p1 phase out #concept `concept` in favor of more ergonomic approach
- #p4 phase out #defer `defer` keyword for more ergonomic
- #p0 #jai like type definition:
  - `Vec` declares opaque type `Vec` #ifpossible
  - `Vec: { x: int, y: int, m: f64 }` declares type `Vec` #ifpossible (if so: phase out `type` keyword) (if not: keep using `type` keyword or consider more ergonomic/semantically meaningful alt)
  - `v: { x: int, y: int, m: f64 } = { x = 3, y = 4, m = 2.0 }` (if type is known as float but floating decimal not specified infers smart) -> initializes duo table anonymous table for value v
  - `v2: Vec = ...` same as other languages
  - etc
- #p4 support smart field assigning semantics: #ifpossible
  - `Vec: {x: int, y:int}; v: Vec = {1,2}` -> `Vec{x=1,y=2}`
  - `Vec: {x:int, y:int}; v: Vec = Vec{1,2}` -> `Vec{x=1,y=2}`
- #p4 smart / ergonomic generics like zig but less verbose, integrate into existing compile time architecture
- #p4 #maybe `as` cast semantics
- #p2 ergonomic optional and result typing with `!`, `?`, `or` etc
- #p99 support for `not` and other common keywords not supported by lua
- #p99 figure out `0` or `1` based indexing

### Goals
- 0. #p2 Reorganize Duo's standard library to be as comprehensive as Go's standard library while structured like Zig's (single `std` namespace with logical sub-namespaces).
- 1. #p0 Should target metaprogramming framework that allows most comprehensive performant semantically sensible efficient syntax that as minimally as possible amends lua, and only where it is sensible with regards to saving on ergonomics (omitting local, file-level module scope, syntax sugar req instead of require, fun instead of function etc)-> output from metaprogramming utilities that are as compact as semantically meaningful as comprehensive in low-level control as readable as possible (self-documenting) contained (small binary) performant (faster than c) output as possible
- 2. #p0 support compiler hints and directives and annotations as extensions of lua in comments of lua files in addition to full lua55 support
- 3. #p1 eventually rmmova all possible interfaces with lua boxed values and types, whatever maximizes performance
- 4. #p4 Make `then` optional and eventually deprecate
- 5. #p4 full and well-supported wasm/wasi target support
- 6. #p5 multiple compilation and transpilation targets
- 7. #p4 `duo lsp`, `duo test`, `duo fmt/format`, `duo build`, `duo init`, `duo run` commands
  - 1. #p4 `duo lsp` in duo (started implementation in ~/x/duo-lsp)
  - 2. #p4 `duo build` robust build system ergonomic enough to use for any project
    - 1. consider in-file/compiler directive build instructions, no separate file (like casey's cdep, programming language agnostic comment reading)
- 8. #p1 support for lua file compile, compat `5.5`, fastest runtime, compiler extensions with comment level `@directives` and hints
- 9. #p4 most beautiful and useful and fast compiler output and debugging
- 10. #p5 [eventually] #eventually self hosted compiler #p5
- 11. #p5 plug and play script for devenv set up (neovim, vim, etc.)

## tasks
- [ ] add `@this` OR `this` OR `self` OR `@self` OR any of these capitalized (since it is a type) to reference the type of whatever scope we're in
- [ ] compiler outputting and formatting more pretty than `kiro-cli`, `opencode`
- [ ] extremely comprehensive stdlib
- [ ] comprehensive shell / lsp / etc. support completions completion description etc.
- [ ] compiler warning on:
  - [ ] `then` when made optional, `do` when optional
  - [ ] `local`

## rules
- `local` omitted
- prefer syntax sugar for duo files - `fun` over `function`, `req` over `require`, etc
- prefer file-level modules over `local M = ...; return M` modules
- favor intersection of readability and performance
- more metaprogramming facilities than jai, more fine grained targeting and control than rust, intuitiveness and ergonomics of zig
- minimize syntax/keyword additions over lua55 and existing syntax
- more fine grained low level opt-in control than c
- more performant than c
- more performant lua compilation than equivalent c
- if a performance improvement can be made asymmetrically to duo over lua, make it
- smaller binary size, faster compile times
- "whipitupitude"
- favor adding syntax sugar which allows for scripting ergonomics
- favor compact syntax and grammar while maintaining readability

## Tooling

- [ ] #p3 `tree-sitter-duo`
- [ ] #p4 `duo.nvim` / `duo.vim`

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
  - support nested module dependency
- `src/sema.zig`: _(no changes beyond original)_

## Design Constraints
- All `.duo` modules must use `local function` or `fun` (no `local` for module-level vars - they cause C code ordering issues)
  - omit local
- Function names in embedded modules become file-scoped C functions — they **must not** collide with C standard library names (`open`, `close`, `read`, `write`, `register`, `final`, `clock`, `difftime`, `sleep`, etc.) or with functions in other modules
  - fix scoping
- Pattern: use `local function modulename_functionname(...)` to prefix C names uniquely
- `_` as discard variable triggers C compiler errors — use named variables (`d1`, `d2`, etc.)
- End modules with bare `M` expression (not `return M`)
  - disregard, prefer file level modules wherever possible
- `import()` is not defined — use `req()` or `require()`
  - preer req
  - @include to include in scope/namespace
- `local` inside typed `fun` functions generates broken C code — use `local function` (untyped)
  - fix this, prefer omitting local always
- `req()` inside table literals fails — use field-assignment style
  - ix this

## Miscellaneous

### prompts

- computer discoverability opportunities while also enabling comprehensive fine grained control through discoverable common sense semantics:
  - when i first used zig comptimes the concept of generics clicked into place and compile time vs runtime. 
  - when i first used traits the extensibility of metaprogramming and possibilities for compact-as-possible code implementing as robust and as complex as possible runtime code became visible
  - etc. these sorts of moments should about in duo. always be thinking of new ways to enable these sorts of moments/lasting feelings while using duo, especially considering through agentic workflows (ie saving on tokens with as little code as possible doing as much as possible)
