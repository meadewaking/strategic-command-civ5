-- Shared national strategy, world model, operations, and utility scoring.
-- This module is loaded after the compatibility command layer has been defined.

SC_STRATEGY_VERSION = "5.1"
SC_STRATEGY_STATE = SC_STRATEGY_STATE or {
	turn = -1,
	playerID = -1,
	world = nil,
	plan = nil,
	assignments = {},
	cityRoles = {},
	targetHistory = {},
	unlockCache = nil,
	buildingYieldCache = {},
	researchCandidates = {},
	policyCandidates = {},
	powerHistory = nil,
	forceHistory = {},
	unitTasks = {},
	previousPlan = nil,
	national = nil,
	processCities = {},
	taskMetrics = {}
}
SC_STRATEGY_STATE.lossesByTurn = SC_STRATEGY_STATE.lossesByTurn or {}
SC_STRATEGY_STATE.lossKeys = SC_STRATEGY_STATE.lossKeys or {}

local SC_STRATEGY_COMBAT_CLASSES = {
	air_defense_screen = true, air_superiority = true, airborne_raider = true,
	arsenal_capital = true, attack_submarine = true, ballistic_submarine = true,
	carrier_multirole = true, counter_defender = true, escort_screen = true,
	fleet_carrier = true, gunship = true, line_assault = true, line_defender = true,
	missile_strike = true, mobile_air_defense = true, mobile_breakthrough = true,
	naval_assault = true, ranged_support = true, recon_raider = true,
	siege_artillery = true, static_fortress = true, strategic_nuclear = true,
	strike_aircraft = true, super_heavy = true, surface_fire_support = true
}

local SC_STRATEGY_HIGH_VALUE_CLASSES = {
	arsenal_capital = true, ballistic_submarine = true, fleet_carrier = true,
	super_heavy = true, strike_aircraft = true, carrier_multirole = true
}

local function SC_StrategyConfig(key, defaultValue)
	if SC_CONFIG ~= nil and SC_CONFIG[key] ~= nil then
		return SC_CONFIG[key]
	end
	return defaultValue
end

local function SC_StrategySafe(callback, defaultValue)
	local ok, value = pcall(callback)
	if ok and value ~= nil then return value end
	return defaultValue
end

function SC_StrategyRecordUnitLoss(ownerID, unitID, unitType)
	local playerID = tonumber(ownerID) or -1
	if playerID < 0 or (SC_STRATEGY_STATE.playerID or -1) ~= playerID then return false end
	local turn = SC_StrategySafe(function() return Game.GetGameTurn() end, -1)
	local key = tostring(turn)..":"..tostring(playerID)..":"..tostring(unitID)
	if SC_STRATEGY_STATE.lossKeys[key] then return false end
	SC_STRATEGY_STATE.lossKeys[key] = true
	local entry = SC_STRATEGY_STATE.lossesByTurn[turn] or { count = 0, types = {} }
	entry.count = entry.count + 1
	local typeKey = tostring(unitType or "unknown")
	entry.types[typeKey] = (entry.types[typeKey] or 0) + 1
	SC_STRATEGY_STATE.lossesByTurn[turn] = entry
	for oldTurn in pairs(SC_STRATEGY_STATE.lossesByTurn) do
		if tonumber(oldTurn) ~= nil and oldTurn < turn - 8 then SC_STRATEGY_STATE.lossesByTurn[oldTurn] = nil end
	end
	return true
end

local function SC_StrategyInfo(tableName, id)
	if GameInfo == nil or GameInfo[tableName] == nil then return nil end
	return GameInfo[tableName][id]
end

local function SC_StrategyUnitInfo(unit)
	if unit == nil then return nil end
	return SC_StrategyInfo("Units", SC_StrategySafe(function() return unit:GetUnitType() end, -1))
end

local function SC_StrategyDistance(a, b)
	if a == nil or b == nil or Map == nil then return 999 end
	return SC_StrategySafe(function()
		return Map.PlotDistance(a:GetX(), a:GetY(), b:GetX(), b:GetY())
	end, 999)
end

local function SC_StrategyPlotKey(plot)
	if plot == nil then return "nil" end
	return tostring(SC_StrategySafe(function() return plot:GetX() end, -1))..":"..
		tostring(SC_StrategySafe(function() return plot:GetY() end, -1))
end

local function SC_StrategyUnitKey(unit)
	if unit == nil then return nil end
	return tostring(SC_StrategySafe(function() return unit:GetOwner() end, -1))..":"..
		tostring(SC_StrategySafe(function() return unit:GetID() end, -1))
end

local function SC_StrategyAtWar(player, otherPlayer)
	if player == nil or otherPlayer == nil or Teams == nil then return false end
	local team = Teams[SC_StrategySafe(function() return player:GetTeam() end, -1)]
	return team ~= nil and SC_StrategySafe(function() return team:IsAtWar(otherPlayer:GetTeam()) end, false)
end

local function SC_StrategyUnitNeed(unitInfo)
	if unitInfo == nil or SC_GetProductionNeedForUnitInfo == nil then return nil end
	return SC_GetProductionNeedForUnitInfo(unitInfo)
end

local function SC_StrategyUnitCapabilities(unitInfo, profile, primaryNeed)
	local capabilities = {}
	local function supply(need, value)
		capabilities[need] = math.max(capabilities[need] or 0, value or 0)
	end
	if primaryNeed ~= nil then supply(primaryNeed, 1) end
	if unitInfo == nil or profile == nil then return capabilities end
	local class = profile.doctrineClass or ""
	if profile.canCapture then
		supply("line_frontline", 1)
		local moves = tonumber(unitInfo.Moves) or 0
		if moves >= 4 or unitInfo.Domain == "DOMAIN_SEA" or class == "airborne_raider" then supply("rapid_capture", 1) end
	end
	if class == "carrier_multirole" then
		supply("carrier_air", 1); supply("air_superiority", 0.75); supply("air_strike", 0.65)
	elseif class == "air_superiority" then
		supply("air_superiority", 1); supply("air_strike", 0.20)
	elseif class == "strike_aircraft" then supply("air_strike", 1)
	elseif class == "siege_artillery" or class == "ranged_support" then supply("siege", 1)
	elseif class == "surface_fire_support" or class == "arsenal_capital" then supply("naval_fire", 1)
	elseif class == "fleet_carrier" then supply("fleet_carrier", 1)
	elseif class == "ballistic_submarine" then supply("strategic_submarine", 1); supply("naval_screen", 0.35)
	elseif class == "attack_submarine" or class == "escort_screen" or class == "naval_assault" or class == "air_defense_screen" then supply("naval_screen", 1)
	elseif class == "missile_strike" or class == "strategic_nuclear" then supply("missile_strike", 1) end
	-- Database classes describe the primary role. Preserve secondary weapons so
	-- multi-role late-game ships can fill a fire-support slot as well as screen.
	local ranged = tonumber(unitInfo.RangedCombat) or 0
	local range = tonumber(unitInfo.Range) or 0
	if unitInfo.Domain == "DOMAIN_SEA" and ranged > 0 and range >= 2 then
		supply("naval_fire", range >= 4 and 1 or 0.65)
	end
	if class == "ballistic_submarine" then supply("missile_strike", 0.50) end
	return capabilities
end

local function SC_StrategyGetYield(city, yieldName)
	if city == nil or YieldTypes == nil or YieldTypes[yieldName] == nil then return 0 end
	return SC_StrategySafe(function() return city:GetYieldRate(YieldTypes[yieldName]) end, 0)
end

local function SC_StrategyNearestDistance(plot, entries)
	local best = 999
	for _, entry in ipairs(entries or {}) do
		local otherPlot = entry.plot or entry
		local distance = SC_StrategyDistance(plot, otherPlot)
		if distance < best then best = distance end
	end
	return best
end

local function SC_StrategyCityMetrics(city, world)
	local key = tostring(SC_StrategySafe(function() return city:GetID() end, -1))
	local plot = SC_StrategySafe(function() return city:Plot() end, nil)
	local population = SC_StrategySafe(function() return city:GetPopulation() end, 1)
	local production = SC_StrategyGetYield(city, "YIELD_PRODUCTION")
	local science = SC_StrategyGetYield(city, "YIELD_SCIENCE")
	local gold = SC_StrategyGetYield(city, "YIELD_GOLD")
	local coastal = SC_StrategySafe(function() return city:IsCoastal() end, false)
	local capital = SC_StrategySafe(function() return city:IsCapital() end, false)
	local frontDistance = SC_StrategyNearestDistance(plot, world.enemyCities)
	return {
		key = key, city = city, plot = plot, population = population,
		production = production, science = science, gold = gold,
		coastal = coastal, capital = capital, frontDistance = frontDistance
	}
end

local function SC_StrategyAssignCityRoles(world)
	local metrics = {}
	for _, entry in ipairs(world.ownCities) do
		local value = SC_StrategyCityMetrics(entry.city, world)
		entry.metrics = value
		table.insert(metrics, value)
	end
	local quotas = {
		frontier = world.atWar and math.max(1, math.ceil(#metrics * 0.20)) or 0,
		naval_base = math.max(1, math.ceil(#metrics * 0.12)),
		industrial = math.max(1, math.ceil(#metrics * 0.18)),
		science = math.max(1, math.ceil(#metrics * 0.18)),
		finance = math.max(1, math.ceil(#metrics * 0.12))
	}
	local assigned = {}
	local function assignRanked(role, filter, score)
		local candidates = {}
		for _, value in ipairs(metrics) do
			if not assigned[value.key] and not value.capital and filter(value) then
				table.insert(candidates, { value = value, score = score(value) })
			end
		end
		table.sort(candidates, function(a, b) return a.score > b.score end)
		for i = 1, math.min(#candidates, quotas[role] or 0), 1 do
			assigned[candidates[i].value.key] = role
		end
	end
	for _, value in ipairs(metrics) do if value.capital then assigned[value.key] = "capital" end end
	assignRanked("frontier", function(value) return value.frontDistance <= 12 end,
		function(value) return 500 - value.frontDistance * 30 + value.population * 4 end)
	assignRanked("naval_base", function(value) return value.coastal end,
		function(value) return value.production * 5 + value.population * 2 end)
	assignRanked("industrial", function() return true end,
		function(value) return value.production * 6 + value.population end)
	assignRanked("science", function() return true end,
		function(value) return value.science * 6 + value.population * 2 end)
	assignRanked("finance", function() return true end,
		function(value) return value.gold * 6 + value.population end)
	for _, entry in ipairs(world.ownCities) do
		local value = entry.metrics
		local role = assigned[value.key]
		if role == nil then role = value.population <= 7 and "growth" or "balanced" end
		local existing = SC_STRATEGY_STATE.cityRoles[value.key]
		if existing ~= nil and world.turn - (existing.turn or world.turn) < 4
			and existing.role ~= "frontier" and role ~= "frontier" then
			role = existing.role
		end
		entry.role = role
		SC_STRATEGY_STATE.cityRoles[value.key] = { role = role, turn = world.turn }
	end
end

local function SC_StrategyHealthFactor(unit)
	local damage = SC_StrategySafe(function() return unit:GetDamage() end, 0)
	return math.max(0.18, 1 - math.max(0, damage) / 100)
end

local function SC_StrategyEffectivePower(profile, unit)
	if profile == nil or not SC_STRATEGY_COMBAT_CLASSES[profile.doctrineClass or ""] then return 0 end
	local raw = math.max(tonumber(profile.power) or 0, 0)
	if raw <= 0 then return 0 end
	local class = profile.doctrineClass
	local multiplier = 1
	if class == "missile_strike" or class == "strategic_nuclear" then multiplier = 0.28
	elseif class == "fleet_carrier" then multiplier = 0.72
	elseif class == "air_superiority" or class == "carrier_multirole" then multiplier = 1.18
	elseif class == "siege_artillery" or class == "surface_fire_support" then multiplier = 1.12
	elseif class == "super_heavy" then multiplier = 1.35 end
	if SC5 and SC5.Safe(function() return unit:IsEmbarked() end, false) then multiplier = multiplier * 0.12 end
	return (raw ^ 1.24) * multiplier * SC_StrategyHealthFactor(unit)
end

local function SC_StrategyEnemyProfile(unit, info)
	if info == nil then return nil end
	return SC_GetUnitCapabilityProfile ~= nil and SC_GetUnitCapabilityProfile(unit, info) or {
		doctrineClass = "line_assault",
		power = math.max(tonumber(info.Combat) or 0, tonumber(info.RangedCombat) or 0),
		domain = info.Domain,
		canCapture = info.Domain ~= "DOMAIN_AIR"
	}
end

local function SC_StrategyPowerNear(entries, plot, radius, domain)
	local power, count = 0, 0
	for _, entry in ipairs(entries or {}) do
		if entry.plot ~= nil and (domain == nil or domain == "joint" or entry.domain == domain)
			and SC_StrategyDistance(entry.plot, plot) <= radius then
		power = power + (entry.effectivePower or 0)
		if (entry.effectivePower or 0) > 0 then count = count + 1 end
		end
	end
	return power, count
end

local function SC_StrategyCountNeedNear(entries, plot, radius, need)
	local count = 0
	for _, entry in ipairs(entries or {}) do
		local supply = entry.capabilities and entry.capabilities[need] or 0
		if entry.plot ~= nil and supply > 0 and SC_StrategyDistance(entry.plot, plot) <= radius then
			count = count + supply
		end
	end
	return count
end

local function SC_StrategyCountCaptureNear(entries, plot, radius)
	local count = 0
	for _, entry in ipairs(entries or {}) do
		if entry.plot ~= nil and entry.profile ~= nil and entry.profile.canCapture
			and SC_StrategyDistance(entry.plot, plot) <= radius then count = count + 1 end
	end
	return count
end

function SC_StrategyBuildWorld(player, atWar, force)
	if player == nil then return nil end
	local turn = SC_StrategySafe(function() return Game.GetGameTurn() end, -1)
	local playerID = SC_StrategySafe(function() return player:GetID() end, -1)
	if not force and SC_STRATEGY_STATE.world ~= nil and SC_STRATEGY_STATE.turn == turn
		and SC_STRATEGY_STATE.playerID == playerID then
		return SC_STRATEGY_STATE.world
	end
	local world = {
		turn = turn,
		playerID = playerID,
		atWar = atWar == true,
		ownCities = {}, enemyCities = {}, ownUnits = {}, enemyUnits = {},
		counts = {}, classCounts = {}, combatUnits = 0, enemyCombatUnits = 0,
		combatPower = 0, enemyCombatPower = 0, frontierEnemyPower = 0,
		gold = SC_StrategySafe(function() return player:GetGold() end, 0),
		goldRate = SC_StrategySafe(function() return player:CalculateGoldRate() end, 0),
		happiness = SC_StrategySafe(function() return player:GetExcessHappiness() end, 0),
		unitCost = SC_StrategySafe(function() return player:CalculateUnitCost() end, 0),
		scienceRate = SC_StrategySafe(function() return player:GetScience() end, 0),
		culture = SC_StrategySafe(function() return player:GetJONSCulture() end, 0)
	}
	for city in player:Cities() do
		local plot = SC_StrategySafe(function() return city:Plot() end, nil)
		if plot ~= nil then
			table.insert(world.ownCities, { city = city, plot = plot })
		end
	end
	for unit in player:Units() do
		if unit ~= nil and not SC_StrategySafe(function() return unit:IsDead() end, true) then
			local info = SC_StrategyUnitInfo(unit)
			local profile = info ~= nil and SC_GetUnitCapabilityProfile(unit, info) or nil
			local need = SC_StrategyUnitNeed(info)
			local capabilities = SC_StrategyUnitCapabilities(info, profile, need)
			for capability, supply in pairs(capabilities) do world.counts[capability] = (world.counts[capability] or 0) + supply end
			local doctrineClass = profile ~= nil and profile.doctrineClass or "unknown"
			world.classCounts[doctrineClass] = (world.classCounts[doctrineClass] or 0) + 1
			local effectivePower = SC_StrategyEffectivePower(profile, unit)
			if effectivePower > 0 then
				world.combatUnits = world.combatUnits + 1
				world.combatPower = world.combatPower + effectivePower
			end
			table.insert(world.ownUnits, {
				unit = unit, info = info, profile = profile, need = need, capabilities = capabilities,
				plot = SC_StrategySafe(function() return unit:GetPlot() end, nil),
				domain = info and info.Domain or "", effectivePower = effectivePower
			})
		end
	end
	for _, otherPlayer in pairs(Players or {}) do
		if otherPlayer ~= nil and otherPlayer ~= player and SC_StrategySafe(function() return otherPlayer:IsAlive() end, false)
			and SC_StrategyAtWar(player, otherPlayer) then
			for city in otherPlayer:Cities() do
				local plot = SC_StrategySafe(function() return city:Plot() end, nil)
				if plot ~= nil and (not SC5 or SC5.ObservedCity(player, city)) then table.insert(world.enemyCities, {
					city = city, plot = plot, owner = otherPlayer,
					ownerID = SC_StrategySafe(function() return otherPlayer:GetID() end, -1),
					cityID = SC_StrategySafe(function() return city:GetID() end, -1)
				}) end
			end
			for unit in otherPlayer:Units() do
				if unit ~= nil and not SC_StrategySafe(function() return unit:IsDead() end, true) then
					local info = SC_StrategyUnitInfo(unit)
					local plot = SC_StrategySafe(function() return unit:GetPlot() end, nil)
					if plot ~= nil and (not SC5 or SC5.ObservedUnit(player, unit)) then
						local profile = SC_StrategyEnemyProfile(unit, info)
						local power = math.max(tonumber(info and info.Combat) or 0, tonumber(info and info.RangedCombat) or 0)
						local effectivePower = SC_StrategyEffectivePower(profile, unit)
						if effectivePower > 0 then
							world.enemyCombatUnits = world.enemyCombatUnits + 1
							world.enemyCombatPower = world.enemyCombatPower + effectivePower
						end
						table.insert(world.enemyUnits, {
							unit = unit, info = info, profile = profile, plot = plot, power = power,
							domain = info and info.Domain or "", effectivePower = effectivePower,
							ownerID = SC_StrategySafe(function() return unit:GetOwner() end, -1),
							unitID = SC_StrategySafe(function() return unit:GetID() end, -1)
						})
					end
				end
			end
		end
	end
	SC_StrategyAssignCityRoles(world)
	for _, entry in ipairs(world.ownCities) do
		entry.enemyPower, entry.enemyCount = SC_StrategyPowerNear(world.enemyUnits, entry.plot, 10, nil)
		entry.friendlyPower, entry.friendlyCount = SC_StrategyPowerNear(world.ownUnits, entry.plot, 10, nil)
		entry.threatRatio = entry.enemyPower / math.max(entry.friendlyPower, 1)
		world.frontierEnemyPower = world.frontierEnemyPower + entry.enemyPower
	end
	SC_STRATEGY_STATE.turn = turn
	SC_STRATEGY_STATE.playerID = playerID
	SC_STRATEGY_STATE.world = world
	if SC_STRATEGY_STATE.plan ~= nil then SC_STRATEGY_STATE.previousPlan = SC_STRATEGY_STATE.plan end
	SC_STRATEGY_STATE.plan = nil
	SC_STRATEGY_STATE.researchCandidates = {}
	SC_STRATEGY_STATE.policyCandidates = {}
	return world
end

local function SC_StrategyTargetScore(world, entry)
	local city = entry.city
	local plot = entry.plot
	local population = SC_StrategySafe(function() return city:GetPopulation() end, 1)
	local damage = SC_StrategySafe(function() return city:GetDamage() end, 0)
	local maxHP = math.max(SC_StrategySafe(function() return city:GetMaxHitPoints() end, 100), 1)
	local capital = SC_StrategySafe(function() return city:IsCapital() end, false)
	local coastal = SC_StrategySafe(function() return city:IsCoastal() end, false)
	local distance = SC_StrategyNearestDistance(plot, world.ownCities)
	local enemyPower, localDefenders = SC_StrategyPowerNear(world.enemyUnits, plot, 6, nil)
	local friendlyPower, localFriendly = SC_StrategyPowerNear(world.ownUnits, plot, 16, nil)
	local captureUnits = SC_StrategyCountCaptureNear(world.ownUnits, plot, 18)
	local localRatio = friendlyPower / math.max(enemyPower, 1)
	local production = SC_StrategyGetYield(city, "YIELD_PRODUCTION")
	local criticalDefenders = 0
	for _, enemy in ipairs(world.enemyUnits) do
		if SC_StrategyDistance(enemy.plot, plot) <= 8 then
			local class = enemy.profile and enemy.profile.doctrineClass or ""
			if class == "siege_artillery" or class == "ranged_support" or class == "strike_aircraft"
				or class == "surface_fire_support" or class == "arsenal_capital" then
				criticalDefenders = criticalDefenders + 1
			end
		end
	end
	local score = population * 28
		+ damage * SC_StrategyConfig("BlitzCityDamageScore", 1200) / maxHP
		+ production * SC_StrategyConfig("BlitzCityProductionWeight", 18)
		+ criticalDefenders * 90 - distance * 8
		- enemyPower * 0.08 + friendlyPower * 0.045 + math.min(localRatio, 4) * 160
	if capital then score = score + 900 end
	if coastal then score = score + 130 end
	if captureUnits <= 0 then score = score - 2400 end
	return score, distance, localDefenders, capital, coastal, enemyPower, friendlyPower, localRatio,
		captureUnits, localFriendly, production, criticalDefenders
end

local function SC_StrategyBuildTargets(world)
	local candidates = {}
	SC_STRATEGY_STATE.targetProgress = SC_STRATEGY_STATE.targetProgress or {}
	local observedProgress = {}
	for _, entry in ipairs(world.enemyCities) do
		local score, distance, defenders, capital, coastal, enemyPower, friendlyPower, localRatio,
			captureUnits, localFriendly, production, criticalDefenders = SC_StrategyTargetScore(world, entry)
		local key = "city:"..SC_StrategyPlotKey(entry.plot)
		local lockBonus = nil
		if SC5 then
			local distanceToCapturer = 999
			for _, own in ipairs(world.ownUnits or {}) do
				if own.profile and own.profile.canCapture then distanceToCapturer = math.min(distanceToCapturer, SC_StrategyDistance(own.plot, entry.plot)) end
			end
			local progressKey = tostring(world.playerID)..":"..key
			local progress, idle
			lockBonus, progress, idle = SC5.OperationProgress(SC_STRATEGY_STATE.targetProgress[progressKey], {
				turn = world.turn, distance = distanceToCapturer,
				hp = SC5.HP(entry.city), enemyPower = enemyPower,
			})
			observedProgress[progressKey] = progress
			if idle >= 3 then SC_Debug("decision5 operation release="..key.." reason=no-progress idle="..idle.." captureDistance="..distanceToCapturer) end
		end
		local lastTargetTurn = SC_STRATEGY_STATE.targetHistory[key]
		if lastTargetTurn ~= nil and world.turn - lastTargetTurn <= 5 then score = score + 500 end
		local previousOperationID = nil
		local previousStartedTurn = nil
		local targetLockAge = nil
		local targetLocked = false
		for _, oldOperation in ipairs(SC_STRATEGY_STATE.previousPlan and SC_STRATEGY_STATE.previousPlan.operations or {}) do
			if oldOperation.kind == "city_assault" and oldOperation.target ~= nil and oldOperation.target.key == key then
				previousOperationID = oldOperation.id
				previousStartedTurn = oldOperation.startedTurn or (SC_STRATEGY_STATE.previousPlan and SC_STRATEGY_STATE.previousPlan.turn) or (world.turn - 1)
				targetLockAge = math.max(0, world.turn - previousStartedTurn)
					targetLocked = targetLockAge <= SC_StrategyConfig("OperationPlanPersistenceTurns", 8)
					if lockBonus ~= nil then
						targetLocked = targetLocked and lockBonus > 0
						score = score + (targetLocked and lockBonus or 0)
					else
						score = score + (targetLocked and SC_StrategyConfig("BlitzTargetLockBonus", 15000) or 1200)
					end
				break
			end
		end
		table.insert(candidates, {
			city = entry.city, plot = entry.plot, owner = entry.owner, ownerID = entry.ownerID, cityID = entry.cityID, score = score,
			distance = distance, defenders = defenders, capital = capital, coastal = coastal,
			enemyPower = enemyPower, friendlyPower = friendlyPower, localRatio = localRatio,
			captureUnits = captureUnits, localFriendly = localFriendly, production = production,
			criticalDefenders = criticalDefenders, kind = "enemy_city",
			key = key, previousOperationID = previousOperationID,
			previousStartedTurn = previousStartedTurn, targetLockAge = targetLockAge,
			targetLocked = targetLocked
		})
	end
	SC_STRATEGY_STATE.targetProgress = observedProgress
	table.sort(candidates, function(a, b)
		if SC5 == nil and a.targetLocked ~= b.targetLocked then return a.targetLocked end
		if a.score == b.score then return a.key < b.key end
		return a.score > b.score
	end)
	return candidates
end

local function SC_StrategyOperationRequirements(kind, coastal, precision)
	if kind == "city_defense" then
		return {
			rapid_capture = 0, line_frontline = 4, siege = 1,
			air_superiority = 2, carrier_air = 0, air_strike = 1,
			naval_screen = coastal and 3 or 0, naval_fire = coastal and 1 or 0,
			fleet_carrier = 0, strategic_submarine = 0, missile_strike = 0
		}
	end
	if precision and coastal then
		return {
			rapid_capture = 1, line_frontline = 0, siege = 0,
			air_superiority = 2, carrier_air = 3, air_strike = 3,
			naval_screen = 3, naval_fire = 3, fleet_carrier = 1,
			strategic_submarine = 1, missile_strike = 0
		}
	end
	if precision then
		return {
			rapid_capture = 1, line_frontline = 2, siege = 2,
			air_superiority = 2, air_strike = 3, missile_strike = 2
		}
	end
	if coastal then
		return {
			rapid_capture = 2, line_frontline = 3, siege = 2,
			air_superiority = 2, carrier_air = 2, air_strike = 3,
			naval_screen = 4, naval_fire = 3, fleet_carrier = 1,
			strategic_submarine = 1, missile_strike = 2
		}
	end
	return {
		rapid_capture = 2, line_frontline = 4, siege = 2,
		air_superiority = 2, air_strike = 3, missile_strike = 2
	}
end

local function SC_StrategyRequirementReadiness(world, target, requirements, radius)
	local total, ready, parts = 0, 0, {}
	for need, required in pairs(requirements) do
		if required > 0 then
			local current = SC_StrategyCountNeedNear(world.ownUnits, target.plot, radius, need)
			total = total + required
			ready = ready + math.min(current, required)
			table.insert(parts, need..":"..tostring(current).."/"..tostring(required))
		end
	end
	table.sort(parts)
	return total > 0 and ready / total or 1, table.concat(parts, ",")
end

local function SC_StrategyBuildDefensiveOperations(world, maxOperations)
	local candidates = {}
	for _, cityEntry in ipairs(world.ownCities) do
		if (cityEntry.enemyCount or 0) > 0 then
			local city = cityEntry.city
			local damage = SC_StrategySafe(function() return city:GetDamage() end, 0)
			local population = SC_StrategySafe(function() return city:GetPopulation() end, 1)
			local capital = SC_StrategySafe(function() return city:IsCapital() end, false)
			local coastal = SC_StrategySafe(function() return city:IsCoastal() end, false)
			local score = (cityEntry.enemyPower or 0) * 0.12 + (cityEntry.threatRatio or 0) * 700
				+ damage * 8 + population * 18 + (capital and 1000 or 0)
			table.insert(candidates, {
				city = city, plot = cityEntry.plot, key = "defend:"..SC_StrategyPlotKey(cityEntry.plot),
				kind = "city_defense", score = score, coastal = coastal, capital = capital,
				enemyPower = cityEntry.enemyPower, friendlyPower = cityEntry.friendlyPower,
				localRatio = cityEntry.friendlyPower / math.max(cityEntry.enemyPower, 1),
				enemyCount = cityEntry.enemyCount or 0
			})
		end
	end
	table.sort(candidates, function(a, b) return a.score > b.score end)
	local operations = {}
	for i = 1, math.min(#candidates, maxOperations), 1 do
		local target = candidates[i]
		local requirements = SC_StrategyOperationRequirements("city_defense", target.coastal, false)
		local readiness, readinessDebug = SC_StrategyRequirementReadiness(world, target, requirements, 14)
		table.insert(operations, {
			id = "OP:"..target.key, kind = "city_defense", target = target,
			phase = target.localRatio < 0.85 and "hold" or "counterattack",
			domain = target.coastal and "joint" or "land", requirements = requirements,
			readiness = readiness, readinessDebug = readinessDebug, admitted = true,
			lossBudget = 0.04
		})
	end
	return operations
end

local function SC_StrategyBuildOffensiveOperations(world, candidates, maxOperations, posture)
	local operations, rejected = {}, {}
	for _, target in ipairs(candidates) do
		if #operations >= maxOperations then break end
		local deployablePower = SC_StrategyPowerNear(world.ownUnits, target.plot, 55, nil)
		local strategicRatio = deployablePower / math.max(target.enemyPower, 1)
		local precision = target.captureUnits >= SC_StrategyConfig("PrecisionStrikeMinimumCaptureUnits", 1)
			and math.max(target.localRatio, strategicRatio) >= SC_StrategyConfig("PrecisionStrikePowerRatio", 2.40)
		local requirements = SC_StrategyOperationRequirements("city_assault", target.coastal, precision)
		local readiness, readinessDebug = SC_StrategyRequirementReadiness(world, target, requirements, 22)
		local globalReadiness, globalReadinessDebug = SC_StrategyRequirementReadiness(world, target, requirements, 999)
		local minimumReadiness = posture == "decapitation" and 0.68 or 0.78
		local minimumRatio = posture == "decapitation" and 1.10 or 1.25
		local tacticalAdmission = target.captureUnits > 0 and readiness >= minimumReadiness and target.localRatio >= minimumRatio
		local assemblySlotAvailable = #operations == 0 or (posture == "decapitation" and precision)
		local assemblyAdmission = assemblySlotAvailable and target.distance <= 55 and globalReadiness >= 0.82
			and strategicRatio >= 1.45 and (world.counts.rapid_capture or 0) + (world.counts.line_frontline or 0) > 0
		local admitted = tacticalAdmission or assemblyAdmission
		if admitted then
			SC_STRATEGY_STATE.targetHistory[target.key] = world.turn
			table.insert(operations, {
				id = "OP:"..target.key, kind = "city_assault", target = target,
				startedTurn = target.previousStartedTurn or world.turn,
				targetLocked = target.targetLocked == true, targetLockAge = target.targetLockAge,
				phase = tacticalAdmission and (target.defenders > 5 and "shape" or "assault") or "assemble",
				domain = target.coastal and "joint" or "land", requirements = requirements,
				readiness = tacticalAdmission and readiness or globalReadiness,
				readinessDebug = tacticalAdmission and readinessDebug or globalReadinessDebug,
				localReadiness = readiness, strategicRatio = strategicRatio, admitted = true,
				precision = precision, deployablePower = deployablePower,
				lossBudget = posture == "decapitation" and 0.07 or 0.05
			})
			if assemblyAdmission and not tacticalAdmission and posture ~= "decapitation" then break end
		else
			table.insert(rejected, target.key..":ready="..string.format("%.2f", readiness)..
				":globalReady="..string.format("%.2f", globalReadiness)..
				":ratio="..string.format("%.2f", target.localRatio)..
				":strategicRatio="..string.format("%.2f", strategicRatio)..":capture="..tostring(target.captureUnits)..":precision="..tostring(precision))
		end
	end
	return operations, rejected
end

local function SC_StrategyBuildNationalPriorities(world, posture, operations)
	local doctrine = SC_StrategyConfig("Doctrine", "BALANCED")
	local economy = SC_StrategyConfig("EconomyProfile", "BALANCED")
	local build = SC_StrategyConfig("BuildProfile", "INFRASTRUCTURE")
	local victory = "balanced"
	if doctrine == "SCIENCE" or economy == "SCIENCE" or build == "SCIENCE" then victory = "science"
	elseif world.atWar or doctrine == "WAR" or posture == "decapitation" or SC_StrategyConfig("WarProfile", "ADVANCE") == "ASSAULT" then victory = "conquest"
	elseif doctrine == "INDUSTRY" then victory = "industry" end
	local crisis = "stable"
	local finance = SC5 and SC5.Finance({ gold = world.gold, goldRate = world.goldRate,
		unitCost = world.unitCost, cities = #world.ownCities, happiness = world.happiness, atWar = world.atWar })
	if finance then crisis = finance.crisis
	elseif world.happiness < 0 then crisis = "happiness"
	elseif world.goldRate < -math.max(25, #world.ownCities * 3) then crisis = "deficit"
	elseif posture == "defend" then crisis = "defense" end
	local priorities = {
		growth = 1.0, production = 1.15, science = 1.10, gold = 0.85,
		culture = 0.55, happiness = 1.0, military = world.atWar and 1.25 or 0.55,
		expansion = 0.35, defense = posture == "defend" and 1.8 or 0.75
	}
	if victory == "science" then priorities.science = 1.75; priorities.production = 1.30
	elseif victory == "conquest" then priorities.military = 1.75; priorities.production = 1.45; priorities.science = 1.20
	elseif victory == "industry" then priorities.production = 1.75; priorities.gold = 1.10 end
	if crisis == "happiness" then priorities.happiness = 2.4; priorities.expansion = 0
	elseif crisis == "deficit" then priorities.gold = 2.1; priorities.military = math.min(priorities.military, 0.9)
	elseif crisis == "defense" then priorities.defense = 2.4; priorities.military = math.max(priorities.military, 1.8) end
	if economy == "EXPANSION" and world.happiness >= 8 and world.goldRate >= 0 and not world.atWar then priorities.expansion = 1.7 end
	local reserve = math.max(#world.ownCities * 1800, math.max(0, -world.goldRate) * 20, world.unitCost * 4)
	if posture == "defend" then reserve = reserve * 1.25 end
	local spendable = math.max(0, world.gold - reserve)
	local militaryFraction = world.atWar and (posture == "defend" and 0.34 or 0.24) or 0.08
	if crisis == "deficit" then militaryFraction = math.min(militaryFraction, 0.08) end
	if finance then
		reserve, spendable, militaryFraction = finance.reserve, finance.spendable, finance.militaryFraction
		priorities.gold = finance.goldWeight
		SC_Debug("decision5 finance runway="..string.format("%.1f", finance.runway)..
			" reserve="..reserve.." spendable="..spendable.." crisis="..crisis)
	end
	return {
		victory = victory, crisis = crisis, priorities = priorities,
		reserveGold = math.floor(reserve), spendableGold = math.floor(spendable),
		militaryPurchaseFraction = militaryFraction,
		operationCount = #operations
	}
end

local function SC_StrategyBuildForceTargets(world, operations, immediateEnemyPower)
	local operationCount = math.max(#operations, world.atWar and 1 or 0)
	local coastalOperations = 0
	for _, operation in ipairs(operations) do
		if operation.target.coastal then coastalOperations = coastalOperations + 1 end
	end
	local coastalCities = 0
	for _, entry in ipairs(world.ownCities) do
		if SC_StrategySafe(function() return entry.city:IsCoastal() end, false) then coastalCities = coastalCities + 1 end
	end
	local averagePower = world.combatPower / math.max(world.combatUnits, 1)
	local threatEquivalent = math.ceil(math.max(tonumber(immediateEnemyPower) or 0, 0) * 1.15 / math.max(averagePower, 1))
	local cityGarrisonFloor = math.ceil(#world.ownCities * (world.atWar and 2.4 or 1.4))
	local operationMinimum = 0
	for _, operation in ipairs(operations) do
		for _, required in pairs(operation.requirements or {}) do
			operationMinimum = operationMinimum + math.max(tonumber(required) or 0, 0)
		end
	end
	local reserveFloor = math.max(#world.ownCities * SC_StrategyConfig("OperationMinimumReservePerCity", 1), math.ceil(operationMinimum * 0.30))
	local targetForce = math.max(world.atWar and 18 or 8, threatEquivalent, cityGarrisonFloor, operationMinimum + reserveFloor)
	-- Existing surplus is not a production target. Otherwise every extra unit
	-- permanently raises every doctrinal quota and creates a self-feeding army.
	if world.combatUnits > targetForce * 1.35 then targetForce = math.ceil(targetForce * 1.10) end
	local navalTheater = coastalCities > 0 and (world.atWar or coastalOperations > 0)
	local targets = {
		rapid_capture = math.max(2, math.ceil(targetForce * 0.10)),
		line_frontline = math.max(4, math.ceil(targetForce * 0.34)),
		siege = math.max(2, math.ceil(targetForce * 0.12)),
		air_superiority = math.max(2, math.ceil(targetForce * 0.10)),
		carrier_air = navalTheater and math.max(2, math.ceil(targetForce * 0.06)) or 0,
		air_strike = math.max(2, math.ceil(targetForce * 0.12)),
		naval_screen = navalTheater and math.max(4, math.ceil(targetForce * 0.13)) or 0,
		naval_fire = navalTheater and math.max(2, math.ceil(targetForce * 0.08)) or 0,
		fleet_carrier = navalTheater and math.max(1, math.ceil(targetForce * 0.025)) or 0,
		strategic_submarine = navalTheater and math.max(1, math.ceil(targetForce * 0.025)) or 0,
		missile_strike = math.max(2, math.ceil(targetForce * 0.06))
	}
	return targets, targetForce
end

local function SC_StrategyOperationSlot(operation, entry)
	if operation == nil or entry == nil or entry.profile == nil then return nil end
	local need = entry.need
	if need == "rapid_capture" and (operation.requirements.rapid_capture or 0) <= 0 then need = "line_frontline" end
	if need ~= nil and (operation.requirements[need] or 0) > 0 then return need end
	local class = entry.profile.doctrineClass
	if operation.target.coastal then
		if class == "fleet_carrier" then return "fleet_carrier" end
		if class == "ballistic_submarine" then return "strategic_submarine" end
		if class == "attack_submarine" or class == "escort_screen" or class == "naval_assault" then return "naval_screen" end
		if class == "surface_fire_support" or class == "arsenal_capital" then return "naval_fire" end
	end
	if class == "mobile_air_defense" or class == "air_defense_screen" or class == "counter_defender"
		or class == "line_defender" or class == "static_fortress" then return "line_frontline" end
	if class == "gunship" or class == "mobile_breakthrough" or class == "airborne_raider" or class == "recon_raider"
		or class == "super_heavy" then return (operation.requirements.rapid_capture or 0) > 0 and "rapid_capture" or "line_frontline" end
	if class == "siege_artillery" or class == "ranged_support" then return "siege" end
	if class == "air_superiority" then return "air_superiority" end
	if class == "carrier_multirole" then return (operation.requirements.carrier_air or 0) > 0 and "carrier_air" or "air_superiority" end
	if class == "strike_aircraft" then return "air_strike" end
	if class == "missile_strike" or class == "strategic_nuclear" then return "missile_strike" end
	if entry.info.Domain == "DOMAIN_LAND" then return "line_frontline" end
	return nil
end

local function SC_StrategyOperationCompatible(operation, entry)
	if operation == nil or entry == nil or entry.info == nil or entry.plot == nil then return false end
	if (entry.effectivePower or 0) <= 0 then return false end
	local class = entry.profile and entry.profile.doctrineClass or ""
	if operation.kind == "city_defense" and (class == "fleet_carrier" or class == "carrier_multirole"
		or class == "ballistic_submarine" or class == "arsenal_capital"
		or class == "missile_strike" or class == "strategic_nuclear") then return false end
	if operation.kind ~= "city_defense" and (class == "static_fortress" or class == "line_defender") then return false end
	local domain = entry.info.Domain
	if domain == "DOMAIN_SEA" and not operation.target.coastal then return false end
	for slot, required in pairs(operation.requirements or {}) do
		if required > 0 and entry.capabilities ~= nil and (entry.capabilities[slot] or 0) > 0 then return true end
	end
	return SC_StrategyOperationSlot(operation, entry) ~= nil
end

local function SC_StrategyOperationCapacity(operation, slot)
	local required = operation.requirements[slot] or 0
	local forceBudget = math.max(operation.forceBudget or 0, 1)
	if required <= 0 then return 0 end
	-- A city assault needs a primary capturer and at most one backup.  Extra
	-- melee hulls belong in the screen/frontline slots instead of forming a
	-- twenty-unit queue behind the same zero-HP city.
	if slot == "rapid_capture" then
		return math.max(1, math.min(required, SC_StrategyConfig("StrategicCityCaptureTargetCapacity", 2)))
	end
	-- Defensive operations receive only their contracted specialist package.
	-- Extra strike aircraft, artillery and naval fire belong on the offensive
	-- axis; only line troops and screens scale with local defensive pressure.
	if operation.kind == "city_defense"
		and slot ~= "line_frontline" and slot ~= "naval_screen" then
		return required
	end
	local fractions = {
		line_frontline = operation.kind == "city_defense" and 0.55 or 0.30,
		siege = operation.kind == "city_defense" and 0.14 or 0.20,
		air_superiority = 0.15, carrier_air = 0.16, air_strike = 0.20,
		naval_screen = operation.kind == "city_defense" and 0.30 or 0.20,
		naval_fire = operation.kind == "city_defense" and 0.12 or 0.20,
		fleet_carrier = 0.08, strategic_submarine = 0.08, missile_strike = 0.12
	}
	return math.max(required, math.ceil(forceBudget * (fractions[slot] or 0.12)))
end

local function SC_StrategyRequirementTotal(operation)
	local total = 0
	for _, required in pairs(operation.requirements or {}) do total = total + math.max(tonumber(required) or 0, 0) end
	return total
end

local function SC_StrategyPrepareOperationBudgets(world, operations, posture)
	if #operations <= 0 then return 0 end
	local reserveFraction = math.max(0.05, math.min(SC_StrategyConfig("OperationReserveFraction", 0.10), 0.30))
	local available = math.max(1, math.floor(world.combatUnits * (1 - reserveFraction)))
	local totalWeight = 0
	for _, operation in ipairs(operations) do
		local enemyPower = math.max(tonumber(operation.target.enemyPower) or 0, 1)
		local weight = math.sqrt(enemyPower) + SC_StrategyRequirementTotal(operation) * 8
		if operation.kind == "city_defense" then weight = weight * 1.18 end
		operation.forceWeight = weight
		totalWeight = totalWeight + weight
	end
	local minimumTotal = 0
	for _, operation in ipairs(operations) do minimumTotal = minimumTotal + SC_StrategyRequirementTotal(operation) end
	local blitzFloor = 0
	if posture == "decapitation" and #operations > 0 then
		local utilization = math.max(0.50, math.min(SC_StrategyConfig("BlitzForceUtilization", 0.90), 1.0))
		blitzFloor = math.ceil(available * utilization / #operations)
	end
	local allocated = 0
	for _, operation in ipairs(operations) do
		local rawMinimum = SC_StrategyRequirementTotal(operation)
		local minimum = rawMinimum
		if minimumTotal > available then
			minimum = math.max(1, math.floor(available * rawMinimum / math.max(minimumTotal, 1)))
		end
		local defenders = math.max(tonumber(operation.target.defenders)
			or tonumber(operation.target.localDefenders)
			or tonumber(operation.target.enemyCount) or 0, 0)
		local reinforcement = math.ceil(defenders * (operation.kind == "city_defense" and 0.85 or 0.60))
		if operation.phase == "assemble" then reinforcement = math.ceil(reinforcement * 0.65) end
		local hardCap = operation.target.coastal
			and SC_StrategyConfig("OperationCoastalForceCap", 48)
			or SC_StrategyConfig("OperationLandForceCap", 36)
		if operation.kind == "city_defense" then
			hardCap = operation.target.coastal
				and SC_StrategyConfig("OperationDefenseCoastalForceCap", 30)
				or SC_StrategyConfig("OperationDefenseLandForceCap", 24)
		end
		operation.minimumForceBudget = minimum
		local operationBlitzFloor = operation.kind == "city_assault" and blitzFloor or 0
		operation.desiredForceBudget = math.max(minimum, math.min(hardCap, math.max(rawMinimum + reinforcement, operationBlitzFloor)))
		operation.forceBudget = minimum
		allocated = allocated + operation.forceBudget
	end
	while allocated > available do
		local reducible = nil
		for _, operation in ipairs(operations) do
			if operation.forceBudget > 1
				and (reducible == nil or operation.forceBudget > reducible.forceBudget) then reducible = operation end
		end
		if reducible == nil then break end
		reducible.forceBudget = reducible.forceBudget - 1
		allocated = allocated - 1
	end
	while allocated < available do
		local best = nil
		local bestNeed = -1
		for _, operation in ipairs(operations) do
			local remaining = math.max((operation.desiredForceBudget or 0) - (operation.forceBudget or 0), 0)
			local need = remaining * (operation.forceWeight or 1)
			if remaining > 0 and need > bestNeed then
				best = operation
				bestNeed = need
			end
		end
		if best == nil then break end
		best.forceBudget = best.forceBudget + 1
		allocated = allocated + 1
	end
	return allocated
end

local function SC_StrategyAssignOperations(world, plan)
	local previous = SC_STRATEGY_STATE.assignments or {}
	local assignments = {}
	plan.assignmentBudget = SC_StrategyPrepareOperationBudgets(world, plan.operations, plan.posture)
	for _, operation in ipairs(plan.operations) do operation.assigned = {}; operation.assignedTotal = 0 end
	local entries = {}
	for _, entry in ipairs(world.ownUnits) do
		local damage = SC_StrategySafe(function() return entry.unit:GetDamage() end, 0)
		if (entry.effectivePower or 0) > 0 and damage < 55 then table.insert(entries, entry) end
	end
	local unassigned = {}
	for _, entry in ipairs(entries) do unassigned[SC_StrategyUnitKey(entry.unit)] = entry end
	local assignmentOperations = {}
	for _, operation in ipairs(plan.operations) do table.insert(assignmentOperations, operation) end
	local function operationPriority(operation)
		if operation.kind == "city_defense" and operation.phase == "hold" and (operation.target.localRatio or 9) < 0.65 then return 4 end
		if operation.kind == "city_assault" then return 3 end
		if operation.kind == "city_defense" and operation.phase == "hold" then return 2 end
		return 1
	end
	table.sort(assignmentOperations, function(a, b)
		local ap, bp = operationPriority(a), operationPriority(b)
		if ap == bp then return (a.target.score or 0) > (b.target.score or 0) end
		return ap > bp
	end)
	for index, operation in ipairs(assignmentOperations) do operation.assignmentPriority = index end
	local function candidateScore(entry, operation, slot, requiredPass)
		if not SC_StrategyOperationCompatible(operation, entry) then return -999999 end
		local supply = entry.capabilities and (entry.capabilities[slot] or 0) or 0
		if supply <= 0 then
			local naturalSlot = SC_StrategyOperationSlot(operation, entry)
			if naturalSlot ~= slot then return -999999 end
			supply = 1
		end
		local distance = SC_StrategyDistance(entry.plot, operation.target.plot)
		local joinLimit = operation.phase == "assemble" and 75 or (entry.info.Domain == "DOMAIN_LAND" and 60 or 55)
		if distance > joinLimit then return -999999 end
		local key = SC_StrategyUnitKey(entry.unit)
		local old = key ~= nil and previous[key] or nil
		local score = (requiredPass and 2200 or 500) - distance * 14
			+ (entry.effectivePower or 0) * 0.04 + supply * 300
		if entry.need == slot then score = score + 180 end
		if operation.kind == "city_defense" and operation.phase == "hold" then score = score + 280 end
		if operation.kind == "city_assault" then score = score + 520 end
		if old ~= nil and old.operationID == operation.id and old.slot == slot then score = score + 1200 end
		if operation.kind ~= "city_defense" and SC_STRATEGY_HIGH_VALUE_CLASSES[entry.profile.doctrineClass or ""]
			and operation.readiness < 0.60 then score = score - 2600 end
		return score
	end
	local function assignBest(operation, slot, requiredPass)
		if operation.assignedTotal >= (operation.forceBudget or 0) then return false end
		if (operation.assigned[slot] or 0) >= SC_StrategyOperationCapacity(operation, slot) then return false end
		local bestKey, bestEntry, bestScore = nil, nil, -999999
		for key, entry in pairs(unassigned) do
			local score = candidateScore(entry, operation, slot, requiredPass)
			if score > bestScore then bestKey, bestEntry, bestScore = key, entry, score end
		end
		if bestEntry == nil or bestScore <= -999000 then return false end
		operation.assigned[slot] = (operation.assigned[slot] or 0) + 1
		operation.assignedTotal = operation.assignedTotal + 1
		assignments[bestKey] = { operationID = operation.id, slot = slot, turn = plan.turn, score = bestScore }
		unassigned[bestKey] = nil
		return true
	end
	local slotOrder = {"rapid_capture", "line_frontline", "siege", "air_superiority", "carrier_air", "air_strike", "naval_screen", "naval_fire", "fleet_carrier", "strategic_submarine", "missile_strike"}
	-- First fill the formation contract. This prevents powerful carriers or
	-- artillery from consuming the budget before capturers and screens exist.
	for _, operation in ipairs(assignmentOperations) do
		for _, slot in ipairs(slotOrder) do
			for _ = 1, math.max(operation.requirements[slot] or 0, 0), 1 do
				if not assignBest(operation, slot, true) then break end
			end
		end
	end
	-- Then add bounded reinforcements without exceeding slot or operation caps.
	for _, operation in ipairs(assignmentOperations) do
		local progress = true
		while progress and operation.assignedTotal < (operation.forceBudget or 0) do
			progress = false
			for _, slot in ipairs(slotOrder) do
				if assignBest(operation, slot, false) then progress = true end
				if operation.assignedTotal >= (operation.forceBudget or 0) then break end
			end
		end
	end
	SC_STRATEGY_STATE.assignments = assignments
	plan.assignedCombat = 0
	for _, operation in ipairs(plan.operations) do
		local parts = {}
		local requiredTotal, requiredFilled = 0, 0
		for slot, count in pairs(operation.assigned) do table.insert(parts, slot..":"..tostring(count)) end
		for slot, required in pairs(operation.requirements or {}) do
			requiredTotal = requiredTotal + required
			requiredFilled = requiredFilled + math.min(operation.assigned[slot] or 0, required)
		end
		table.sort(parts)
		operation.assignmentDebug = table.concat(parts, ",")
		operation.formationReadiness = requiredTotal > 0 and requiredFilled / requiredTotal or 1
		if operation.kind == "city_assault" and operation.formationReadiness < 0.70 then operation.phase = "assemble" end
		plan.assignedCombat = plan.assignedCombat + (operation.assignedTotal or 0)
	end
	plan.reserveCombat = math.max(0, world.combatUnits - plan.assignedCombat)
end

local function SC_StrategyBuildUnitTasks(world, plan)
	local tasks, metrics = {}, {}
	local function count(kind) metrics[kind] = (metrics[kind] or 0) + 1 end
	local primaryOffensive = nil
	for _, operation in ipairs(plan.operations or {}) do
		if operation.kind == "city_assault"
			and (primaryOffensive == nil or (operation.target.score or 0) > (primaryOffensive.target.score or 0)) then
			primaryOffensive = operation
		end
	end
	for _, entry in ipairs(world.ownUnits) do
		local key = SC_StrategyUnitKey(entry.unit)
		local assignment = key ~= nil and SC_STRATEGY_STATE.assignments[key] or nil
		local class = entry.profile and entry.profile.doctrineClass or "unknown"
		local damage = SC_StrategySafe(function() return entry.unit:GetDamage() end, 0)
		local task = nil
		if damage >= 55 and (entry.effectivePower or 0) > 0 then
			task = { kind = "recovery", priority = 1000, reason = "damage="..tostring(damage) }
		elseif assignment ~= nil then
			local operation = nil
			for _, candidate in ipairs(plan.operations) do if candidate.id == assignment.operationID then operation = candidate break end end
			task = { kind = "operation", priority = 800, operationID = assignment.operationID,
				slot = assignment.slot, phase = operation and operation.phase or "unknown",
				targetPlot = operation and operation.target.plot or nil, reason = "formation-slot" }
		elseif class == "civilian_builder" then task = { kind = "improve", priority = 500, reason = "builder" }
		elseif class == "civilian_settler" then task = { kind = "settle", priority = 650, reason = "settler" }
		elseif class == "civilian_trade" then task = { kind = "trade", priority = 550, reason = "trade-unit" }
		elseif class == "civilian_specialist" then task = { kind = "great_person", priority = 600, reason = "specialist" }
		elseif (entry.effectivePower or 0) > 0 then
			local nearest, nearestDistance = nil, 999
			for _, cityEntry in ipairs(world.ownCities) do
				local distance = SC_StrategyDistance(entry.plot, cityEntry.plot)
				if distance < nearestDistance then nearest, nearestDistance = cityEntry, distance end
			end
			local enemyDistance = SC_StrategyNearestDistance(entry.plot, world.enemyUnits)
			local highValue = SC_STRATEGY_HIGH_VALUE_CLASSES[class] == true
			local reserveKind = enemyDistance <= 8 and "local_reserve" or (highValue and "strategic_reserve" or "garrison_reserve")
			local reservePriority = reserveKind == "local_reserve" and 520 or (highValue and 450 or 300)
			local reserveTarget = highValue and primaryOffensive ~= nil and primaryOffensive.target.plot or (nearest and nearest.plot or nil)
			task = { kind = reserveKind, priority = reservePriority,
				targetPlot = reserveTarget,
				operationID = highValue and primaryOffensive ~= nil and primaryOffensive.id or nil,
				reason = "unassigned:"..class..":enemyDistance="..tostring(enemyDistance)..":cityDistance="..tostring(nearestDistance)..
					(highValue and primaryOffensive ~= nil and ":primaryAssault" or "") }
		else task = { kind = "support", priority = 200, reason = class } end
		if key ~= nil then tasks[key] = task; count(task.kind) end
	end
	SC_STRATEGY_STATE.unitTasks = tasks
	SC_STRATEGY_STATE.taskMetrics = metrics
	plan.taskMetrics = metrics
end

function SC_StrategyTaskMetricsDebug()
	local parts = {}
	for kind, count in pairs(SC_STRATEGY_STATE.taskMetrics or {}) do table.insert(parts, kind..":"..tostring(count)) end
	table.sort(parts)
	return table.concat(parts, ",")
end

function SC_StrategyBuildPlan(player, atWar, force)
	local world = SC_StrategyBuildWorld(player, atWar, force)
	if world == nil then return nil end
	if not force and SC_STRATEGY_STATE.plan ~= nil and SC_STRATEGY_STATE.plan.turn == world.turn then
		return SC_STRATEGY_STATE.plan
	end
	local candidates = SC_StrategyBuildTargets(world)
	local casualtyRate = 0
	local previousPower = SC_STRATEGY_STATE.powerHistory
	if previousPower ~= nil and previousPower.turn == world.turn - 1 and previousPower.power > 0 then
		casualtyRate = math.max(0, (previousPower.power - world.combatPower) / previousPower.power)
	end
	local directLosses = 0
	for lossTurn = world.turn - 1, world.turn do
		local lossEntry = SC_STRATEGY_STATE.lossesByTurn[lossTurn]
		if lossEntry ~= nil then directLosses = directLosses + (lossEntry.count or 0) end
	end
	local directCasualtyRate = directLosses / math.max(world.combatUnits + directLosses, 1)
	casualtyRate = math.max(casualtyRate, directCasualtyRate)
	SC_STRATEGY_STATE.forceHistory = SC_STRATEGY_STATE.forceHistory or {}
	local historyWindow = math.max(2, SC_StrategyConfig("StrategicForceHistoryTurns", 6))
	local peakRecentForce = world.combatUnits
	for _, snapshot in ipairs(SC_STRATEGY_STATE.forceHistory) do
		if snapshot.turn >= world.turn - historyWindow then
			peakRecentForce = math.max(peakRecentForce, snapshot.combatUnits or 0)
		end
	end
	local forceDrawdown = peakRecentForce > 0 and math.max(0, (peakRecentForce - world.combatUnits) / peakRecentForce) or 0
	local immediateEnemyPower = 0
	for _, enemy in ipairs(world.enemyUnits) do
		if SC_StrategyNearestDistance(enemy.plot, world.ownCities) <= 18 then
			immediateEnemyPower = immediateEnemyPower + (enemy.effectivePower or 0)
		end
	end
	local threatenedCities = {}
	for _, cityEntry in ipairs(world.ownCities) do if (cityEntry.enemyCount or 0) > 0 then table.insert(threatenedCities, cityEntry) end end
	local immediateFriendlyPower = 0
	for _, own in ipairs(world.ownUnits) do
		if SC_StrategyNearestDistance(own.plot, threatenedCities) <= 18 then immediateFriendlyPower = immediateFriendlyPower + (own.effectivePower or 0) end
	end
	local offensivePowerRatio = 0
	for _, target in ipairs(candidates) do
		if target.captureUnits > 0 then offensivePowerRatio = math.max(offensivePowerRatio, target.localRatio or 0) end
	end
	local defensivePowerRatio = immediateEnemyPower > 0
		and immediateFriendlyPower / math.max(immediateEnemyPower, 1) or 9
	local powerRatio = offensivePowerRatio > 0 and offensivePowerRatio or defensivePowerRatio
	local posture = "peace"
	if SC5 then
		posture = SC5.Posture({ atWar = world.atWar, offensiveRatio = offensivePowerRatio,
			defensiveRatio = defensivePowerRatio, hasCapturer = offensivePowerRatio > 0 })
	elseif world.atWar then
		if defensivePowerRatio < 0.72
			or casualtyRate >= SC_StrategyConfig("StrategicCasualtyDefendThreshold", 0.08)
			or forceDrawdown >= SC_StrategyConfig("StrategicForceDrawdownDefendThreshold", 0.08)
			or (world.happiness < -30 and defensivePowerRatio < 1.15 and offensivePowerRatio < 1.40) then
			posture = "defend"
		elseif offensivePowerRatio >= 1.40 then
			posture = "decapitation"
		else
			posture = "advance"
		end
	end
	local configuredOperations = math.max(1, math.min(SC_StrategyConfig("NationalMaxOperations", 8), 8))
	local enemyCountRatio = world.enemyCombatUnits / math.max(world.combatUnits, 1)
	local offensiveLimit = 0
	local defenseLimit = 0
	if posture == "defend" then
		defenseLimit = math.min(configuredOperations, math.max(1, #threatenedCities), 4)
	elseif posture == "decapitation" then
		offensiveLimit = math.min(SC_StrategyConfig("BlitzMaxConcurrentAssaults", 2), configuredOperations)
		defenseLimit = math.min(SC_StrategyConfig("BlitzMaxConcurrentDefenses", 2), #threatenedCities)
	elseif posture == "advance" then
		offensiveLimit = math.min(SC_StrategyConfig("AdvanceMaxConcurrentAssaults", 1), configuredOperations)
		defenseLimit = math.min(SC_StrategyConfig("BlitzMaxConcurrentDefenses", 2), #threatenedCities)
	end
	local multiAxisOvermatch = posture == "decapitation"
		and offensivePowerRatio >= SC_StrategyConfig("DecapitationMultiAxisPowerRatio", 3.0)
		and defensivePowerRatio >= SC_StrategyConfig("DecapitationMultiAxisDefenseRatio", 1.20)
	local severeAttrition = casualtyRate >= SC_StrategyConfig("StrategicCasualtyDefendThreshold", 0.08)
		or forceDrawdown >= SC_StrategyConfig("StrategicForceDrawdownDefendThreshold", 0.08)
	local numericallyPressed = enemyCountRatio >= SC_StrategyConfig("BlitzOutnumberedSingleAxisRatio", 2.50)
		and offensivePowerRatio < SC_StrategyConfig("DecapitationMultiAxisPowerRatio", 3.0)
	if offensiveLimit > 1 and not multiAxisOvermatch and (numericallyPressed or severeAttrition) then
		offensiveLimit = 1
	end
	if defenseLimit + offensiveLimit > configuredOperations then
		defenseLimit = math.max(0, configuredOperations - offensiveLimit)
	end
	local maxOperations = math.min(configuredOperations, defenseLimit + offensiveLimit)
	if maxOperations <= 0 and world.atWar then maxOperations = 1 end
	local operations = SC_StrategyBuildDefensiveOperations(world, defenseLimit)
	local rejected = {}
	if posture ~= "defend" and offensiveLimit > 0 then
		local offensive, offensiveRejected = SC_StrategyBuildOffensiveOperations(world, candidates, offensiveLimit, posture)
		for _, operation in ipairs(offensive) do table.insert(operations, operation) end
		rejected = offensiveRejected
	end
	local targets = {}
	for _, operation in ipairs(operations) do table.insert(targets, operation.target) end
	local national = SC_StrategyBuildNationalPriorities(world, posture, operations)
	local forceTargets, forceTargetTotal = SC_StrategyBuildForceTargets(world, operations, immediateEnemyPower)
	local plan = {
		turn = world.turn, posture = posture, powerRatio = powerRatio,
		targets = targets, targetCandidates = candidates, forceTargets = forceTargets,
		operations = operations, rejectedOperations = rejected, forceTargetTotal = forceTargetTotal,
		immediateEnemyPower = immediateEnemyPower, immediateFriendlyPower = immediateFriendlyPower,
		offensivePowerRatio = offensivePowerRatio, defensivePowerRatio = defensivePowerRatio,
		maxOperations = maxOperations, offensiveLimit = offensiveLimit,
		casualtyRate = casualtyRate, directLosses = directLosses, forceDrawdown = forceDrawdown,
		enemyCountRatio = enemyCountRatio,
		national = national, reserveGold = national.reserveGold
	}
	SC_StrategyAssignOperations(world, plan)
	SC_StrategyBuildUnitTasks(world, plan)
	SC_STRATEGY_STATE.powerHistory = { turn = world.turn, power = world.combatPower }
	local lastForceSnapshot = SC_STRATEGY_STATE.forceHistory[#SC_STRATEGY_STATE.forceHistory]
	if lastForceSnapshot ~= nil and lastForceSnapshot.turn == world.turn then
		lastForceSnapshot.combatUnits = world.combatUnits
	else
		table.insert(SC_STRATEGY_STATE.forceHistory, { turn = world.turn, combatUnits = world.combatUnits })
	end
	while #SC_STRATEGY_STATE.forceHistory > historyWindow do table.remove(SC_STRATEGY_STATE.forceHistory, 1) end
	SC_STRATEGY_STATE.national = national
	SC_STRATEGY_STATE.plan = plan
	return plan
end

function SC_StrategyBeginTurn(player, atWar, reason, force)
	local plan = SC_StrategyBuildPlan(player, atWar, force)
	if plan == nil then return nil end
	local world = SC_STRATEGY_STATE.world
	local targetParts = {}
	for _, operation in ipairs(plan.operations) do
		local target = operation.target
		local capacityParts = {}
		for slot, required in pairs(operation.requirements or {}) do
			if required > 0 then table.insert(capacityParts, slot..":"..tostring(SC_StrategyOperationCapacity(operation, slot))) end
		end
		table.sort(capacityParts)
		table.insert(targetParts, operation.kind..":"..target.key.."@"..tostring(math.floor(target.score))..
			":ready="..tostring(math.floor((operation.readiness or 0) * 100)).."%:force="..
			tostring(operation.assignedTotal or 0).."/"..tostring(operation.forceBudget or 0)..":assigned="..tostring(operation.assignmentDebug or ""))
		SC_Debug("strategyOperation turn="..tostring(plan.turn).." id="..tostring(operation.id)..
			" kind="..tostring(operation.kind).." phase="..tostring(operation.phase)..
			" assignmentPriority="..tostring(operation.assignmentPriority or 0)..
			" formationReady="..tostring(math.floor((operation.formationReadiness or 0) * 100)).."%"..
			" assigned="..tostring(operation.assignedTotal or 0).." budget="..tostring(operation.forceBudget or 0)..
			" desired="..tostring(operation.desiredForceBudget or operation.forceBudget or 0)..
			" defenders="..tostring(target.defenders or target.localDefenders or target.enemyCount or 0)..
			" enemyPower="..tostring(math.floor(tonumber(target.enemyPower) or 0))..
			" friendlyPower="..tostring(math.floor(tonumber(target.friendlyPower) or 0))..
			" localRatio="..string.format("%.2f", tonumber(target.localRatio) or 0)..
			" strategicRatio="..string.format("%.2f", tonumber(operation.strategicRatio) or 0)..
			" startedTurn="..tostring(operation.startedTurn or plan.turn)..
			" targetLocked="..tostring(operation.targetLocked == true)..
			" lockAge="..tostring(operation.targetLockAge or 0)..
			" precision="..tostring(operation.precision == true)..
			" production="..tostring(math.floor(tonumber(target.production) or 0))..
			" criticalDefenders="..tostring(target.criticalDefenders or 0)..
			" slots="..tostring(operation.assignmentDebug or "").." capacities="..table.concat(capacityParts, ","))
	end
	local deficitParts = {}
	for need, target in pairs(plan.forceTargets) do
		local current = world.counts[need] or 0
		if target > current then table.insert(deficitParts, need..":"..tostring(current).."/"..tostring(target)) end
	end
	table.sort(deficitParts)
	SC_Debug("strategyPlan turn="..tostring(plan.turn).." reason="..tostring(reason)..
		" posture="..tostring(plan.posture).." powerRatio="..string.format("%.2f", plan.powerRatio)..
		" defensiveRatio="..string.format("%.2f", plan.defensivePowerRatio or 0)..
		" offensiveRatio="..string.format("%.2f", plan.offensivePowerRatio or 0)..
		" victory="..tostring(plan.national and plan.national.victory or "balanced")..
		" crisis="..tostring(plan.national and plan.national.crisis or "stable")..
		" ownCombat="..tostring(world.combatUnits).." enemyCombat="..tostring(world.enemyCombatUnits)..
		" ownPower="..tostring(math.floor(world.combatPower)).." immediateEnemyPower="..tostring(math.floor(plan.immediateEnemyPower or 0))..
		" assignedCombat="..tostring(plan.assignedCombat or 0).." reserveCombat="..tostring(plan.reserveCombat or world.combatUnits)..
		" operationCap="..tostring(plan.maxOperations or 0)..
		" assaultCap="..tostring(plan.offensiveLimit or 0)..
		" targetForce="..tostring(plan.forceTargetTotal or 0)..
		" casualtyRate="..string.format("%.3f", plan.casualtyRate or 0)..
		" directLosses="..tostring(plan.directLosses or 0)..
		" forceDrawdown="..string.format("%.3f", plan.forceDrawdown or 0)..
		" enemyCountRatio="..string.format("%.2f", plan.enemyCountRatio or 0)..
		" reserveGold="..tostring(plan.reserveGold or 0).." spendableGold="..tostring(plan.national and plan.national.spendableGold or 0)..
		" operations="..table.concat(targetParts, ",").." rejected="..table.concat(plan.rejectedOperations or {}, "|")..
		" deficits="..table.concat(deficitParts, ",").." tasks="..SC_StrategyTaskMetricsDebug())
	return plan
end

function SC_StrategyGetNationalPlan()
	return SC_STRATEGY_STATE.national, SC_STRATEGY_STATE.plan
end

function SC_StrategyGetUnitTask(unit)
	local key = SC_StrategyUnitKey(unit)
	return key ~= nil and SC_STRATEGY_STATE.unitTasks[key] or nil
end

function SC_StrategyGetUnitTaskDebug(unit)
	local task = SC_StrategyGetUnitTask(unit)
	if task == nil then return "unowned" end
	return tostring(task.kind)..":"..tostring(task.operationID or "-")..":"..tostring(task.slot or "-")..
		":"..tostring(task.phase or "-")..":"..tostring(task.reason or "-")
end

function SC_StrategyUnitAllowsModule(unit, moduleName)
	local task = SC_StrategyGetUnitTask(unit)
	if task == nil then return true, "legacy-unowned" end
	if moduleName == "healing" then return task.kind == "recovery", task.kind end
	if moduleName == "airRebase" then
		return true, task.kind
	end
	if moduleName == "strategicMovement" then
		-- The national plan supplies target preference, never an execution veto.
		return true, task.kind
	end
	if moduleName == "localDefense" then
		local specialInfo = unit and GameInfo.Units[unit:GetUnitType()] or nil
		if specialInfo ~= nil and (specialInfo.Type == "UNIT_PARTICLE_CANNON"
			or specialInfo.Type == "UNIT_PROTON_COLLIDER_VESSEL") then
			return false, "special_weapon"
		end
		return true, task.kind
	end
	if moduleName == "greatPeople" then return task.kind == "great_person", task.kind end
	if moduleName == "tradeRoutes" then return task.kind == "trade", task.kind end
	if moduleName == "worker" then return task.kind == "improve", task.kind end
	return true, task.kind
end

function SC_StrategyRecordTaskAction(unit, moduleName, outcome)
	local task = SC_StrategyGetUnitTask(unit)
	if task == nil then return end
	task.actions = (task.actions or 0) + 1
	task.lastModule = moduleName
	task.lastOutcome = outcome
end

function SC_StrategyAdjustBuildingWeights(city, weights)
	local national = SC_STRATEGY_STATE.national
	if weights == nil or national == nil then return weights end
	local p = national.priorities or {}
	weights.FLAVOR_PRODUCTION = (weights.FLAVOR_PRODUCTION or 0) * (p.production or 1)
	weights.YIELD_PRODUCTION = (weights.YIELD_PRODUCTION or 0) * (p.production or 1)
	weights.FLAVOR_SCIENCE = (weights.FLAVOR_SCIENCE or 0) * (p.science or 1)
	weights.YIELD_SCIENCE = (weights.YIELD_SCIENCE or 0) * (p.science or 1)
	weights.FLAVOR_GOLD = (weights.FLAVOR_GOLD or 0) * (p.gold or 1)
	weights.YIELD_GOLD = (weights.YIELD_GOLD or 0) * (p.gold or 1)
	weights.FLAVOR_GROWTH = (weights.FLAVOR_GROWTH or 0) * (p.growth or 1)
	weights.YIELD_FOOD = (weights.YIELD_FOOD or 0) * (p.growth or 1)
	weights.FLAVOR_HAPPINESS = (weights.FLAVOR_HAPPINESS or 0) * (p.happiness or 1)
	weights.FLAVOR_CITY_DEFENSE = (weights.FLAVOR_CITY_DEFENSE or 0) * (p.defense or 1)
	weights.FLAVOR_MILITARY_TRAINING = (weights.FLAVOR_MILITARY_TRAINING or 0) * (p.military or 1)
	return weights
end

function SC_StrategyGetMinimumBuildingScore(city, defaultScore)
	local role = SC_StrategyGetCityRole(city)
	local national = SC_STRATEGY_STATE.national
	local score = tonumber(defaultScore) or 40
	if role == "growth" or role == "frontier" or role == "capital" then score = score - 12 end
	if national ~= nil and national.crisis == "deficit" then score = score + 18 end
	return math.max(12, score)
end

function SC_StrategyGetProcessChoice(player, city, reservedOrders)
	local national = SC_STRATEGY_STATE.national
	local role = SC_StrategyGetCityRole(city)
	local process = "PROCESS_WEALTH"
	local reason = "economic-buffer"
	if national ~= nil and national.crisis == "deficit" then process, reason = "PROCESS_WEALTH", "national-deficit"
	elseif national ~= nil and national.victory == "science" and role ~= "finance" then process, reason = "PROCESS_RESEARCH", "science-route"
	elseif role == "science" then process, reason = "PROCESS_RESEARCH", "science-city"
	elseif role == "industrial" and national ~= nil and national.victory == "conquest" then process, reason = "PROCESS_WEALTH", "war-reserve" end
	return process, reason
end

function SC_StrategyGetCapitalDeployment(player, atWar)
	local national = SC_STRATEGY_STATE.national
	local plan = SC_STRATEGY_STATE.plan
	local world = SC_STRATEGY_STATE.world
	if national == nil or plan == nil or world == nil then return false, 0, 0, "no-plan", 0 end
	if not atWar or #(world.enemyCities or {}) <= 0 then return false, 0, 0, "no-active-war", 0 end
	local actualGold = SC_StrategySafe(function() return player:GetGold() end, world.gold or 0)
	local actualGoldRate = SC_StrategySafe(function() return player:CalculateGoldRate() end, world.goldRate or 0)
	local actualHappiness = SC_StrategySafe(function() return player:GetExcessHappiness() end, world.happiness or 0)
	local spendable = math.max(0, actualGold - (national.reserveGold or 0))
	local minimumSurplus = math.max(SC_StrategyConfig("CapitalDeploymentMinimumSurplus", 50000), 1)
	if spendable < minimumSurplus then return false, 0, 0, "surplus-below-threshold", 0 end
	local deficitRunway = actualGoldRate < 0 and spendable / math.max(-actualGoldRate, 1) or 9999
	if actualGoldRate < SC_StrategyConfig("CapitalDeploymentMinimumGoldRate", 25)
		and deficitRunway < SC_StrategyConfig("CapitalDeploymentDeficitRunwayTurns", 40) then
		return false, 0, 0, "deficit-runway:"..string.format("%.1f", deficitRunway), 0
	end

	local cityTarget = #(world.ownCities or {}) * 2
	local averageOwnPower = (world.combatPower or 0) / math.max(world.combatUnits or 0, 1)
	local theaterEnemyPower = math.max(tonumber(plan.immediateEnemyPower) or 0, 0)
	for _, operation in ipairs(plan.operations or {}) do
		local target = operation.target or {}
		theaterEnemyPower = math.max(theaterEnemyPower, tonumber(target.enemyPower) or 0)
	end
	local enemyEquivalent = math.ceil(theaterEnemyPower / math.max(averageOwnPower, 1)
		* SC_StrategyConfig("CapitalForceEnemyRatio", 1.35))
	local desiredForce = math.max(cityTarget, enemyEquivalent, plan.forceTargetTotal or 0)
	local shortage = math.max(desiredForce - (world.combatUnits or 0), 0)
	if shortage <= 0 then return false, 0, desiredForce, "capital-force-ceiling", 0 end
	local wealthQuota = math.max(1, math.ceil(spendable / minimumSurplus))
	local shortageQuota = math.max(1, math.ceil(shortage / 4))
	local quota = math.min(SC_StrategyConfig("CapitalMilitaryPurchasesPerTurn", 10), wealthQuota, shortageQuota)
	return quota > 0, quota, desiredForce,
		"capital-deployment spendable="..tostring(math.floor(spendable))..
		" runway="..string.format("%.1f", deficitRunway).." happiness="..tostring(actualHappiness)..
		" theaterEnemyPower="..tostring(math.floor(theaterEnemyPower))..
		" globalEnemyPower="..tostring(math.floor(world.enemyCombatPower or 0))..
		" enemyEquivalent="..tostring(enemyEquivalent)..
		" force="..tostring(world.combatUnits or 0).."/"..tostring(desiredForce), shortage
end

function SC_StrategyGetMilitaryPurchaseBudget(player, atWar)
	local national = SC_STRATEGY_STATE.national
	if national == nil then return nil end
	local plan = SC_STRATEGY_STATE.plan
	local deficit = 0
	local world = SC_STRATEGY_STATE.world
	if plan ~= nil and world ~= nil then
		for need, target in pairs(plan.forceTargets or {}) do deficit = deficit + math.max(target - (world.counts[need] or 0), 0) end
	end
	local capitalEnabled, capitalQuota, desiredForce, capitalReason = SC_StrategyGetCapitalDeployment(player, atWar)
	if deficit <= 0 and not capitalEnabled then return national.reserveGold, 0, 0, "force-balanced:"..tostring(capitalReason) end
	local fraction = national.militaryPurchaseFraction or (atWar and 0.20 or 0.05)
	if capitalEnabled then fraction = math.max(fraction, SC_StrategyConfig("CapitalMilitaryPurchaseFraction", 0.42)) end
	local actualGold = SC_StrategySafe(function() return player:GetGold() end, 0)
	local spendable = math.max(0, actualGold - (national.reserveGold or 0))
	local budget = math.floor(spendable * fraction)
	local maxPurchases = math.max(1, math.min(SC_StrategyConfig("MilitaryPurchaseMaxPerTurn", 10), math.ceil(deficit / 2)))
	if capitalEnabled then maxPurchases = math.max(maxPurchases, capitalQuota) end
	return national.reserveGold, budget, maxPurchases,
		"victory="..tostring(national.victory).." crisis="..tostring(national.crisis).." deficit="..tostring(deficit)..
		" capital="..tostring(capitalEnabled).." desiredForce="..tostring(desiredForce).." reason="..tostring(capitalReason)
end

function SC_StrategyGetMilitaryNeed(player, city, atWar, reservedOrders, excludedNeeds)
	local plan = SC_StrategyBuildPlan(player, atWar, false)
	local world = SC_STRATEGY_STATE.world
	if plan == nil or world == nil or not atWar then return nil, 0, "strategy-peace" end
	local coastal = SC_StrategySafe(function() return city ~= nil and city:IsCoastal() end, false)
	local priority = {
		rapid_capture = 125, line_frontline = 85, siege = 115, air_superiority = 135,
		carrier_air = 130, air_strike = 145, naval_screen = 150, naval_fire = 140,
		fleet_carrier = 105, strategic_submarine = 75, missile_strike = 55
	}
	if plan.posture == "defend" then
		priority.line_frontline = 155; priority.air_superiority = 165; priority.naval_screen = 165
	elseif plan.posture == "decapitation" then
		priority.rapid_capture = 175; priority.air_strike = 180; priority.siege = 150
	end
	local capitalEnabled, _, desiredForce, capitalReason = SC_StrategyGetCapitalDeployment(player, atWar)
	local capitalScale = capitalEnabled and math.max(1, desiredForce / math.max(plan.forceTargetTotal or 0, 1)) or 1
	local bestNeed, bestScore, bestDeficit = nil, -999999, 0
	local parts = {}
	for need, baseTarget in pairs(plan.forceTargets) do
		local target = baseTarget
		if capitalEnabled then target = math.ceil(baseTarget * capitalScale) end
		local queued = reservedOrders ~= nil and (tonumber(reservedOrders["NEED:"..need]) or 0) or 0
		local current = world.counts[need] or 0
		local deficit = target - current - queued
		local domain = SC_GetProductionNeedDomain ~= nil and SC_GetProductionNeedDomain(need) or "land"
		local allowed = domain ~= "sea" or coastal
		local score = (priority[need] or 50) + math.max(deficit, 0) * 100 / math.max(target, 1)
		if current > target * 1.5 then score = score - 500 end
		table.insert(parts, need..":"..tostring(current).."+"..tostring(queued).."/"..tostring(target).."@"..tostring(math.floor(score)))
		if deficit > 0 and allowed and not (excludedNeeds ~= nil and excludedNeeds[need]) and score > bestScore then
			bestNeed, bestScore, bestDeficit = need, score, deficit
		end
	end
	table.sort(parts)
	return bestNeed, bestDeficit, "nationalPlan="..plan.posture.." choice="..tostring(bestNeed).." score="..tostring(math.floor(bestScore))..
		" capital="..tostring(capitalEnabled).." capitalReason="..tostring(capitalReason).." "..table.concat(parts, ",")
end

function SC_StrategyScoreUnit(player, city, unitInfo, needKey, baseScore)
	local world = SC_STRATEGY_STATE.world
	local plan = SC_STRATEGY_STATE.plan
	if world == nil or plan == nil or unitInfo == nil then return baseScore, "no-plan" end
	local need = SC_StrategyUnitNeed(unitInfo)
	local score = baseScore or 0
	local reason = "balanced"
	if need ~= nil then
		local current = world.counts[need] or 0
		local target = plan.forceTargets[need] or 0
		if needKey ~= nil and need == needKey then score = score + 900 end
		if target > current then
			score = score + (target - current) * 90
			reason = "deficit:"..need..":"..tostring(current).."/"..tostring(target)
		elseif current > math.max(target * 1.35, target + 3) then
			score = score - 2400
			reason = "overcap:"..need..":"..tostring(current).."/"..tostring(target)
		end
	end
	return score, reason
end

function SC_StrategyGetCityRole(city)
	local key = tostring(SC_StrategySafe(function() return city:GetID() end, -1))
	local entry = SC_STRATEGY_STATE.cityRoles[key]
	return entry ~= nil and entry.role or "balanced"
end

function SC_StrategyGetCivilianProductionNeed(player, reservedOrders)
	local world = SC_STRATEGY_STATE.world
	local plan = SC_STRATEGY_STATE.plan
	if world == nil or plan == nil then return nil, 0, "no-plan" end
	local workers, settlers = 0, 0
	for _, entry in ipairs(world.ownUnits) do
		local class = entry.profile and entry.profile.doctrineClass or ""
		if class == "civilian_builder" and entry.info ~= nil and entry.info.DefaultUnitAI == "UNITAI_WORKER" then workers = workers + 1 end
		if class == "civilian_settler" then settlers = settlers + 1 end
	end
	local national = SC_STRATEGY_STATE.national
	local expansionPriority = national and national.priorities and national.priorities.expansion or 0
	local workerDivisor = expansionPriority >= 1 and 2 or (plan.posture == "decapitation" and 4 or 3)
	local workerTarget = math.max(1, math.ceil(#world.ownCities / workerDivisor))
	local workerReserved = reservedOrders ~= nil and (tonumber(reservedOrders["CIVILIAN:worker"]) or 0) or 0
	local settlerReserved = reservedOrders ~= nil and (tonumber(reservedOrders["CIVILIAN:settler"]) or 0) or 0
	local expansion = SC_StrategyConfig("EconomyProfile", "BALANCED") == "EXPANSION" or expansionPriority >= 1
	local expansionSafe = world.happiness >= 5 and world.goldRate >= 0 and plan.posture ~= "defend"
	if expansion and expansionSafe and settlers + settlerReserved < 1 then
		return "settler", 1, "expansion-safe happiness="..tostring(world.happiness).." goldRate="..tostring(world.goldRate)
	end
	if workers + workerReserved < workerTarget then
		return "worker", workerTarget - workers - workerReserved, "worker-deficit="..tostring(workers + workerReserved).."/"..tostring(workerTarget)
	end
	return nil, 0, "civilian-balanced workers="..tostring(workers).."/"..tostring(workerTarget).." settlers="..tostring(settlers)
end

local function SC_StrategyBuildingYields(buildingType)
	if SC_STRATEGY_STATE.buildingYieldCache[buildingType] ~= nil then
		return SC_STRATEGY_STATE.buildingYieldCache[buildingType]
	end
	local data = {
		yields = { food = 0, production = 0, gold = 0, science = 0, culture = 0 },
		perPop = { food = 0, production = 0, gold = 0, science = 0, culture = 0 },
		resourceUtility = 0
	}
	local names = {
		YIELD_FOOD = "food", YIELD_PRODUCTION = "production", YIELD_GOLD = "gold",
		YIELD_SCIENCE = "science", YIELD_CULTURE = "culture"
	}
	local function addRows(tableName, field, multiplier)
		if GameInfo == nil or GameInfo[tableName] == nil then return end
		pcall(function()
			for row in GameInfo[tableName]{ BuildingType = buildingType } do
				local key = names[row.YieldType]
				if key ~= nil then data.yields[key] = data.yields[key] + (tonumber(row[field]) or 0) * multiplier end
			end
		end)
	end
	addRows("Building_YieldChanges", "Yield", 1)
	addRows("Building_YieldModifiers", "Yield", 0.12)
	-- Conditional tile/resource/specialist yields are discounted because not
	-- every city can work every affected source, but ignoring them entirely
	-- made several late-game economic buildings look worthless.
	addRows("Building_ResourceYieldChanges", "Yield", 0.18)
	addRows("Building_SpecialistYieldChanges", "Yield", 0.35)
	addRows("Building_TerrainYieldChanges", "Yield", 0.14)
	addRows("Building_FeatureYieldChanges", "Yield", 0.14)
	pcall(function()
		for row in GameInfo.Building_YieldChangesPerPop{ BuildingType = buildingType } do
			local key = names[row.YieldType]
			if key ~= nil then data.perPop[key] = data.perPop[key] + (tonumber(row.Yield) or 0) / 100 end
		end
	end)
	pcall(function()
		for row in GameInfo.Building_ResourceQuantity{ BuildingType = buildingType } do
			local quantity = math.max(tonumber(row.Quantity) or 0, 0)
			data.resourceUtility = data.resourceUtility + math.sqrt(quantity) * 30
		end
	end)
	for key, value in pairs(data.yields) do data.yields[key] = math.max(-10, math.min(value, 10)) end
	SC_STRATEGY_STATE.buildingYieldCache[buildingType] = data
	return data
end

function SC_StrategyScoreBuilding(player, city, building, baseScore, purchased)
	if city == nil or building == nil then return baseScore or 0, "missing" end
	if SC5 then return SC5.ScoreBuilding(player, city, building, purchased) end
	local role = SC_StrategyGetCityRole(city)
	local yieldData = SC_StrategyBuildingYields(building.Type)
	local population = SC_StrategySafe(function() return city:GetPopulation() end, 1)
	local score = baseScore or 0
	local weights = { food = 20, production = 25, gold = 16, science = 22, culture = 10 }
	if role == "industrial" then weights.production = 42
	elseif role == "science" then weights.science = 42
	elseif role == "finance" then weights.gold = 38
	elseif role == "growth" then weights.food = 38
	elseif role == "frontier" then score = score + (tonumber(building.Defense) or 0) / 20
	elseif role == "naval_base" then score = score + (tonumber(building.Experience) or 0) * 1.5 end
	for key, value in pairs(yieldData.yields) do score = score + value * (weights[key] or 0) end
	for key, value in pairs(yieldData.perPop) do score = score + value * population * (weights[key] or 0) end
	score = score + yieldData.resourceUtility
	score = score + (tonumber(building.Happiness) or 0) * (SC_STRATEGY_STATE.world and SC_STRATEGY_STATE.world.happiness < 5 and 55 or 24)
	score = score + (tonumber(building.GreatPeopleRateChange) or 0) * math.max(population, 1) / 4
	score = score + math.max(tonumber(building.SpecialistCount) or 0, 0) * 28
	score = score + math.max(tonumber(building.NumTradeRouteBonus) or 0, 0) * 180
	score = score + math.max(tonumber(building.MilitaryProductionModifier) or 0, 0) * 4
	local occupied = SC_StrategySafe(function() return city:IsOccupied() end, false)
	local removesOccupation = building.NoOccupiedUnhappiness == true or tonumber(building.NoOccupiedUnhappiness) == 1
	if occupied and removesOccupation then score = score + 3200 end
	if tonumber(building.Airlift) == 1 then score = score + (SC_STRATEGY_STATE.world and SC_STRATEGY_STATE.world.atWar and 900 or 320) end
	if SC_STRATEGY_STATE.world and SC_STRATEGY_STATE.world.atWar then
		score = score + math.max(tonumber(building.Experience) or 0, 0) * 4
		score = score + math.max(tonumber(building.Defense) or 0, 0) / 12
	end
	local cost = math.max(tonumber(building.Cost) or 0, 0)
	local cityProduction = math.max(SC_StrategyGetYield(city, "YIELD_PRODUCTION"), 1)
	score = score - math.min(cost / cityProduction, 80) * 3
	score = score - math.max(tonumber(building.GoldMaintenance) or 0, 0) * 12
	return score, "role="..role.." costTurns="..tostring(math.floor(cost / cityProduction))..
		" resourceUtility="..tostring(math.floor(yieldData.resourceUtility))
end

local function SC_StrategyBuildUnlockCache()
	if SC_STRATEGY_STATE.unlockCache ~= nil then return SC_STRATEGY_STATE.unlockCache end
	local cache = { tech = {}, successors = {} }
	local function techEntry(techType)
		if techType == nil or techType == "" then return nil end
		cache.tech[techType] = cache.tech[techType] or { units = {}, buildings = {}, projects = {}, flavors = {} }
		return cache.tech[techType]
	end
	pcall(function()
		for unit in GameInfo.Units() do
			local entry = techEntry(unit.PrereqTech)
			if entry ~= nil then table.insert(entry.units, unit) end
		end
		for building in GameInfo.Buildings() do
			local entry = techEntry(building.PrereqTech)
			if entry ~= nil then table.insert(entry.buildings, building) end
		end
		for project in GameInfo.Projects() do
			local entry = techEntry(project.TechPrereq)
			if entry ~= nil then table.insert(entry.projects, project) end
		end
		for flavor in GameInfo.Technology_Flavors() do
			local entry = techEntry(flavor.TechType)
			if entry ~= nil then entry.flavors[flavor.FlavorType] = (entry.flavors[flavor.FlavorType] or 0) + (tonumber(flavor.Flavor) or 0) end
		end
		for row in GameInfo.Technology_PrereqTechs() do
			cache.successors[row.PrereqTech] = cache.successors[row.PrereqTech] or {}
			table.insert(cache.successors[row.PrereqTech], row.TechType)
		end
	end)
	SC_STRATEGY_STATE.unlockCache = cache
	return cache
end

local function SC_StrategyTechDirectValue(cache, techType)
	local entry = cache.tech[techType] or { units = {}, buildings = {}, projects = {}, flavors = {} }
	local plan = SC_STRATEGY_STATE.plan
	local world = SC_STRATEGY_STATE.world
	local player = world and Players[world.playerID]
	local score, availableUnits, availableBuildings = #entry.projects * 80, 0, 0
	for _, building in ipairs(entry.buildings) do
		if SC5 == nil or SC5.CivilizationUnlock(player, building, "building") then
			score = score + 35
			availableBuildings = availableBuildings + 1
		end
	end
	for _, unit in ipairs(entry.units) do
		if SC5 == nil or SC5.CivilizationUnlock(player, unit, "unit") then
		local power = math.max(tonumber(unit.Combat) or 0, tonumber(unit.RangedCombat) or 0)
		local need = SC_StrategyUnitNeed(unit)
		local unlockValue = math.sqrt(power) * 16
		if unit.ProjectPrereq ~= nil and unit.ProjectPrereq ~= "" then unlockValue = unlockValue * 0.5 end
		score = score + unlockValue
		availableUnits = availableUnits + 1
		if plan ~= nil and world ~= nil and need ~= nil and (world.counts[need] or 0) < (plan.forceTargets[need] or 0) then score = score + 160 end
		end
	end
	local doctrine = SC_StrategyConfig("Doctrine", "BALANCED")
	local national = SC_STRATEGY_STATE.national
	local priorities = national and national.priorities or {}
	for flavor, value in pairs(entry.flavors) do
		local weight = 2
		if doctrine == "WAR" and (flavor == "FLAVOR_OFFENSE" or flavor == "FLAVOR_DEFENSE" or flavor == "FLAVOR_AIR" or flavor == "FLAVOR_NAVAL") then weight = 8
		elseif doctrine == "SCIENCE" and flavor == "FLAVOR_SCIENCE" then weight = 9
		elseif doctrine == "INDUSTRY" and flavor == "FLAVOR_PRODUCTION" then weight = 9 end
		if flavor == "FLAVOR_SCIENCE" then weight = weight * (priorities.science or 1)
		elseif flavor == "FLAVOR_PRODUCTION" then weight = weight * (priorities.production or 1)
		elseif flavor == "FLAVOR_GOLD" then weight = weight * (priorities.gold or 1)
		elseif flavor == "FLAVOR_GROWTH" then weight = weight * (priorities.growth or 1)
		elseif flavor == "FLAVOR_HAPPINESS" then weight = weight * (priorities.happiness or 1)
		elseif flavor == "FLAVOR_OFFENSE" or flavor == "FLAVOR_DEFENSE" or flavor == "FLAVOR_AIR" or flavor == "FLAVOR_NAVAL" then weight = weight * (priorities.military or 1) end
		score = score + value * weight
	end
	return score, availableUnits, availableBuildings, #entry.projects
end

local function SC_StrategyTechUnlockValue(techType)
	local cache = SC_StrategyBuildUnlockCache()
	local score, units, buildings, projects = SC_StrategyTechDirectValue(cache, techType)
	local visited = { [techType] = 0 }
	local queue = { { type = techType, depth = 0 } }
	local head = 1
	local discounts = { [1] = 0.35, [2] = 0.15, [3] = 0.07 }
	while head <= #queue do
		local current = queue[head]
		head = head + 1
		if current.depth < 3 then
			for _, successor in ipairs(cache.successors[current.type] or {}) do
				local nextDepth = current.depth + 1
				if visited[successor] == nil or nextDepth < visited[successor] then
					visited[successor] = nextDepth
					table.insert(queue, { type = successor, depth = nextDepth })
				end
			end
		end
	end
	for successor, depth in pairs(visited) do
		if successor ~= techType and depth > 0 and depth <= 3 then
			local successorScore = SC_StrategyTechDirectValue(cache, successor)
			score = score + successorScore * (discounts[depth] or 0)
		end
	end
	return score, units, buildings, projects
end

function SC_StrategyScoreResearch(player, tech, turns, baseScore)
	if tech == nil then return baseScore or 0, "missing" end
	local unlock, units, buildings, projects = SC_StrategyTechUnlockValue(tech.Type)
	local score = (baseScore or 0) + unlock / (1 + math.max(turns or 1, 1) / 8)
	local reason = "unlock="..tostring(math.floor(unlock)).." units="..tostring(units).." buildings="..tostring(buildings).." projects="..tostring(projects).." turns="..tostring(turns)
	table.insert(SC_STRATEGY_STATE.researchCandidates, { type = tech.Type, score = score, reason = reason })
	return score, reason
end

function SC_StrategyLogResearchChoice(techID)
	local candidates = SC_STRATEGY_STATE.researchCandidates or {}
	table.sort(candidates, function(a, b) return a.score > b.score end)
	local parts = {}
	for i = 1, math.min(#candidates, 5), 1 do
		table.insert(parts, candidates[i].type..":"..tostring(math.floor(candidates[i].score)).."["..candidates[i].reason.."]")
	end
	local chosen = SC_StrategyInfo("Technologies", techID)
	SC_Debug("researchDecision chosen="..tostring(chosen and chosen.Type or techID).." candidates="..table.concat(parts, ";"))
	SC_STRATEGY_STATE.researchCandidates = {}
end

function SC_StrategyScorePolicy(player, policy, baseScore)
	if policy == nil then return baseScore or 0, "missing" end
	local world = SC_STRATEGY_STATE.world
	local plan = SC_STRATEGY_STATE.plan
	local national = SC_STRATEGY_STATE.national
	local priorities = national and national.priorities or {}
	local cityCount = world ~= nil and #world.ownCities or 1
	local score = baseScore or 0
	local fields = {
		Happiness = 45, ExtraHappiness = 45, HappinessPerCity = 30 * cityCount,
		CulturePerCity = 10 * cityCount, GoldPerUnit = 5, UnitGoldMaintenanceMod = -4,
		WorkerSpeedModifier = 2, ImprovementCostModifier = -2, PlotGoldCostMod = -2,
		MilitaryProductionModifier = plan ~= nil and plan.posture ~= "peace" and 5 or 2,
		UnitPurchaseCostModifier = -4, FreeExperience = 3, ExperienceModifier = 3,
		GreatPeopleRateModifier = 3, PolicyCostModifier = -5, TechCostModifier = -5
	}
	for field, weight in pairs(fields) do score = score + (tonumber(policy[field]) or 0) * weight end
	if SC5 then score = score + SC5.PolicyYieldValue(player, policy) end
	local flavorWeights = {
		FLAVOR_SCIENCE = priorities.science or 1, FLAVOR_PRODUCTION = priorities.production or 1,
		FLAVOR_GOLD = priorities.gold or 1, FLAVOR_GROWTH = priorities.growth or 1,
		FLAVOR_HAPPINESS = priorities.happiness or 1, FLAVOR_OFFENSE = priorities.military or 1,
		FLAVOR_DEFENSE = priorities.defense or 1, FLAVOR_MILITARY_TRAINING = priorities.military or 1
	}
	pcall(function()
		for row in GameInfo.Policy_Flavors{ PolicyType = policy.Type } do
			score = score + (tonumber(row.Flavor) or 0) * 8 * (flavorWeights[row.FlavorType] or 0.6)
		end
	end)
	if world ~= nil and world.happiness < 5 then
		score = score + ((tonumber(policy.Happiness) or 0) + (tonumber(policy.ExtraHappiness) or 0)) * 70
	end
	local reason = "cities="..tostring(cityCount).." posture="..tostring(plan and plan.posture or "none").." victory="..tostring(national and national.victory or "balanced")
	table.insert(SC_STRATEGY_STATE.policyCandidates, { type = policy.Type, score = score, reason = reason })
	return score, reason
end

function SC_StrategyLogPolicyChoice(policyID)
	local candidates = SC_STRATEGY_STATE.policyCandidates or {}
	table.sort(candidates, function(a, b) return a.score > b.score end)
	local parts = {}
	for i = 1, math.min(#candidates, 5), 1 do
		table.insert(parts, candidates[i].type..":"..tostring(math.floor(candidates[i].score)))
	end
	local chosen = SC_StrategyInfo("Policies", policyID)
	SC_Debug("policyDecision chosen="..tostring(chosen and chosen.Type or policyID).." candidates="..table.concat(parts, ";"))
	SC_STRATEGY_STATE.policyCandidates = {}
end

function SC_StrategyScorePolicyBranch(player, branchInfo, baseScore)
	if branchInfo == nil then return baseScore or 0 end
	local branchType = branchInfo.Type or ""
	local plan = SC_STRATEGY_STATE.plan
	local world = SC_STRATEGY_STATE.world
	local doctrine = SC_StrategyConfig("Doctrine", "BALANCED")
	local national = SC_STRATEGY_STATE.national
	local score = baseScore or 0
	if branchType == "POLICY_BRANCH_RATIONALISM" then score = score + (doctrine == "SCIENCE" and 900 or 450) end
	if branchType == "POLICY_BRANCH_COMMERCE" then score = score + (world ~= nil and world.goldRate < 0 and 850 or 180) end
	if branchType == "POLICY_BRANCH_EXPLORATION" then
		local coastal = 0
		for _, city in ipairs(world and world.ownCities or {}) do
			if SC_StrategySafe(function() return city.city:IsCoastal() end, false) then coastal = coastal + 1 end
		end
		score = score + coastal * 90
	end
	if branchType == "POLICY_BRANCH_HONOR" then score = score + (plan ~= nil and plan.posture ~= "peace" and 650 or 50) end
	if branchType == "POLICY_BRANCH_AUTOCRACY" then score = score + (plan ~= nil and plan.posture == "decapitation" and 1000 or 200) end
	if branchType == "POLICY_BRANCH_ORDER" then score = score + (doctrine == "INDUSTRY" and 800 or 350) end
	if branchType == "POLICY_BRANCH_TRADITION" then score = score + (world ~= nil and #world.ownCities <= 5 and 700 or 100) end
	if national ~= nil and national.victory == "science" and branchType == "POLICY_BRANCH_RATIONALISM" then score = score + 700 end
	if national ~= nil and national.victory == "conquest" and (branchType == "POLICY_BRANCH_HONOR" or branchType == "POLICY_BRANCH_AUTOCRACY") then score = score + 650 end
	if national ~= nil and national.crisis == "deficit" and branchType == "POLICY_BRANCH_COMMERCE" then score = score + 850 end
	return score
end

function SC_StrategyScoreTradeRoute(player, route, baseScore)
	if route == nil then return baseScore or -999999, "missing" end
	local world = SC_STRATEGY_STATE.world
	local plot = nil
	pcall(function() plot = Map.GetPlot(route.X, route.Y) end)
	if world == nil or plot == nil then return baseScore or 0, "no-world" end
	local score = baseScore or 0
	local national = SC_STRATEGY_STATE.national
	local priorities = national and national.priorities or {}
	local owner = SC_StrategySafe(function() return plot:GetOwner() end, -1)
	local internal = owner == world.playerID
	local threatDistance = SC_StrategyNearestDistance(plot, world.enemyUnits)
	if world.atWar and threatDistance <= 5 then score = score - 6000 end
	if internal then
		local city = SC_StrategySafe(function() return plot:GetPlotCity() end, nil)
		local role = city ~= nil and SC_StrategyGetCityRole(city) or "balanced"
		if role == "frontier" then score = score + 1800 * (priorities.defense or 1)
		elseif role == "growth" then score = score + 900 * (priorities.growth or 1)
		elseif role == "industrial" then score = score + 500 * (priorities.production or 1) end
	elseif world.goldRate < 0 then
		score = score + 700 * (priorities.gold or 1)
	end
	return score, "internal="..tostring(internal).." threatDistance="..tostring(threatDistance)
end

local function SC_StrategyOperationForUnit(unit)
	local plan = SC_STRATEGY_STATE.plan
	if plan == nil or #plan.operations == 0 or unit == nil then return nil end
	local key = SC_StrategyUnitKey(unit)
	local existing = key ~= nil and SC_STRATEGY_STATE.assignments[key] or nil
	if existing == nil then return nil end
	for _, operation in ipairs(plan.operations) do
		if operation.id == existing.operationID then return operation end
	end
	return nil
end

local function SC_StrategyPrimaryOffensiveOperation()
	local plan = SC_STRATEGY_STATE.plan
	if plan == nil then return nil end
	local best, bestScore = nil, -999999
	local fallback, fallbackScore = nil, -999999
	for _, operation in ipairs(plan.operations or {}) do
		local operationScore = tonumber(operation.target and operation.target.score) or 0
		if operationScore > fallbackScore then fallback, fallbackScore = operation, operationScore end
		if operation.kind == "city_assault" then
			local phaseBonus = operation.phase == "exploit" and 4000
				or (operation.phase == "bombard" and 3000 or (operation.phase == "advance" and 2000 or 0))
			local score = phaseBonus + operationScore
			if score > bestScore then best, bestScore = operation, score end
		end
	end
	return best or fallback
end

function SC_StrategyGetPrimaryOffensiveTarget()
	local operation = SC_StrategyPrimaryOffensiveOperation()
	if operation == nil then return nil, nil, "no-operation" end
	return operation.target and operation.target.plot or nil, operation,
		operation.id..":"..tostring(operation.kind)..":"..tostring(operation.phase)
end

local function SC_StrategyAppendUnique(pool, bucket, item, seen)
	if item == nil then return end
	local key = bucket..":"..tostring(item)
	if not seen[key] then
		seen[key] = true
		table.insert(pool[bucket], item)
	end
end

local function SC_StrategyAppendFireEnvelope(unit, defaultPool, pool, seen)
	if unit == nil or defaultPool == nil then return 0, 0 end
	local unitPlot = SC_StrategySafe(function() return unit:GetPlot() end, nil)
	local info = unit and GameInfo.Units[unit:GetUnitType()] or nil
	local profile = SC_GetUnitCapabilityProfile ~= nil and SC_GetUnitCapabilityProfile(unit, info) or nil
	local range = math.max(tonumber(profile and profile.range) or 0,
		SC_StrategySafe(function() return unit:Range() end, 0))
	if unitPlot == nil or range <= 0 then return 0, 0 end
	local units, cities = 0, 0
	for _, enemyUnit in ipairs(defaultPool.units or {}) do
		local plot = SC_StrategySafe(function() return enemyUnit:GetPlot() end, nil)
		if plot ~= nil and SC_StrategyDistance(plot, unitPlot) <= range then
			SC_StrategyAppendUnique(pool, "units", enemyUnit, seen)
			units = units + 1
		end
	end
	for _, enemyCity in ipairs(defaultPool.cities or {}) do
		local plot = SC_StrategySafe(function() return enemyCity:Plot() end, nil)
		if plot ~= nil and SC_StrategyDistance(plot, unitPlot) <= range then
			SC_StrategyAppendUnique(pool, "cities", enemyCity, seen)
			cities = cities + 1
		end
	end
	return units, cities
end

function SC_StrategyGetTargetPoolForUnit(player, unit, defaultPool)
	if SCX_GetExecutionTargetPool ~= nil then
		return SCX_GetExecutionTargetPool(player, unit, "strategic", defaultPool)
	end
	local world = SC_STRATEGY_STATE.world
	local operation = SC_StrategyOperationForUnit(unit)
	if world == nil then return defaultPool, "legacy-no-world" end
	local borrowedOperation = false
	if operation == nil then
		local task = SC_StrategyGetUnitTask ~= nil and SC_StrategyGetUnitTask(unit) or nil
		if task ~= nil and task.kind == "strategic_reserve" then
			operation = SC_StrategyPrimaryOffensiveOperation()
			borrowedOperation = operation ~= nil
		end
	end
	if operation == nil then
		local reservePool = { cities = {}, units = {} }
		local seen = {}
		local unitPlot = SC_StrategySafe(function() return unit:GetPlot() end, nil)
		for _, entry in ipairs(world.enemyUnits) do
			if unitPlot ~= nil and SC_StrategyDistance(entry.plot, unitPlot) <= 4 then
				local liveUnit = SC_ResolveLiveUnit ~= nil and SC_ResolveLiveUnit(entry.ownerID, entry.unitID) or entry.unit
				SC_StrategyAppendUnique(reservePool, "units", liveUnit, seen)
			end
		end
		local fireUnits, fireCities = SC_StrategyAppendFireEnvelope(unit, defaultPool, reservePool, seen)
		return reservePool, "reserve-local:"..tostring(SC_STRATEGY_STATE.plan and SC_STRATEGY_STATE.plan.posture or "none")..
			":fireEnvelope="..tostring(fireUnits).."/"..tostring(fireCities)
	end
	local pool = { cities = {}, units = {} }
	local seen = {}
	if operation.kind == "city_assault" then
		local liveCity = nil
		local owner = Players ~= nil and Players[operation.target.ownerID or -1] or nil
		if owner ~= nil then pcall(function() liveCity = owner:GetCityByID(operation.target.cityID) end) end
		SC_StrategyAppendUnique(pool, "cities", liveCity, seen)
	elseif operation.kind == "city_defense" and operation.phase == "counterattack"
		and (tonumber(operation.target.localRatio) or 0) >= 1.05 then
		local bestCity, bestDistance = nil, 999
		for _, entry in ipairs(world.enemyCities) do
			local distance = SC_StrategyDistance(entry.plot, operation.target.plot)
			if distance <= 18 and distance < bestDistance then
				local owner = Players ~= nil and Players[entry.ownerID or -1] or nil
				local liveCity = nil
				if owner ~= nil then pcall(function() liveCity = owner:GetCityByID(entry.cityID) end) end
				if liveCity ~= nil then bestCity, bestDistance = liveCity, distance end
			end
		end
		SC_StrategyAppendUnique(pool, "cities", bestCity, seen)
	end
	local unitPlot = SC_StrategySafe(function() return unit:GetPlot() end, nil)
	local localRadius = math.max(6, SC_StrategyConfig("OperationLocalEnemyRadius", 10))
	for _, entry in ipairs(world.enemyUnits) do
		local objectiveRadius = operation.kind == "city_defense" and localRadius + 3 or localRadius
		if SC_StrategyDistance(entry.plot, operation.target.plot) <= objectiveRadius
			or (SC_StrategyDistance(entry.plot, unitPlot) <= math.floor(localRadius * 0.6)
				and SC_StrategyDistance(entry.plot, operation.target.plot) <= objectiveRadius + 4) then
			local liveUnit = SC_ResolveLiveUnit ~= nil and SC_ResolveLiveUnit(entry.ownerID, entry.unitID) or entry.unit
			SC_StrategyAppendUnique(pool, "units", liveUnit, seen)
		end
	end
	local fireUnits, fireCities = SC_StrategyAppendFireEnvelope(unit, defaultPool, pool, seen)
	return pool, (borrowedOperation and "strategic-reserve:" or "")..operation.id..":"..operation.kind..":"..operation.phase..
		":fireEnvelope="..tostring(fireUnits).."/"..tostring(fireCities)
end

function SC_StrategyGetOperationDebug(unit)
	local operation = SC_StrategyOperationForUnit(unit)
	if operation == nil then return "reserve" end
	local key = SC_StrategyUnitKey(unit)
	local assignment = key ~= nil and SC_STRATEGY_STATE.assignments[key] or nil
	return operation.id..":"..operation.kind..":"..operation.phase..":slot="..tostring(assignment and assignment.slot or "?")
end

function SC_StrategyGetOperationForUnit(unit)
	return SC_StrategyOperationForUnit(unit)
end

function SC_StrategyGetCombatTempo(unit)
	local operation = SC_StrategyOperationForUnit(unit)
	if operation == nil then return "reserve" end
	if operation.kind == "city_assault" and operation.phase ~= "assemble" then return "blitz" end
	if operation.kind == "city_defense" then return "defense" end
	return operation.phase or "operation"
end

function SC_StrategyInvalidate(reason)
	if SC_STRATEGY_STATE.plan ~= nil then SC_STRATEGY_STATE.previousPlan = SC_STRATEGY_STATE.plan end
	SC_STRATEGY_STATE.world = nil
	SC_STRATEGY_STATE.plan = nil
	SC_Debug("strategy invalidate reason="..tostring(reason))
end

SC_Debug("strategyCore loaded version="..SC_STRATEGY_VERSION)
