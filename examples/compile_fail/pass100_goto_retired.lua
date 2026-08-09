-- NEGATIVE CONTROL for pass100_goto_retired.duo — the same program in Lua.
--
-- This file must COMPILE. `goto` is Lua 5.4 syntax and Duo is a Lua superset;
-- the Pass 100 deny table is gated on the `.duo` dialect, not removed from the
-- compiler, so "lua native compile" keeps working. If this ever starts
-- failing, the gate leaked out of duo_mode.
--
-- The label is `skip` rather than `continue` on purpose: `continue` is a Duo
-- keyword and the shared lexer classifies it in both dialects, so `goto
-- continue` fails for a reason that has nothing to do with this row.

local function main()
  local n = 0
  for i = 1, 3 do
    if i == 2 then goto skip end
    n = n + i
    ::skip::
  end
  return n
end

print(main())
