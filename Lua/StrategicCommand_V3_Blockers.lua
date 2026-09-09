-- Strategic Command V3: end-turn blocker dispatcher with bounded convergence.

local function SCV3_BlockerContains(name, fragment)
	return string.find(tostring(name), fragment, 1, true) ~= nil
end

function SCV3_HandleEndTurnBlocker(player, atWar, allowNotificationActivation, adapters)
	if player == nil or adapters == nil then
		return 0
	end
	local before = adapters.getBlockerName(player)
	if SCV3_BlockerContains(before, "NO_ENDTURN_BLOCKING_TYPE") or before == "clear" then
		SCV3.blocker = { name = before, attempts = 0, stagnant = 0 }
		return 0
	end
	if SCV3.blocker.name ~= before then
		SCV3.blocker = { name = before, attempts = 0, stagnant = 0 }
	end
	SCV3.blocker.attempts = SCV3.blocker.attempts + 1
	local handled, errors = 0, 0
	local function run(name, callback)
		local count, _, moduleErrors = SCV3_RunModule(adapters, "blocker."..name, callback)
		handled = handled + count
		errors = errors + moduleErrors
	end
	if SCV3_BlockerContains(before, "UNIT_PROMOTION") then
		run("promotion", function() return adapters.promotions(player) end)
	elseif SCV3_BlockerContains(before, "STACKED_UNITS") then
		run("stacked", function() return adapters.stacked(player) end)
		if handled == 0 then
			run("orders", function() return adapters.finalOrders(player, atWar) end)
		end
	elseif SCV3_BlockerContains(before, "UNIT_NEEDS_ORDERS") or SCV3_BlockerContains(before, "ENDTURN_BLOCKING_UNITS") then
		run("stacked", function() return adapters.stacked(player) end)
		run("orders", function() return adapters.finalOrders(player, atWar) end)
	elseif SCV3_BlockerContains(before, "CITY_RANGE_ATTACK") then
		run("cityStrike", function() return adapters.cityStrike(player, atWar) end)
	elseif SCV3_BlockerContains(before, "RESEARCH") or SCV3_BlockerContains(before, "FREE_TECH") or SCV3_BlockerContains(before, "STEAL_TECH") then
		run("research", function() return adapters.research(player) end)
	elseif SCV3_BlockerContains(before, "PRODUCTION") then
		local count, _, moduleErrors = SCV3_RunCityProduction(player, atWar, adapters, "production-blocker")
		handled = handled + count
		errors = errors + moduleErrors
	elseif SCV3_BlockerContains(before, "POLICY") or SCV3_BlockerContains(before, "CHOOSE_IDEOLOGY") then
		run("ideology", function() return adapters.ideology(player) end)
		run("policy", function() return adapters.policy(player) end)
	elseif SCV3_BlockerContains(before, "DIPLO_VOTE") then
		run("diploVote", function() return adapters.diploVote(player) end)
		run("league", function() return adapters.leagues(player) end)
	elseif SCV3_BlockerContains(before, "LEAGUE_CALL") then
		run("league", function() return adapters.leagues(player) end)
	end
	local after = adapters.getBlockerName(player)
	if after == before then
		SCV3.blocker.stagnant = SCV3.blocker.stagnant + 1
	else
		SCV3.blocker = { name = after, attempts = 0, stagnant = 0 }
	end
	local status = after ~= before and "advanced" or (handled > 0 and "submitted" or "stalled")
	adapters.log("V3 blocker step before="..tostring(before).." after="..tostring(after)..
		" handled="..tostring(handled).." errors="..tostring(errors)..
		" attempt="..tostring(SCV3.blocker.attempts).." stagnant="..tostring(SCV3.blocker.stagnant)..
		" status="..status)
	if allowNotificationActivation ~= false and handled == 0 and SCV3.blocker.stagnant >= 2 then
		local activated = adapters.activateBlockingNotification(player)
		adapters.log("V3 blocker fallback name="..tostring(after).." activated="..tostring(activated))
	end
	return handled
end
