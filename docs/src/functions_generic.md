# Generic Functions

Generics allow you to write reusable, type-safe code without runtime overhead. Duo uses compile-time monomorphization to generate specialized versions for each concrete type used.

## Declaration

Generic functions use the `<T>` syntax for type parameters:

```duo
fun identity<T>(value: T): T
    value
end

-- Multiple type parameters
fun pair<T, U>(first: T, second: U): { first: T, second: U }
    return { first = first, second = second }
end
```

## Monomorphization

When you call a generic function with concrete types, Duo generates specialized versions:

```duo
-- Duo generates two specializations:
result1 = identity(42)        -- duo_identity_i64(42)
result2 = identity("hello")   -- duo_identity_str("hello")
```

Each specialization is independent, with zero runtime overhead for type dispatch.

## Constraints

Type parameters can have constraints using concepts:

```duo
-- Concept: Addable requires + operator
fun sum<T: Addable>(a: T, b: T): T
    a + b
end

-- This works because i64 is Addable
int_result = sum(1, 2)

-- String concatenation also works
str_result = sum("a", "b")
```

## Generic Data Structures

Use `List[T]` / `[]T` when you want type-safe list values:

```duo
fun first_or<T>(items: List[T], fallback: T): T
    if #items == 0 then
        return fallback
    end
    items[1]
end
```

Generic type aliases use the same `<T>` declaration style as generic functions:

```duo
type Vec<T> = List[T]
local xs: Vec[i64] = {}
```

Alias type arguments are substituted through the alias target during semantic
and native type resolution, so `Vec[i64]` above resolves like `List[i64]` in
function parameters, return checks, locals, and generated C types.

## Explicit Specialization

Call sites normally infer generic type arguments automatically. When you want a
specialization generated ahead of time, use `@specialize(name, types...)` at
module scope:

```duo
fun hash<T>(value: T): i64
    return builtin_hash(value)
end

@specialize(hash, str)
```

This generates the same `hash<str>` native body that a typed call would have
requested, without requiring a call site in the current module. Custom
replacement implementations for particular type tuples are still planned.

The target must be a known top-level generic function, and the number of type
arguments must match the function's type-parameter list. Invalid specialization
requests are compile-time errors instead of silent no-ops.

Type arguments use normal Duo type syntax, so nested generic types keep their
commas inside the type argument:

```duo
@specialize(hash, Result[i64, str])
@specialize(first_or, List[i64])
```

## Advanced Generics

Type parameters can be used in complex type expressions:

```duo
-- Result with generic error type
fun operation<T, E>(input: T): Result[T, E]
    if validate(input) then
        return ok(process(input))
    end
    return err(make_error())
end

-- Generic options
fun get_or_default<T>(opt: Option[T], default: T): T
    match opt
        some(v) then v
        none then default
    end
end
```

## Performance

Generics have zero runtime cost:

```duo
-- This loop compiles to native C with no indirection
fun dot_product<T>(a: []T, b: []T): T
    sum: T = 0
    for i = 1, #a
        sum = sum + a[i] * b[i]
    end
    return sum
end

-- Mono: Vec_i64_dot_product optimized for i64
```
