local t = {}
local t_start = os.clock()
for i = 1, 100000 do
    t[i] = i
end
local sum = 0
for i = 1, 100000 do
    sum += t[i]
end
local t_end = os.clock()
print("Table sum:", sum)
print("Table Time:", t_end - t_start, "seconds")
