-- Test script to thoroughly verify all remaining implemented standard library features

print("--- Testing Math Library Extras ---")
print("math.pi:", math.pi)
assert(math.pi > 3.14 and math.pi < 3.15, "math.pi failed")
print("math.maxinteger:", math.maxinteger)
assert(math.maxinteger > 900000000000000000, "math.maxinteger failed")
print("math.mininteger:", math.mininteger)
assert(math.mininteger < -900000000000000000, "math.mininteger failed")

-- test math.deg/rad/type
print("math.deg(math.pi):", math.deg(math.pi))
assert(math.deg(math.pi) == 180, "math.deg failed")
print("math.rad(180):", math.rad(180))
assert(math.rad(180) == math.pi, "math.rad failed")

print("math.type(10):", math.type(10))
assert(math.type(10) == "integer", "math.type integer failed")
print("math.type(10.5):", math.type(10.5))
assert(math.type(10.5) == "float", "math.type float failed")

-- test math.random / math.randomseed
math.randomseed(1234)
local r1 = math.random()
local r2 = math.random(10)
local r3 = math.random(100, 200)
print("math.random() float:", r1)
assert(r1 >= 0 and r1 <= 1, "math.random float failed")
print("math.random(10):", r2)
assert(r2 >= 1 and r2 <= 10, "math.random 1-arg failed")
print("math.random(100, 200):", r3)
assert(r3 >= 100 and r3 <= 200, "math.random 2-arg failed")

print("\n--- Testing String Library Extras ---")
local byte_val = string.byte("Duo", 1)
print("string.byte('Duo', 1):", byte_val)
assert(byte_val == 68, "string.byte failed")

local find_pos = string.find("Hello, Duo!", "Duo")
print("string.find('Hello, Duo!', 'Duo'):", find_pos)
assert(find_pos == 8, "string.find failed")

print("\n--- Testing Table Library Extras ---")
local t1 = { 1, 2, 3 }
local t2 = { 10, 20, 30 }
table.move(t1, 1, 3, 2, t2) -- copy t1[1..3] to t2 starting at index 2
print("table.move concat:", table.concat(t2, ", "))
assert(table.concat(t2, ", ") == "10, 1, 2, 3", "table.move failed")

local unpacked = table.unpack(t2, 2)
print("table.unpack(t2, 2):", unpacked)
assert(unpacked == 1, "table.unpack failed")

print("\n--- Testing File IO Library ---")
local temp_file = "duo_temp_test.txt"
local f = io.open(temp_file, "w")
assert(f ~= nil, "io.open for writing failed")
f:write("Line 1 from Duo File IO!\n")
f:close()

local f_in = io.open(temp_file, "r")
assert(f_in ~= nil, "io.open for reading failed")
local read_line = f_in:read()
print("Read from file:", read_line)
assert(read_line == "Line 1 from Duo File IO!", "file read failed")
f_in:close()

-- Clean up
os.remove(temp_file)

print("\n--- Testing OS Date & Execute ---")
local formatted_date = os.date("%Y-%m-%d")
print("os.date('%Y-%m-%d'):", formatted_date)
assert(string.len(formatted_date) == 10, "os.date length mismatch")

local exec_ok = os.execute("echo 'os.execute works!'")
assert(exec_ok == true, "os.execute failed")

print("\n--- Testing UTF-8 Codepoint Length ---")
local u_str = "Duo 🚀"
print("utf8.len('Duo 🚀'):", utf8.len(u_str))
assert(utf8.len(u_str) == 5, "utf8.len failed")

print("\n--- Testing Debug Traceback ---")
local tb = debug.traceback()
print("debug.traceback():\n" .. tb)
assert(string.find(tb, "traceback") ~= nil, "debug.traceback failed")

print("\n--- Testing Require Cache / Globals ---")
local req_math = require("math")
assert(req_math == math, "require('math') failed")
print("require('math').pi:", req_math.pi)

print("\nAll remaining stdlib implementations tested and verified successfully!")
