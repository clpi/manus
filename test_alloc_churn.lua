function alloc_churn(n)
    local sum = 0
    local t = {}
    for i = 1, n do
        t[1] = i
        t[2] = i * 2
        t[3] = i * 3
        t[4] = i * 4
        sum = sum + t[1] + t[2] + t[3] + t[4]
        t = {} -- new table
    end
    return sum
end

print("Alloc churn: ", alloc_churn(10000000))
