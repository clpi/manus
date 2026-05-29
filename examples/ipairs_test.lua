-- Test ipairs iterator in Duo AOT compiler
local t = { "a", "b", "c" }
print("Iterating using ipairs:")
for i, v in ipairs(t) do
    print(i, v)
end
