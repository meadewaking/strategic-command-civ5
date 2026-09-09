-- Real main/module integration. Native fixtures expose only named methods.
dofile(assert(arg[2], "offline bootstrap required"))
local checks = 0
local function check(value, reason) assert(value, reason); checks = checks + 1 end
check(SC_GetUnitRole == nil and SC_GetUnitInfo == nil, "private helpers leaked into global test environment")
local turn = 217
Game.GetGameTurn = function() return turn end
GameDefines = { MOVE_DENOMINATOR = 60 }
local plots, units, cities = {}, { [0] = {}, [1] = {} }, { [0] = {}, [1] = {} }
local function list(values)
	local index = 0
	return function() index = index + 1; return values[index] end
end
local function plot(x, y)
	local key = x..":"..y
	if plots[key] then return plots[key] end
	local p = { x = x, y = y, water = false, owner = -1, visible = true, stack = {} }
	function p:GetX() return self.x end
	function p:GetY() return self.y end
	function p:GetPlotIndex() return (self.x + 100) * 300 + self.y + 100 end
	function p:IsWater() return self.water end
	function p:IsVisible() return self.visible end
	function p:IsRevealed() return self.visible end
	function p:GetOwner() return self.owner end
	function p:IsCity() return self.city ~= nil end
	function p:GetPlotCity() return self.city end
	function p:GetNumUnits() return #self.stack end
	function p:GetUnit(i) return self.stack[i + 1] end
	function p:GetBestDefender(owner, attackingPlayer, attacker, war, potential, canMove)
		check(owner == -1 and attackingPlayer == attacker:GetOwner() and war == 1 and potential == 0 and canMove == 0,
			"native defender selector signature or integer flags incorrect")
		return self.defender
	end
	plots[key] = p
	return p
end
Map = {}
Map.PlotDistance = function(x, y, a, b) return (math.abs(x-a) + math.abs(y-b) + math.abs(x+y-a-b)) / 2 end
Map.GetPlot = plot
local directions = { {1,0}, {0,1}, {-1,1}, {-1,0}, {0,-1}, {1,-1} }
Map.PlotDirection = function(x, y, i) return plot(x + directions[i+1][1], y + directions[i+1][2]) end
Teams = { [0] = { IsAtWar = function(_, id) return id == 1 end },
	[1] = { IsAtWar = function(_, id) return id == 0 end } }
Players = {}
for id = 0, 1 do
	local p = { id = id }
	function p:GetID() return self.id end
	function p:GetTeam() return self.id end
	function p:IsAlive() return true end
	function p:IsMinorCiv() return false end
	function p:IsBarbarian() return false end
	function p:Units() return list(units[self.id]) end
	function p:Cities() return list(cities[self.id]) end
	function p:GetUnitByID(uid) for _, u in ipairs(units[self.id]) do if u.id == uid and not u.dead then return u end end end
	function p:GetCityByID(cid) for _, c in ipairs(cities[self.id]) do if c.id == cid then return c end end end
	Players[id] = p
end
GameInfo.Units[99001] = { ID=99001, Type="UNIT_MECH", Combat=500, RangedCombat=500, Range=5, Moves=12,
	Domain="DOMAIN_LAND", CombatClass="UNITCOMBAT_ARMOR", Cost=3000 }
GameInfo.Units[99002] = { ID=99002, Type="UNIT_TEST_BOMBER", Combat=0, RangedCombat=100, Range=5, Moves=2,
	Domain="DOMAIN_AIR", CombatClass="UNITCOMBAT_BOMBER", Cost=700 }
GameInfo.Units[99003] = { ID=99003, Type="UNIT_TEST_ARTILLERY", Combat=30, RangedCombat=100, Range=3, Moves=3,
	Domain="DOMAIN_LAND", CombatClass="UNITCOMBAT_SIEGE", Cost=600 }
SC_UNIT_CAPABILITY_CACHE = {}
local function makeUnit(id, owner, kind, p)
	local u = { id=id, owner=owner, kind=kind, p=p, hp=100, moves=180, power=40, damageOut=70, shots=0 }
	function u:GetID() return self.id end
	function u:GetOwner() return self.owner end
	function u:GetUnitType() return self.kind end
	function u:GetPlot() return self.p end
	function u:GetDamage() return 100-self.hp end
	function u:GetMaxHitPoints() return 100 end
	function u:GetMaxAttackStrength() return self.power*100 end
	function u:GetMaxDefenseStrength() return self.power*100 end
	function u:GetCombatDamage(a,b,damage,random,attackingCity) return attackingCity and 1 or 20 end
	function u:GetRangeCombatDamage(enemy) return enemy and enemy.power > 100 and 1 or self.damageOut end
	function u:GetAirStrikeDefenseDamage() return self.power > 100 and 1018 or 1 end
	function u:Range() return GameInfo.Units[self.kind].Range end
	function u:MaxMoves() return GameInfo.Units[self.kind].Moves*60 end
	function u:MovesLeft() return self.moves end
	function u:CanMove() return self.moves > 0 and not self.dead end
	function u:IsReadyToMove() return self:CanMove() end
	function u:ReadyToMove() return self:CanMove() end
	function u:CanRangeStrikeAt(x, y)
		return self:CanMove() and Map.PlotDistance(self.p.x,self.p.y,x,y) <= self:Range()
	end
	function u:RangeStrike(x, y)
		local target = plot(x,y).defender
		assert(target, "fixture shot without native defender")
		self.lastShot = target.id
		target.hp = math.max(0, target.hp-self:GetRangeCombatDamage(target))
		target.dead = target.hp <= 0
		self.shots, self.moves = self.shots+1, 0
	end
	function u:PushMission(mission, x, y, flags, append, manual, missionAI)
		assert(missionAI == -1, "targeted mission passed invalid MissionAI")
		-- Explicit accepted/no-effect fixture, exercising the native fallback.
	end
	function u:IsInvisible() return false end
	function u:IsDead() return self.dead == true end
	function u:IsEmbarked() return false end
	function u:IsHasPromotion() return false end
	function u:IsNoCapture() return false end
	function u:IsCombatUnit() return true end
	function u:GetCargo() return 0 end
	function u:GetBestInterceptor() return nil end
	function u:CanMoveInto(p) return not p.blocked and not p.city and p.owner ~= 1 end
	function u:GetName() return GameInfo.Units[self.kind].Type end
	units[owner][#units[owner]+1] = u
	p.stack[#p.stack+1] = u
	return u
end
local actor = makeUnit(1, 0, 99001, plot(0,0))
local city = { id=7, p=plot(1,0) }
function city:Plot() return self.p end
function city:GetOwner() return 1 end
function city:GetID() return self.id end
function city:GetDamage() return 0 end
function city:GetMaxHitPoints() return 200 end
function city:GetStrengthValue() return 1000 end
function city:GetPopulation() return 10 end
city.p.city, city.p.owner = city, 1
cities[1] = { city }
check(SC5.CanFinishCity(Players[0], actor, city), "actual main role/profile integration cannot finish full-HP city")
check(SC5.CityHasFinisher(Players[0], city), "city board finisher scan failed through real private role helper")
SC_ENEMY_TARGET_POOL_THIS_TURN = {}
local tasks = SC_BuildCityCaptureTasks(Players[0])
check(#tasks == 1 and #tasks[1].assigned == 1 and tasks[1].assigned[1].unitID == actor.id,
	"real capture board did not reserve the lethal full-HP city opportunity")
actor.moves = 0
check(not SC5.CanFinishCity(Players[0], actor, city), "spent actor selected as finisher")
actor.moves = 180

-- The weak cargo is deliberately first in the stack; the native hull is second.
local bomber = makeUnit(2, 0, 99002, plot(0,1))
local cargo = makeUnit(10, 1, 99003, plot(3,0))
cargo.hp = 1
local hull = makeUnit(11, 1, 99001, cargo.p)
hull.hp, hull.power = 90, 500
cargo.p.defender = hull
local score, reason = SC5.ScoreRangedTarget(Players[0], bomber, cargo)
check(score < 0 and reason == "not-native-defender", "untargetable weak cargo still creates false kill score")
score, reason = SC5.ScoreRangedTarget(Players[0], bomber, hull)
check(score < 0, "native 1018 retaliation accepted for bomber")
local facts = SC5.LogAttackFacts(Players[0], bomber, cargo.p)
check(facts.enemyID == hull.id and facts.targetHP == 90 and facts.damage == 1, "logged target differs from native hull")
local actualScore, _, actualFacts = SC5.ScoreRangedTarget(Players[0], actor, hull)
check(actualScore > 0 and actualFacts.enemyID == hull.id, "safe overmatching ranged attack incorrectly blocked")
local rejected = SC5.LogAttackFacts(Players[0], actor, cargo.p, { decisionID=9, bestFacts={ enemyID=cargo.id, enemyOwner=1 } })
check(rejected == nil, "defender swap did not cancel stale selection")
local oldSelector = cargo.p.GetBestDefender
cargo.p.GetBestDefender = nil
check(not pcall(SC5.ScoreRangedTarget, Players[0], actor, hull), "missing mandatory API did not fail the military module")
cargo.p.GetBestDefender = oldSelector

-- Survival uses native enemy previews and real six-neighbor movement, not a
-- Python combat score. Successful fixture shots consume all remaining movement.
local artillery = makeUnit(3, 0, 99003, plot(0,0))
units[0], units[1], cities[1] = { artillery }, { cargo }, {}
cargo.hp, cargo.p = 100, plot(2,0)
artillery.hp = 4
SCX_InvalidateExecutionWorld("fixture")
local logs, movementCalls = {}, 0
local adapter = SC_GetV3Adapters()
local nativeReserve = adapter.reserveWithdrawal
adapter.log = function(s) logs[#logs+1] = s end
adapter.getUnitDebugLabel = function(u) return "fixture#"..u.id end
adapter.survivalMove = function(u, p)
	movementCalls = movementCalls+1
	u.p, u.moves = p, u.moves-60
	return true, "moved", u
end
adapter.reserveWithdrawal = function(u) nativeReserve(u) end
local initial = SC5.PlotExposure(artillery.p, SC5.ThreatSources(Players[0], artillery))
check(SC5.RunSurvival(Players[0], true, adapter) == 1 and movementCalls > 0, "4 HP artillery fired before possible escape")
check(SC5.IsWithdrawing(artillery), "withdrawal reservation absent")
local after = SC5.PlotExposure(artillery.p, SC5.ThreatSources(Players[0], artillery))
check(after < initial, "successful withdrawal did not reduce predicted exposure")
check(SC5.ScoreRangedTarget(Players[0], artillery, cargo) < 0, "later fire phase overwrote withdrawal")
check(SC_GetStrategicOrderCount(SC_GetUnitTurnKey(artillery)) > 0, "real strategic mover not reserved")
turn = turn+1
check(not SC5.IsWithdrawing(artillery), "withdrawal leaked into next turn")
check(not SC5.NeedsWithdrawal(100, 2, true), "technological superiority turned into indiscriminate retreat")
check(SC5.NeedsWithdrawal(100, 100, true), "full HP elite ignores lethal enemy-turn fire")
check(not SC5.NeedsWithdrawal(4, 0, true), "safe wounded unit forced to retreat")
local land, sea = plot(30,0), plot(30,1)
sea.water = true
local restricted = { { x=30,y=0,range=5,move=0,damage=80,domainOnly=true,domain="DOMAIN_SEA" } }
check(SC5.PlotExposure(land,restricted) == 0 and SC5.PlotExposure(sea,restricted) == 80,
	"sea-only submarine threat causes land army to flee")
artillery.p, artillery.moves = plot(0,0), 180
movementCalls = 0
adapter.survivalMove = function(u) movementCalls = movementCalls+1; return false, "no-state-change", u end
SCX_InvalidateExecutionWorld("fixture-failed-path")
check(SC5.RunSurvival(Players[0], true, adapter) == 0, "accepted no-op counted as escape")
check(not SC5.IsWithdrawing(artillery) and movementCalls <= 6, "failed paths consume all future offensive opportunities")

-- Execute the real target pool, scorer, selection loop, mission fallback and
-- outcome logger. A tempting 1 HP cargo must not steal the shot from a killable
-- independent target. The fake native strike obeys the observed all-moves cost.
turn = turn+1
actor.p, actor.moves, actor.shots = plot(0,0), 180, 0
cargo.p, cargo.hp, hull.p = plot(3,0), 1, plot(3,0)
units[0], units[1] = {actor}, {cargo, hull}
cargo.p.stack, cargo.p.defender = {cargo,hull}, hull
local exposed = makeUnit(12,1,99003,plot(3,1))
exposed.hp, exposed.p.defender = 70, exposed
SC_CITY_CAPTURE_ASSIGNMENTS_THIS_TURN = {}
SC_HEAL_HANDLED_THIS_TURN = {}
SC_TACTICAL_ORDERED_THIS_TURN = {}
SC_TACTICAL_NO_TARGET_THIS_TURN = {}
SC_CONFIG.AutoLocalDefense = true
SCX_InvalidateExecutionWorld("fixture-real-fire")
local count = SC_GetV3Adapters().localDefense(Players[0],true)
check(count == 1 and actor.shots == 1 and actor.lastShot == exposed.id, "real fire pipeline chose cargo or failed to execute")
check(actor.moves == 0 and exposed.dead and hull.hp == 90, "native outcome diverged from chosen defender")
SC5.IsWithdrawing(actor)
SC5.withdrawn["0:1"] = true
actor.moves = 180
local fireOK, fireReason = SC_GetV3Adapters().rangeStrike(actor,hull.p)
check(not fireOK and fireReason == "withdrawal-reserved", "direct fire adapter bypassed withdrawal reservation")
local moveOK, moveReason = SC_GetV3Adapters().survivalMove(actor,plot(-1,0))
check(moveReason ~= "withdrawal-reserved", "withdrawal reservation blocked continued emergency escape")

local chain = makeUnit(4,0,99003,plot(0,0))
local chainID = GameInfoTypes.PROMOTION_CHAIN_REACTION
chain.IsHasPromotion = function(_, id) return id == chainID end
local distant = makeUnit(13,1,99003,plot(20,20))
SCX_InvalidateExecutionWorld("fixture-chain")
local chainFacts = SC5.AttackFacts(Players[0],chain,hull,nil,false)
check(chainFacts.scriptValue > 0 and chainFacts.scriptCount == 2,
	"chain forecast missed visible same-owner units outside ordinary range")
check(SC5.AttackScore(chainFacts) > actualScore, "chain payoff ignored in final score")
distant.p.visible = false
SCX_InvalidateExecutionWorld("fixture-chain-fog")
local fogFacts = SC5.AttackFacts(Players[0],chain,hull,nil,false)
check(fogFacts.scriptCount == 1 and fogFacts.scriptValue < chainFacts.scriptValue, "hidden unit included in chain reward")
local lethalFacts = SC5.AttackFacts(Players[0],chain,cargo,nil,false)
check(lethalFacts.scriptReason == "chain-trigger-may-die" and lethalFacts.scriptValue == nil,
	"lethal primary target incorrectly guarantees CombatEnded chain")
local cityFacts = SC5.AttackFacts(Players[0],chain,nil,city,false)
check(cityFacts.scriptValue == nil, "city bombardment given unit-only chain payoff")
local moveAfterID, logisticsID = GameInfoTypes.PROMOTION_CAN_MOVE_AFTER_ATTACKING, GameInfoTypes.PROMOTION_LOGISTICS
chain.IsHasPromotion = function(_, id) return id==chainID or id==moveAfterID or id==logisticsID end
check(not SC5.HasChainReaction(chain), "early-return promotion combination still counted as active chain")

-- Inject an actual Lua exception: no subsequent fire, wait, blocker or end-turn
-- callback may run. Use the real adapter-backed module runner, not a success stub.
local phases, halted = {}, 0
local engineAdapters = {
	log=function() end, getTurn=function() return turn end,
	getConfig=function(_, fallback) return fallback end,
	runCount=function(_, callback)
		local ok, n = pcall(callback)
		if not ok then return 0, nil, 1 end
		return n or 0, nil, 0
	end,
	haltTakeover=function() halted=halted+1 end,
	refreshTacticalWorld=function() end,
}
for _, name in ipairs({"upgrades","promotions","survival","airRebase","capture","airSuperiority","localDefense",
	"cityStrike","healing","transportEscort","strategicMovement","stacked","idlePosture","finalOrders"}) do
	local key = name
	engineAdapters[key] = function()
		phases[#phases+1] = key
		if key == "capture" then error("regression missing adapter") end
		return 0
	end
end
local actualSpecial = SCV3_RunSpecialWeapons
SCV3_RunSpecialWeapons = function() return 0 end
SCV3.criticalFault = nil
SCX_RunExecutionMilitary(Players[0], true, engineAdapters, SCV3_NewResults())
check(halted == 1 and SCV3.criticalFault ~= nil, "critical error did not latch takeover stop")
check(phases[#phases] == "capture", "fire or cleanup ran after capture module failure")
local called = false
SCV3_RunModule(engineAdapters, "blocker", function() called=true; return 1 end)
check(not called, "light/blocker callback bypassed military safety latch")
SCV3.criticalFault = nil
SCV3_RunSpecialWeapons = actualSpecial
print("PASS real-main combat integration: "..checks.." checks")
