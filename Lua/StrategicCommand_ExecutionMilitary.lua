-- Strategic Command 4.1: execution-first military phase loop.

function SCX_RunExecutionMilitary(player, atWar, adapters, results)
	local function run(name, resultKey, callback)
		local count, _, errors = SCV3_RunModule(adapters, "executionMilitary."..name, callback)
		SCV3_AddResult(results, resultKey, count, errors)
		return tonumber(count) or 0
	end
	local function refresh(reason)
		if not SCV3.criticalFault then adapters.refreshTacticalWorld(player, reason) end
	end

	adapters.log("executionMilitary phase=readiness begin")
	run("upgrade", "upgrades", function() return adapters.upgrades(player) end)
	run("promotion", "promotions", function() return adapters.promotions(player) end)

	refresh("execution-opening")
	adapters.log("executionMilitary phase=survival begin")
	run("survivalOpening", "heals", function() return adapters.survival and adapters.survival(player, atWar) or 0 end)
	run("airEvacuation", "strategicMoves", function() return adapters.airRebase(player, atWar, true) end)
	if SCV3.criticalFault then return end
	refresh("execution-after-move-survival")
	adapters.log("executionMilitary phase=opening begin")
	run("specialOpening", "specialWeapons", function() return SCV3_RunSpecialWeapons(player, atWar, adapters) end)
	run("captureOpening", "captureFinishers", function() return adapters.capture(player, atWar) end)
	local openingAir = run("airOpening", "defenseActions", function() return adapters.airSuperiority(player, atWar) end)
	local openingFire = run("fireOpening", "defenseActions", function() return adapters.localDefense(player, atWar) end)
	local openingCity = run("cityOpening", "cityStrikes", function() return adapters.cityStrike(player, atWar) end)
	if openingAir + openingFire + openingCity > 0 then refresh("execution-after-opening-fire") end
	run("captureAfterOpening", "captureFinishers", function() return adapters.capture(player, atWar) end)
	adapters.log("executionMilitary phase=logistics begin")
	-- Clear reachable threats before consuming moves on healing or redeployment.
	run("heal", "heals", function() return adapters.healing(player) end)
	run("transport", "transportEscort", function() return adapters.transportEscort(player, atWar) end)
	run("airRebase", "strategicMoves", function() return adapters.airRebase(player, atWar) end)
	refresh("execution-after-move-logistics")

	local maxWaves = math.max(1, adapters.getConfig("ExecutionMilitaryMaxWaves", 3))
	for wave = 1, maxWaves, 1 do
		if SCV3.criticalFault then return end
		adapters.log("executionMilitary wave="..tostring(wave).." phase=maneuver begin")
		local moves = run("move"..tostring(wave), "strategicMoves", function()
			return adapters.strategicMovement(player, atWar)
		end)
		if moves > 0 then refresh("execution-after-move-"..tostring(wave)) end
		if moves > 0 then
			run("survival"..wave, "heals", function() return adapters.survival and adapters.survival(player, atWar) or 0 end)
		end
		local rebases = 0
		if moves > 0 then
			rebases = run("airRebaseAfterMove"..tostring(wave), "strategicMoves", function()
				return adapters.airRebase(player, atWar)
			end)
			if rebases > 0 then refresh("execution-after-rebase-"..tostring(wave)) end
		end
		local specials = 0
		if wave == 1 and moves > 0 then
			specials = run("specialAfterMove", "specialWeapons", function()
				return SCV3_RunSpecialWeapons(player, atWar, adapters)
			end)
		end
		local air = run("air"..tostring(wave), "defenseActions", function()
			return adapters.airSuperiority(player, atWar)
		end)
		local fire = run("fire"..tostring(wave), "defenseActions", function()
			return adapters.localDefense(player, atWar)
		end)
		if specials + air + fire > 0 then refresh("execution-after-fire-"..tostring(wave)) end
		local captures = run("capture"..tostring(wave), "captureFinishers", function()
			return adapters.capture(player, atWar)
		end)
		adapters.log("executionMilitary wave="..tostring(wave)..
			" result moves="..tostring(moves).." rebases="..tostring(rebases).." special="..tostring(specials)..
			" air="..tostring(air).." fire="..tostring(fire).." capture="..tostring(captures))
		if moves + rebases + specials + air + fire + captures <= 0 then
			adapters.log("executionMilitary wave="..tostring(wave).." converge=true")
			break
		end
	end

	adapters.log("executionMilitary phase=cleanup begin")
	if SCV3.criticalFault then return end
	run("stacked", "stackedMoves", function() return adapters.stacked(player) end)
	-- Posture and finalOrders only clear genuine residual blockers after all action waves.
	run("idlePosture", "idlePosture", function() return adapters.idlePosture(player) end)
	run("finalOrders", "finalOrders", function() return adapters.finalOrders(player, atWar) end)
end
