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
        Color.Red => "red"
        Color.Green => "green"
        Color.Blue => "blue"
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
        Shape.Circle(r) => 3.14159 * r * r
        Shape.Rectangle(w, h) => w * h
        Shape.Point => 0.0
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
        Shape.Circle(r) => "Circle with radius " .. tostring(r)
        Shape.Rectangle(w, h) => "Rectangle " .. tostring(w) .. "x" .. tostring(h)
        Shape.Point => "Point at origin"
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
        Result.Success(_) => true
        Result.Failure(_) => false
    end
end

-- Usage
r: Result[i64] = Result.Success(42)
if r.is_ok() then
    print("Success!")
end
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
        Tree.Leaf(v) => v
        Tree.Branch(l, r) => sum(l) + sum(r)
    end
end
```

## Exhaustiveness Checking

The compiler ensures all variants are handled:

```duo
-- ERROR: Missing Tree.Branch case
-- fun Tree.count_leaves(t: Tree): i64
--     match t
--         Tree.Leaf(_) => 1
--     end
-- end
```