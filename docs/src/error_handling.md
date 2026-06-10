# Error Handling

Duo provides Rust-inspired error handling with `Result[T, E]` and `Option[T]` types, enabling safe error propagation without exceptions.

## Result Type

The `Result[T, E]` type represents success or failure:

```duo
-- Result type with ok/err constructors
fun divide(a: f64, b: f64): Result[f64, str]
    if b == 0 then
        return err("division by zero")
    end
    return ok(a / b)
end
```

## The `?` Operator

Propagate errors with the postfix `?` operator:

```duo
fun safe_sqrt(x: f64): Result[f64, str]
    half = divide(x, 2.0)?  -- Propagates error if present
    if half < 0 then
        return err("negative input")
    end
    return ok(math.sqrt(half))
end
```

## The `!` Operator

Unwrap result values with `!`, panicking on error:

```duo
-- In functions returning non-Result types
fun compute(x: f64): f64
    -- Compile error if function doesn't return Result
    -- safe_sqrt(x)!  -- Would panic on error
    
    -- Safe unwrap with default
    result = safe_sqrt(x)
    if result then
        return result
    end
    return 0.0
end
```

## Option Type

`Option[T]` represents a value that may be absent:

```duo
fun find_user(id: i64): Option[{ id: i64, name: str }]
    if id == 0 then
        return none
    end
    return some({ id = id, name = "user_" .. tostring(id) })
end

-- Using optional values
user = find_user(42)
if user then
    print(user.name)
else
    print("not found")
end
```

## try/catch Statements

Handle errors with try/catch blocks:

```duo
try
    result = risky_operation()?
catch err(msg)
    print("Error: " .. msg)
    return err("failed")
end
```

## Custom Error Types

Define structured errors with enums:

```duo
enum Error
    NotFound(resource: str)
    InvalidInput(field: str, expected: str)
    Timeout(duration: i64)
end

fun read_config(path: str): Result[table, Error]
    if not fs.exists(path) then
        return err(Error.NotFound(path))
    end
    return ok(json.parse(fs.read(path)))
end
```

## Defer for Cleanup

Use `defer` for cleanup that runs on scope exit:

```duo
fun process_file(path: str): Result[str, str]
    f = fs.open(path, "r")
    
    defer fs.close(f)
    
    content = fs.read(f)?
    return ok(content)
end
```

Defer blocks execute in LIFO order, even on errors.