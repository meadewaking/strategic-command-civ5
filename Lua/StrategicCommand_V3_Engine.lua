-- Strategic Command V3: the sole takeover orchestration entry point.

function SCV3_RunEngine(player, atWar, fullAutomation, reason, adapters)
	local turn = adapters.getTurn()
	SCV3_BeginPass(turn, reason, fullAutomation, adapters)
	local results = SCV3_NewResults()
	local cityDetails = {}
	if SCV3.criticalFault then
		results.criticalFault = SCV3.criticalFault
		return results, cityDetails
	end
	local function run(name, resultKey, callback)
		local count, detail, errors = SCV3_RunModule(adapters, name, callback)
		SCV3_AddResult(results, resultKey, count, errors)
		return count, detail
	end

	if fullAutomation then
		adapters.log("V3 engine phase=national begin")
		run("capital", "capitalActions", function() return adapters.capital(player, atWar) end)
		local cityCount, details, cityErrors = SCV3_RunCityProduction(player, atWar, adapters, "scheduled")
		SCV3_AddResult(results, "cityOrders", cityCount, cityErrors)
		if details ~= nil then
			for _, detail in ipairs(details) do
				if #cityDetails < 10 then table.insert(cityDetails, detail) end
			end
		end
		run("purchase", "purchases", function() return adapters.purchases(player, atWar) end)
		run("ideology", "ideologies", function() return adapters.ideology(player) end)
		run("research", "research", function() return adapters.research(player) end)
		run("policy", "policies", function() return adapters.policy(player) end)
		run("greatPeople", "greatPeople", function() return adapters.greatPeople(player, atWar) end)
		if SCX_RunExecutionMilitary ~= nil then
			SCX_RunExecutionMilitary(player, atWar, adapters, results)
		else
			SCV3_RunMilitary(player, atWar, adapters, results)
		end
		if SCV3.criticalFault then
			results.criticalFault = SCV3.criticalFault
			return results, cityDetails
		end
		run("trade", "tradeRoutes", function() return adapters.tradeRoutes(player) end)
		run("league", "leagues", function() return adapters.leagues(player) end)
	else
		-- Popup/update callbacks only converge the decision currently blocking the
		-- turn.  They never rerun the national or military planner.
		adapters.log("V3 engine phase=light-convergence begin")
	end

	local blockerCount, _, blockerErrors = SCV3_RunModule(adapters, "blocker", function()
		return SCV3_HandleEndTurnBlocker(player, atWar, true, adapters)
	end)
	SCV3_AddResult(results, "blockers", blockerCount, blockerErrors)
	results.popups = adapters.takePopupCount()
	results.diplo = adapters.takeDiploCount()
	adapters.log("V3 engine end seq="..tostring(SCV3.passSequence).." mode="..(fullAutomation and "full" or "light")..
		" blocker="..tostring(adapters.getBlockerName(player)).." errors="..tostring(results.moduleErrors))
	return results, cityDetails
end
