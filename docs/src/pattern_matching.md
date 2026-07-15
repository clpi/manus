# Pattern Matching

Pattern matching in Duo lets you destructure and inspect values with Lua-like `match` expressions.

Each arm starts with a pattern and optional `if` guard. Use either `then` or
`do` before the arm's statement. A leading `case` remains accepted when it helps
readability.

## Basic Match

```duo
match value
    0 then "zero"
    1 then "one"
    _ then "other"  -- wildcard pattern
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
        Shape.Circle(r) then 3.14159 * r * r
        Shape.Rect(w, h) then w * h
        Shape.Point then 0.0
    end
end
```

## Table Destructuring

Destructure table patterns:

```duo
fun get_name(person: { name: str, age: i64 }): str
    match person
        { name = n } then n
        _ then "unknown"
    end
end
```

## Array Destructuring

Pattern match on array-like tables:

```duo
fun head(xs: any): any
    match xs
        [first, _] then first
        [only] then only
        _ then nil
    end
end

fun sum3(nums: any): f64
    match nums
        [a, b, c] then a + b + c
        _ then -1.0
    end
end
```

## Guards

Add conditions to match arms:

```duo
fun classify(n: i64): str
    match n
        x if x < 0 then "negative"
        x if x > 0 then "positive"
        0 then "zero"
    end
end
```

## Exhaustiveness

The compiler checks that all cases are covered:

```duo
-- ERROR: Missing Shape.Point case
-- fun area(s: Shape): f64
--     match s
--         Shape.Circle(r) then 3.14 * r * r
--         Shape.Rect(w, h) then w * h
--     end
-- end
```

## Wildcard Pattern

The `_` pattern matches anything and discards the value:

```duo
match result
    ok(value) then process(value)
    err(_) then print("error occurred")  -- Ignore error details
end
```
