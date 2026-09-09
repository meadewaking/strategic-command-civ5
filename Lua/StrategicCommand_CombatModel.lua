-- Native combat previews and live decision facts. Never retain native unit handles.
function SC5.Safe(callback, fallback)
	local ok, value = pcall(callback)
	if ok and value ~= nil then return value end
	return fallback
end

function SC5.Info(unit)
	return unit and GameInfo.Units[unit:GetUnitType()] or nil
end

function SC5.HP(entity)
	local maximum = math.max(SC5.Safe(function() return entity:GetMaxHitPoints() end, 100), 1)
	return math.max(0, maximum - entity:GetDamage()), maximum
end

function SC5.Value(unit)
	local info = SC5.Info(unit) or {}
	local profile = SC_GetUnitCapabilityProfile(unit, info)
	local cost = math.max(tonumber(info.Cost) or 0, (profile.power or 0) * 2, 40)
	local cargo = SC5.Safe(function() return unit:GetCargo() end, 0)
	local elite = SC_IsEliteUnitInfo and SC_IsEliteUnitInfo(info)
	return cost * (elite and 1.5 or 1) + cargo * cost * 0.5
end

function SC5.LiveProfile(unit, base)
	if not unit then return base end
	local range = SC5.Safe(function() return unit:Range() end, base.range)
	local moves = SC5.Safe(function() return unit:MaxMoves() / (GameDefines.MOVE_DENOMINATOR or 60) end, base.moves)
	local noCapture = SC5.Safe(function() return unit:IsNoCapture() end, base.noCapture)
	local maxHP = SC5.Safe(function() return unit:GetMaxHitPoints() end, base.maxHP)
	if range == base.range and moves == base.moves and noCapture == base.noCapture and maxHP == base.maxHP then return base end
	local result = {}
	for key, value in pairs(base) do result[key] = value end
	result.range, result.moves, result.noCapture = range, moves, noCapture
	result.maxHP = maxHP
	result.canCapture = base.canCapture and not noCapture
	return result
end

function SC5.ObservedUnit(player, unit)
	if player == nil or unit == nil then return false end
	local plot = unit:GetPlot()
	if plot == nil then return false end
	return SC5.Safe(function() return plot:IsVisible(player:GetTeam(), false) end, false)
		and not SC5.Safe(function() return unit:IsInvisible(player:GetTeam(), false) end, false)
end

function SC5.ObservedCity(player, city)
	local plot = city and city:Plot()
	return plot ~= nil and SC5.Safe(function() return plot:IsRevealed(player:GetTeam(), false) end, false)
end

function SC5.Preview(unit, enemy, city, melee)
	if unit == nil or (enemy == nil and city == nil) then return nil, "missing-target" end
	local target = city or enemy
	local targetPlot = city and city:Plot() or enemy:GetPlot()
	local source = unit:GetPlot()
	if targetPlot == nil or source == nil then return nil, "missing-plot" end
	local damage, retaliation
	local uncertainty = 0
	local confidence = "native"
	local info = SC5.Info(unit) or {}
	if melee then
		local attack = SC5.Safe(function() return unit:GetMaxAttackStrength(source, targetPlot, enemy) end, nil)
		local defense = city and SC5.Safe(function() return city:GetStrengthValue() end, nil)
			or SC5.Safe(function() return enemy:GetMaxDefenseStrength(targetPlot, unit) end, nil)
		if attack and defense and attack > 0 and defense > 0 then
			damage = SC5.Safe(function()
				return unit:GetCombatDamage(attack, defense, unit:GetDamage(), false, false, city ~= nil)
			end, nil)
			retaliation = SC5.Safe(function()
				return unit:GetCombatDamage(defense, attack, target:GetDamage(), false, city ~= nil, false)
			end, nil)
		end
	else
		damage = SC5.Safe(function() return unit:GetRangeCombatDamage(enemy, city, false) end, nil)
		retaliation = 0
		if info.Domain == "DOMAIN_AIR" then
			retaliation = SC5.Safe(function() return target:GetAirStrikeDefenseDamage(unit, false) end, nil)
			local interceptor = SC5.Safe(function() return unit:GetBestInterceptor(targetPlot, enemy, false, true) end, nil)
			if interceptor ~= nil and retaliation ~= nil then
				-- This DLL does not expose interception damage. Keep an explicit
				-- uncertainty allowance instead of inventing a Lua API.
				uncertainty = 25
				confidence = "native+interceptor-bound"
			end
		end
	end
	if damage == nil or retaliation == nil then return nil, "preview-unavailable" end
	local targetHP, targetMaxHP = SC5.HP(target)
	local hp, maxHP = SC5.HP(unit)
	-- Installed NewCombatRules.lua explicitly grants this effect, except mech vs mech.
	if info.Type == "UNIT_MECH" and (city ~= nil or (SC5.Info(enemy) or {}).Type ~= "UNIT_MECH") then
		damage = targetHP
		confidence = "native+mech-script"
	end
	return {
		damage = math.max(damage, 0), retaliation = math.max(retaliation, 0),
		uncertainty = uncertainty,
		hp = hp, maxHP = maxHP, targetHP = targetHP, targetMaxHP = targetMaxHP,
		confidence = confidence,
	}
end

function SC5.CanFinishCity(player, unit, city)
	if not unit or not city or not unit:CanMove() then return false end
	if SC5.IsWithdrawing(unit) then return false end
	local info = SC5.Info(unit)
	if not SC_IsDedicatedCityCaptureUnit(unit, info) then return false end
	local source, target = unit:GetPlot(), city:Plot()
	if not source or not target then return false end
	-- A one-turn geometric bound only generates candidates. The native mission
	-- decides actual reachability; failed destinations are excluded for this turn.
	local distance = Map.PlotDistance(source:GetX(), source:GetY(), target:GetX(), target:GetY())
	if distance > SC_GetCityCaptureOneTurnReach(unit, info) then return false end
	local preview = SC5.Preview(unit, nil, city, true)
	return preview ~= nil and preview.damage >= preview.targetHP and preview.retaliation * 1.25 < preview.hp
end

function SC5.CityHasFinisher(player, city)
	for unit in player:Units() do
		if SC5.CanFinishCity(player, unit, city) then return true end
	end
	return false
end

function SC5.HasPromotion(unit, name)
	local promotion = GameInfo.UnitPromotions and GameInfo.UnitPromotions[name]
	local id = promotion and promotion.ID or (GameInfoTypes and GameInfoTypes[name])
	return id ~= nil and SC5.Safe(function() return unit:IsHasPromotion(id) end, false)
end

function SC5.HasChainReaction(unit)
	return SC5.HasPromotion(unit, "PROMOTION_CHAIN_REACTION")
		and not (SC5.HasPromotion(unit, "PROMOTION_LOGISTICS")
			and SC5.HasPromotion(unit, "PROMOTION_CAN_MOVE_AFTER_ATTACKING"))
end

function SC5.ChainForecast(player, unit, enemy, preview)
	if not enemy or not SC5.HasChainReaction(unit) then return end
	-- Installed CombatEnded handler exits when its defender is gone. Use a
	-- survival margin on the trigger, not an invented chain bonus on lethal shots.
	if preview.damage * 1.25 >= preview.targetHP then
		preview.scriptReason = "chain-trigger-may-die"
		return
	end
	local epoch = Game.GetGameTurn()..":"..tostring(SC_EXECUTION_WORLD_GENERATION or 0)
	if SC5.chainEpoch ~= epoch then SC5.chainEpoch, SC5.chainCache = epoch, {} end
	local key = unit:GetOwner()..":"..unit:GetID()..":"..unit:MovesLeft()..":"..unit:GetDamage()..":"..enemy:GetOwner()
	local cached = SC5.chainCache[key]
	if not cached then
		cached = {}
		for other in Players[enemy:GetOwner()]:Units() do
			if other:IsCombatUnit() and SC5.ObservedUnit(player, other) then
				local damage = SC5.Safe(function() return unit:GetRangeCombatDamage(other, nil, false) end, 0) * 0.73
				local hp, maximum = SC5.HP(other)
				if hp > 0 and damage > 0 then
					local value = SC5.Value(other)
					cached[#cached + 1] = { owner=other:GetOwner(), id=other:GetID(), hp=hp,
						damage=math.min(damage,hp), value=value*math.min(damage,hp)/maximum
							+ (damage >= hp and value*0.5 or 0) }
				end
			end
		end
		SC5.chainCache[key] = cached
	end
	preview.scriptValue, preview.scriptDamage, preview.scriptTargets = 0, 0, {}
	for _, record in ipairs(cached) do
		if record.id ~= enemy:GetID() then
			preview.scriptValue = preview.scriptValue + record.value
			preview.scriptDamage = preview.scriptDamage + record.damage
			preview.scriptTargets[#preview.scriptTargets + 1] = record
		end
	end
	preview.scriptCount = #preview.scriptTargets
	preview.scriptReason = "visible-owner-chain-reaction"
end

function SC5.AttackFacts(player, unit, enemy, city, melee)
	local preview, failure = SC5.Preview(unit, enemy, city, melee)
	if not preview then return nil, failure end
	local info = SC5.Info(unit)
	local profile = SC_GetUnitCapabilityProfile(unit, info)
	preview.city = city ~= nil
	preview.capture = melee and city ~= nil
	preview.selfValue = SC5.Value(unit)
	preview.protected = SC_GetUnitProtectionTier(unit, info) >= 2
	preview.consumable = profile.suicide == true or tonumber(info.Suicide) == 1
		or profile.doctrineClass == "missile_strike" or info.Type == "UNIT_BAZOOKA"
	local targetPlot = city and city:Plot() or enemy:GetPlot()
	preview.authorized = Teams[player:GetTeam()]:IsAtWar(Players[(city or enemy):GetOwner()]:GetTeam())
	preview.key = (melee and "melee:" or "ranged:")..targetPlot:GetX()..":"..targetPlot:GetY()
	preview.enemyOwner = enemy and enemy:GetOwner() or nil
	preview.enemyID = enemy and enemy:GetID() or nil
	preview.cityOwner = city and city:GetOwner() or nil
	preview.cityID = city and city:GetID() or nil
	preview.targetValue = city and (600 + city:GetPopulation() * 40) or SC5.Value(enemy)
	preview.threat = 0
	if enemy ~= nil then
		local enemyInfo = SC5.Info(enemy)
		local enemyProfile = SC_GetUnitCapabilityProfile(enemy, enemyInfo)
		if enemyProfile.canRange then preview.threat = 0.8 end
		if enemyProfile.intercept and enemyProfile.intercept > 0 then preview.threat = preview.threat + 0.5 end
		local world = SC_STRATEGY_STATE and SC_STRATEGY_STATE.world
		for _, entry in ipairs(world and world.ownCities or {}) do
			if Map.PlotDistance(entry.plot:GetX(), entry.plot:GetY(), targetPlot:GetX(), targetPlot:GetY()) <= 6 then
				preview.threat = preview.threat + 1.2
				break
			end
		end
	else
		preview.capturerNear = SC_CountFriendlyRoleNearPlot(player, targetPlot, 4, "capture", 1) > 0
	end
	if not melee then SC5.ChainForecast(player, unit, enemy, preview) end
	return preview
end

function SC5.Defender(player, unit, plot)
	if not plot or plot:IsCity() then return nil, "city-target" end
	-- CvLuaPlot uses integer flags. CvUnit::airStrikeTarget uses these same
	-- combat-defender arguments; the noncombat-only extension is not Lua-bound.
	local ok, defender = pcall(function()
		return plot:GetBestDefender(-1, player:GetID(), unit, 1, 0, 0)
	end)
	if not ok then error("defender-api-unavailable: "..tostring(defender)) end
	if defender and SC5.ObservedUnit(player, defender)
		and Teams[player:GetTeam()]:IsAtWar(Players[defender:GetOwner()]:GetTeam()) then
		return defender, "native-defender"
	end
	return nil, "no-visible-combat-defender"
end

function SC5.ScoreRangedTarget(player, unit, enemy, city)
	if SC5.IsWithdrawing(unit) then return -999999, "withdrawal-reserved" end
	if enemy and enemy:GetPlot():IsCity() then return -999999, "garrison-use-city-target" end
	if enemy then
		local defender, reason = SC5.Defender(player, unit, enemy:GetPlot())
		if not defender then return -999999, reason end
		if defender:GetID() ~= enemy:GetID() or defender:GetOwner() ~= enemy:GetOwner() then
			return -999999, "not-native-defender"
		end
	end
	local facts, failure = SC5.AttackFacts(player, unit, enemy, city, false)
	if not facts then return -999999, failure end
	local score, reason = SC5.AttackScore(facts)
	return score or -999999, tostring(reason)..",preview="..tostring(facts.confidence), facts
end

function SC5.SweepScore(unit, plot, enemy)
	local interceptor = SC5.Safe(function() return unit:GetBestInterceptor(plot, enemy, false, true) end, nil)
	if not interceptor then return -999999, "no-active-interceptor" end
	local preview = SC5.Preview(unit, interceptor, nil, false)
	if not preview or (preview.retaliation + preview.uncertainty) * 1.25 >= preview.hp then return -999999, "unsafe-sweep" end
	return 500 + SC5.Value(interceptor) * 0.25, "suppress-active-interceptor"
end

function SC5.CollectCandidate(stats, score, reason, facts)
	stats.evaluated = stats.evaluated or {}
	stats.rejected = stats.rejected or {}
	if score <= 0 then
		local key = tostring(reason):match("^[^,]+") or "unknown"
		stats.rejected[key] = (stats.rejected[key] or 0) + 1
	elseif facts then
		stats.evaluated[#stats.evaluated + 1] = { score = score, reason = reason, facts = facts }
	end
end

function SC5.FactText(facts)
	local parts = {}
	for key, value in pairs(facts) do
		if type(value) == "number" or type(value) == "boolean" or type(value) == "string" then
			parts[#parts + 1] = key.."="..tostring(value)
		end
	end
	table.sort(parts)
	return table.concat(parts, " ")
end

function SC5.LogCandidates(unit, stats)
	SC5.sequence = (SC5.sequence or 0) + 1
	stats.decisionID = SC5.sequence
	local candidates = stats.evaluated or {}
	table.sort(candidates, function(a, b)
		if a.score == b.score then return a.facts.key < b.facts.key end
		return a.score > b.score
	end)
	for i = 1, math.min(#candidates, 3) do
		local c = candidates[i]
		SC_Debug("decision5 candidate decision="..stats.decisionID.." rank="..i..
			" score="..c.score.." "..SC5.FactText(c.facts))
	end
	SC_Debug("decision5 selection decision="..stats.decisionID.." unit="..SC_GetUnitDebugLabel(unit)..
		" considered="..tostring(stats.enemyUnits + stats.enemyCities)..
		" accepted="..#candidates.." rejected="..SC5.FactText(stats.rejected or {}))
end

function SC5.MeleeGate(player, unit, plot)
	if not plot then return true end
	local city = plot:IsCity() and plot:GetPlotCity() or nil
	if city and not Teams[player:GetTeam()]:IsAtWar(Players[city:GetOwner()]:GetTeam()) then return true end
	local enemy = nil
	if not city then
		local hasEnemy = false
		for index = 0, plot:GetNumUnits() - 1 do
			local candidate = plot:GetUnit(index)
			if candidate and Teams[player:GetTeam()]:IsAtWar(Players[candidate:GetOwner()]:GetTeam())
				and candidate:IsCombatUnit() then hasEnemy = true; break end
		end
		if hasEnemy then
			local reason
			enemy, reason = SC5.Defender(player, unit, plot)
			if not enemy then return false, reason end
		end
	end
	if not city and not enemy then return true end
	local info = SC5.Info(unit)
	local profile = SC_GetUnitCapabilityProfile(unit, info)
	if profile.domain == "DOMAIN_AIR" then return true end
	if city and not profile.canCapture then return false, "support-cannot-capture" end
	local facts, failure = SC5.AttackFacts(player, unit, enemy, city, true)
	if not facts then return false, failure end
	if city and facts.damage < facts.targetHP then
		local potential = facts.damage
		for support in player:Units() do
			if support:GetID() ~= unit:GetID() and support:CanMove() then
				local p = SC_GetUnitCapabilityProfile(support, SC5.Info(support))
				local distance = Map.PlotDistance(support:GetPlot():GetX(), support:GetPlot():GetY(), plot:GetX(), plot:GetY())
				local ranged = p.canRange and SC5.Safe(function() return support:CanRangeStrikeAt(plot:GetX(), plot:GetY()) end, false)
				if ranged or (p.canCapture and distance <= 1) then
					local estimate = SC5.Preview(support, nil, city, not ranged)
					if estimate and (estimate.retaliation + estimate.uncertainty) * 1.25 < estimate.hp then potential = potential + estimate.damage end
				end
			end
		end
		facts.assaultSupported, facts.capturerNear = potential >= facts.targetHP, true
	end
	local score, reason = SC5.AttackScore(facts)
	return score ~= nil, reason
end

function SC5.BaseThreat(player, plot)
	if not plot then return false, 0 end
	local city = plot:IsCity() and plot:GetPlotCity() or nil
	local host = nil
	if not city then
		for i = 0, plot:GetNumUnits() - 1 do
			local candidate = plot:GetUnit(i)
			local info = candidate and SC5.Info(candidate)
			if candidate and candidate:GetOwner() == player:GetID() and info and info.Domain == "DOMAIN_SEA" then
				if not host or SC5.Value(candidate) > SC5.Value(host) then host = candidate end
			end
		end
	end
	if not city and not host then return false, 0 end
	if host then
		local total = SC5.PlotExposure(plot, SC5.ThreatSources(player, host))
		return SC5.NeedsWithdrawal(SC5.HP(host), total, true), total
	end
	local world = SCX_GetExecutionWorld(player, "base-risk")
	local damage = {}
	for _, record in ipairs(world and world.units or {}) do
		local distance = Map.PlotDistance(plot:GetX(), plot:GetY(), record.x, record.y)
		-- Coarse prefilter bounds expensive native previews; this is a danger
		-- estimate, not proof that the enemy has a traversable next-turn path.
		if distance <= 16 then
			local enemy = SC_ResolveLiveUnit(record.ownerID, record.unitID)
			if enemy then
				local info = SC5.Info(enemy)
				local p = SC_GetUnitCapabilityProfile(enemy, info)
				local range = p.range or 0
				local reach = range + (info.Domain == "DOMAIN_AIR" and 0 or math.min(p.moves or 2, 10))
				local compatible = city ~= nil or info.Domain ~= "DOMAIN_LAND" or p.canRange
				if compatible and distance <= reach and not SC5.Safe(function() return enemy:IsEmbarked() end, false) then
					local preview = SC5.Preview(enemy, host, city, not p.canRange)
					if preview then
						local weighted = preview.damage * (distance <= math.max(range, 1) and 1 or 0.5)
						damage[#damage + 1] = weighted
					end
				end
			end
		end
	end
	table.sort(damage, function(a, b) return a > b end)
	local total = 0
	for i = 1, math.min(#damage, 6) do total = total + damage[i] end
	local hp = SC5.HP(city or host)
	return total * 1.25 >= hp * 0.75, total
end

function SC5.Standoff(unit, defaultMin, defaultMax, defaultDesired)
	local info = SC5.Info(unit)
	local profile = SC_GetUnitCapabilityProfile(unit, info)
	local range = math.max(SC5.Safe(function() return unit:Range() end, 0), profile.range or 0)
	if profile.canRange and range >= 2 then
		return math.max(1, range - 1), range, range
	end
	if info and info.DomainCargo == "DOMAIN_AIR" then
		local cargoRange = nil
		local plot = unit:GetPlot()
		for index = 0, plot:GetNumUnits() - 1 do
			local cargo = plot:GetUnit(index)
			local transport = SC5.Safe(function() return cargo:GetTransportUnit() end, nil)
			if transport and transport:GetOwner() == unit:GetOwner() and transport:GetID() == unit:GetID() then
				local r = SC5.Safe(function() return cargo:Range() end, 0)
				if r > 0 then cargoRange = math.min(cargoRange or r, r) end
			end
		end
		if cargoRange then
			return math.max(2, cargoRange - 2), math.max(2, cargoRange), math.max(2, cargoRange - 1)
		end
	end
	return defaultMin, defaultMax, defaultDesired
end

function SC5.LogAttackFacts(player, unit, plot, stats)
	local city = plot:IsCity() and plot:GetPlotCity() or nil
	local enemy = not city and SC5.Defender(player, unit, plot) or nil
	local facts = SC5.AttackFacts(player, unit, enemy, city, false)
	if not facts then return nil end
	local chosen = stats and stats.bestFacts
	if chosen and (chosen.enemyID ~= facts.enemyID or chosen.enemyOwner ~= facts.enemyOwner
		or chosen.cityID ~= facts.cityID or chosen.cityOwner ~= facts.cityOwner
		or chosen.targetHP ~= facts.targetHP or chosen.hp ~= facts.hp
		or chosen.damage ~= facts.damage or chosen.retaliation ~= facts.retaliation) then
		SC_Debug("decision5 target-changed decision="..tostring(stats.decisionID).." recovery=rescore-next-wave")
		return nil
	end
	SC5.sequence = (SC5.sequence or 0) + 1
	facts.sequence = SC5.sequence
	facts.owner, facts.unitID = unit:GetOwner(), unit:GetID()
	facts.movesBefore = unit:MovesLeft()
	facts.enemyOwner = enemy and enemy:GetOwner() or nil
	facts.enemyID = enemy and enemy:GetID() or nil
	facts.cityOwner = city and city:GetOwner() or nil
	facts.cityID = city and city:GetID() or nil
	SC_Debug("decision5 attack seq="..facts.sequence.." unit="..SC_GetUnitDebugLabel(unit)..
		" decision="..tostring(stats and stats.decisionID or 0)..
		" "..SC5.FactText(facts).." choiceScore="..tostring(stats and stats.bestScore or 0))
	return facts
end

function SC5.LogAttackOutcome(facts, status)
	if not facts then return end
	local live = SC_ResolveLiveUnit(facts.owner, facts.unitID)
	local target = nil
	if facts.enemyOwner ~= nil then target = SC_ResolveLiveUnit(facts.enemyOwner, facts.enemyID)
	elseif facts.cityOwner ~= nil then
		target = SC5.Safe(function() return Players[facts.cityOwner]:GetCityByID(facts.cityID) end, nil)
	end
	local dealt = facts.targetHP - (target and SC5.HP(target) or 0)
	local lost = facts.hp - (live and SC5.HP(live) or 0)
	local confirmed = dealt > 0 or lost > 0
	local movesAfter = live and live:MovesLeft() or 0
	local collateral, affected = 0, 0
	for _, record in ipairs(facts.scriptTargets or {}) do
		local other = SC_ResolveLiveUnit(record.owner, record.id)
		local damage = math.max(0, record.hp - (other and SC5.HP(other) or 0))
		collateral = collateral + damage
		if damage > 0 then affected = affected + 1 end
	end
	SC_Debug("decision5 outcome seq="..facts.sequence.." status="..tostring(status)..
		" confirmed="..tostring(confirmed).." observedDamage="..dealt.." observedLoss="..lost..
		" movesBefore="..tostring(facts.movesBefore).." movesAfter="..movesAfter..
		" scriptExpected="..tostring(facts.scriptDamage or 0).." scriptObserved="..collateral..
		" scriptAffected="..affected..
		" predictionError="..(dealt - math.min(facts.damage, facts.targetHP)))
end

function SC5.IsWithdrawing(unit)
	local turn = Game.GetGameTurn()
	if SC5.withdrawTurn ~= turn then
		SC5.withdrawTurn, SC5.withdrawn = turn, {}
		SC5.riskLogged = {}
	end
	return SC5.withdrawn[unit:GetOwner()..":"..unit:GetID()] == true
end

-- Preview strength once per threatened actor, then score escape tiles cheaply.
-- Movement reach is an upper bound, not a claim that an enemy has a legal path.
function SC5.ThreatSources(player, unit)
	local world = SCX_GetExecutionWorld(player, "survival")
	local sources = {}
	local origin = unit:GetPlot()
	if not origin or not world then return sources end
	local ownInfo = SC5.Info(unit)
	local ownWater = origin:IsWater()
	local _, maxHP = SC5.HP(unit)
	world.threatCapabilities = world.threatCapabilities or {}
	for _, record in ipairs(world.units or {}) do
		local key = record.ownerID..":"..record.unitID
		local capability = world.threatCapabilities[key]
		if not capability then
			local enemy = SC_ResolveLiveUnit(record.ownerID, record.unitID)
			if enemy then
				local info = SC5.Info(enemy)
				local p = SC_GetUnitCapabilityProfile(enemy, info)
				capability = { ranged = p.canRange == true, domain = info.Domain,
					domainOnly = SC_DBFlag(info.RangeAttackOnlyInDomain),
					range = p.canRange and math.max(p.range or 0, 1) or 1,
					move = info.Domain == "DOMAIN_AIR" and 0 or math.min(p.moves or 2, 10) }
				world.threatCapabilities[key] = capability
			end
		end
		if capability then
			local ranged, range, move = capability.ranged, capability.range, capability.move
			local distance = Map.PlotDistance(origin:GetX(), origin:GetY(), record.x, record.y)
			local compatible = ranged or (capability.domain == ownInfo.Domain)
				or (capability.domain == "DOMAIN_SEA" and ownWater)
			local enemy = compatible and distance <= range + move + 6
				and SC_ResolveLiveUnit(record.ownerID, record.unitID) or nil
			if enemy and SC5.ObservedUnit(player, enemy) and not enemy:IsEmbarked()
				and (ranged or enemy:IsCombatUnit()) then
				local preview = SC5.Preview(enemy, unit, nil, not ranged)
				if preview and preview.damage > 0 then
					sources[#sources + 1] = { x = record.x, y = record.y, range = range,
						move = move, damage = math.min(preview.damage, maxHP),
						domain = capability.domain, domainOnly = capability.domainOnly,
						owner = record.ownerID, unitID = record.unitID }
				end
			end
		end
	end
	for _, record in ipairs(world.cities or {}) do
		if Map.PlotDistance(origin:GetX(), origin:GetY(), record.x, record.y) <= 8 then
			local city = Players[record.ownerID]:GetCityByID(record.cityID)
			if city and city:Plot():IsVisible(player:GetTeam(), false) then
				local damage = SC5.Safe(function() return city:RangeCombatDamage(unit, nil) end, 0)
				sources[#sources + 1] = { x = record.x, y = record.y, range = 2, move = 0,
					damage = math.min(damage, maxHP), owner = record.ownerID, cityID = record.cityID }
			end
		end
	end
	return sources
end

function SC5.PlotExposure(plot, sources)
	local hits, pressure = {}, 0
	for _, source in ipairs(sources) do
		local distance = Map.PlotDistance(plot:GetX(), plot:GetY(), source.x, source.y)
		local weight = 0
		if distance <= source.range then weight = 1
		elseif source.move > 0 and distance <= source.range + source.move then
			weight = 0.5 * (source.range + source.move + 1 - distance) / source.move
		end
		if source.domainOnly and ((source.domain == "DOMAIN_SEA") ~= plot:IsWater()) then weight = 0 end
		if weight > 0 then
			hits[#hits + 1] = source.damage * weight
			pressure = pressure + source.damage / (distance + 1)
		end
	end
	table.sort(hits, function(a, b) return a > b end)
	local total = 0
	for i = 1, math.min(#hits, 6) do total = total + hits[i] end
	return total, pressure
end

function SC5.NeedsWithdrawal(hp, exposure, protected)
	return hp > 0 and exposure * 1.25 >= hp * (protected and 0.65 or 0.9)
end

function SC5.RunSurvival(player, atWar, adapters)
	if not player or not atWar then return 0 end
	local units = {}
	for unit in player:Units() do
		local info = SC5.Info(unit)
		if info and info.Domain ~= "DOMAIN_AIR" and unit:IsCombatUnit() and unit:CanMove() then
			units[#units + 1] = { owner = unit:GetOwner(), id = unit:GetID(), value = SC5.Value(unit) }
		end
	end
	table.sort(units, function(a, b)
		if a.value == b.value then return a.id < b.id end
		return a.value > b.value
	end)
	local actions = 0
	for _, identity in ipairs(units) do
		local unit = SC_ResolveLiveUnit(identity.owner, identity.id)
		if unit and unit:CanMove() then
			SC5.IsWithdrawing(unit)
			local sources = SC5.ThreatSources(player, unit)
			local exposure = SC5.PlotExposure(unit:GetPlot(), sources)
			local hp = SC5.HP(unit)
			local protected = SC_GetUnitProtectionTier(unit, SC5.Info(unit)) >= 2
			local logKey = identity.owner..":"..identity.id
			if not SC5.riskLogged[logKey] then
				SC5.riskLogged[logKey] = true
				adapters.log("survival5 assess unit="..adapters.getUnitDebugLabel(unit).." hp="..hp..
					" incoming="..exposure.." sources="..#sources.." protected="..tostring(protected)..
					" endangered="..tostring(SC5.NeedsWithdrawal(hp, exposure, protected))..
					" plot="..unit:GetPlot():GetX()..","..unit:GetPlot():GetY())
			end
			if SC5.NeedsWithdrawal(hp, exposure, protected) then
				local before = exposure
				local steps, failed = 0, {}
				local status = "no-safer-legal-step"
				local label = adapters.getUnitDebugLabel(unit)
				-- Adjacent verified moves cannot stop at an unknown intermediate
				-- tile of a multi-turn retreat path. Re-resolve after every mission.
				for step = 1, 8 do
					if not unit or not unit:CanMove() then break end
					local origin, best = unit:GetPlot(), nil
					local current, pressure = SC5.PlotExposure(origin, sources)
					if not SC5.NeedsWithdrawal(SC5.HP(unit), current, protected) then break end
					local bestScore = current * 1000 + pressure
					for direction = 0, 5 do
						local plot = Map.PlotDirection(origin:GetX(), origin:GetY(), direction)
						local key = plot and plot:GetX()..":"..plot:GetY() or "-"
						local info = SC5.Info(unit)
						local domainSafe = plot and (info.Domain ~= "DOMAIN_LAND" or origin:IsWater() or not plot:IsWater())
						if domainSafe and not failed[key]
							and not SC_PlotWouldRequireNewWar(player, plot)
							and SC5.Safe(function() return unit:CanMoveInto(plot, 0) end, false) then
							local risk, nextPressure = SC5.PlotExposure(plot, sources)
							local score = risk * 1000 + nextPressure
							if score < bestScore - 0.01 then best, bestScore = plot, score end
						end
					end
					if not best then break end
					local ok, moveStatus = adapters.survivalMove(unit, best)
					unit = SC_ResolveLiveUnit(identity.owner, identity.id)
					status = moveStatus or "unknown"
					if ok and unit and unit:GetPlot() ~= origin then
						steps = steps + 1
						SC5.IsWithdrawing(unit)
						SC5.withdrawn[identity.owner..":"..identity.id] = true
						adapters.reserveWithdrawal(unit)
					else
						failed[best:GetX()..":"..best:GetY()] = true
						if not unit then break end
					end
				end
				if steps > 0 then actions = actions + 1 end
				local after = unit and SC5.PlotExposure(unit:GetPlot(), sources) or -1
				adapters.log("survival5 unit="..label.." hp="..hp.." incomingBefore="..before..
					" incomingAfter="..after.." sources="..#sources.." steps="..steps..
					" status="..tostring(status).." movementReach=upper-bound")
			end
		end
	end
	return actions
end
