-- This plain .lua file runs through duo unchanged (100% Lua compatible)
print("Hello from duo!")

local function greet(name)
    return "Hello, " .. name .. "!"
end

print(greet("world"))
