-- Test standard Lua 5.4 dynamic operations in Duo
local a = 10
local b = 3

print("Floor Division (10 // 3):", a // b)
assert(a // b == 3, "floor division failed")

print("Modulo (10 % 3):", a % b)
assert(a % b == 1, "modulo failed")

print("Power (10 ^ 3):", a ^ b)
assert(a ^ b == 1000, "power failed")

print("Bitwise AND (10 & 3):", a & b)
assert(a & b == 2, "bitwise AND failed")

print("Bitwise OR (10 | 3):", a | b)
assert(a | b == 11, "bitwise OR failed")

print("Bitwise XOR (10 ~ 3):", a ~ b)
assert(a ~ b == 9, "bitwise XOR failed")

print("Left Shift (1 << 3):", 1 << 3)
assert(1 << 3 == 8, "left shift failed")

print("Right Shift (8 >> 2):", 8 >> 2)
assert(8 >> 2 == 2, "right shift failed")

print("All Lua 5.4 dynamic operations verified successfully!")
