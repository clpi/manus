-- Test stdlib functions in Duo AOT compiler
local val_num = 123.45
local val_str = tostring(val_num)
assert(type(val_str) == "string", "tostring failed")
print("tostring successful, type is:", type(val_str))

local val_num2 = tonumber(val_str)
assert(type(val_num2) == "number", "tonumber failed")
print("tonumber successful, type is:", type(val_num2))

assert(1 + 1 == 2, "math failed")
print("All assertions passed successfully!")
