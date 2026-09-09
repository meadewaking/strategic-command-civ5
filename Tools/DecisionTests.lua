-- Behavioral tests of the deployed Lua, using explicit native API fixtures.
local mod = assert(arg[1], "mod directory required")
local function load(name) dofile(mod.."/Lua/"..name..".lua") end
load("StrategicCommand_Decisions")
load("StrategicCommand_CombatModel")
load("StrategicCommand_Development")
local tests = 0
local function check(condition, message)
	assert(condition, message)
	tests = tests + 1
end
local function copy(value, changes)
	local result = {}
	for key, item in pairs(value) do result[key] = item end
	for key, item in pairs(changes or {}) do result[key] = item end
	return result
end
local base = { key = "tank", hp = 100, maxHP = 100, damage = 100, retaliation = 0,
	targetHP = 100, targetMaxHP = 100, targetValue = 1000, selfValue = 400,
	authorized = true, threat = 1 }
local kill = SC5.AttackScore(base)
local scratch = SC5.AttackScore(copy(base, { damage = 5 }))
check(kill > scratch, "finishing an active enemy must beat ineffective chip damage")
check(SC5.AttackScore(copy(base, { authorized = false })) == nil, "peace target allowed")
check(SC5.AttackScore(copy(base, { hp = 0 })) == nil, "dead actor assigned an attack")
check(SC5.AttackScore(copy(base, { hp = 20, retaliation = 18 })) == nil, "lethal retaliation allowed")
check(SC5.AttackScore(copy(base, { hp = 20 })) ~= nil, "safe wounded ranged attacker forbidden")
check(SC5.AttackScore(copy(base, { hp = 20, uncertainty = 25 })) == nil, "uncertain interception can kill wounded aircraft")
check(SC5.AttackScore(copy(base, { uncertainty = 25 })) == SC5.AttackScore(base), "survival uncertainty treated as guaranteed economic loss")
check(SC5.AttackScore(copy(base, { consumable = true, selfValue = 5000, targetHP = 4, targetValue = 50 })) == nil,
	"expensive ammunition wasted on a nearly dead cheap unit")
check(SC5.AttackScore(copy(base, { city = true, targetHP = 1 })) == nil, "bombardment wasted on 1 HP city")
check(SC5.AttackScore(copy(base, { city = true, capture = true, targetHP = 200, damage = 250 })) ~= nil,
	"overmatching melee unit cannot finish an undamaged city")
check(SC5.AttackScore(copy(base, { city = true, capture = true, targetHP = 200, damage = 190 })) == nil,
	"nonlethal city melee attack passed the finisher gate")
local noFinisher = SC5.AttackScore(copy(base, { city = true, capturerNear = false }))
local finisher = SC5.AttackScore(copy(base, { city = true, capturerNear = true }))
check(finisher > noFinisher, "unexploitable siege received the same priority as supported capture")
local first = SC5.Rank({ copy(base, { key = "z" }), copy(base, { key = "a" }) }, SC5.AttackScore)
check(first.candidate.key == "a", "tie breaking must be deterministic")

local rich = SC5.Finance({ gold = 1000000, goldRate = -7000, unitCost = 10000, cities = 32, atWar = true })
local bankrupt = SC5.Finance({ gold = 10000, goldRate = -7000, cities = 32, atWar = true })
check(rich.crisis == "stable" and rich.spendable > 900000, "large treasury incorrectly forced austerity")
check(bankrupt.crisis == "deficit" and bankrupt.spendable == 0, "bankruptcy failed to protect operating cash")
check(SC5.Posture({ atWar = true, offensiveRatio = 8.7, defensiveRatio = 0.65, hasCapturer = true }) == "decapitation",
	"local winning attack cancelled by unrelated defensive pressure")
check(SC5.Posture({ atWar = true, offensiveRatio = 0.5, defensiveRatio = 0.65, hasCapturer = true }) == "defend",
	"weak force did not defend")

local function rows(values)
	local index = {}
	for _, v in ipairs(values) do if v.ID then index[v.ID] = v end; if v.Type then index[v.Type] = v end end
	return setmetatable(index, { __call = function(_, filter)
		local i = 0
		return function()
			while i < #values do
				i = i + 1
				local match = true
				for key, value in pairs(filter or {}) do if values[i][key] ~= value then match = false end end
				if match then return values[i] end
			end
		end
	end })
end
Game = { GetGameTurn = function() return 1 end }
GameDefines = { MOVE_DENOMINATOR = 60 }
YieldTypes = { YIELD_FOOD = 0, YIELD_PRODUCTION = 1, YIELD_GOLD = 2, YIELD_SCIENCE = 3, YIELD_CULTURE = 4, YIELD_FAITH = 5 }
GameInfo = {
	Units = rows({
		{ ID = 1, Type = "UNIT_MECH", Cost = 2000, Domain = "DOMAIN_LAND" },
		{ ID = 2, Type = "UNIT_TANK", Cost = 500, Domain = "DOMAIN_LAND" },
		{ ID = 3, Type = "UNIT_AIRCRAFT", Cost = 700, Domain = "DOMAIN_AIR" },
	}),
	Building_YieldChanges = rows({ { BuildingType = "FACTORY", YieldType = "YIELD_PRODUCTION", Yield = 4 } }),
	Building_YieldModifiers = rows({ { BuildingType = "LAB", YieldType = "YIELD_SCIENCE", Yield = 50 } }),
	Building_ResourceYieldChanges = rows({ { BuildingType = "MINT", ResourceType = "GOLD", YieldType = "YIELD_GOLD", Yield = 5 } }),
	Specialists = rows({}), Buildings = rows({}),
}
local function city(id, science)
	return {
		GetID = function() return id end, GetPopulation = function() return 10 end,
		GetYieldRate = function(_, yield) return yield == 3 and science or yield == 1 and 20 or 0 end,
		GetNumCityPlots = function() return 0 end, IsOccupied = function() return false end,
		GetBuildingProductionTurnsLeft = function() return 5 end,
	}
end
local player = { GetID = function() return 0 end, GetTeam = function() return 0 end }
SC_STRATEGY_STATE = { world = { happiness = 10, atWar = false }, national = { priorities = {} } }
function SC_StrategyGetCityRole() return "science" end
local lab = { ID = 1, Type = "LAB", Cost = 100 }
local bigLab = SC5.ScoreBuilding(player, city(1, 200), lab)
local smallLab = SC5.ScoreBuilding(player, city(2, 10), lab)
check(bigLab > smallLab * 5, "percentage building ignores actual city yields")
local mint = SC5.ScoreBuilding(player, city(3, 10), { ID = 2, Type = "MINT", Cost = 100 })
check(mint == 0, "conditional resource benefit fabricated without worked resources")
local maintenance = SC5.BuildingScore({ yields = { gold = 1 }, maintenance = 10, turns = 5 })
check(maintenance < 0, "maintenance ignored by economic score")

local native = { damage = 45, retaliation = 12 }
local function plot(x, y)
	return { GetX = function() return x end, GetY = function() return y end,
		IsVisible = function() return true end, IsRevealed = function() return true end,
		IsCity = function() return false end }
end
local function unit(id, kind, x, y)
	return {
		GetID = function() return id end, GetOwner = function() return id < 10 and 0 or 1 end,
		GetUnitType = function() return kind end, GetPlot = function() return plot(x, y) end,
		GetDamage = function() return 0 end, GetMaxHitPoints = function() return 100 end,
		CanMove = function() return true end, IsInvisible = function() return false end,
		GetMaxAttackStrength = function() return 50000 end, GetMaxDefenseStrength = function() return 50000 end,
		GetCombatDamage = function(_, a, b, damage, random, attackingCity) return attackingCity and native.retaliation or native.damage end,
		GetRangeCombatDamage = function() return native.damage end,
		GetAirStrikeDefenseDamage = function() return native.retaliation end,
		GetBestInterceptor = function() return nil end,
		Range = function() return 5 end, MaxMoves = function() return 420 end,
		IsNoCapture = function() return false end,
	}
end
function SC_GetUnitCapabilityProfile() return { canCapture = true, power = 200, range = 5, canRange = true } end
function SC_IsDedicatedCityCaptureUnit() return true end
function SC_GetCityCaptureOneTurnReach() return 3 end
function SC_GetUnitProtectionTier() return 2 end
Map = { PlotDistance = function(x, y, a, b) return math.max(math.abs(x - a), math.abs(y - b)) end }
local mech = unit(1, 1, 0, 0)
local enemyMech = unit(10, 1, 1, 0)
local enemyTank = unit(11, 2, 1, 0)
local same = SC5.Preview(mech, enemyMech, nil, true)
local different = SC5.Preview(mech, enemyTank, nil, true)
check(same.damage == 45 and different.damage == 100, "scripted mech kill applied to another mech")
local baseProfile = { range = 2, moves = 2, noCapture = false, canCapture = true }
local live = SC5.LiveProfile(mech, baseProfile)
check(live.range == 5 and live.moves == 7 and baseProfile.range == 2, "live promotions contaminated shared type profile")
local minimum, maximum, desired = SC5.Standoff(mech, 6, 10, 8)
check(maximum == 5 and desired == 5, "fire support placed outside its firing range")
check(SC5.ObservedUnit(player, mech), "visible unit hidden from planning")
local hidden = copy(mech, { GetPlot = function() return { IsVisible = function() return false end } end })
check(not SC5.ObservedUnit(player, hidden), "fog-of-war unit used in planning")
local enemyCity = {
	Plot = function() return plot(1, 0) end, GetDamage = function() return 0 end,
	GetMaxHitPoints = function() return 200 end, GetStrengthValue = function() return 5000 end,
}
check(SC5.CanFinishCity(player, mech, enemyCity), "full-health city excluded despite native/scripted lethal damage")
native.damage = 20
check(not SC5.CanFinishCity(player, unit(2, 2, 0, 0), enemyCity), "weak attack incorrectly marked capture ready")
native.damage = 100
local candidateA = copy(base, { key = "screen", damage = native.damage })
local candidateB = copy(base, { key = "second", targetValue = 600 })
local before = SC5.Rank({ candidateA, candidateB }, SC5.AttackScore)
candidateA.targetHP = 0
local after = SC5.Rank({ candidateA, candidateB }, SC5.AttackScore)
check(before.candidate.key == "screen" and after.candidate.key == "second", "volley did not retarget after confirmed kill")

-- Run the actual production military phase loop with callback spies.
load("StrategicCommand_V3_State")
local calls = {}
local function record(name) calls[#calls + 1] = name; return 0 end
SCV3_RunModule = function(_, _, callback) return callback(), nil, 0 end
SCV3_AddResult = function() end
SCV3_RunSpecialWeapons = function() return record("special") end
local adapters = { log = function() end, getConfig = function(_, fallback) return fallback end,
	refreshTacticalWorld = function() record("refresh") end }
for _, name in ipairs({ "upgrades", "promotions", "healing", "transportEscort", "airRebase", "capture",
	"airSuperiority", "localDefense", "cityStrike", "strategicMovement", "stacked", "idlePosture", "finalOrders" }) do
	local key = name
	adapters[key] = function(_, _, emergency)
		return record(key == "airRebase" and emergency and "airEvacuation" or key)
	end
end
adapters.survival = function() return record("survival") end
load("StrategicCommand_ExecutionMilitary")
SCX_RunExecutionMilitary(player, true, adapters, {})
local positions = {}
for i, name in ipairs(calls) do positions[name] = positions[name] or i end
check(positions.localDefense < positions.healing and positions.localDefense < positions.airRebase,
	"healing or rebasing consumed firing opportunity before opening combat")
check(positions.finalOrders > positions.strategicMovement, "cleanup ran before maneuver")
check(positions.survival < positions.localDefense and positions.airEvacuation < positions.localDefense,
	"emergency withdrawal must precede firing, ordinary rebase must follow it")

local lastHP = SC5.AttackScore(copy(base, { city = true, capture = true, damage = 10, targetHP = 1 }))
check(lastHP ~= nil, "1 HP city capture rejected by bombardment stop rule")
local noBomb = SC5.AttackScore(copy(base, { city = true, capture = false, damage = 10, targetHP = 1 }))
check(noBomb == nil, "1 HP city still consumes bombardment")
GameInfo.Civilizations = rows({ { ID = 0, Type = "CIV_TEST" } })
GameInfo.UnitClasses = rows({ { ID = 0, Type = "CLASS_TANK", DefaultUnit = "TANK" } })
GameInfo.Civilization_UnitClassOverrides = rows({ { CivilizationType = "CIV_TEST", UnitClassType = "CLASS_TANK", UnitType = "UNIQUE_TANK" } })
player.GetCivilizationType = function() return 0 end
check(SC5.CivilizationUnlock(player, { Class = "CLASS_TANK", Type = "UNIQUE_TANK" }, "unit"), "own unique ignored")
check(not SC5.CivilizationUnlock(player, { Class = "CLASS_TANK", Type = "TANK" }, "unit"), "replaced default counted twice")
check(not SC5.CivilizationUnlock(player, { Class = "CLASS_TANK", Type = "FOREIGN_TANK" }, "unit"), "foreign unique distorts research")
local boughtLab = SC5.ScoreBuilding(player, city(1, 200), lab, true)
check(boughtLab > bigLab, "purchased building penalized by production completion time")
local boosted = city(6, 200)
boosted.GetBaseYieldRate = function(_, yield) return yield == 3 and 100 or 0 end
local baseLab = SC5.ScoreBuilding(player, boosted, lab)
check(math.abs(baseLab * 2 - bigLab) < 0.001, "percentage yields compounded existing modifiers")
local assault = SC5.AttackScore(copy(base, { city = true, capture = true, targetHP = 200, damage = 190,
	assaultSupported = true, capturerNear = true }))
check(assault ~= nil, "supported nonlethal city assault cannot begin")
local bonus, progress = SC5.OperationProgress(nil, { turn = 1, distance = 8, hp = 200, enemyPower = 100 })
check(bonus > 0, "new operation lost all continuity")
local stuck = SC5.OperationProgress(progress, { turn = 4, distance = 8, hp = 200, enemyPower = 100 })
check(stuck == 0, "stalled operation keeps absolute target lock")
local advancing = SC5.OperationProgress(progress, { turn = 4, distance = 7, hp = 200, enemyPower = 100 })
check(advancing > 0, "moving army loses operation continuity")
check(SC5.EliteInvestment({ target = 5, current = 3, queued = 2, power = 100, bestPower = 100 }) == nil,
	"queued role supply ignored by elite production")
check(SC5.EliteInvestment({ target = 5, current = 3, power = 100, bestPower = 100 }) ~= nil,
	"needed elite role blocked")
check(SC5.EliteInvestment({ target = 5, current = 5, power = 200, bestPower = 100 }) ~= nil,
	"generation-leading elite blocked by adequate but obsolete army count")
check(SC5.EliteInvestment({ target = 5, current = 5, power = 110, bestPower = 100 }) == nil,
	"elite label alone creates unnecessary army expansion")
check(SC5.EliteInvestment({ target = 5, current = 0, project = true, danger = true }) == nil,
	"threatened city starts a long elite project")
check(SC5.EliteInvestment({ target = 5, current = 0, crisis = "deficit" }) == nil,
	"elite project crowds out urgent financial recovery")
check(SC5.EliteInvestment({ target = 5, current = 0, crisis = "deficit", danger = true }) ~= nil,
	"financial recovery blocks immediate defensive unit")
SC_STRATEGY_STATE.national.crisis = "happiness"
check(SC5.NeedsEconomicRelief(player, city(1, 200)), "happiness crisis did not get production priority")
check(SC5.IsEconomicRelief(player, city(1, 200), { Type = "STADIUM", Happiness = 4 }), "happiness relief building excluded")
check(not SC5.IsEconomicRelief(player, city(1, 200), lab), "science building disguised as happiness relief")
print("PASS deployed Lua decision behavior: "..tests.." assertions")
