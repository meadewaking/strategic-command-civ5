-- Scalar facts over stdin; never evaluate log text as Lua code.
local root = arg[1] or "."
dofile(root.."/Lua/StrategicCommand_Decisions.lua")
for line in io.lines() do
	local facts = {}
	for key, value in line:gmatch("([%w_]+)=([^%s]+)") do
		if value == "true" then facts[key] = true
		elseif value == "false" then facts[key] = false
		else facts[key] = tonumber(value) or value end
	end
	local score, reason = SC5.AttackScore(facts)
	io.write((score and string.format("%.10f", score) or "reject").."\t"..reason.."\n")
end
