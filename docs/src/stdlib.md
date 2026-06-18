# Standard Library

Duo ships with a standard library in `lib/std/`. Import modules with `require("std.module")` or the shorthand `req "std.module"`.

## Module overview

```duo
-- Core language and data
log = req "std.log"
json = req "std.json"
fmt = req "std.fmt"
meta = req "std.meta"
memo = req "std.memo"
test = req "std.test"

-- Text and data manipulation
str = req "std.string"
re = req "std.regex"
utf8 = req "std.utf8"
base64 = req "std.base64"
hex = req "std.url"
url = req "std.url"
uuid = req "std.uuid"
random = req "std.random"

-- Math and collections
num = req "std.math"
tbl = req "std.table"
coll = req "std.collections"
iter = req "std.iter"
hash = req "std.hash"

-- OS / system / I/O
os2 = req "std.os"
fs = req "std.fs"
io2 = req "std.io"
path = req "std.path"
time = req "std.time"
env = req "std.env"
proc = req "std.proc"

-- Concurrency
sync = req "std.sync"
channel = req "std.sync"     -- sync also exposes channel helpers
concurrent = req "std.concurrent"
thread = req "std.thread"
mproc = req "std.mproc"
atomic = req "std.atomic"
coroutine2 = req "std.coroutine"

-- Networking and low-level
net = req "std.net"
mem = req "std.mem"

-- Build tooling
build = req "std.build"
argparse = req "std.argparse"
package2 = req "std.package"
debug2 = req "std.debug"

-- WASM / WASI
wasi = req "std.wasm.wasi"
```

`lib/std.duo` also groups many of these into convenience namespaces such as `std.math`, `std.sys.*`, `std.net`, `std.sync.*`, `std.data.*`, `std.crypto.*`, and `std.tools.*`.

## Logging Module (`std.log`)

```duo
log = req "std.log"

log.info("Information message")
log.warn("Warning message")
log.error("Error message")
```

## Encoding and Formatting (`std.json`, `std.csv`, `std.xml`, `std.toml`, `std.yaml`, `std.ini`, `std.html`, `std.base64`, `std.base32`, `std.hex`)

```duo
json = req "std.json"
csv = req "std.csv"
html = req "std.html"
xml = req "std.xml"
toml = req "std.toml"
yaml = req "std.yaml"
ini = req "std.ini"
base32 = req "std.base32"

parsed_json = json.parse('{"a": 1}')
str_json = json.stringify({a = 1})

parsed_csv = csv.parse("a,b,c\n1,2,3")
str_csv = csv.format({{"a", "b", "c"}, {1, 2, 3}})

parsed_toml = toml.parse("key = \"value\"")
escaped = html.escape("<script>alert(1)</script>")
unescaped = html.unescape("&lt;div&gt;")

b32 = base32.encode("hello")
```

## Hash Module (`std.hash`)

```duo
hash = req "std.hash"

h: i64 = hash.simple("hello")
assert(hash.simple("hello") == hash.simple("hello"))  -- Deterministic
```

## Format Module (`std.fmt`)

```duo
fmt = req "std.fmt"

padded = fmt.pad("x", 5)            -- "x    "
msg = fmt.format("Hello, {}!", "world")
```

## Meta Module (`std.meta`)

Runtime type introspection:

```duo
meta = req "std.meta"

meta.is_nil(nil)
meta.is_bool(true)
meta.is_number(42)
meta.is_string("hi")
meta.is_table({})
meta.is_func(fun() end)

type_name = meta.typeof(value)      -- "number", "string", etc.
```

## Crypto Module (`std.crypto`)

```duo
crypto = req "std.crypto"

encoded = crypto.base64_encode("Hey!")  -- "SGV5IA=="
decoded = crypto.base64_decode(encoded)
```

`std.crypto` also provides `hex_encode` / `hex_decode` and the raw hash helpers used by `std.hash`.

## Encoding Modules

### Base64 (`std.base64`)

```duo
b64 = req "std.base64"
encoded = b64.encode("hello")
decoded = b64.decode(encoded)
```

### Hex (`std.hex`)

```duo
h = req "std.hex"
encoded = h.encode("hello")
decoded = h.decode(encoded)
```

### URL (`std.url`)

```duo
u = req "std.url"
encoded = u.encode("hello world")   -- "hello%20world"
decoded = u.decode("hello%20world")
parsed = u.parse("https://example.com:8080/path?q=1")
-- {scheme="https", host="example.com", port=8080, path="/path", query="q=1"}
```

### UUID (`std.uuid`)

```duo
uuid = req "std.uuid"
id = uuid.v4()  -- random UUID v4 string
```

### UTF-8 (`std.utf8`)

```duo
u = req "std.utf8"
cp = u.codepoint("hello", 1, 1)
len = u.len("hello")
char = u.char(65)   -- "A"
```

## Memo Module (`std.memo`)

```duo
memo = req "std.memo"

m = memo.table_new()
memo.table_set(m, "key", 42)
value = memo.table_get(m, "key")
has = memo.table_has(m, "key")

doubled = memo.wrap(fun(x) return x * 2 end)
result = doubled(21)  -- 42 (cached)
```

## Atomic Module (`std.atomic`)

```duo
atomic = req "std.atomic"

mutex = atomic.mutex_new()
mutex.locked = true
```

## Test Module (`std.test`)

```duo
test = req "std.test"

test.start("test suite name")
test.assert_eq(actual, expected, "error message")
test.done()
```

## Build Module (`std.build`)

```duo
build = req "std.build"

build.project({ name = "app", version = "0.1.0", default = "app" })

build.exe({
    name = "app",
    src = "src/main.duo",
    out = "zig-out/bin/app",
    opt = "-O3",
})

-- Query build environment
info = build.info()
platform = build.platform()
target = build.target()
```

The CLI reads this shape from `build.duo` for `duo build` and `duo run`.

## Command-Line Arguments (`std.argparse`)

```duo
argparse = req "std.argparse"

parsed = argparse.parse(arg)
-- parsed.flags, parsed.positionals
```

## Environment Variables (`std.env`)

```duo
env = req "std.env"

home = env.get("HOME")
has_debug = env.has("DEBUG")
```

## String Helpers (`std.string`)

```duo
str = req "std.string"

str.starts_with("duo-lang", "duo")  -- true
str.ends_with("duo-lang", "lang")   -- true
str.contains("duo-lang", "-")        -- true
str.trim("  duo  ")                  -- "duo"
parts = str.split("a,b,c", ",")
joined = str.join(parts, "|")       -- "a|b|c"
str.replace_all("a-b-c", "-", ":")  -- "a:b:c"
str.repeat_str("ha", 3)               -- "hahaha"
lines = str.lines("one\ntwo")
str.to_upper("hi")                    -- "HI"
str.to_lower("HI")                    -- "hi"
str.capitalize("hello")               -- "Hello"
str.pad_left("42", 4, "0")            -- "0042"
str.reverse("abc")                    -- "cba"
str.count("hello", "l")               -- 2
str.index_of("abc", "b")              -- 2
```

## Regular Expressions (`std.regex`)

`std.regex` wraps Lua patterns for convenience:

```duo
regex = req "std.regex"

matched = regex.match("hello 123", "%d+")   -- "123"
found = regex.find("hello 123", "%d+")      -- true
replaced = regex.replace("a1 b2", "%d", "X") -- "aX bX"
all = regex.gmatch("10 20 30", "%d+")       -- {"10", "20", "30"}
```

## Math Helpers (`std.math`)

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
num.gcd(12, 8)              -- 4
num.lcm(12, 8)              -- 24
num.distance(0, 0, 3, 4)    -- 5.0

-- std.math is also a superset of the global math module:
val = num.pi + num.sqrt(16)
```

## Table Helpers (`std.table`)

```duo
tbl = req "std.table"

xs = {1, 2, 3}
tbl.len(xs)                            -- 3
tbl.contains(xs, 2)                    -- true
tbl.index_of(xs, 3)                    -- 3
tbl.reverse(xs)                        -- {3, 2, 1}
tbl.map(xs, fun(v) return v * 2 end)
tbl.filter(xs, fun(v) return v > 1 end)
tbl.reduce(xs, fun(acc, v) return acc + v end, 0)
keys = tbl.keys({a = 1, b = 2})
values = tbl.values({a = 1, b = 2})
copy = tbl.clone({a = 1})
merged = tbl.merge({a = 1}, {b = 2})
tbl.insert(xs, 1, 99)
tbl.remove(xs, 1)
tbl.sort(xs)
tbl.clear(xs)
empty = tbl.is_empty(xs)               -- true
```

## Collections (`std.collections`)

```duo
coll = req "std.collections"

-- Sets
s1 = coll.set_new()
coll.set_add(s1, "a")
s2 = coll.set_new()
coll.set_add(s2, "b")
union = coll.set_union(s1, s2)

-- Maps
m = coll.map_new()
coll.map_set(m, "key", "val")
keys = coll.map_keys(m)
```

## Functional Iterators (`std.iter`)

```duo
iter = req "std.iter"

xs = {1, 2, 3}
ys = {"a", "b", "c"}

pairs = iter.zip(xs, ys)     -- {{1, "a"}, {2, "b"}, {3, "c"}}
enum = iter.enumerate(ys)    -- {{1, "a"}, {2, "b"}, {3, "c"}}
flat = iter.flat_map({1, 2}, fun(x) return {x, x*2} end) -- {1, 2, 2, 4}
```

## Random (`std.random`)

```duo
random = req "std.random"

random.seed(os.time())
f = random.float()              -- float between 0.0 and 1.0
i = random.int(1, 100)          -- integer between 1 and 100
item = random.choice({"A", "B", "C"})
list = {"A", "B", "C"}
random.shuffle(list)            -- randomizes array in-place
```

## File-System and Archives (`std.fs`, `std.tar`, `std.zip`)

```duo
fs = req "std.fs"
tar = req "std.tar"
zip = req "std.zip"

fs.write_file("/tmp/example.txt", "one\ntwo\n")
fs.append_file("/tmp/example.txt", "three\n")

tar.create("archive.tar", "/tmp/dir")
tar.extract("archive.tar", "/tmp/out")
zip.create("archive.zip", "/tmp/dir")
zip.extract("archive.zip", "/tmp/out")
```
fs.exists("/tmp/example.txt")       -- true
text = fs.read_file("/tmp/example.txt")
lines = fs.read_lines("/tmp/example.txt")
fs.rename("/tmp/example.txt", "/tmp/example2.txt")
fs.remove("/tmp/example2.txt")

fs.mkdir_all("/tmp/nested/dir")
fs.copy("/tmp/a.txt", "/tmp/b.txt")
files = fs.read_dir("/tmp")
is_dir = fs.is_dir("/tmp")
size = fs.size("/tmp/a.txt")
```

## Path Manipulations (`std.path`)

```duo
path = req "std.path"

path.join("a", "b/c")      -- "a/b/c"
path.basename("/a/b.txt")  -- "b.txt"
path.dirname("/a/b.txt")   -- "/a"
path.extname("file.txt")   -- ".txt"
path.normalize("a//b/")    -- "a/b"
path.is_absolute("/etc")   -- true
```

## Time (`std.time`)

```duo
time = req "std.time"

now = time.now()
elapsed = time.clock()
diff = time.difftime(now, start)
time.sleep(1)  -- shell-based; mostly for scripts
```

## OS, Process, and I/O Modules

These modules are thin wrappers or helpers over Lua's built-in `os`, `io`, and `package` libraries. Use the global builtins for full Lua compatibility, or `std.os` / `std.proc` / `std.io` for a Duo-style module interface.

### `std.os`

```duo
os2 = req "std.os"
rc = os2.execute("ls -la")
os2.exit(1)
removed = os2.remove("file.txt")
renamed = os2.rename("old.txt", "new.txt")
```

### `std.sqlite`

`std.sqlite` provides a basic wrapper around the `sqlite3` command-line tool for simple local database scripts.

```duo
sqlite = req "std.sqlite"
sqlite.execute("app.db", "CREATE TABLE users(id INTEGER PRIMARY KEY, name TEXT);")
csv_data = sqlite.query_csv("app.db", "SELECT * FROM users;")
```

### `std.proc`

```duo
proc = req "std.proc"
rc = proc.exec("ls -la")
out = proc.capture("echo hello")  -- "hello\n"
```

### `std.io`

```duo
io2 = req "std.io"
-- Re-exports Lua-style io helpers; see Lua reference for full API.
```

### `std.package`

```duo
package2 = req "std.package"
path = package2.searchpath("mymod", "./?.duo;./?.lua")
```

## Memory Primitives (`std.mem`)

`std.mem` exposes allocator-like helpers implemented over tables. Native allocators are still in development; this module is mainly for portable scripts.

```duo
mem = req "std.mem"

arena = mem.arena_new(65536)
ptr = arena.alloc(64)
arena.free_all()

pool = mem.pool_new(64, 1024)
block = pool.alloc()
pool.free(block)

stack = mem.stack_new(4096)
cp = stack.checkpoint()
ptr2 = stack.alloc(32)
stack.restore(cp)
```

## Networking (`std.net`, `std.http`)

`std.net` provides URL parsing, TCP/UDP helpers, and core HTTP functions. When the module variable is named `net`, the compiler emits direct C calls (`duo_net_http_get`, etc.) for zero-overhead networking.
`std.http` provides a convenient alias for high-level HTTP client and server functions.

```duo
net = req "std.net"
http = req "std.http"

parsed = net.parse_url("https://example.com:8080/path")
body = http.get("https://example.com")
resp = http.post(url, "body", "application/json")
```

## Coroutines and Concurrency

### `std.coroutine`

```duo
co = req "std.coroutine"

fiber = co.create(fun() return 42 end)
ok, val = co.resume(fiber)
co.yield("pause")
status = co.status(fiber)
```

### `std.sync`

Cooperative scheduler with typed channels. Single-threaded; for multi-core work use `std.concurrent` / `std.thread`.

```duo
sync = req "std.sync"

sync.spawn(fun()
    print("task 1")
end)

ch = sync.channel(10)
sync.spawn(fun()
    sync.channel_send(ch, "hello")
end)

msg = sync.channel_recv(ch)
sync.run()   -- drive all spawned tasks to completion
```

### `std.concurrent`

High-level patterns built on `std.sync`:

```duo
concurrent = req "std.concurrent"

-- Run a task and return a future
fut = concurrent.go(fun() return 42 end)
val = concurrent.wait(fut)   -- 42

-- Run many tasks, collect results
results = concurrent.all({
    fun() return 1 end,
    fun() return 2 end,
})
```

### `std.thread`

OS-level threading primitives (mutex, rwlock, cond, semaphore, barrier). In single-threaded mode these are backed by coroutines; with `@concurrent("threaded")` they map to pthreads.

```duo
thread = req "std.thread"

m = thread.mutex()
thread.lock(m)
-- critical section
thread.unlock(m)
```

### `std.mproc`

```duo
mp = req "std.mproc"
mp.spawn("sleep 1 && echo done")
```

## WASM / WASI (`std.wasm.wasi`)

Type definitions and constants for WebAssembly System Interface targets. Imported automatically or referenced when compiling with `--target wasm32-wasi`.

```duo
wasi = req "std.wasm.wasi"

fd = wasi.fd_stdout()   -- 1
err = wasi.errno_success()  -- 0
```

## Debug and Formatting Modules (`std.debug`, `std.color`)

```duo
debug2 = req "std.debug"

msg = debug2.traceback("error context", 1)
info = debug2.getinfo(my_fn, "nSl")
```

```duo
color = req "std.color"

print(color.red("Error:") .. " " .. color.bold("something went wrong"))
```

## Global Functions

Duo also keeps Lua's global functions available:

```duo
print("Hello, Duo!")
assert(x > 0, "x must be positive")
warn("This is a warning")
first, second, third = unpack({1, 2, 3})
count = collectgarbage("count")
ok, err = xpcall(fun() return error() end, fun(e) return e end)
chunk = load("return 1 + 1")
result = dofile("script.duo")
```

## Metatable Functions

```duo
mt = { __tostring = fun() return "custom" end }
t = {}
setmetatable(t, mt)
got_mt = getmetatable(t)

val = rawget(t, "key")
rawset(t, "key", value)
rawlen("hello")
rawequal(t, t)
```
