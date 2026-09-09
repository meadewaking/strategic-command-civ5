-- Strategic Command V3: city production transaction reconciliation.

local function SCV3_CitySafeNumber(callback, fallback)
	local ok, value = pcall(callback)
	if ok and tonumber(value) ~= nil then
		return tonumber(value)
	end
	return fallback
end

local function SCV3_CitySafeText(callback, fallback)
	local ok, value = pcall(callback)
	if ok and value ~= nil then
		return tostring(value)
	end
	return fallback
end

local function SCV3_CitySnapshot(player)
	local snapshot = {}
	if player == nil or player.Cities == nil then
		return snapshot
	end
	for city in player:Cities() do
		if city ~= nil then
			local id = SCV3_CitySafeNumber(function() return city:GetID() end, -1)
			local queue = SCV3_CitySafeNumber(function() return city:GetOrderQueueLength() end, 0)
			local unit = SCV3_CitySafeNumber(function() return city:GetProductionUnit() end, -1)
			local building = SCV3_CitySafeNumber(function() return city:GetProductionBuilding() end, -1)
			local project = SCV3_CitySafeNumber(function() return city:GetProductionProject() end, -1)
			local process = SCV3_CitySafeNumber(function() return city:GetProductionProcess() end, -1)
			local name = SCV3_CitySafeText(function() return city:GetName() end, "CITY")
			local signature = table.concat({queue, unit, building, project, process}, ":")
			snapshot[tostring(id)] = {
				id = id, name = name, queue = queue, signature = signature
			}
		end
	end
	return snapshot
end

local function SCV3_CityReconcile(before, adapters, reason)
	local confirmed = 0
	local expired = 0
	local waiting = 0
	for key, transaction in pairs(SCV3.transactions) do
		if string.sub(key, 1, 5) == "city:" then
			local cityKey = string.sub(key, 6)
			local current = before[cityKey]
			if current == nil then
				SCV3_ClearTransaction(key)
				expired = expired + 1
			elseif current.signature ~= transaction.signature then
				SCV3_ClearTransaction(key)
				confirmed = confirmed + 1
				adapters.log("V3 cityTxn confirmed city="..tostring(current.name)..
					" from="..tostring(transaction.signature).." to="..tostring(current.signature)..
					" reason="..tostring(reason))
			else
				transaction.polls = (transaction.polls or 0) + 1
				if transaction.polls >= 2 then
					SCV3_ClearTransaction(key)
					expired = expired + 1
					adapters.log("V3 cityTxn retry city="..tostring(current.name)..
						" signature="..tostring(current.signature).." polls="..tostring(transaction.polls)..
						" reason="..tostring(reason))
				else
					waiting = waiting + 1
				end
			end
		end
	end
	return confirmed, expired, waiting
end

function SCV3_RunCityProduction(player, atWar, adapters, reason)
	reason = reason or "scheduled"
	local before = SCV3_CitySnapshot(player)
	local confirmed, expired, waiting = SCV3_CityReconcile(before, adapters, reason)
	if waiting > 0 then
		adapters.log("V3 cityTxn await reason="..tostring(reason).." pending="..tostring(waiting)..
			" confirmed="..tostring(confirmed).." expired="..tostring(expired))
		return 1, nil, 0
	end
	local count, details, errors = SCV3_RunModule(adapters, "city.production", function()
		return adapters.automateCities(player, atWar)
	end)
	local after = SCV3_CitySnapshot(player)
	local changed = 0
	local pending = 0
	for key, oldCity in pairs(before) do
		local newCity = after[key]
		if newCity ~= nil and newCity.signature ~= oldCity.signature then
			changed = changed + 1
			SCV3_ClearTransaction("city:"..key)
		elseif newCity ~= nil and oldCity.queue <= 0 and count > 0 then
			-- Civ V may apply a pushed order after the Lua callback returns.  This
			-- transaction is deliberately short lived and never locks a whole turn.
			SCV3_SetTransaction("city:"..key, {
				signature = oldCity.signature, polls = 0, submittedPass = SCV3.passSequence
			})
			pending = pending + 1
		end
	end
	adapters.log("V3 cityTxn summary reason="..tostring(reason).." submitted="..tostring(count)..
		" changed="..tostring(changed).." confirmed="..tostring(confirmed)..
		" expired="..tostring(expired).." pending="..tostring(pending).." errors="..tostring(errors))
	return count, details, errors
end
