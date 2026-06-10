# Concepts (Interfaces)

Concepts in Duo are structural interfaces that define required methods and fields. Types satisfy concepts automatically when they provide the required members.

## Concept Declaration

```duo
concept Iterable
    required_methods: {
        __iter: () -> fun(): any
    }
end

concept Addable
    required_methods: {
        __add: (any, any) -> any
    }
end
```

## Implementing Concepts

Types satisfy concepts when they have matching methods/fields:

```duo
-- This table satisfies Iterable
local my_iterable = {
    data = {1, 2, 3},
    __iter = function()
        local i = 0
        return function()
            i = i + 1
            return my_iterable.data[i]
        end
    end
}

-- Explicit annotation
local it: Iterable = my_iterable
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

## Multiple Constraints

Combine multiple concepts:

```duo
concept Display
    required_methods: {
        __display: () -> str
    }
end

fun describe<T: Iterable + Display>(value: T): str
    -- T must satisfy both Iterable AND Display
end
```

## Anonymous Concepts

Use inline concept requirements:

```duo
fun process<T: { __iter: () -> fun(): any }>(value: T): i64
    count: i64 = 0
    for item in value
        count = count + 1
    end
    return count
end
```

## Concept Satisfaction Checking

The compiler verifies concept satisfaction at compile time:

```duo
-- This fails if MyType doesn't have __iter method
fun count_items<T: Iterable>(container: T): i64
    local iter = container.__iter()
    -- ...
end
```

## Built-in Concepts

Duo provides several built-in concepts:

| Concept | Required Members |
|---------|----------------|
| `Iterable` | `__iter` method returning iterator function |
| `Addable` | `__add` method or `+` operator support |
| `Closeable` | `__close` metamethod for cleanup |
| `Comparable` | `__lt`, `__gt`, etc. for comparison |