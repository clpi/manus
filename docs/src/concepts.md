# Concepts (Interfaces)

Concepts in Duo are structural interfaces that define required methods and fields. Types satisfy concepts automatically when they provide the required members.

## Concept Declaration

```duo
concept Iterable
    fun __iter(self): any
end

concept Addable
    fun add(self, other): any
end
```

## Implementing Concepts

Concepts can require methods and fields. Record-typed bindings can opt into a
compile-time satisfaction check with `@implements(...)`:

```duo
concept PointLike
    x: f64
    y: f64
    fun len(self): f64
end

@implements(PointLike)
local p: { x: f64, y: f64, len: any } = {
    x = 3.0,
    y = 4.0,
    len = fun(self): f64
        math.sqrt(self.x * self.x + self.y * self.y)
    end,
}
```

## Concept Constraints on Generics

Use concepts to constrain generic type parameters:

```duo
fun sum<T: Addable>(items: []T): T
    local result: T = zero(T)
    for item in items
        result = result + item
    end
    return result
end

-- Works with any Addable type
print(sum({1, 2, 3}))           -- i64 array
print(sum({"a", "b", "c"}))       -- str array
```

Constraint syntax is parsed and tracked for generic functions. Deep concept
dispatch and metatable unification are still roadmap work.

## Multiple Constraints

Combine multiple concepts:

```duo
concept Display
    fun display(self): str
end

fun describe<T: Iterable + Display>(value: T): str
    -- T must satisfy both Iterable AND Display
end
```

## Concept Satisfaction Checking

The compiler verifies concept satisfaction at compile time:

```duo
concept Pair
    first: i64
    second: i64
end

-- ERROR: missing required field `second`
@implements(Pair)
local bad_pair: { first: i64 } = { first = 1 }
```

## Built-in Concepts

Duo provides several built-in concepts:

| Concept | Required Members |
|---------|----------------|
| `Iterable` | `__iter` method returning iterator function |
| `Addable` | Add/combine method or `+` operator support |
| `Closeable` | `__close` metamethod for cleanup |
| `Comparable` | `__lt`, `__gt`, etc. for comparison |
