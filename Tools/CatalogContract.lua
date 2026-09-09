-- Bootstrap the real main file, then replace fixture rows with the installed DB.
dofile(assert(arg[2], "offline bootstrap required"))
local tables = dofile(assert(arg[3], "database fixture required"))
local function iterable(rows)
	local lookup = {}
	for _, row in ipairs(rows) do
		if row.ID ~= nil then lookup[row.ID] = row end
		if row.Type then lookup[row.Type] = row end
	end
	return setmetatable(lookup, { __call = function(_, filter)
		local i = 0
		return function()
			while i < #rows do
				i = i + 1
				local match = true
				for k, v in pairs(filter or {}) do if rows[i][k] ~= v then match = false end end
				if match then return rows[i] end
			end
		end
	end })
end
for name, rows in pairs(tables) do GameInfo[name] = iterable(rows) end
SC_UNIT_CAPABILITY_CACHE = {}
local count = 0
for row in GameInfo.Units() do
	local p = SC_GetUnitCapabilityProfile(nil, row)
	assert(p.doctrineClass ~= nil and p.doctrineClass ~= "unknown", row.Type.." unclassified")
	assert(p.range >= 0 and p.moves >= 0 and p.power >= 0, row.Type.." invalid capabilities")
	assert(not (p.noCapture and p.canCapture), row.Type.." contradictory capture flags")
	assert(not (row.Domain == "DOMAIN_AIR" and p.canCapture), row.Type.." air capture")
	io.write("CATALOG|"..row.Type.."|"..p.doctrineClass.."|"..tostring(p.range).."|"..tostring(p.canCapture).."\n")
	count = count + 1
end
assert(count > 200, "incomplete installed database fixture")
print("PASS installed database through deployed Lua: "..count.." units")
