-- Test newly supported coroutine, package, table extensions, and string buffers in Duo

-- 1. Table extensions (table.new & table.clear)
print("--- Table Extensions ---")
local t = table.new(10, 10)
table.insert(t, "apple")
table.insert(t, "banana")
print("table size after insert:", #t) -- using generic table len
assert(table.concat(t, ", ") == "apple, banana", "table.new insert failed")

table.clear(t)
print("table size after clear:", #t)
assert(#t == 0, "table.clear failed")

-- 2. String Buffer (string.buffer)
print("\n--- String Buffer ---")
local buf = string.buffer.new()
buf:put("Hello")
buf:put(", ")
buf:put("Duo Extensions!")

local result = buf:get()
print("Buffer content:", result)
assert(result == "Hello, Duo Extensions!", "string.buffer failed")

-- 3. Coroutines (coroutine)
print("\n--- Coroutines ---")
local co = coroutine.create(function(val)
    print("Coroutine started with value:", val)
    assert(val == "start", "coroutine input mismatch")
    
    local yield_res = coroutine.yield("first_yield")
    print("Coroutine resumed with value:", yield_res)
    assert(yield_res == "resume_data", "coroutine resume mismatch")
    
    return "done"
end)

print("Coroutine status before resume:", coroutine.status(co))
assert(coroutine.status(co) == "suspended", "coroutine status failed")

local res1 = coroutine.resume(co, "start")
print("First yield returned:", res1)
assert(res1 == "first_yield", "coroutine resume 1 failed")
assert(coroutine.status(co) == "suspended", "coroutine status should be suspended")

local res2 = coroutine.resume(co, "resume_data")
print("Final return returned:", res2)
assert(res2 == "done", "coroutine resume 2 failed")
assert(coroutine.status(co) == "dead", "coroutine status should be dead")

-- 4. Package and Require (package & require)
print("\n--- Package & Require ---")
print("package.path:", package.path)
assert(package.path == "./?.lua", "package.path failed")

local pkg = require("math")
print("require successfully called!")

print("\nAll advanced features (coroutine, package, table.new, table.clear, string.buffer) verified successfully!")
