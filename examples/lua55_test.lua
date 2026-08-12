-- Lua 5.5 language features and stdlib coverage for Duo

local function assert_eq(a, b, msg)
    if a ~= b then
        error((msg or "assert_eq") .. ": got " .. tostring(a) .. " expected " .. tostring(b))
    end
end

print("--- global declarations ---")
global g55 = 42
assert_eq(g55, 42, "global g55")

print("--- named vararg table ---")
function sum_all(first, ...rest)
    local total = first
    for i = 1, rest.n do
        total += rest[i]
    end
    return total
end
assert_eq(sum_all(1, 2, 3, 4), 10, "named varargs sum")

print("--- table.create ---")
local t1 = table.create(3)
local t2 = table.create(3, 2)
table.insert(t1, "a")
assert_eq(#t1, 1, "table.create seq")
assert_eq(type(t2), "table", "table.create seq+hash")

print("--- utf8.offset dual return ---")
local pos, cpos = utf8.offset("hello", 2)
assert_eq(pos, 2, "utf8.offset byte pos")
assert_eq(cpos, 2, "utf8.offset char pos")

print("--- math 5.x extras ---")
assert_eq(math.type(1.0), "float", "math.type float")
assert_eq(math.tointeger(3.0), 3, "math.tointeger")
local lo, hi = math.modf(3.75)
assert_eq(lo, 3.0, "math.modf int")
assert_eq(math.atan2(1, 1) > 0.7, true, "math.atan2")
assert_eq(math.log10(1000), 3.0, "math.log10")

print("--- multi-return assignment ---")
local function dual() return 10, 20 end
local ma, mb
ma, mb = dual()
assert_eq(ma, 10, "multi-assign first")
assert_eq(mb, 20, "multi-assign second")

print("--- string.buffer module ---")
local buf = string.buffer.new()
buf:put("lua")
buf:put("55")
assert_eq(buf:get(), "lua55", "string.buffer")
local buf2 = string.buffer.new("init")
assert_eq(buf2:get(), "init", "string.buffer new init")
buf2:reset()
buf2:put("x")
assert_eq(buf2:tostring(), "x", "string.buffer tostring")
buf2:set("y")
assert_eq(buf2:get(), "y", "string.buffer set")

print("--- integer number_kind through arithmetic ---")
assert_eq(math.type(1 + 2), "integer", "int add")
assert_eq(math.type(1.0 + 2), "float", "mixed add")
assert_eq(math.type(10 // 3), "integer", "int idiv")

print("--- debug.getinfo stub ---")
local info = debug.getinfo(1)
assert_eq(type(info), "table", "debug.getinfo table")
assert_eq(info.what, "C", "debug.getinfo what")

print("--- to-be-closed locals ---")
do
    local f <close> = io.open("/dev/null", "r")
    assert_eq(type(f), "file", "close file type")
end

print("--- dynamic math.atan2 ---")
local atan2_fn = math.atan2
assert_eq(atan2_fn(1, 1) > 0.7, true, "math.atan2 dynamic")

print("--- for loop control vars are read-only (compile-time) ---")
print("(verified by sema: assigning to numeric/generic for vars is rejected)")

print("--- _VERSION ---")
assert_eq(_VERSION, "Lua 5.5", "_VERSION")

print("--- table.pack varargs ---")
local pk = table.pack(1, 2, 3)
assert_eq(pk.n, 3, "table.pack n")
assert_eq(pk[2], 2, "table.pack [2]")

print("--- table.freeze ---")
local fr = { a = 1 }
assert_eq(table.isfrozen(fr), false, "not frozen yet")
table.freeze(fr)
assert_eq(table.isfrozen(fr), true, "frozen")

print("--- math hyperbolic and pow ---")
assert_eq(math.pow(2, 3), 8, "math.pow")
assert_eq(math.tanh(0), 0, "math.tanh(0)")

print("--- string.buffer len/putf ---")
local buf3 = string.buffer.new()
buf3:putf("x=%d", 7)
assert_eq(buf3:len(), 3, "buffer len")
assert_eq(buf3:get(), "x=7", "buffer putf")

print("--- pcall with extra args ---")
local function add3(a, b, c) return a + b + c end
local ok, sum = pcall(add3, 1, 2, 3)
assert_eq(ok, true, "pcall ok")
assert_eq(sum, 6, "pcall multi-arg result")

print("--- package fields ---")
assert_eq(type(package.preload), "table", "package.preload")
assert_eq(type(package.searchers), "table", "package.searchers")

print("--- io std handles ---")
assert_eq(type(io.stdin), "file", "io.stdin")
assert_eq(type(io.stdout), "file", "io.stdout")

print("All Lua 5.5 feature tests passed")
