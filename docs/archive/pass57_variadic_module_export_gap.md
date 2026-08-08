# Gap: a variadic function exported from a `req`'d module is never emitted

Found 2026-08-07 while clearing tier-0 (`agent-smoke`) failures. Recorded here
rather than fixed, because the fix is in the compiler's module emission and the
standing directive is Duo-only.

## Minimal repro

`lib/probe/n.duo`:

```duo
plain(a: any, b: any): any
    a + b
end

variadic(a: any, ...): any
    extra = {...}
    a + extra[1]
end

M = {}
M.plain = plain
M.variadic = variadic
M
```

Consumer:

```duo
p = req "probe.n"
main(): i64
    print(p.plain(1, 2))      -- prints 3
    print(p.variadic(1, 2))   -- does not compile
    0
end
```

`p.plain` works. `p.variadic` fails at the C compiler:

```
error: call to undeclared function 'probe_n__variadic'
```

The symbol is *called* but never *emitted*. The same function body in a
single-file program compiles and runs correctly, so this is specific to
crossing a module boundary — not to varargs, `{...}`, `setmetatable`, or
`__call`, each of which was ruled out separately.

## What it currently costs

`std.meta.partial` is the only stdlib casualty found. It is uncallable: any
consumer that calls it fails to compile. Everything else in `std.meta` works.

## Why `partial` was rewritten anyway

`partial` used to close over `f` and its bound args:

```duo
partial(f: any, ...): any
    partial_args = {...}
    apply = (...)
        ...
        return f(table.unpack(joined, 1, n))
    end
    return apply
end
```

The C backend has no closure capture, so this emitted `use of undeclared
identifier 'f'` and `'partial_args'` — which broke **the whole module**, so
every consumer of `std.meta` failed to compile, whether or not it touched
`partial`. It now stores state in a table and exposes a `__call` metamethod
(`_partial_invoke`, private per Pass 57 C2), which captures nothing and lowers
cleanly. `std.meta` compiles for everyone again; `partial` alone stays blocked
on the gap above.

That is a strict improvement, not a fix: the failure moved from "poisons the
module" to "this one function is unavailable, loudly, at compile time".

## Verified pre-existing

Both failures reproduce with a compiler built from committed `HEAD` in a clean
worktree, so neither was introduced by concurrent work.
