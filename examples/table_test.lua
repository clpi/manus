-- Test dynamic tables and pairs iterator in Duo AOT compiler
local t = { name = "duo", version = 1.0, 42 }
print("Table positional element:", t[1])
print("Table field 'name':", t.name)
print("Table field 'version':", t.version)
t.version = 2.0
print("Updated version:", t.version)

print("Iterating over keys and values using pairs:")
for k, v in pairs(t) do
    print(k, v)
end
