-- Comprehensive test of newly implemented standard library modules in Duo

-- 1. String Library
print("--- String Library ---")
local s = "Hello, Duo!"
print("string.len:", string.len(s))
assert(string.len(s) == 11, "string.len failed")

print("string.lower:", string.lower(s))
assert(string.lower(s) == "hello, duo!", "string.lower failed")

print("string.upper:", string.upper(s))
assert(string.upper(s) == "HELLO, DUO!", "string.upper failed")

print("string.sub (positive):", string.sub(s, 8, 10))
assert(string.sub(s, 8, 10) == "Duo", "string.sub positive failed")

print("string.sub (negative):", string.sub(s, -4, -2))
assert(string.sub(s, -4, -2) == "Duo", "string.sub negative failed")

print("string.char:", string.char(68, 117, 111))
assert(string.char(68, 117, 111) == "Duo", "string.char failed")

print("string.rep:", string.rep("duo", 3, "-"))
assert(string.rep("duo", 3, "-") == "duo-duo-duo", "string.rep failed")

print("string.reverse:", string.reverse("abc"))
assert(string.reverse("abc") == "cba", "string.reverse failed")

print("string.format:", string.format("Lang: %s, Vers: %d", "Duo", 2))
assert(string.format("Lang: %s, Vers: %d", "Duo", 2) == "Lang: Duo, Vers: 2", "string.format failed")

-- 2. Table Library
print("\n--- Table Library ---")
local t = {}
table.insert(t, 20)
table.insert(t, 30)
table.insert(t, 1, 10) -- insert 10 at index 1

print("table after inserts: concat = ", table.concat(t, ", "))
assert(table.concat(t, ", ") == "10, 20, 30", "table insert failed")

local removed = table.remove(t, 2)
print("removed element:", removed)
assert(removed == 20, "table.remove element mismatch")
assert(table.concat(t, ", ") == "10, 30", "table remove shift failed")

table.insert(t, 5)
print("before sort:", table.concat(t, ", "))
table.sort(t)
print("after sort:", table.concat(t, ", "))
assert(table.concat(t, ", ") == "5, 10, 30", "table.sort failed")

-- 3. IO Library
print("\n--- IO Library ---")
io.write("Hello ", "from ", "io.write!\n")
io.flush()

-- 4. OS Library
print("\n--- OS Library ---")
local now = os.time()
print("os.time:", now)
assert(now > 0, "os.time failed")

local clock_time = os.clock()
print("os.clock:", clock_time)

local path = os.getenv("PATH")
print("os.getenv('PATH') length:", string.len(path))
assert(string.len(path) > 0, "os.getenv failed")

print("\nAll standard library modules (string, table, io, os) verified successfully in Duo!")
