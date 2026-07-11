# Enums

Enums in Duo represent tagged unions (sum types) with optional payloads, enabling type-safe variant data.

## Basic Enum

Declare enums with the `enum` keyword:

```duo
enum Color
    Red
    Green
    Blue
end

fun color_name(c: Color): str
    match c
        case Color.Red then "red"
        case Color.Green then "green"
        case Color.Blue then "blue"
    end
end
```

## Payload Variants

Enums can carry data with each variant:

```duo
enum Shape
    Circle(radius: f64)
    Rectangle(width: f64, height: f64)
    Point(x: f64, y: f64)
end

fun area(s: Shape): f64
    match s
        case Shape.Circle(r) then 3.14159 * r * r
        case Shape.Rectangle(w, h) then w * h
        case Shape.Point then 0.0
    end
end
```

## Enum Constructors

Create enum values using constructor syntax:

```duo
circ: Shape = Shape.Circle(5.0)
rect: Shape = Shape.Rectangle(3.0, 4.0)
```

## Matching Enums

Pattern match on enum variants:

```duo
fun describe(s: Shape): str
    match s
        case Shape.Circle(r) then "Circle with radius " .. tostring(r)
        case Shape.Rectangle(w, h) then "Rectangle " .. tostring(w) .. "x" .. tostring(h)
        case Shape.Point then "Point at origin"
    end
end
```

## Enum Methods

Add methods to enums via extension functions:

```duo
-- Define enum
enum Result
    Success(value)
    Failure(error)
end

-- Extension method (prefix function)
fun Result<T>.is_ok(r: Result<T>): bool
    match r
        case Result.Success(_) then true
        case Result.Failure(_) then false
    end
end

-- Usage
r: Result[i64] = Result.Success(42)
if r.is_ok() then
    print("Success!")
end
```

## Derived Enum Metadata and Display

`@derive(...)` records runtime metadata for enum declarations. Variant
constructors keep the same enum representation, while `Enum.name`,
`Enum.variants`, and `Enum.derives` expose descriptor fields. Payload-free
enums that derive `Display` get a generated `to_string` method and participate
in `tostring(...)`; payload-free enums that derive `Eq` get a generated `eq`
method:

```duo
@derive("Display", "Clone", "Eq")
enum Color
    Red
    Green
end

print(Color.name)             -- Color
print(Color.variants[1].name) -- Red
print(Color.derives[1])       -- Display
print(Color.Red:to_string())  -- Red
print(tostring(Color.Green))  -- Green
print(Color.Red:eq(Color.Green)) -- false
```

## Recursive Enums

Enums can be recursive:

```duo
enum Tree
    Leaf(value: i64)
    Branch(left: Tree, right: Tree)
end

fun sum(t: Tree): i64
    match t
        case Tree.Leaf(v) then v
        case Tree.Branch(l, r) then sum(l) + sum(r)
    end
end
```

## Exhaustiveness Checking

The compiler ensures all variants are handled:

```duo
-- ERROR: Missing Tree.Branch case
-- fun Tree.count_leaves(t: Tree): i64
--     match t
--         case Tree.Leaf(_) then 1
--     end
-- end
```
