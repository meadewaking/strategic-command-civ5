-- Exercise the deployed movement planner with explicit world/path fixtures.
dofile(assert(arg[2], "offline bootstrap required"))
local planner = SC_FindStrategicMovePlan
local original = getfenv(planner)
local scoreIndex, oldScore
for i = 1, 100 do
	local name, value = debug.getupvalue(planner, i)
	if name == nil then break end
	if name == "SC_ScoreStrategicTarget" then scoreIndex, oldScore = i, value; break end
end
assert(scoreIndex, "planner scorer dependency missing")
local function plot(x)
	return { GetX = function() return x end, GetY = function() return 0 end }
end
local origin = plot(0)
local unit = { GetUnitType = function() return 99099 end, GetPlot = function() return origin end }
GameInfo.Units[99099] = { ID = 99099, Type = "UNIT_TEST_PLANNER", Domain = "DOMAIN_LAND", Combat = 100, Moves = 3 }
local player = { GetTeam = function() return 0 end }
local targets, searches = {}, 0
for i = 1, 40 do
	local p = plot(i)
	targets[#targets + 1] = { GetPlot = function() return p end, GetOwner = function() return 1 end, GetID = function() return p:GetX() end }
end
local env = setmetatable({
	SC5 = false,
	Teams = { [0] = {} },
	Map = { PlotDistance = function(x, y, a, b) return math.abs(x - a) end },
	SC_GetUnitCombatTag = function() return "test" end,
	SC_GetUnitCapabilityProfile = function() return { doctrineClass = "ranged_support" } end,
	SC_GetUnitTurnKey = function() return "test" end,
	SC_ShouldPursueStrategicEnemyUnit = function() return true end,
	SC_IsDedicatedCityCaptureUnit = function() return false end,
	SC_GetStrategicTargetKey = function(p) return tostring(p:GetX()) end,
	SC_GetStrategicTargetCapacity = function() return 1 end,
	SC_GetStrategicTargetMemoryBonus = function() return 0, nil, 0 end,
	SC_GetStrategicCommitmentPenalty = function() return 0, 0 end,
	SC_IsStrategicRangedUnit = function() return true end,
	SC_FindStandoffMovePlot = function(_, _, _, target)
		searches = searches + 1
		if searches <= 3 then return nil end
		return plot(1)
	end,
	SC_GetStablePlotKey = function(p) return tostring(p:GetX()) end,
	SCX_GetExecutionTargetPool = function() return { cities = {}, units = targets }, "fixture" end,
	SC_IsEnemyTargetUnitValid = function() return true end,
	SC_EXECUTION_REJECTED_MOVE_PLOTS_THIS_TURN = {},
	SC_Debug = function() end,
}, { __index = original })
setfenv(planner, env)
debug.setupvalue(planner, scoreIndex, function(_, _, _, _, target) return 2000 - target:GetX(), "fixture" end)
local ok, result, stats = pcall(planner, player, unit, {})
setfenv(planner, original)
debug.setupvalue(planner, scoreIndex, oldScore)
assert(ok, result)
assert(searches == 6 and stats.availableTargets == 40, "expensive search not bounded independently of world scan")
assert(result ~= nil and stats.noMovePlot == 3, "blocked top choices prevented feasible alternatives")
print("PASS deployed movement planner: 40 targets, 6 position searches, fallback after 3 blocked targets")
