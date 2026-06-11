# Standard Library

Duo provides a comprehensive standard library for common tasks, accessible via the `require` function.

## Modules

Modules are imported with `require("std.module")` or the shorthand `req "std.module"`:

```duo
-- Import modules
log = req "std.log"
str = req "std.string"
num = req "std.math"
tbl = req "std.table"
fs = req "std.fs"
json = req "std.json"
hash = req "std.hash"
fmt = req "std.fmt"
meta = req "std.meta"
test = req "std.test"
atomic = req "std.atomic"
crypto = req "std.crypto"
memo = req "std.memo"
build = req "std.build"
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

## Build Module (`std.build`)

Project build helpers:

```duo
build = req "std.build"

build.project({ name = "app", version = "0.1.0", default = "app" })

build.exe({
    name = "app",
    src = "src/main.duo",
    out = "zig-out/bin/app",
    opt = "-O3",
})
```

The CLI reads this shape from `build.duo` for `duo build` and `duo run`.

## String Helpers (`std.string`)

Convenience wrappers for common string tasks:

```duo
str = req "std.string"

str.starts_with("duo-lang", "duo")  -- true
str.ends_with("duo-lang", "lang")   -- true
str.contains("duo-lang", "-")       -- true
str.trim("  duo  ")                 -- "duo"
parts = str.split("a,b,c", ",")
joined = str.join(parts, "|")       -- "a|b|c"
str.replace_all("a-b-c", "-", ":")  -- "a:b:c"
str.repeat_str("ha", 3)             -- "hahaha"
lines = str.lines("one\ntwo")
```

## Math Helpers (`std.math`)

Small numeric helpers:

```duo
num = req "std.math"

num.clamp(12, 1, 10)        -- 10
num.min(3, 7)               -- 3
num.max(3, 7)               -- 7
num.sign(-4)                -- -1
num.round(2.6)              -- 3
num.lerp(0, 10, 0.5)        -- 5
num.remap(5, 0, 10, 0, 100) -- 50
num.sum({1, 2, 3})          -- 6
num.mean({2, 4, 6})         -- 4
num.is_even(4)              -- true
num.is_odd(5)               -- true
```

## Table Helpers (`std.table`)

Table and array helpers:

```duo
tbl = req "std.table"

xs = {1, 2, 3}
tbl.len(xs)                         -- 3
tbl.contains(xs, 2)                 -- true
tbl.index_of(xs, 3)                 -- 3
tbl.reverse(xs)                     -- {3, 2, 1}
tbl.map(xs, fun(v) return v * 2 end)
tbl.filter(xs, fun(v) return v > 1 end)
tbl.reduce(xs, fun(acc, v) return acc + v end, 0)
keys = tbl.keys({a = 1, b = 2})
values = tbl.values({a = 1, b = 2})
copy = tbl.clone({a = 1})
merged = tbl.merge({a = 1}, {b = 2})
```

## File-System Helpers (`std.fs`)

Simple file helpers built on `io` and `os`:

```duo
fs = req "std.fs"

fs.write_file("/tmp/example.txt", "one\ntwo\n")
fs.append_file("/tmp/example.txt", "three\n")
fs.exists("/tmp/example.txt")       -- true
text = fs.read_file("/tmp/example.txt")
lines = fs.read_lines("/tmp/example.txt")
fs.rename("/tmp/example.txt", "/tmp/example2.txt")
fs.remove("/tmp/example2.txt")
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
