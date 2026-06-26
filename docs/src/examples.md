# Example Programs

Here are a few example programs to give you a feel for Duo's syntax and capabilities. Because Duo is heavily inspired by Lua, the syntax will look very familiar, but it incorporates many modern features like type annotations, enums, and pattern matching.

## Hello World

```duo
print("Hello, Duo!")
```

## Fibonacci Sequence (Typed)

Using static type annotations significantly improves performance when compiled:

```duo
fun fib(n: i64): i64
    if n <= 1 then
        return n
    end
    return fib(n - 1) + fib(n - 2)
end

print(fib(10))
```

## Pattern Matching with Enums

Duo supports algebraic data types through enums, and powerful pattern matching:

```duo
enum Option
    Some(val: any)
    None
end

fun handle_option(opt: Option)
    match opt
        case Some(val) then print("Got value:", val)
        case None then print("No value")
    end
end

handle_option(Option.Some(42))
handle_option(Option.None)
```

## Object-Oriented Style

Just like Lua, you can implement Object-Oriented patterns using tables and metatables:

```duo
-- A simple Point "class" using factory function pattern
fun Point.new(x: f64, y: f64)
    {
        x = x,
        y = y,
        move = fun(self, dx: f64, dy: f64)
            self.x = self.x + dx
            self.y = self.y + dy
        end,
        describe = fun(self)
            "Point(" .. tostring(self.x) .. ", " .. tostring(self.y) .. ")"
        end,
    }
end

p = Point.new(10.0, 20.0)
print(p.describe(p))
p.move(p, 5.0, -5.0)
print(p.describe(p))
```
