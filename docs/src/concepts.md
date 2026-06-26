# Concepts and Meta Descriptors

Concepts in Duo are structural interfaces that define required methods and fields. Types satisfy concepts automatically when they provide the required members.

The runtime/metaprogramming path is moving toward ordinary meta-table
descriptors. Prefer `std.meta.make_concept(...)` for reflection and dynamic
checks; the `concept` keyword remains for compile-time `@implements` checks
while that path is merged into metatables.

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

Concept declarations also produce runtime descriptor tables. The descriptor is
ordinary Lua-shaped data, so reflection code can use the same metatable/table
path as dynamic objects:

```duo
meta = req "std.meta"

concept Drawable
    id: i64
    fun draw(self): str
end

shape = { id = 7, draw = fun(self): str return "shape" end }

print(Drawable.name)                         -- Drawable
print(meta.satisfies_concept(shape, Drawable)) -- true
```

The descriptor bridge is implemented; full metatable dispatch and replacing the
`concept` declaration syntax with ordinary meta-table construction remain
roadmap work.

For runtime reflection, the same descriptor shape can be built without the
keyword:

```duo
meta = req "std.meta"

Drawable = meta.make_concept("Drawable", {
    fields = { "id" },
    methods = { "draw" },
})

shape = {
    id = 7,
    draw = fun(self): str return "shape" end,
}

print(meta.satisfies_concept(shape, Drawable)) -- true
print(getmetatable(Drawable).type)             -- concept
```

Literal `meta.make_concept(...)` descriptors are also recognized by
`@implements`, so compile-time checks can use the same table declaration:

```duo
PointLike = meta.make_concept("PointLike", {
    fields = { "x", "y" },
    methods = { "len" },
})

@implements(PointLike)
local p: { x: i64, y: i64, len: any } = {
    x = 3,
    y = 4,
    len = fun(self): i64 return 5 end,
}
```

`std.meta.derive` exports its built-in descriptors using this table form, so
runtime code can use `derive.Display`, `derive.Clone`, and the other standard
descriptors without declaring keyword concepts.

## Built-in Concepts

Derivable concept descriptors are available from `std.meta.derive`:

| Concept | Required Members |
|---------|----------------|
| `Iterable` | `__iter` method returning iterator function |
| `Addable` | Add/combine method or `+` operator support |
| `Closeable` | `__close` metamethod for cleanup |
| `Comparable` | `__lt`, `__gt`, etc. for comparison |
