-- Strategic Command V3: shared state and fault-isolated module execution.

SCV3 = SCV3 or {}
SCV3.VERSION = "5.1"
SCV3.turn = SCV3.turn or -1
SCV3.passSequence = SCV3.passSequence or 0
SCV3.transactions = SCV3.transactions or {}
SCV3.blocker = SCV3.blocker or { name = "none", attempts = 0, stagnant = 0 }

local function SCV3_Log(adapters, message)
	if adapters ~= nil and adapters.log ~= nil then
		adapters.log("V3 "..tostring(message))
	end
end

function SCV3_ResetForTurn(turn, adapters)
	turn = tonumber(turn) or -1
	if SCV3.turn == turn then
		return false
	end
	SCV3.turn = turn
	SCV3.passSequence = 0
	SCV3.transactions = {}
	SCV3.criticalFault = nil
	SCV3.blocker = { name = "none", attempts = 0, stagnant = 0 }
	SCV3_Log(adapters, "state reset turn="..tostring(turn))
	return true
end

function SCV3_BeginPass(turn, reason, fullAutomation, adapters)
	SCV3_ResetForTurn(turn, adapters)
	SCV3.passSequence = SCV3.passSequence + 1
	SCV3_Log(adapters, "engine begin seq="..tostring(SCV3.passSequence)..
		" reason="..tostring(reason).." mode="..(fullAutomation and "full" or "light"))
	return SCV3.passSequence
end

function SCV3_NewResults()
	return {
		cityOrders = 0, capitalActions = 0, ideologies = 0, research = 0,
		policies = 0, upgrades = 0, promotions = 0, greatPeople = 0,
		purchases = 0, heals = 0, defenseActions = 0, specialWeapons = 0, captureFinishers = 0,
		cityStrikes = 0, strategicMoves = 0, stackedMoves = 0,
		transportEscort = 0, idlePosture = 0, tradeRoutes = 0,
		finalOrders = 0, notifications = 0, leagues = 0, blockers = 0,
		popups = 0, diplo = 0, moduleErrors = 0
	}
end

function SCV3_RunModule(adapters, moduleName, callback)
	if SCV3.criticalFault then return 0, nil, 0 end
	if callback == nil then
		SCV3_Log(adapters, "module skip name="..tostring(moduleName).." reason=no-adapter")
		return 0, nil, 0
	end
	if adapters ~= nil and adapters.runCount ~= nil then
		local count, detail, errors = adapters.runCount("v3."..tostring(moduleName), callback)
		if (errors or 0) > 0 and string.find(moduleName, "executionMilitary.", 1, true) == 1 then
			SCV3_HaltMilitary(adapters, moduleName)
		end
		return count, detail, errors
	end
	local ok, count, detail = pcall(callback)
	if not ok then
		SCV3_Log(adapters, "module error name="..tostring(moduleName).." err="..tostring(count))
		if string.find(moduleName, "executionMilitary.", 1, true) == 1 then
			SCV3_HaltMilitary(adapters, moduleName)
		end
		return 0, nil, 1
	end
	return tonumber(count) or 0, detail, 0
end

function SCV3_HaltMilitary(adapters, reason)
	if SCV3.criticalFault then return end
	SCV3.criticalFault = tostring(reason)
	SCV3_Log(adapters, "military halted reason="..SCV3.criticalFault.." recovery=stop-takeover")
	if adapters and adapters.haltTakeover then adapters.haltTakeover(SCV3.criticalFault) end
end

function SCV3_AddResult(results, key, count, errors)
	results[key] = (tonumber(results[key]) or 0) + (tonumber(count) or 0)
	results.moduleErrors = (tonumber(results.moduleErrors) or 0) + (tonumber(errors) or 0)
end

function SCV3_SetTransaction(key, value)
	SCV3.transactions[tostring(key)] = value
end

function SCV3_GetTransaction(key)
	return SCV3.transactions[tostring(key)]
end

function SCV3_ClearTransaction(key)
	SCV3.transactions[tostring(key)] = nil
end
