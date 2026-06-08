local function fib(n)
    if n <= 1 then return n end
    return fib(n - 1) + fib(n - 2)
end

-- fib(10) = 55
print(fib(10))

-- fib(0..5)
for i = 0, 5 do
    print(fib(i))
end
