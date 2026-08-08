-- NEGATIVE CONTROL for pass100_try_retired.duo — byte-identical body.
--
-- This file must COMPILE. It is what proves the Pass 100 deny table is gated on
-- the `.duo` dialect rather than removed from the compiler: "lua native compile"
-- keeps working. If this ever starts failing, the gate leaked out of duo_mode.

local ok = 1
try
  ok = 2
catch e
  ok = 3
end
print(ok)
