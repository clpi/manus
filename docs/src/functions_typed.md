# Typed Functions

Typed functions provide static type safety with zero runtime overhead. When all parameters and return types are annotated, Duo generates pure C code without any boxing or dynamic dispatch.

## Declaration

```duo
fun add(a: i64, b: i64): i64
    a + b
end
```

The `fun` keyword is an alias for `function`. All parameters and return types must be explicitly annotated.

## Zero-Cost Abstractions

Typed functions compile directly to C:

```duo
-- Duo source
fun distance(x1: f64, y1: f64, x2: f64, y2: f64): f64
    dx = (x2 - x1) * (x2 - x1)
    dy = (y2 - y1) * (y2 - y1)
    math.sqrt(dx + dy)
end
```

Compiles to:
```c
double duo_distance(double x1, double y1, double x2, double y2) {
    double dx = (x2 - x1) * (x2 - x1);
    double dy = (y2 - y1) * (y2 - y1);
    return sqrt(dx + dy);
}
```

## Type Checking

The compiler enforces type correctness at compile time:

```duo
fun only_ints(x: i64, y: i64): i64
    return x + y
end

-- This is a compile error:
-- only_ints(1.0, 2.0)  -- float passed to i64 parameter

-- This is OK:
only_ints(1, 2)
```

## Exhaustive Type Coverage

All code paths must return a value matching the declared type:

```duo
-- Valid: all paths return i64
fun abs(x: i64): i64
    if x < 0 then
        return -x
    end
    return x
end

-- Invalid: missing else branch
-- fun guarded(x: i64): i64
--     if x > 0 then
--         return x  -- Compile error: no return in else branch
--     end
-- end
```

## Type Inference in Typed Functions

Local variables inside typed functions are inferred from their initializers:

```duo
fun compute(max: i64): i64
    local sum = 0       -- inferred as i64
    local i = 1         -- inferred as i64
    while i <= max
        sum = sum + i
        i = i + 1
    end
    return sum
end
```

## Multiple Return Values

Typed functions support multiple return values:

```duo
fun divmod(a: i64, b: i64): (i64, i64)
    q: i64 = a / b
    r: i64 = a % b
    return q, r
end

quotient, remainder = divmod(10, 3)
```

## Calling Typed Functions

Typed functions can be called with any compatible expression:

```duo
fun square(x: f64): f64
    return x * x
end

-- Direct call
print(square(3.0))

-- Via variable
op = square
print(op(4.0))

-- Higher-order use
fun apply_twice(f: fun(f64): f64, x: f64): f64
    return f(f(x))
end

print(apply_twice(square, 2.0))  -- 16.0
```