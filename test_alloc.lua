function alloc_churn(n)
    local sum = 0
    local t = {}
    for i = 1, n do
        t[1] = i
        t[2] = i * 2
        t[3] = "hello"
        sum = sum + t[1] + t[2]
        t = {}
    end
    return sum
end
local t0 = os.clock()
print("Sum:", alloc_churn(10000000))
print("Time:", os.clock() - t0)
