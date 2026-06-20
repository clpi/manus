# Pattern Matching

Pattern matching in Duo lets you destructure and inspect values with Rust/Go-style `match` expressions.

Each arm starts with `case`, followed by a pattern and optional `if` guard.
Use either `then` or `do` before the arm's statement. The older
`pattern => statement` spelling remains accepted for compatibility, but
`case ... then ...` is the canonical form emitted by the compiler's
pretty-printer.

## Basic Match

```duo
match value
    case 0 then "zero"
    case 1 then "one"
    case _ then "other"  -- wildcard pattern
end
```

## Enum Destructuring

Match enum variants and extract their payloads:

```duo
enum Shape
    Circle(radius: f64)
    Rect(w: f64, h: f64)
    Point
end

fun area(s: Shape): f64
    match s
        case Shape.Circle(r) then 3.14159 * r * r
        case Shape.Rect(w, h) then w * h
        case Shape.Point then 0.0
    end
end
```

## Table Destructuring

Destructure table patterns:

```duo
fun get_name(person: { name: str, age: i64 }): str
    match person
        case { name = n } then n
        case _ then "unknown"
    end
end
```

## Array Destructuring

Pattern match on array-like tables:

```duo
fun head(xs: any): any
    match xs
        case [first, _] then first
        case [only] then only
        case _ then nil
    end
end

fun sum3(nums: any): f64
    match nums
        case [a, b, c] then a + b + c
        case _ then -1.0
    end
end
```

## Guards

Add conditions to match arms:

```duo
fun classify(n: i64): str
    match n
        case x if x < 0 then "negative"
        case x if x > 0 then "positive"
        case 0 then "zero"
    end
end
```

## Exhaustiveness

The compiler checks that all cases are covered:

```duo
-- ERROR: Missing Shape.Point case
-- fun area(s: Shape): f64
--     match s
--         case Shape.Circle(r) then 3.14 * r * r
--         case Shape.Rect(w, h) then w * h
--     end
-- end
```

## Wildcard Pattern

The `_` pattern matches anything and discards the value:

```duo
match result
    case ok(value) then process(value)
    case err(_) then print("error occurred")  -- Ignore error details
end
```
