local function custom_iter(state, index)
    local next = index + 1
    if next > 2 then
        return nil
    end
    return next, next * 5
end

local values = setmetatable({}, {
    __pairs = function(self)
        return custom_iter, nil, 0
    end,
    __ipairs = function(self)
        return custom_iter, nil, 0
    end,
})

local pair_sum = 0
for i, value in pairs(values) do
    pair_sum += value
end

local ipairs_sum = 0
for i, value in ipairs(values) do
    ipairs_sum += value
end

print(pair_sum)
print(ipairs_sum)
