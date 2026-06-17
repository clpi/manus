# Idiomatic Duo (The Zen of Duo)

Duo is designed to be a pragmatic, high-performance language that blends the flexibility of Lua with the speed and safety of native C. To get the most out of Duo, follow these idiomatic guidelines:

## 1. Prefer Implicit Returns

When the last thing a function does is produce a value, let the block tail expression be the return. This is cleaner, faster to read, and generates the same code as an explicit `return`.

**Idiomatic:**
```duo
fun add(a: i64, b: i64): i64
    a + b
end

fun max(a: i64, b: i64): i64
    if a > b then a else b end
end
```

**Less idiomatic:**
```duo
fun add(a: i64, b: i64): i64
    return a + b
end
```

Use explicit `return` only when you need to exit early:

```duo
fun find_index(list: any, target: any): i64
    for i = 1, #list do
        if list[i] == target then
            return i
        end
    end
    -1
end
```

## 2. Embrace Type Annotations for Performance

While Duo allows you to write untyped Lua-style code, adding static type annotations (`x: number`, `s: string`) allows the compiler to:
- Generate highly optimized C code (often 4-100x faster than untyped code).
- Perform constant-folding and dead-code elimination at compile time.
- Provide compile-time safety and better error messages.

**Idiomatic (when performance matters):**
```duo
fun calculate_sum(n: number): number
    local sum: number = 0
    for i = 1, n do
        sum = sum + i
    end
    sum
end
```

**Less idiomatic (but valid for quick scripting):**
```duo
fun calculate_sum(n)
    local sum = 0
    for i = 1, n do
        sum = sum + i
    end
    return sum
end
```

## 3. Default to `local`

Always declare variables with `local`. Global variables are discouraged unless absolutely necessary, as they can inhibit optimizations and cause unintended side-effects across your program.

## 4. Leverage Pattern Matching

Duo's pattern matching (`match`) is more expressive and safer than complex `if/elseif/else` chains. Use it to handle enums, variants, and structured data clearly.

```duo
local enum Option
    Some(val: any)
    None
end

fun process(opt: Option)
    match opt
        case Some(val) => print(val)
        case None => print("Nothing")
    end
end
```

## 5. Take Advantage of Constant Folding

When values are known at compile time, the Duo compiler will aggressively constant-fold. You can rely on this for zero-cost abstractions, meaning that clear, descriptive code often compiles down to nothing!

```duo
fun circle_area(r: f64): f64
    math.pi * r * r
end
```
