# Standard Library

Duo provides a comprehensive standard library for common tasks, accessible via the `require` function.

## Modules

Modules are imported with `require("std.module")` or the shorthand `req "std.module"`:

```duo
-- Import modules
log = req "std.log"
json = req "std.json"
hash = req "std.hash"
fmt = req "std.fmt"
meta = req "std.meta"
test = req "std.test"
atomic = req "std.atomic"
crypto = req "std.crypto"
memo = req "std.memo"
```

## Logging Module (`std.log`)

Logging functions:

```duo
log = req "std.log"

log.info("Information message")
log.warn("Warning message")
log.error("Error message")
```

## JSON Module (`std.json`)

JSON parsing and serialization:

```duo
json = req "std.json"

-- Encode/decode
data = json.encode({name = "Duo", version = 1})
object = json.decode(data)

-- Or via table functions
text = json.stringify({a = 1})
obj = json.parse('{"b": 2}')
```

## Hash Module (`std.hash`)

Hash functions:

```duo
hash = req "std.hash"

-- Simple hash for strings
h: i64 = hash.simple("hello")
assert(hash.simple("hello") == hash.simple("hello"))  -- Deterministic
```

## Format Module (`std.fmt`)

String formatting:

```duo
fmt = req "std.fmt"

-- Padding
padded = fmt.pad("x", 5)  -- "x    "

-- Formatting
msg = fmt.format("Hello, {}!", "world")
```

## Meta Module (`std.meta`)

Runtime type introspection:

```duo
meta = req "std.meta"

-- Type checking
meta.is_nil(nil)      -- true
meta.is_bool(true)    -- true
meta.is_number(42)    -- true
meta.is_string("hi")  -- true
meta.is_table({})     -- true
meta.is_func(fun() end) -- true

-- Type name
type_name = meta.typeof(value)  -- "number", "string", etc.
```

## Crypto Module (`std.crypto`)

Cryptographic functions:

```duo
crypto = req "std.crypto"

-- Base64 encoding
encoded = crypto.base64_encode("Hey!")  -- "SGV5IA=="
decoded = crypto.base64_decode(encoded)
```

## Memo Module (`std.memo`)

Memoization utilities:

```duo
memo = req "std.memo"

-- Create memoized table
m = memo.table_new()
memo.table_set(m, "key", 42)
value = memo.table_get(m, "key")
has = memo.table_has(m, "key")

-- Memoize functions
doubled = memo.wrap(fun(x) return x * 2 end)
result = doubled(21)  -- 42 (cached)
```

## Atomic Module (`std.atomic`)

Atomic primitives for concurrent code:

```duo
atomic = req "std.atomic"

-- Mutex
mutex = atomic.mutex_new()
mutex.locked = true
```

## Test Module (`std.test`)

Testing utilities:

```duo
test = req "std.test"

test.start("test suite name")
test.assert_eq(actual, expected, "error message")
test.done()
```

## String Library

Lua-compatible string functions:

```duo
-- Length
len = string.len("Hello")  -- 5

-- Case conversion
lower = string.lower("HELLO")
upper = string.upper("hello")

-- Substring
sub = string.sub("Hello", 1, 3)  -- "Hel"
neg = string.sub("Hello", -3, -1) -- "llo"

-- Repetition
rep = string.rep("ab", 3, "-")  -- "ab-ab-ab"

-- Reverse
rev = string.reverse("abc")  -- "cba"

-- Pack/unpack
packed = string.pack("i", 42)
unpacked = string.unpack("i", packed)
size = string.packsize("i")

-- Matching
gm = string.gmatch("hello world", "%w+")
for word in gm do
    print(word)
end
```

## Table Library

Lua-compatible table functions:

```duo
t = {10, 20, 30}

-- Insert
table.insert(t, 2, 15)  -- Insert 15 at position 2

-- Remove
val = table.remove(t, 3)  -- Remove and return element

-- Sort
table.sort(t)  -- In-place sort

-- Concatenate
s = table.concat(t, ", ")  -- "10, 15, 20, 30"
```

## IO Library

Lua-compatible I/O functions:

```duo
-- Writing
io.write("Hello", " ", "world!\n")
io.flush()

-- Files
f = io.open("file.txt", "w")
f:write("Content\n")
f:flush()
f:close()

-- Type
typ = io.type(f)  -- "closed file" or "file"

-- Pipes
pipe = io.popen("echo 'test'")
output = pipe:read()
pipe:close()
```

## OS Library

System operations:

```duo
-- Time
now = os.time()
elapsed = os.clock()

-- Environment
path = os.getenv("PATH")

-- Files
found = os.remove("file.txt")
```

## Coroutine Library

Coroutine support:

```duo
-- Create coroutine
co = coroutine.create(fun()
    return 42
end)

-- Close
ok = coroutine.close(co)
```

## Package Library

Module search path:

```duo
-- Search for module
path = package.searchpath("mymod", "./?.lua")
```

## Global Functions

```duo
-- Print
print("Hello, Duo!")
print("Value:", 42)

-- Assertion
assert(x > 0, "x must be positive")

-- Warning
warn("This is a warning")

-- Unpack
first, second, third = unpack({1, 2, 3})

-- Garbage collection
count = collectgarbage("count")

-- Protected call
ok, err = xpcall(fun() return error() end, fun(e) return e end)

-- Load/Do
chunk = load("return 1 + 1")
result = dofile("script.lua")
```

## Metatable Functions

```duo
-- Set/get metatable
mt = { __tostring = fun() return "custom" end }
t = {}
setmetatable(t, mt)
got_mt = getmetatable(t)

-- Raw operations
val = rawget(t, "key")
rawset(t, "key", value)
len = rawlen("hello")  -- 5
eq = rawequal(t, t)
```