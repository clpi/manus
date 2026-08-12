-- Basic Lua/Duo compatibility smoke tests.
-- These are run by scripts/run_compile_fail_tests.sh via `duo check`.

-- Arithmetic
local a = 1 + 2
local b = a * 3
local c = b - 1

-- Conditionals
if a < b then
    local x = 1
end

-- Loops
local sum = 0
for i = 1, 10 do
    sum += i
end

-- Functions
local function double(n)
    return n * 2
end
local result = double(21)

-- Tables
local t = {1, 2, 3}
local named = {x = 10, y = 20}

-- String operations
local s = "hello"
local greeting = s .. " world"

-- Boolean logic
local flag = true
if flag and a > 0 then
    local ok = true
end

-- Nested functions
local function make_adder(n)
    return function(x)
        return x + n
    end
end
