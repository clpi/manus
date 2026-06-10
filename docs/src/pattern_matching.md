# Pattern Matching

Pattern matching in Duo lets you destructure and inspect values with Rust/Go-style `match` expressions.

## Basic Match

```duo
match value
    0 => "zero"
    1 => "one"
    _ => "other"  -- wildcard pattern
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
        Shape.Circle(r) => 3.14159 * r * r
        Shape.Rect(w, h) => w * h
        Shape.Point => 0.0
    end
end
```

## Table Destructuring

Destructure table patterns:

```duo
fun get_name(person: { name: str, age: i64 }): str
    match person
        { name = n } => n
        _ => "unknown"
    end
end
```

## Array Destructuring

Pattern match on array-like tables:

```duo
fun head(xs: any): any
    match xs
        [first, _] => first
        [only] => only
        _ => nil
    end
end

fun sum3(nums: any): f64
    match nums
        [a, b, c] => a + b + c
        _ => -1.0
    end
end
```

## Guards

Add conditions to match arms:

```duo
fun classify(n: i64): str
    match n
        x if x < 0 => "negative"
        x if x > 0 => "positive"
        0 => "zero"
    end
end
```

## Exhaustiveness

The compiler checks that all cases are covered:

```duo
-- ERROR: Missing Shape.Point case
-- fun area(s: Shape): f64
--     match s
--         Shape.Circle(r) => 3.14 * r * r
--         Shape.Rect(w, h) => w * h
--     end
-- end
```

## Wildcard Pattern

The `_` pattern matches anything and discards the value:

```duo
match result
    ok(value) => process(value)
    err(_) => print("error occurred")  -- Ignore error details
end
```