# Functions

Functions are the core building blocks in Duo. They support both Lua's dynamic style and typed, performance-oriented variants.

## Function Declaration

### Typed Functions (Recommended)

```duo
fun add(a: i64, b: i64): i64
    a + b
end
```

Typed functions compile to native C with zero overhead. All parameters and the return type must be annotated.

### Untyped Functions (Lua-Compatible)

```duo
function multiply(a, b)
    return a * b
end
```

Untyped functions use Lua's dynamic semantics and can accept any value.

### Anonymous Functions

```duo
-- Typed anonymous function
local adder = fun(x: i64, y: i64): i64
    x + y
end

-- Untyped anonymous function
local multiplier = function(a, b)
    return a * b
end
```

## Return Values

Functions return values implicitly (last expression) or explicitly:

```duo
-- Implicit return
fun square(x: f64): f64
    x * x
end

-- Explicit return
fun clamp(x: f64, min: f64, max: f64): f64
    if x < min then return min end
    if x > max then return max end
    return x
end

-- Multiple return values
fun divmod(a: i64, b: i64): (i64, i64)
    return a / b, a % b
end
```

## Parameters

### Default Values

```duo
fun greet(name: str, times: i64): str
    if times <= 0 then return "" end
    return greet(name, times - 1) .. "Hello, " .. name .. "!\n"
end
```

### Variadic Functions

```duo
fun sum(...: i64): i64
    local total: i64 = 0
    for i = 1, select("#", ...)
        total = total + select(i, ...)
    end
    return total
end
```

## Closures

Functions capture variables from their enclosing scope:

```duo
fun make_counter(): (fun(): i64)
    local count: i64 = 0
    -- Returns a closure that captures 'count'
    fun(): i64
        count = count + 1
        return count
    end
end

counter = make_counter()
print(counter())  -- 1
print(counter())  -- 2
```

## Function Attributes

Functions can be annotated with attributes:

```duo
-- Exported function (WASM entry point)
@export
fun main(): i64
    print("Hello from WASM!")
    return 0
end

-- No-panic function (compile error on ! operator)
@nopanic
fun safe_divide(a: f64, b: f64): f64
    a / b  -- compile error if b could be 0
end

-- Inline hint
@inline
fun fast_abs(x: f64): f64
    if x < 0 then -x else x end
end
```

## Statement-Style Calls

Duo supports Ruby/shell-style statement calls as syntactic sugar:

```duo
-- These are equivalent:
print("hello")
print "hello"

-- Nested calls:
f g x    -- Equivalent to: f(g(x))

-- Binary operators terminate the argument list:
f x & y  -- Equivalent to: (f(x)) & y
```