-- Pure decision rules. The game and offline behavioral tests execute this file.
SC5 = SC5 or {}
SC5.VERSION = "5.1"

function SC5.Clamp(value, low, high)
	return math.max(low, math.min(tonumber(value) or 0, high))
end

function SC5.AttackScore(c)
	if c.authorized == false then return nil, "not-at-war" end
	if c.legal == false then return nil, "illegal-target" end
	local hp = math.max(tonumber(c.hp) or 100, 0)
	if hp <= 0 then return nil, "actor-dead" end
	local targetHP = math.max(tonumber(c.targetHP) or 100, 0)
	local maxHP = math.max(tonumber(c.targetMaxHP) or 100, 1)
	local damage = math.max(tonumber(c.damage) or 0, 0)
	local retaliation = math.max(tonumber(c.retaliation) or 0, 0)
	local uncertainty = math.max(tonumber(c.uncertainty) or 0, 0)
	if damage <= 0 then return nil, "no-damage" end
	if targetHP <= (c.city and not c.capture and 1 or 0) then return nil, "already-neutralized" end
	local kill = damage >= targetHP
	if c.capture and not kill and not c.assaultSupported then return nil, "capture-needs-fire" end
	-- Native previews omit random rolls and some scripted combat effects.
	if not c.consumable and (retaliation + uncertainty) * 1.25 >= hp then return nil, "lethal-retaliation" end
	local dealt = math.min(damage, targetHP)
	local value = math.max(tonumber(c.targetValue) or 100, 30)
	local selfValue = math.max(tonumber(c.selfValue) or 100, 30)
	local valueRemoved = value * dealt / maxHP
	local loss = c.consumable and selfValue or selfValue * retaliation / math.max(c.maxHP or 100, 1)
	local threat = SC5.Clamp(c.threat, 0, 3)
	if c.city and not (c.capture and kill) then
		-- Bombard to support a real assault, never repeatedly pound a city at 1 HP.
		valueRemoved = valueRemoved * (c.capturerNear and 1.0 or 0.22)
	elseif kill then
		valueRemoved = valueRemoved + value * (0.65 + threat * 0.20)
	end
	if c.consumable and valueRemoved * (1 + threat * 0.25) < selfValue * 0.55 then
		return nil, "save-ammunition"
	end
	local score = valueRemoved * (1 + threat * 0.35) - loss * (c.protected and 2.5 or 1.5)
	score = score + math.max(tonumber(c.scriptValue) or 0, 0)
	if c.capture and kill then score = score + 1800 + value end
	if c.city and c.capturerNear and dealt >= targetHP - 1 then score = score + 400 end
	score = score + SC5.Clamp(c.focusBonus, 0, 120)
	if score <= 0 then return nil, "unfavorable-exchange" end
	return score, "damage="..math.floor(dealt).."/"..math.floor(targetHP)..
		",return="..math.floor(retaliation)..",kill="..tostring(kill)..
		",value="..math.floor(valueRemoved)..",loss="..math.floor(loss)..
		",script="..math.floor(c.scriptValue or 0)
end

function SC5.Finance(c)
	local gold = math.max(c.gold or 0, 0)
	local burn = math.max(-(c.goldRate or 0), 0)
	local reserveTurns = c.atWar and 8 or 12
	local operating = math.max((c.unitCost or 0) * 2, (c.cities or 1) * 100)
	local reserve = math.max(operating, burn * reserveTurns)
	local runway = burn > 0 and gold / burn or 9999
	local crisis = runway < reserveTurns and "deficit" or (c.happiness or 0) < 0 and "happiness" or "stable"
	return {
		reserve = math.floor(reserve), spendable = math.max(0, gold - reserve),
		runway = runway, crisis = crisis,
		militaryFraction = crisis == "deficit" and 0.05 or c.atWar and 0.30 or 0.06,
		goldWeight = runway < reserveTurns and 3 or runway < 20 and 1.8 or 0.9,
	}
end

function SC5.BuildingScore(c)
	local turns = math.max(c.turns or 1, 1)
	local horizon = c.atWar and 25 or 40
	local weights = c.weights or { food = 20, production = 30, gold = 16, science = 25, culture = 12, faith = 8 }
	local perTurn = 0
	for yield, value in pairs(c.yields or {}) do
		perTurn = perTurn + value * (weights[yield] or 0)
	end
	perTurn = perTurn - (c.maintenance or 0) * (weights.gold or 16)
	local productiveTurns = math.max(4, horizon - turns)
	local score = perTurn * productiveTurns / horizon / (1 + turns / 12)
	-- One-time utility is earned when completion happens, not immediately.
	score = score + (c.utility or 0) / (1 + turns / 15)
	return score, "netYield="..math.floor(perTurn)..",turns="..math.ceil(turns)..",horizon="..horizon
end

function SC5.Posture(c)
	if not c.atWar then return "peace" end
	-- Casualties can demand reinforcements without cancelling a winning offensive.
	if (c.offensiveRatio or 0) >= 1.4 and c.hasCapturer then return "decapitation" end
	if (c.defensiveRatio or 9) < 0.85 then return "defend" end
	return "advance"
end

function SC5.OperationProgress(previous, current)
	local advanced = previous == nil or current.distance < previous.distance
		or current.hp < previous.hp or current.enemyPower < previous.enemyPower * 0.8
	current.lastProgress = advanced and current.turn or previous.lastProgress
	local idle = math.max(0, current.turn - current.lastProgress)
	return idle < 3 and 900 / (1 + idle) or 0, current, idle
end

function SC5.EliteInvestment(c)
	if c.project and c.danger then return nil, "front-needs-immediate-force" end
	if c.crisis == "deficit" and not c.danger then return nil, "repair-finances-first" end
	local deficit = (c.target or 0) - (c.current or 0) - (c.queued or 0)
	if deficit > 0 then return 1 + math.min(deficit / math.max(c.target or 1, 1), 1), "fill-role-deficit" end
	if (c.current or 0) > 0 and (c.power or 0) >= math.max(c.bestPower or 0, 1) * 1.35 then
		return 0.9, "replace-with-generation-advantage"
	end
	return nil, "no-role-or-quality-deficit"
end

function SC5.Rank(candidates, scorer)
	local ranked, rejected = {}, {}
	for _, candidate in ipairs(candidates) do
		local score, reason = scorer(candidate)
		if score ~= nil then
			ranked[#ranked + 1] = { candidate = candidate, score = score, reason = reason }
		else
			rejected[reason or "unknown"] = (rejected[reason or "unknown"] or 0) + 1
		end
	end
	table.sort(ranked, function(a, b)
		if a.score == b.score then return tostring(a.candidate.key) < tostring(b.candidate.key) end
		return a.score > b.score
	end)
	return ranked[1], ranked, rejected
end
