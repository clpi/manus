-- The .lua half of the GAP-059 pair, and the load-bearing half.
--
-- Infix `@` was NOT removed from the compiler — it was gated on the dialect.
-- Lua is not the canonical surface, `.matmul` is still the operator it always was
-- there, and this file must keep checking clean. Without this row the suite
-- cannot tell "Duo refuses a spaced `@` over non-tensors" apart from "the front
-- end lost the operator", which is the same distinction the retired pairs
-- draw over `try` and `goto`.
--
-- Positive control, not decoration: if `check_infix_at` in src/sema.zig ever
-- forgets its `duo_mode` guard, this row is what goes red.

local a = 3
local b = 4
local c = a @ b
print(c)
