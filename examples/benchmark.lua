-- Duo Comprehensive Performance Benchmark Suite

-- 1. Recursive Fibonacci
function fib(n)
    if n <= 1 then return n end
    return fib(n - 1) + fib(n - 2)
end

-- 2. Sieve of Eratosthenes
function count_primes(limit)
    local count = 0
    local n = 2
    while n <= limit do
        local is_prime = true
        local d = 2
        while d * d <= n do
            if n % d == 0 then
                is_prime = false
            end
            d = d + 1
        end
        if is_prime then
            count = count + 1
        end
        n = n + 1
    end
    return count
end

-- 3. Heavy Floating Point Math (Mandelbrot core iteration)
function mandel_iter(cx, cy)
    local zx = 0.0
    local zy = 0.0
    local i = 0
    while i < 10000 do
        local zx2 = zx * zx
        local zy2 = zy * zy
        if zx2 + zy2 > 4.0 then
            return i
        end
        zy = 2.0 * zx * zy + cy
        zx = zx2 - zy2 + cx
        i = i + 1
    end
    return i
end

-- 4. Nested Matrix Formula Grid Solver (Spectral Norm style formula)
function eval_A(i, j)
    return 1.0 / ((i + j) * (i + j + 1) / 2 + i + 1)
end

function compute_grid_sum(size)
    local total = 0.0
    local i = 0
    while i < size do
        local j = 0
        while j < size do
            total = total + eval_A(i, j)
            j = j + 1
        end
        i = i + 1
    end
    return total
end

-- 5. N-Body 3-Body Gravitational Coordinate Physics Simulator
function simulate_nbody(steps)
    -- Body 1 (Heavy Star)
    local x1 = 0.0
    local y1 = 0.0
    local vx1 = 0.0
    local vy1 = 0.0
    local m1 = 1000.0

    -- Body 2 (Planet A)
    local x2 = 10.0
    local y2 = 0.0
    local vx2 = 0.0
    local vy2 = 10.0
    local m2 = 1.0

    -- Body 3 (Planet B)
    local x3 = 0.0
    local y3 = -10.0
    local vx3 = -10.0
    local vy3 = 0.0
    local m3 = 1.0

    local dt = 0.001
    local i = 0
    while i < steps do
        -- Body 1 & 2 gravity
        local dx12 = x2 - x1
        local dy12 = y2 - y1
        local dist12_sq = dx12 * dx12 + dy12 * dy12 + 0.001
        local dist12 = math.sqrt(dist12_sq)
        local f12 = (m1 * m2) / dist12_sq
        
        -- Accel body 1
        vx1 = vx1 + (f12 * dx12 / dist12) * dt / m1
        vy1 = vy1 + (f12 * dy12 / dist12) * dt / m1
        -- Accel body 2
        vx2 = vx2 - (f12 * dx12 / dist12) * dt / m2
        vy2 = vy2 - (f12 * dy12 / dist12) * dt / m2

        -- Body 1 & 3 gravity
        local dx13 = x3 - x1
        local dy13 = y3 - y1
        local dist13_sq = dx13 * dx13 + dy13 * dy13 + 0.001
        local dist13 = math.sqrt(dist13_sq)
        local f13 = (m1 * m3) / dist13_sq

        -- Accel body 1
        vx1 = vx1 + (f13 * dx13 / dist13) * dt / m1
        vy1 = vy1 + (f13 * dy13 / dist13) * dt / m1
        -- Accel body 3
        vx3 = vx3 - (f13 * dx13 / dist13) * dt / m3
        vy3 = vy3 - (f13 * dy13 / dist13) * dt / m3

        -- Update positions
        x1 = x1 + vx1 * dt
        y1 = y1 + vy1 * dt
        x2 = x2 + vx2 * dt
        y2 = y2 + vy2 * dt
        x3 = x3 + vx3 * dt
        y3 = y3 + vy3 * dt

        i = i + 1
    end

    return x1 + y1 + x2 + y2 + x3 + y3
end

-- Main Benchmark Driver
print("========================================")
print("     COMPREHENSIVE BENCHMARK SUITE      ")
print("========================================")

-- Benchmark 1Fibonacci
print("Running Fibonacci(40)...")
local t_start1 = os.clock()
local fib_res = fib(40)
local t_end1 = os.clock()
local fib_time = t_end1 - t_start1
print("Fibonacci(40) Result:", fib_res)
print("Fibonacci(40) Time ", fib_time, "seconds")
print("----------------------------------------")

-- Benchmark 2Sieve of Eratosthenes
print("Running Prime Sieve (limit 100,000)...")
local t_start2 = os.clock()
local prime_res = count_primes(100000)
local t_end2 = os.clock()
local prime_time = t_end2 - t_start2
print("Primes Found       ", prime_res)
print("Prime Sieve Time   ", prime_time, "seconds")
print("----------------------------------------")

-- Benchmark 3Mandelbrot Core Floating Point
print("Running Mandelbrot iterations...")
local t_start3 = os.clock()
local sum_iters = 0
local y = -100
while y <= 100 do
    local x = -100
    while x <= 100 do
        local cx = x / 100.0
        local cy = y / 100.0
        sum_iters = sum_iters + mandel_iter(cx, cy)
        x = x + 1
    end
    y = y + 1
end
local t_end3 = os.clock()
local mandel_time = t_end3 - t_start3
print("Mandel Iterations  ", sum_iters)
print("Mandelbrot Time    ", mandel_time, "seconds")
print("----------------------------------------")

-- Benchmark 4Grid Matrix solver
print("Running Grid Matrix solver (size 5,000)...")
local t_start4 = os.clock()
local grid_res = compute_grid_sum(5000)
local t_end4 = os.clock()
local grid_time = t_end4 - t_start4
print("Grid Matrix Result ", grid_res)
print("Grid Matrix Time   ", grid_time, "seconds")
print("----------------------------------------")

-- Benchmark 5N-Body Physics Simulator
print("Running N-Body Physics (5,000,000 steps)...")
local t_start5 = os.clock()
local nbody_res = simulate_nbody(5000000)
local t_end5 = os.clock()
local nbody_time = t_end5 - t_start5
print("N-Body Coord Sum   ", nbody_res)
print("N-Body Physics Time", nbody_time, "seconds")
print("========================================")
