-- Duo WASM Runtime Benchmark Suite
-- Same 40 compute kernels as benchmark.lua, without os.clock().
-- Timed externally (wall clock per runtime). Prints RESULT lines for
-- correctness verification against the native reference.
-- Compatible with wasm32-wasi: no coroutines, no os/io libraries.

-- 1. Recursive Fibonacci (lowered to iterative by the compiler)
function fib(n)
    if n <= 1 then return n end
    return fib(n - 1) + fib(n - 2)
end

-- 2. Prime counting (trial division in source; Eratosthenes sieve in codegen)
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

-- 3. Mandelbrot core iteration
function mandel_iter(cx: f64, cy: f64): i64
    local zx: f64 = 0.0
    local zy: f64 = 0.0
    local i: i64 = 0
    while i < 10000 do
        local zx2: f64 = zx * zx
        local zy2: f64 = zy * zy
        if zx2 + zy2 > 4.0 then
            return i
        end
        zy = 2.0 * zx * zy + cy
        zx = zx2 - zy2 + cx
        i = i + 1
    end
    return i
end

-- 4. Spectral-norm style grid
function eval_A(i: i64, j: i64): f64
    return 1.0 / ((i + j) * (i + j + 1) / 2 + i + 1)
end

function compute_grid_sum(size: i64): f64
    local total: f64 = 0.0
    local i: i64 = 0
    while i < size do
        local j: i64 = 0
        while j < size do
            total = total + eval_A(i, j)
            j = j + 1
        end
        i = i + 1
    end
    return total
end

-- 5. N-body physics
function simulate_nbody(steps: i64): f64
    local x1: f64 = 0.0
    local y1: f64 = 0.0
    local vx1: f64 = 0.0
    local vy1: f64 = 0.0
    local m1: f64 = 1000.0
    local x2: f64 = 10.0
    local y2: f64 = 0.0
    local vx2: f64 = 0.0
    local vy2: f64 = 10.0
    local m2: f64 = 1.0
    local x3: f64 = 0.0
    local y3: f64 = -10.0
    local vx3: f64 = -10.0
    local vy3: f64 = 0.0
    local m3: f64 = 1.0
    local dt: f64 = 0.001
    local i: i64 = 0
    while i < steps do
        local dx12: f64 = x2 - x1
        local dy12: f64 = y2 - y1
        local dist12_sq: f64 = dx12 * dx12 + dy12 * dy12 + 0.001
        local dist12: f64 = math.sqrt(dist12_sq)
        local f12: f64 = (m1 * m2) / dist12_sq
        vx1 = vx1 + (f12 * dx12 / dist12) * dt / m1
        vy1 = vy1 + (f12 * dy12 / dist12) * dt / m1
        vx2 = vx2 - (f12 * dx12 / dist12) * dt / m2
        vy2 = vy2 - (f12 * dy12 / dist12) * dt / m2
        local dx13: f64 = x3 - x1
        local dy13: f64 = y3 - y1
        local dist13_sq: f64 = dx13 * dx13 + dy13 * dy13 + 0.001
        local dist13: f64 = math.sqrt(dist13_sq)
        local f13: f64 = (m1 * m3) / dist13_sq
        vx1 = vx1 + (f13 * dx13 / dist13) * dt / m1
        vy1 = vy1 + (f13 * dy13 / dist13) * dt / m1
        vx3 = vx3 - (f13 * dx13 / dist13) * dt / m3
        vy3 = vy3 - (f13 * dy13 / dist13) * dt / m3
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

-- 6. String stdlib: rep + len + byte checksum
function string_byte_sum(n)
    local s = string.rep("The quick brown fox jumps over the lazy dog. ", n)
    local sum = 0
    local i = 1
    local last = string.len(s)
    while i <= last do
        sum = sum + string.byte(s, i)
        i = i + 1
    end
    return sum
end

-- 7. Table stdlib pattern: fill indexed table and sum (dense array lowering)
function table_array_sum(n)
    local t = {}
    local i = 1
    while i <= n do
        t[i] = i
        i = i + 1
    end
    local sum = 0
    i = 1
    while i <= n do
        sum = sum + t[i]
        i = i + 1
    end
    return sum
end

-- 8. Math stdlib: sin/cos accumulation
function trig_sum(n)
    local sum = 0.0
    local i = 0
    while i < n do
        sum = sum + math.sin(i) * math.cos(i)
        i = i + 1
    end
    return sum
end

-- 9. String stdlib chain: len + rep in a hot loop
function string_len_chain(n)
    local s = string.rep("a", 1000)
    local total = 0
    local i = 1
    while i <= n do
        total = total + string.len(s) + string.len(string.rep("b", (i % 10) + 1))
        i = i + 1
    end
    return total
end

-- 10. Integer hash using string.byte on a long literal
function string_hash_roll(n)
    local s = string.rep("benchmark", n)
    local h = 0
    local i = 1
    local lim = string.len(s)
    while i <= lim do
        h = (h * 31 + string.byte(s, i)) % 1000000007
        i = i + 1
    end
    return h
end

-- 11. Math stdlib mix: floor + max (common game / layout logic)
function math_floor_max(n)
    local acc = 0.0
    local peak = 0.0
    local i = 0
    while i < n do
        local v = math.floor((i * 0.73) + 0.5)
        acc = acc + v
        peak = math.max(peak, v)
        i = i + 1
    end
    return acc + peak
end

-- 12. Dense table scan: max value (table-as-array pattern)
function table_max_scan(n)
    local t = {}
    local i = 1
    while i <= n do
        t[i] = (i * 17) % 100003
        i = i + 1
    end
    local mx = 0
    i = 1
    while i <= n do
        if t[i] > mx then
            mx = t[i]
        end
        i = i + 1
    end
    return mx
end

-- 13. Math stdlib: pow + sqrt accumulation
function math_pow_sqrt(n)
    local sum = 0.0
    local i = 1
    while i <= n do
        sum = sum + math.sqrt(math.pow(i % 997, 0.25))
        i = i + 1
    end
    return sum
end

-- 14. Sorted-array binary search (config lookup / game entity ID)
function binary_search_scan(n)
    local t = {}
    local i = 1
    while i <= n do
        t[i] = i
        i = i + 1
    end
    local hits = 0
    local q = 1
    while q <= 200000 do
        local key = ((q * 7919) % n) + 1
        local lo = 1
        local hi = n
        while lo <= hi do
            local mid = math.floor((lo + hi) / 2)
            if t[mid] < key then
                lo = mid + 1
            elseif t[mid] > key then
                hi = mid - 1
            else
                hits = hits + 1
                break
            end
        end
        q = q + 1
    end
    return hits
end

-- 15. Filter / predicate count (analytics, log filtering)
function filter_count(n)
    local count = 0
    local i = 1
    while i <= n do
        local v = (i * 17) % 100003
        if v > 50000 then
            count = count + 1
        end
        i = i + 1
    end
    return count
end

-- 16. Dot product of two vectors (ML features, physics, graphics)
function dot_product(n)
    local a = {}
    local b = {}
    local i = 1
    while i <= n do
        a[i] = i
        b[i] = n - i + 1
        i = i + 1
    end
    local sum = 0
    i = 1
    while i <= n do
        sum = sum + a[i] * b[i]
        i = i + 1
    end
    return sum
end

-- 17. Clamp / saturate accumulation (color, audio, game stats)
function clamp_sum(n)
    local sum = 0
    local i = 0
    while i < n do
        sum = sum + math.min(255, math.max(0, i % 1000))
        i = i + 1
    end
    return sum
end

-- 18. Bucket / histogram key hash (sharding, metrics tags)
function bucket_hash(n)
    local sum = 0
    local i = 1
    while i <= n do
        sum = sum + (i * 31) % 256
        i = i + 1
    end
    return sum
end

-- 19. Exponential moving average (metrics, smoothing)
function ema_smooth(n)
    local avg = 0.0
    local i = 0
    while i < n do
        avg = avg * 0.95 + (i % 100) * 0.05
        i = i + 1
    end
    return avg
end

-- 20. Token / word count (log parsing, CSV fields)
function token_count(n)
    local s = string.rep("alpha beta gamma ", n)
    local count = 0
    local i = 1
    local last = string.len(s)
    while i <= last do
        if string.byte(s, i) == 32 then
            count = count + 1
        end
        i = i + 1
    end
    return count
end

-- 21. Config / JSON-ish delimiter scan
function config_parse_sum(n)
    local s = string.rep('{"id":1,"name":"item","ok":true},', n)
    local sum = 0
    local i = 1
    local last = string.len(s)
    while i <= last do
        local c = string.byte(s, i)
        if c == 123 or c == 58 or c == 34 then
            sum = sum + c
        end
        i = i + 1
    end
    return sum
end

-- 22. Indexed table lookup accumulation (cache / entity table)
function table_lookup_sum(n)
    local t = {}
    local i = 1
    while i <= n do
        t[i] = i * 3
        i = i + 1
    end
    local sum = 0
    local q = 1
    while q <= n do
        local idx = (q * 7) % n + 1
        sum = sum + t[idx]
        q = q + 1
    end
    return sum
end

-- 23. Table insert churn then aggregate (metrics buffers)
function table_insert_churn(n)
    local t = {}
    local i = 1
    while i <= n do
        t[i] = (i * 13) % 997
        i = i + 1
    end
    local sum = 0
    i = 1
    while i <= n do
        sum = sum + t[i]
        i = i + 1
    end
    return sum
end

-- 24. Small matrix multiply (nested loop + indexed table access)
function matmul(n: i64): i64
    local size: i64 = 200
    local a = {}
    local b = {}
    local c = {}
    local i: i64 = 1
    while i <= size * size do
        a[i] = i % 100
        b[i] = (i * 7) % 100
        c[i] = 0
        i = i + 1
    end
    local rep: i64 = 0
    while rep < n do
        i = 0
        while i < size do
            local j: i64 = 0
            while j < size do
                local sum: i64 = 0
                local k: i64 = 0
                while k < size do
                    sum = sum + a[i * size + k + 1] * b[k * size + j + 1]
                    k = k + 1
                end
                c[i * size + j + 1] = sum
                j = j + 1
            end
            i = i + 1
        end
        rep = rep + 1
    end
    local total: i64 = 0
    i = 1
    while i <= size * size do
        total = total + c[i]
        i = i + 1
    end
    return total
end

-- 25. Prefix sum scan (serial scan pattern)
function prefix_sum(n)
    local t = {}
    local i = 1
    while i <= n do
        t[i] = (i * 3) % 1000
        i = i + 1
    end
    i = 2
    while i <= n do
        t[i] = t[i] + t[i - 1]
        i = i + 1
    end
    return t[n]
end

-- 26. GCD reduction (Euclidean algorithm, branch-heavy)
function gcd_reduce(n)
    local sum = 0
    local i = 1
    while i <= n do
        local a = i
        local b = (i * 7 + 3) % 10000 + 1
        while b ~= 0 do
            local tmp = b
            b = a % b
            a = tmp
        end
        sum = sum + a
        i = i + 1
    end
    return sum
end

-- 27. Collatz chain length accumulation (unpredictable branching)
function collatz_sum(n: i64): i64
    local total: i64 = 0
    local i: i64 = 1
    while i <= n do
        local x: i64 = i
        local steps: i64 = 0
        while x ~= 1 do
            if x % 2 == 0 then
                x = x // 2
            else
                x = 3 * x + 1
            end
            steps = steps + 1
        end
        total = total + steps
        i = i + 1
    end
    return total
end

-- 28. XOR fold / bit manipulation reduction
function xor_fold(n)
    local acc = 0
    local i = 1
    while i <= n do
        acc = acc ~ (i * 2654435761)
        i = i + 1
    end
    return acc
end

-- 29. Ring buffer write/read simulation (modulo indexing)
function ring_buffer(n)
    local size = 1024
    local buf = {}
    local i = 1
    while i <= size do
        buf[i] = 0
        i = i + 1
    end
    local sum = 0
    i = 0
    while i < n do
        local idx = (i % size) + 1
        buf[idx] = (i * 31) % 100000
        sum = sum + buf[((i + size - 7) % size) + 1]
        i = i + 1
    end
    return sum
end

-- 30. Conditional swap reduce (sorting-kernel pattern)
function cond_swap(n)
    local t = {}
    local i = 1
    while i <= n do
        t[i] = (i * 17) % 10007
        i = i + 1
    end
    local passes = 5
    local p = 0
    while p < passes do
        i = 1
        while i < n do
            if t[i] > t[i + 1] then
                local tmp = t[i]
                t[i] = t[i + 1]
                t[i + 1] = tmp
            end
            i = i + 1
        end
        p = p + 1
    end
    local sum = 0
    i = 1
    while i <= n do
        sum = sum + t[i]
        i = i + 1
    end
    return sum
end

-- 31. Ackermann-like (bounded recursion stress)
function ack(m, n)
    if m == 0 then return n + 1 end
    if n == 0 then return ack(m - 1, 1) end
    return ack(m - 1, ack(m, n - 1))
end

-- 32. Levenshtein distance (2D DP table)
function leven(n)
    local sum = 0
    local rep = 0
    while rep < n do
        local len_a = 12
        local len_b = 13
        local prev = {}
        local curr = {}
        local j = 0
        while j <= len_b do
            prev[j] = j
            j = j + 1
        end
        local i = 1
        while i <= len_a do
            curr[0] = i
            j = 1
            while j <= len_b do
                local a_char = ((rep * 7 + i * 3) % 26)
                local b_char = ((rep * 13 + j * 5) % 26)
                local cost = 0
                if a_char ~= b_char then cost = 1 end
                local del = prev[j] + 1
                local ins = curr[j - 1] + 1
                local sub = prev[j - 1] + cost
                local mn = del
                if ins < mn then mn = ins end
                if sub < mn then mn = sub end
                curr[j] = mn
                j = j + 1
            end
            local tmp = prev
            prev = curr
            curr = tmp
            i = i + 1
        end
        sum = sum + prev[len_b]
        rep = rep + 1
    end
    return sum
end

-- 33. Sieve of Eratosthenes (boolean array)
function sieve(n: i64): i64
    local is_prime = {}
    local i: i64 = 0
    while i <= n do
        is_prime[i] = true
        i = i + 1
    end
    is_prime[0] = false
    is_prime[1] = false
    i = 2
    while i * i <= n do
        if is_prime[i] then
            local j: i64 = i * i
            while j <= n do
                is_prime[j] = false
                j = j + i
            end
        end
        i = i + 1
    end
    local count: i64 = 0
    i = 2
    while i <= n do
        if is_prime[i] then count = count + 1 end
        i = i + 1
    end
    return count
end

-- 34. Fenwick tree (point update + prefix query)
function fenwick(size: i64): i64
    local tree = {}
    local i: i64 = 0
    while i <= size do
        tree[i] = 0
        i = i + 1
    end
    i = 1
    while i <= size do
        local val: i64 = (i * 3) % 1000
        local idx: i64 = i
        while idx <= size do
            tree[idx] = tree[idx] + val
            idx = idx + (idx & (-idx))
        end
        i = i + 1
    end
    local sum: i64 = 0
    local q: i64 = 1
    while q <= size do
        local idx: i64 = q
        while idx > 0 do
            sum = sum + tree[idx]
            idx = idx - (idx & (-idx))
        end
        q = q + 1
    end
    return sum
end

-- 35. Linear interpolation table lookup
function interp(n)
    local tbl_size = 1024
    local tbl = {}
    local i = 0
    while i < tbl_size do
        tbl[i] = math.sin(i * 0.01)
        i = i + 1
    end
    local sum = 0.0
    i = 0
    while i < n do
        local x = (i * 0.0073) % (tbl_size - 1)
        local idx = math.floor(x)
        local frac = x - idx
        sum = sum + tbl[idx] * (1.0 - frac) + tbl[idx + 1] * frac
        i = i + 1
    end
    return sum
end

-- 36. Run-length encoding count (byte comparison)
function run_len(n)
    local s = string.rep("aaabbccddddeefffff", n)
    local count = 0
    local i = 2
    local last = string.len(s)
    while i <= last do
        if string.byte(s, i) ~= string.byte(s, i - 1) then
            count = count + 1
        end
        i = i + 1
    end
    return count + 1
end

-- 37. Population count / Hamming weight reduction
function bitcount(n: i64): i64
    local sum: i64 = 0
    local i: i64 = 1
    while i <= n do
        local x: i64 = i
        local c: i64 = 0
        while x ~= 0 do
            c = c + (x & 1)
            x = x >> 1
            end
        sum = sum + c
        i = i + 1
    end
    return sum
end

-- 38. CORDIC-style sin approximation (shift+add, no math.sin)
function cordic(n)
    local sum = 0.0
    local i = 0
    while i < n do
        local angle = (i % 1000) * 0.001
        local s = angle
        local term = angle
        local k = 1
        while k <= 5 do
            term = -term * angle * angle / ((2 * k) * (2 * k + 1))
            s = s + term
            k = k + 1
        end
        sum = sum + s
        i = i + 1
    end
    return sum
end

-- 39. Sparse vector dot (stride access pattern)
function sparse_dot(n)
    local stride = 16
    local len = n * stride
    local a = {}
    local b = {}
    local i = 1
    while i <= len do
        a[i] = 0
        b[i] = 0
        i = i + 1
    end
    i = 1
    while i <= n do
        local idx = (i - 1) * stride + 1
        a[idx] = i
        b[idx] = n - i + 1
        i = i + 1
    end
    local sum = 0
    i = 1
    while i <= n do
        local idx = (i - 1) * stride + 1
        sum = sum + a[idx] * b[idx]
        i = i + 1
    end
    return sum
end

-- 40. Game of Life step (2D grid neighbor count)
function life(steps)
    local W = 128
    local H = 128
    local grid = {}
    local next_grid = {}
    local i = 0
    while i < W * H do
        grid[i] = (i * 31337) % 3 == 0 and 1 or 0
        next_grid[i] = 0
        i = i + 1
    end
    local s = 0
    while s < steps do
        local y = 1
        while y < H - 1 do
            local x = 1
            while x < W - 1 do
                local neighbors = grid[(y-1)*W + (x-1)] + grid[(y-1)*W + x] + grid[(y-1)*W + (x+1)] + grid[y*W + (x-1)] + grid[y*W + (x+1)] + grid[(y+1)*W + (x-1)] + grid[(y+1)*W + x] + grid[(y+1)*W + (x+1)]
                local cell = grid[y * W + x]
                if cell == 1 then
                    next_grid[y * W + x] = (neighbors == 2 or neighbors == 3) and 1 or 0
                else
                    next_grid[y * W + x] = neighbors == 3 and 1 or 0
                end
                x = x + 1
            end
            y = y + 1
        end
        local tmp = grid
        grid = next_grid
        next_grid = tmp
        s = s + 1
    end
    local sum = 0
    i = 0
    while i < W * H do
        sum = sum + grid[i]
        i = i + 1
    end
    return sum
end

-- ── Execution (no os.clock — timed externally per WASM runtime) ──────────────

local fib_res = fib(40)
print("RESULT fib", fib_res)

local prime_res = count_primes(100000)
print("RESULT primes", prime_res)

local sum_iters = 0
local y = -100
while y <= 100 do
    local x = -100
    while x <= 100 do
        sum_iters = sum_iters + mandel_iter(x / 100.0, y / 100.0)
        x = x + 1
    end
    y = y + 1
end
print("RESULT mandel", sum_iters)

local grid_res = compute_grid_sum(5000)
print("RESULT grid", grid_res)

local nbody_res = simulate_nbody(5000000)
print("RESULT nbody", nbody_res)

local str_res = string_byte_sum(500)
print("RESULT str_bytes", str_res)

local tbl_res = table_array_sum(500000)
print("RESULT table_sum", tbl_res)

local trig_res = trig_sum(5000000)
print("RESULT trig", trig_res)

local chain_res = string_len_chain(5000)
print("RESULT str_chain", chain_res)

local hash_res = string_hash_roll(8000)
print("RESULT str_hash", hash_res)

local math_res = math_floor_max(5000000)
print("RESULT floor_max", math_res)

local max_res = table_max_scan(500000)
print("RESULT table_max", max_res)

local pow_res = math_pow_sqrt(2000000)
print("RESULT pow_sqrt", pow_res)

local bsearch_res = binary_search_scan(500000)
print("RESULT bsearch", bsearch_res)

local filter_res = filter_count(500000)
print("RESULT filter", filter_res)

local dot_res = dot_product(500000)
print("RESULT dot", dot_res)

local clamp_res = clamp_sum(5000000)
print("RESULT clamp", clamp_res)

local bucket_res = bucket_hash(1000000)
print("RESULT bucket", bucket_res)

local ema_res = ema_smooth(5000000)
print("RESULT ema", ema_res)

local token_res = token_count(50000)
print("RESULT token", token_res)

local parse_res = config_parse_sum(20000)
print("RESULT parse", parse_res)

local lookup_res = table_lookup_sum(500000)
print("RESULT lookup", lookup_res)

local churn_res = table_insert_churn(500000)
print("RESULT churn", churn_res)

local matmul_res = matmul(50)
print("RESULT matmul", matmul_res)

local prefix_res = prefix_sum(2000000)
print("RESULT prefix", prefix_res)

local gcd_res = gcd_reduce(2000000)
print("RESULT gcd", gcd_res)

local collatz_res = collatz_sum(500000)
print("RESULT collatz", collatz_res)

local xor_res = xor_fold(5000000)
print("RESULT xorfold", xor_res)

local ring_res = ring_buffer(5000000)
print("RESULT ringbuf", ring_res)

local swap_res = cond_swap(100000)
print("RESULT cond_swap", swap_res)

local ack_res = ack(3, 11)
print("RESULT ack", ack_res)

local leven_res = leven(200000)
print("RESULT leven", leven_res)

local sieve_res = sieve(2000000)
print("RESULT sieve", sieve_res)

local fenwick_res = fenwick(500000)
print("RESULT fenwick", fenwick_res)

local interp_res = interp(5000000)
print("RESULT interp", interp_res)

local rle_res = run_len(50000)
print("RESULT run_len", rle_res)

local bitcount_res = bitcount(5000000)
print("RESULT bitcount", bitcount_res)

local cordic_res = cordic(5000000)
print("RESULT cordic", cordic_res)

local sparse_res = sparse_dot(200000)
print("RESULT sparse", sparse_res)

local life_res = life(500)
print("RESULT life", life_res)
