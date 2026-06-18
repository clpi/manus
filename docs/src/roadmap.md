# Language Status and Roadmap

Duo stays close to Lua while adding static types, AOT codegen, and a small set
of syntax extensions where they buy real safety or performance. This page tracks
the current language direction so examples do not drift from the compiler.

## Implemented

- `await` is the async wait primitive. There is no separate `wait` keyword.
- Postfix `?` and `!` parse as propagation and unwrap operators.
- `.duo` files are local-by-default for bare assignments; `local` remains valid
  for Lua compatibility and readability.
- `Table` and `table` name the dynamic Lua table representation.
- `List[T]`, `list[T]`, and `[]T` resolve to the same dynamic typed list shape.
- `type Name = ExistingType` is the preferred type-alias spelling. `alias` is
  still accepted as legacy syntax.
- `std.string`, `std.io`, `std.math`, `std.table`, and related modules are
  available through `req "std.module"` / `require("std.module")`.

## Partial

- `a = expr and x or y` follows Lua truthiness and short-circuit semantics.
  Narrowing and typed-codegen recovery for this idiom still need more work.
- `if ... then ... else ... end` can be used as a tail expression in blocks.
  Postfix `expr if cond else fallback` syntax is not implemented.
- Concepts exist as compile-time structural checks. They have not been merged
  with metatable semantics yet.
- Pointer types use `*T`. Reference and ownership semantics are still evolving.
- Allocator and memory-management work is tracked through ARC, escape analysis,
  and custom allocator tasks.

## Planned

- List comprehension syntax.
- Macros and metaprogramming beyond the current compile-time `##(...)` escape
  and `std.meta` helpers.
- `case ... do/then ...` match arms as a Lua-like replacement for arrow arms.
- A tighter concept/metatable model that removes unnecessary syntax additions.
- Deeper table/list lowering so dynamic Lua tables and typed Duo lists share
  more optimizer paths without losing Lua compatibility.
