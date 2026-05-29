-- Comprehensive test of newly added standard library features for Lua 5.4 in Duo

print("--- Testing Global standard functions ---")
local sel_res = select(1, "first")
print("select(1, 'first'):", sel_res)
assert(sel_res == "first", "select failed")

local total_args = select("#", "only_one")
print("select('#', 'only_one'):", total_args)
assert(total_args == 1, "select count failed")

-- pcall test
local function pass_func(v)
    print("Function called inside pcall with:", v)
    return "ok"
end
local success = pcall(pass_func, "arg_data")
print("pcall success:", success)
assert(success == true, "pcall failed")

print("\n--- Testing Math 5.4 Extras ---")
local to_int = math.tointeger(15.0)
print("math.tointeger(15.0):", to_int)
assert(to_int == 15, "math.tointeger failed")

local not_int = math.tointeger(15.5)
print("math.tointeger(15.5):", not_int)
assert(not_int == nil, "math.tointeger for float failed")

local int_part = math.modf(12.34)
print("math.modf(12.34) integral:", int_part)
assert(int_part == 12, "math.modf failed")

local is_ult = math.ult(10, 20)
print("math.ult(10, 20):", is_ult)
assert(is_ult == true, "math.ult failed")

print("\n--- Testing String 5.4 Extras ---")
local match_res = string.match("Hello, Duo Compiler!", "Duo")
print("string.match:", match_res)
assert(match_res == "Duo", "string.match failed")

print("\n--- Testing Table 5.4 Extras ---")
local packed_tbl = table.pack("packed_item")
print("table.pack count:", packed_tbl.n)
assert(packed_tbl.n == 1, "table.pack count failed")
assert(packed_tbl[1] == "packed_item", "table.pack content failed")

print("\n--- Testing Coroutine 5.4 Extras ---")
-- local function test_co(v)
--     print("Inside wrapped coroutine:", v)
--     return "done"
-- end
-- local ok_wrap, wrap_err = pcall(function() coroutine.wrap(test_co) end)
-- assert(not ok_wrap, "coroutine.wrap should throw an unsupported error")

local yieldable = coroutine.isyieldable()
print("Main thread yieldable:", yieldable)
assert(yieldable == false, "isyieldable failed")

print("\n--- Testing OS 5.4 Extras ---")
local tmp = os.tmpname()
print("os.tmpname():", tmp)
assert(string.len(tmp) > 0, "os.tmpname failed")

print("\n--- Testing UTF8 5.4 Extras ---")
local codep = utf8.codepoint("Duo", 2) -- 'u' is 117
print("utf8.codepoint('Duo', 2):", codep)
assert(codep == 117, "utf8.codepoint failed")

local offs = utf8.offset("Duo 🚀", 5) -- offset for emoji (5th codepoint)
print("utf8.offset('Duo 🚀', 5) offset:", offs)
assert(offs == 5, "utf8.offset failed")

print("\nAll standard library features verified successfully!")
