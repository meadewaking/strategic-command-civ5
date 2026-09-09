-- Strategic Command V3: high-impact weapons act before the ordinary fire plan.

local function SCV3_SafeNumber(callback, fallback)
	local ok, value = pcall(callback)
	if ok and tonumber(value) ~= nil then return tonumber(value) end
	return fallback or 0
end

local function SCV3_IsGlobalFireSupport(unitInfo)
	if unitInfo == nil then return false end
	return unitInfo.Type == "UNIT_PARTICLE_CANNON"
		or unitInfo.Type == "UNIT_PROTON_COLLIDER_VESSEL"
end

local function SCV3_SpecialTargetScore(target, targetInfo, targetProfile, distance)
	local combat = math.max(tonumber(targetInfo and targetInfo.Combat) or 0, 0)
	local ranged = math.max(tonumber(targetInfo and targetInfo.RangedCombat) or 0, 0)
	local damage = SCV3_SafeNumber(function() return target:GetDamage() end, 0)
	local score = combat * 9 + ranged * 11 + math.max(0, 100 - damage) * 5
	score = score + math.max(tonumber(distance) or 0, 0) * 70
	local class = targetProfile and targetProfile.doctrineClass or "unknown"
	if class == "arsenal_capital" or class == "fleet_carrier" or class == "ballistic_submarine" then
		score = score + 2400
	elseif class == "siege_artillery" or class == "surface_fire_support" or class == "strike_aircraft" then
		score = score + 1500
	elseif class == "air_defense_screen" or class == "mobile_air_defense" then
		score = score + 1100
	end
	return score, class
end

function SCV3_RunSpecialWeapons(player, atWar, adapters)
	if player == nil or not atWar then return 0 end
	local actions = 0
	for unit in player:Units() do
		local isDead = unit == nil or SCV3_SafeNumber(function() return unit:IsDead() and 1 or 0 end, 1) > 0
		local alive = not isDead
		local canMove = alive and SCV3_SafeNumber(function() return unit:CanMove() and 1 or 0 end, 0) > 0
		local unitInfo = alive and adapters.getUnitInfo(unit) or nil
		if canMove and SCV3_IsGlobalFireSupport(unitInfo) and (not SC5 or not SC5.IsWithdrawing(unit)) then
			local pool = adapters.getExecutionTargetPool ~= nil
				and adapters.getExecutionTargetPool(player, unit, "fire")
				or adapters.getEnemyTargetPool(player)
			local sourcePlot = unit:GetPlot()
			local threatRadius = adapters.getConfig("SpecialWeaponImmediateThreatRadius", 4)
			local nearbyThreats = sourcePlot ~= nil and adapters.countEnemyCombatPresenceNearPlot(player, sourcePlot, threatRadius, 8) or 8
			local best = nil
			local bestScore = -999999
			local bestClass = "none"
			local bestFacts = nil
			local legal = 0
			local unsafeRange = 0
			local minimumStandoff = adapters.getConfig("SpecialWeaponMinimumStandoff", 5)
			for _, target in ipairs(pool.units or {}) do
				if adapters.isEnemyUnitValid(player, target) then
					local plot = target:GetPlot()
					local distance = sourcePlot ~= nil and plot ~= nil and adapters.plotDistance(sourcePlot, plot) or 0
					if plot ~= nil and adapters.isCombatTargetAuthorized(unit, plot)
						and adapters.isPotentialRangeStrikeAt(unit, plot) then
						if distance >= minimumStandoff then
							legal = legal + 1
							local targetInfo = adapters.getUnitInfo(target)
							local targetProfile = adapters.getUnitCapabilityProfile(target, targetInfo)
							local score, class = SCV3_SpecialTargetScore(target, targetInfo, targetProfile, distance)
							local candidateFacts, scoreReason
							if SC5 then score, scoreReason, candidateFacts = SC5.ScoreRangedTarget(player, unit, target, nil) end
							if score > bestScore then
								best, bestScore, bestClass = target, score, class
								bestFacts = candidateFacts
							end
						else
							unsafeRange = unsafeRange + 1
						end
					end
				end
			end
			local label = adapters.getUnitDebugLabel(unit)
			if best ~= nil and bestScore > 0 and nearbyThreats <= 0 then
				local targetPlot = best:GetPlot()
				adapters.log("V3 specialWeapon choose unit="..label..
					" candidates="..tostring(legal).." visibleEnemies="..tostring(#(pool.units or {}))..
					" target="..adapters.getUnitDebugLabel(best).." class="..bestClass..
					" score="..tostring(math.floor(bestScore)))
				local unitKey = adapters.getUnitTurnKey(unit)
				local ownerID, unitID = unit:GetOwner(), unit:GetID()
				local facts = SC5 and SC5.LogAttackFacts(player, unit, targetPlot,
					{ bestFacts=bestFacts, bestScore=bestScore, decisionID=0 }) or nil
				local ok, status = false, "target-revalidation-failed"
				if not SC5 or facts then ok, status = adapters.rangeStrike(unit, targetPlot) end
				if SC5 then SC5.LogAttackOutcome(facts, status) end
				if ok then
					actions = actions + 1
					adapters.recordTacticalAction(unitKey)
					local live = SC_ResolveLiveUnit and SC_ResolveLiveUnit(ownerID, unitID) or nil
					if live then adapters.markStrategicUnitDone(live) end
				end
				adapters.log("V3 specialWeapon result unit="..label.." ok="..tostring(ok)..
					" status="..tostring(status).." refresh="..(ok and "volley-end" or "none"))
			elseif nearbyThreats > 0 then
				adapters.log("V3 specialWeapon hold unit="..label..
					" reason=immediate-threat threats="..tostring(nearbyThreats).." radius="..tostring(threatRadius)..
					" safeCandidates="..tostring(legal).." unsafeRange="..tostring(unsafeRange))
			else
				adapters.log("V3 specialWeapon hold unit="..label..
					" reason=no-safe-standoff-target safeCandidates="..tostring(legal)..
					" unsafeRange="..tostring(unsafeRange).." visibleEnemies="..tostring(#(pool.units or {})))
			end
		end
	end
	if actions > 0 then adapters.refreshTacticalWorld(player, "special-weapon-volley") end
	return actions
end
