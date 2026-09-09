-- Strategic Command 4.1: minimal live world used by the military executor.
-- It stores identities instead of native unit handles and is rebuilt after combat.

SC_EXECUTION_WORLD = SC_EXECUTION_WORLD or nil
SC_EXECUTION_WORLD_GENERATION = SC_EXECUTION_WORLD_GENERATION or 0

local function SCX_Safe(callback, fallback)
	local ok, value = pcall(callback)
	if ok and value ~= nil then return value end
	return fallback
end

local function SCX_Config(key, fallback)
	if SC_CONFIG ~= nil and SC_CONFIG[key] ~= nil then return SC_CONFIG[key] end
	return fallback
end

local function SCX_UnitInfo(unit)
	if unit == nil or GameInfo == nil or GameInfo.Units == nil then return nil end
	local unitType = SCX_Safe(function() return unit:GetUnitType() end, nil)
	return unitType ~= nil and GameInfo.Units[unitType] or nil
end

local function SCX_CellSize()
	return math.max(tonumber(SCX_Config("ExecutionWorldCellSize", 8)) or 8, 4)
end

local function SCX_CellCoordinate(value, size)
	return math.floor((tonumber(value) or 0) / size)
end

local function SCX_CellKey(x, y, size)
	return tostring(SCX_CellCoordinate(x, size))..":"..tostring(SCX_CellCoordinate(y, size))
end

local function SCX_AddBucket(buckets, record, size)
	local key = SCX_CellKey(record.x, record.y, size)
	local bucket = buckets[key]
	if bucket == nil then
		bucket = {}
		buckets[key] = bucket
	end
	table.insert(bucket, record)
end

function SCX_InvalidateExecutionWorld(reason)
	SC_EXECUTION_WORLD = nil
	SC_EXECUTION_WORLD_GENERATION = SC_EXECUTION_WORLD_GENERATION + 1
	if SC_Debug ~= nil then
		SC_Debug("executionWorld invalidate generation="..tostring(SC_EXECUTION_WORLD_GENERATION)..
			" reason="..tostring(reason or "unspecified"))
	end
end

function SCX_BuildExecutionWorld(player, reason)
	if player == nil then return nil end
	local playerID = SCX_Safe(function() return player:GetID() end, -1)
	local team = Teams ~= nil and Teams[SCX_Safe(function() return player:GetTeam() end, -1)] or nil
	if playerID < 0 or team == nil then return nil end
	local size = SCX_CellSize()
	local world = {
		playerID = playerID,
		turn = SCX_Safe(function() return Game.GetGameTurn() end, -1),
		generation = SC_EXECUTION_WORLD_GENERATION,
		cellSize = size,
		units = {}, cities = {}, unitBuckets = {}, cityBuckets = {},
	}
	for _, otherPlayer in pairs(Players) do
		if otherPlayer ~= nil and otherPlayer:IsAlive() and otherPlayer:GetID() ~= playerID
			and team:IsAtWar(otherPlayer:GetTeam()) then
			local ownerID = otherPlayer:GetID()
			for city in otherPlayer:Cities() do
				local plot = city ~= nil and city:Plot() or nil
				if plot ~= nil and (not SC5 or SC5.ObservedCity(player, city)) then
					local record = {
						ownerID = ownerID,
						cityID = SCX_Safe(function() return city:GetID() end, -1),
						x = plot:GetX(), y = plot:GetY(),
					}
					table.insert(world.cities, record)
					SCX_AddBucket(world.cityBuckets, record, size)
				end
			end
			for enemyUnit in otherPlayer:Units() do
				local plot = enemyUnit ~= nil and enemyUnit:GetPlot() or nil
				if plot ~= nil and (not SC5 or SC5.ObservedUnit(player, enemyUnit)) then
					local record = {
						ownerID = ownerID,
						unitID = SCX_Safe(function() return enemyUnit:GetID() end, -1),
						x = plot:GetX(), y = plot:GetY(),
					}
					table.insert(world.units, record)
					SCX_AddBucket(world.unitBuckets, record, size)
				end
			end
		end
	end
	SC_EXECUTION_WORLD = world
	if SC_Debug ~= nil then
		SC_Debug("executionWorld build turn="..tostring(world.turn)..
			" generation="..tostring(world.generation)..
			" reason="..tostring(reason or "request")..
			" units="..tostring(#world.units).." cities="..tostring(#world.cities)..
			" cellSize="..tostring(size))
	end
	return world
end

function SCX_GetExecutionWorld(player, reason)
	if player == nil then return nil end
	local playerID = SCX_Safe(function() return player:GetID() end, -1)
	local turn = SCX_Safe(function() return Game.GetGameTurn() end, -1)
	if SC_EXECUTION_WORLD == nil
		or SC_EXECUTION_WORLD.playerID ~= playerID
		or SC_EXECUTION_WORLD.turn ~= turn
		or SC_EXECUTION_WORLD.generation ~= SC_EXECUTION_WORLD_GENERATION then
		return SCX_BuildExecutionWorld(player, reason)
	end
	return SC_EXECUTION_WORLD
end

local function SCX_ResolveUnit(record)
	if record == nil then return nil end
	if SC_ResolveLiveUnit ~= nil then
		return SC_ResolveLiveUnit(record.ownerID, record.unitID)
	end
	local owner = Players ~= nil and Players[record.ownerID] or nil
	return owner ~= nil and SCX_Safe(function() return owner:GetUnitByID(record.unitID) end, nil) or nil
end

local function SCX_ResolveCity(record)
	if record == nil then return nil end
	local owner = Players ~= nil and Players[record.ownerID] or nil
	return owner ~= nil and SCX_Safe(function() return owner:GetCityByID(record.cityID) end, nil) or nil
end

local function SCX_AppendLocalRecords(world, records, buckets, unitPlot, radius, resolver, validator, output)
	local size = world.cellSize
	local mapWidth = SCX_Safe(function()
		local width = Map.GetGridSize()
		return width
	end, 0)
	if radius >= size * 6
		or (mapWidth > 0 and (unitPlot:GetX() - radius < 0 or unitPlot:GetX() + radius >= mapWidth)) then
		for _, record in ipairs(records) do
			local distance = Map.PlotDistance(unitPlot:GetX(), unitPlot:GetY(), record.x, record.y)
			if distance <= radius then
				local value = resolver(record)
				if value ~= nil and validator(value) then table.insert(output, value) end
			end
		end
		return
	end
	local minX = SCX_CellCoordinate(unitPlot:GetX() - radius, size)
	local maxX = SCX_CellCoordinate(unitPlot:GetX() + radius, size)
	local minY = SCX_CellCoordinate(unitPlot:GetY() - radius, size)
	local maxY = SCX_CellCoordinate(unitPlot:GetY() + radius, size)
	for cellX = minX, maxX, 1 do
		for cellY = minY, maxY, 1 do
			local bucket = buckets[tostring(cellX)..":"..tostring(cellY)] or {}
			for _, record in ipairs(bucket) do
				local distance = Map.PlotDistance(unitPlot:GetX(), unitPlot:GetY(), record.x, record.y)
				if distance <= radius then
					local value = resolver(record)
					if value ~= nil and validator(value) then table.insert(output, value) end
				end
			end
		end
	end
end

local function SCX_GetPurposeRadius(unit, purpose)
	local info = SCX_UnitInfo(unit)
	local profile = SC_GetUnitCapabilityProfile ~= nil and SC_GetUnitCapabilityProfile(unit, info) or nil
	local range = math.max(tonumber(profile and profile.range) or 0,
		SCX_Safe(function() return unit:Range() end, 0), 1)
	if purpose == "fire" or purpose == "air-sweep" then return range end
	if purpose == "capture" then return SCX_Config("CityCaptureAssignmentSeaDistance", 12) end
	if info ~= nil and info.Domain == "DOMAIN_SEA" then
		return SCX_Config("StrategicUnitPursuitSeaDistance", 14)
	end
	return SCX_Config("StrategicUnitPursuitLandDistance", 10)
end

function SCX_GetExecutionTargetPool(player, unit, purpose, fallbackPool)
	local world = SCX_GetExecutionWorld(player, purpose)
	local unitPlot = unit ~= nil and unit:GetPlot() or nil
	if world == nil or unitPlot == nil then return fallbackPool or { units = {}, cities = {} }, "fallback" end
	local pool = { units = {}, cities = {} }
	local radius = math.max(SCX_GetPurposeRadius(unit, purpose), 1)
	SCX_AppendLocalRecords(world, world.units, world.unitBuckets, unitPlot, radius, SCX_ResolveUnit,
		function(value) return SC_IsEnemyTargetUnitValid(player, value) end, pool.units)
	if purpose == "strategic" then
		-- Every unit receives a bounded nearest-city fallback. The strategic
		-- operation focus is appended as advice when it lies outside that set.
		local info = SCX_UnitInfo(unit)
		local candidates = {}
		for _, record in ipairs(world.cities) do
			local city = SCX_ResolveCity(record)
			local plot = city ~= nil and city:Plot() or nil
			local domainAllowed = info == nil or info.Domain ~= "DOMAIN_SEA"
				or (plot ~= nil and SC_IsCoastalAssaultPlot ~= nil and SC_IsCoastalAssaultPlot(plot))
			if plot ~= nil and domainAllowed and SC_IsEnemyTargetCityValid(player, city) then
				table.insert(candidates, {
					city = city,
					distance = Map.PlotDistance(unitPlot:GetX(), unitPlot:GetY(), plot:GetX(), plot:GetY())
				})
			end
		end
		table.sort(candidates, function(a, b) return a.distance < b.distance end)
		local cityLimit = math.max(1, tonumber(SCX_Config("ExecutionStrategicCityLimit", 10)) or 10)
		local included = {}
		for index = 1, math.min(#candidates, cityLimit), 1 do
			local city = candidates[index].city
			local plot = city:Plot()
			local key = tostring(plot:GetX())..":"..tostring(plot:GetY())
			included[key] = true
			table.insert(pool.cities, city)
		end
		if SC_GetOperationFocusPlot ~= nil then
			local focusPlot = SCX_Safe(function() return SC_GetOperationFocusPlot(player, unit) end, nil)
			if focusPlot ~= nil then
				local focusKey = tostring(focusPlot:GetX())..":"..tostring(focusPlot:GetY())
				if not included[focusKey] then
					for _, candidate in ipairs(candidates) do
						local plot = candidate.city:Plot()
						if plot:GetX() == focusPlot:GetX() and plot:GetY() == focusPlot:GetY() then
							table.insert(pool.cities, candidate.city)
							break
						end
					end
				end
			end
		end
	else
		SCX_AppendLocalRecords(world, world.cities, world.cityBuckets, unitPlot, radius, SCX_ResolveCity,
			function(value) return SC_IsEnemyTargetCityValid(player, value) end, pool.cities)
	end
	return pool, "execution:"..tostring(purpose)..":radius="..tostring(radius)..
		":units="..tostring(#pool.units)..":cities="..tostring(#pool.cities)
end
