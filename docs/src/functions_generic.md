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

Generics enable type-safe containers:

```duo
-- Generic vector type
type Vec<T> = {
    data: []T,
    length: i64
}

fun Vec<T>.new(): Vec<T>
    return { data = {}, length = 0 }
end

fun Vec<T>.push(v: Vec<T>, item: T): void
    v.length = v.length + 1
    v.data[v.length] = item
end
```

## Partial Specialization

You can provide custom implementations for specific types:

```duo
fun hash<T>(value: T): i64
    -- Default implementation
    return builtin_hash(value)
end

-- Custom hash for strings
@specialize(hash, str)
fun hash_str(s: str): i64
    -- Optimized string hashing
    return djb2_hash(s)
end
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
        some(v) => v
        none => default
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