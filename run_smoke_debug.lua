local std = require("lib.std")
local members = __concept_members("ContractShape")
for i, m in ipairs(members) do
  print("MEMBER:", m.name, "KIND:", m.kind, "RET:", m.ret)
end
