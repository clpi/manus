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

Just like Lua, you can implement Object-Oriented patterns using metatables:

```duo
local Point = {}
Point.__index = Point

fn Point.new(x: number, y: number): any
    local self = {
        x = x,
        y = y
    }
    setmetatable(self, Point)
    return self
end

fn Point:move(dx: number, dy: number)
    self.x = self.x + dx
    self.y = self.y + dy
end

local p = Point.new(10, 20)
p:move(5, -5)
print(p.x, p.y)
```
