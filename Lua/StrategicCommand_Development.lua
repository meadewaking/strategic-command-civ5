-- City-specific marginal yields and affordable national priorities.
SC5.buildingData = SC5.buildingData or {}
SC5.cityEconomy = SC5.cityEconomy or {}
local yieldNames = {
	YIELD_FOOD = "food", YIELD_PRODUCTION = "production", YIELD_GOLD = "gold",
	YIELD_SCIENCE = "science", YIELD_CULTURE = "culture", YIELD_FAITH = "faith",
}

function SC5.Rows(name, filter)
	if not GameInfo or not GameInfo[name] then return function() return nil end end
	local ok, iterator = pcall(function() return GameInfo[name](filter) end)
	return ok and iterator or function() return nil end
end

function SC5.BuildingData(buildingType)
	if SC5.buildingData[buildingType] then return SC5.buildingData[buildingType] end
	local data = { flat = {}, modifier = {}, perPop = {}, conditional = {} }
	local tables = {
		Building_YieldChanges = "flat", Building_YieldModifiers = "modifier",
		Building_YieldChangesPerPop = "perPop",
		Building_ResourceYieldChanges = "resource", Building_TerrainYieldChanges = "terrain",
		Building_FeatureYieldChanges = "feature", Building_SpecialistYieldChanges = "specialist",
	}
	for name, kind in pairs(tables) do
		for row in SC5.Rows(name, { BuildingType = buildingType }) do
			local yield = yieldNames[row.YieldType]
			if yield then
				local amount = tonumber(row.Yield) or 0
				if data[kind] then data[kind][yield] = (data[kind][yield] or 0) + amount
				else data.conditional[#data.conditional + 1] = {
					yield = yield, amount = amount, kind = kind,
					type = row.ResourceType or row.TerrainType or row.FeatureType or row.SpecialistType,
				} end
			end
		end
	end
	SC5.buildingData[buildingType] = data
	return data
end

function SC5.CityEconomy(player, city)
	local turn = Game.GetGameTurn()
	local key = player:GetID()..":"..city:GetID()
	local cached = SC5.cityEconomy[key]
	if cached and cached.turn == turn then return cached end
	local c = { turn = turn, yields = {}, baseYields = {}, sources = { resource = {}, terrain = {}, feature = {}, specialist = {} } }
	for id, name in pairs(yieldNames) do
		c.yields[name] = SC5.Safe(function() return city:GetYieldRate(YieldTypes[id]) end, 0)
		c.baseYields[name] = SC5.Safe(function() return city:GetBaseYieldRate(YieldTypes[id]) end, c.yields[name])
	end
	local function add(kind, tableName, id, weight)
		local row = id and id >= 0 and GameInfo[tableName] and GameInfo[tableName][id]
		if row then c.sources[kind][row.Type] = (c.sources[kind][row.Type] or 0) + weight end
	end
	local count = SC5.Safe(function() return city:GetNumCityPlots() end, 0)
	for i = 0, count - 1 do
		local plot = SC5.Safe(function() return city:GetCityIndexPlot(i) end, nil)
		if plot and plot:GetOwner() == player:GetID() then
			local working = SC5.Safe(function() return city:IsWorkingPlot(plot) end, false)
			-- Only current worked tiles contribute; do not invent yields for every
			-- resource/specialist type defined in the database.
			if working then
				add("resource", "Resources", SC5.Safe(function() return plot:GetResourceType(player:GetTeam()) end, -1), 1)
				add("terrain", "Terrains", plot:GetTerrainType(), 1)
				add("feature", "Features", plot:GetFeatureType(), 1)
			end
		end
	end
	for specialist in SC5.Rows("Specialists") do
		c.sources.specialist[specialist.Type] = SC5.Safe(function() return city:GetSpecialistCount(specialist.ID) end, 0)
	end
	SC5.cityEconomy[key] = c
	return c
end

function SC5.ScoreBuilding(player, city, building, purchased)
	local data = SC5.BuildingData(building.Type)
	local economy = SC5.CityEconomy(player, city)
	local state = SC_STRATEGY_STATE or {}
	local world = state.world or {}
	local national = state.national or {}
	local weights = { food = 20, production = 30, gold = 16, science = 25, culture = 12, faith = 8 }
	for name, priority in pairs(national.priorities or {}) do
		if weights[name] then weights[name] = weights[name] * priority end
	end
	if (world.happiness or 0) < 0 then weights.food = 2 end
	local role = SC_StrategyGetCityRole(city)
	local roleYield = { industrial = "production", science = "science", finance = "gold", growth = "food" }
	if roleYield[role] then weights[roleYield[role]] = weights[roleYield[role]] * 1.25 end
	local yields = {}
	for _, name in pairs(yieldNames) do
		yields[name] = (data.flat[name] or 0) + (data.perPop[name] or 0) * city:GetPopulation() / 100
			+ (data.modifier[name] or 0) * (economy.baseYields[name] or 0) / 100
	end
	for _, row in ipairs(data.conditional) do
		yields[row.yield] = yields[row.yield] + row.amount * (economy.sources[row.kind][row.type] or 0)
	end
	local utility = ((tonumber(building.Happiness) or 0) + (tonumber(building.UnmoddedHappiness) or 0))
		* ((world.happiness or 0) < 5 and 180 or 40)
	if SC5.Safe(function() return city:IsOccupied() end, false)
		and (building.NoOccupiedUnhappiness == true or tonumber(building.NoOccupiedUnhappiness) == 1) then utility = utility + 3200 end
	if building.Airlift == true or tonumber(building.Airlift) == 1 then utility = utility + (world.atWar and 800 or 160) end
	utility = utility + (tonumber(building.NumTradeRouteBonus) or 0) * 240
		+ (tonumber(building.MilitaryProductionModifier) or 0) * (world.atWar and 5 or 1)
		+ (tonumber(building.Experience) or 0) * ((role == "naval_base" or role == "industrial") and 4 or 1)
	if role == "frontier" then utility = utility + (tonumber(building.Defense) or 0) / 12 end
	for row in SC5.Rows("Building_ResourceQuantity", { BuildingType = building.Type }) do
		local resource = GameInfo.Resources[row.ResourceType]
		local available = resource and SC5.Safe(function() return player:GetNumResourceAvailable(resource.ID, true) end, 0) or 0
		utility = utility + (tonumber(row.Quantity) or 0) * (available <= 2 and 160 or 20)
	end
	local turns = SC5.Safe(function() return city:GetBuildingProductionTurnsLeft(building.ID, 0) end, nil)
	if not turns or turns < 0 or turns > 999 then
		turns = math.max(tonumber(building.Cost) or 0, 0) / math.max(economy.yields.production or 0, 1)
	end
	if purchased then turns = 0 end
	local score, reason = SC5.BuildingScore({ yields = yields, weights = weights, turns = turns,
		utility = utility, maintenance = tonumber(building.GoldMaintenance) or 0, atWar = world.atWar })
	return score, "role="..role..",purchased="..tostring(purchased == true)..","..reason
end

function SC5.PolicyYieldValue(player, policy)
	local state = SC_STRATEGY_STATE or {}
	local cities = state.world and state.world.ownCities or {}
	local weights = { food = 16, production = 25, gold = 15, science = 25, culture = 14, faith = 8 }
	local score = 0
	for row in SC5.Rows("Policy_BuildingClassYieldChanges", { PolicyType = policy.Type }) do
		for _, entry in ipairs(cities) do
			local count = 0
			for building in SC5.Rows("Buildings", { BuildingClass = row.BuildingClassType }) do
				count = count + entry.city:GetNumRealBuilding(building.ID)
			end
			score = score + count * (tonumber(row.YieldChange) or 0) * (weights[yieldNames[row.YieldType]] or 0)
		end
	end
	for row in SC5.Rows("Policy_CityYieldChanges", { PolicyType = policy.Type }) do
		score = score + #cities * (tonumber(row.Yield) or 0) * (weights[yieldNames[row.YieldType]] or 0)
	end
	return score
end

function SC5.CivilizationUnlock(player, row, kind)
	if not player then return false end
	local civilization = GameInfo.Civilizations[player:GetCivilizationType()]
	if not civilization then return false end
	local units = kind == "unit"
	local class = units and row.Class or row.BuildingClass
	local classes = units and GameInfo.UnitClasses or GameInfo.BuildingClasses
	local classInfo = classes and classes[class]
	if not classInfo then return true end
	local allowed = units and classInfo.DefaultUnit or classInfo.DefaultBuilding
	local name = units and "Civilization_UnitClassOverrides" or "Civilization_BuildingClassOverrides"
	for override in SC5.Rows(name, { CivilizationType = civilization.Type }) do
		local overrideClass = units and override.UnitClassType or override.BuildingClassType
		if overrideClass == class then
			allowed = units and override.UnitType or override.BuildingType
			break
		end
	end
	return allowed == row.Type
end

function SC5.CityInImmediateDanger(city)
	local world = SC_STRATEGY_STATE and SC_STRATEGY_STATE.world
	for _, entry in ipairs(world and world.ownCities or {}) do
		if entry.city:GetID() == city:GetID() then
			return (entry.enemyCount or 0) > 0 and (entry.enemyPower or 0) > (entry.friendlyPower or 0) * 1.2
		end
	end
	return false
end

function SC5.ElitePlanValue(player, city, info, reservations, project)
	local state = SC_STRATEGY_STATE or {}
	local world, plan = state.world, state.plan
	if not world or not plan then return 1, "no-plan" end
	local need = SC_GetProductionNeedForUnitInfo(info)
	if not need then return nil, "no-military-role" end
	world.bestRolePower = world.bestRolePower or {}
	if world.bestRolePower[need] == nil then
		local best = 0
		for _, entry in ipairs(world.ownUnits or {}) do
			if entry.need == need and entry.profile then best = math.max(best, entry.profile.power or 0) end
		end
		world.bestRolePower[need] = best
	end
	return SC5.EliteInvestment({ target = (plan.forceTargets or {})[need] or 0,
		current = (world.counts or {})[need] or 0,
		queued = reservations and reservations["NEED:"..need] or 0,
		power = math.max(tonumber(info.Combat) or 0, tonumber(info.RangedCombat) or 0),
		bestPower = world.bestRolePower[need], project = project,
		danger = SC5.CityInImmediateDanger(city), crisis = state.national and state.national.crisis,
	})
end

function SC5.NeedsEconomicRelief(player, city)
	local national = SC_STRATEGY_STATE and SC_STRATEGY_STATE.national
	local crisis = national and national.crisis
	return not SC5.CityInImmediateDanger(city) and (crisis == "deficit" or crisis == "happiness"
		or SC5.Safe(function() return city:IsOccupied() end, false))
end

function SC5.IsEconomicRelief(player, city, building)
	local national = SC_STRATEGY_STATE and SC_STRATEGY_STATE.national
	local crisis = national and national.crisis
	if SC5.Safe(function() return city:IsOccupied() end, false)
		and (building.NoOccupiedUnhappiness == true or tonumber(building.NoOccupiedUnhappiness) == 1) then return true end
	if crisis == "happiness" then
		return (tonumber(building.Happiness) or 0) + (tonumber(building.UnmoddedHappiness) or 0) > 0
	end
	if crisis == "deficit" then
		local data, economy = SC5.BuildingData(building.Type), SC5.CityEconomy(player, city)
		local gold = (data.flat.gold or 0) + (data.modifier.gold or 0) * economy.baseYields.gold / 100
			+ (data.perPop.gold or 0) * city:GetPopulation() / 100 - (tonumber(building.GoldMaintenance) or 0)
		for _, row in ipairs(data.conditional) do
			if row.yield == "gold" then gold = gold + row.amount * (economy.sources[row.kind][row.type] or 0) end
		end
		return gold > 0
	end
	return false
end
