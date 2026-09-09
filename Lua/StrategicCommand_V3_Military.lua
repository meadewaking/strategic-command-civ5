-- Strategic Command V3: explicit joint-operations phase ownership.

function SCV3_RunMilitary(player, atWar, adapters, results)
	local function run(name, resultKey, callback)
		local count, _, errors = SCV3_RunModule(adapters, "military."..name, callback)
		SCV3_AddResult(results, resultKey, count, errors)
		return count
	end
	adapters.log("V3 military phase=readiness begin")
	run("upgrade", "upgrades", function() return adapters.upgrades(player) end)
	run("promotion", "promotions", function() return adapters.promotions(player) end)
	run("heal", "heals", function() return adapters.healing(player) end)

	adapters.log("V3 military phase=logistics begin")
	run("transport", "transportEscort", function() return adapters.transportEscort(player, atWar) end)
	run("airRebase", "strategicMoves", function() return adapters.airRebase(player, atWar) end)

	adapters.log("V3 military phase=opening-fire begin")
	run("specialWeapons", "specialWeapons", function() return SCV3_RunSpecialWeapons(player, atWar, adapters) end)
	run("captureBeforeFire", "captureFinishers", function() return adapters.capture(player, atWar) end)
	local openingAir = run("airSuperiority", "defenseActions", function() return adapters.airSuperiority(player, atWar) end)
	local openingFire = run("localDefense", "defenseActions", function() return adapters.localDefense(player, atWar) end)
	local openingCity = run("cityStrike", "cityStrikes", function() return adapters.cityStrike(player, atWar) end)
	if openingAir + openingFire + openingCity > 0 then
		adapters.refreshTacticalWorld(player, "after-opening-fire")
	end
	run("captureAfterFire", "captureFinishers", function() return adapters.capture(player, atWar) end)

	adapters.log("V3 military phase=maneuver begin")
	local moves = run("strategicMovement", "strategicMoves", function() return adapters.strategicMovement(player, atWar) end)

	-- Movement can expose targets or place a capturer next to a zero-HP city.
	adapters.log("V3 military phase=exploitation begin")
	if moves > 0 then adapters.refreshTacticalWorld(player, "after-maneuver") end
	run("specialWeaponsAfterMove", "specialWeapons", function() return SCV3_RunSpecialWeapons(player, atWar, adapters) end)
	local exploitAir = run("airAfterMove", "defenseActions", function() return adapters.airSuperiority(player, atWar) end)
	local exploitFire = run("fireAfterMove", "defenseActions", function() return adapters.localDefense(player, atWar) end)
	if exploitAir + exploitFire > 0 then
		adapters.refreshTacticalWorld(player, "after-exploitation-fire")
	end
	run("captureAfterMove", "captureFinishers", function() return adapters.capture(player, atWar) end)

	adapters.log("V3 military phase=cleanup begin")
	run("stacked", "stackedMoves", function() return adapters.stacked(player) end)
	run("idlePosture", "idlePosture", function() return adapters.idlePosture(player) end)
	run("finalOrders", "finalOrders", function() return adapters.finalOrders(player, atWar) end)
end
