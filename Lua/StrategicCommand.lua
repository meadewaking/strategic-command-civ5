-- Strategic Command
-- A high-level automation layer for late-game play.

include("StrategicCommand_Config.lua")

local SC_VERSION = "5.1"
local SC_LOAD_TURN = -1
local SC_SAVE_DATA = nil
local SC_TAKEOVER_SAVE_KEY = "SC_TAKEOVER_REMAINING"
local SC_CAPTURED_CITY_SAVE_KEY = "SC_CAPTURED_CITY_ACTION"
local SC_LAST_TAKEOVER_PASS_TURN = -1
local SC_LAST_TAKEOVER_PASS_COUNT = 0
SC_FULL_AUTOMATION_PASS_COUNT = 0
local SC_LAST_AUTO_END_TURN = -1
local SC_AUTO_END_SEND_COUNT_THIS_TURN = 0
local SC_AUTO_END_STALL_LOGGED_THIS_TURN = false
local SC_AUTO_END_POST_SEND_LOGGED_THIS_TURN = false
local SC_LAST_UNHANDLED_POPUP = "none"
local SC_AUTO_RETRY_ACCUMULATOR = 0
local SC_AUTO_RETRY_RUNNING = false
SC_STRATEGIC_ORDERED_THIS_TURN = {}
SC_TACTICAL_ORDERED_THIS_TURN = {}
SC_TACTICAL_NO_TARGET_THIS_TURN = {}
SC_TACTICAL_QUEUED_THIS_TURN = {}
SC_ASSAULT_SUPPORT_CACHE_THIS_TURN = {}
SC_PROTECTED_ASSET_CACHE_THIS_TURN = {}
SC_UNIT_CAPABILITY_CACHE = {}
SC_OPERATION_TARGET_CACHE_THIS_TURN = {}
SC_OPERATION_FOCUS_THIS_TURN = {}
SC_OPERATION_FOCUS_LOGGED_THIS_TURN = {}
SC_STRATEGIC_TARGET_COMMITMENTS_THIS_TURN = {}
SC_STRATEGIC_UNIT_TARGET_THIS_TURN = {}
SC_CITY_CAPTURE_TASKS_THIS_TURN = {}
SC_CITY_CAPTURE_ASSIGNMENTS_THIS_TURN = {}
SC_CITY_CAPTURE_TASK_LOGGED_THIS_TURN = {}
SC_DECAPITATION_FOCUS_THIS_TURN = {}
SC_RETREAT_THREAT_CACHE_THIS_TURN = {}
SC_SEA_THREAT_CACHE_THIS_TURN = {}
SC_MILITARY_ROSTER_CACHE_THIS_TURN = {}
SC_LEGACY_QUEUE_PRUNED = {}
SC_ELITE_PROJECT_UNIT_CACHE = {}
SC_AIRLIFT_BUILDING_IDS = nil
SC_STRATEGIC_TARGET_MEMORY = {}
SC_AIRLIFT_PENDING = {}
SC_AIRLIFT_RECENT_ROUTE = {}
SC_ENEMY_TARGET_POOL_THIS_TURN = {}
SC_RANGE_TARGET_STRIKE_COUNT_THIS_TURN = {}
SC_STACK_MOVE_ATTEMPTED_THIS_TURN = {}
SC_FINAL_ORDER_ATTEMPTED_THIS_TURN = {}
SC_TRANSPORT_ESCORT_ORDERED_THIS_TURN = {}
SC_TRANSPORT_ESCORT_FAILED_THIS_TURN = {}
SC_TRANSPORT_RELEASE_LOGGED_THIS_TURN = {}
SC_DIRECT_PUSH_FAILED_THIS_TURN = {}
SC_EXECUTION_REJECTED_MOVE_PLOTS_THIS_TURN = {}
SC_HEAL_FAILED_THIS_TURN = {}
SC_HEAL_HANDLED_THIS_TURN = {}
SC_RANGE_FAILED_THIS_TURN = {}
SC_POPUP_LOGGED_THIS_TURN = {}
SC_USER_INPUT_LOG_COUNT_THIS_TURN = 0
SC_RECENT_PLAYER_INPUT_EVENTS = 0
SC_AUDIT_COUNTER_TURN = -1
SC_DEMO_LOG_COUNT_THIS_TURN = 0
SC_DEMO_WORLD_SNAPSHOT_TURN = -1
SC_DEMO_WORLD_SNAPSHOT_REASON = ""
SC_POLICY_FAILED_THIS_TURN = {}
SC_POLICY_PENDING_THIS_TURN = false
SC_UNIT_AUDIT_LAST = {}
SC_UNIT_AUDIT_SEQ = 0
SC_LAST_AUDIT_MOUSE_HEX = "?"
SC_PROMOTION_SCAN_ATTEMPTED_THIS_TURN = {}
SC_PROMOTION_FAILED_THIS_TURN = {}
SC_PROMOTION_HANDLED_THIS_TURN = {}
SC_PROMOTION_DIRECT_GRANTED_THIS_TURN = {}
SC_PROMOTION_ACTION_LOGGED_THIS_TURN = {}
SC_GREAT_PERSON_ACTION_ATTEMPTED_THIS_TURN = {}
SC_GREAT_PERSON_POSITIONED_THIS_TURN = {}
SC_GREAT_PERSON_TARGET_RESERVED_THIS_TURN = {}
SC_GREAT_PERSON_MODAL_PENDING = {}
SC_MILITARY_PURCHASED_TURN = {}
SC_MILITARY_PURCHASE_FAILED_THIS_TURN = {}
SC_CAPITAL_DEPLOYMENT_TURN = {}
SC_AIR_SUPERIORITY_BUDGET_THIS_TURN = {}
SC_AIR_REBASED_THIS_TURN = {}
SC_AIR_REBASE_DESTINATION_COUNT_THIS_TURN = {}
SC_AIR_REBASE_NO_DEST_THIS_TURN = {}
SC_NOTIFICATION_QUEUE = {}
SC_NOTIFICATION_QUEUE_KEYS = {}
SC_NOTIFICATION_PROCESSING = false
local SC_UnitNeedsOrder = nil
local SC_GetUnitOrderDebug = nil
local SC_TryDirectTargetedMission = nil
SC_ProcessNotificationQueue = nil
SC_TryCloseDiplomacy = nil
SC_DIPLO_CLOSE_PENDING_TICKS = 0
SC_DIPLO_CLOSE_PLAYER = -1

pcall(function()
	SC_LOAD_TURN = Game.GetGameTurn()
end)

local function SC_Log(text)
	print("[Strategic Command] "..tostring(text))
end

local function SC_GetConfig(key, defaultValue)
	if SC_CONFIG ~= nil and SC_CONFIG[key] ~= nil then
		return SC_CONFIG[key]
	end
	return defaultValue
end

function SC_GetSafeNumber(callback, defaultValue)
	local ok, value = pcall(callback)
	if ok and value ~= nil then
		return value
	end
	return defaultValue or 0
end

function SC_DBNumber(value, defaultValue)
	if type(value) == "number" then
		return value
	end
	if type(value) == "boolean" then
		return value and 1 or 0
	end
	local parsed = tonumber(value)
	if parsed ~= nil then
		return parsed
	end
	return defaultValue or 0
end

function SC_DBFlag(value)
	if type(value) == "boolean" then
		return value
	end
	return SC_DBNumber(value, 0) ~= 0
end

function SC_Debug(text)
	if not SC_GetConfig("DebugLogging", false) then
		return
	end
	local turn = -1
	pcall(function()
		if Game ~= nil and Game.GetGameTurn ~= nil then
			turn = Game.GetGameTurn()
		end
	end)
	print("[Strategic Command][SCDBG][T"..tostring(turn).."] "..tostring(text))
end

function SC_BoolText(value)
	if value then
		return "true"
	end
	return "false"
end

function SC_GetUnitDebugLabel(unit)
	if unit == nil then
		return "nil-unit"
	end
	local unitType = "UNIT?"
	local unitID = "?"
	local ownerID = "?"
	pcall(function()
		local info = GameInfo.Units[unit:GetUnitType()]
		if info ~= nil and info.Type ~= nil then
			unitType = info.Type
		end
	end)
	pcall(function() unitID = tostring(unit:GetID()) end)
	pcall(function() ownerID = tostring(unit:GetOwner()) end)
	return unitType.."#"..unitID.."@P"..ownerID
end

function SC_GetUnitTurnKey(unit)
	if unit == nil then
		return nil
	end
	local ownerID = "?"
	local unitID = "?"
	pcall(function() ownerID = tostring(unit:GetOwner()) end)
	pcall(function() unitID = tostring(unit:GetID()) end)
	return ownerID..":"..unitID
end

function SC_GetPlotDebug(plot)
	if plot == nil then
		return "nil-plot"
	end
	local x = "?"
	local y = "?"
	pcall(function()
		x = tostring(plot:GetX())
		y = tostring(plot:GetY())
	end)
	return x..","..y
end

function SC_GetMouseAuditDebug()
	local parts = {}
	local plot = nil
	pcall(function()
		if UI ~= nil and UI.GetMouseOverHex ~= nil and Map ~= nil then
			plot = Map.GetPlot(UI.GetMouseOverHex())
		end
	end)
	if plot ~= nil then
		table.insert(parts, "mouseHex="..SC_GetPlotDebug(plot))
		local owner = -1
		pcall(function() owner = plot:GetOwner() end)
		if owner ~= nil and owner >= 0 then
			table.insert(parts, "hexOwner=P"..tostring(owner))
		end
	else
		table.insert(parts, "mouseHex=?")
	end
	local mouseX = nil
	local mouseY = nil
	pcall(function()
		if UIManager ~= nil and UIManager.GetMousePos ~= nil then
			mouseX, mouseY = UIManager:GetMousePos()
		end
	end)
	if mouseX ~= nil and mouseY ~= nil then
		table.insert(parts, "mousePos="..tostring(mouseX)..","..tostring(mouseY))
	end
	return table.concat(parts, " ")
end

function SC_GetSelectionAuditDebug()
	local parts = {}
	local unit = nil
	local city = nil
	pcall(function()
		if UI ~= nil and UI.GetHeadSelectedUnit ~= nil then
			unit = UI.GetHeadSelectedUnit()
		end
	end)
	pcall(function()
		if UI ~= nil and UI.GetHeadSelectedCity ~= nil then
			city = UI.GetHeadSelectedCity()
		end
	end)
	if unit ~= nil then
		local plot = nil
		pcall(function() plot = unit:GetPlot() end)
		table.insert(parts, "selectedUnit="..SC_GetUnitDebugLabel(unit).."@"..SC_GetPlotDebug(plot))
	end
	if city ~= nil then
		local cityName = "city?"
		pcall(function() cityName = city:GetName() end)
		table.insert(parts, "selectedCity="..tostring(cityName).."#"..tostring(city:GetID()).."@"..tostring(city:GetX())..","..tostring(city:GetY()))
	end
	local mode = nil
	pcall(function()
		if UI ~= nil and UI.GetInterfaceMode ~= nil then
			mode = UI.GetInterfaceMode()
		end
	end)
	if mode ~= nil then
		table.insert(parts, "mode="..SC_GetEnumDebugName(InterfaceModeTypes, mode))
	end
	local activePlayer = nil
	pcall(function()
		if Players ~= nil and Game ~= nil then
			activePlayer = Players[Game.GetActivePlayer()]
		end
	end)
	table.insert(parts, "blocker="..SC_GetBlockingDebug(activePlayer))
	table.insert(parts, "lastPopup="..tostring(SC_LAST_UNHANDLED_POPUP))
	return table.concat(parts, " ")
end

function SC_AuditUserInput(action, detail)
	local remaining = tonumber(SC_GetConfig("TakeoverTurnsRemaining", 0)) or 0
	local demoActive = SC_IsDemonstrationLoggingActive ~= nil and SC_IsDemonstrationLoggingActive()
	if not SC_GetConfig("AuditUserInput", true) or (remaining <= 0 and not demoActive) then
		return
	end
	if SC_ResetAuditCountersForTurn ~= nil then
		SC_ResetAuditCountersForTurn()
	end
	local limit = SC_GetConfig("AuditUserInputLimitPerTurn", 120)
	if demoActive then
		limit = SC_GetConfig("DemonstrationInputLimitPerTurn", 1200)
	end
	if SC_USER_INPUT_LOG_COUNT_THIS_TURN >= limit then
		return
	end
	SC_USER_INPUT_LOG_COUNT_THIS_TURN = SC_USER_INPUT_LOG_COUNT_THIS_TURN + 1
	SC_Debug("USERINPUT action="..tostring(action)..
		" detail="..tostring(detail or "")..
		" "..SC_GetMouseAuditDebug()..
		" "..SC_GetSelectionAuditDebug())
end

function SC_GetEnumDebugName(enumTable, value)
	if enumTable ~= nil and value ~= nil then
		local ok, name = pcall(function()
			for key, enumValue in pairs(enumTable) do
				if enumValue == value then
					return tostring(key).."("..tostring(value)..")"
				end
			end
			return nil
		end)
		if ok and name ~= nil then
			return name
		end
	end
	return tostring(value)
end

function SC_ResetAuditCountersForTurn()
	local turn = -1
	pcall(function()
		if Game ~= nil and Game.GetGameTurn ~= nil then
			turn = Game.GetGameTurn()
		end
	end)
	if SC_AUDIT_COUNTER_TURN ~= turn then
		SC_AUDIT_COUNTER_TURN = turn
		SC_USER_INPUT_LOG_COUNT_THIS_TURN = 0
		SC_DEMO_LOG_COUNT_THIS_TURN = 0
		SC_RECENT_PLAYER_INPUT_EVENTS = 0
	end
end

function SC_IsDemonstrationLoggingActive()
	return SC_GetConfig("DemonstrationLogging", true) == true
end

function SC_DemoLog(category, detail)
	if not SC_IsDemonstrationLoggingActive() then
		return false
	end
	SC_ResetAuditCountersForTurn()
	local maxLines = SC_GetConfig("DemonstrationMaxLinesPerTurn", 5000)
	if SC_DEMO_LOG_COUNT_THIS_TURN >= maxLines then
		if SC_DEMO_LOG_COUNT_THIS_TURN == maxLines then
			SC_DEMO_LOG_COUNT_THIS_TURN = SC_DEMO_LOG_COUNT_THIS_TURN + 1
			SC_Debug("DEMO category=cap reason=max-lines-per-turn max="..tostring(maxLines))
		end
		return false
	end
	SC_DEMO_LOG_COUNT_THIS_TURN = SC_DEMO_LOG_COUNT_THIS_TURN + 1
	SC_Debug("DEMO category="..tostring(category).." "..tostring(detail or ""))
	return true
end

local function SC_GetID(typeName)
	if typeName == nil then
		return nil
	end
	return GameInfoTypes[typeName]
end

local function SC_GetMissionID(typeName)
	if typeName == nil then
		return nil
	end
	if MissionTypes ~= nil and MissionTypes[typeName] ~= nil then
		return MissionTypes[typeName]
	end
	if GameInfoTypes ~= nil and GameInfoTypes[typeName] ~= nil then
		return GameInfoTypes[typeName]
	end
	return nil
end

local function SC_IsTargetlessUnitMission(missionType)
	if missionType == nil then
		return false
	end
	local names = {
		"MISSION_SKIP",
		"MISSION_SLEEP",
		"MISSION_ALERT",
		"MISSION_HEAL",
		"MISSION_AIRPATROL",
		"MISSION_INTERCEPT",
		"MISSION_WAKE"
	}
	for _, name in ipairs(names) do
		if SC_GetMissionID(name) == missionType then
			return true
		end
	end
	return false
end

local function SC_SendUnitMission(unit, missionType, data1, data2, flags)
	if unit == nil or missionType == nil or Game == nil or Game.SelectionListGameNetMessage == nil or GameMessageTypes == nil then
		SC_Debug("mission skip unit="..SC_GetUnitDebugLabel(unit).." mission="..tostring(missionType).." reason=missing-api")
		return false
	end
	local ownerID, unitID, unitLabel = SC_GetUnitIdentity(unit)
	local beforePlot = nil
	local beforeMoves = "?"
	local beforeActivity = "?"
	pcall(function() beforePlot = unit:GetPlot() end)
	pcall(function() beforeMoves = tostring(unit:MovesLeft()) end)
	pcall(function() beforeActivity = tostring(unit:GetActivityType()) end)
	local selected = pcall(function()
		UI.SelectUnit(unit)
	end)
	if not selected then
		SC_Debug("mission select-failed unit="..SC_GetUnitDebugLabel(unit).." mission="..tostring(missionType))
		return false
	end
	local sendData1 = data1
	local sendData2 = data2
	if sendData1 == nil and sendData2 == nil and SC_IsTargetlessUnitMission(missionType) then
		pcall(function() sendData1 = unit:GetID() end)
		sendData2 = 0
	end
	if sendData1 == nil then
		sendData1 = -1
	end
	if sendData2 == nil then
		sendData2 = -1
	end
	local ok, err = pcall(function()
		Game.SelectionListGameNetMessage(GameMessageTypes.GAMEMESSAGE_PUSH_MISSION, missionType, sendData1, sendData2, flags or 0, false, false)
	end)
	local liveUnit = SC_ResolveLiveUnit(ownerID, unitID)
	if liveUnit == nil then
		SC_Debug("mission unit-removed unit="..tostring(unitLabel)..
			" mission="..SC_GetEnumDebugName(MissionTypes, missionType)..
			" data="..tostring(data1)..","..tostring(data2)..
			" ok="..SC_BoolText(ok).." err="..tostring(err))
		return ok, "unit-removed", nil
	end
	if SC_GetConfig("DebugUnitCommands", true) then
		local afterPlot = nil
		local afterMoves = "?"
		local afterActivity = "?"
		pcall(function() afterPlot = liveUnit:GetPlot() end)
		pcall(function() afterMoves = tostring(liveUnit:MovesLeft()) end)
		pcall(function() afterActivity = tostring(liveUnit:GetActivityType()) end)
		SC_Debug("mission unit="..tostring(unitLabel)..
			" mission="..SC_GetEnumDebugName(MissionTypes, missionType)..
			" data="..tostring(data1)..","..tostring(data2)..
			" sentData="..tostring(sendData1)..","..tostring(sendData2)..
			" flags="..tostring(flags or 0)..
			" ok="..SC_BoolText(ok)..
			" err="..tostring(err)..
			" before="..SC_GetPlotDebug(beforePlot).."/m"..beforeMoves.."/a"..beforeActivity..
			" after="..SC_GetPlotDebug(afterPlot).."/m"..afterMoves.."/a"..afterActivity)
	end
	return ok, ok and "sent" or "send-failed", liveUnit
end

local function SC_SendUnitCommand(unit, commandType, data1, data2)
	if unit == nil or commandType == nil or Game == nil or Game.SelectionListGameNetMessage == nil or GameMessageTypes == nil then
		SC_Debug("command skip unit="..SC_GetUnitDebugLabel(unit).." command="..tostring(commandType).." reason=missing-api")
		return false
	end
	local ownerID, unitID, unitLabel = SC_GetUnitIdentity(unit)
	local beforePlot = nil
	local beforeMoves = "?"
	local beforeActivity = "?"
	pcall(function() beforePlot = unit:GetPlot() end)
	pcall(function() beforeMoves = tostring(unit:MovesLeft()) end)
	pcall(function() beforeActivity = tostring(unit:GetActivityType()) end)
	local selected = pcall(function()
		UI.SelectUnit(unit)
	end)
	if not selected then
		SC_Debug("command select-failed unit="..SC_GetUnitDebugLabel(unit).." command="..tostring(commandType))
		return false
	end
	local sendData1 = data1
	local sendData2 = data2
	if sendData1 == nil then
		sendData1 = -1
	end
	if sendData2 == nil then
		sendData2 = -1
	end
	local ok, err = pcall(function()
		Game.SelectionListGameNetMessage(GameMessageTypes.GAMEMESSAGE_DO_COMMAND, commandType, sendData1, sendData2, 0, false, false)
	end)
	local liveUnit = SC_ResolveLiveUnit(ownerID, unitID)
	if liveUnit == nil then
		SC_Debug("command unit-removed unit="..tostring(unitLabel)..
			" command="..SC_GetEnumDebugName(CommandTypes, commandType)..
			" data="..tostring(data1)..","..tostring(data2)..
			" ok="..SC_BoolText(ok).." err="..tostring(err))
		return ok, "unit-removed", nil
	end
	if SC_GetConfig("DebugUnitCommands", true) then
		local afterPlot = nil
		local afterMoves = "?"
		local afterActivity = "?"
		pcall(function() afterPlot = liveUnit:GetPlot() end)
		pcall(function() afterMoves = tostring(liveUnit:MovesLeft()) end)
		pcall(function() afterActivity = tostring(liveUnit:GetActivityType()) end)
		SC_Debug("command unit="..tostring(unitLabel)..
			" command="..SC_GetEnumDebugName(CommandTypes, commandType)..
			" data="..tostring(data1)..","..tostring(data2)..
			" sentData="..tostring(sendData1)..","..tostring(sendData2)..
			" ok="..SC_BoolText(ok)..
			" err="..tostring(err)..
			" before="..SC_GetPlotDebug(beforePlot).."/m"..beforeMoves.."/a"..beforeActivity..
			" after="..SC_GetPlotDebug(afterPlot).."/m"..afterMoves.."/a"..afterActivity)
	end
	return ok, ok and "sent" or "send-failed", liveUnit
end

function SC_GetUnitIdentity(unit)
	if unit == nil then
		return -1, -1, "nil-unit"
	end
	local ownerID = SC_GetSafeNumber(function() return unit:GetOwner() end, -1)
	local unitID = SC_GetSafeNumber(function() return unit:GetID() end, -1)
	return ownerID, unitID, SC_GetUnitDebugLabel(unit)
end

function SC_ResolveLiveUnit(ownerID, unitID)
	if Players == nil or ownerID == nil or unitID == nil or ownerID < 0 or unitID < 0 then
		return nil
	end
	local owner = Players[ownerID]
	if owner == nil then
		return nil
	end
	local liveUnit = nil
	pcall(function() liveUnit = owner:GetUnitByID(unitID) end)
	if liveUnit == nil then
		return nil
	end
	local dead = true
	local ok = pcall(function() dead = liveUnit:IsDead() end)
	return ok and not dead and liveUnit or nil
end

local function SC_TryMoveMission(unit, plot, reason, requirePlotChange)
	if unit == nil or plot == nil then
		return false, "missing", nil
	end
	if SC5 and SC5.IsWithdrawing(unit) and reason ~= "survival-withdraw" then
		return false, "withdrawal-reserved", unit
	end
	local ownerID, unitID, unitLabel = SC_GetUnitIdentity(unit)
	local owner = Players ~= nil and Players[ownerID] or nil
	if owner ~= nil and SC_PlotWouldRequireNewWar ~= nil and SC_PlotWouldRequireNewWar(owner, plot) then
		SC_Debug("moveMission diplomacy-block unit="..tostring(unitLabel)..
			" reason="..tostring(reason)..
			" target="..SC_GetPlotDebug(plot))
		return false, "diplomacy-block", unit
	end
	local mission = SC_GetMissionID("MISSION_MOVE_TO")
	if mission == nil then
		return false, "missing-mission", unit
	end
	if SC5 ~= nil and owner ~= nil then
		local allowed, why = SC5.MeleeGate(owner, unit, plot)
		if not allowed then
			SC_Debug("moveMission combat-gate unit="..unitLabel.." reason="..tostring(why).." target="..SC_GetPlotDebug(plot))
			return false, "combat-gate:"..tostring(why), unit
		end
	end
	local beforePlot = nil
	local beforeIndex = nil
	local beforeMoves = SC_GetSafeNumber(function() return unit:MovesLeft() end, -1)
	local beforeTargetOwner = SC_GetSafeNumber(function() return plot:GetOwner() end, -1)
	local beforeTargetUnits = SC_GetSafeNumber(function() return plot:GetNumUnits() end, 0)
	pcall(function() beforePlot = unit:GetPlot() end)
	pcall(function()
		if beforePlot ~= nil then
			beforeIndex = beforePlot:GetPlotIndex()
		end
	end)
	local ok = SC_SendUnitMission(unit, mission, plot:GetX(), plot:GetY())
	if not ok then
		return false, "send-failed", SC_ResolveLiveUnit(ownerID, unitID)
	end
	local liveUnit = SC_ResolveLiveUnit(ownerID, unitID)
	if liveUnit == nil then
		SC_Debug("moveMission unit-removed unit="..tostring(unitLabel)..
			" reason="..tostring(reason).." phase=network target="..SC_GetPlotDebug(plot))
		return false, "unit-removed", nil
	end
	local afterPlot = nil
	local afterIndex = nil
	local afterMoves = SC_GetSafeNumber(function() return liveUnit:MovesLeft() end, -1)
	local afterTargetOwner = SC_GetSafeNumber(function() return plot:GetOwner() end, -1)
	local afterTargetUnits = SC_GetSafeNumber(function() return plot:GetNumUnits() end, 0)
	pcall(function() afterPlot = liveUnit:GetPlot() end)
	pcall(function()
		if afterPlot ~= nil then
			afterIndex = afterPlot:GetPlotIndex()
		end
	end)
	local needsOrder = false
	if SC_UnitNeedsOrder ~= nil then
		needsOrder = SC_UnitNeedsOrder(liveUnit)
	end
	local changedPlot = beforeIndex ~= nil and afterIndex ~= nil and beforeIndex ~= afterIndex
	local combatResolved = (beforeTargetUnits > 0 and afterMoves >= 0 and beforeMoves >= 0 and afterMoves < beforeMoves)
		or (afterTargetUnits < beforeTargetUnits)
		or (beforeTargetOwner ~= afterTargetOwner)
	local accepted = changedPlot or combatResolved or (not requirePlotChange and not needsOrder)
	if SC_GetConfig("DebugUnitCommands", true) then
		SC_Debug("moveMission unit="..tostring(unitLabel)..
			" reason="..tostring(reason)..
			" target="..SC_GetPlotDebug(plot)..
			" accepted="..SC_BoolText(accepted)..
			" changedPlot="..SC_BoolText(changedPlot)..
			" combatResolved="..SC_BoolText(combatResolved)..
			" targetState="..tostring(beforeTargetOwner).."/"..tostring(beforeTargetUnits).."->"..tostring(afterTargetOwner).."/"..tostring(afterTargetUnits)..
			" requirePlotChange="..SC_BoolText(requirePlotChange == true)..
			" state="..SC_GetUnitOrderDebug(liveUnit))
	end
	if not accepted and SC_GetConfig("DirectPushMoveMissionFallback", true) then
		local directOk, directErr = pcall(function()
			liveUnit:PushMission(mission, plot:GetX(), plot:GetY(), 0, 0, 1, -1)
		end)
		liveUnit = SC_ResolveLiveUnit(ownerID, unitID)
		if liveUnit == nil then
			SC_Debug("moveMission unit-removed unit="..tostring(unitLabel)..
				" reason="..tostring(reason).." phase=direct target="..SC_GetPlotDebug(plot)..
				" ok="..SC_BoolText(directOk).." err="..tostring(directErr))
			return false, "unit-removed", nil
		end
		local directAfterPlot = nil
		local directAfterIndex = nil
		local directAfterMoves = SC_GetSafeNumber(function() return liveUnit:MovesLeft() end, -1)
		local directAfterTargetOwner = SC_GetSafeNumber(function() return plot:GetOwner() end, -1)
		local directAfterTargetUnits = SC_GetSafeNumber(function() return plot:GetNumUnits() end, 0)
		pcall(function() directAfterPlot = liveUnit:GetPlot() end)
		pcall(function()
			if directAfterPlot ~= nil then
				directAfterIndex = directAfterPlot:GetPlotIndex()
			end
		end)
		local directNeedsOrder = false
		if SC_UnitNeedsOrder ~= nil then
			directNeedsOrder = SC_UnitNeedsOrder(liveUnit)
		end
		local directChangedPlot = beforeIndex ~= nil and directAfterIndex ~= nil and beforeIndex ~= directAfterIndex
		local directCombatResolved = (beforeTargetUnits > 0 and directAfterMoves >= 0 and beforeMoves >= 0 and directAfterMoves < beforeMoves)
			or directAfterTargetUnits < beforeTargetUnits
			or directAfterTargetOwner ~= beforeTargetOwner
		local directAccepted = directOk and (directChangedPlot or directCombatResolved or (not requirePlotChange and not directNeedsOrder))
		if SC_GetConfig("DebugUnitCommands", true) then
			SC_Debug("moveMission direct-fallback unit="..tostring(unitLabel)..
				" reason="..tostring(reason)..
				" target="..SC_GetPlotDebug(plot)..
				" ok="..SC_BoolText(directOk)..
				" err="..tostring(directErr)..
				" accepted="..SC_BoolText(directAccepted)..
				" changedPlot="..SC_BoolText(directChangedPlot)..
				" combatResolved="..SC_BoolText(directCombatResolved)..
				" requirePlotChange="..SC_BoolText(requirePlotChange == true)..
				" state="..SC_GetUnitOrderDebug(liveUnit))
		end
		if directAccepted then
			return true, "direct", liveUnit
		end
	end
	return accepted, accepted and "network" or "not-accepted", liveUnit
end

local function SC_IsHumanActivePlayer(playerID)
	if playerID == nil or playerID ~= Game.GetActivePlayer() then
		return false
	end
	local player = Players[playerID]
	return player ~= nil and player:IsHuman() and player:IsAlive()
end

local function SC_PlayerAtWar(player)
	if player == nil then
		return false
	end
	local team = Teams[player:GetTeam()]
	if team == nil then
		return false
	end
	for otherID, otherPlayer in pairs(Players) do
		if otherPlayer ~= nil and otherPlayer:IsAlive() and otherPlayer:GetID() ~= player:GetID() then
			if team:IsAtWar(otherPlayer:GetTeam()) then
				return true
			end
		end
	end
	return false
end

local function SC_GetWarSummary(player)
	local enemies = {}
	if player == nil then
		return enemies
	end
	local team = Teams[player:GetTeam()]
	if team == nil then
		return enemies
	end
	for otherID, otherPlayer in pairs(Players) do
		if otherPlayer ~= nil and otherPlayer:IsAlive() and otherPlayer:GetID() ~= player:GetID() then
			if team:IsAtWar(otherPlayer:GetTeam()) then
				table.insert(enemies, otherPlayer:GetName())
			end
		end
	end
	return enemies
end

function SC_IsEnemyTargetPlayer(player, ownerID)
	if player == nil or ownerID == nil or ownerID < 0 or ownerID == player:GetID() then
		return false
	end
	local owner = Players[ownerID]
	local team = Teams[player:GetTeam()]
	return owner ~= nil and owner:IsAlive() and team ~= nil and team:IsAtWar(owner:GetTeam())
end

function SC_IsEnemyTargetUnitValid(player, unit)
	if player == nil or unit == nil then
		return false
	end
	local dead = true
	local ownerID = -1
	local ok = pcall(function()
		dead = unit:IsDead()
		ownerID = unit:GetOwner()
	end)
	return ok and not dead and SC_IsEnemyTargetPlayer(player, ownerID) and (SC5 == nil or SC5.ObservedUnit(player, unit))
end

function SC_IsEnemyTargetCityValid(player, city)
	if player == nil or city == nil then
		return false
	end
	local ownerID = -1
	local ok = pcall(function() ownerID = city:GetOwner() end)
	return ok and SC_IsEnemyTargetPlayer(player, ownerID) and (SC5 == nil or SC5.ObservedCity(player, city))
end

function SC_GetEnemyTargetPool(player)
	if player == nil then
		return { units = {}, cities = {} }
	end
	local playerID = player:GetID()
	local cached = SC_ENEMY_TARGET_POOL_THIS_TURN[playerID]
	if cached ~= nil then
		return cached
	end
	local pool = { units = {}, cities = {} }
	local team = Teams[player:GetTeam()]
	if team ~= nil then
		for _, otherPlayer in pairs(Players) do
			if otherPlayer ~= nil and otherPlayer:IsAlive() and otherPlayer:GetID() ~= playerID
				and team:IsAtWar(otherPlayer:GetTeam()) then
				for city in otherPlayer:Cities() do
					if SC5 == nil or SC5.ObservedCity(player, city) then table.insert(pool.cities, city) end
				end
				for enemyUnit in otherPlayer:Units() do
					if SC5 == nil or SC5.ObservedUnit(player, enemyUnit) then table.insert(pool.units, enemyUnit) end
				end
			end
		end
	end
	SC_ENEMY_TARGET_POOL_THIS_TURN[playerID] = pool
	SC_Debug("targetPool build player=P"..tostring(playerID)..
		" cities="..tostring(#pool.cities).." units="..tostring(#pool.units))
	return pool
end

function SC_GetEnumName(enumTable, value)
	return SC_GetEnumDebugName(enumTable, value)
end

function SC_GetBlockingDebug(player)
	if player == nil then
		return "nil-player"
	end
	local blocking = SC_GetSafeNumber(function() return player:GetEndTurnBlockingType() end, -999)
	return SC_GetEnumName(EndTurnBlockingTypes, blocking)
end

local function SC_GetSaveData()
	if SC_SAVE_DATA ~= nil then
		return SC_SAVE_DATA
	end
	if Modding ~= nil and Modding.OpenSaveData ~= nil then
		pcall(function()
			SC_SAVE_DATA = Modding.OpenSaveData()
		end)
	end
	return SC_SAVE_DATA
end

local function SC_UpdateSharedState()
	pcall(function()
		if MapModData == nil then
			return
		end
		MapModData.StrategicCommand = MapModData.StrategicCommand or {}
		MapModData.StrategicCommand.TakeoverTurnsRemaining = SC_GetSafeNumber(function() return SC_CONFIG.TakeoverTurnsRemaining end, 0)
		MapModData.StrategicCommand.AutoPopupHandling = SC_GetConfig("AutoPopupHandling", true)
		MapModData.StrategicCommand.Version = SC_VERSION
	end)
end

local function SC_SaveTakeoverState()
	SC_UpdateSharedState()
	local saveData = SC_GetSaveData()
	if saveData == nil then
		SC_Debug("state save skipped reason=no-save-data")
		return
	end
	local remaining = SC_GetSafeNumber(function() return SC_CONFIG.TakeoverTurnsRemaining end, 0)
	local ok = pcall(function()
		saveData.SetValue(SC_TAKEOVER_SAVE_KEY, remaining)
	end)
	if not ok then
		pcall(function()
			saveData:SetValue(SC_TAKEOVER_SAVE_KEY, remaining)
		end)
	end
	local capturedCityAction = tostring(SC_GetConfig("CapturedCityAction", "PUPPET"))
	ok = pcall(function()
		saveData.SetValue(SC_CAPTURED_CITY_SAVE_KEY, capturedCityAction)
	end)
	if not ok then
		pcall(function()
			saveData:SetValue(SC_CAPTURED_CITY_SAVE_KEY, capturedCityAction)
		end)
	end
end

function SC_ReadSaveValue(saveData, key)
	if saveData == nil or key == nil then
		return nil
	end
	local ok, value = pcall(function()
		return saveData.GetValue(key)
	end)
	if ok then
		return value
	end
	ok, value = pcall(function()
		return saveData:GetValue(key)
	end)
	if ok then
		return value
	end
	return nil
end

function SC_LoadTakeoverState()
	local saveData = SC_GetSaveData()
	if saveData == nil then
		SC_Debug("state load skipped reason=no-save-data")
		return
	end
	local remaining = tonumber(SC_ReadSaveValue(saveData, SC_TAKEOVER_SAVE_KEY))
	if remaining ~= nil then
		SC_CONFIG.TakeoverTurnsRemaining = math.max(remaining, 0)
	end
	local capturedCityAction = SC_ReadSaveValue(saveData, SC_CAPTURED_CITY_SAVE_KEY)
	if capturedCityAction ~= nil and capturedCityAction ~= "" then
		SC_CONFIG.CapturedCityAction = tostring(capturedCityAction)
	end
	SC_UpdateSharedState()
	SC_Debug("state load remaining="..tostring(SC_GetConfig("TakeoverTurnsRemaining", 0))..
		" capturedCityAction="..tostring(SC_GetConfig("CapturedCityAction", "PUPPET")))
end

local function SC_CityCanConstruct(city, buildingID)
	if city == nil or buildingID == nil or buildingID < 0 then
		return false
	end
	local ok, result = pcall(function()
		return city:CanConstruct(buildingID)
	end)
	return ok and result
end

local function SC_CityCanTrain(city, unitID)
	if city == nil or unitID == nil or unitID < 0 then
		return false
	end
	local ok, result = pcall(function()
		return city:CanTrain(unitID)
	end)
	if ok then
		return result
	end
	ok, result = pcall(function()
		return city:CanTrain(unitID, 0, 1)
	end)
	return ok and result
end

local function SC_CityCanMaintain(city, processID)
	if city == nil or processID == nil or processID < 0 then
		return false
	end
	local ok, result = pcall(function()
		return city:CanMaintain(processID)
	end)
	return ok and result
end

local function SC_CityCanCreate(city, projectID)
	if city == nil or projectID == nil or projectID < 0 then
		return false
	end
	local ok, result = pcall(function()
		return city:CanCreate(projectID)
	end)
	if ok then
		return result
	end
	ok, result = pcall(function()
		return city:CanCreate(projectID, 0, 1)
	end)
	return ok and result
end

local function SC_PushCityOrder(city, orderType, itemID)
	if city == nil or orderType == nil or itemID == nil then
		return false
	end
	local ok = false
	if Game ~= nil and Game.CityPushOrder ~= nil then
		ok = pcall(function()
			Game.CityPushOrder(city, orderType, itemID, false, false, true)
		end)
		if ok then
			return true
		end
	end
	ok = pcall(function()
		city:PushOrder(orderType, itemID, -1, 0, false, false)
	end)
	return ok
end

local function SC_BuildFirstAvailable(city, buildingTypes)
	for _, buildingType in ipairs(buildingTypes) do
		local buildingID = SC_GetID(buildingType)
		if SC_CityCanConstruct(city, buildingID) then
			if SC_PushCityOrder(city, OrderTypes.ORDER_CONSTRUCT, buildingID) then
				return buildingType
			end
		end
	end
	return nil
end

local function SC_GetBuildingPlan(player, city, atWar)
	local doctrine = SC_GetConfig("Doctrine", "BALANCED")
	local happiness = SC_GetSafeNumber(function() return player:GetExcessHappiness() end, 10)

	local happinessBuildings = {
		"BUILDING_COLOSSEUM", "BUILDING_THEATRE", "BUILDING_ZOO", "BUILDING_STADIUM",
		"BUILDING_CIRCUS", "BUILDING_COURTHOUSE"
	}
	local defenseBuildings = {
		"BUILDING_WALLS", "BUILDING_CASTLE", "BUILDING_ARSENAL", "BUILDING_MILITARY_BASE"
	}
	local scienceBuildings = {
		"BUILDING_LIBRARY", "BUILDING_UNIVERSITY", "BUILDING_PUBLIC_SCHOOL",
		"BUILDING_LABORATORY", "BUILDING_RESEARCH_LAB"
	}
	local productionBuildings = {
		"BUILDING_GRANARY", "BUILDING_WATERMILL", "BUILDING_AQUEDUCT",
		"BUILDING_WORKSHOP", "BUILDING_WINDMILL", "BUILDING_FACTORY",
		"BUILDING_GRAIN_DEPOT", "BUILDING_MECHANIZED_FARM",
		"BUILDING_HYDRO_PLANT", "BUILDING_SOLAR_PLANT", "BUILDING_NUCLEAR_PLANT"
	}
	local goldBuildings = {
		"BUILDING_MARKET", "BUILDING_BANK", "BUILDING_STOCK_EXCHANGE"
	}
	local militaryBuildings = {
		"BUILDING_BARRACKS", "BUILDING_ARMORY", "BUILDING_MILITARY_ACADEMY", "BUILDING_AIRPORT"
	}
	
	if happiness < 5 then
		return happinessBuildings
	end

	if atWar and doctrine ~= "SCIENCE" then
		return defenseBuildings
	end

	if doctrine == "SCIENCE" then
		return scienceBuildings
	elseif doctrine == "INDUSTRY" then
		return productionBuildings
	elseif doctrine == "WAR" then
		return militaryBuildings
	end
	
	local population = SC_GetSafeNumber(function() return city:GetPopulation() end, 1)
	if population >= 12 then
		return scienceBuildings
	end
	if SC_GetSafeNumber(function() return player:CalculateGoldRate() end, 0) < 0 then
		return goldBuildings
	end
	return productionBuildings
end

local function SC_TextHas(text, pattern)
	return text ~= nil and pattern ~= nil and string.find(text, pattern) ~= nil
end

local function SC_GetUnitInfo(unit)
	if unit == nil then
		return nil
	end
	local unitType = nil
	pcall(function() unitType = unit:GetUnitType() end)
	if unitType == nil then
		return nil
	end
	return GameInfo.Units[unitType]
end

local function SC_UnitHasPromotion(unit, promotionType)
	if unit == nil or promotionType == nil then
		return false
	end
	local promotionID = nil
	if GameInfoTypes ~= nil then
		promotionID = GameInfoTypes[promotionType]
	end
	if promotionID == nil and GameInfo ~= nil and GameInfo.UnitPromotions ~= nil and GameInfo.UnitPromotions[promotionType] ~= nil then
		promotionID = GameInfo.UnitPromotions[promotionType].ID
	end
	if promotionID == nil then
		return false
	end
	local ok, hasPromotion = pcall(function() return unit:IsHasPromotion(promotionID) end)
	return ok and hasPromotion
end

local function SC_GetUnitRole(unit, unitInfo)
	unitInfo = unitInfo or SC_GetUnitInfo(unit)
	if unitInfo == nil then
		return "unknown"
	end
	local unitType = unitInfo.Type or ""
	local domain = unitInfo.Domain or ""
	local combatClass = unitInfo.CombatClass or ""
	local ai = unitInfo.DefaultUnitAI or ""
	local ranged = unitInfo.RangedCombat or 0
	local range = unitInfo.Range or 0
	local specialCargo = unitInfo.SpecialCargo or ""
	local domainCargo = unitInfo.DomainCargo or ""
	local special = unitInfo.Special or ""
	local isCarrier = combatClass == "UNITCOMBAT_CARRIER"
		or ai == "UNITAI_CARRIER_SEA"
		or (specialCargo == "SPECIALUNIT_FIGHTER" and domainCargo == "DOMAIN_AIR")
		or SC_TextHas(unitType, "CARRIER")
		or SC_UnitHasPromotion(unit, "PROMOTION_CARRIER_UNIT")
	local isMissileCarrier = specialCargo == "SPECIALUNIT_MISSILE"
		or SC_TextHas(unitType, "MISSILE_CRUISER")
		or SC_TextHas(unitType, "KIROV")
		or SC_TextHas(unitType, "052D")
		or SC_TextHas(unitType, "ARSENAL")
		or SC_UnitHasPromotion(unit, "PROMOTION_MISSILE_CARRIER")
	local isSubmarine = combatClass == "UNITCOMBAT_SUBMARINE"
		or SC_TextHas(unitType, "SUBMARINE")
		or SC_UnitHasPromotion(unit, "PROMOTION_SUBMARINE_COMBAT")
	if domain == "DOMAIN_AIR" then
		if (unitInfo.NukeDamageLevel or 0) > 0 or special == "SPECIALUNIT_NUKE" or ai == "UNITAI_ICBM" then
			return "nuke"
		end
		if special == "SPECIALUNIT_MISSILE" or ai == "UNITAI_MISSILE_AIR" or ai == "UNITAI_MISSILE_CARRIER_SEA" or SC_TextHas(unitType, "GUIDED_MISSILE") or SC_TextHas(unitType, "MISSILE") then
			return "missile"
		end
		if SC_UnitHasPromotion(unit, "PROMOTION_CARRIER_FIGHTER") or SC_TextHas(unitType, "CARRIER_FIGHTER") or SC_TextHas(unitType, "HARRIER") then
			return "carrier_air"
		end
		if ai == "UNITAI_DEFENSE_AIR" or combatClass == "UNITCOMBAT_FIGHTER" then
			return "fighter"
		end
		return "bomber"
	end
	if isCarrier then
		return "carrier"
	end
	if isSubmarine then
		return "submarine"
	end
	if domain == "DOMAIN_SEA" then
		if isMissileCarrier then
			return "missile_carrier"
		end
		if combatClass == "UNITCOMBAT_NAVALRANGED" or (ranged > 0 and range > 1) then
			return "naval_ranged"
		end
		return "naval_melee"
	end
	if combatClass == "UNITCOMBAT_SIEGE" or ai == "UNITAI_CITY_BOMBARD" then
		return "siege"
	end
	if combatClass == "UNITCOMBAT_ARMOR" or combatClass == "UNITCOMBAT_HELICOPTER" or ai == "UNITAI_FAST_ATTACK" or SC_TextHas(unitType, "ARMOR") or SC_TextHas(unitType, "TANK") then
		return "fast_assault"
	end
	if ranged > 0 and (range > 1 or ai == "UNITAI_RANGED") then
		return "land_ranged"
	end
	return "assault"
end

function SC_GetUnitIntrinsicPromotionSummary(unitInfo)
	if unitInfo == nil then
		return {}
	end
	local unitType = unitInfo.Type or "UNKNOWN"
	local cached = SC_UNIT_CAPABILITY_CACHE[unitType]
	if cached ~= nil and cached.promotionSummary ~= nil then
		return cached.promotionSummary
	end
	local summary = {
		moveAfterAttack = false,
		extraAttacks = 0,
		mustSetUp = false,
		dropRange = 0,
		rangeChange = 0,
		intercept = 0,
		airSweep = false,
		indirectFire = SC_DBFlag(unitInfo.RangeAttackIgnoreLOS),
		noCapture = false,
		onlyDefensive = false,
		cityAttackOnly = false,
		ignoreZOC = false,
		ignoreTerrain = false,
		alwaysHeal = false,
		healOnKill = 0,
		cityAttack = 0,
		attack = 0,
		defense = 0,
		cargo = 0,
		carrierAir = false,
		carrier = false,
		missileCarrier = false,
		submarine = false
	}
	pcall(function()
		for freePromotion in GameInfo.Unit_FreePromotions{ UnitType = unitType } do
			local promotion = GameInfo.UnitPromotions[freePromotion.PromotionType]
			if promotion ~= nil then
				local promotionType = promotion.Type or freePromotion.PromotionType or ""
				summary.moveAfterAttack = summary.moveAfterAttack
					or SC_DBFlag(promotion.CanMoveAfterAttacking)
					or SC_DBFlag(promotion.Blitz)
					or SC_DBNumber(promotion.ExtraAttacks, 0) > 0
				summary.extraAttacks = summary.extraAttacks + math.max(SC_DBNumber(promotion.ExtraAttacks, 0), 0)
				summary.mustSetUp = summary.mustSetUp or SC_DBFlag(promotion.MustSetUpToRangedAttack)
				summary.dropRange = math.max(summary.dropRange, SC_DBNumber(promotion.DropRange, 0))
				summary.rangeChange = summary.rangeChange + SC_DBNumber(promotion.RangeChange, 0)
				summary.intercept = summary.intercept
					+ math.max(SC_DBNumber(promotion.InterceptChanceChange, 0), 0)
					+ math.max(SC_DBNumber(promotion.NumInterceptionChange, 0), 0) * 100
				summary.airSweep = summary.airSweep or SC_DBFlag(promotion.AirSweepCapable)
				summary.indirectFire = summary.indirectFire or SC_DBFlag(promotion.RangeAttackIgnoreLOS)
				summary.noCapture = summary.noCapture or SC_DBFlag(promotion.NoCapture)
				summary.onlyDefensive = summary.onlyDefensive or SC_DBFlag(promotion.OnlyDefensive)
				summary.cityAttackOnly = summary.cityAttackOnly or SC_DBFlag(promotion.CityAttackOnly)
				summary.ignoreZOC = summary.ignoreZOC or SC_DBFlag(promotion.IgnoreZOC)
				summary.ignoreTerrain = summary.ignoreTerrain
					or SC_DBFlag(promotion.IgnoreTerrainCost)
					or SC_DBFlag(promotion.FlatMovementCost)
				summary.alwaysHeal = summary.alwaysHeal or SC_DBFlag(promotion.AlwaysHeal)
				summary.healOnKill = summary.healOnKill + math.max(SC_DBNumber(promotion.HPHealedIfDestroyEnemy, 0), 0)
				summary.cityAttack = summary.cityAttack + SC_DBNumber(promotion.CityAttack, 0)
				summary.attack = summary.attack + SC_DBNumber(promotion.AttackMod, 0)
				summary.defense = summary.defense + SC_DBNumber(promotion.DefenseMod, 0)
				summary.cargo = summary.cargo + math.max(SC_DBNumber(promotion.CargoChange, 0), 0)
				summary.carrierAir = summary.carrierAir or SC_TextHas(promotionType, "CARRIER_FIGHTER")
				summary.carrier = summary.carrier or SC_TextHas(promotionType, "CARRIER_UNIT")
				summary.missileCarrier = summary.missileCarrier or SC_TextHas(promotionType, "MISSILE_CARRIER")
				summary.submarine = summary.submarine or SC_TextHas(promotionType, "SUBMARINE_COMBAT")
			end
		end
	end)
	SC_UNIT_CAPABILITY_CACHE[unitType] = SC_UNIT_CAPABILITY_CACHE[unitType] or {}
	SC_UNIT_CAPABILITY_CACHE[unitType].promotionSummary = summary
	return summary
end

function SC_GetUnitCapabilityProfile(unit, unitInfo, role)
	unitInfo = unitInfo or SC_GetUnitInfo(unit)
	if unitInfo == nil then
		return { doctrineClass = "unknown", phase = 99, canCapture = false, power = 0 }
	end
	local unitType = unitInfo.Type or "UNKNOWN"
	local cached = SC_UNIT_CAPABILITY_CACHE[unitType]
	if cached ~= nil and cached.profile ~= nil then
		return SC5 and SC5.LiveProfile(unit, cached.profile) or cached.profile
	end
	role = role or SC_GetUnitRole(unit, unitInfo)
	local promotions = SC_GetUnitIntrinsicPromotionSummary(unitInfo)
	local domain = unitInfo.Domain or ""
	local combatClass = unitInfo.CombatClass or ""
	local ai = unitInfo.DefaultUnitAI or ""
	local combat = math.max(SC_DBNumber(unitInfo.Combat, 0), 0)
	local ranged = math.max(SC_DBNumber(unitInfo.RangedCombat, 0), 0)
	local range = math.max(SC_DBNumber(unitInfo.Range, 0) + SC_DBNumber(promotions.rangeChange, 0), 0)
	local moves = math.max(SC_DBNumber(unitInfo.Moves, 0), 0)
	local special = unitInfo.Special or ""
	local specialCargo = unitInfo.SpecialCargo or ""
	local domainCargo = unitInfo.DomainCargo or ""
	local civilianAI = ai == "UNITAI_WORKER"
		or ai == "UNITAI_ARCHAEOLOGIST"
		or ai == "UNITAI_SETTLE"
		or ai == "UNITAI_TRADE_UNIT"
		or ai == "UNITAI_ARTIST"
		or ai == "UNITAI_WRITER"
		or ai == "UNITAI_MUSICIAN"
		or ai == "UNITAI_SCIENTIST"
		or ai == "UNITAI_MERCHANT"
		or ai == "UNITAI_ENGINEER"
		or ai == "UNITAI_GENERAL"
		or ai == "UNITAI_ADMIRAL"
		or ai == "UNITAI_MISSIONARY"
		or ai == "UNITAI_PROPHET"
		or ai == "UNITAI_INQUISITOR"
		or SC_TextHas(ai, "SPACESHIP")
	local doctrineClass = "line_assault"
	local phase = 4
	if civilianAI or (combat <= 0 and ranged <= 0 and combatClass == "" and domain ~= "DOMAIN_AIR" and domain ~= "DOMAIN_SEA") then
		if ai == "UNITAI_WORKER" or ai == "UNITAI_ARCHAEOLOGIST" then
			doctrineClass = "civilian_builder"
		elseif ai == "UNITAI_SETTLE" then
			doctrineClass = "civilian_settler"
		elseif ai == "UNITAI_TRADE_UNIT" then
			doctrineClass = "civilian_trade"
		elseif SC_TextHas(ai, "MISSIONARY") or SC_TextHas(ai, "PROPHET") or SC_TextHas(ai, "INQUISITOR") then
			doctrineClass = "civilian_religious"
		elseif SC_TextHas(ai, "SPACESHIP") then
			doctrineClass = "civilian_spaceship"
		else
			doctrineClass = "civilian_specialist"
		end
		phase = 90
	elseif domain == "DOMAIN_AIR" then
		if (unitInfo.NukeDamageLevel or 0) > 0 or special == "SPECIALUNIT_NUKE" or ai == "UNITAI_ICBM" then
			doctrineClass = "strategic_nuclear"
			phase = 2
		elseif SC_DBFlag(unitInfo.Suicide) or special == "SPECIALUNIT_MISSILE" or ai == "UNITAI_MISSILE_AIR" then
			doctrineClass = "missile_strike"
			phase = 2
		elseif combatClass == "UNITCOMBAT_FIGHTER" or ai == "UNITAI_DEFENSE_AIR" then
			if promotions.carrierAir or SC_TextHas(unitType, "CARRIER_FIGHTER") or SC_TextHas(unitType, "HARRIER") then
				doctrineClass = "carrier_multirole"
			else
				doctrineClass = "air_superiority"
			end
			phase = 1
		else
			doctrineClass = "strike_aircraft"
			phase = 2
		end
	elseif domain == "DOMAIN_SEA" then
		local isCarrier = combatClass == "UNITCOMBAT_CARRIER"
			or ai == "UNITAI_CARRIER_SEA"
			or promotions.carrier
			or (specialCargo == "SPECIALUNIT_FIGHTER" and domainCargo == "DOMAIN_AIR")
		local isSubmarine = combatClass == "UNITCOMBAT_SUBMARINE" or promotions.submarine
		if isCarrier then
			doctrineClass = "fleet_carrier"
			phase = 5
		elseif isSubmarine and (specialCargo == "SPECIALUNIT_NUKE" or SC_TextHas(unitType, "SSBN")) then
			doctrineClass = "ballistic_submarine"
			phase = 5
		elseif isSubmarine then
			doctrineClass = "attack_submarine"
			phase = 2
		elseif ranged >= 300 and range >= 6 then
			doctrineClass = "arsenal_capital"
			phase = 3
		elseif promotions.intercept > 0 or specialCargo == "SPECIALUNIT_MISSILE" or promotions.missileCarrier or role == "missile_carrier" then
			doctrineClass = "air_defense_screen"
			phase = 1
		elseif combatClass == "UNITCOMBAT_NAVALRANGED" or (ranged > 0 and range > 1) then
			doctrineClass = "surface_fire_support"
			phase = 3
		elseif ai == "UNITAI_ESCORT_SEA" or combatClass == "UNITCOMBAT_RECON" then
			doctrineClass = "escort_screen"
			phase = 1
		else
			doctrineClass = "naval_assault"
			phase = 4
		end
	elseif domain == "DOMAIN_HOVER" then
		doctrineClass = "static_fortress"
		phase = 3
	elseif unitType == "UNIT_MECH" then
		doctrineClass = "super_heavy"
		phase = 3
	elseif promotions.intercept > 0 then
		doctrineClass = "mobile_air_defense"
		phase = 1
	elseif combatClass == "UNITCOMBAT_HELICOPTER" then
		doctrineClass = "gunship"
		phase = 2
	elseif combatClass == "UNITCOMBAT_SIEGE" or ai == "UNITAI_CITY_BOMBARD"
		or (ranged > 0 and range >= 3) then
		doctrineClass = "siege_artillery"
		phase = 3
	elseif ai == "UNITAI_PARADROP" or (promotions.dropRange or 0) > 0 then
		doctrineClass = "airborne_raider"
		phase = 1
	elseif combatClass == "UNITCOMBAT_RECON" or ai == "UNITAI_EXPLORE" then
		doctrineClass = "recon_raider"
		phase = 1
	elseif ai == "UNITAI_COUNTER" then
		doctrineClass = "counter_defender"
		phase = 4
	elseif combatClass == "UNITCOMBAT_ARMOR" or combatClass == "UNITCOMBAT_MOUNTED" or ai == "UNITAI_FAST_ATTACK" or role == "fast_assault" or (moves >= 5 and combat > 0) then
		doctrineClass = "mobile_breakthrough"
		phase = 4
	elseif ai == "UNITAI_DEFENSE" or promotions.onlyDefensive then
		doctrineClass = "line_defender"
		phase = 4
	elseif ranged > 0 then
		doctrineClass = "ranged_support"
		phase = 3
	end
	-- Static capture eligibility follows the unit's melee chassis.  Several
	-- Super Power dual-mode units carry an OnlyDefensive promotion for their
	-- ranged weapon while their melee chassis can still take cities (MECH is
	-- the important example), so OnlyDefensive alone is not a capture veto.
	local landCaptureClass = combatClass == "UNITCOMBAT_ARMOR"
		or combatClass == "UNITCOMBAT_MELEE"
		or combatClass == "UNITCOMBAT_MOUNTED"
		or combatClass == "UNITCOMBAT_RECON"
		or combatClass == "UNITCOMBAT_GUN"
	local seaCaptureClass = combatClass == "UNITCOMBAT_NAVALMELEE"
		or (combatClass == "UNITCOMBAT_RECON" and range <= 1 and ai ~= "UNITAI_EXPLORE_SEA")
	local canCapture = combat > 0
		and not promotions.noCapture
		and not SC_DBFlag(unitInfo.Suicide)
		and not civilianAI
		and ((domain == "DOMAIN_LAND" and landCaptureClass)
			or (domain == "DOMAIN_SEA" and seaCaptureClass))
	local profile = {
		doctrineClass = doctrineClass,
		phase = phase,
		domain = domain,
		combatClass = combatClass,
		defaultAI = ai,
		combat = combat,
		ranged = ranged,
		range = range,
		moves = moves,
		power = math.max(combat, ranged),
		canRange = ranged > 0 or domain == "DOMAIN_AIR",
		canCapture = canCapture,
		moveAfterAttack = promotions.moveAfterAttack,
		extraAttacks = promotions.extraAttacks,
		mustSetUp = promotions.mustSetUp,
		dropRange = promotions.dropRange,
		intercept = promotions.intercept,
		airSweep = promotions.airSweep,
		indirectFire = promotions.indirectFire,
		ignoreZOC = promotions.ignoreZOC,
		ignoreTerrain = promotions.ignoreTerrain,
		alwaysHeal = promotions.alwaysHeal,
		healOnKill = promotions.healOnKill,
		cityAttack = promotions.cityAttack,
		attack = promotions.attack,
		defense = promotions.defense,
		cargo = promotions.cargo,
		noCapture = promotions.noCapture,
		cityAttackOnly = promotions.cityAttackOnly,
		suicide = SC_DBFlag(unitInfo.Suicide),
		maxHP = math.max(SC_DBNumber(unitInfo.MaxHitPoints, 100), 1)
	}
	SC_UNIT_CAPABILITY_CACHE[unitType] = SC_UNIT_CAPABILITY_CACHE[unitType] or {}
	SC_UNIT_CAPABILITY_CACHE[unitType].profile = profile
	return SC5 and SC5.LiveProfile(unit, profile) or profile
end

function SC_GetUnitDoctrineClass(unit, unitInfo, role)
	return SC_GetUnitCapabilityProfile(unit, unitInfo, role).doctrineClass
end

function SC_GetUnitDoctrinePhase(unit, unitInfo, role)
	return SC_GetUnitCapabilityProfile(unit, unitInfo, role).phase or 99
end

function SC_GetStrategicMovementPhase(unit, unitInfo, role)
	local doctrineClass = SC_GetUnitDoctrineClass(unit, unitInfo, role)
	if doctrineClass == "fleet_carrier" or doctrineClass == "ballistic_submarine" or doctrineClass == "arsenal_capital" then
		return 4
	end
	if SC_IsScreenDoctrineClass ~= nil and SC_IsScreenDoctrineClass(doctrineClass) then
		return 1
	end
	if doctrineClass == "surface_fire_support" or doctrineClass == "siege_artillery" or doctrineClass == "ranged_support" then
		return 3
	end
	if doctrineClass == "civilian_builder" or doctrineClass == "civilian_settler" or doctrineClass == "civilian_trade" or doctrineClass == "civilian_religious" or doctrineClass == "civilian_specialist" then
		return 90
	end
	return 2
end

function SC_GetDoctrineRosterDebug(player)
	if player == nil then
		return "roster=nil"
	end
	local counts = {}
	local total = 0
	for unit in player:Units() do
		if unit ~= nil and not unit:IsDead() then
			local doctrineClass = SC_GetUnitDoctrineClass(unit, SC_GetUnitInfo(unit))
			counts[doctrineClass] = (counts[doctrineClass] or 0) + 1
			total = total + 1
		end
	end
	local parts = {}
	for doctrineClass, count in pairs(counts) do
		table.insert(parts, tostring(doctrineClass)..":"..tostring(count))
	end
	table.sort(parts)
	return "units="..tostring(total).." classes="..table.concat(parts, ",")
end

function SC_GetOperationFocusPlot(player, unit, unitInfo, profile)
	if player == nil then
		return nil
	end
	unitInfo = unitInfo or SC_GetUnitInfo(unit)
	profile = profile or SC_GetUnitCapabilityProfile(unit, unitInfo)
	if unitInfo == nil then
		return nil
	end
	if SC_StrategyGetOperationForUnit ~= nil then
		local assignedOperation = SC_StrategyGetOperationForUnit(unit)
		if assignedOperation ~= nil and assignedOperation.target ~= nil and assignedOperation.target.plot ~= nil then
			return assignedOperation.target.plot
		end
	end
	local operationDomain = "land"
	if unitInfo.Domain == "DOMAIN_SEA" then
		operationDomain = "sea"
	elseif unitInfo.Domain == "DOMAIN_AIR" then
		operationDomain = "air"
	end
	local unitPlot = unit ~= nil and unit:GetPlot() or nil
	local theaterSize = math.max(SC_GetConfig("OperationTheaterCellSize", 20), 8)
	local theaterX = "global"
	local theaterY = "global"
	if unitPlot ~= nil then
		theaterX = math.floor(unitPlot:GetX() / theaterSize)
		theaterY = math.floor(unitPlot:GetY() / theaterSize)
	end
	local cacheKey = tostring(player:GetID()).."|"..operationDomain.."|"..tostring(theaterX).."|"..tostring(theaterY)
	local decapitationPlot = nil
	local strikeReadiness = 0
	if SC_GetDecapitationFocusPlot ~= nil then
		decapitationPlot, strikeReadiness = SC_GetDecapitationFocusPlot(player)
	end
	local readinessThreshold = SC_GetConfig("DecapitationReadinessThreshold", 0.55)
	local decapitationAllowed = decapitationPlot ~= nil and strikeReadiness >= readinessThreshold
	local decapitationDistance = 9999
	if decapitationAllowed and unitPlot ~= nil then
		decapitationDistance = Map.PlotDistance(unitPlot:GetX(), unitPlot:GetY(), decapitationPlot:GetX(), decapitationPlot:GetY())
		local joinDistance = SC_GetConfig("DecapitationLandJoinDistance", 10)
		if operationDomain == "air" then
			joinDistance = math.max((profile.range or 0) + 2, SC_GetConfig("DecapitationAirJoinDistance", 10))
		elseif operationDomain == "sea" then
			joinDistance = SC_GetConfig("DecapitationSeaJoinDistance", 12)
		end
		decapitationAllowed = decapitationDistance <= joinDistance
	end
	if decapitationAllowed and operationDomain == "sea" then
		decapitationAllowed = SC_IsWaterOrCoastalStrategicPlot ~= nil and SC_IsWaterOrCoastalStrategicPlot(decapitationPlot)
	end
	if decapitationAllowed then
		local logKey = cacheKey.."|decapitation|"..SC_GetPlotDebug(decapitationPlot)
		if not SC_OPERATION_FOCUS_LOGGED_THIS_TURN[logKey] then
			SC_OPERATION_FOCUS_LOGGED_THIS_TURN[logKey] = true
			SC_Debug("operationFocus decapitation-local theater="..tostring(theaterX)..","..tostring(theaterY).." domain="..operationDomain.." class="..tostring(profile.doctrineClass).." target="..SC_GetPlotDebug(decapitationPlot).." distance="..tostring(decapitationDistance).." readiness="..tostring(math.floor(strikeReadiness * 100)).."%")
		end
		return decapitationPlot
	end
	local cached = SC_OPERATION_FOCUS_THIS_TURN[cacheKey]
	if cached ~= nil then
		return cached.plot
	end
	local team = Teams[player:GetTeam()]
	if team == nil then
		return nil
	end
	local bestPlot = nil
	local bestScore = -999999
	for otherID, otherPlayer in pairs(Players) do
		if otherPlayer ~= nil and otherPlayer:IsAlive() and otherPlayer:GetID() ~= player:GetID() and team:IsAtWar(otherPlayer:GetTeam()) then
			for city in otherPlayer:Cities() do
				local cityPlot = city:Plot()
				local domainAllowed = cityPlot ~= nil
				if operationDomain == "sea" and cityPlot ~= nil then
					domainAllowed = SC_IsWaterOrCoastalStrategicPlot ~= nil and SC_IsWaterOrCoastalStrategicPlot(cityPlot)
				end
				if domainAllowed and cityPlot ~= nil then
					local distance = 0
					if unitPlot ~= nil then
						distance = Map.PlotDistance(unitPlot:GetX(), unitPlot:GetY(), cityPlot:GetX(), cityPlot:GetY())
					end
					local damage = SC_GetSafeNumber(function() return city:GetDamage() end, 0)
					local score = 2400 - distance * 14 + damage * 2
					if SC_GetSafeNumber(function() return city:IsCapital() and 1 or 0 end, 0) > 0 then
						score = score + 260
					end
					if score > bestScore then
						bestScore = score
						bestPlot = cityPlot
					end
				end
			end
		end
	end
	SC_OPERATION_FOCUS_THIS_TURN[cacheKey] = { plot = bestPlot, score = bestScore }
	if bestPlot ~= nil then
		SC_Debug("operationFocus select theater="..tostring(theaterX)..","..tostring(theaterY).." domain="..operationDomain.." class="..tostring(profile.doctrineClass).." target="..SC_GetPlotDebug(bestPlot).." score="..tostring(bestScore))
	end
	return bestPlot
end

function SC_GetUnitCombatTag(unit, unitInfo, role)
	unitInfo = unitInfo or SC_GetUnitInfo(unit)
	if unitInfo == nil then
		return "unknown"
	end
	role = role or SC_GetUnitRole(unit, unitInfo)
	local profile = SC_GetUnitCapabilityProfile(unit, unitInfo, role)
	local doctrineClass = profile.doctrineClass
	local unitType = unitInfo.Type or ""
	if doctrineClass == "fleet_carrier" then
		return "fleet_flagship"
	end
	if doctrineClass == "ballistic_submarine" then
		return "strategic_submarine"
	end
	if doctrineClass == "attack_submarine" then
		return "sub_hunter"
	end
	if doctrineClass == "arsenal_capital" then
		return "arsenal_ship"
	end
	if doctrineClass == "air_defense_screen" then
		return "missile_screen"
	end
	if doctrineClass == "surface_fire_support" or doctrineClass == "escort_screen" or doctrineClass == "naval_assault" then
		return "surface_screen"
	end
	if doctrineClass == "missile_strike" or doctrineClass == "strategic_nuclear" then
		return "missile_strike"
	end
	if doctrineClass == "air_superiority" or doctrineClass == "carrier_multirole" or doctrineClass == "strike_aircraft" then
		return "air_wing"
	end
	if doctrineClass == "super_heavy" then
		return "super_heavy"
	end
	if doctrineClass == "siege_artillery" or doctrineClass == "static_fortress" then
		return "siege_artillery"
	end
	if doctrineClass == "mobile_breakthrough" or doctrineClass == "gunship" or (unitType == "UNIT_MECHANIZED_INFANTRY") then
		return "fast_breakthrough"
	end
	if doctrineClass == "ranged_support" or doctrineClass == "mobile_air_defense" then
		return "fire_support"
	end
	return "line_assault"
end

function SC_IsProtectedCombatTag(tag)
	return tag == "fleet_flagship"
		or tag == "arsenal_ship"
		or tag == "strategic_submarine"
end

function SC_IsScreenCombatTag(tag)
	return tag == "missile_screen"
		or tag == "surface_screen"
		or tag == "sub_hunter"
end

function SC_IsProtectedDoctrineClass(doctrineClass)
	return doctrineClass == "fleet_carrier"
		or doctrineClass == "ballistic_submarine"
		or doctrineClass == "arsenal_capital"
end

function SC_GetUnitProtectionTier(unit, unitInfo, role, profile)
	unitInfo = unitInfo or SC_GetUnitInfo(unit)
	if unitInfo == nil then
		return 0
	end
	role = role or SC_GetUnitRole(unit, unitInfo)
	profile = profile or SC_GetUnitCapabilityProfile(unit, unitInfo, role)
	local unitType = unitInfo.Type or ""
	if SC_TextHas(unitType, "GREAT_GENERAL") or SC_TextHas(unitType, "GREAT_ADMIRAL") then
		return 3
	end
	if unitType == "UNIT_MECH" or SC_IsProtectedDoctrineClass(profile.doctrineClass) then
		return 3
	end
	if unitInfo.ProjectPrereq ~= nil and unitInfo.ProjectPrereq ~= "" then
		return 3
	end
	if profile.doctrineClass == "siege_artillery" or profile.doctrineClass == "gunship"
		or (profile.canRange and (profile.range or 0) >= 4) or (profile.power or 0) >= 250 then
		return 2
	end
	if (profile.power or 0) >= 130 then
		return 1
	end
	return 0
end

function SC_IsHighValueCombatAsset(unit, unitInfo, role, profile)
	return SC_GetUnitProtectionTier(unit, unitInfo, role, profile) >= 2
end

function SC_GetUnitRetreatDamageThreshold(unit, unitInfo, role, profile)
	local threshold = SC_GetConfig("HealDamageThreshold", 45)
	if SC_GetUnitProtectionTier(unit, unitInfo, role, profile) >= 2 then
		threshold = math.min(threshold, SC_GetConfig("ProtectedAssetRetreatDamage", 20))
	end
	return threshold
end

function SC_UnitIsFitForCombat(unit, unitInfo, role, profile)
	if SC5 and unit ~= nil then
		local key = SC_GetUnitTurnKey(unit)
		if key and SC_HEAL_HANDLED_THIS_TURN[key] then return false end
		profile = profile or SC_GetUnitCapabilityProfile(unit, unitInfo, role)
		if profile.canRange then return SC5.HP(unit) > 0 end
	end
	return unit ~= nil and unit:GetDamage() < SC_GetUnitRetreatDamageThreshold(unit, unitInfo, role, profile)
end

function SC_IsScreenDoctrineClass(doctrineClass)
	return doctrineClass == "air_defense_screen"
		or doctrineClass == "escort_screen"
		or doctrineClass == "attack_submarine"
		or doctrineClass == "mobile_air_defense"
end

function SC_GetUnitEffectivePower(unit, unitInfo, profile)
	unitInfo = unitInfo or SC_GetUnitInfo(unit)
	profile = profile or SC_GetUnitCapabilityProfile(unit, unitInfo)
	local power = math.max(profile.power or 0, 1)
	local damage = SC_GetSafeNumber(function() return unit:GetDamage() end, 0)
	local maxHP = math.max(profile.maxHP or 100, 1)
	local healthRatio = math.max(0.15, 1 - damage / maxHP)
	return power * (0.45 + healthRatio * 0.55)
end

function SC_CountEnemyCombatPresenceNearPlot(player, targetPlot, radius, maxCount)
	if player == nil or targetPlot == nil then
		return 0
	end
	radius = radius or SC_GetConfig("OperationEnemyScreenRadius", 4)
	maxCount = maxCount or 8
	local playerID = player:GetID()
	local plotIndex = nil
	pcall(function() plotIndex = targetPlot:GetPlotIndex() end)
	local cacheKey = nil
	if plotIndex ~= nil then
		cacheKey = tostring(playerID).."|"..tostring(plotIndex).."|"..tostring(radius)
		if SC_OPERATION_TARGET_CACHE_THIS_TURN[cacheKey] ~= nil then
			return SC_OPERATION_TARGET_CACHE_THIS_TURN[cacheKey]
		end
	end
	local team = Teams[player:GetTeam()]
	local count = 0
	for dx = -radius, radius, 1 do
		for dy = -radius, radius, 1 do
			local plot = SC_GetNearbyPlot(targetPlot:GetX(), targetPlot:GetY(), dx, dy, radius)
			if plot ~= nil and Map.PlotDistance(targetPlot:GetX(), targetPlot:GetY(), plot:GetX(), plot:GetY()) <= radius then
				local unitCount = SC_GetSafeNumber(function() return plot:GetNumUnits() end, 0)
				for i = 0, unitCount - 1, 1 do
					local enemyUnit = nil
					pcall(function() enemyUnit = plot:GetUnit(i) end)
					if enemyUnit ~= nil and not enemyUnit:IsDead() then
						local ownerID = SC_GetSafeNumber(function() return enemyUnit:GetOwner() end, -1)
						local owner = Players[ownerID]
						local enemyInfo = SC_GetUnitInfo(enemyUnit)
						if owner ~= nil and owner:IsAlive() and team ~= nil and team:IsAtWar(owner:GetTeam())
							and enemyInfo ~= nil and ((enemyInfo.Combat or 0) > 0 or (enemyInfo.RangedCombat or 0) > 0) then
							count = count + 1
							if count >= maxCount then
								if cacheKey ~= nil then
									SC_OPERATION_TARGET_CACHE_THIS_TURN[cacheKey] = count
								end
								return count
							end
						end
					end
				end
			end
		end
	end
	if cacheKey ~= nil then
		SC_OPERATION_TARGET_CACHE_THIS_TURN[cacheKey] = count
	end
	return count
end

function SC_GetDoctrineTargetModifier(attacker, attackerInfo, attackerRole, targetUnit, targetInfo, targetRole, reasons)
	if attackerInfo == nil or targetInfo == nil then
		return 0
	end
	local attackerProfile = SC_GetUnitCapabilityProfile(attacker, attackerInfo, attackerRole)
	local targetProfile = SC_GetUnitCapabilityProfile(targetUnit, targetInfo, targetRole)
	local attackerClass = attackerProfile.doctrineClass
	local targetClass = targetProfile.doctrineClass
	local score = 0
	local attackerPower = SC_GetUnitEffectivePower(attacker, attackerInfo, attackerProfile)
	local targetPower = SC_GetUnitEffectivePower(targetUnit, targetInfo, targetProfile)
	local powerRatio = attackerPower / math.max(targetPower, 1)
	if powerRatio >= 2.5 then
		score = score + 360
		SC_AddScoreReason(reasons, "overmatch", 360)
	elseif powerRatio >= 1.6 then
		score = score + 220
		SC_AddScoreReason(reasons, "powerEdge", 220)
	elseif powerRatio < 0.72 and not attackerProfile.canRange then
		score = score - 900
		SC_AddScoreReason(reasons, "badMatchup", -900)
	elseif powerRatio < 0.95 and not attackerProfile.canRange then
		score = score - 320
		SC_AddScoreReason(reasons, "riskyMelee", -320)
	end
	if targetProfile.ranged > 0 or targetClass == "siege_artillery" or targetClass == "strike_aircraft" then
		score = score + 180
		SC_AddScoreReason(reasons, "removeFirepower", 180)
	end
	if targetClass == "fleet_carrier" or targetClass == "ballistic_submarine" or targetClass == "arsenal_capital" then
		score = score + 420
		SC_AddScoreReason(reasons, "strategicAsset", 420)
	end
	if attackerClass == "air_superiority" or attackerClass == "carrier_multirole" then
		if targetClass == "strike_aircraft" or targetClass == "air_superiority" or targetClass == "carrier_multirole" then
			score = score + 620
			SC_AddScoreReason(reasons, "airControl", 620)
		elseif targetClass == "mobile_air_defense" or targetClass == "air_defense_screen" then
			score = score + 360
			SC_AddScoreReason(reasons, "suppressAA", 360)
		elseif targetInfo.Domain == "DOMAIN_SEA" then
			score = score + 260
			SC_AddScoreReason(reasons, "fleetStrike", 260)
		end
	elseif attackerClass == "strike_aircraft" or attackerClass == "missile_strike" then
		if targetClass == "mobile_air_defense" or targetClass == "air_defense_screen" then
			score = score + 520
			SC_AddScoreReason(reasons, "openAirCorridor", 520)
		elseif targetClass == "siege_artillery" or targetClass == "surface_fire_support" then
			score = score + 360
			SC_AddScoreReason(reasons, "deepStrike", 360)
		end
	elseif attackerClass == "attack_submarine" then
		if targetClass == "fleet_carrier" then
			score = score + 900
			SC_AddScoreReason(reasons, "carrierKill", 900)
		elseif targetClass == "ballistic_submarine" or targetClass == "arsenal_capital" then
			score = score + 700
			SC_AddScoreReason(reasons, "capitalKill", 700)
		elseif targetInfo.Domain == "DOMAIN_SEA" then
			score = score + 420
			SC_AddScoreReason(reasons, "seaDenial", 420)
		else
			score = score - 420
			SC_AddScoreReason(reasons, "subLandWaste", -420)
		end
	elseif attackerClass == "air_defense_screen" or attackerClass == "mobile_air_defense" then
		if targetInfo.Domain == "DOMAIN_AIR" or targetClass == "missile_strike" then
			score = score + 760
			SC_AddScoreReason(reasons, "airDefense", 760)
		elseif targetInfo.Domain == "DOMAIN_SEA" and attackerClass == "air_defense_screen" then
			score = score + 240
			SC_AddScoreReason(reasons, "screenFight", 240)
		end
	elseif attackerClass == "mobile_breakthrough" or attackerClass == "gunship" or attackerClass == "super_heavy" then
		if targetClass == "siege_artillery" or targetClass == "ranged_support" or targetClass == "mobile_air_defense" then
			score = score + 460
			SC_AddScoreReason(reasons, "breakthroughTarget", 460)
		elseif targetClass == "line_defender" or targetClass == "counter_defender" then
			score = score - 120
			SC_AddScoreReason(reasons, "screenedTarget", -120)
		end
	elseif attackerClass == "counter_defender" then
		if targetClass == "mobile_breakthrough" or targetClass == "gunship" then
			score = score + 520
			SC_AddScoreReason(reasons, "counterMobile", 520)
		end
	elseif attackerClass == "siege_artillery" or attackerClass == "surface_fire_support" or attackerClass == "arsenal_capital" then
		if targetClass == "line_defender" or targetClass == "counter_defender" or targetClass == "surface_fire_support" then
			score = score + 260
			SC_AddScoreReason(reasons, "fireSupportTarget", 260)
		end
	end
	if attackerProfile.suicide and targetPower < attackerPower * 0.35 then
		score = score - 700
		SC_AddScoreReason(reasons, "munitionWaste", -700)
	end
	return score
end

function SC_CountFriendlyProtectedAssetsNearPlot(player, targetPlot, radius, maxCount)
	if player == nil or targetPlot == nil then
		return 0, 0
	end
	radius = radius or SC_GetConfig("ProtectedAssetThreatRadius", 6)
	maxCount = maxCount or 8
	local playerID = player:GetID()
	local plotIndex = nil
	pcall(function() plotIndex = targetPlot:GetPlotIndex() end)
	local cacheKey = nil
	if plotIndex ~= nil then
		cacheKey = tostring(playerID).."|"..tostring(plotIndex).."|"..tostring(radius)
		local cached = SC_PROTECTED_ASSET_CACHE_THIS_TURN[cacheKey]
		if cached ~= nil then
			return cached.protected or 0, cached.transports or 0
		end
	end
	local protected = 0
	local transports = 0
	for dx = -radius, radius, 1 do
		for dy = -radius, radius, 1 do
			local plot = SC_GetNearbyPlot ~= nil and SC_GetNearbyPlot(targetPlot:GetX(), targetPlot:GetY(), dx, dy, radius) or nil
			if plot ~= nil and Map.PlotDistance(targetPlot:GetX(), targetPlot:GetY(), plot:GetX(), plot:GetY()) <= radius then
				local unitCount = SC_GetSafeNumber(function() return plot:GetNumUnits() end, 0)
				for i = 0, unitCount - 1, 1 do
					local otherUnit = nil
					pcall(function() otherUnit = plot:GetUnit(i) end)
					if otherUnit ~= nil and SC_GetSafeNumber(function() return otherUnit:GetOwner() end, -1) == playerID then
						local otherInfo = SC_GetUnitInfo(otherUnit)
						if SC_IsFragileTransportUnit ~= nil and SC_IsFragileTransportUnit(otherUnit, otherInfo) then
							transports = transports + 1
						else
							local otherRole = SC_GetUnitRole(otherUnit, otherInfo)
							local otherTag = SC_GetUnitCombatTag(otherUnit, otherInfo, otherRole)
							local otherProfile = SC_GetUnitCapabilityProfile(otherUnit, otherInfo, otherRole)
							if otherRole == "carrier" or SC_IsProtectedCombatTag(otherTag)
								or SC_IsHighValueCombatAsset(otherUnit, otherInfo, otherRole, otherProfile) then
								protected = protected + 1
							end
						end
						if protected + transports >= maxCount then
							if cacheKey ~= nil then
								SC_PROTECTED_ASSET_CACHE_THIS_TURN[cacheKey] = { protected = protected, transports = transports }
							end
							return protected, transports
						end
					end
				end
			end
		end
	end
	if cacheKey ~= nil then
		SC_PROTECTED_ASSET_CACHE_THIS_TURN[cacheKey] = { protected = protected, transports = transports }
	end
	return protected, transports
end

function SC_GetProtectedAssetThreatScore(player, attacker, targetPlot, enemyUnit, enemyInfo, enemyRole, friendlyRole, friendlyTag, reasons)
	if player == nil or attacker == nil or targetPlot == nil or enemyUnit == nil then
		return 0
	end
	local attackerPlot = attacker:GetPlot()
	if attackerPlot == nil then
		return 0
	end
	local responseDistance = Map.PlotDistance(attackerPlot:GetX(), attackerPlot:GetY(), targetPlot:GetX(), targetPlot:GetY())
	local screenResponder = SC_IsScreenCombatTag(friendlyTag)
		or friendlyRole == "carrier_air"
		or friendlyRole == "fighter"
		or friendlyRole == "bomber"
		or friendlyRole == "missile"
	local responseLimit = SC_GetConfig("ProtectedAssetResponseMaxDistance", 12)
	if screenResponder then
		responseLimit = SC_GetConfig("ProtectedAssetScreenResponseMaxDistance", 16)
	end
	if responseDistance > responseLimit then
		return 0
	end
	local protected, transports = SC_CountFriendlyProtectedAssetsNearPlot(player, targetPlot, SC_GetConfig("ProtectedAssetThreatRadius", 6), 8)
	if protected <= 0 and transports <= 0 then
		return 0
	end
	local threatWeight = 1
	if enemyInfo ~= nil then
		if enemyInfo.Domain == "DOMAIN_SEA" then
			threatWeight = threatWeight + 1
		end
		if enemyInfo.Domain == "DOMAIN_AIR" then
			threatWeight = threatWeight + 1
		end
		if (enemyInfo.RangedCombat or 0) > 0 then
			threatWeight = threatWeight + 1
		end
		if (enemyInfo.Range or 0) >= 2 then
			threatWeight = threatWeight + 1
		end
	end
	if enemyRole == "submarine" or enemyRole == "missile_carrier" or enemyRole == "naval_ranged" or enemyRole == "carrier_air" or enemyRole == "bomber" or enemyRole == "missile" then
		threatWeight = threatWeight + 2
	end
	local protectedWeight = math.min(protected, 3)
	local transportWeight = math.min(transports, 2)
	local rawScore = protectedWeight * 140 * threatWeight + transportWeight * 220 * threatWeight
	if friendlyTag == "missile_screen" or friendlyTag == "sub_hunter" or friendlyRole == "carrier_air" or friendlyRole == "fighter" or friendlyRole == "bomber" or friendlyRole == "missile" then
		rawScore = rawScore + (protectedWeight + transportWeight) * 120
	end
	local distanceFactor = math.max(0.2, (responseLimit - responseDistance + 1) / (responseLimit + 1))
	local roleFactor = screenResponder and 1 or 0.35
	local scoreCap = screenResponder and SC_GetConfig("ProtectedAssetScreenThreatScoreCap", 1400)
		or SC_GetConfig("ProtectedAssetOtherThreatScoreCap", 650)
	local score = math.min(scoreCap, math.floor(rawScore * distanceFactor * roleFactor))
	if score > 0 then
		SC_AddScoreReason(reasons, "localAssetThreat", score)
		SC_AddScoreReason(reasons, "responseDist", -responseDistance * 10)
	end
	return score
end

function SC_GetUnitAuditSnapshot(unit)
	if unit == nil then
		return nil
	end
	local unitInfo = SC_GetUnitInfo(unit)
	local unitRole = SC_GetUnitRole(unit, unitInfo)
	local capability = SC_GetUnitCapabilityProfile(unit, unitInfo, unitRole)
	local plot = nil
	pcall(function() plot = unit:GetPlot() end)
	local snapshot = {
		key = SC_GetUnitTurnKey(unit),
		label = SC_GetUnitDebugLabel(unit),
		role = unitRole,
		doctrineClass = capability.doctrineClass,
		phase = capability.phase,
		power = capability.power,
		range = capability.range,
		intercept = capability.intercept,
		canCapture = capability.canCapture,
		moveAfterAttack = capability.moveAfterAttack,
		extraAttacks = capability.extraAttacks,
		mustSetUp = capability.mustSetUp,
		dropRange = capability.dropRange,
		unitType = unitInfo ~= nil and unitInfo.Type or "UNIT?",
		domain = unitInfo ~= nil and unitInfo.Domain or "?",
		combatClass = unitInfo ~= nil and unitInfo.CombatClass or "?",
		ai = unitInfo ~= nil and unitInfo.DefaultUnitAI or "?",
		plot = SC_GetPlotDebug(plot),
		x = "?",
		y = "?",
		owner = "?",
		moves = "?",
		damage = "?",
		hp = "?",
		activity = "?",
		ready = "?",
		waiting = "?",
		automated = "?",
		canMove = "?",
		needsOrder = "?",
		embarked = "?",
		fortified = "?",
		cargo = "?",
		level = "?",
		experience = "?"
	}
	if plot ~= nil then
		pcall(function() snapshot.x = tostring(plot:GetX()) end)
		pcall(function() snapshot.y = tostring(plot:GetY()) end)
	end
	pcall(function() snapshot.owner = tostring(unit:GetOwner()) end)
	pcall(function() snapshot.moves = tostring(unit:MovesLeft()) end)
	pcall(function() snapshot.damage = tostring(unit:GetDamage()) end)
	pcall(function() snapshot.hp = tostring(unit:GetCurrHitPoints()) end)
	pcall(function() snapshot.activity = tostring(unit:GetActivityType()) end)
	pcall(function() snapshot.ready = SC_BoolText(unit:IsReadyToMove()) end)
	pcall(function() snapshot.waiting = SC_BoolText(unit:IsWaiting()) end)
	pcall(function() snapshot.automated = SC_BoolText(unit:IsAutomated()) end)
	pcall(function() snapshot.canMove = SC_BoolText(unit:CanMove()) end)
	pcall(function() snapshot.embarked = SC_BoolText(unit:IsEmbarked()) end)
	pcall(function() snapshot.fortified = tostring(unit:GetFortifyTurns()) end)
	pcall(function() snapshot.cargo = tostring(unit:GetCargo()) end)
	pcall(function() snapshot.level = tostring(unit:GetLevel()) end)
	pcall(function() snapshot.experience = tostring(unit:GetExperience()) end)
	if SC_UnitNeedsOrder ~= nil then
		pcall(function() snapshot.needsOrder = SC_BoolText(SC_UnitNeedsOrder(unit)) end)
	end
	return snapshot
end

function SC_FormatUnitAuditSnapshot(snapshot)
	if snapshot == nil then
		return "nil-snapshot"
	end
	return "unit="..tostring(snapshot.label)..
		" role="..tostring(snapshot.role)..
		" class="..tostring(snapshot.doctrineClass)..
		" phase="..tostring(snapshot.phase)..
		" type="..tostring(snapshot.unitType)..
		" domain="..tostring(snapshot.domain)..
		" ai="..tostring(snapshot.ai)..
		" power="..tostring(snapshot.power)..
		" range="..tostring(snapshot.range)..
		" intercept="..tostring(snapshot.intercept)..
		" canCapture="..SC_BoolText(snapshot.canCapture == true)..
		" moveAfterAttack="..SC_BoolText(snapshot.moveAfterAttack == true)..
		" extraAttacks="..tostring(snapshot.extraAttacks)..
		" mustSetUp="..SC_BoolText(snapshot.mustSetUp == true)..
		" dropRange="..tostring(snapshot.dropRange)..
		" plot="..tostring(snapshot.plot)..
		" moves="..tostring(snapshot.moves)..
		" damage="..tostring(snapshot.damage)..
		" hp="..tostring(snapshot.hp)..
		" activity="..tostring(snapshot.activity)..
		" ready="..tostring(snapshot.ready)..
		" waiting="..tostring(snapshot.waiting)..
		" automated="..tostring(snapshot.automated)..
		" canMove="..tostring(snapshot.canMove)..
		" needsOrder="..tostring(snapshot.needsOrder)..
		" embarked="..tostring(snapshot.embarked)..
		" fortified="..tostring(snapshot.fortified)..
		" cargo="..tostring(snapshot.cargo)..
		" level="..tostring(snapshot.level)..
		" xp="..tostring(snapshot.experience)
end

function SC_GetUnitAuditDelta(previous, current)
	if previous == nil or current == nil then
		return nil
	end
	local parts = {}
	local function compare(name)
		if previous[name] ~= current[name] then
			table.insert(parts, name.."="..tostring(previous[name]).."->"..tostring(current[name]))
		end
	end
	compare("plot")
	compare("moves")
	compare("damage")
	compare("hp")
	compare("activity")
	compare("ready")
	compare("waiting")
	compare("automated")
	compare("canMove")
	compare("needsOrder")
	compare("embarked")
	compare("fortified")
	compare("cargo")
	compare("level")
	compare("experience")
	if #parts == 0 then
		return nil
	end
	return table.concat(parts, " ")
end

function SC_AuditPlayerUnits(player, phase, fullSnapshot)
	if not SC_GetConfig("DebugUnitAudit", true) or player == nil then
		return 0, 0
	end
	local playerID = SC_GetSafeNumber(function() return player:GetID() end, -1)
	local maxUnits = SC_GetConfig("DebugUnitAuditMaxUnitsPerPass", 500)
	local seen = {}
	local count = 0
	local changes = 0
	SC_UNIT_AUDIT_SEQ = (SC_UNIT_AUDIT_SEQ or 0) + 1
	SC_Debug("unitAudit begin seq="..tostring(SC_UNIT_AUDIT_SEQ).." phase="..tostring(phase).." full="..SC_BoolText(fullSnapshot == true).." player=P"..tostring(playerID))
	for unit in player:Units() do
		local snapshot = SC_GetUnitAuditSnapshot(unit)
		if snapshot ~= nil and snapshot.key ~= nil then
			count = count + 1
			seen[snapshot.key] = true
			local previous = SC_UNIT_AUDIT_LAST[snapshot.key]
			local delta = SC_GetUnitAuditDelta(previous, snapshot)
			if (fullSnapshot == true or previous == nil) and count <= maxUnits then
				SC_Debug("unitAudit state seq="..tostring(SC_UNIT_AUDIT_SEQ).." phase="..tostring(phase).." "..SC_FormatUnitAuditSnapshot(snapshot))
			end
			if previous == nil then
				changes = changes + 1
				SC_Debug("unitAudit new seq="..tostring(SC_UNIT_AUDIT_SEQ).." phase="..tostring(phase).." "..SC_FormatUnitAuditSnapshot(snapshot))
			elseif delta ~= nil then
				changes = changes + 1
				SC_Debug("unitAudit delta seq="..tostring(SC_UNIT_AUDIT_SEQ).." phase="..tostring(phase).." unit="..tostring(snapshot.label).." role="..tostring(snapshot.role).." "..delta)
			end
			SC_UNIT_AUDIT_LAST[snapshot.key] = snapshot
		end
	end
	for key, previous in pairs(SC_UNIT_AUDIT_LAST) do
		if previous ~= nil and tostring(previous.owner) == tostring(playerID) and not seen[key] then
			changes = changes + 1
			SC_Debug("unitAudit missing seq="..tostring(SC_UNIT_AUDIT_SEQ).." phase="..tostring(phase).." unit="..tostring(previous.label).." role="..tostring(previous.role).." lastPlot="..tostring(previous.plot).." lastDamage="..tostring(previous.damage).." lastActivity="..tostring(previous.activity))
			SC_UNIT_AUDIT_LAST[key] = nil
		end
	end
	SC_Debug("unitAudit end seq="..tostring(SC_UNIT_AUDIT_SEQ).." phase="..tostring(phase).." units="..tostring(count).." changes="..tostring(changes))
	return count, changes
end

function SC_SanitizeDemoText(text)
	text = tostring(text or "")
	text = string.gsub(text, "[\r\n\t ]+", "_")
	text = string.gsub(text, "\"", "'")
	return text
end

function SC_GetPlayerDemoLabel(player)
	if player == nil then
		return "P?"
	end
	local playerID = SC_GetSafeNumber(function() return player:GetID() end, -1)
	local teamID = SC_GetSafeNumber(function() return player:GetTeam() end, -1)
	local civ = "?"
	local leader = "?"
	pcall(function() civ = player:GetCivilizationShortDescription() end)
	pcall(function() leader = player:GetName() end)
	return "P"..tostring(playerID).." team="..tostring(teamID).." civ="..SC_SanitizeDemoText(civ).." leader="..SC_SanitizeDemoText(leader)
end

function SC_CountPlayerUnits(player)
	local count = 0
	if player ~= nil then
		for unit in player:Units() do
			count = count + 1
		end
	end
	return count
end

function SC_CountPlayerCities(player)
	local count = 0
	if player ~= nil then
		for city in player:Cities() do
			count = count + 1
		end
	end
	return count
end

function SC_PlayerAtWarWithActive(player)
	local active = nil
	pcall(function()
		if Players ~= nil and Game ~= nil then
			active = Players[Game.GetActivePlayer()]
		end
	end)
	if player == nil or active == nil or player:GetID() == active:GetID() then
		return false
	end
	local activeTeam = Teams[active:GetTeam()]
	if activeTeam == nil then
		return false
	end
	return activeTeam:IsAtWar(player:GetTeam())
end

function SC_FormatCityDemoSnapshot(city)
	if city == nil then
		return "city=nil"
	end
	local owner = SC_GetSafeNumber(function() return city:GetOwner() end, -1)
	local cityID = SC_GetSafeNumber(function() return city:GetID() end, -1)
	local x = SC_GetSafeNumber(function() return city:GetX() end, -1)
	local y = SC_GetSafeNumber(function() return city:GetY() end, -1)
	local pop = SC_GetSafeNumber(function() return city:GetPopulation() end, -1)
	local damage = SC_GetSafeNumber(function() return city:GetDamage() end, -1)
	local maxHP = SC_GetSafeNumber(function() return city:GetMaxHitPoints() end, -1)
	local production = "?"
	local name = "city"
	pcall(function() name = city:GetName() end)
	pcall(function() production = city:GetProductionName() end)
	return "city="..SC_SanitizeDemoText(name).."#"..tostring(cityID)..
		" owner=P"..tostring(owner)..
		" plot="..tostring(x)..","..tostring(y)..
		" pop="..tostring(pop)..
		" damage="..tostring(damage)..
		" maxHP="..tostring(maxHP)..
		" production="..SC_SanitizeDemoText(production)
end

function SC_DemoAuditWorld(reason, fullSnapshot)
	if not SC_IsDemonstrationLoggingActive() then
		return
	end
	local turn = SC_GetSafeNumber(function() return Game.GetGameTurn() end, -1)
	local snapshotKey = tostring(turn).."|"..tostring(reason)
	if SC_DEMO_WORLD_SNAPSHOT_TURN == turn and SC_DEMO_WORLD_SNAPSHOT_REASON == snapshotKey then
		return
	end
	SC_DEMO_WORLD_SNAPSHOT_TURN = turn
	SC_DEMO_WORLD_SNAPSHOT_REASON = snapshotKey
	local activePlayerID = SC_GetSafeNumber(function() return Game.GetActivePlayer() end, -1)
	local maxUnits = SC_GetConfig("DemonstrationMaxUnitsPerSnapshot", 2500)
	local maxCities = SC_GetConfig("DemonstrationMaxCitiesPerSnapshot", 500)
	local unitLines = 0
	local cityLines = 0
	SC_DemoLog("world", "reason="..tostring(reason).." full="..SC_BoolText(fullSnapshot == true).." active=P"..tostring(activePlayerID))
	for playerID, player in pairs(Players) do
		if player ~= nil and player:IsAlive() then
			local unitCount = SC_CountPlayerUnits(player)
			local cityCount = SC_CountPlayerCities(player)
			SC_DemoLog("playerSummary", "reason="..tostring(reason).." "..SC_GetPlayerDemoLabel(player)..
				" human="..SC_BoolText(player:IsHuman())..
				" minor="..SC_BoolText(player:IsMinorCiv())..
				" barbarian="..SC_BoolText(player:IsBarbarian())..
				" atWarActive="..SC_BoolText(SC_PlayerAtWarWithActive(player))..
				" units="..tostring(unitCount)..
				" cities="..tostring(cityCount)..
				" gold="..tostring(SC_GetSafeNumber(function() return player:GetGold() end, "?"))..
				" goldRate="..tostring(SC_GetSafeNumber(function() return player:CalculateGoldRate() end, "?")))
			if fullSnapshot == true then
				for city in player:Cities() do
					if cityLines < maxCities then
						SC_DemoLog("cityState", "reason="..tostring(reason).." "..SC_FormatCityDemoSnapshot(city))
					elseif cityLines == maxCities then
						SC_DemoLog("cityState", "reason="..tostring(reason).." truncated=true max="..tostring(maxCities))
					end
					cityLines = cityLines + 1
				end
				for unit in player:Units() do
					if unitLines < maxUnits then
						local snapshot = SC_GetUnitAuditSnapshot(unit)
						SC_DemoLog("unitState", "reason="..tostring(reason).." "..SC_FormatUnitAuditSnapshot(snapshot))
					elseif unitLines == maxUnits then
						SC_DemoLog("unitState", "reason="..tostring(reason).." truncated=true max="..tostring(maxUnits))
					end
					unitLines = unitLines + 1
				end
			end
		end
	end
	SC_DemoLog("worldEnd", "reason="..tostring(reason).." unitsLogged="..tostring(math.min(unitLines, maxUnits)).." unitsSeen="..tostring(unitLines).." citiesLogged="..tostring(math.min(cityLines, maxCities)).." citiesSeen="..tostring(cityLines))
end

local function SC_IsRangedAttackUnit(unit, unitInfo, role)
	if unit == nil or unitInfo == nil then
		return false
	end
	if role == "carrier" or role == "nuke" then
		return false
	end
	if role == "missile" then
		return true
	end
	if (unitInfo.NukeDamageLevel or 0) > 0 or unitInfo.Special == "SPECIALUNIT_NUKE" then
		return false
	end
	if unitInfo.Domain == "DOMAIN_AIR" and (unitInfo.RangedCombat or 0) > 0 then
		return true
	end
	if (unitInfo.RangedCombat or 0) > 0 then
		return true
	end
	local isRanged = false
	pcall(function() isRanged = unit:IsRanged() end)
	return isRanged
end

local function SC_IsCombatAutomationUnit(unit, unitInfo)
	if unit == nil then
		return false
	end
	unitInfo = unitInfo or SC_GetUnitInfo(unit)
	local isCombat = false
	pcall(function() isCombat = unit:IsCombatUnit() end)
	if isCombat then
		return true
	end
	if unitInfo ~= nil and unitInfo.Domain == "DOMAIN_AIR" then
		return true
	end
	if unitInfo ~= nil and ((unitInfo.Combat or 0) > 0 or (unitInfo.RangedCombat or 0) > 0) then
		return true
	end
	return false
end

local function SC_CanUnitActForTactical(unit, unitInfo)
	if unit == nil then
		return false
	end
	if SC5 and SC5.IsWithdrawing(unit) then return false end
	local canAct = false
	pcall(function() canAct = unit:CanMove() end)
	if canAct then
		return true
	end
	pcall(function() canAct = unit:IsReadyToMove() end)
	if canAct then
		return true
	end
	pcall(function() canAct = unit:ReadyToMove() end)
	if canAct then
		return true
	end
	unitInfo = unitInfo or SC_GetUnitInfo(unit)
	if unitInfo ~= nil and unitInfo.Domain == "DOMAIN_AIR" and (unitInfo.RangedCombat or 0) > 0 then
		local moves = SC_GetSafeNumber(function() return unit:MovesLeft() end, 0)
		local canMove = false
		pcall(function() canMove = unit:CanMove() end)
		return canMove or moves > 0
	end
	return false
end

function SC_GetTacticalActionCount(unitKey)
	if unitKey == nil then
		return 0
	end
	local value = SC_TACTICAL_ORDERED_THIS_TURN[unitKey]
	if value == true then
		return 1
	end
	return tonumber(value) or 0
end

function SC_GetStrategicOrderCount(unitKey)
	if unitKey == nil then
		return 0
	end
	local value = SC_STRATEGIC_ORDERED_THIS_TURN[unitKey]
	if value == true then
		return 1
	end
	return tonumber(value) or 0
end

function SC_RecordStrategicOrder(unitKey)
	if unitKey == nil then
		return 0
	end
	local count = SC_GetStrategicOrderCount(unitKey) + 1
	SC_STRATEGIC_ORDERED_THIS_TURN[unitKey] = count
	return count
end

function SC_GetStrategicOrderCapForUnit(unit, unitInfo, role)
	local profile = SC_GetUnitCapabilityProfile(unit, unitInfo, role)
	local cap = 1
	if profile.moveAfterAttack then
		cap = cap + 1
	end
	cap = cap + math.min(profile.extraAttacks or 0, 2)
	if profile.doctrineClass == "super_heavy" then
		cap = math.max(cap, 4)
	end
	return math.min(cap, SC_GetConfig("MaxStrategicOrdersPerUnitPerTurn", 4))
end

function SC_MarkStrategicUnitDone(unit)
	local unitKey = SC_GetUnitTurnKey(unit)
	if unitKey == nil then
		return
	end
	local unitInfo = SC_GetUnitInfo(unit)
	local role = SC_GetUnitRole(unit, unitInfo)
	SC_STRATEGIC_ORDERED_THIS_TURN[unitKey] = SC_GetStrategicOrderCapForUnit(unit, unitInfo, role)
end

function SC_RecordTacticalAction(unitKey)
	if unitKey == nil then
		return 0
	end
	local count = SC_GetTacticalActionCount(unitKey) + 1
	SC_TACTICAL_ORDERED_THIS_TURN[unitKey] = count
	return count
end

function SC_GetTacticalActionCapForUnit(unit, unitInfo, role)
	local defaultCap = SC_GetConfig("MaxTacticalActionsPerUnitPerTurn", 2)
	local profile = SC_GetUnitCapabilityProfile(unit, unitInfo, role)
	local cap = defaultCap
	if role == "carrier_air" or role == "fighter" or role == "bomber" then
		cap = SC_GetConfig("MaxAirTacticalActionsPerUnitPerTurn", 5)
	elseif role == "missile" then
		cap = SC_GetConfig("MaxMissileTacticalActionsPerUnitPerTurn", 2)
	elseif role == "missile_carrier" or role == "naval_ranged" or role == "submarine" then
		cap = SC_GetConfig("MaxNavalTacticalActionsPerUnitPerTurn", 4)
	elseif role == "siege" or role == "land_ranged" then
		cap = SC_GetConfig("MaxLandRangedTacticalActionsPerUnitPerTurn", 3)
	end
	if profile.moveAfterAttack or (profile.extraAttacks or 0) > 0 then
		cap = math.max(cap, math.min(1 + (profile.extraAttacks or 0), SC_GetConfig("MaxMultiAttackTacticalActions", 6)))
	end
	return cap
end

function SC_GetUnitPlotIndexForTacticalCache(unit)
	if unit == nil then
		return nil
	end
	local plot = nil
	pcall(function() plot = unit:GetPlot() end)
	if plot == nil then
		return nil
	end
	local ok, index = pcall(function() return plot:GetPlotIndex() end)
	if ok then
		return index
	end
	return nil
end

function SC_FormatTacticalNoTargetCache(info)
	if info == nil then
		return "cache=nil"
	end
	return "cachedPlot="..tostring(info.plotIndex or "nil")..
		" role="..tostring(info.role or "nil")..
		" enemyUnits="..tostring(info.enemyUnits or 0)..
		" enemyCities="..tostring(info.enemyCities or 0)..
		" outOfRange="..tostring(info.outOfRange or 0)..
		" reason="..tostring(info.reason or "nil")
end

function SC_GetValidTacticalNoTargetCache(unit, unitKey)
	if unitKey == nil then
		return nil
	end
	local info = SC_TACTICAL_NO_TARGET_THIS_TURN[unitKey]
	if info == nil then
		return nil
	end
	local currentPlotIndex = SC_GetUnitPlotIndexForTacticalCache(unit)
	if currentPlotIndex ~= nil and info.plotIndex ~= nil and currentPlotIndex ~= info.plotIndex then
		SC_TACTICAL_NO_TARGET_THIS_TURN[unitKey] = nil
		return nil
	end
	return info
end

function SC_RecordTacticalNoTarget(unit, unitKey, role, stats, reason)
	if unitKey == nil or stats == nil then
		return
	end
	if (stats.inRangeUnits or 0) > 0 or (stats.inRangeCities or 0) > 0 then
		SC_TACTICAL_NO_TARGET_THIS_TURN[unitKey] = nil
		return
	end
	SC_TACTICAL_NO_TARGET_THIS_TURN[unitKey] = {
		plotIndex = SC_GetUnitPlotIndexForTacticalCache(unit),
		role = role,
		enemyUnits = stats.enemyUnits or 0,
		enemyCities = stats.enemyCities or 0,
		outOfRange = stats.outOfRange or 0,
		reason = reason or "no-in-range-target"
	}
end

function SC_FormatTacticalQueuedCache(info)
	if info == nil then
		return "queue=nil"
	end
	return "queuedPlot="..tostring(info.plotIndex or "nil")..
		" target="..tostring(info.targetKey or "nil")..
		" role="..tostring(info.role or "nil")..
		" status="..tostring(info.status or "nil")..
		" reason="..tostring(info.reason or "nil")
end

function SC_GetValidTacticalQueuedCache(unit, unitKey)
	if unitKey == nil then
		return nil
	end
	local info = SC_TACTICAL_QUEUED_THIS_TURN[unitKey]
	if info == nil then
		return nil
	end
	if SC_UnitNeedsOrder ~= nil and SC_UnitNeedsOrder(unit) then
		SC_TACTICAL_QUEUED_THIS_TURN[unitKey] = nil
		return nil
	end
	local currentPlotIndex = SC_GetUnitPlotIndexForTacticalCache(unit)
	if currentPlotIndex ~= nil and info.plotIndex ~= nil and currentPlotIndex ~= info.plotIndex then
		SC_TACTICAL_QUEUED_THIS_TURN[unitKey] = nil
		return nil
	end
	return info
end

function SC_RecordTacticalQueued(unit, unitKey, role, targetPlot, status, reason)
	if unitKey == nil then
		return
	end
	local targetKey = "nil"
	if targetPlot ~= nil then
		targetKey = tostring(targetPlot:GetX())..","..tostring(targetPlot:GetY())
	end
	SC_TACTICAL_QUEUED_THIS_TURN[unitKey] = {
		plotIndex = SC_GetUnitPlotIndexForTacticalCache(unit),
		targetKey = targetKey,
		role = role,
		status = status or "queued",
		reason = reason or "pending-resolution"
	}
end

function SC_IsStrikeStatusFired(status)
	return status == "fired" or status == "direct-fired" or status == "native-fired"
end

function SC_IsStrikeStatusQueued(status)
	return status == "queued" or status == "direct-queued" or status == "native-queued"
end

function SC_GetEraRank(eraType)
	local ranks = {
		ERA_ANCIENT = 0,
		ERA_CLASSICAL = 1,
		ERA_MEDIEVAL = 2,
		ERA_RENAISSANCE = 3,
		ERA_INDUSTRIAL = 4,
		ERA_MODERN = 5,
		ERA_WORLDWAR = 6,
		ERA_POSTMODERN = 7,
		ERA_INFORMATION = 8,
		ERA_FUTURE = 9
	}
	return ranks[eraType or ""] or -1
end

function SC_GetPlayerEraRankForCity(city)
	if city == nil then
		return -1
	end
	local ownerID = SC_GetSafeNumber(function() return city:GetOwner() end, -1)
	local player = Players[ownerID]
	if player == nil then
		return -1
	end
	local eraID = SC_GetSafeNumber(function() return player:GetCurrentEra() end, -1)
	local eraType = nil
	if GameInfo ~= nil and GameInfo.Eras ~= nil and eraID ~= nil and eraID >= 0 then
		local eraInfo = GameInfo.Eras[eraID]
		if eraInfo == nil then
			for row in GameInfo.Eras() do
				if row.ID == eraID then
					eraInfo = row
					break
				end
			end
		end
		if eraInfo ~= nil then
			eraType = eraInfo.Type
		end
	end
	return SC_GetEraRank(eraType)
end

function SC_GetUnitEraRank(unitInfo)
	if unitInfo == nil then
		return -1
	end
	local techType = unitInfo.PrereqTech
	if techType ~= nil and techType ~= "" and GameInfo ~= nil and GameInfo.Technologies ~= nil then
		local techInfo = GameInfo.Technologies[techType]
		if techInfo ~= nil then
			return SC_GetEraRank(techInfo.Era)
		end
	end
	return -1
end

function SC_GetUnitPowerScore(unitInfo)
	if unitInfo == nil then
		return 0
	end
	return math.max(unitInfo.Combat or 0, unitInfo.RangedCombat or 0)
end

function SC_GetOutdatedUnitRejectReason(unitInfo, playerEraRank)
	if not SC_GetConfig("AvoidObsoleteFallbackUnits", true) then
		return nil
	end
	if unitInfo == nil then
		return "missing-info"
	end
	local power = SC_GetUnitPowerScore(unitInfo)
	local unitEraRank = SC_GetUnitEraRank(unitInfo)
	local maxGap = SC_GetConfig("MaxFallbackUnitEraGap", 2)
	if playerEraRank >= 0 and unitEraRank >= 0 and (playerEraRank - unitEraRank) > maxGap then
		return "era-gap:"..tostring(playerEraRank - unitEraRank)
	end
	if playerEraRank >= SC_GetEraRank("ERA_MODERN") and power > 0 and power < SC_GetConfig("MinLateGameFallbackCombatPower", 45) then
		return "low-power:"..tostring(power)
	end
	return nil
end

function SC_PlayerHasTechType(player, techType)
	if player == nil or techType == nil or techType == "" then
		return false
	end
	local techID = SC_GetID(techType)
	local team = Teams[SC_GetSafeNumber(function() return player:GetTeam() end, -1)]
	if team == nil or techID == nil or techID < 0 then
		return false
	end
	return SC_GetSafeNumber(function() return team:IsHasTech(techID) and 1 or 0 end, 0) > 0
end

function SC_IsEliteUnitInfo(unitInfo)
	if unitInfo == nil or not SC_GetConfig("AutoElitePrograms", true) then
		return false
	end
	if unitInfo.Type == "UNIT_MECH" and not SC_GetConfig("AllowMechEliteProduction", false) then
		return false
	end
	if SC_GetUnitPowerScore(unitInfo) <= 0 or SC_DBNumber(unitInfo.NukeDamageLevel, 0) > 0 then
		return false
	end
	local projectType = unitInfo.ProjectPrereq
	if projectType == nil or projectType == "" or GameInfo == nil or GameInfo.Projects == nil then
		return false
	end
	local projectInfo = GameInfo.Projects[projectType]
	return projectInfo ~= nil and SC_DBNumber(projectInfo.MaxGlobalInstances, -1) == 1
end

function SC_GetEliteProjectUnits(projectType)
	if projectType == nil or projectType == "" then
		return {}
	end
	if SC_ELITE_PROJECT_UNIT_CACHE[projectType] ~= nil then
		return SC_ELITE_PROJECT_UNIT_CACHE[projectType]
	end
	local units = {}
	if GameInfo ~= nil and GameInfo.Units ~= nil then
		for unitInfo in GameInfo.Units() do
			if unitInfo.ProjectPrereq == projectType and SC_IsEliteUnitInfo(unitInfo) then
				table.insert(units, unitInfo)
			end
		end
	end
	SC_ELITE_PROJECT_UNIT_CACHE[projectType] = units
	return units
end

function SC_IsEliteUnitEraRelevant(playerEraRank, unitInfo, player)
	if unitInfo == nil then
		return false, "missing-unit"
	end
	if unitInfo.ObsoleteTech ~= nil and unitInfo.ObsoleteTech ~= "" and SC_PlayerHasTechType(player, unitInfo.ObsoleteTech) then
		return false, "obsolete-tech"
	end
	local unitEraRank = SC_GetUnitEraRank(unitInfo)
	if playerEraRank >= 0 and unitEraRank >= 0 and playerEraRank - unitEraRank > SC_GetConfig("MaxEliteEraLag", 2) then
		return false, "era-lag:"..tostring(playerEraRank - unitEraRank)
	end
	return true, "relevant"
end

function SC_GetEliteUnitStrategicScore(unitInfo, playerEraRank, atWar)
	if unitInfo == nil then
		return -999999
	end
	local power = SC_GetUnitPowerScore(unitInfo)
	local unitEraRank = SC_GetUnitEraRank(unitInfo)
	local score = power * 5 + SC_DBNumber(unitInfo.RangedCombat, 0) * 1.5
		+ SC_DBNumber(unitInfo.Range, 0) * 45 + SC_DBNumber(unitInfo.Moves, 0) * 12
		+ math.max(SC_DBNumber(unitInfo.Cost, 0), 0) / 8 + math.max(unitEraRank, 0) * 80
	if playerEraRank >= 0 and unitEraRank >= playerEraRank then
		score = score + 300
	end
	if atWar then
		score = score + SC_GetConfig("EliteProjectScoreBonusAtWar", 700)
	end
	return score
end

function SC_CountPlayerUnitType(player, unitID)
	if player == nil or unitID == nil then
		return 0
	end
	local count = 0
	for unit in player:Units() do
		if unit ~= nil and not unit:IsDead() and SC_GetSafeNumber(function() return unit:GetUnitType() end, -1) == unitID then
			count = count + 1
		end
	end
	return count
end

function SC_GetBestTrainableEliteUnit(player, city, atWar, reservedOrders)
	if player == nil or city == nil or not SC_GetConfig("AutoElitePrograms", true) then
		return nil, -999999, 0, "disabled"
	end
	local playerEraRank = SC_GetPlayerEraRankForCity(city)
	local bestUnitID = nil
	local bestScore = -999999
	local bestReason = "none"
	local candidates = 0
	local excluded = {}
	for unitInfo in GameInfo.Units() do
		if SC_IsEliteUnitInfo(unitInfo) and SC_CityCanTrain(city, unitInfo.ID) then
			local relevant, relevanceReason = SC_IsEliteUnitEraRelevant(playerEraRank, unitInfo, player)
			local queued = reservedOrders ~= nil and SC_DBNumber(reservedOrders["ELITE_UNIT:"..tostring(unitInfo.ID)], 0) or 0
			local existing = SC_CountPlayerUnitType(player, unitInfo.ID)
			local investment, investmentReason = 1, "legacy"
			if SC5 then investment, investmentReason = SC5.ElitePlanValue(player, city, unitInfo, reservedOrders, false) end
			if not investment then excluded[investmentReason] = (excluded[investmentReason] or 0) + 1 end
			if relevant and investment and existing + queued < SC_GetConfig("EliteUnitTargetPerType", 1) then
				candidates = candidates + 1
				local score = (SC_GetEliteUnitStrategicScore(unitInfo, playerEraRank, atWar) + SC_GetConfig("EliteUnitScoreBonus", 1800)) * investment
				if score > bestScore then
					bestScore = score
					bestUnitID = unitInfo.ID
					bestReason = "project="..tostring(unitInfo.ProjectPrereq).." existing="..tostring(existing).." queued="..tostring(queued).." relevance="..relevanceReason.." investment="..investmentReason
				end
			end
		end
	end
	if SC5 and next(excluded) then SC_Debug("decision5 elite-filter city="..city:GetID().." excluded="..SC5.FactText(excluded)) end
	return bestUnitID, bestScore, candidates, bestReason
end

function SC_GetMilitaryRosterSnapshot(player)
	local snapshot = {
		rapidCapture = 0,
		lineFrontline = 0,
		siege = 0,
		airSuperiority = 0,
		carrierAir = 0,
		airStrike = 0,
		navalScreen = 0,
		navalFire = 0,
		fleetCarrier = 0,
		strategicSubmarine = 0,
		missileStrike = 0,
		useful = 0,
		coastalCities = 0
	}
	if player == nil then
		return snapshot
	end
	local cacheKey = tostring(SC_GetSafeNumber(function() return player:GetID() end, 0))
	if SC_MILITARY_ROSTER_CACHE_THIS_TURN[cacheKey] ~= nil then
		return SC_MILITARY_ROSTER_CACHE_THIS_TURN[cacheKey]
	end
	for city in player:Cities() do
		local coastal = false
		pcall(function() coastal = city:IsCoastal() end)
		if coastal then
			snapshot.coastalCities = snapshot.coastalCities + 1
		end
	end
	for unit in player:Units() do
		if unit ~= nil and not unit:IsDead() then
			local unitInfo = SC_GetUnitInfo(unit)
			if unitInfo ~= nil then
				local role = SC_GetUnitRole(unit, unitInfo)
				local profile = SC_GetUnitCapabilityProfile(unit, unitInfo, role)
				local class = profile.doctrineClass
				if class == "missile_strike" then
					snapshot.missileStrike = snapshot.missileStrike + 1
				elseif (profile.power or 0) > 0 then
					snapshot.useful = snapshot.useful + 1
					if class == "air_superiority" then
						snapshot.airSuperiority = snapshot.airSuperiority + 1
					elseif class == "carrier_multirole" then
						snapshot.carrierAir = snapshot.carrierAir + 1
					elseif class == "strike_aircraft" then
						snapshot.airStrike = snapshot.airStrike + 1
					elseif class == "fleet_carrier" then
						snapshot.fleetCarrier = snapshot.fleetCarrier + 1
					elseif class == "ballistic_submarine" then
						snapshot.strategicSubmarine = snapshot.strategicSubmarine + 1
					elseif class == "surface_fire_support" or class == "arsenal_capital" then
						snapshot.navalFire = snapshot.navalFire + 1
					elseif profile.domain == "DOMAIN_SEA" and (SC_IsScreenDoctrineClass(class) or class == "attack_submarine" or class == "naval_assault") then
						snapshot.navalScreen = snapshot.navalScreen + 1
					elseif class == "siege_artillery" or class == "ranged_support" then
						snapshot.siege = snapshot.siege + 1
					elseif profile.canCapture then
						if class == "mobile_breakthrough" or class == "gunship" or class == "airborne_raider" or class == "super_heavy" or class == "recon_raider" then
							snapshot.rapidCapture = snapshot.rapidCapture + 1
						else
							snapshot.lineFrontline = snapshot.lineFrontline + 1
						end
					end
				end
			end
		end
	end
	SC_MILITARY_ROSTER_CACHE_THIS_TURN[cacheKey] = snapshot
	return snapshot
end

function SC_GetStrikePackageTargets(player, snapshot)
	local cityCount = math.max(SC_GetSafeNumber(function() return player:GetNumCities() end, 1), 1)
	local packageCount = math.max(2, math.min(SC_GetConfig("MaxStrikePackages", 6), math.ceil(math.sqrt(cityCount))))
	local hasCoast = snapshot ~= nil and snapshot.coastalCities > 0
	local carrierTarget = hasCoast and math.max(1, math.ceil(packageCount / 3)) or 0
	return {
		rapid_capture = math.max(2, math.ceil(packageCount * 0.8)),
		line_frontline = math.max(2, packageCount),
		siege = math.max(2, math.ceil(packageCount * 0.8)),
		air_superiority = math.max(2, math.ceil(packageCount * 0.6)),
		carrier_air = hasCoast and math.max(2, carrierTarget * 2) or 0,
		air_strike = math.max(2, packageCount),
		naval_screen = hasCoast and math.max(2, packageCount) or 0,
		naval_fire = hasCoast and math.max(1, math.ceil(packageCount * 0.8)) or 0,
		fleet_carrier = carrierTarget,
		strategic_submarine = hasCoast and math.max(1, math.ceil(packageCount / 3)) or 0,
		missile_strike = math.max(2, packageCount),
		packageCount = packageCount
	}
end

function SC_GetProductionNeedForUnitInfo(unitInfo)
	if unitInfo == nil then
		return nil
	end
	local role = SC_GetUnitRole(nil, unitInfo)
	local profile = SC_GetUnitCapabilityProfile(nil, unitInfo, role)
	local class = profile.doctrineClass
	if class == "missile_strike" then
		return "missile_strike"
	elseif class == "air_superiority" then
		return "air_superiority"
	elseif class == "carrier_multirole" then
		return "carrier_air"
	elseif class == "strike_aircraft" then
		return "air_strike"
	elseif class == "fleet_carrier" then
		return "fleet_carrier"
	elseif class == "ballistic_submarine" then
		return "strategic_submarine"
	elseif class == "surface_fire_support" or class == "arsenal_capital" then
		return "naval_fire"
	elseif profile.domain == "DOMAIN_SEA" and (SC_IsScreenDoctrineClass(class) or class == "attack_submarine" or class == "naval_assault") then
		return "naval_screen"
	elseif class == "siege_artillery" or class == "ranged_support" then
		return "siege"
	elseif profile.canCapture and (class == "mobile_breakthrough" or class == "gunship" or class == "airborne_raider" or class == "super_heavy" or class == "recon_raider") then
		return "rapid_capture"
	elseif profile.domain == "DOMAIN_LAND" and profile.canCapture then
		return "line_frontline"
	end
	return nil
end

function SC_GetProductionNeedDomain(needKey)
	if needKey == "air_superiority" or needKey == "carrier_air" or needKey == "air_strike" or needKey == "missile_strike" then
		return "air"
	end
	if needKey == "naval_screen" or needKey == "naval_fire" or needKey == "fleet_carrier" or needKey == "strategic_submarine" then
		return "sea"
	end
	return "land"
end

function SC_GetMilitaryProductionNeed(player, city, atWar, reservedOrders, excludedNeeds)
	if player == nil or not atWar then
		return nil, 0, "peace"
	end
	if SC_StrategyGetMilitaryNeed ~= nil then
		local strategyNeed, strategyDeficit, strategyDebug = SC_StrategyGetMilitaryNeed(player, city, atWar, reservedOrders, excludedNeeds)
		return strategyNeed, strategyDeficit, strategyDebug
	end
	local snapshot = SC_GetMilitaryRosterSnapshot(player)
	local targets = SC_GetStrikePackageTargets(player, snapshot)
	local current = {
		rapid_capture = snapshot.rapidCapture,
		line_frontline = snapshot.lineFrontline + snapshot.rapidCapture,
		siege = snapshot.siege,
		air_superiority = snapshot.airSuperiority,
		carrier_air = snapshot.carrierAir,
		air_strike = snapshot.airStrike,
		naval_screen = snapshot.navalScreen,
		naval_fire = snapshot.navalFire,
		fleet_carrier = snapshot.fleetCarrier,
		strategic_submarine = snapshot.strategicSubmarine,
		missile_strike = snapshot.missileStrike
	}
	local priority = {
		rapid_capture = 82, line_frontline = 48, siege = 78,
		air_superiority = 92, carrier_air = 100, air_strike = 98,
		naval_screen = 70, naval_fire = 86, fleet_carrier = 82,
		strategic_submarine = 74, missile_strike = 64
	}
	local warProfile = SC_GetConfig("WarProfile", "ADVANCE")
	local production = SC_GetConfig("ProductionProfile", "BUILDINGS")
	if warProfile == "NAVAL" or production == "AIRSEA" then
		priority.naval_screen = 108
		priority.naval_fire = 112
		priority.fleet_carrier = 106
		priority.strategic_submarine = 98
		priority.air_superiority = 102
		priority.carrier_air = 108
		priority.air_strike = 104
	elseif warProfile == "ASSAULT" then
		priority.rapid_capture = 105
		priority.siege = 98
		priority.air_strike = 104
	elseif warProfile == "DEFENSE" then
		priority.line_frontline = 100
		priority.air_superiority = 106
		priority.naval_screen = 90
	end
	local cityCoastal = false
	pcall(function() cityCoastal = city ~= nil and city:IsCoastal() end)
	local bestNeed = nil
	local bestDeficit = 0
	local bestScore = -999999
	local scoreParts = {}
	local needs = {"rapid_capture", "line_frontline", "siege", "air_superiority", "carrier_air", "air_strike", "naval_screen", "naval_fire", "fleet_carrier", "strategic_submarine", "missile_strike"}
	for _, need in ipairs(needs) do
		local queued = reservedOrders ~= nil and SC_DBNumber(reservedOrders["NEED:"..need], 0) or 0
		if need == "line_frontline" and reservedOrders ~= nil then queued = queued + SC_DBNumber(reservedOrders["NEED:rapid_capture"], 0) end
		local deficit = targets[need] - current[need] - queued
		local domainAllowed = SC_GetProductionNeedDomain(need) ~= "sea" or cityCoastal
		local excluded = excludedNeeds ~= nil and excludedNeeds[need]
		local score = priority[need] + deficit * 100 / math.max(targets[need], 1)
		if current[need] + queued <= 0 and targets[need] > 0 then
			score = score + SC_GetConfig("MissingStrikeArmBonus", 45)
		end
		table.insert(scoreParts, need..":"..tostring(current[need]).."+"..tostring(queued).."/"..tostring(targets[need]).."@"..tostring(math.floor(score)))
		if deficit > 0 and domainAllowed and not excluded then
			if score > bestScore then
				bestScore = score
				bestNeed = need
				bestDeficit = deficit
			end
		end
	end
	local debugText = "packages="..tostring(targets.packageCount).." choice="..tostring(bestNeed).." score="..tostring(math.floor(bestScore)).." arms="..table.concat(scoreParts, ",").." useful="..tostring(snapshot.useful)
	return bestNeed, bestDeficit, debugText
end

function SC_UnitMatchesProductionNeed(unitInfo, needKey)
	if unitInfo == nil or needKey == nil or needKey == "balanced" then
		return true
	end
	local role = SC_GetUnitRole(nil, unitInfo)
	local profile = SC_GetUnitCapabilityProfile(nil, unitInfo, role)
	local class = profile.doctrineClass
	return SC_GetProductionNeedForUnitInfo(unitInfo) == needKey
end

function SC_GetStrikePackageReadiness(player)
	local snapshot = SC_GetMilitaryRosterSnapshot(player)
	local targets = SC_GetStrikePackageTargets(player, snapshot)
	local current = {
		rapid_capture = snapshot.rapidCapture,
		siege = snapshot.siege,
		air_superiority = snapshot.airSuperiority,
		carrier_air = snapshot.carrierAir,
		air_strike = snapshot.airStrike,
		naval_screen = snapshot.navalScreen,
		naval_fire = snapshot.navalFire,
		fleet_carrier = snapshot.fleetCarrier,
		strategic_submarine = snapshot.strategicSubmarine
	}
	local weights = {
		rapid_capture = 1.2, siege = 1.0,
		air_superiority = 0.8, carrier_air = 0.8, air_strike = 1.2,
		naval_screen = 0.7, naval_fire = 0.9, fleet_carrier = 0.6,
		strategic_submarine = 0.4
	}
	local totalWeight = 0
	local readyWeight = 0
	local parts = {}
	for _, need in ipairs({"rapid_capture", "siege", "air_superiority", "carrier_air", "air_strike", "naval_screen", "naval_fire", "fleet_carrier", "strategic_submarine"}) do
		local target = targets[need] or 0
		if target > 0 then
			local weight = weights[need] or 1
			local ratio = math.min((current[need] or 0) / target, 1)
			totalWeight = totalWeight + weight
			readyWeight = readyWeight + ratio * weight
			table.insert(parts, need..":"..tostring(current[need] or 0).."/"..tostring(target))
		end
	end
	local readiness = totalWeight > 0 and readyWeight / totalWeight or 0
	return readiness, "packages="..tostring(targets.packageCount).." readiness="..tostring(math.floor(readiness * 100)).."% "..table.concat(parts, ",")
end

function SC_GetNearestFriendlyCaptureDistance(player, targetPlot)
	if player == nil or targetPlot == nil then
		return 9999
	end
	local bestDistance = 9999
	for unit in player:Units() do
		if unit ~= nil and not unit:IsDead() then
			local unitInfo = SC_GetUnitInfo(unit)
			local role = SC_GetUnitRole(unit, unitInfo)
			local domainEligible = unitInfo ~= nil and (unitInfo.Domain ~= "DOMAIN_SEA" or SC_IsCoastalAssaultPlot(targetPlot))
			if domainEligible and SC_IsDedicatedCityCaptureUnit(unit, unitInfo, role) then
				local unitPlot = unit:GetPlot()
				if unitPlot ~= nil then
					local distance = Map.PlotDistance(unitPlot:GetX(), unitPlot:GetY(), targetPlot:GetX(), targetPlot:GetY())
					if distance < bestDistance then
						bestDistance = distance
					end
				end
			end
		end
	end
	return bestDistance
end

function SC_GetDecapitationFocusPlot(player)
	if player == nil then
		return nil, 0, "player=nil"
	end
	local playerID = SC_GetSafeNumber(function() return player:GetID() end, -1)
	local cacheKey = tostring(playerID)
	local cached = SC_DECAPITATION_FOCUS_THIS_TURN[cacheKey]
	if cached ~= nil then
		return cached.plot, cached.readiness, cached.debugText
	end
	local readiness, readinessDebug = SC_GetStrikePackageReadiness(player)
	local team = Teams[player:GetTeam()]
	local anchorPlot = nil
	pcall(function()
		local capital = player:GetCapitalCity()
		if capital ~= nil then anchorPlot = capital:Plot() end
	end)
	if anchorPlot == nil then
		for city in player:Cities() do
			anchorPlot = city:Plot()
			break
		end
	end
	local bestPlot = nil
	local bestScore = -999999
	local bestReason = "none"
	if team ~= nil then
		for _, otherPlayer in pairs(Players) do
			if otherPlayer ~= nil and otherPlayer:IsAlive() and otherPlayer:GetID() ~= playerID and team:IsAtWar(otherPlayer:GetTeam()) then
				for city in otherPlayer:Cities() do
					local cityPlot = city:Plot()
					if cityPlot ~= nil then
						local captureDistance = SC_GetNearestFriendlyCaptureDistance(player, cityPlot)
						local stagingDistance = SC_GetConfig("DecapitationCaptureStagingDistance", 10)
						if captureDistance <= stagingDistance then
							local distance = 0
							if anchorPlot ~= nil then
								distance = Map.PlotDistance(anchorPlot:GetX(), anchorPlot:GetY(), cityPlot:GetX(), cityPlot:GetY())
							end
							local damage, maxHP, damageRatio = SC_GetCityDamageInfo(city)
							local score = 1800 - distance * 9 - captureDistance * 45 + damage * 4
							local capital = SC_GetSafeNumber(function() return city:IsCapital() and 1 or 0 end, 0) > 0
							if capital then score = score + SC_GetConfig("DecapitationCapitalBonus", 900) end
							if damageRatio >= 0.72 then score = score + 650 elseif damageRatio >= 0.45 then score = score + 320 end
							if SC_IsCoastalAssaultPlot(cityPlot) then score = score + 120 end
							if score > bestScore then
								bestScore = score
								bestPlot = cityPlot
								bestReason = "capital="..SC_BoolText(capital).." anchorDist="..tostring(distance).." captureDist="..tostring(captureDistance).." damage="..tostring(damage).."/"..tostring(maxHP)
							end
						end
					end
				end
			end
		end
	end
	local debugText = readinessDebug.." target="..SC_GetPlotDebug(bestPlot).." score="..tostring(bestScore).." "..bestReason
	SC_DECAPITATION_FOCUS_THIS_TURN[cacheKey] = { plot = bestPlot, readiness = readiness, debugText = debugText }
	if bestPlot ~= nil then
		SC_Debug("strikePackage focus "..debugText)
	end
	return bestPlot, readiness, debugText
end

local function SC_GetBestTrainableUnit(city, preferSea, preferAir, reservedOrders, needKey)
	local bestUnitID = nil
	local bestScore = -1
	local bestRole = nil
	local candidateCount = 0
	local reservedCount = 0
	local rejectedOutdated = 0
	local playerEraRank = SC_GetPlayerEraRankForCity(city)
	local production = SC_GetConfig("ProductionProfile", "BUILDINGS")
	local war = SC_GetConfig("WarProfile", "ADVANCE")
	for unitInfo in GameInfo.Units() do
		local unitID = unitInfo.ID
		local reserveKey = "U:"..tostring(unitID)
		if SC_CityCanTrain(city, unitID) then
			local combat = unitInfo.Combat or 0
			local rangedCombat = unitInfo.RangedCombat or 0
			local cost = unitInfo.Cost or 0
			local domain = unitInfo.Domain
			local nukeDamage = unitInfo.NukeDamageLevel or 0
			if nukeDamage <= 0 and (combat > 0 or rangedCombat > 0) then
				if (preferAir and domain == "DOMAIN_AIR") or (preferSea and domain == "DOMAIN_SEA") or ((not preferSea) and (not preferAir) and domain == "DOMAIN_LAND") then
					local rejectReason = SC_GetOutdatedUnitRejectReason(unitInfo, playerEraRank)
					if rejectReason ~= nil then
						rejectedOutdated = rejectedOutdated + 1
					else
						candidateCount = candidateCount + 1
						local role = SC_GetUnitRole(nil, unitInfo)
						local tag = SC_GetUnitCombatTag(nil, unitInfo, role)
						local capability = SC_GetUnitCapabilityProfile(nil, unitInfo, role)
						local doctrineClass = capability.doctrineClass
						local unitType = unitInfo.Type or ""
						local unitEraRank = SC_GetUnitEraRank(unitInfo)
						local power = SC_GetUnitPowerScore(unitInfo)
						local score = power * 2.2 + rangedCombat * 0.7 + math.max(cost, 0) / 10 + (unitInfo.Range or 0) * 18 + (unitInfo.Moves or 0) * 5 + math.max(unitEraRank, 0) * 35
						if needKey ~= nil then
							if SC_UnitMatchesProductionNeed(unitInfo, needKey) then
								score = score + SC_GetConfig("MilitaryNeedScoreBonus", 1200)
							else
								score = -999999
							end
						end
						if SC_StrategyScoreUnit ~= nil then
							score = SC_StrategyScoreUnit(nil, city, unitInfo, needKey, score)
						end
						local repeated = reservedOrders ~= nil and SC_DBNumber(reservedOrders[reserveKey], 0) or 0
						if repeated > 0 then
							reservedCount = reservedCount + repeated
							score = score - repeated * SC_GetConfig("RepeatedUnitReservationPenalty", 220)
							if repeated >= SC_GetConfig("ProductionRepeatedTypeHardCap", 4) then score = -999999 end
						end
						if playerEraRank >= 0 and unitEraRank >= playerEraRank - 1 then
							score = score + 90
						end
						if production == "AIRSEA" or war == "NAVAL" then
							if tag == "arsenal_ship" then
								score = score + 380
							elseif tag == "missile_screen" then
								score = score + 340
							elseif tag == "fleet_flagship" then
								score = score + 260
							elseif tag == "sub_hunter" then
								score = score + 230
							elseif tag == "air_wing" or tag == "missile_strike" then
								score = score + 220
							end
							if doctrineClass == "ballistic_submarine" then
								score = score + 180
							elseif doctrineClass == "attack_submarine" then
								score = score + 240
							elseif doctrineClass == "air_defense_screen" or doctrineClass == "escort_screen" then
								score = score + 300
							elseif doctrineClass == "carrier_multirole" or doctrineClass == "air_superiority" then
								score = score + 260
							end
							if SC_TextHas(unitType, "052D") or SC_TextHas(unitType, "KIROV") or SC_TextHas(unitType, "MISSILE_CRUISER") then
								score = score + 170
							end
							if SC_TextHas(unitType, "FUTURE_BATTLESHIP") or SC_TextHas(unitType, "SUPER_CARRIER") or SC_TextHas(unitType, "CARRIER_FIGHTER") then
								score = score + 150
							end
						elseif production == "MILITARY" or war == "ASSAULT" then
							if tag == "fast_breakthrough" then
								score = score + 250
							elseif tag == "siege_artillery" then
								score = score + 230
							elseif tag == "fire_support" then
								score = score + 170
							elseif tag == "line_assault" or tag == "super_heavy" then
								score = score + 110
							end
							if doctrineClass == "mobile_air_defense" or doctrineClass == "counter_defender" then
								score = score + 180
							elseif doctrineClass == "airborne_raider" or doctrineClass == "gunship" then
								score = score + 220
							elseif doctrineClass == "siege_artillery" then
								score = score + 160
							end
							if SC_TextHas(unitType, "MODERN_ARMOR") or SC_TextHas(unitType, "APACHE") or SC_TextHas(unitType, "ROCKET_ARTILLERY") or SC_TextHas(unitType, "CRUSADER_ARTILLERY") then
								score = score + 140
							end
						elseif war == "DEFENSE" then
							if role == "land_ranged" or role == "siege" or role == "fighter" or tag == "missile_screen" then
								score = score + 150
							end
						end
						if score > bestScore then
							bestScore = score
							bestUnitID = unitID
							bestRole = role
						end
					end
				end
			end
		end
	end
	return bestUnitID, bestScore, candidateCount, bestRole, reservedCount, rejectedOutdated, playerEraRank
end

function SC_GetMilitaryNeedCounts(snapshot)
	return {
		rapid_capture = snapshot.rapidCapture,
		line_frontline = snapshot.lineFrontline + snapshot.rapidCapture,
		siege = snapshot.siege,
		air_superiority = snapshot.airSuperiority,
		carrier_air = snapshot.carrierAir,
		air_strike = snapshot.airStrike,
		naval_screen = snapshot.navalScreen,
		naval_fire = snapshot.navalFire,
		fleet_carrier = snapshot.fleetCarrier,
		strategic_submarine = snapshot.strategicSubmarine,
		missile_strike = snapshot.missileStrike
	}
end

function SC_GetMilitaryPurchaseNeed(player, city, reservations, excludedNeeds)
	if SC_StrategyGetMilitaryNeed ~= nil then
		local mapped = {}
		for need, count in pairs(reservations or {}) do mapped["NEED:"..tostring(need)] = count end
		local strategyNeed, strategyDeficit, strategyDebug = SC_StrategyGetMilitaryNeed(player, city, true, mapped, excludedNeeds)
		if strategyNeed ~= nil then
			return strategyNeed, 1000 + strategyDeficit * 100, strategyDeficit, strategyDebug
		end
		return nil, 0, 0, strategyDebug
	end
	local snapshot = SC_GetMilitaryRosterSnapshot(player)
	local baseTargets = SC_GetStrikePackageTargets(player, snapshot)
	local current = SC_GetMilitaryNeedCounts(snapshot)
	local multiplier = math.max(SC_GetConfig("MilitaryPurchaseForceMultiplier", 2.0), 1)
	local priority = {
		rapid_capture = 145, line_frontline = 115, siege = 60,
		air_superiority = 95, carrier_air = 88, air_strike = 120,
		naval_screen = 100, naval_fire = 115, fleet_carrier = 72,
		strategic_submarine = 82, missile_strike = 45
	}
	local warProfile = SC_GetConfig("WarProfile", "ADVANCE")
	if warProfile == "NAVAL" then
		priority.naval_screen = 135
		priority.naval_fire = 145
		priority.fleet_carrier = 110
		priority.carrier_air = 115
	elseif warProfile == "ASSAULT" then
		priority.rapid_capture = 165
		priority.air_strike = 140
	elseif warProfile == "DEFENSE" then
		priority.line_frontline = 150
		priority.air_superiority = 135
	end
	local cityCoastal = false
	pcall(function() cityCoastal = city:IsCoastal() end)
	local bestNeed = nil
	local bestScore = -999999
	local bestDeficit = 0
	local parts = {}
	local needs = {"rapid_capture", "line_frontline", "siege", "air_superiority", "carrier_air", "air_strike", "naval_screen", "naval_fire", "fleet_carrier", "strategic_submarine", "missile_strike"}
	for _, need in ipairs(needs) do
		local target = math.ceil((baseTargets[need] or 0) * multiplier)
		local ownReserved = reservations ~= nil and SC_DBNumber(reservations[need], 0) or 0
		local effectiveReserved = ownReserved
		if need == "line_frontline" and reservations ~= nil then effectiveReserved = effectiveReserved + SC_DBNumber(reservations.rapid_capture, 0) end
		local available = (current[need] or 0) + effectiveReserved
		local deficit = target - available
		local domainAllowed = SC_GetProductionNeedDomain(need) ~= "sea" or cityCoastal
		local ratio = target > 0 and available / target or 99
		local score = (priority[need] or 0) + math.max(0, 1 - ratio) * 220
		score = score - ownReserved * SC_GetConfig("MilitaryPurchaseRepeatedNeedPenalty", 100)
		if available <= 0 and target > 0 then score = score + SC_GetConfig("MissingStrikeArmBonus", 45) end
		if need == "rapid_capture" and snapshot.siege >= math.max(snapshot.rapidCapture * 2, 4) then score = score + 90 end
		table.insert(parts, need..":"..tostring(available).."/"..tostring(target).."@"..tostring(math.floor(score)))
		if deficit > 0 and domainAllowed and not (excludedNeeds ~= nil and excludedNeeds[need]) and score > bestScore then
			bestNeed = need
			bestScore = score
			bestDeficit = deficit
		end
	end
	return bestNeed, bestScore, bestDeficit, table.concat(parts, ",")
end

function SC_CityCanPurchaseUnitGold(city, unitID, requireAffordable)
	if city == nil or unitID == nil or YieldTypes == nil or YieldTypes.YIELD_GOLD == nil then return false end
	local canPurchase = false
	local ok = pcall(function()
		canPurchase = city:IsCanPurchase(requireAffordable == true, requireAffordable == true, unitID, -1, -1, YieldTypes.YIELD_GOLD)
	end)
	return ok and canPurchase
end

function SC_CountLivingPlayerUnits(player)
	local count = 0
	if player ~= nil then
		for unit in player:Units() do
			if unit ~= nil and not unit:IsDead() then count = count + 1 end
		end
	end
	return count
end

function SC_BuildMilitaryPurchaseCatalog(player, maximumBudget)
	local catalog = {}
	if player == nil then return catalog end
	for city in player:Cities() do
		local cityID = SC_GetSafeNumber(function() return city:GetID() end, -1)
		local byNeed = {}
		catalog[cityID] = byNeed
		if not city:IsPuppet() and not city:IsResistance() then
			local playerEraRank = SC_GetPlayerEraRankForCity(city)
			for unitInfo in GameInfo.Units() do
				local combat = SC_DBNumber(unitInfo.Combat, 0)
				local rangedCombat = SC_DBNumber(unitInfo.RangedCombat, 0)
				local need = SC_GetProductionNeedForUnitInfo(unitInfo)
				if need ~= nil and (combat > 0 or rangedCombat > 0) and SC_DBNumber(unitInfo.NukeDamageLevel, 0) <= 0
					and SC_GetOutdatedUnitRejectReason(unitInfo, playerEraRank) == nil
					and SC_CityCanPurchaseUnitGold(city, unitInfo.ID, false) then
					local cost = SC_GetSafeNumber(function() return city:GetUnitPurchaseCost(unitInfo.ID) end, -1)
					if cost > 0 and cost <= maximumBudget and SC_CityCanPurchaseUnitGold(city, unitInfo.ID, true) then
						byNeed[need] = byNeed[need] or {}
						table.insert(byNeed[need], { info = unitInfo, cost = cost, era = SC_GetUnitEraRank(unitInfo) })
					end
				end
			end
		end
	end
	return catalog
end

function SC_GetBestPurchasableMilitaryUnit(city, needKey, budgetLeft, purchaseOrders, purchaseCatalog)
	local bestUnitID = nil
	local bestScore = -999999
	local bestCost = 0
	local candidateCount = 0
	local rejectedBudget = 0
	local playerEraRank = SC_GetPlayerEraRankForCity(city)
	local source = nil
	if purchaseCatalog ~= nil then
		local cityID = SC_GetSafeNumber(function() return city:GetID() end, -1)
		source = purchaseCatalog[cityID] ~= nil and purchaseCatalog[cityID][needKey] or {}
	end
	local candidates = source or {}
	if source == nil then
		for unitInfo in GameInfo.Units() do
			if SC_UnitMatchesProductionNeed(unitInfo, needKey) then
				table.insert(candidates, { info = unitInfo, cost = SC_GetSafeNumber(function() return city:GetUnitPurchaseCost(unitInfo.ID) end, -1), era = SC_GetUnitEraRank(unitInfo) })
			end
		end
	end
	for _, candidate in ipairs(candidates) do
		local unitInfo = candidate.info
		local combat = SC_DBNumber(unitInfo.Combat, 0)
		local rangedCombat = SC_DBNumber(unitInfo.RangedCombat, 0)
		if (combat > 0 or rangedCombat > 0) and SC_DBNumber(unitInfo.NukeDamageLevel, 0) <= 0 and SC_UnitMatchesProductionNeed(unitInfo, needKey) then
			local rejectReason = SC_GetOutdatedUnitRejectReason(unitInfo, playerEraRank)
			if rejectReason == nil and SC_CityCanPurchaseUnitGold(city, unitInfo.ID, false) then
				local cost = candidate.cost
				if cost > 0 and cost <= budgetLeft and SC_CityCanPurchaseUnitGold(city, unitInfo.ID, true) then
					candidateCount = candidateCount + 1
					local unitEraRank = candidate.era
					local power = SC_GetUnitPowerScore(unitInfo)
					local score = power * 2.5 + rangedCombat * 0.8 + SC_DBNumber(unitInfo.Range, 0) * 20 + SC_DBNumber(unitInfo.Moves, 0) * 6 + math.max(unitEraRank, 0) * 45
					if playerEraRank >= 0 and unitEraRank >= playerEraRank - 1 then score = score + 140 end
					if SC_IsEliteUnitInfo(unitInfo) then score = score + 260 end
					local repeated = purchaseOrders ~= nil and SC_DBNumber(purchaseOrders[unitInfo.Type or tostring(unitInfo.ID)], 0) or 0
					if repeated >= SC_GetConfig("MilitaryPurchaseRepeatedTypeHardCap", 2) then
						score = -999999
					else
						score = score - repeated * SC_GetConfig("MilitaryPurchaseRepeatedTypePenalty", 180)
					end
					score = score - cost / 80
					if score >= SC_GetConfig("MilitaryPurchaseMinimumQualityScore", 120) and score > bestScore then
						bestUnitID = unitInfo.ID
						bestScore = score
						bestCost = cost
					end
				elseif cost > budgetLeft then
					rejectedBudget = rejectedBudget + 1
				end
			end
		end
	end
	return bestUnitID, bestScore, bestCost, candidateCount, rejectedBudget
end

function SC_AutomateMilitaryPurchases(player, atWar)
	if player == nil or not SC_GetConfig("AutoPurchaseMilitary", true) then return 0 end
	if SC_GetConfig("MilitaryPurchaseAtWarOnly", false) and not atWar then return 0 end
	local playerID = SC_GetSafeNumber(function() return player:GetID() end, -1)
	local turn = SC_GetSafeNumber(function() return Game.GetGameTurn() end, -1)
	if SC_MILITARY_PURCHASED_TURN[playerID] == turn then return 0 end
	SC_MILITARY_PURCHASED_TURN[playerID] = turn
	local gold = SC_GetSafeNumber(function() return player:GetGold() end, 0)
	local goldRate = SC_GetSafeNumber(function() return player:CalculateGoldRate() end, 0)
	local cityCount = math.max(SC_GetSafeNumber(function() return player:GetNumCities() end, 1), 1)
	local reserve = math.max(
		SC_GetConfig("MilitaryPurchaseMinimumGold", 75000),
		cityCount * SC_GetConfig("MilitaryPurchaseReservePerCity", 2500),
		math.max(0, -goldRate) * SC_GetConfig("MilitaryPurchaseDeficitReserveTurns", 15)
	)
	local surplus = math.max(0, gold - reserve)
	local budget = math.floor(surplus * SC_GetConfig("MilitaryPurchaseBudgetFraction", 0.12))
	local strategyMaxPurchases = nil
	local strategyBudgetReason = "legacy"
	if SC_StrategyGetMilitaryPurchaseBudget ~= nil then
		local strategyReserve, strategyBudget, strategyMax, strategyReason = SC_StrategyGetMilitaryPurchaseBudget(player, atWar)
		if strategyReserve ~= nil then reserve = strategyReserve end
		if strategyBudget ~= nil then budget = strategyBudget end
		strategyMaxPurchases = strategyMax
		strategyBudgetReason = strategyReason or "national-plan"
	end
	if budget < SC_GetConfig("MilitaryPurchaseMinimumBudget", 1500) then
		SC_Debug("militaryPurchase skip reason=insufficient-surplus gold="..tostring(gold).." goldRate="..tostring(goldRate).." reserve="..tostring(reserve).." budget="..tostring(budget).." strategy="..tostring(strategyBudgetReason))
		return 0
	end
	local maxPurchases = math.min(
		SC_GetConfig("MilitaryPurchaseMaxPerTurn", 6),
		math.max(1, math.ceil(cityCount / math.max(SC_GetConfig("MilitaryPurchaseCitiesPerUnit", 6), 1)))
	)
	if strategyMaxPurchases ~= nil then maxPurchases = math.min(maxPurchases, math.max(strategyMaxPurchases, 0)) end
	local focusPlot = nil
	pcall(function() focusPlot = SC_GetDecapitationFocusPlot(player) end)
	local reservations = {}
	local purchaseOrders = {}
	local usedCities = {}
	local purchased = 0
	local spent = 0
	local purchaseCatalog = SC_BuildMilitaryPurchaseCatalog(player, budget)
	local catalogCities, catalogCandidates = 0, 0
	for _, byNeed in pairs(purchaseCatalog) do
		catalogCities = catalogCities + 1
		for _, candidates in pairs(byNeed) do catalogCandidates = catalogCandidates + #candidates end
	end
	SC_Debug("militaryPurchase begin gold="..tostring(gold).." goldRate="..tostring(goldRate).." reserve="..tostring(reserve).." budget="..tostring(budget).." max="..tostring(maxPurchases).." strategy="..tostring(strategyBudgetReason).." focus="..SC_GetPlotDebug(focusPlot).." catalogCities="..tostring(catalogCities).." catalogCandidates="..tostring(catalogCandidates))
	while purchased < maxPurchases and budget - spent >= SC_GetConfig("MilitaryPurchaseMinimumBudget", 1500) do
		local best = nil
		local needSummaries = {}
		for city in player:Cities() do
			local cityID = SC_GetSafeNumber(function() return city:GetID() end, -1)
			if not usedCities[cityID] and not city:IsPuppet() and not city:IsResistance() then
				local excludedNeeds = {}
				for needAttempt = 1, 11, 1 do
					local needKey, needScore, deficit, needDebug = SC_GetMilitaryPurchaseNeed(player, city, reservations, excludedNeeds)
					if needKey == nil then break end
					if SC_DBNumber(reservations[needKey], 0) >= SC_GetConfig("MilitaryPurchaseRepeatedNeedHardCap", 3) then
						excludedNeeds[needKey] = true
					else
					local unitID, unitScore, cost, candidates, rejectedBudget = SC_GetBestPurchasableMilitaryUnit(city, needKey, budget - spent, purchaseOrders, purchaseCatalog)
					if #needSummaries < 8 then table.insert(needSummaries, tostring(city:GetName()).."="..tostring(needKey)..":"..tostring(math.floor(needScore)).." candidates="..tostring(candidates).." budgetReject="..tostring(rejectedBudget)) end
					if unitID ~= nil then
						local cityScore = SC_GetSafeNumber(function() return city:GetPopulation() end, 1) * 3
						local cityPlot = city:Plot()
						local frontDistance = 999
						if focusPlot ~= nil and cityPlot ~= nil then
							frontDistance = Map.PlotDistance(cityPlot:GetX(), cityPlot:GetY(), focusPlot:GetX(), focusPlot:GetY())
							cityScore = cityScore + math.max(0, 700 - frontDistance * SC_GetConfig("MilitaryPurchaseFrontDistanceWeight", 12))
						end
						local totalScore = unitScore + needScore * 7 + cityScore
						local pairKey = tostring(cityID)..":"..tostring(unitID)
						if not SC_MILITARY_PURCHASE_FAILED_THIS_TURN[pairKey] and (best == nil or totalScore > best.totalScore) then
							best = {city = city, cityID = cityID, unitID = unitID, unitScore = unitScore, needScore = needScore, totalScore = totalScore, cost = cost, needKey = needKey, deficit = deficit, frontDistance = frontDistance, needDebug = needDebug, pairKey = pairKey}
						end
						break
					else
						excludedNeeds[needKey] = true
					end
					end
				end
			end
		end
		if best == nil then
			SC_Debug("militaryPurchase stop reason=no-purchasable-candidate budgetLeft="..tostring(budget - spent).." needs="..table.concat(needSummaries, " | "))
			break
		end
		local beforeGold = SC_GetSafeNumber(function() return player:GetGold() end, gold - spent)
		local beforeUnits = SC_CountLivingPlayerUnits(player)
		local callOK, callError = pcall(function() Game.CityPurchaseUnit(best.city, best.unitID, YieldTypes.YIELD_GOLD) end)
		local afterGold = SC_GetSafeNumber(function() return player:GetGold() end, beforeGold)
		local afterUnits = SC_CountLivingPlayerUnits(player)
		-- City purchases are dispatched through the game message queue. The gold and
		-- roster snapshots often update only after this Lua callback returns.
		local immediateConfirmation = callOK and (afterUnits > beforeUnits or afterGold < beforeGold)
		local success = callOK
		local unitInfo = GameInfo.Units[best.unitID]
		local unitType = unitInfo ~= nil and unitInfo.Type or tostring(best.unitID)
		if success then
			local actualCost = math.max(0, beforeGold - afterGold)
			if actualCost <= 0 then actualCost = best.cost end
			spent = spent + actualCost
			purchased = purchased + 1
			usedCities[best.cityID] = true
			reservations[best.needKey] = SC_DBNumber(reservations[best.needKey], 0) + 1
			purchaseOrders[unitType] = SC_DBNumber(purchaseOrders[unitType], 0) + 1
			SC_Debug("militaryPurchase success city="..tostring(best.city:GetName()).." item="..tostring(unitType).." need="..tostring(best.needKey).." deficit="..tostring(best.deficit).." cost="..tostring(actualCost).." gold="..tostring(beforeGold).."->"..tostring(afterGold).." budgetLeft="..tostring(budget - spent).." frontDistance="..tostring(best.frontDistance).." score="..tostring(math.floor(best.totalScore)).." status="..(immediateConfirmation and "confirmed" or "submitted"))
		else
			SC_MILITARY_PURCHASE_FAILED_THIS_TURN[best.pairKey] = true
			usedCities[best.cityID] = true
			SC_Debug("militaryPurchase failure city="..tostring(best.city:GetName()).." item="..tostring(unitType).." need="..tostring(best.needKey).." expectedCost="..tostring(best.cost).." callOK="..SC_BoolText(callOK).." err="..tostring(callError).." gold="..tostring(beforeGold).."->"..tostring(afterGold).." units="..tostring(beforeUnits).."->"..tostring(afterUnits))
		end
	end
	SC_MILITARY_ROSTER_CACHE_THIS_TURN = {}
	SC_Debug("militaryPurchase end purchased="..tostring(purchased).." spent="..tostring(spent).." budget="..tostring(budget).." gold="..tostring(SC_GetSafeNumber(function() return player:GetGold() end, gold - spent)))
	return purchased
end

local function SC_ShouldBuildMilitary(player, city, atWar, reservedOrders)
	local production = SC_GetConfig("ProductionProfile", "BUILDINGS")
	local war = SC_GetConfig("WarProfile", "ADVANCE")
	if not atWar and production ~= "MILITARY" and production ~= "AIRSEA" and war ~= "ASSAULT" then
		return false, nil, 0, "peace-profile"
	end
	local needKey, needDeficit, rosterDebug = SC_GetMilitaryProductionNeed(player, city, atWar, reservedOrders)
	if needKey ~= nil then
		return true, needKey, needDeficit, rosterDebug
	end
	local militaryCount = SC_GetSafeNumber(function() return player:GetNumMilitaryUnits() end, 0)
	local snapshot = SC_GetMilitaryRosterSnapshot(player)
	local packageCount = SC_GetStrikePackageTargets(player, snapshot).packageCount
	local targetMilitary = math.max(packageCount * 8, 12)
	if SC_GetConfig("Doctrine", "BALANCED") == "WAR" then
		targetMilitary = math.max(packageCount * 10, 18)
	end
	if production == "MILITARY" or production == "AIRSEA" then
		targetMilitary = math.max(packageCount * 12, 24)
	end
	if war == "ASSAULT" then
		targetMilitary = math.max(packageCount * 11, 30)
	elseif war == "NAVAL" then
		targetMilitary = math.max(packageCount * 10, 24)
	end
	if militaryCount < targetMilitary then
		return true, "balanced", targetMilitary - militaryCount, rosterDebug or "total-force"
	end
	return false, nil, 0, rosterDebug or "force-sufficient"
end

local function SC_ChooseCityProduction(player, city, atWar)
	if city == nil or city:IsPuppet() or city:IsResistance() then
		return nil
	end
	local queueLength = SC_GetSafeNumber(function() return city:GetOrderQueueLength() end, 0)
	if queueLength >= SC_GetConfig("MinCityQueueLength", 1) then
		return nil
	end
	
	if SC_ShouldBuildMilitary(player, city, atWar) then
		local preferSea = false
		local ok, coastal = pcall(function() return city:IsCoastal() end)
		preferSea = ok and coastal
		local unitID = SC_GetBestTrainableUnit(city, preferSea)
		if unitID == nil and preferSea then
			unitID = SC_GetBestTrainableUnit(city, false)
		end
		if unitID ~= nil and SC_PushCityOrder(city, OrderTypes.ORDER_TRAIN, unitID) then
			local unitInfo = GameInfo.Units[unitID]
			return unitInfo and unitInfo.Type or "UNIT"
		end
	end
	
	local buildingPlan = SC_GetBuildingPlan(player, city, atWar)
	local built = SC_BuildFirstAvailable(city, buildingPlan)
	if built ~= nil then
		return built
	end
	
	local processType = "PROCESS_RESEARCH"
	if SC_GetSafeNumber(function() return player:CalculateGoldRate() end, 0) < 0 then
		processType = "PROCESS_WEALTH"
	end
	local processID = SC_GetID(processType)
	if SC_CityCanMaintain(city, processID) and SC_PushCityOrder(city, OrderTypes.ORDER_MAINTAIN, processID) then
		return processType
	end
	return nil
end

local function SC_AutomateCities(player, atWar)
	local handled = 0
	local details = {}
	if not SC_GetConfig("AutoCityProduction", true) then
		return handled, details
	end
	for city in player:Cities() do
		local productionType = SC_ChooseCityProduction(player, city, atWar)
		if productionType ~= nil then
			handled = handled + 1
			table.insert(details, city:GetName().." -> "..productionType)
		end
	end
	return handled, details
end

local function SC_CanRangeStrikeAt(unit, plot)
	if unit == nil or plot == nil then
		return false
	end
	local x = plot:GetX()
	local y = plot:GetY()
	local ok, result = pcall(function()
		return unit:CanRangeStrikeAt(x, y, true, true)
	end)
	if ok and result then
		return true
	end
	ok, result = pcall(function()
		return unit:CanRangeStrikeAt(x, y)
	end)
	return ok and result
end

local function SC_IsPotentialRangeStrikeAt(unit, plot)
	if SC_CanRangeStrikeAt(unit, plot) then
		return true
	end
	if unit == nil or plot == nil then
		return false
	end
	local unitInfo = SC_GetUnitInfo(unit)
	local profile = SC_GetUnitCapabilityProfile(unit, unitInfo)
	if not profile.mustSetUp then
		return false
	end
	local unitPlot = unit:GetPlot()
	if unitPlot == nil then
		return false
	end
	local distance = Map.PlotDistance(unitPlot:GetX(), unitPlot:GetY(), plot:GetX(), plot:GetY())
	return distance <= SC_GetUnitRangeValue(unit, unitInfo)
end

local function SC_RangeStrike(unit, plot)
	if unit == nil or plot == nil then
		return false
	end
	if SC5 and SC5.IsWithdrawing(unit) then return false, "withdrawal-reserved" end
	if SC_IsCombatTargetAuthorized ~= nil and not SC_IsCombatTargetAuthorized(unit, plot) then
		SC_Debug("rangeStrike diplomacy-block unit="..SC_GetUnitDebugLabel(unit).." target="..SC_GetPlotDebug(plot))
		return false, "diplomacy-block"
	end
	local ownerID, identityUnitID, unitLabel = SC_GetUnitIdentity(unit)
	local unitInfo = SC_GetUnitInfo(unit)
	local role = SC_GetUnitRole(unit, unitInfo)
	local profile = SC_GetUnitCapabilityProfile(unit, unitInfo, role)
	if profile.mustSetUp and not SC_CanRangeStrikeAt(unit, plot) then
		local setupMission = SC_GetMissionID("MISSION_SET_UP_FOR_RANGED_ATTACK")
		local setupOK, setupStatus, setupUnit = SC_SendUnitMission(unit, setupMission)
		if setupMission ~= nil and setupOK then
			if setupUnit ~= nil then unit = setupUnit end
			SC_Debug("rangeStrike setup unit="..tostring(unitLabel).." class="..tostring(profile.doctrineClass).." target="..SC_GetPlotDebug(plot).." status="..tostring(setupStatus))
			return true, "setup"
		end
	end
	local isAirAttack = unitInfo ~= nil and unitInfo.Domain == "DOMAIN_AIR"
	local moveMission = SC_GetMissionID("MISSION_MOVE_TO")
	local rangeMission = SC_GetMissionID("MISSION_RANGE_ATTACK")
	local unitKey = SC_GetUnitTurnKey(unit)
	local targetKey = tostring(plot:GetX())..","..tostring(plot:GetY())
	local cacheKey = tostring(unitKey or SC_GetUnitDebugLabel(unit)).."|"..targetKey
	local function getStrikeSnapshot()
		local resolvedUnit = SC_ResolveLiveUnit(ownerID, identityUnitID)
		if resolvedUnit == nil then
			return {removed = true, moves = -999999, damage = -999999, activity = -999999}
		end
		unit = resolvedUnit
		local currentPlot = nil
		pcall(function() currentPlot = unit:GetPlot() end)
		local x = nil
		local y = nil
		if currentPlot ~= nil then
			pcall(function() x = currentPlot:GetX() end)
			pcall(function() y = currentPlot:GetY() end)
		end
		return {
			moves = SC_GetSafeNumber(function() return unit:MovesLeft() end, -999999),
			damage = SC_GetSafeNumber(function() return unit:GetDamage() end, -999999),
			activity = SC_GetSafeNumber(function() return unit:GetActivityType() end, -999999),
			x = x,
			y = y
		}
	end
	local function strikeStateChanged(before, after)
		if before == nil or after == nil then
			return false
		end
		return after.removed == true
			or after.moves < before.moves
			or after.damage ~= before.damage
	end
	local function finishIfStrikeResolved(before, method, allowOrderClear)
		local after = getStrikeSnapshot()
		if after.removed then
			SC_Debug("rangeStrike unit-removed unit="..tostring(unitLabel).." method="..tostring(method).." target="..SC_GetPlotDebug(plot))
			return true, "unit-removed"
		end
		local changed = strikeStateChanged(before, after)
		local needsOrder = SC_UnitNeedsOrder(unit)
		if changed or (allowOrderClear and not needsOrder) then
			local status = "queued"
			if changed then
				status = "fired"
			end
			SC_Debug("rangeStrike resolved unit="..tostring(unitLabel)..
				" method="..tostring(method)..
				" status="..tostring(status)..
				" changed="..SC_BoolText(changed)..
				" needsOrder="..SC_BoolText(needsOrder)..
				" moves="..tostring(before and before.moves or "?").."->"..tostring(after.moves)..
				" damage="..tostring(before and before.damage or "?").."->"..tostring(after.damage)..
				" activity="..tostring(before and before.activity or "?").."->"..tostring(after.activity)..
				" state="..SC_GetUnitOrderDebug(unit))
			return true, status
		end
		return false, "unresolved"
	end
	if SC_RANGE_FAILED_THIS_TURN[cacheKey] then
		SC_Debug("rangeStrike cached-skip unit="..SC_GetUnitDebugLabel(unit)..
			" role="..tostring(role)..
			" target="..SC_GetPlotDebug(plot)..
			" state="..SC_GetUnitOrderDebug(unit))
		return false, "cached"
	end
	SC_Debug("rangeStrike try unit="..SC_GetUnitDebugLabel(unit)..
		" role="..tostring(role)..
		" target="..SC_GetPlotDebug(plot)..
		" airAttack="..SC_BoolText(isAirAttack))
	local targetCommandAccepted = false
	local function tryTargetMission(missionType, reason, allowOrderClear)
		if missionType == nil then
			return false, "missing-mission"
		end
		local before = getStrikeSnapshot()
		local missionOK, missionStatus, missionUnit = SC_SendUnitMission(unit, missionType, plot:GetX(), plot:GetY())
		if missionStatus == "unit-removed" then
			return missionOK, "unit-removed"
		end
		if missionUnit ~= nil then unit = missionUnit end
		if missionOK then
			local resolved, status = finishIfStrikeResolved(before, reason, false)
			if resolved then
				return true, status
			end
			local directTried = false
			local directOK, directStatus, directUnit = false, nil, nil
			if SC_TryDirectTargetedMission ~= nil then
				directOK, directStatus, directUnit = SC_TryDirectTargetedMission(unit, missionType, plot, reason)
			end
			if directStatus == "unit-removed" then
				return directOK, "unit-removed"
			end
			if directUnit ~= nil then unit = directUnit end
			if directOK then
				directTried = true
				local directResolved, directStatus = finishIfStrikeResolved(before, tostring(reason).."-direct", true)
				if directResolved then
					return true, directStatus
				end
			elseif SC_GetConfig("DirectPushTargetedMissionFallback", true) then
				directTried = true
			end
			resolved, status = finishIfStrikeResolved(before, reason, allowOrderClear)
			if resolved then
				SC_Debug("rangeStrike post-fallback-resolved unit="..SC_GetUnitDebugLabel(unit)..
					" mission="..SC_GetEnumDebugName(MissionTypes, missionType)..
					" reason="..tostring(reason)..
					" directTried="..SC_BoolText(directTried)..
					" status="..tostring(status)..
					" state="..SC_GetUnitOrderDebug(unit))
				return true, status
			end
			SC_Debug("rangeStrike unresolved unit="..SC_GetUnitDebugLabel(unit)..
				" mission="..SC_GetEnumDebugName(MissionTypes, missionType)..
				" reason="..tostring(reason)..
				" directTried="..SC_BoolText(directTried)..
				" state="..SC_GetUnitOrderDebug(unit))
			targetCommandAccepted = true
		end
		return false, "unresolved"
	end
	do
		local done, status = tryTargetMission(rangeMission, "range-attack", true)
		if done then
			return true, status
		end
	end
	if isAirAttack then
		local done, status = tryTargetMission(moveMission, "air-move", true)
		if done then
			return true, status
		end
	elseif role == "fighter" or role == "bomber" or role == "carrier_air" then
		local done, status = tryTargetMission(moveMission, "air-fallback-move", true)
		if done then
			return true, status
		end
	end
	local nativeBefore = getStrikeSnapshot()
	local ok, err = pcall(function()
		unit:RangeStrike(plot:GetX(), plot:GetY())
	end)
	local nativeAfter = getStrikeSnapshot()
	SC_Debug("rangeStrike native unit="..tostring(unitLabel)..
		" target="..SC_GetPlotDebug(plot)..
		" ok="..SC_BoolText(ok)..
		" err="..tostring(err)..
		" removed="..SC_BoolText(nativeAfter.removed == true))
	if ok then
		local resolved, status = finishIfStrikeResolved(nativeBefore, "native", true)
		if resolved then
			return true, status
		end
	end
	if ok then
		SC_Debug("rangeStrike native-unresolved unit="..SC_GetUnitDebugLabel(unit).." target="..SC_GetPlotDebug(plot).." state="..SC_GetUnitOrderDebug(unit))
	end
	SC_RANGE_FAILED_THIS_TURN[cacheKey] = true
	SC_Debug("rangeStrike all-methods-unresolved unit="..SC_GetUnitDebugLabel(unit)..
		" target="..SC_GetPlotDebug(plot)..
		" accepted="..SC_BoolText(targetCommandAccepted)..
		" nativeOk="..SC_BoolText(ok)..
		" state="..SC_GetUnitOrderDebug(unit))
	return false, "unresolved"
end

function SC_AddScoreReason(reasons, label, value)
	if reasons == nil or label == nil or value == nil or value == 0 then
		return
	end
	table.insert(reasons, tostring(label)..":"..tostring(math.floor(value)))
end

function SC_JoinScoreReasons(reasons)
	if reasons == nil or #reasons <= 0 then
		return "base"
	end
	return table.concat(reasons, ",")
end

function SC_IsNavalAssaultStrikeRole(role)
	return role == "missile_carrier"
		or role == "naval_ranged"
		or role == "submarine"
		or role == "carrier_air"
		or role == "bomber"
		or role == "missile"
end

function SC_IsAssaultCaptureRole(role)
	return role == "fast_assault"
		or role == "assault"
		or role == "naval_melee"
end

function SC_CanActAsCityCaptureUnit(unit, unitInfo, role)
	unitInfo = unitInfo or SC_GetUnitInfo(unit)
	if unitInfo == nil then
		return false
	end
	return SC_GetUnitCapabilityProfile(unit, unitInfo, role).canCapture == true
end

function SC_IsDedicatedCityCaptureUnit(unit, unitInfo, role)
	unitInfo = unitInfo or SC_GetUnitInfo(unit)
	if unitInfo == nil or not SC_CanActAsCityCaptureUnit(unit, unitInfo, role) then
		return false
	end
	role = role or SC_GetUnitRole(unit, unitInfo)
	local profile = SC_GetUnitCapabilityProfile(unit, unitInfo, role)
	local combatClass = profile.combatClass or unitInfo.CombatClass or ""
	if combatClass == "UNITCOMBAT_CARRIER"
		or combatClass == "UNITCOMBAT_SUBMARINE"
		or combatClass == "UNITCOMBAT_NAVALRANGED"
		or combatClass == "UNITCOMBAT_SIEGE"
		or combatClass == "UNITCOMBAT_BOMBER"
		or combatClass == "UNITCOMBAT_ARCHER" then
		return false
	end
	-- Role names describe the best special weapon, not the hull's capture
	-- ability.  A 052D is a missile carrier and a naval-melee destroyer; its
	-- hull is therefore a valid finisher even though its role is not naval_melee.
	if profile.domain == "DOMAIN_SEA" then
		return combatClass == "UNITCOMBAT_NAVALMELEE"
			or (combatClass == "UNITCOMBAT_RECON" and (profile.range or 0) <= 1)
	end
	return profile.domain == "DOMAIN_LAND"
end

function SC_GetCaptureUnitEffectivePower(unit, unitInfo, role, distance)
	if unit == nil or unitInfo == nil then
		return 0
	end
	local profile = SC_GetUnitCapabilityProfile(unit, unitInfo, role)
	local maxHP = math.max(SC_DBNumber(profile.maxHP, 100), 1)
	local damage = math.max(SC_GetSafeNumber(function() return unit:GetDamage() end, 0), 0)
	local health = math.max(0.10, 1 - damage / maxHP)
	local power = math.max(SC_DBNumber(profile.power, 0), 1) * health
	if distance ~= nil then
		if distance <= 1 then
			power = power * 1.0
		elseif distance == 2 then
			power = power * 0.75
		else
			power = power * 0.45
		end
	end
	return power
end

function SC_GetCityCaptureSecurity(player, cityPlot, captureUnit)
	if player == nil or cityPlot == nil then
		return false, 0, 0, "missing", 0, 0
	end
	local radius = SC_GetConfig("CaptureSecurityEnemyRadius", 3)
	local enemyCount = 0
	local friendlyCover = 0
	local immediateEnemies = 0
	local enemyPower = 0
	local friendlyPower = 0
	local seenPlots = {}
	for dx = -radius, radius, 1 do
		for dy = -radius, radius, 1 do
			local plot = SC_GetNearbyPlot(cityPlot:GetX(), cityPlot:GetY(), dx, dy, radius)
			if plot ~= nil and Map.PlotDistance(cityPlot:GetX(), cityPlot:GetY(), plot:GetX(), plot:GetY()) <= radius then
				local plotIndex = SC_GetSafeNumber(function() return plot:GetPlotIndex() end, -1)
				local plotKey = plotIndex >= 0 and tostring(plotIndex)
					or (tostring(plot:GetX())..","..tostring(plot:GetY()))
				if not seenPlots[plotKey] then
					seenPlots[plotKey] = true
					local unitCount = SC_GetSafeNumber(function() return plot:GetNumUnits() end, 0)
					for i = 0, unitCount - 1, 1 do
						local nearbyUnit = nil
						pcall(function() nearbyUnit = plot:GetUnit(i) end)
						if nearbyUnit ~= nil and nearbyUnit ~= captureUnit and not nearbyUnit:IsDead() then
							local nearbyInfo = SC_GetUnitInfo(nearbyUnit)
							local combat = nearbyInfo ~= nil and ((nearbyInfo.Combat or 0) > 0 or (nearbyInfo.RangedCombat or 0) > 0)
							if combat then
								local ownerID = SC_GetSafeNumber(function() return nearbyUnit:GetOwner() end, -1)
								local distance = Map.PlotDistance(cityPlot:GetX(), cityPlot:GetY(), plot:GetX(), plot:GetY())
								local effectivePower = SC_GetCaptureUnitEffectivePower(nearbyUnit, nearbyInfo, nil, distance)
								if ownerID == player:GetID() then
									friendlyCover = friendlyCover + 1
									friendlyPower = friendlyPower + effectivePower
								elseif SC_IsEnemyTargetPlayer(player, ownerID) then
									enemyCount = enemyCount + 1
									enemyPower = enemyPower + effectivePower
									if distance <= 1 then immediateEnemies = immediateEnemies + 1 end
								end
							end
						end
					end
				end
			end
		end
	end
	local captureInfo = SC_GetUnitInfo(captureUnit)
	local captureRole = captureInfo ~= nil and SC_GetUnitRole(captureUnit, captureInfo) or nil
	local capturePower = captureInfo ~= nil and SC_GetCaptureUnitEffectivePower(captureUnit, captureInfo, captureRole, 0) or 0
	local captureDamage = captureUnit ~= nil and SC_GetSafeNumber(function() return captureUnit:GetDamage() end, 0) or 100
	local combinedPower = friendlyPower + capturePower
	local requiredRatio = SC_GetConfig("CaptureSecurityPowerRatio", 0.80)
	if captureDamage >= SC_GetConfig("CaptureSecurityCriticalDamage", 55) then
		requiredRatio = SC_GetConfig("CaptureSecurityCriticalPowerRatio", 1.25)
	elseif captureInfo ~= nil and SC_GetUnitProtectionTier(captureUnit, captureInfo, captureRole) >= 2 then
		requiredRatio = math.max(requiredRatio, SC_GetConfig("CaptureSecurityElitePowerRatio", 0.95))
	end
	local secure = enemyCount <= SC_GetConfig("CaptureSecurityMaxEnemies", 0)
		or enemyPower <= 0
		or combinedPower >= enemyPower * requiredRatio
	local reason = "enemies="..tostring(enemyCount)..
		" immediate="..tostring(immediateEnemies)..
		" cover="..tostring(friendlyCover)..
		" power="..tostring(math.floor(combinedPower)).."/"..tostring(math.floor(enemyPower))..
		" ratioNeed="..tostring(requiredRatio)..
		" radius="..tostring(radius)
	return secure, enemyCount, friendlyCover, reason, combinedPower, enemyPower
end

function SC_IsRangedSupportRole(role)
	return role == "missile_carrier"
		or role == "naval_ranged"
		or role == "submarine"
		or role == "siege"
		or role == "land_ranged"
		or role == "carrier_air"
		or role == "fighter"
		or role == "bomber"
		or role == "missile"
end

function SC_GetCityDamageInfo(city)
	local damage = SC_GetSafeNumber(function() return city:GetDamage() end, 0)
	local maxHP = SC_GetSafeNumber(function() return city:GetMaxHitPoints() end, 0)
	local ratio = 0
	if maxHP ~= nil and maxHP > 0 then
		ratio = math.max(0, math.min(1.5, damage / maxHP))
	end
	return damage, maxHP, ratio
end

function SC_IsCityReadyForCapture(city)
	if city == nil then
		return false
	end
	local _, cityMaxHP, cityDamageRatio = SC_GetCityDamageInfo(city)
	return cityMaxHP ~= nil and cityMaxHP > 0 and cityDamageRatio >= SC_GetConfig("CityCaptureReadyDamageRatio", 0.92)
end

function SC_GetRangeTargetStrikeKey(plot, targetKind, bucket)
	if plot == nil then
		return nil
	end
	local plotID = nil
	pcall(function() plotID = plot:GetPlotIndex() end)
	if plotID == nil then
		pcall(function() plotID = tostring(plot:GetX())..","..tostring(plot:GetY()) end)
	end
	if plotID == nil then
		return nil
	end
	return tostring(targetKind or "target").."|"..tostring(plotID).."|"..tostring(bucket or "all")
end

function SC_GetRangeRoleStrikeBucket(role)
	if role == "missile" then
		return "missile"
	end
	if role == "carrier_air" or role == "bomber" or role == "fighter" then
		return "air"
	end
	if role == "missile_carrier" or role == "naval_ranged" or role == "submarine" then
		return "ship"
	end
	if role == "siege" or role == "land_ranged" then
		return "land"
	end
	return "other"
end

function SC_GetRangeTargetStrikeCount(plot, targetKind, bucket)
	local key = SC_GetRangeTargetStrikeKey(plot, targetKind, bucket)
	if key == nil then
		return 0
	end
	return SC_RANGE_TARGET_STRIKE_COUNT_THIS_TURN[key] or 0
end

function SC_RecordRangeTargetStrike(plot, role, targetKind)
	local kind = targetKind or "target"
	local totalKey = SC_GetRangeTargetStrikeKey(plot, kind, "all")
	if totalKey ~= nil then
		SC_RANGE_TARGET_STRIKE_COUNT_THIS_TURN[totalKey] = (SC_RANGE_TARGET_STRIKE_COUNT_THIS_TURN[totalKey] or 0) + 1
	end
	local bucketKey = SC_GetRangeTargetStrikeKey(plot, kind, SC_GetRangeRoleStrikeBucket(role))
	if bucketKey ~= nil then
		SC_RANGE_TARGET_STRIKE_COUNT_THIS_TURN[bucketKey] = (SC_RANGE_TARGET_STRIKE_COUNT_THIS_TURN[bucketKey] or 0) + 1
	end
end

function SC_IsCoastalAssaultPlot(plot)
	if plot == nil then
		return false
	end
	if SC_IsWaterOrCoastalStrategicPlot ~= nil then
		return SC_IsWaterOrCoastalStrategicPlot(plot)
	end
	local isWater = SC_GetSafeNumber(function() return plot:IsWater() and 1 or 0 end, 0)
	return isWater > 0
end

function SC_CountFriendlyRoleNearPlot(player, targetPlot, radius, roleKind, maxCount)
	if player == nil or targetPlot == nil then
		return 0
	end
	radius = radius or 4
	maxCount = maxCount or 6
	local playerID = player:GetID()
	local count = 0
	local targetX = targetPlot:GetX()
	local targetY = targetPlot:GetY()
	for dx = -radius, radius, 1 do
		for dy = -radius, radius, 1 do
			local plot = nil
			if SC_GetNearbyPlot ~= nil then
				plot = SC_GetNearbyPlot(targetX, targetY, dx, dy, radius)
			elseif Map ~= nil then
				pcall(function() plot = Map.GetPlot(targetX + dx, targetY + dy) end)
			end
			if plot ~= nil then
				local distance = Map.PlotDistance(targetX, targetY, plot:GetX(), plot:GetY())
				if distance <= radius then
					local plotUnits = SC_GetSafeNumber(function() return plot:GetNumUnits() end, 0)
					for i = 0, plotUnits - 1, 1 do
						local nearbyUnit = nil
						pcall(function() nearbyUnit = plot:GetUnit(i) end)
						if nearbyUnit ~= nil and SC_GetSafeNumber(function() return nearbyUnit:GetOwner() end, -1) == playerID then
							local nearbyInfo = SC_GetUnitInfo(nearbyUnit)
							local nearbyRole = SC_GetUnitRole(nearbyUnit, nearbyInfo)
							if (roleKind == "capture" and SC_IsDedicatedCityCaptureUnit(nearbyUnit, nearbyInfo, nearbyRole))
								or (roleKind == "support" and SC_IsRangedSupportRole(nearbyRole)) then
								count = count + 1
								if count >= maxCount then
									return count
								end
							end
						end
					end
				end
			end
		end
	end
	return count
end

function SC_GetAssaultSupportNearPlot(player, targetPlot)
	local playerID = player ~= nil and player:GetID() or -1
	local plotIndex = nil
	pcall(function() plotIndex = targetPlot:GetPlotIndex() end)
	local cacheKey = nil
	if plotIndex ~= nil then
		cacheKey = tostring(playerID).."|"..tostring(plotIndex)
		local cached = SC_ASSAULT_SUPPORT_CACHE_THIS_TURN[cacheKey]
		if cached ~= nil then
			return cached.support or 0, cached.capture or 0
		end
	end
	local support = SC_CountFriendlyRoleNearPlot(player, targetPlot, 5, "support", 5)
	local capture = SC_CountFriendlyRoleNearPlot(player, targetPlot, 4, "capture", 4)
	if cacheKey ~= nil then
		SC_ASSAULT_SUPPORT_CACHE_THIS_TURN[cacheKey] = { support = support, capture = capture }
	end
	return support, capture
end

local function SC_ScoreRangeTarget(player, unit, role, unitPlot, targetPlot, enemyUnit, enemyCity)
	if SC5 ~= nil then return SC5.ScoreRangedTarget(player, unit, enemyUnit, enemyCity) end
	if unitPlot == nil or targetPlot == nil then
		return -999999, "missing-plot"
	end
	local distance = Map.PlotDistance(unitPlot:GetX(), unitPlot:GetY(), targetPlot:GetX(), targetPlot:GetY())
	local score = 1000 - distance * 8
	local reasons = {"dist"..tostring(distance)}
	local coastalTarget = SC_IsCoastalAssaultPlot(targetPlot)
	local unitInfo = SC_GetUnitInfo(unit)
	local unitTag = SC_GetUnitCombatTag(unit, unitInfo, role)
	local unitProfile = SC_GetUnitCapabilityProfile(unit, unitInfo, role)
	local combatTempo = SC_StrategyGetCombatTempo ~= nil and SC_StrategyGetCombatTempo(unit) or "legacy"
	local focusPlot = SC_GetOperationFocusPlot(player, unit, unitInfo, unitProfile)
	if focusPlot ~= nil then
		local focusDistance = Map.PlotDistance(targetPlot:GetX(), targetPlot:GetY(), focusPlot:GetX(), focusPlot:GetY())
		if focusDistance <= SC_GetConfig("OperationFocusRadius", 5) then
			local focusScore = 520 - focusDistance * 70
			if combatTempo == "blitz" then focusScore = focusScore + SC_GetConfig("BlitzOperationFocusBonus", 900) end
			score = score + focusScore
			SC_AddScoreReason(reasons, "operationFocus", focusScore)
		end
	end
	local supportCount = 0
	local captureCount = 0
	if enemyUnit ~= nil then
		local enemyInfo = SC_GetUnitInfo(enemyUnit)
		local enemyRole = SC_GetUnitRole(enemyUnit, enemyInfo)
		local enemyClass = SC_GetUnitDoctrineClass(enemyUnit, enemyInfo, enemyRole)
		local doctrineScore = SC_GetDoctrineTargetModifier(unit, unitInfo, role, enemyUnit, enemyInfo, enemyRole, reasons)
		score = score + doctrineScore
		local protectedThreatScore = SC_GetProtectedAssetThreatScore(player, unit, targetPlot, enemyUnit, enemyInfo, enemyRole, role, unitTag, reasons)
		score = score + protectedThreatScore
		local enemyDamage = SC_GetSafeNumber(function() return enemyUnit:GetDamage() end, 0)
		local damageScore = enemyDamage * 8
		score = score + damageScore
		SC_AddScoreReason(reasons, "unitDamage", damageScore)
		local powerScore = (enemyInfo and ((enemyInfo.Combat or 0) + (enemyInfo.RangedCombat or 0)) or 0) / 2
		score = score + powerScore
		SC_AddScoreReason(reasons, "unitPower", powerScore)
		if enemyDamage >= 70 then
			score = score + 320
			SC_AddScoreReason(reasons, "finishUnit", 320)
		elseif enemyDamage >= 45 then
			score = score + 170
			SC_AddScoreReason(reasons, "woundedUnit", 170)
		end
		if role == "missile" or role == "carrier_air" or role == "bomber" then
			score = score + 420
			SC_AddScoreReason(reasons, "airClean", 420)
		end
		if unitTag == "missile_screen" and enemyInfo ~= nil and enemyInfo.Domain == "DOMAIN_SEA" then
			score = score + 440
			SC_AddScoreReason(reasons, "screenNaval", 440)
		end
		if unitTag == "sub_hunter" and enemyInfo ~= nil and enemyInfo.Domain == "DOMAIN_SEA" then
			score = score + 520
			SC_AddScoreReason(reasons, "subHuntNavy", 520)
		end
		if unitTag == "air_wing" and enemyInfo ~= nil and enemyInfo.Domain == "DOMAIN_SEA" then
			score = score + 360
			SC_AddScoreReason(reasons, "navalAirStrike", 360)
		end
		if enemyInfo ~= nil and enemyInfo.Domain == "DOMAIN_LAND" and (enemyRole == "siege" or enemyRole == "land_ranged") then
			if role == "carrier_air" or role == "bomber" or role == "missile" or unitTag == "fast_breakthrough" then
				score = score + 260
				SC_AddScoreReason(reasons, "killSiege", 260)
			end
		end
		if combatTempo == "blitz" then
			if enemyClass == "siege_artillery" or enemyClass == "surface_fire_support" or enemyClass == "arsenal_capital" then
				local blitzScore = SC_GetConfig("BlitzSiegeTargetBonus", 1100)
				score = score + blitzScore
				SC_AddScoreReason(reasons, "blitzKillSiege", blitzScore)
			elseif enemyClass == "ranged_support" or enemyClass == "strike_aircraft" or enemyClass == "air_superiority" then
				local blitzScore = SC_GetConfig("BlitzRangedTargetBonus", 650)
				score = score + blitzScore
				SC_AddScoreReason(reasons, "blitzSuppressFire", blitzScore)
			end
		end
		if SC_IsUnitEmbarked ~= nil and SC_IsUnitEmbarked(enemyUnit) and (role == "carrier_air" or role == "bomber" or role == "missile" or role == "missile_carrier" or role == "naval_ranged" or role == "submarine") then
			score = score + 300
			SC_AddScoreReason(reasons, "sinkTransport", 300)
		end
		if enemyInfo ~= nil and enemyInfo.Domain == "DOMAIN_SEA" then
			if role == "naval_ranged" or role == "missile_carrier" or role == "submarine" or role == "carrier_air" or role == "bomber" or role == "missile" then
				score = score + 360
				SC_AddScoreReason(reasons, "killNavy", 360)
			end
		end
		if enemyRole == "carrier" or enemyRole == "missile_carrier" or enemyRole == "submarine" then
			score = score + 300
			SC_AddScoreReason(reasons, "highValueNaval", 300)
		end
		if role == "fighter" and enemyInfo ~= nil and enemyInfo.Domain == "DOMAIN_AIR" then
			score = score + 300
			SC_AddScoreReason(reasons, "airDefense", 300)
		end
		if role == "siege" and enemyInfo ~= nil and enemyInfo.Domain == "DOMAIN_LAND" then
			score = score + 80
			SC_AddScoreReason(reasons, "siegeVsLand", 80)
		end
		if SC_IsNavalAssaultStrikeRole(role) and coastalTarget then
			supportCount, captureCount = SC_GetAssaultSupportNearPlot(player, targetPlot)
			local assaultScore = 120 + math.min(supportCount, 4) * 60
			score = score + assaultScore
			SC_AddScoreReason(reasons, "coastalFront", assaultScore)
			if captureCount > 0 then
				local screenScore = math.min(captureCount, 3) * 70
				score = score + screenScore
				SC_AddScoreReason(reasons, "clearForCapture", screenScore)
			end
		end
	end
	if enemyCity ~= nil then
		local cityDamage, cityMaxHP, cityDamageRatio = SC_GetCityDamageInfo(enemyCity)
		if cityMaxHP > 0 and cityDamage >= cityMaxHP - 1 then
			return -999999, "captureWaitZeroHP"
		end
		if cityDamageRatio >= SC_GetConfig("CityCaptureReadyDamageRatio", 0.92) then
			local captureNear = SC_CountFriendlyRoleNearPlot(
				player,
				targetPlot,
				SC_GetConfig("CaptureReadyFireSupportRadius", 5),
				"capture",
				1)
			if captureNear <= 0 then
				return -999999, "captureWaitNoUnit"
			end
		end
		local doctrineClass = SC_GetUnitDoctrineClass(unit, unitInfo, role)
		local enemyScreen = SC_CountEnemyCombatPresenceNearPlot(player, targetPlot, SC_GetConfig("OperationEnemyScreenRadius", 4), 6)
		local cityStrikeCount = SC_GetRangeTargetStrikeCount(targetPlot, "city", "all")
		local roleStrikeBucket = SC_GetRangeRoleStrikeBucket(role)
		local roleStrikeCount = SC_GetRangeTargetStrikeCount(targetPlot, "city", roleStrikeBucket)
		score = score + 700
		SC_AddScoreReason(reasons, "city", 700)
		if enemyScreen > 0 and cityDamageRatio < SC_GetConfig("CityCaptureReadyDamageRatio", 0.92) then
			local screenPenalty = math.min(enemyScreen, 4) * 260
			if doctrineClass == "siege_artillery" or doctrineClass == "arsenal_capital" then
				screenPenalty = math.floor(screenPenalty * 0.45)
			end
			score = score - screenPenalty
			SC_AddScoreReason(reasons, "clearUnitsFirst", -screenPenalty)
		end
		local cityDamageScore = cityDamage * 4
		score = score + cityDamageScore
		SC_AddScoreReason(reasons, "cityDamage", cityDamageScore)
		if cityDamageRatio >= 0.75 then
			score = score + 520
			SC_AddScoreReason(reasons, "captureReady", 520)
		elseif cityDamageRatio >= 0.45 then
			score = score + 300
			SC_AddScoreReason(reasons, "pressDamagedCity", 300)
		end
		if coastalTarget and SC_IsNavalAssaultStrikeRole(role) then
			score = score + 340
			SC_AddScoreReason(reasons, "coastalCity", 340)
		end
		if role == "siege" or role == "bomber" or role == "carrier_air" or role == "missile" then
			local airCityScore = 220
			if cityDamageRatio >= 0.45 then
				airCityScore = airCityScore + 180
			end
			score = score + airCityScore
			SC_AddScoreReason(reasons, "airVsCity", airCityScore)
		elseif role == "naval_ranged" or role == "missile_carrier" then
			score = score + 320
			SC_AddScoreReason(reasons, "shipVsCity", 320)
		elseif role == "land_ranged" then
			score = score + 120
			SC_AddScoreReason(reasons, "rangedVsCity", 120)
		end
		if unitTag == "arsenal_ship" then
			score = score + 380
			SC_AddScoreReason(reasons, "arsenalSiege", 380)
			if cityDamageRatio >= SC_GetConfig("CityCaptureReadyDamageRatio", 0.92) and cityStrikeCount >= 1 then
				score = score - 520
				SC_AddScoreReason(reasons, "arsenalHoldForCapture", -520)
			end
		elseif unitTag == "missile_screen" then
			score = score + 170
			SC_AddScoreReason(reasons, "screenSiege", 170)
		elseif unitTag == "air_wing" or unitTag == "missile_strike" then
			if cityDamageRatio < SC_GetConfig("CityCaptureReadyDamageRatio", 0.92) then
				score = score + 180
				SC_AddScoreReason(reasons, "airSoftening", 180)
			else
				score = score - 420
				SC_AddScoreReason(reasons, "airHoldForCapture", -420)
			end
		end
		if SC_IsNavalAssaultStrikeRole(role) or SC_IsAssaultCaptureRole(role) then
			supportCount, captureCount = SC_GetAssaultSupportNearPlot(player, targetPlot)
			if supportCount >= 2 then
				local focusScore = math.min(supportCount, 5) * 70
				score = score + focusScore
				SC_AddScoreReason(reasons, "fleetFocus", focusScore)
			end
			if captureCount > 0 and cityDamageRatio >= 0.35 then
				local captureScore = math.min(captureCount, 4) * 90
				score = score + captureScore
				SC_AddScoreReason(reasons, "captureUnitNear", captureScore)
			end
		end
		if cityDamageRatio >= SC_GetConfig("CityCaptureReadyDamageRatio", 0.92)
			and SC_IsDedicatedCityCaptureUnit(unit, unitInfo, role)
			and distance <= SC_GetConfig("CityCaptureDirectMaxDistance", 2) then
			local capturePenalty = SC_GetConfig("CaptureReadyAdjacentFirePenalty", 4200)
			score = score - capturePenalty
			SC_AddScoreReason(reasons, "captureInsteadOfFire", -capturePenalty)
		end
		if SC_GetSafeNumber(function() return enemyCity:IsCapital() and 1 or 0 end, 0) > 0 then
			score = score + 120
			SC_AddScoreReason(reasons, "capital", 120)
		end
		if cityDamageRatio >= SC_GetConfig("CityCaptureReadyDamageRatio", 0.92) and cityStrikeCount >= 2 then
			local saturationPenalty = 900 + cityStrikeCount * 220
			if roleStrikeBucket == "missile" or roleStrikeBucket == "air" then
				saturationPenalty = saturationPenalty + 500
			end
			score = score - saturationPenalty
			SC_AddScoreReason(reasons, "citySaturated", -saturationPenalty)
		end
		if cityStrikeCount >= SC_GetConfig("MaxRangeStrikesPerCityPerTurn", 8) then
			score = score - 3500
			SC_AddScoreReason(reasons, "cityStrikeCap", -3500)
		end
		if roleStrikeBucket == "missile" and roleStrikeCount >= SC_GetConfig("MaxMissileStrikesPerCityPerTurn", 2) then
			score = score - 2800
			SC_AddScoreReason(reasons, "missileCityCap", -2800)
		elseif roleStrikeBucket == "air" and roleStrikeCount >= SC_GetConfig("MaxAirStrikesPerCityPerTurn", 4) then
			score = score - 2000
			SC_AddScoreReason(reasons, "airCityCap", -2000)
		end
	end
	return score, SC_JoinScoreReasons(reasons)
end

function SC_GetRangeTargetStatsDebug(stats)
	if stats == nil then
		return "stats=nil"
	end
	return "enemyUnits="..tostring(stats.enemyUnits or 0)..
		" enemyCities="..tostring(stats.enemyCities or 0)..
		" inRangeUnits="..tostring(stats.inRangeUnits or 0)..
		" inRangeCities="..tostring(stats.inRangeCities or 0)..
		" outOfRange="..tostring(stats.outOfRange or 0)..
		" noPlot="..tostring(stats.noPlot or 0)..
		" lowScore="..tostring(stats.lowScore or 0)..
		" captureWaitZeroHP="..tostring(stats.captureWaitZeroHP or 0)..
		" captureWaitNoUnit="..tostring(stats.captureWaitNoUnit or 0)..
		" bestScore="..tostring(stats.bestScore or "nil")..
		" bestKind="..tostring(stats.bestKind or "nil")..
		" bestReason="..tostring(stats.bestReason or "nil")
end

local function SC_FindRangeTarget(player, unit)
	if player == nil or unit == nil then
		return nil, -999999, nil
	end
	local team = Teams[player:GetTeam()]
	if team == nil then
		return nil, -999999, nil
	end
	local unitPlot = unit:GetPlot()
	if unitPlot == nil then
		return nil, -999999, nil
	end
	local unitInfo = SC_GetUnitInfo(unit)
	local role = SC_GetUnitRole(unit, unitInfo)
	local profile = SC_GetUnitCapabilityProfile(unit, unitInfo, role)
	local rangeLimit = math.max(profile.range or 0, SC_GetSafeNumber(function() return unit:Range() end, 0), 1)
	local bestPlot = nil
	local bestScore = -999999
	local stats = {
		enemyUnits = 0,
		enemyCities = 0,
		inRangeUnits = 0,
		inRangeCities = 0,
		outOfRange = 0,
		noPlot = 0,
		lowScore = 0,
		captureWaitZeroHP = 0,
		captureWaitNoUnit = 0,
		bestScore = nil,
		bestKind = nil
	}
	local targetPool = nil
	if SCX_GetExecutionTargetPool ~= nil then
		targetPool = SCX_GetExecutionTargetPool(player, unit, "fire")
	elseif SC_StrategyGetTargetPoolForUnit ~= nil then
		targetPool = SC_StrategyGetTargetPoolForUnit(player, unit, SC_GetEnemyTargetPool(player))
	else
		targetPool = SC_GetEnemyTargetPool(player)
	end
	for _, enemyUnit in ipairs(targetPool.units) do
		if SC_IsEnemyTargetUnitValid(player, enemyUnit) then
				stats.enemyUnits = stats.enemyUnits + 1
				local plot = enemyUnit:GetPlot()
				if plot == nil then
					stats.noPlot = stats.noPlot + 1
				elseif Map.PlotDistance(unitPlot:GetX(), unitPlot:GetY(), plot:GetX(), plot:GetY()) > rangeLimit then
					stats.outOfRange = stats.outOfRange + 1
				elseif SC_IsPotentialRangeStrikeAt(unit, plot) then
					stats.inRangeUnits = stats.inRangeUnits + 1
					local score, reason, facts = SC_ScoreRangeTarget(player, unit, role, unitPlot, plot, enemyUnit, nil)
					if SC5 then SC5.CollectCandidate(stats, score, reason, facts) end
					if score > bestScore or (score == bestScore and facts and facts.key < (stats.bestKey or "~")) then
						bestScore = score
						bestPlot = plot
						stats.bestKey = facts and facts.key or nil
						stats.bestScore = score
						stats.bestKind = "unit"
						stats.bestReason = reason
						stats.bestFacts = facts
					end
				else
					stats.outOfRange = stats.outOfRange + 1
				end
		end
	end
	for _, city in ipairs(targetPool.cities) do
		if SC_IsEnemyTargetCityValid(player, city) then
				stats.enemyCities = stats.enemyCities + 1
				local plot = city:Plot()
				if plot == nil then
					stats.noPlot = stats.noPlot + 1
				elseif Map.PlotDistance(unitPlot:GetX(), unitPlot:GetY(), plot:GetX(), plot:GetY()) > rangeLimit then
					stats.outOfRange = stats.outOfRange + 1
				elseif SC_IsPotentialRangeStrikeAt(unit, plot) then
					stats.inRangeCities = stats.inRangeCities + 1
					local score, reason, facts = SC_ScoreRangeTarget(player, unit, role, unitPlot, plot, nil, city)
					if SC5 then SC5.CollectCandidate(stats, score, reason, facts) end
					if reason == "captureWaitZeroHP" then
						stats.captureWaitZeroHP = stats.captureWaitZeroHP + 1
					elseif reason == "captureWaitNoUnit" then
						stats.captureWaitNoUnit = stats.captureWaitNoUnit + 1
					end
					if score > bestScore or (score == bestScore and facts and facts.key < (stats.bestKey or "~")) then
						bestScore = score
						bestPlot = plot
						stats.bestKey = facts and facts.key or nil
						stats.bestScore = score
						stats.bestKind = "city"
						stats.bestReason = reason
						stats.bestFacts = facts
					end
				else
					stats.outOfRange = stats.outOfRange + 1
				end
		end
	end
	if bestPlot ~= nil and bestScore < SC_GetConfig("MinTacticalTargetScore", 1) then
		stats.lowScore = (stats.lowScore or 0) + 1
		stats.bestReason = "below-threshold:"..tostring(bestScore)..":"..tostring(stats.bestReason or "none")
		bestPlot = nil
	end
	if SC5 then SC5.LogCandidates(unit, stats) end
	return bestPlot, bestScore, stats
end

function SC_GetStablePlotKey(plot)
	if plot == nil then return "nil" end
	local index = nil
	pcall(function() index = plot:GetPlotIndex() end)
	if index ~= nil then return tostring(index) end
	return tostring(SC_GetSafeNumber(function() return plot:GetX() end, -1))..":"..
		tostring(SC_GetSafeNumber(function() return plot:GetY() end, -1))
end

function SC_FindAirSweepTarget(player, unit, targetCounts)
	if player == nil or unit == nil then
		return nil, -999999, "missing"
	end
	local unitInfo = SC_GetUnitInfo(unit)
	local role = SC_GetUnitRole(unit, unitInfo)
	local profile = SC_GetUnitCapabilityProfile(unit, unitInfo, role)
	if not profile.airSweep and profile.doctrineClass ~= "air_superiority" and profile.doctrineClass ~= "carrier_multirole" then
		return nil, -999999, "not-sweep-capable"
	end
	local unitPlot = unit:GetPlot()
	local team = Teams[player:GetTeam()]
	if unitPlot == nil or team == nil then
		return nil, -999999, "no-plot"
	end
	local bestPlot = nil
	local bestScore = -999999
	local bestReason = "no-enemy-air"
	local targetPool = nil
	if SCX_GetExecutionTargetPool ~= nil then
		targetPool = SCX_GetExecutionTargetPool(player, unit, "air-sweep")
	elseif SC_StrategyGetTargetPoolForUnit ~= nil then
		targetPool = SC_StrategyGetTargetPoolForUnit(player, unit, SC_GetEnemyTargetPool(player))
	else
		targetPool = SC_GetEnemyTargetPool(player)
	end
	for _, enemyUnit in ipairs(targetPool.units) do
		if SC_IsEnemyTargetUnitValid(player, enemyUnit) then
				local enemyInfo = SC_GetUnitInfo(enemyUnit)
				local enemyPlot = enemyUnit ~= nil and enemyUnit:GetPlot() or nil
				if enemyPlot ~= nil and enemyInfo ~= nil then
					local plotKey = SC_GetStablePlotKey(enemyPlot)
					local saturated = targetCounts ~= nil and SC_DBNumber(targetCounts[plotKey], 0) >= SC_GetConfig("AirSweepMaxPerTargetPerTurn", 2)
					local distance = Map.PlotDistance(unitPlot:GetX(), unitPlot:GetY(), enemyPlot:GetX(), enemyPlot:GetY())
					if not saturated and distance <= math.max(profile.range or 0, 1) and SC_IsCombatTargetAuthorized(unit, enemyPlot) then
						local enemyProfile = SC_GetUnitCapabilityProfile(enemyUnit, enemyInfo)
						local score = 1800 - distance * 12 + (enemyProfile.power or 0) * 3 + (enemyProfile.intercept or 0) * 2
						local candidateReason = "enemy-air"
						if enemyProfile.doctrineClass == "air_superiority" or enemyProfile.doctrineClass == "carrier_multirole" then
							score = score + 520
							candidateReason = "enemy-fighter"
						elseif enemyProfile.doctrineClass == "strike_aircraft" then
							score = score + 360
							candidateReason = "enemy-strike-air"
						end
						if SC5 then score, candidateReason = SC5.SweepScore(unit, enemyPlot, enemyUnit) end
						if score > bestScore then
							bestScore = score
							bestPlot = enemyPlot
							bestReason = candidateReason
						end
					end
				end
		end
	end
	return bestPlot, bestScore, bestReason
end

function SC_CanAirRebaseAt(unit, plot)
	if unit == nil or plot == nil then return false end
	local canRebase = false
	local ok = pcall(function() canRebase = unit:CanRebaseAt(plot:GetX(), plot:GetY()) end)
	return ok and canRebase
end

function SC_TryAirRebaseAt(unit, plot)
	if unit == nil or plot == nil then return false, "missing", unit end
	local mission = SC_GetMissionID("MISSION_REBASE")
	if mission == nil then return false, "missing-mission", unit end
	local ownerID, unitID = SC_GetUnitIdentity(unit)
	local beforeIndex = SC_GetUnitPlotIndexForTacticalCache(unit)
	local sent, status, liveUnit = SC_SendUnitMission(unit, mission, plot:GetX(), plot:GetY())
	if status == "unit-removed" then return false, status, nil end
	unit = liveUnit or unit
	local changed = beforeIndex ~= nil and SC_GetUnitPlotIndexForTacticalCache(unit) ~= beforeIndex
	if not changed and SC_TryDirectTargetedMission ~= nil then
		local _, directStatus, directUnit = SC_TryDirectTargetedMission(unit, mission, plot, "air-rebase")
		if directStatus == "unit-removed" then return false, directStatus, nil end
		unit = directUnit or unit
		changed = beforeIndex ~= nil and SC_GetUnitPlotIndexForTacticalCache(unit) ~= beforeIndex
		status = changed and "direct" or tostring(status).."/"..tostring(directStatus)
	end
	return changed, changed and status or "no-state-change:"..tostring(status), unit
end

function SC_AutomateAirRebase(player, atWar, emergencyOnly)
	if player == nil or not atWar or SC_StrategyGetOperationForUnit == nil then return 0 end
	local destinations = {}
	for city in player:Cities() do
		local plot = city:Plot()
		if plot ~= nil then table.insert(destinations, { plot = plot, kind = "city", label = city:GetName() }) end
	end
	for carrier in player:Units() do
		local carrierInfo = SC_GetUnitInfo(carrier)
		local carrierProfile = SC_GetUnitCapabilityProfile(carrier, carrierInfo)
		local isMobileAirbase = carrierInfo ~= nil
			and carrierInfo.Domain == "DOMAIN_SEA"
			and carrierInfo.DomainCargo == "DOMAIN_AIR"
			and carrierInfo.SpecialCargo ~= nil and carrierInfo.SpecialCargo ~= ""
		if carrier ~= nil and not carrier:IsDead()
			and (carrierProfile.doctrineClass == "fleet_carrier" or isMobileAirbase) then
			local plot = carrier:GetPlot()
			if plot ~= nil then table.insert(destinations, { plot = plot, kind = "mobile-base", label = SC_GetUnitDebugLabel(carrier) }) end
		end
	end
	local moved = 0
	local maxRebases = SC_GetConfig("MaxAirRebasesPerTurn", 20)
	if emergencyOnly then maxRebases = math.huge end
	local reserved = SC_AIR_REBASE_DESTINATION_COUNT_THIS_TURN
	local destinationKeys = {}
	for _, destination in ipairs(destinations) do
		table.insert(destinationKeys, tostring(destination.kind)..":"..tostring(SC_GetStablePlotKey(destination.plot)))
	end
	table.sort(destinationKeys)
	local destinationSignature = table.concat(destinationKeys, ",")
	local baseThreatCache = {}
	local function baseThreat(plot)
		local key = SC_GetStablePlotKey(plot)
		if baseThreatCache[key] == nil then baseThreatCache[key] = SC5 and SC5.BaseThreat(player, plot) or false end
		return baseThreatCache[key]
	end
	for unit in player:Units() do
		if moved >= maxRebases then break end
		local unitInfo = SC_GetUnitInfo(unit)
		local unitKey = unit ~= nil and SC_GetUnitTurnKey(unit) or nil
		if unit ~= nil and unitInfo ~= nil and unitInfo.Domain == "DOMAIN_AIR" and not unit:IsDead()
			and unit:CanMove() and (unitKey == nil or not SC_AIR_REBASED_THIS_TURN[unitKey]) then
			local taskAllowed = true
			if SC_StrategyUnitAllowsModule ~= nil then taskAllowed = SC_StrategyUnitAllowsModule(unit, "airRebase") end
			local operation = taskAllowed and SC_StrategyGetOperationForUnit(unit) or nil
			local source = unit:GetPlot()
			local emergencyRadius = SC_GetConfig("AirbaseEmergencyThreatRadius", 6)
			local sourceEnemyDistance = source ~= nil and SC_GetNearestEnemyCombatDistance(player, source, emergencyRadius + 1) or 999
			local emergency = SC5 and baseThreat(source) or (not SC5 and sourceEnemyDistance <= emergencyRadius)
			local target = operation ~= nil and operation.target and operation.target.plot or nil
			local targetReason = operation ~= nil and operation.id or "assigned"
			if taskAllowed and target == nil and SC_StrategyGetPrimaryOffensiveTarget ~= nil then
				local fallbackTarget, _, fallbackReason = SC_StrategyGetPrimaryOffensiveTarget()
				target = fallbackTarget
				targetReason = "primary:"..tostring(fallbackReason)
			end
			if source ~= nil and (target ~= nil or emergency) and (not emergencyOnly or emergency) then
				local profile = SC_GetUnitCapabilityProfile(unit, unitInfo)
				local currentDistance = target ~= nil and Map.PlotDistance(source:GetX(), source:GetY(), target:GetX(), target:GetY()) or 0
				local usefulRange = math.max(profile.range or 0, SC_GetSafeNumber(function() return unit:Range() end, 0), 4)
				local noDestination = unitKey ~= nil and SC_AIR_REBASE_NO_DEST_THIS_TURN[unitKey] or nil
				local sourceIndex = SC_GetUnitPlotIndexForTacticalCache(unit)
				local noDestinationStillValid = noDestination ~= nil
					and noDestination.sourceIndex == sourceIndex
					and noDestination.destinationSignature == destinationSignature
					and noDestination.emergency == emergency
				if (emergency or currentDistance > usefulRange) and not noDestinationStillValid then
					local best, bestScore = nil, -999999
					for _, destination in ipairs(destinations) do
						local destinationKey = SC_GetStablePlotKey(destination.plot)
						if (emergency or SC_DBNumber(reserved[destinationKey], 0) < SC_GetConfig("AirRebaseMaxPerDestinationPerTurn", 4))
							and destination.plot ~= source and SC_CanAirRebaseAt(unit, destination.plot) then
							local targetDistance = target ~= nil and Map.PlotDistance(destination.plot:GetX(), destination.plot:GetY(), target:GetX(), target:GetY()) or 0
							local improvement = currentDistance - targetDistance
							local destinationThreatRadius = SC_GetConfig("AirbaseEmergencyDestinationThreatRadius", 8)
							local enemyDistance = SC_GetNearestEnemyCombatDistance(player, destination.plot, destinationThreatRadius + 1)
							local score = improvement * 160 + math.min(enemyDistance, destinationThreatRadius + 1) * 30
							if destination.kind == "city" then score = score + 180 end
							local acceptable = improvement >= SC_GetConfig("AirRebaseMinimumDistanceGain", 4)
							if emergency then
								acceptable = SC5 and not baseThreat(destination.plot)
									or (not SC5 and enemyDistance > emergencyRadius and enemyDistance > sourceEnemyDistance)
								score = enemyDistance * 520 - targetDistance * 12 + (destination.kind == "city" and 240 or 0)
							end
							if SC5 and baseThreat(destination.plot) then acceptable = false end
							if acceptable and score > bestScore then
								best, bestScore = destination, score
							end
						end
					end
					if best ~= nil then
						local ok, status, liveUnit = SC_TryAirRebaseAt(unit, best.plot)
						if liveUnit ~= nil then unit = liveUnit end
						if ok then
							if SC_StrategyRecordTaskAction ~= nil then SC_StrategyRecordTaskAction(unit, "airRebase", best.kind) end
							local bestKey = SC_GetStablePlotKey(best.plot)
							reserved[bestKey] = SC_DBNumber(reserved[bestKey], 0) + 1
							if unitKey ~= nil then SC_AIR_REBASED_THIS_TURN[unitKey] = true end
							if unitKey ~= nil then SC_AIR_REBASE_NO_DEST_THIS_TURN[unitKey] = nil end
							moved = moved + 1
							SC_Debug("airRebase success unit="..SC_GetUnitDebugLabel(unit).." operation="..tostring(targetReason).." emergency="..SC_BoolText(emergency).." sourceEnemyDistance="..tostring(sourceEnemyDistance).." destination="..tostring(best.label).." kind="..tostring(best.kind).." distance="..tostring(currentDistance).."->"..tostring(target ~= nil and Map.PlotDistance(best.plot:GetX(), best.plot:GetY(), target:GetX(), target:GetY()) or 0).." score="..tostring(math.floor(bestScore)).." status="..tostring(status))
						else
							if unitKey ~= nil then
								SC_AIR_REBASE_NO_DEST_THIS_TURN[unitKey] = {
									sourceIndex = sourceIndex, destinationSignature = destinationSignature, emergency = emergency
								}
							end
							SC_Debug("airRebase failed unit="..SC_GetUnitDebugLabel(unit).." operation="..tostring(targetReason).." destination="..tostring(best.label).." status="..tostring(status))
						end
					end
					if best == nil and unitKey ~= nil then
						SC_AIR_REBASE_NO_DEST_THIS_TURN[unitKey] = {
							sourceIndex = sourceIndex, destinationSignature = destinationSignature, emergency = emergency
						}
					end
					if emergency and best == nil then
						SC_Debug("airRebase emergency-hold unit="..SC_GetUnitDebugLabel(unit).." source="..SC_GetPlotDebug(source).." sourceEnemyDistance="..tostring(sourceEnemyDistance).." reason=no-safe-destination")
					end
				end
			end
		end
	end
	return moved
end

local function SC_AutomateAirSuperiority(player, atWar)
	if player == nil or not atWar then
		return 0
	end
	local playerID = SC_GetSafeNumber(function() return player:GetID() end, -1)
	local turn = SC_GetSafeNumber(function() return Game.GetGameTurn() end, -1)
	local budgetKey = tostring(playerID)..":"..tostring(turn)
	local budgetState = SC_AIR_SUPERIORITY_BUDGET_THIS_TURN[budgetKey]
	if budgetState == nil then
		local wings, enemyAir = {}, 0
		for unit in player:Units() do
			local unitInfo = SC_GetUnitInfo(unit)
			local profile = SC_GetUnitCapabilityProfile(unit, unitInfo)
			if unit ~= nil and not unit:IsDead() and (profile.doctrineClass == "air_superiority" or profile.doctrineClass == "carrier_multirole") then
				local ownerID, unitID = SC_GetUnitIdentity(unit)
				table.insert(wings, {
					ownerID = ownerID, unitID = unitID,
					doctrineClass = profile.doctrineClass, power = profile.power or 0
				})
			end
		end
		local targetPool = SC_GetEnemyTargetPool(player)
		for _, enemyUnit in ipairs(targetPool.units) do
			local enemyInfo = SC_GetUnitInfo(enemyUnit)
			local p = SC_GetUnitCapabilityProfile(enemyUnit, enemyInfo)
			if enemyInfo ~= nil and (enemyInfo.Domain == "DOMAIN_AIR" or (p.intercept or 0) > 0) then enemyAir = enemyAir + 1 end
		end
		table.sort(wings, function(a, b)
			if a.doctrineClass ~= b.doctrineClass then return a.doctrineClass == "air_superiority" end
			return a.power > b.power
		end)
		local reserveFraction = math.max(0.2, math.min(SC_GetConfig("AirSuperiorityReserveFraction", 0.35), 0.75))
		local available = math.max(0, math.floor(#wings * (1 - reserveFraction)))
		local maxSweeps = math.min(available, math.max(0, math.ceil(enemyAir * SC_GetConfig("AirSweepPerEnemyAir", 1.5))))
		budgetState = { wings = wings, enemyAir = enemyAir, maxSweeps = maxSweeps, used = 0, targetCounts = {}, failed = {} }
		SC_AIR_SUPERIORITY_BUDGET_THIS_TURN[budgetKey] = budgetState
		SC_Debug("airSuperiority budget wings="..tostring(#wings).." enemyAir="..tostring(enemyAir).." reserve="..tostring(#wings - available).." maxSweeps="..tostring(maxSweeps))
	end
	local actions = 0
	for _, identity in ipairs(budgetState.wings) do
		if budgetState.used >= budgetState.maxSweeps then break end
		local unit = SC_ResolveLiveUnit(identity.ownerID, identity.unitID)
		if unit ~= nil and not unit:IsDead() and SC_CanUnitActForTactical(unit, SC_GetUnitInfo(unit)) then
			local unitInfo = SC_GetUnitInfo(unit)
			local role = SC_GetUnitRole(unit, unitInfo)
			local profile = SC_GetUnitCapabilityProfile(unit, unitInfo, role)
			local unitKey = SC_GetUnitTurnKey(unit)
			local actionCap = SC_GetTacticalActionCapForUnit(unit, unitInfo, role)
			if (profile.doctrineClass == "air_superiority" or profile.doctrineClass == "carrier_multirole")
				and SC_GetTacticalActionCount(unitKey) < actionCap then
				local targetPlot, targetScore, reason = SC_FindAirSweepTarget(player, unit, budgetState.targetCounts)
				if targetPlot ~= nil and not budgetState.failed[unitKey] then
					local ownerID, identityUnitID, unitLabel = SC_GetUnitIdentity(unit)
					local beforeMoves = unit:MovesLeft()
					local mission = SC_GetMissionID("MISSION_AIR_SWEEP")
					local ok, missionStatus, missionUnit = false, nil, nil
					if mission ~= nil then
						ok, missionStatus, missionUnit = SC_SendUnitMission(unit, mission, targetPlot:GetX(), targetPlot:GetY())
					end
					if missionUnit ~= nil then unit = missionUnit end
					local live = SC_ResolveLiveUnit(ownerID, identityUnitID)
					local confirmed = live == nil or live:MovesLeft() < beforeMoves
					if not confirmed and live ~= nil and mission ~= nil and SC_TryDirectTargetedMission ~= nil then
						unit = live
						ok, missionStatus, missionUnit = SC_TryDirectTargetedMission(unit, mission, targetPlot, "air-superiority")
						if missionUnit ~= nil then unit = missionUnit end
					end
					live = SC_ResolveLiveUnit(ownerID, identityUnitID)
					confirmed = live == nil or live:MovesLeft() < beforeMoves
					if confirmed then
						local count = SC_RecordTacticalAction(unitKey)
						local targetKey = SC_GetStablePlotKey(targetPlot)
						budgetState.targetCounts[targetKey] = SC_DBNumber(budgetState.targetCounts[targetKey], 0) + 1
						budgetState.used = budgetState.used + 1
						actions = actions + 1
						SC_Debug("airSuperiority sweep unit="..tostring(unitLabel).." class="..tostring(profile.doctrineClass).." target="..SC_GetPlotDebug(targetPlot).." score="..tostring(targetScore).." reason="..tostring(reason).." count="..tostring(count).."/"..tostring(actionCap).." status="..tostring(missionStatus))
					else
						budgetState.failed[unitKey] = true
						local resolvedUnit = SC_ResolveLiveUnit(ownerID, identityUnitID)
						SC_Debug("airSuperiority failed unit="..tostring(unitLabel).." target="..SC_GetPlotDebug(targetPlot).." score="..tostring(targetScore).." reason="..tostring(reason).." status="..tostring(missionStatus).." live="..SC_BoolText(resolvedUnit ~= nil))
					end
				end
			end
		end
	end
	return actions
end

local function SC_AutomateLocalDefense(player, atWar)
	if not SC_GetConfig("AutoLocalDefense", true) or not atWar then
		SC_Debug("localDefense skip enabled="..SC_BoolText(SC_GetConfig("AutoLocalDefense", true)).." atWar="..SC_BoolText(atWar))
		return 0
	end
	local actions = 0
	local maxActions = SC_GetConfig("MaxUnitTacticalStrikesPerTurn", SC_GetConfig("LocalDefenseMaxActions", 12))
	local maxRounds = SC_GetConfig("MaxUnitTacticalStrikeRounds", 2)
	local debugCount = 0
	local debugLimit = SC_GetConfig("DebugUnitDecisionLimit", 60)
	local cachedDebugCount = 0
	local cachedDebugLimit = SC_GetConfig("DebugCachedUnitDecisionLimit", 8)
	local function debugUnit(text)
		if SC_GetConfig("DebugUnitDecisions", true) and debugCount < debugLimit then
			debugCount = debugCount + 1
			SC_Debug(text)
		end
	end
	local function debugCached(text)
		if cachedDebugCount < cachedDebugLimit then
			cachedDebugCount = cachedDebugCount + 1
			debugUnit(text)
		end
	end
	local orderedUnits = {}
	for unit in player:Units() do
		local taskAllowed = true
		if unit ~= nil and SC_StrategyUnitAllowsModule ~= nil then taskAllowed = SC_StrategyUnitAllowsModule(unit, "localDefense") end
		if unit ~= nil and taskAllowed then
			local unitInfo = SC_GetUnitInfo(unit)
			local profile = SC_GetUnitCapabilityProfile(unit, unitInfo)
			local ownerID, unitID = SC_GetUnitIdentity(unit)
				local firePriority = 4
				if SC5 and SC5.HasChainReaction(unit) then
					firePriority = 0
				elseif profile.doctrineClass == "missile_strike" or profile.doctrineClass == "strike_aircraft" then
					firePriority = 1
				elseif profile.doctrineClass == "arsenal_capital" or profile.doctrineClass == "surface_fire_support"
					or profile.doctrineClass == "siege_artillery" or profile.doctrineClass == "ranged_support" then
					firePriority = 2
				elseif profile.doctrineClass == "carrier_multirole" or profile.doctrineClass == "air_superiority" then
					firePriority = 3
				end
				table.insert(orderedUnits, {
					ownerID = ownerID, unitID = unitID,
					firePriority = firePriority, phase = profile.phase or 99,
					range = profile.range or 0, power = profile.power or 0
				})
		end
	end
	table.sort(orderedUnits, function(a, b)
		if a.firePriority ~= b.firePriority then
			return a.firePriority < b.firePriority
		end
		if a.phase ~= b.phase then
			return a.phase < b.phase
		end
		if a.range ~= b.range then
			return a.range > b.range
		end
		return a.power > b.power
	end)
	SC_Debug("localDefense start maxActions="..tostring(maxActions).." maxRounds="..tostring(maxRounds))
	for round = 1, maxRounds, 1 do
		local roundActions = 0
		for _, identity in ipairs(orderedUnits) do
			if actions >= maxActions then
				SC_Debug("localDefense cap actions="..tostring(actions))
				return actions
			end
			local unit = SC_ResolveLiveUnit(identity.ownerID, identity.unitID)
			if unit ~= nil then
				local unitInfo = SC_GetUnitInfo(unit)
				local role = SC_GetUnitRole(unit, unitInfo)
				local unitTag = SC_GetUnitCombatTag(unit, unitInfo, role)
				local doctrineClass = SC_GetUnitDoctrineClass(unit, unitInfo, role)
				local unitKey = SC_GetUnitTurnKey(unit)
				local taskAllowed, taskKind = true, "legacy"
				if SC_StrategyUnitAllowsModule ~= nil then taskAllowed, taskKind = SC_StrategyUnitAllowsModule(unit, "localDefense") end
				if not taskAllowed then
					debugCached("localDefense task-skip unit="..SC_GetUnitDebugLabel(unit).." task="..tostring(taskKind).." directive="..tostring(SC_StrategyGetUnitTaskDebug and SC_StrategyGetUnitTaskDebug(unit) or "-"))
				elseif SC_IsCombatAutomationUnit(unit, unitInfo) and SC_UnitIsFitForCombat(unit, unitInfo, role) then
					local canAct = SC_CanUnitActForTactical(unit, unitInfo)
					local actionCount = SC_GetTacticalActionCount(unitKey)
					local actionCap = SC_GetTacticalActionCapForUnit(unit, unitInfo, role)
					local captureAssignment = unitKey ~= nil and SC_CITY_CAPTURE_ASSIGNMENTS_THIS_TURN[unitKey] or nil
					local preserveForCapture = captureAssignment ~= nil
						and captureAssignment.task ~= nil
						and SC_IsEnemyTargetCityValid(player, captureAssignment.task.city)
						and SC_IsCityReadyForCapture(captureAssignment.task.city)
					if preserveForCapture then
						debugCached("localDefense capture-reserve unit="..SC_GetUnitDebugLabel(unit)..
							" slot="..tostring(captureAssignment.slot)..
							" city="..SC_GetPlotDebug(captureAssignment.task.plot)..
							" reason=preserve-finisher-action")
					elseif unitKey ~= nil and actionCount >= actionCap then
						debugCached("localDefense unit-cap unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role).." tag="..tostring(unitTag).." count="..tostring(actionCount).." cap="..tostring(actionCap))
					elseif canAct and SC_IsRangedAttackUnit(unit, unitInfo, role) then
						local cachedQueued = SC_GetValidTacticalQueuedCache(unit, unitKey)
						if cachedQueued ~= nil then
							debugCached("localDefense queued-cached unit="..SC_GetUnitDebugLabel(unit).." "..SC_FormatTacticalQueuedCache(cachedQueued))
						else
						local cachedNoTarget = SC_GetValidTacticalNoTargetCache(unit, unitKey)
						if cachedNoTarget ~= nil then
							debugCached("localDefense no-target-cached unit="..SC_GetUnitDebugLabel(unit).." "..SC_FormatTacticalNoTargetCache(cachedNoTarget))
						else
							local targetPlot, targetScore, targetStats = SC_FindRangeTarget(player, unit)
							local strikeDone = false
							local strikeStatus = "none"
							local unitLabel = SC_GetUnitDebugLabel(unit)
							local attackFacts = nil
							if targetPlot ~= nil then
								if SC5 then attackFacts = SC5.LogAttackFacts(player, unit, targetPlot, targetStats) end
								if not SC5 or attackFacts then
									strikeDone, strikeStatus = SC_RangeStrike(unit, targetPlot)
								else
									strikeStatus = "target-revalidation-failed"
								end
								unit = SC_ResolveLiveUnit(identity.ownerID, identity.unitID)
								if SC5 then SC5.LogAttackOutcome(attackFacts, strikeStatus) end
							end
							if targetPlot ~= nil and strikeDone then
								if unit and SC_StrategyRecordTaskAction ~= nil then SC_StrategyRecordTaskAction(unit, "localDefense", strikeStatus) end
								local newCount = SC_RecordTacticalAction(unitKey)
								SC_RecordRangeTargetStrike(targetPlot, role, targetStats and targetStats.bestKind or nil)
								local label = "queued"
								if SC_IsStrikeStatusFired(strikeStatus) then
									label = "fired"
								end
								debugUnit("localDefense "..label.." round="..tostring(round).." unit="..unitLabel.." role="..tostring(role).." class="..tostring(doctrineClass).." tag="..tostring(unitTag).." status="..tostring(strikeStatus).." count="..tostring(newCount).."/"..tostring(actionCap).." target="..SC_GetPlotDebug(targetPlot).." score="..tostring(targetScore).." reason="..tostring(targetStats and targetStats.bestReason or "nil"))
								if unitKey ~= nil then
									SC_TACTICAL_ORDERED_THIS_TURN[unitKey] = newCount
									if unit and SC_IsStrikeStatusQueued(strikeStatus) then
										SC_RecordTacticalQueued(unit, unitKey, role, targetPlot, strikeStatus, "localDefense")
									else
										SC_TACTICAL_QUEUED_THIS_TURN[unitKey] = nil
										SC_TACTICAL_NO_TARGET_THIS_TURN[unitKey] = nil
									end
								end
								actions = actions + 1
								roundActions = roundActions + 1
							elseif targetPlot == nil then
								SC_RecordTacticalNoTarget(unit, unitKey, role, targetStats, "out-of-range")
								debugUnit("localDefense no-target unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role).." tag="..tostring(unitTag).." "..SC_GetRangeTargetStatsDebug(targetStats))
							else
								local newCount = SC_RecordTacticalAction(unitKey)
								debugUnit("localDefense fire-failed unit="..unitLabel.." role="..tostring(role).." tag="..tostring(unitTag).." status="..tostring(strikeStatus).." count="..tostring(newCount).."/"..tostring(actionCap).." target="..SC_GetPlotDebug(targetPlot).." score="..tostring(targetScore).." reason="..tostring(targetStats and targetStats.bestReason or "nil"))
								if unitKey ~= nil then
									SC_TACTICAL_ORDERED_THIS_TURN[unitKey] = newCount
								end
							end
						end
						end
					elseif not canAct then
						debugCached("localDefense cannot-act unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role).." tag="..tostring(unitTag))
					else
						debugCached("localDefense not-ranged unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role))
					end
				end
			end
		end
		if roundActions == 0 then
			break
		end
	end
	SC_Debug("localDefense end actions="..tostring(actions))
	return actions
end

local function SC_TechKeywordScore(techType, words, score)
	if techType == nil then
		return 0
	end
	for _, word in ipairs(words) do
		if string.find(techType, word) ~= nil then
			return score
		end
	end
	return 0
end

local function SC_GetBestResearch(player)
	if player == nil then
		return nil
	end
	local doctrine = SC_GetConfig("Doctrine", "BALANCED")
	local bestTechID = nil
	local bestScore = -999999
	for tech in GameInfo.Technologies() do
		local canResearch = false
		pcall(function()
			canResearch = player:CanResearch(tech.ID)
		end)
		if canResearch then
			local turns = SC_GetSafeNumber(function() return player:GetResearchTurnsLeft(tech.ID, true) end, 999)
			local techType = tech.Type or ""
			local score = 1000 - turns * 8
			if SC5 ~= nil then
				score = 0
			elseif doctrine == "WAR" then
				score = score + SC_TechKeywordScore(techType, {"MILITARY", "BALLISTICS", "COMBUSTION", "FLIGHT", "RADAR", "ROCKETRY", "LASER", "STEALTH", "NUCLEAR", "ROBOTICS"}, 600)
			elseif doctrine == "SCIENCE" then
				score = score + SC_TechKeywordScore(techType, {"EDUCATION", "SCIENTIFIC", "ELECTRICITY", "PLASTICS", "COMPUTERS", "SATELLITES", "NANOTECHNOLOGY"}, 600)
			elseif doctrine == "INDUSTRY" then
				score = score + SC_TechKeywordScore(techType, {"METAL", "INDUSTRIALIZATION", "STEAM", "RAILROAD", "ELECTRICITY", "REPLACEABLE", "PLASTICS", "ECOLOGY"}, 600)
			else
				score = score + SC_TechKeywordScore(techType, {"EDUCATION", "INDUSTRIALIZATION", "ELECTRICITY", "PLASTICS", "RADAR", "COMPUTERS"}, 350)
			end
			if SC_StrategyScoreResearch ~= nil then
				score = SC_StrategyScoreResearch(player, tech, turns, score)
			end
			if score > bestScore then
				bestScore = score
				bestTechID = tech.ID
			end
		end
	end
	return bestTechID
end

local function SC_AutomateResearch(player)
	if not SC_GetConfig("AutoResearch", false) or player == nil then
		return 0
	end
	local currentResearch = SC_GetSafeNumber(function() return player:GetCurrentResearch() end, -1)
	local freeTechs = SC_GetSafeNumber(function() return player:GetNumFreeTechs() end, 0)
	if currentResearch ~= -1 and freeTechs <= 0 then
		return 0
	end
	local techID = SC_GetBestResearch(player)
	if techID == nil then
		return 0
	end
	if SC_StrategyLogResearchChoice ~= nil then
		SC_StrategyLogResearchChoice(techID)
	end
	local ok = pcall(function()
		Network.SendResearch(techID, freeTechs, -1, false)
	end)
	if ok then
		return 1
	end
	return 0
end

local function SC_AutomateUnitUpgrades(player)
	if not SC_GetConfig("AutoUpgradeUnits", false) or player == nil then
		return 0
	end
	local upgraded = 0
	local maxUpgrades = SC_GetConfig("MaxAutoUpgradesPerTurn", 8)
	for unit in player:Units() do
		if upgraded >= maxUpgrades then
			return upgraded
		end
		if unit ~= nil and not unit:IsDead() and unit:CanUpgradeRightNow() then
			local ok = SC_SendUnitCommand(unit, CommandTypes["COMMAND_UPGRADE"])
			if ok then
				upgraded = upgraded + 1
			end
		end
	end
	return upgraded
end

function SC_GetNearestEnemyCombatDistance(player, targetPlot, maxDistance)
	if player == nil or targetPlot == nil then
		return 999
	end
	maxDistance = maxDistance or 12
	local plotIndex = nil
	pcall(function() plotIndex = targetPlot:GetPlotIndex() end)
	local cacheKey = plotIndex ~= nil and tostring(player:GetID()).."|"..tostring(plotIndex).."|"..tostring(maxDistance) or nil
	if cacheKey ~= nil and SC_RETREAT_THREAT_CACHE_THIS_TURN[cacheKey] ~= nil then
		return SC_RETREAT_THREAT_CACHE_THIS_TURN[cacheKey]
	end
	local team = Teams[player:GetTeam()]
	if team == nil then
		return 999
	end
	local bestDistance = maxDistance
	local found = false
	for otherID, otherPlayer in pairs(Players) do
		if otherPlayer ~= nil and otherPlayer:IsAlive() and otherPlayer:GetID() ~= player:GetID() and team:IsAtWar(otherPlayer:GetTeam()) then
			for enemyUnit in otherPlayer:Units() do
				local enemyInfo = SC_GetUnitInfo(enemyUnit)
				local enemyPlot = enemyUnit ~= nil and enemyUnit:GetPlot() or nil
				if enemyPlot ~= nil and enemyInfo ~= nil and ((enemyInfo.Combat or 0) > 0 or (enemyInfo.RangedCombat or 0) > 0) then
					local distance = Map.PlotDistance(targetPlot:GetX(), targetPlot:GetY(), enemyPlot:GetX(), enemyPlot:GetY())
					if distance < bestDistance then
						bestDistance = distance
						found = true
					end
				end
			end
		end
	end
	if not found then
		if cacheKey ~= nil then
			SC_RETREAT_THREAT_CACHE_THIS_TURN[cacheKey] = 999
		end
		return 999
	end
	if cacheKey ~= nil then
		SC_RETREAT_THREAT_CACHE_THIS_TURN[cacheKey] = bestDistance
	end
	return bestDistance
end

function SC_FindRetreatPlot(player, unit)
	if player == nil or unit == nil then
		return nil
	end
	local sourcePlot = unit:GetPlot()
	local unitInfo = SC_GetUnitInfo(unit)
	if sourcePlot == nil or unitInfo == nil then
		return nil
	end
	local radius = SC_GetConfig("RetreatSearchRadius", 4)
	local layer = SC_GetUnitStackLayer(unit)
	local role = SC_GetUnitRole(unit, unitInfo)
	local profile = SC_GetUnitCapabilityProfile(unit, unitInfo, role)
	local protectionTier = SC_GetUnitProtectionTier(unit, unitInfo, role, profile)
	local bestPlot = nil
	local bestScore = -999999
	for dx = -radius, radius, 1 do
		for dy = -radius, radius, 1 do
			local plot = SC_GetNearbyPlot(sourcePlot:GetX(), sourcePlot:GetY(), dx, dy, radius)
			local usable, moveDistance = SC_MoveCandidateIsUsable(player, unit, unitInfo, sourcePlot, plot, layer, nil, nil, nil)
			if usable and moveDistance ~= nil and moveDistance <= radius then
				local checked, canEnter = pcall(function() return unit:CanMoveInto(plot, 0) end)
				if checked and canEnter then
					local enemyDistance = SC_GetNearestEnemyCombatDistance(player, plot, 12)
					local score = enemyDistance * 150 - moveDistance * 15
					local owner = SC_GetSafeNumber(function() return plot:GetOwner() end, -1)
					if owner == player:GetID() then
						score = score + 520
					elseif owner < 0 then
						score = score + 100
					end
					local isWater = SC_GetSafeNumber(function() return plot:IsWater() and 1 or 0 end, 0) > 0
					local isFriendlyCity = SC_GetSafeNumber(function() return plot:IsCity() and 1 or 0 end, 0) > 0 and owner == player:GetID()
					if isFriendlyCity then
						score = score + 1100
					end
					if unitInfo.Domain == "DOMAIN_LAND" then
						if isWater then
							score = score - (protectionTier >= 2 and 2400 or 700)
						else
							score = score + (protectionTier >= 2 and 500 or 180)
						end
					end
					if unitInfo.Domain == "DOMAIN_SEA" then
						score = score - SC_CountEnemySeaThreatsNearPlot(player, plot, SC_GetConfig("FleetStandoffThreatRadius", 4)) * 260
					end
					if score > bestScore then
						bestScore = score
						bestPlot = plot
					end
				end
			end
		end
	end
	return bestPlot
end

local function SC_AutomateDamagedUnitHealing(player)
	if not SC_GetConfig("AutoHealDamagedUnits", false) or player == nil then
		return 0
	end
	local healed = 0
	local maxHeals = SC_GetConfig("MaxAutoHealsPerTurn", 12)
	for unit in player:Units() do
		if healed >= maxHeals then
			return healed
		end
		if unit ~= nil and unit:IsCombatUnit() and unit:CanMove() then
			local unitInfo = SC_GetUnitInfo(unit)
			local role = SC_GetUnitRole(unit, unitInfo)
			local profile = SC_GetUnitCapabilityProfile(unit, unitInfo, role)
			local protectionTier = SC_GetUnitProtectionTier(unit, unitInfo, role, profile)
			local unitThreshold = SC_GetUnitRetreatDamageThreshold(unit, unitInfo, role, profile)
			if unit:GetDamage() >= unitThreshold then
				local unitKey = SC_GetUnitTurnKey(unit)
			if unitKey ~= nil and SC_HEAL_HANDLED_THIS_TURN[unitKey] then
				-- A successful heal/retreat order is stable for the rest of this turn.
			elseif unitKey ~= nil and SC_HEAL_FAILED_THIS_TURN[unitKey] then
				if SC_GetConfig("DebugUnitCommands", true) then
					SC_Debug("heal cached-skip unit="..SC_GetUnitDebugLabel(unit).." state="..SC_GetUnitOrderDebug(unit))
				end
			else
				local unitPlot = unit:GetPlot()
				local threatRadius = protectionTier >= 2 and SC_GetConfig("HighValueThreatRadius", 8) or SC_GetConfig("RetreatThreatRadius", 5)
				local enemyDistance = SC_GetNearestEnemyCombatDistance(player, unitPlot, threatRadius + 1)
				local criticalDamage = unit:GetDamage() >= SC_GetConfig("CriticalDamageRetreatThreshold", 55)
				local owner = unitPlot ~= nil and SC_GetSafeNumber(function() return unitPlot:GetOwner() end, -1) or -1
				local inFriendlyCity = unitPlot ~= nil
					and SC_GetSafeNumber(function() return unitPlot:IsCity() and 1 or 0 end, 0) > 0
					and owner == player:GetID()
				local retreated = false
				local retreatStatus = nil
				if enemyDistance <= threatRadius or (criticalDamage and not inFriendlyCity) then
					local retreatPlot = SC_FindRetreatPlot(player, unit)
					if retreatPlot ~= nil then
						local liveUnit = nil
						retreated, retreatStatus, liveUnit = SC_TryMoveMission(unit, retreatPlot, "damaged-retreat", true)
						if retreatStatus == "unit-removed" then
							if unitKey ~= nil then SC_HEAL_HANDLED_THIS_TURN[unitKey] = true end
							retreated = true
							SC_Debug("heal retreat unit-removed key="..tostring(unitKey).." to="..SC_GetPlotDebug(retreatPlot))
						elseif liveUnit ~= nil then
							unit = liveUnit
						end
						if retreated then
							if unitKey ~= nil then
								if retreatStatus ~= "unit-removed" then
									SC_STRATEGIC_ORDERED_THIS_TURN[unitKey] = SC_GetStrategicOrderCapForUnit(unit, unitInfo, role)
								end
								SC_HEAL_HANDLED_THIS_TURN[unitKey] = true
							end
							healed = healed + 1
							if retreatStatus ~= "unit-removed" then
								SC_Debug("heal retreat unit="..SC_GetUnitDebugLabel(unit).." class="..tostring(profile.doctrineClass).." tier="..tostring(protectionTier).." damage="..tostring(unit:GetDamage()).." critical="..SC_BoolText(criticalDamage).." enemyDistance="..tostring(enemyDistance).." threatRadius="..tostring(threatRadius).." to="..SC_GetPlotDebug(retreatPlot))
							end
						end
					end
				end
				local ok = false
				local healStatus = nil
				if not retreated then
					local liveUnit = nil
					ok, healStatus, liveUnit = SC_SendUnitMission(unit, GameInfoTypes.MISSION_HEAL)
					if liveUnit ~= nil then unit = liveUnit end
					if healStatus == "unit-removed" then
						if unitKey ~= nil then SC_HEAL_HANDLED_THIS_TURN[unitKey] = true end
						healed = healed + 1
					end
				end
				if healStatus ~= "unit-removed" and ok and (SC_UnitNeedsOrder == nil or not SC_UnitNeedsOrder(unit)) then
					if unitKey ~= nil then
						SC_HEAL_HANDLED_THIS_TURN[unitKey] = true
					end
					healed = healed + 1
				elseif not retreated and healStatus ~= "unit-removed" then
					if unitKey ~= nil then
						SC_HEAL_FAILED_THIS_TURN[unitKey] = true
					end
					if ok and SC_GetConfig("DebugUnitCommands", true) then
						SC_Debug("heal pending-clear unit="..SC_GetUnitDebugLabel(unit).." state="..SC_GetUnitOrderDebug(unit))
					elseif SC_GetConfig("DebugUnitCommands", true) then
						SC_Debug("heal failed unit="..SC_GetUnitDebugLabel(unit).." state="..SC_GetUnitOrderDebug(unit))
					end
				end
			end
			end
		end
	end
	return healed
end

local function SC_AutomateIdlePosture(player)
	if not SC_GetConfig("AutoIdlePosture", false) or player == nil then
		return 0
	end
	local handled = 0
	local maxPosture = SC_GetConfig("MaxIdlePosturePerTurn", 20)
	local atWar = SC_PlayerAtWar(player)
	for unit in player:Units() do
		if handled >= maxPosture then
			return handled
		end
		if unit ~= nil and unit:CanMove() and unit:GetActivityType() == 0 then
			local ok = false
			if unit:IsCombatUnit() then
				if unit:GetDomainType() == DomainTypes.DOMAIN_AIR then
					local unitInfo = SC_GetUnitInfo(unit)
					local role = SC_GetUnitRole(unit, unitInfo)
					if role == "fighter" and unit:CurrInterceptionProbability() > 0 and unit:GetCurrHitPoints() > 30 then
						ok = SC_SendUnitMission(unit, GameInfoTypes.MISSION_AIRPATROL)
					elseif atWar then
						ok = SC_SendUnitMission(unit, GameInfoTypes.MISSION_SKIP)
					else
						ok = SC_SendUnitMission(unit, GameInfoTypes.MISSION_SLEEP)
					end
				else
					ok = SC_SendUnitMission(unit, GameInfoTypes.MISSION_ALERT)
				end
			end
			if ok then
				handled = handled + 1
			end
		end
	end
	return handled
end

local function SC_FindCityStrikeTarget(player, city)
	if player == nil or city == nil then
		return nil
	end
	local team = Teams[player:GetTeam()]
	if team == nil then
		return nil
	end
	local cityX = city:GetX()
	local cityY = city:GetY()
	local bestPlot = nil
	local bestScore = 999999
	for otherID, otherPlayer in pairs(Players) do
		if otherPlayer ~= nil and otherPlayer:IsAlive() and team:IsAtWar(otherPlayer:GetTeam()) then
			for enemyUnit in otherPlayer:Units() do
				local plot = enemyUnit:GetPlot()
				if plot ~= nil then
					local canStrike = false
					pcall(function()
						canStrike = city:CanRangeStrikeAt(plot:GetX(), plot:GetY(), true, true)
					end)
					if canStrike then
						local distance = Map.PlotDistance(cityX, cityY, plot:GetX(), plot:GetY())
						local score = distance * 10 - enemyUnit:GetDamage()
						if score < bestScore then
							bestScore = score
							bestPlot = plot
						end
					end
				end
			end
		end
	end
	return bestPlot
end

local function SC_AutomateCityRangedStrike(player, atWar)
	if not SC_GetConfig("AutoCityRangedStrike", false) or not atWar or player == nil then
		return 0
	end
	local strikes = 0
	local maxStrikes = SC_GetConfig("MaxCityStrikesPerTurn", 8)
	for city in player:Cities() do
		if strikes >= maxStrikes then
			return strikes
		end
		local canStrike = false
		pcall(function()
			canStrike = city:CanRangeStrike()
		end)
		if canStrike then
			local targetPlot = SC_FindCityStrikeTarget(player, city)
			if targetPlot ~= nil then
				local ok = pcall(function()
					Network.SendDoTask(city:GetID(), TaskTypes.TASK_RANGED_ATTACK, targetPlot:GetX(), targetPlot:GetY(), false, false, false, false)
				end)
				if ok then
					strikes = strikes + 1
				end
			end
		end
	end
	return strikes
end

local function SC_CountEmptyCityQueues(player)
	local count = 0
	if player == nil then
		return count
	end
	for city in player:Cities() do
		if city ~= nil and not city:IsPuppet() and not city:IsResistance() then
			local queueLength = SC_GetSafeNumber(function() return city:GetOrderQueueLength() end, 0)
			if queueLength < 1 then
				count = count + 1
			end
		end
	end
	return count
end

local function SC_GetPendingDecisionLines(player)
	local lines = {}
	if player == nil then
		return lines
	end
	if SC_GetSafeNumber(function() return player:GetCurrentResearch() end, -1) == -1 then
		table.insert(lines, "需要选择科技。")
	end
	if SC_GetSafeNumber(function() return player:GetNumFreeTechs() end, 0) > 0 then
		table.insert(lines, "有免费科技待选择。")
	end
	if SC_GetSafeNumber(function() return player:GetNumFreePolicies() end, 0) > 0 then
		table.insert(lines, "有免费政策待选择。")
	elseif SC_GetSafeNumber(function() return player:GetJONSCulture() end, 0) >= SC_GetSafeNumber(function() return player:GetNextPolicyCost() end, 999999) then
		table.insert(lines, "可以选择社会政策。")
	end
	local emptyQueues = SC_CountEmptyCityQueues(player)
	if emptyQueues > 0 then
		table.insert(lines, tostring(emptyQueues).." 个城市生产队列为空。")
	end
	return lines
end

local function SC_CountIdleCombatUnits(player)
	local count = 0
	for unit in player:Units() do
		if unit ~= nil and unit:IsCombatUnit() and unit:CanMove() then
			count = count + 1
		end
	end
	return count
end

local function SC_SendNotification(player, heading, text)
	if player == nil then
		return
	end
	pcall(function()
		player:AddNotification(NotificationTypes.NOTIFICATION_GENERIC, text, heading, -1, -1)
	end)
end

local function SC_SendNationalBrief(player, cityOrders, defenseActions, cityDetails, atWar)
	if player == nil then
		return
	end
	if not SC_GetConfig("NationalBrief", true) then
		return
	end
	local interval = math.max(SC_GetConfig("InterventionInterval", 10), 1)
	local turn = Game.GetGameTurn()
	if turn % interval ~= 0 then
		return
	end
	
	local enemies = SC_GetWarSummary(player)
	local lines = {}
	table.insert(lines, "战略指挥部简报")
	table.insert(lines, "回合: "..tostring(turn))
	table.insert(lines, "城市自动安排: "..tostring(cityOrders))
	table.insert(lines, "自动远程反击: "..tostring(defenseActions))
	table.insert(lines, "待命作战单位: "..tostring(SC_CountIdleCombatUnits(player)))
	table.insert(lines, "快乐: "..tostring(SC_GetSafeNumber(function() return player:GetExcessHappiness() end, 0)))
	table.insert(lines, "国库: "..tostring(SC_GetSafeNumber(function() return player:GetGold() end, 0)))
	if atWar then
		table.insert(lines, "战争状态: 与 "..table.concat(enemies, ", ").." 交战")
	else
		table.insert(lines, "战争状态: 和平")
	end
	if #cityDetails > 0 then
		table.insert(lines, "最近城市安排:")
		for i = 1, math.min(#cityDetails, 6), 1 do
			table.insert(lines, cityDetails[i])
		end
	end
	
	SC_SendNotification(player, "战略指挥部", table.concat(lines, "[NEWLINE]"))
end

local function SC_SendNationalBriefNow(player, cityOrders, defenseActions, cityDetails, atWar)
	if player == nil then
		return
	end
	local oldBrief = SC_GetConfig("NationalBrief", true)
	SC_CONFIG.NationalBrief = true
	local oldInterval = SC_GetConfig("InterventionInterval", 10)
	SC_CONFIG.InterventionInterval = 1
	SC_SendNationalBrief(player, cityOrders or 0, defenseActions or 0, cityDetails or {}, atWar)
	SC_CONFIG.InterventionInterval = oldInterval
	SC_CONFIG.NationalBrief = oldBrief
end

local function SC_BuildLightweightAutomationResults(player, atWar)
	local results = {
		cityOrders = 0, ideologies = 0, research = 0, policies = 0, upgrades = 0,
		promotions = 0, greatPeople = 0, purchases = 0, heals = 0, defenseActions = 0,
		captureFinishers = 0, cityStrikes = 0, strategicMoves = 0, stackedMoves = 0,
		transportEscort = 0, idlePosture = 0, tradeRoutes = 0, finalOrders = 0,
		notifications = 0, leagues = 0, blockers = 0, popups = 0, diplo = 0, moduleErrors = 0
	}
	local maxSweeps = SC_GetConfig("MaxLightweightInnerSweeps", 1)
	for sweep = 1, maxSweeps, 1 do
		SC_Debug("sweep begin index="..tostring(sweep).." mode=light blocker="..SC_GetBlockingDebug(player))
		local before = results.ideologies + results.research + results.policies + results.promotions
			+ results.greatPeople + results.finalOrders + results.leagues + results.blockers
		local count, _, moduleErrors = SC_RunCountModule("ideology", function() return SC_LightAutomateIdeology(player) end)
		results.ideologies = results.ideologies + count
		results.moduleErrors = results.moduleErrors + moduleErrors
		count, _, moduleErrors = SC_RunCountModule("research", function() return SC_AutomateResearch(player) end)
		results.research = results.research + count
		results.moduleErrors = results.moduleErrors + moduleErrors
		count, _, moduleErrors = SC_RunCountModule("policy", function() return SC_LightAutomatePolicy(player) end)
		results.policies = results.policies + count
		results.moduleErrors = results.moduleErrors + moduleErrors
		count, _, moduleErrors = SC_RunCountModule("promotion", function() return SC_AutomateUnitPromotions(player) end)
		results.promotions = results.promotions + count
		results.moduleErrors = results.moduleErrors + moduleErrors
		count, _, moduleErrors = SC_RunCountModule("greatPeople", function() return SC_AutomateGreatPeople(player, atWar) end)
		results.greatPeople = results.greatPeople + count
		results.moduleErrors = results.moduleErrors + moduleErrors
		count, _, moduleErrors = SC_RunCountModule("finalOrders", function() return SC_LightAutomateFinalUnitOrders(player, atWar) end)
		results.finalOrders = results.finalOrders + count
		results.moduleErrors = results.moduleErrors + moduleErrors
		if sweep == 1 then
			count, _, moduleErrors = SC_RunCountModule("leagues", function() return SC_LightAutomateLeagues(player) end)
			results.leagues = results.leagues + count
			results.moduleErrors = results.moduleErrors + moduleErrors
		end
		count, _, moduleErrors = SC_RunCountModule("endTurnBlocker", function() return SC_LightHandleEndTurnBlocker(player, atWar) end)
		results.blockers = results.blockers + count
		results.moduleErrors = results.moduleErrors + moduleErrors
		local after = results.ideologies + results.research + results.policies + results.promotions
			+ results.greatPeople + results.finalOrders + results.leagues + results.blockers
		SC_Debug("sweep end index="..tostring(sweep).." mode=light promote="..tostring(results.promotions)..
			" greatPeople="..tostring(results.greatPeople).." finalOrders="..tostring(results.finalOrders)..
			" leagues="..tostring(results.leagues).." blockers="..tostring(results.blockers)..
			" moduleErrors="..tostring(results.moduleErrors).." blockerNow="..SC_GetBlockingDebug(player))
		if after == before then
			break
		end
	end
	return results, {}
end

local function SC_BuildAutomationResults(player, atWar, fullAutomation)
	if fullAutomation == false then
		return SC_BuildLightweightAutomationResults(player, atWar)
	end
	local cityOrders, cityDetails = SC_AutomateCities(player, atWar)
	local results = {
		cityOrders = cityOrders,
		research = SC_AutomateResearch(player),
		upgrades = SC_AutomateUnitUpgrades(player),
		heals = SC_AutomateDamagedUnitHealing(player),
		defenseActions = SC_AutomateAirSuperiority(player, atWar) + SC_AutomateLocalDefense(player, atWar),
		cityStrikes = SC_AutomateCityRangedStrike(player, atWar),
		idlePosture = SC_AutomateIdlePosture(player)
	}
	return results, cityDetails
end

local function SC_SendNationalBrief(player, results, cityDetails, atWar)
	if player == nil then
		return
	end
	if not SC_GetConfig("NationalBrief", true) then
		return
	end
	local interval = math.max(SC_GetConfig("InterventionInterval", 10), 1)
	local turn = Game.GetGameTurn()
	if turn % interval ~= 0 then
		return
	end
	
	results = results or {}
	cityDetails = cityDetails or {}
	local enemies = SC_GetWarSummary(player)
	local lines = {}
	table.insert(lines, "战略指挥部简报")
	table.insert(lines, "回合: "..tostring(turn))
	table.insert(lines, "城市安排: "..tostring(results.cityOrders or 0))
	table.insert(lines, "意识形态: "..tostring(results.ideologies or 0))
	table.insert(lines, "科研选择: "..tostring(results.research or 0))
	table.insert(lines, "单位升级: "..tostring(results.upgrades or 0))
	table.insert(lines, "治疗命令: "..tostring(results.heals or 0))
	table.insert(lines, "单位远程攻击: "..tostring(results.defenseActions or 0))
	table.insert(lines, "城市炮击: "..tostring(results.cityStrikes or 0))
	table.insert(lines, "待命姿态命令: "..tostring(results.idlePosture or 0))
	table.insert(lines, "可行动作战单位: "..tostring(SC_CountIdleCombatUnits(player)))
	table.insert(lines, "快乐: "..tostring(SC_GetSafeNumber(function() return player:GetExcessHappiness() end, 0)))
	table.insert(lines, "国库: "..tostring(SC_GetSafeNumber(function() return player:GetGold() end, 0)))
	if atWar then
		table.insert(lines, "战争状态: 正在与 "..table.concat(enemies, ", ").." 交战")
	else
		table.insert(lines, "战争状态: 和平")
	end
	if #cityDetails > 0 then
		table.insert(lines, "最近城市安排:")
		for i = 1, math.min(#cityDetails, 6), 1 do
			table.insert(lines, cityDetails[i])
		end
	end
	local pendingLines = SC_GetPendingDecisionLines(player)
	if #pendingLines > 0 then
		table.insert(lines, "待处理事项:")
		for i = 1, math.min(#pendingLines, 5), 1 do
			table.insert(lines, pendingLines[i])
		end
	end
	
	SC_SendNotification(player, "战略指挥部", table.concat(lines, "[NEWLINE]"))
end

local function SC_SendNationalBriefNow(player, results, cityDetails, atWar)
	if player == nil then
		return
	end
	local oldBrief = SC_GetConfig("NationalBrief", true)
	local oldInterval = SC_GetConfig("InterventionInterval", 10)
	SC_CONFIG.NationalBrief = true
	SC_CONFIG.InterventionInterval = 1
	SC_SendNationalBrief(player, results or {}, cityDetails or {}, atWar)
	SC_CONFIG.InterventionInterval = oldInterval
	SC_CONFIG.NationalBrief = oldBrief
end

local function SC_GetDoctrineDisplayName(doctrine)
	if doctrine == "SCIENCE" then
		return "科研"
	elseif doctrine == "INDUSTRY" then
		return "工业"
	elseif doctrine == "WAR" then
		return "战争"
	end
	return "均衡"
end

local function SC_OnPlayerDoTurnUnsafe(playerID)
	-- Disabled by the v1.1 command layer below; kept only so the earlier event
	-- registration remains harmless if Civ5 has already bound it.
	return
end

local function SC_OnPlayerDoTurn(playerID)
	local ok, err = pcall(function()
		SC_OnPlayerDoTurnUnsafe(playerID)
	end)
	if not ok then
		SC_Log("PlayerDoTurn failed: "..tostring(err))
	end
end
-- V3 registers the single active turn driver near the end of this file.
-- Keeping the original v1.0 handler registered would execute a second planner.

local function SC_GetActiveHuman()
	local playerID = Game.GetActivePlayer()
	local player = Players[playerID]
	if player ~= nil and player:IsHuman() and player:IsAlive() then
		return player
	end
	return nil
end

local function SC_SetLabel(control, text)
	if control ~= nil then
		local ok = pcall(function() control:SetText(text) end)
		if not ok then
			pcall(function() control:LocalizeAndSetText(text) end)
		end
	end
end

local function SC_UpdatePanel()
	if Controls == nil then
		return
	end
	local player = SC_GetActiveHuman()
	local atWar = SC_PlayerAtWar(player)
	local function boolText(key)
		if SC_GetConfig(key, false) then
			return "开"
		end
		return "关"
	end
	
	SC_SetLabel(Controls.DoctrineLabel, SC_GetDoctrineDisplayName(SC_GetConfig("Doctrine", "BALANCED")))
	SC_SetLabel(Controls.ResearchAutomationLabel, "自动科研："..boolText("AutoResearch"))
	SC_SetLabel(Controls.CityAutomationLabel, "自动城市生产："..boolText("AutoCityProduction"))
	SC_SetLabel(Controls.DefenseAutomationLabel, "自动本土防御："..boolText("AutoLocalDefense"))
	SC_SetLabel(Controls.CityStrikeAutomationLabel, "自动城市炮击："..boolText("AutoCityRangedStrike"))
	SC_SetLabel(Controls.UpgradeAutomationLabel, "自动单位升级："..boolText("AutoUpgradeUnits"))
	SC_SetLabel(Controls.HealAutomationLabel, "自动伤兵治疗："..boolText("AutoHealDamagedUnits"))
	SC_SetLabel(Controls.IdlePostureAutomationLabel, "自动待命姿态："..boolText("AutoIdlePosture"))
	if player ~= nil then
		local status = "城市: "..tostring(player:GetNumCities())
		status = status.."   国库: "..tostring(SC_GetSafeNumber(function() return player:GetGold() end, 0))
		status = status.."[NEWLINE]可行动作战单位: "..tostring(SC_CountIdleCombatUnits(player))
		status = status.."   空生产队列: "..tostring(SC_CountEmptyCityQueues(player))
		if atWar then
			status = status.."[NEWLINE]战争状态: 战争中"
		else
			status = status.."[NEWLINE]战争状态: 和平"
		end
		SC_SetLabel(Controls.StatusLabel, status)
	else
		SC_SetLabel(Controls.StatusLabel, "没有有效的人类玩家。")
	end
end

local function SC_TogglePanel()
	if Controls == nil or Controls.MainPanel == nil then
		return
	end
	Controls.MainPanel:SetHide(not Controls.MainPanel:IsHidden())
	SC_UpdatePanel()
end

local function SC_ClosePanel()
	if Controls ~= nil and Controls.MainPanel ~= nil then
		Controls.MainPanel:SetHide(true)
	end
end

local function SC_SetDoctrine(doctrine)
	SC_CONFIG.Doctrine = doctrine
	SC_UpdatePanel()
end

local function SC_ToggleCityAutomation()
	SC_CONFIG.AutoCityProduction = not SC_GetConfig("AutoCityProduction", false)
	SC_UpdatePanel()
end

local function SC_ToggleDefenseAutomation()
	SC_CONFIG.AutoLocalDefense = not SC_GetConfig("AutoLocalDefense", false)
	SC_UpdatePanel()
end

local function SC_RunOnce()
	local player = SC_GetActiveHuman()
	if player == nil then
		return
	end
	local atWar = SC_PlayerAtWar(player)
	local oldCityAutomation = SC_GetConfig("AutoCityProduction", false)
	local oldDefenseAutomation = SC_GetConfig("AutoLocalDefense", false)
	SC_CONFIG.AutoCityProduction = true
	SC_CONFIG.AutoLocalDefense = true
	local cityOrders, cityDetails = SC_AutomateCities(player, atWar)
	local defenseActions = SC_AutomateAirSuperiority(player, atWar) + SC_AutomateLocalDefense(player, atWar)
	SC_CONFIG.AutoCityProduction = oldCityAutomation
	SC_CONFIG.AutoLocalDefense = oldDefenseAutomation
	SC_SendNotification(player, "战略指挥部", "手动执行完成[NEWLINE]城市安排: "..tostring(cityOrders).."[NEWLINE]远程反击: "..tostring(defenseActions))
	SC_UpdatePanel()
end

local function SC_BriefNow()
	local player = SC_GetActiveHuman()
	if player == nil then
		return
	end
	SC_SendNationalBriefNow(player, 0, 0, {}, SC_PlayerAtWar(player))
	SC_UpdatePanel()
end

local function SC_UpdatePanel()
	if Controls == nil then
		return
	end
	local player = SC_GetActiveHuman()
	local atWar = SC_PlayerAtWar(player)
	local function boolText(key)
		if SC_GetConfig(key, false) then
			return "开"
		end
		return "关"
	end
	
	SC_SetLabel(Controls.DoctrineLabel, SC_GetDoctrineDisplayName(SC_GetConfig("Doctrine", "BALANCED")))
	SC_SetLabel(Controls.ResearchAutomationLabel, "自动科研："..boolText("AutoResearch"))
	SC_SetLabel(Controls.CityAutomationLabel, "自动城市生产："..boolText("AutoCityProduction"))
	SC_SetLabel(Controls.DefenseAutomationLabel, "自动本土防御："..boolText("AutoLocalDefense"))
	SC_SetLabel(Controls.CityStrikeAutomationLabel, "自动城市炮击："..boolText("AutoCityRangedStrike"))
	SC_SetLabel(Controls.UpgradeAutomationLabel, "自动单位升级："..boolText("AutoUpgradeUnits"))
	SC_SetLabel(Controls.HealAutomationLabel, "自动伤兵治疗："..boolText("AutoHealDamagedUnits"))
	SC_SetLabel(Controls.IdlePostureAutomationLabel, "自动待命姿态："..boolText("AutoIdlePosture"))
	if player ~= nil then
		local status = "城市: "..tostring(player:GetNumCities())
		status = status.."   国库: "..tostring(SC_GetSafeNumber(function() return player:GetGold() end, 0))
		status = status.."[NEWLINE]可行动作战单位: "..tostring(SC_CountIdleCombatUnits(player))
		status = status.."   空生产队列: "..tostring(SC_CountEmptyCityQueues(player))
		if atWar then
			status = status.."[NEWLINE]战争状态: 战争中"
		else
			status = status.."[NEWLINE]战争状态: 和平"
		end
		SC_SetLabel(Controls.StatusLabel, status)
	else
		SC_SetLabel(Controls.StatusLabel, "没有有效的人类玩家。")
	end
end

local function SC_ToggleResearchAutomation()
	SC_CONFIG.AutoResearch = not SC_GetConfig("AutoResearch", false)
	SC_UpdatePanel()
end

local function SC_ToggleCityStrikeAutomation()
	SC_CONFIG.AutoCityRangedStrike = not SC_GetConfig("AutoCityRangedStrike", false)
	SC_UpdatePanel()
end

local function SC_ToggleUpgradeAutomation()
	SC_CONFIG.AutoUpgradeUnits = not SC_GetConfig("AutoUpgradeUnits", false)
	SC_UpdatePanel()
end

local function SC_ToggleHealAutomation()
	SC_CONFIG.AutoHealDamagedUnits = not SC_GetConfig("AutoHealDamagedUnits", false)
	SC_UpdatePanel()
end

local function SC_ToggleIdlePostureAutomation()
	SC_CONFIG.AutoIdlePosture = not SC_GetConfig("AutoIdlePosture", false)
	SC_UpdatePanel()
end

local function SC_RunOnce()
	local player = SC_GetActiveHuman()
	if player == nil then
		return
	end
	local atWar = SC_PlayerAtWar(player)
	local oldCityAutomation = SC_GetConfig("AutoCityProduction", false)
	local oldDefenseAutomation = SC_GetConfig("AutoLocalDefense", false)
	local oldResearchAutomation = SC_GetConfig("AutoResearch", false)
	local oldCityStrikeAutomation = SC_GetConfig("AutoCityRangedStrike", false)
	local oldUpgradeAutomation = SC_GetConfig("AutoUpgradeUnits", false)
	local oldHealAutomation = SC_GetConfig("AutoHealDamagedUnits", false)
	local oldIdlePostureAutomation = SC_GetConfig("AutoIdlePosture", false)
	SC_CONFIG.AutoCityProduction = true
	SC_CONFIG.AutoLocalDefense = true
	SC_CONFIG.AutoResearch = true
	SC_CONFIG.AutoCityRangedStrike = true
	SC_CONFIG.AutoUpgradeUnits = true
	SC_CONFIG.AutoHealDamagedUnits = true
	SC_CONFIG.AutoIdlePosture = true
	local results, cityDetails = SC_RunV3Once(player, atWar, "manual-legacy-ui")
	SC_CONFIG.AutoCityProduction = oldCityAutomation
	SC_CONFIG.AutoLocalDefense = oldDefenseAutomation
	SC_CONFIG.AutoResearch = oldResearchAutomation
	SC_CONFIG.AutoCityRangedStrike = oldCityStrikeAutomation
	SC_CONFIG.AutoUpgradeUnits = oldUpgradeAutomation
	SC_CONFIG.AutoHealDamagedUnits = oldHealAutomation
	SC_CONFIG.AutoIdlePosture = oldIdlePostureAutomation
	SC_SendNotification(player, "战略指挥部", "手动执行完成[NEWLINE]城市安排: "..tostring(results.cityOrders or 0).."[NEWLINE]科研选择: "..tostring(results.research or 0).."[NEWLINE]单位升级: "..tostring(results.upgrades or 0).."[NEWLINE]治疗命令: "..tostring(results.heals or 0).."[NEWLINE]单位远程攻击: "..tostring(results.defenseActions or 0).."[NEWLINE]城市炮击: "..tostring(results.cityStrikes or 0).."[NEWLINE]待命姿态命令: "..tostring(results.idlePosture or 0))
	SC_SendNationalBriefNow(player, results, cityDetails, atWar)
	SC_UpdatePanel()
end

local function SC_BriefNow()
	local player = SC_GetActiveHuman()
	if player == nil then
		return
	end
	SC_SendNationalBriefNow(player, {}, {}, SC_PlayerAtWar(player))
	SC_UpdatePanel()
end

local function SC_OpenTechTree()
	Events.SerialEventGameMessagePopup({ Type = ButtonPopupTypes.BUTTONPOPUP_TECH_TREE, Data2 = -1 })
end

local function SC_OpenPolicies()
	Events.SerialEventGameMessagePopup({ Type = ButtonPopupTypes.BUTTONPOPUP_CHOOSEPOLICY })
end

-- v1.1 command layer: these definitions replace the first conservative pass above.
local SC_LAST_POPUPS_HANDLED = 0
local SC_LAST_DIPLO_HANDLED = 0

local function SC_GameInfoRows(tableName, filter)
	if GameInfo == nil or GameInfo[tableName] == nil then
		return function() return nil end
	end
	return GameInfo[tableName](filter)
end

local function SC_GetBuildingFlavorScore(buildingType, wanted)
	local score = 0
	for row in SC_GameInfoRows("Building_Flavors", {BuildingType = buildingType}) do
		local weight = wanted[row.FlavorType] or 0
		score = score + weight * (row.Flavor or 0)
	end
	for row in SC_GameInfoRows("Building_YieldChanges", {BuildingType = buildingType}) do
		local weight = wanted[row.YieldType] or 0
		score = score + weight * (row.Yield or 0) * 4
	end
	for row in SC_GameInfoRows("Building_YieldModifiers", {BuildingType = buildingType}) do
		local weight = wanted[row.YieldType] or 0
		score = score + weight * (row.Yield or 0) / 4
	end
	return score
end

local function SC_GetWantedBuildingWeights(player, city, atWar)
	local doctrine = SC_GetConfig("Doctrine", "BALANCED")
	local economy = SC_GetConfig("EconomyProfile", "BALANCED")
	local build = SC_GetConfig("BuildProfile", "INFRASTRUCTURE")
	local production = SC_GetConfig("ProductionProfile", "BUILDINGS")
	local happiness = SC_GetSafeNumber(function() return player:GetExcessHappiness() end, 10)
	local weights = {
		FLAVOR_PRODUCTION = 7, FLAVOR_SCIENCE = 7, FLAVOR_GOLD = 4,
		FLAVOR_GROWTH = 4, FLAVOR_CULTURE = 3, FLAVOR_HAPPINESS = 5,
		FLAVOR_CITY_DEFENSE = 2, FLAVOR_MILITARY_TRAINING = 2,
		YIELD_PRODUCTION = 8, YIELD_SCIENCE = 8, YIELD_GOLD = 4,
		YIELD_FOOD = 4, YIELD_CULTURE = 3, YIELD_FAITH = 2
	}
	if happiness < 5 then
		weights.FLAVOR_HAPPINESS = 20
	end
	if economy == "SCIENCE" then
		weights.FLAVOR_SCIENCE = weights.FLAVOR_SCIENCE + 10
		weights.YIELD_SCIENCE = weights.YIELD_SCIENCE + 10
	elseif economy == "TREASURY" then
		weights.FLAVOR_GOLD = weights.FLAVOR_GOLD + 14
		weights.YIELD_GOLD = weights.YIELD_GOLD + 14
	elseif economy == "EXPANSION" then
		weights.FLAVOR_GROWTH = weights.FLAVOR_GROWTH + 12
		weights.YIELD_FOOD = weights.YIELD_FOOD + 12
		weights.FLAVOR_PRODUCTION = weights.FLAVOR_PRODUCTION + 6
	end
	if build == "HAPPINESS" then
		weights.FLAVOR_HAPPINESS = weights.FLAVOR_HAPPINESS + 18
	elseif build == "SCIENCE" then
		weights.FLAVOR_SCIENCE = weights.FLAVOR_SCIENCE + 14
		weights.YIELD_SCIENCE = weights.YIELD_SCIENCE + 14
	elseif build == "DEFENSE" then
		weights.FLAVOR_CITY_DEFENSE = weights.FLAVOR_CITY_DEFENSE + 18
		weights.FLAVOR_MILITARY_TRAINING = weights.FLAVOR_MILITARY_TRAINING + 8
	elseif build == "INFRASTRUCTURE" then
		weights.FLAVOR_PRODUCTION = weights.FLAVOR_PRODUCTION + 12
		weights.YIELD_PRODUCTION = weights.YIELD_PRODUCTION + 12
		weights.FLAVOR_GROWTH = weights.FLAVOR_GROWTH + 5
	end
	if production == "MILITARY" or production == "AIRSEA" then
		weights.FLAVOR_MILITARY_TRAINING = weights.FLAVOR_MILITARY_TRAINING + 14
		weights.FLAVOR_CITY_DEFENSE = weights.FLAVOR_CITY_DEFENSE + 8
	elseif production == "WONDERS" then
		weights.FLAVOR_PRODUCTION = weights.FLAVOR_PRODUCTION + 10
		weights.YIELD_PRODUCTION = weights.YIELD_PRODUCTION + 10
	end
	if atWar or doctrine == "WAR" then
		weights.FLAVOR_CITY_DEFENSE = math.max(weights.FLAVOR_CITY_DEFENSE, 12)
		weights.FLAVOR_MILITARY_TRAINING = math.max(weights.FLAVOR_MILITARY_TRAINING, 10)
	end
	if doctrine == "SCIENCE" then
		weights.FLAVOR_SCIENCE = 18
		weights.YIELD_SCIENCE = 18
	elseif doctrine == "INDUSTRY" then
		weights.FLAVOR_PRODUCTION = 18
		weights.YIELD_PRODUCTION = 18
	elseif doctrine == "WAR" then
		weights.FLAVOR_MILITARY_TRAINING = 16
		weights.FLAVOR_CITY_DEFENSE = 14
	end
	if SC_StrategyAdjustBuildingWeights ~= nil then
		weights = SC_StrategyAdjustBuildingWeights(city, weights) or weights
	end
	return weights
end

function SC_GetBuildingReservationKey(city, building)
	if city == nil or building == nil then
		return nil, false
	end
	local buildingClass = nil
	pcall(function() buildingClass = GameInfo.BuildingClasses[building.BuildingClass] end)
	local unique = buildingClass ~= nil and (
		SC_DBNumber(buildingClass.MaxGlobalInstances, -1) == 1
		or SC_DBNumber(buildingClass.MaxPlayerInstances, -1) == 1
		or SC_DBNumber(buildingClass.MaxTeamInstances, -1) == 1)
	if unique then
		return "X:B:"..tostring(building.ID), true
	end
	local cityID = SC_GetSafeNumber(function() return city:GetID() end, -1)
	return "C:"..tostring(cityID)..":B:"..tostring(building.ID), false
end

function SC_PruneLegacyV135ProductionOrders(city)
	if city == nil then
		return 0
	end
	local cityKey = tostring(SC_GetSafeNumber(function() return city:GetOwner() end, -1)).."|"..tostring(SC_GetSafeNumber(function() return city:GetID() end, -1))
	if SC_LEGACY_QUEUE_PRUNED[cityKey] then
		return 0
	end
	SC_LEGACY_QUEUE_PRUNED[cityKey] = true
	local queueLength = SC_GetSafeNumber(function() return city:GetOrderQueueLength() end, 0)
	if queueLength <= 0 then
		return 0
	end
	local kept = {}
	local removed = 0
	local removedTypes = {}
	for index = 0, queueLength - 1, 1 do
		local orderType, data1, data2, save, rush = nil, nil, nil, nil, nil
		local ok = pcall(function()
			orderType, data1, data2, save, rush = city:GetOrderFromQueue(index)
		end)
		if ok then
			local remove = false
			if OrderTypes ~= nil and orderType == OrderTypes.ORDER_TRAIN and data1 ~= nil then
				local unitInfo = GameInfo.Units[data1]
				local unitType = unitInfo ~= nil and unitInfo.Type or ""
				remove = unitType == "UNIT_GREAT_WAR_INFANTRY" or unitType == "UNIT_CARRIER"
				if remove then
					removed = removed + 1
					table.insert(removedTypes, unitType)
				end
			end
			if not remove then
				table.insert(kept, { orderType = orderType, data1 = data1, data2 = data2, save = save, rush = rush })
			end
		end
	end
	if removed <= 0 then
		return 0
	end
	local cleared = pcall(function() city:ClearOrderQueue() end)
	if not cleared then
		SC_Debug("cityProduction legacy-prune failed city="..tostring(city:GetName()).." reason=clear-failed removed="..tostring(removed))
		return 0
	end
	local restored = 0
	for _, order in ipairs(kept) do
		local pushed = pcall(function()
			city:PushOrder(order.orderType, order.data1, order.data2 or -1, order.save or 0, order.rush or false, false)
		end)
		if not pushed then
			pushed = SC_PushCityOrder(city, order.orderType, order.data1)
		end
		if pushed then restored = restored + 1 end
	end
	SC_Debug("cityProduction legacy-prune city="..tostring(city:GetName()).." removed="..tostring(removed).." types="..table.concat(removedTypes, ",").." kept="..tostring(#kept).." restored="..tostring(restored))
	return removed
end

function SC_GetBestEliteProject(player, city, atWar, reservedOrders)
	if player == nil or city == nil or not SC_GetConfig("AutoElitePrograms", true) or GameInfo == nil or GameInfo.Projects == nil then
		return nil, -999999, 0, "disabled"
	end
	local queuedTotal = reservedOrders ~= nil and SC_DBNumber(reservedOrders["ELITE_PROJECT_TOTAL"], 0) or 0
	if queuedTotal >= SC_GetConfig("MaxQueuedEliteProjects", 2) then
		return nil, -999999, 0, "project-queue-cap:"..tostring(queuedTotal)
	end
	local queueLength = SC_GetSafeNumber(function() return city:GetOrderQueueLength() end, 0)
	for index = 0, queueLength - 1, 1 do
		local orderType, data1 = nil, nil
		pcall(function() orderType, data1 = city:GetOrderFromQueue(index) end)
		if OrderTypes ~= nil and orderType == OrderTypes.ORDER_CREATE and data1 ~= nil then
			local queuedProject = GameInfo.Projects[data1]
			if queuedProject ~= nil and #SC_GetEliteProjectUnits(queuedProject.Type) > 0 then
				return nil, -999999, 0, "city-project-slot"
			end
		end
	end
	local playerEraRank = SC_GetPlayerEraRankForCity(city)
	local bestProjectID = nil
	local bestScore = -999999
	local bestReason = "none"
	local candidates = 0
	local excluded = {}
	for projectInfo in GameInfo.Projects() do
		local reserveKey = "X:P:"..tostring(projectInfo.ID)
		if SC_DBNumber(projectInfo.MaxGlobalInstances, -1) == 1
			and (reservedOrders == nil or not reservedOrders[reserveKey])
			and SC_CityCanCreate(city, projectInfo.ID) then
			local unlockedUnits = SC_GetEliteProjectUnits(projectInfo.Type)
			local projectBestScore = -999999
			local projectBestUnit = nil
			for _, unitInfo in ipairs(unlockedUnits) do
				local relevant = SC_IsEliteUnitEraRelevant(playerEraRank, unitInfo, player)
				local investment, investmentReason = 1, "legacy"
				if SC5 then investment, investmentReason = SC5.ElitePlanValue(player, city, unitInfo, reservedOrders, true) end
				if not investment then excluded[investmentReason] = (excluded[investmentReason] or 0) + 1 end
				if relevant and investment then
					local score = SC_GetEliteUnitStrategicScore(unitInfo, playerEraRank, atWar) * investment
					if score > projectBestScore then
						projectBestScore = score
						projectBestUnit = unitInfo
					end
				end
			end
			if projectBestUnit ~= nil and projectBestScore >= SC_GetConfig("EliteProjectMinScore", 600) then
				candidates = candidates + 1
				local score = projectBestScore - math.max(SC_DBNumber(projectInfo.Cost, 0), 0) / 5
				if score > bestScore then
					bestScore = score
					bestProjectID = projectInfo.ID
					bestReason = "unlocks="..tostring(projectBestUnit.Type).." unitScore="..tostring(math.floor(projectBestScore)).." projectCost="..tostring(projectInfo.Cost).." playerEra="..tostring(playerEraRank)
				end
			end
		end
	end
	if SC5 and next(excluded) then SC_Debug("decision5 elite-project-filter city="..city:GetID().." excluded="..SC5.FactText(excluded)) end
	return bestProjectID, bestScore, candidates, bestReason
end

function SC_SeedProductionReservations(player)
	local reserved = {}
	if player == nil then
		return reserved
	end
	for city in player:Cities() do
		reserved["CITY_TOTAL"] = SC_DBNumber(reserved["CITY_TOTAL"], 0) + 1
		local queueLength = SC_GetSafeNumber(function() return city:GetOrderQueueLength() end, 0)
		for index = 0, queueLength - 1, 1 do
			local orderType = nil
			local data1 = nil
			pcall(function() orderType, data1 = city:GetOrderFromQueue(index) end)
			if OrderTypes ~= nil and orderType == OrderTypes.ORDER_CONSTRUCT and data1 ~= nil then
				local building = GameInfo.Buildings[data1]
				local reserveKey, unique = SC_GetBuildingReservationKey(city, building)
				if unique and reserveKey ~= nil then
					reserved[reserveKey] = true
				end
			elseif OrderTypes ~= nil and orderType == OrderTypes.ORDER_CREATE and data1 ~= nil then
				local projectInfo = GameInfo.Projects[data1]
				if projectInfo ~= nil then
					reserved["X:P:"..tostring(data1)] = true
					if #SC_GetEliteProjectUnits(projectInfo.Type) > 0 then
						reserved["ELITE_PROJECT_TOTAL"] = SC_DBNumber(reserved["ELITE_PROJECT_TOTAL"], 0) + 1
					end
				end
			elseif OrderTypes ~= nil and orderType == OrderTypes.ORDER_TRAIN and data1 ~= nil then
				local unitInfo = GameInfo.Units[data1]
				local needKey = SC_GetProductionNeedForUnitInfo(unitInfo)
				if unitInfo ~= nil and unitInfo.DefaultUnitAI == "UNITAI_SETTLE" then reserved["CIVILIAN:settler"] = SC_DBNumber(reserved["CIVILIAN:settler"], 0) + 1 end
				if unitInfo ~= nil and unitInfo.DefaultUnitAI == "UNITAI_WORKER" then reserved["CIVILIAN:worker"] = SC_DBNumber(reserved["CIVILIAN:worker"], 0) + 1 end
				local unitReserveKey = "U:"..tostring(data1)
				reserved[unitReserveKey] = SC_DBNumber(reserved[unitReserveKey], 0) + 1
				if SC_IsEliteUnitInfo(unitInfo) then
					local eliteKey = "ELITE_UNIT:"..tostring(data1)
					reserved[eliteKey] = SC_DBNumber(reserved[eliteKey], 0) + 1
				end
				if needKey ~= nil then
					local needReserveKey = "NEED:"..needKey
					reserved[needReserveKey] = SC_DBNumber(reserved[needReserveKey], 0) + 1
				end
			elseif OrderTypes ~= nil and orderType == OrderTypes.ORDER_MAINTAIN then
				reserved["PROCESS_TOTAL"] = SC_DBNumber(reserved["PROCESS_TOTAL"], 0) + 1
			end
		end
	end
	return reserved
end

function SC_GetBestTrainableCivilian(city, civilianNeed)
	if city == nil or civilianNeed == nil then return nil, -999999 end
	local bestID, bestScore = nil, -999999
	for unitInfo in GameInfo.Units() do
		local matches = civilianNeed == "settler" and unitInfo.DefaultUnitAI == "UNITAI_SETTLE"
			or civilianNeed == "worker" and unitInfo.DefaultUnitAI == "UNITAI_WORKER"
		if matches and SC_CityCanTrain(city, unitInfo.ID) then
			local score = SC_DBNumber(unitInfo.Moves, 0) * 35 + SC_DBNumber(unitInfo.WorkRate, 0) * 2 - math.max(SC_DBNumber(unitInfo.Cost, 0), 0) / 8
			if score > bestScore then bestID, bestScore = unitInfo.ID, score end
		end
	end
	return bestID, bestScore
end

function SC_CountCityQueuedTrainOrders(city)
	if city == nil then
		return 0
	end
	local queueLength = SC_GetSafeNumber(function() return city:GetOrderQueueLength() end, 0)
	local count = 0
	for index = 0, queueLength - 1, 1 do
		local orderType = nil
		pcall(function() orderType = city:GetOrderFromQueue(index) end)
		if OrderTypes ~= nil and orderType == OrderTypes.ORDER_TRAIN then
			count = count + 1
		end
	end
	return count
end

local function SC_GetBestConstructibleBuilding(player, city, atWar, reservedOrders, candidateFilter)
	local bestID = nil
	local bestScore = -999999
	local bestIsWonder = false
	local bestReserveKey = nil
	local bestIsUnique = false
	local candidateCount = 0
	local reservedCount = 0
	local ranked = {}
	local wanted = SC_GetWantedBuildingWeights(player, city, atWar)
	local production = SC_GetConfig("ProductionProfile", "BUILDINGS")
	for building in GameInfo.Buildings() do
		local reserveKey, isUnique = SC_GetBuildingReservationKey(city, building)
		if reservedOrders ~= nil and reservedOrders[reserveKey] then
			reservedCount = reservedCount + 1
		elseif (candidateFilter == nil or candidateFilter(player, city, building)) and SC_CityCanConstruct(city, building.ID) then
			candidateCount = candidateCount + 1
			local score = 10 + SC_GetBuildingFlavorScore(building.Type, wanted)
			score = score + (building.Happiness or 0) * wanted.FLAVOR_HAPPINESS
			score = score + (building.Defense or 0) / 40
			score = score + (building.Experience or 0) / 2
			score = score - math.max(building.Cost or 0, 0) / 120
			score = score - (building.GoldMaintenance or 0) * 8
			local strategyReason = "legacy"
			if SC_StrategyScoreBuilding ~= nil then
				score, strategyReason = SC_StrategyScoreBuilding(player, city, building, score)
			end
			local isWonder = false
			local buildingClass = nil
			pcall(function() buildingClass = GameInfo.BuildingClasses[building.BuildingClass] end)
			if buildingClass ~= nil and buildingClass.MaxGlobalInstances == 1 then
				isWonder = true
			end
			if isWonder then
				score = score + 18
				if production == "WONDERS" then
					score = score + 120
				end
			end
			if building.ConquestProb == 0 and (building.Cost or 0) <= 1 then
				score = score - 100
			end
			ranked[#ranked + 1] = { type = building.Type, score = score, reason = strategyReason }
			if score > bestScore then
				bestScore = score
				bestID = building.ID
				bestIsWonder = isWonder
				bestReserveKey = reserveKey
				bestIsUnique = isUnique
			end
		end
	end
	if SC5 then
		table.sort(ranked, function(a, b) if a.score == b.score then return a.type < b.type end; return a.score > b.score end)
		local parts = {}
		for i = 1, math.min(#ranked, 3) do
			local c = ranked[i]
			parts[#parts + 1] = c.type..":"..math.floor(c.score).."["..c.reason.."]"
		end
		SC_Debug("decision5 buildings city="..city:GetID().." legal="..candidateCount.." reserved="..reservedCount
			.." selected="..tostring(bestID).." top="..table.concat(parts, ";"))
	end
	return bestID, bestScore, candidateCount, bestIsWonder, reservedCount, bestReserveKey, bestIsUnique
end

function SC_CityCanPurchaseBuildingGold(city, buildingID, requireAffordable)
	if city == nil or buildingID == nil or YieldTypes == nil or YieldTypes.YIELD_GOLD == nil then return false end
	local canPurchase = false
	local ok = pcall(function()
		canPurchase = city:IsCanPurchase(requireAffordable == true, requireAffordable == true, -1, buildingID, -1, YieldTypes.YIELD_GOLD)
	end)
	return ok and canPurchase
end

function SC_GetCapitalBuildingCandidate(player, city, atWar, budgetLeft)
	if SC5 then SC5.cityEconomy[player:GetID()..":"..city:GetID()] = nil end
	local best = nil
	local wanted = SC_GetWantedBuildingWeights(player, city, atWar)
	local candidateCount = 0
	local rejectedBudget = 0
	for building in GameInfo.Buildings() do
		if SC_CityCanPurchaseBuildingGold(city, building.ID, false) then
			local cost = SC_GetSafeNumber(function() return city:GetBuildingPurchaseCost(building.ID) end, -1)
			if cost > 0 and cost <= budgetLeft and SC_CityCanPurchaseBuildingGold(city, building.ID, true) then
				candidateCount = candidateCount + 1
				local score = 10 + SC_GetBuildingFlavorScore(building.Type, wanted)
				score = score + SC_DBNumber(building.Happiness, 0) * SC_DBNumber(wanted.FLAVOR_HAPPINESS, 0)
				score = score + SC_DBNumber(building.Defense, 0) / 40
				score = score + SC_DBNumber(building.Experience, 0) / 2
				score = score - SC_DBNumber(building.GoldMaintenance, 0) * 8
				local strategyReason = "legacy"
				if SC_StrategyScoreBuilding ~= nil then score, strategyReason = SC_StrategyScoreBuilding(player, city, building, score, true) end
				local occupied = SC_GetSafeNumber(function() return city:IsOccupied() and 1 or 0 end, 0) > 0
				local removesOccupation = building.NoOccupiedUnhappiness == true or SC_DBNumber(building.NoOccupiedUnhappiness, 0) == 1
				if occupied and removesOccupation then score = score + 4000 end
				score = score - cost / 100
				if best == nil or score > best.score then
					best = { city = city, building = building, cost = cost, score = score, reason = strategyReason }
				end
			elseif cost > budgetLeft then
				rejectedBudget = rejectedBudget + 1
			end
		end
	end
	return best, candidateCount, rejectedBudget
end

function SC_AutomateCapitalDeployment(player, atWar)
	if player == nil then return 0 end
	local playerID = SC_GetSafeNumber(function() return player:GetID() end, -1)
	local turn = SC_GetSafeNumber(function() return Game.GetGameTurn() end, -1)
	if SC_CAPITAL_DEPLOYMENT_TURN[playerID] == turn then return 0 end
	SC_CAPITAL_DEPLOYMENT_TURN[playerID] = turn
	if SC_StrategyBuildPlan ~= nil then pcall(function() SC_StrategyBuildPlan(player, atWar, false) end) end
	local national = SC_StrategyGetNationalPlan ~= nil and SC_StrategyGetNationalPlan() or nil
	local gold = SC_GetSafeNumber(function() return player:GetGold() end, 0)
	local goldRate = SC_GetSafeNumber(function() return player:CalculateGoldRate() end, 0)
	local happiness = SC_GetSafeNumber(function() return player:GetExcessHappiness() end, 0)
	local cityCount = math.max(SC_GetSafeNumber(function() return player:GetNumCities() end, 1), 1)
	local reserve = national ~= nil and SC_DBNumber(national.reserveGold, 0) or math.max(cityCount * 2500, SC_GetConfig("MilitaryPurchaseMinimumGold", 75000))
	local spendable = math.max(0, gold - reserve)
	local minimumSurplus = SC_GetConfig("CapitalDeploymentMinimumSurplus", 50000)
	local minimumIncome = SC_GetConfig("CapitalDeploymentMinimumGoldRate", 25)
	local minimumHappiness = SC_GetConfig("CapitalDeploymentMinimumHappiness", 5)
	local deficitRunway = goldRate < 0 and spendable / math.max(-goldRate, 1) or 9999
	local financiallyReady = spendable >= minimumSurplus
		and (goldRate >= minimumIncome or deficitRunway >= SC_GetConfig("CapitalDeploymentDeficitRunwayTurns", 40))
	if not financiallyReady then
		SC_Debug("capitalDeployment skip reason=threshold gold="..tostring(gold).." spendable="..tostring(spendable)..
			" goldRate="..tostring(goldRate).." runway="..string.format("%.1f", deficitRunway)..
			" happiness="..tostring(happiness).." reserve="..tostring(reserve))
		return 0
	end
	SC_Debug("capitalDeployment begin gold="..tostring(gold).." spendable="..tostring(spendable)..
		" goldRate="..tostring(goldRate).." runway="..string.format("%.1f", deficitRunway)..
		" happiness="..tostring(happiness).." reserve="..tostring(reserve))

	local actions = 0
	local annexed = {}
	local annexedCount = 0
	local mayNotAnnex = SC_GetSafeNumber(function() return player:MayNotAnnex() and 1 or 0 end, 0) > 0
	if SC_GetConfig("AutoAnnexPuppetsWhenRich", true) and not mayNotAnnex then
		local candidates = {}
		local minimumPopulation = SC_GetConfig("CapitalAnnexMinimumPopulation", 5)
		local focusPlot = nil
		pcall(function() focusPlot = SC_GetDecapitationFocusPlot(player) end)
		for city in player:Cities() do
			if city:IsPuppet() and not city:IsResistance() then
				local population = SC_GetSafeNumber(function() return city:GetPopulation() end, 1)
				if population >= minimumPopulation then
					local score = population * 80
					score = score + SC_GetSafeNumber(function() return city:GetYieldRate(YieldTypes.YIELD_PRODUCTION) end, 0) * 24
					score = score + SC_GetSafeNumber(function() return city:GetYieldRate(YieldTypes.YIELD_SCIENCE) end, 0) * 12
					score = score + SC_GetSafeNumber(function() return city:GetYieldRate(YieldTypes.YIELD_GOLD) end, 0) * 10
					if SC_GetSafeNumber(function() return city:IsCoastal() and 1 or 0 end, 0) > 0 then score = score + (atWar and 240 or 80) end
					local distance = 999
					if focusPlot ~= nil then
						local cityPlot = city:Plot()
						distance = Map.PlotDistance(cityPlot:GetX(), cityPlot:GetY(), focusPlot:GetX(), focusPlot:GetY())
						score = score + math.max(0, 500 - distance * 18)
					end
					table.insert(candidates, { city = city, population = population, score = score, distance = distance })
				end
			end
		end
		table.sort(candidates, function(a, b) return a.score > b.score end)
		local projectedHappiness = happiness
		local maxAnnex = SC_GetConfig("CapitalAnnexMaxPerTurn", 2)
		local crisisAnnex = happiness < SC_GetConfig("CapitalAnnexMinimumHappiness", 8)
			and SC_GetConfig("CapitalAnnexDuringCrisis", true)
			and spendable >= SC_GetConfig("CapitalCrisisAnnexMinimumSurplus", 250000)
		if crisisAnnex then maxAnnex = math.min(maxAnnex, SC_GetConfig("CapitalCrisisAnnexMaxPerTurn", 1)) end
		for _, candidate in ipairs(candidates) do
			if annexedCount >= maxAnnex then break end
			local projectedCost = math.max(1, math.ceil(candidate.population * SC_GetConfig("CapitalAnnexProjectedHappinessPerPopulation", 0.35)))
			if crisisAnnex or projectedHappiness - projectedCost >= SC_GetConfig("CapitalAnnexMinimumHappiness", 8) then
				local city = candidate.city
				local callOK, callError = pcall(function()
					Network.SendDoTask(city:GetID(), TaskTypes.TASK_ANNEX_PUPPET, -1, -1, false, false, false, false)
					city:SetPuppet(false)
					city:SetProductionAutomated(false)
					local puppetGovernment = GameInfoTypes["BUILDING_PUPPET_GOVERNEMENT"]
					local fullPuppetGovernment = GameInfoTypes["BUILDING_PUPPET_GOVERNEMENT_FULL"]
					if puppetGovernment ~= nil then city:SetNumRealBuilding(puppetGovernment, 0) end
					if fullPuppetGovernment ~= nil then city:SetNumRealBuilding(fullPuppetGovernment, 0) end
				end)
				local confirmed = not city:IsPuppet()
				if confirmed then
					local cityLevelOK, cityLevelError = true, nil
					if SetCityLevelbyDistance ~= nil then cityLevelOK, cityLevelError = pcall(function() SetCityLevelbyDistance(player, city) end) end
					projectedHappiness = projectedHappiness - projectedCost
					annexed[city:GetID()] = true
					annexedCount = annexedCount + 1
					actions = actions + 1
					SC_Debug("capitalAnnex success city="..tostring(city:GetName()).." population="..tostring(candidate.population)..
						" score="..tostring(math.floor(candidate.score)).." frontDistance="..tostring(candidate.distance)..
						" projectedHappiness="..tostring(projectedHappiness).." cityLevel="..(cityLevelOK and "updated" or "fallback")..
						(cityLevelError ~= nil and " cityLevelErr="..tostring(cityLevelError) or ""))
				else
					SC_Debug("capitalAnnex failure city="..tostring(city:GetName()).." callOK="..SC_BoolText(callOK).." err="..tostring(callError))
				end
			end
		end
		if #candidates > 0 and annexedCount == 0 then
			SC_Debug("capitalAnnex skip candidates="..tostring(#candidates).." reason=projected-happiness happiness="..tostring(happiness)..
				" crisisEligible="..SC_BoolText(crisisAnnex))
		end
	end

	if annexedCount > 0 and SC_StrategyInvalidate ~= nil then
		SC_StrategyInvalidate("capital-annex")
		pcall(function() SC_StrategyBuildPlan(player, atWar, true) end)
		national = SC_StrategyGetNationalPlan ~= nil and SC_StrategyGetNationalPlan() or national
		reserve = national ~= nil and SC_DBNumber(national.reserveGold, reserve) or reserve
	end
	local currentGold = SC_GetSafeNumber(function() return player:GetGold() end, gold)
	local buildingFraction = happiness < minimumHappiness
		and SC_GetConfig("CapitalRecoveryBuildingPurchaseFraction", 0.30)
		or SC_GetConfig("CapitalBuildingPurchaseFraction", 0.18)
	local buildingBudget = math.floor(math.max(0, currentGold - reserve) * buildingFraction)
	local minimumBuildingBudget = SC_GetConfig("CapitalBuildingPurchaseMinimumBudget", 1000)
	if buildingBudget >= minimumBuildingBudget then
		local cityCandidates = {}
		local rejectedBudget = 0
		for city in player:Cities() do
			if not city:IsPuppet() and not city:IsResistance() then
				local candidate, candidateCount, cityRejected = SC_GetCapitalBuildingCandidate(player, city, atWar, buildingBudget)
				rejectedBudget = rejectedBudget + cityRejected
				if candidate ~= nil and candidate.score >= SC_GetConfig("CapitalBuildingPurchaseMinimumScore", 80) then
					local cityID = city:GetID()
					candidate.cityPriority = (annexed[cityID] and 1600 or 0) +
						(SC_GetSafeNumber(function() return city:IsOccupied() and 1 or 0 end, 0) > 0 and 900 or 0) +
						SC_GetSafeNumber(function() return city:GetPopulation() end, 1) * 4
					candidate.candidateCount = candidateCount
					table.insert(cityCandidates, candidate)
				end
			end
		end
		table.sort(cityCandidates, function(a, b) return a.score + a.cityPriority > b.score + b.cityPriority end)
		local submitted = 0
		local spent = 0
		local maxPurchases = SC_GetConfig("CapitalBuildingPurchaseMaxPerTurn", 8)
		for _, candidate in ipairs(cityCandidates) do
			if submitted >= maxPurchases then break end
			if spent + candidate.cost <= buildingBudget and SC_CityCanPurchaseBuildingGold(candidate.city, candidate.building.ID, true) then
				local callOK, callError = pcall(function() Game.CityPurchaseBuilding(candidate.city, candidate.building.ID, YieldTypes.YIELD_GOLD) end)
				if callOK then
					submitted = submitted + 1
					spent = spent + candidate.cost
					actions = actions + 1
					SC_Debug("capitalBuildingPurchase success city="..tostring(candidate.city:GetName()).." item="..tostring(candidate.building.Type)..
						" cost="..tostring(candidate.cost).." score="..tostring(math.floor(candidate.score)).." reason="..tostring(candidate.reason)..
						" candidates="..tostring(candidate.candidateCount).." status=submitted")
				else
					SC_Debug("capitalBuildingPurchase failure city="..tostring(candidate.city:GetName()).." item="..tostring(candidate.building.Type).." err="..tostring(callError))
				end
			end
		end
		SC_Debug("capitalBuildingPurchase end submitted="..tostring(submitted).." spent="..tostring(spent).." budget="..tostring(buildingBudget)..
			" eligibleCities="..tostring(#cityCandidates).." budgetRejected="..tostring(rejectedBudget))
	end
	return actions
end

local function SC_ChooseCityProduction(player, city, atWar, reservedOrders)
	if city == nil or city:IsPuppet() or city:IsResistance() then
		return nil
	end
	local queueLength = SC_GetSafeNumber(function() return city:GetOrderQueueLength() end, 0)
	local cityName = "CITY"
	pcall(function() cityName = city:GetName() end)
	-- V3 owns asynchronous order confirmation.  The old per-turn submission
	-- flag could permanently lock a city that completed an item in the same turn.
	local function markSubmitted(category, item) end
	if queueLength > 0 then
		local orderType = nil
		pcall(function()
			orderType = city:GetOrderFromQueue(0)
		end)
		if orderType == OrderTypes.ORDER_MAINTAIN then
			local turn = SC_GetSafeNumber(function() return Game.GetGameTurn() end, 0)
			local interval = math.max(1, SC_GetConfig("ProcessReevaluationTurns", 5))
			if turn % interval ~= 0 then
				if SC_GetConfig("DebugCityProduction", true) then
					SC_Debug("cityProduction keep-process city="..tostring(cityName).." reason=reevaluation-not-due turn="..tostring(turn).." interval="..tostring(interval))
				end
				return nil
			end
			pcall(function() city:ClearOrderQueue() end)
			if SC_GetConfig("DebugCityProduction", true) then
				SC_Debug("cityProduction clear-maintain city="..tostring(cityName).." queueBefore="..tostring(queueLength).." reason=scheduled-reevaluation")
			end
			queueLength = SC_GetSafeNumber(function() return city:GetOrderQueueLength() end, 0)
		end
	end
	if queueLength >= SC_GetConfig("TargetCityQueueLength", SC_GetConfig("MinCityQueueLength", 1)) then
		if SC_GetConfig("DebugCityProduction", true) then
			SC_Debug("cityProduction skip city="..tostring(cityName).." reason=queue-full queue="..tostring(queueLength))
		end
		return nil
	end
	
	local production = SC_GetConfig("ProductionProfile", "BUILDINGS")
	local buildMilitary, militaryNeed, needDeficit, rosterDebug = SC_ShouldBuildMilitary(player, city, atWar, reservedOrders)
	if SC5 and SC5.NeedsEconomicRelief(player, city) then
		local buildingID, score, _, _, _, reserveKey = SC_GetBestConstructibleBuilding(player, city, atWar, reservedOrders, SC5.IsEconomicRelief)
		if buildingID and score > 0 and SC_PushCityOrder(city, OrderTypes.ORDER_CONSTRUCT, buildingID) then
			local info = GameInfo.Buildings[buildingID]
			SC_Debug("cityProduction choose city="..cityName.." category=economic-recovery item="..info.Type.." score="..score)
			return info.Type, reserveKey
		end
	end
	local processCount = reservedOrders ~= nil and SC_DBNumber(reservedOrders["PROCESS_TOTAL"], 0) or 0
	local cityCount = reservedOrders ~= nil and SC_DBNumber(reservedOrders["CITY_TOTAL"], 1) or 1
	local processCap = math.max(1, math.ceil(cityCount * SC_GetConfig("ProcessCityFraction", 0.15)))
	if atWar and processCount >= processCap and not buildMilitary then
		buildMilitary = true
		militaryNeed, needDeficit, rosterDebug = SC_GetMilitaryProductionNeed(player, city, atWar, reservedOrders, {})
		if SC_GetConfig("DebugCityProduction", true) then
			SC_Debug("cityProduction force-military city="..tostring(cityName)..
				" reason=wartime-process-cap processes="..tostring(processCount).."/"..tostring(processCap)..
				" need="..tostring(militaryNeed).." roster="..tostring(rosterDebug))
		end
	end
	local queuedMilitary = SC_CountCityQueuedTrainOrders(city)
	local militaryQueueCap = SC_GetConfig("WarQueueMilitarySlotsPerCity", 2)
	if production == "MILITARY" or production == "AIRSEA" then
		militaryQueueCap = SC_GetConfig("TargetCityQueueLength", 5)
	end
	if buildMilitary and queuedMilitary >= militaryQueueCap then
		buildMilitary = false
		if SC_GetConfig("DebugCityProduction", true) then
			SC_Debug("cityProduction military-defer city="..tostring(cityName).." reason=queue-quota queuedMilitary="..tostring(queuedMilitary).."/"..tostring(militaryQueueCap).." need="..tostring(militaryNeed).." roster="..tostring(rosterDebug))
		end
	end
	if SC_StrategyGetCivilianProductionNeed ~= nil and (not SC5 or not SC5.CityInImmediateDanger(city)) then
		local civilianNeed, civilianDeficit, civilianReason = SC_StrategyGetCivilianProductionNeed(player, reservedOrders)
		if civilianNeed ~= nil then
			local civilianID, civilianScore = SC_GetBestTrainableCivilian(city, civilianNeed)
			if civilianID ~= nil and SC_PushCityOrder(city, OrderTypes.ORDER_TRAIN, civilianID) then
				local civilianInfo = GameInfo.Units[civilianID]
				local reserveKey = "CIVILIAN:"..civilianNeed
				SC_Debug("cityProduction choose city="..tostring(cityName).." category=civilian item="..tostring(civilianInfo and civilianInfo.Type or civilianID).." score="..tostring(math.floor(civilianScore)).." need="..tostring(civilianNeed).." deficit="..tostring(civilianDeficit).." reason="..tostring(civilianReason).." queue="..tostring(queueLength))
				markSubmitted("civilian", civilianInfo and civilianInfo.Type or "UNIT")
				return civilianInfo and civilianInfo.Type or "UNIT", reserveKey
			end
		end
	end
	if queuedMilitary < militaryQueueCap then
		local eliteUnitID, eliteUnitScore, eliteUnitCandidates, eliteUnitReason = SC_GetBestTrainableEliteUnit(player, city, atWar, reservedOrders)
		if eliteUnitID ~= nil and SC_PushCityOrder(city, OrderTypes.ORDER_TRAIN, eliteUnitID) then
			local eliteUnitInfo = GameInfo.Units[eliteUnitID]
			local eliteReserveKey = "ELITE_UNIT:"..tostring(eliteUnitID)
			local eliteNeed = SC_GetProductionNeedForUnitInfo(eliteUnitInfo)
			if SC_GetConfig("DebugCityProduction", true) then
				SC_Debug("cityProduction choose city="..tostring(cityName).." category=elite-unit item="..tostring(eliteUnitInfo and eliteUnitInfo.Type or "UNIT").." score="..tostring(math.floor(eliteUnitScore)).." candidates="..tostring(eliteUnitCandidates).." need="..tostring(eliteNeed).." reason="..tostring(eliteUnitReason).." queue="..tostring(queueLength))
			end
			markSubmitted("elite-unit", eliteUnitInfo and eliteUnitInfo.Type or "UNIT")
			return eliteUnitInfo and eliteUnitInfo.Type or "UNIT", eliteReserveKey, eliteNeed
		end
	end
	local eliteProjectID, eliteProjectScore, eliteProjectCandidates, eliteProjectReason = SC_GetBestEliteProject(player, city, atWar, reservedOrders)
	if eliteProjectID ~= nil and SC_PushCityOrder(city, OrderTypes.ORDER_CREATE, eliteProjectID) then
		local eliteProjectInfo = GameInfo.Projects[eliteProjectID]
		local eliteProjectReserveKey = "X:P:"..tostring(eliteProjectID)
		if reservedOrders ~= nil then
			reservedOrders[eliteProjectReserveKey] = true
			reservedOrders["ELITE_PROJECT_TOTAL"] = SC_DBNumber(reservedOrders["ELITE_PROJECT_TOTAL"], 0) + 1
		end
		if SC_GetConfig("DebugCityProduction", true) then
			SC_Debug("cityProduction choose city="..tostring(cityName).." category=elite-project item="..tostring(eliteProjectInfo and eliteProjectInfo.Type or "PROJECT").." score="..tostring(math.floor(eliteProjectScore)).." candidates="..tostring(eliteProjectCandidates).." reason="..tostring(eliteProjectReason).." queuedProjects="..tostring(reservedOrders ~= nil and reservedOrders["ELITE_PROJECT_TOTAL"] or 1).."/"..tostring(SC_GetConfig("MaxQueuedEliteProjects", 2)).." queue="..tostring(queueLength))
		end
		markSubmitted("elite-project", eliteProjectInfo and eliteProjectInfo.Type or "PROJECT")
		return eliteProjectInfo and eliteProjectInfo.Type or "PROJECT", eliteProjectReserveKey
	end
	if buildMilitary then
		local ok, coastal = pcall(function() return city:IsCoastal() end)
		local unitID = nil
		local unitScore = nil
		local unitCandidates = nil
		local unitRole = nil
		local unitReserved = nil
		local unitRejected = nil
		local unitEra = nil
		local attemptedNeeds = {}
		local attemptParts = {}
		local selectedNeed = nil
		local candidateNeed = militaryNeed
		for attempt = 1, 11, 1 do
			if candidateNeed == nil then break end
			attemptedNeeds[candidateNeed] = true
			local domain = SC_GetProductionNeedDomain(candidateNeed)
			if domain == "sea" and not (ok and coastal) then
				table.insert(attemptParts, candidateNeed..":inland")
			else
				unitID, unitScore, unitCandidates, unitRole, unitReserved, unitRejected, unitEra = SC_GetBestTrainableUnit(
					city,
					domain == "sea",
					domain == "air",
					reservedOrders,
					candidateNeed)
				if unitID ~= nil then
					selectedNeed = candidateNeed
					break
				end
				table.insert(attemptParts, candidateNeed..":no-trainable")
			end
			candidateNeed, needDeficit, rosterDebug = SC_GetMilitaryProductionNeed(player, city, atWar, reservedOrders, attemptedNeeds)
		end
		militaryNeed = selectedNeed or militaryNeed
		if unitID ~= nil and SC_PushCityOrder(city, OrderTypes.ORDER_TRAIN, unitID) then
			local unitInfo = GameInfo.Units[unitID]
			local reserveKey = "U:"..tostring(unitID)
			if SC_GetConfig("DebugCityProduction", true) then
				SC_Debug("cityProduction choose city="..tostring(cityName).." category=military item="..tostring(unitInfo and unitInfo.Type or "UNIT").." role="..tostring(unitRole).." score="..tostring(unitScore).." candidates="..tostring(unitCandidates).." reserved="..tostring(unitReserved).." rejectedOutdated="..tostring(unitRejected).." playerEra="..tostring(unitEra).." reason=strike-package need="..tostring(militaryNeed).." deficit="..tostring(needDeficit).." retries="..table.concat(attemptParts, "|").." queuedMilitary="..tostring(queuedMilitary).."/"..tostring(militaryQueueCap).." roster="..tostring(rosterDebug).." queue="..tostring(queueLength))
			end
			markSubmitted("military", unitInfo and unitInfo.Type or "UNIT")
			return unitInfo and unitInfo.Type or "UNIT", reserveKey, militaryNeed
		end
		if unitID == nil and SC_GetConfig("DebugCityProduction", true) then
			SC_Debug("cityProduction military-no-unit city="..tostring(cityName).." candidates="..tostring(unitCandidates).." reserved="..tostring(unitReserved).." rejectedOutdated="..tostring(unitRejected).." playerEra="..tostring(unitEra).." reason=no-viable-strike-package-unit attempted="..table.concat(attemptParts, "|"))
		end
	elseif SC_GetConfig("DebugCityProduction", true) then
		SC_Debug("cityProduction military-skip city="..tostring(cityName).." reason=force-not-needed profile="..tostring(production).." atWar="..SC_BoolText(atWar))
	end
	
	local buildingID, buildingScore, buildingCandidates, buildingWonder, buildingReserved, buildingReserveKey, buildingUnique = SC_GetBestConstructibleBuilding(player, city, atWar, reservedOrders)
	local minimumBuildingScore = SC_GetConfig("MinimumBuildingUtilityScore", 40)
	if SC_StrategyGetMinimumBuildingScore ~= nil then
		minimumBuildingScore = SC_StrategyGetMinimumBuildingScore(city, minimumBuildingScore)
	end
	if buildingID ~= nil and buildingScore >= minimumBuildingScore and SC_PushCityOrder(city, OrderTypes.ORDER_CONSTRUCT, buildingID) then
		local buildingInfo = GameInfo.Buildings[buildingID]
		local reserveKey = buildingReserveKey
		if SC_GetConfig("DebugCityProduction", true) then
			SC_Debug("cityProduction choose city="..tostring(cityName).." category=building item="..tostring(buildingInfo and buildingInfo.Type or "BUILDING").." score="..tostring(buildingScore).." candidates="..tostring(buildingCandidates).." reserved="..tostring(buildingReserved).." wonder="..SC_BoolText(buildingWonder).." unique="..SC_BoolText(buildingUnique).." reserveKey="..tostring(reserveKey).." queue="..tostring(queueLength))
		end
		markSubmitted("building", buildingInfo and buildingInfo.Type or "BUILDING")
		return buildingInfo and buildingInfo.Type or "BUILDING", reserveKey
	end
	if atWar and processCount >= processCap and buildingID ~= nil
		and SC_PushCityOrder(city, OrderTypes.ORDER_CONSTRUCT, buildingID) then
		local buildingInfo = GameInfo.Buildings[buildingID]
		if SC_GetConfig("DebugCityProduction", true) then
			SC_Debug("cityProduction choose city="..tostring(cityName)..
				" category=building-fallback item="..tostring(buildingInfo and buildingInfo.Type or "BUILDING")..
				" score="..tostring(buildingScore).." threshold="..tostring(minimumBuildingScore)..
				" reason=wartime-process-cap processes="..tostring(processCount).."/"..tostring(processCap))
		end
		markSubmitted("building-fallback", buildingInfo and buildingInfo.Type or "BUILDING")
		return buildingInfo and buildingInfo.Type or "BUILDING", buildingReserveKey
	end

	local unitCandidates = 0
	if buildingID ~= nil and buildingScore < minimumBuildingScore and SC_GetConfig("DebugCityProduction", true) then
		SC_Debug("cityProduction building-reject city="..tostring(cityName).." score="..tostring(buildingScore).." threshold="..tostring(minimumBuildingScore).." reason=low-marginal-utility")
	end
	
	local processType = "PROCESS_WEALTH"
	local processReason = "no-unit-or-building"
	if queueLength > 0 then
		if SC_GetConfig("DebugCityProduction", true) then
			SC_Debug("cityProduction process-defer city="..tostring(cityName).." reason=queue-has-orders queue="..tostring(queueLength))
		end
		return nil
	end
	if SC_StrategyGetProcessChoice ~= nil then
		processType, processReason = SC_StrategyGetProcessChoice(player, city, reservedOrders)
	elseif (SC_GetConfig("Doctrine", "BALANCED") == "SCIENCE" or SC_GetConfig("EconomyProfile", "BALANCED") == "SCIENCE") and SC_GetSafeNumber(function() return player:CalculateGoldRate() end, 0) >= 0 then
		processType = "PROCESS_RESEARCH"
	end
	local processID = SC_GetID(processType)
	if SC_CityCanMaintain(city, processID) and SC_PushCityOrder(city, OrderTypes.ORDER_MAINTAIN, processID) then
		if reservedOrders ~= nil then
			reservedOrders["PROCESS_TOTAL"] = SC_DBNumber(reservedOrders["PROCESS_TOTAL"], 0) + 1
		end
		if SC_GetConfig("DebugCityProduction", true) then
			SC_Debug("cityProduction choose city="..tostring(cityName).." category=process item="..tostring(processType).." reason="..tostring(processReason).." goldRate="..tostring(SC_GetSafeNumber(function() return player:CalculateGoldRate() end, 0)).." queue="..tostring(queueLength))
		end
		markSubmitted("process", processType)
		return processType, "P:"..tostring(processID)
	end
	if SC_GetConfig("DebugCityProduction", true) then
		SC_Debug("cityProduction no-choice city="..tostring(cityName).." queue="..tostring(queueLength).." buildingCandidates="..tostring(buildingCandidates).." unitCandidates="..tostring(unitCandidates))
	end
	return nil
end

local function SC_AutomateCities(player, atWar)
	local changed = 0
	local details = {}
	if not SC_GetConfig("AutoCityProduction", true) then
		return changed, details
	end
	for city in player:Cities() do
		SC_PruneLegacyV135ProductionOrders(city)
	end
	local reservedOrders = SC_SeedProductionReservations(player)
	for city in player:Cities() do
		if city ~= nil then
			local productionType, reserveKey, needKey = SC_ChooseCityProduction(player, city, atWar, reservedOrders)
			if productionType ~= nil then
			if reserveKey ~= nil then
				if string.sub(tostring(reserveKey), 1, 9) == "CIVILIAN:" then
					reservedOrders[reserveKey] = SC_DBNumber(reservedOrders[reserveKey], 0) + 1
				else
					reservedOrders[reserveKey] = SC_DBNumber(reservedOrders[reserveKey], 0) + 1
				end
			end
			if needKey ~= nil then
				local needReserveKey = "NEED:"..tostring(needKey)
				reservedOrders[needReserveKey] = SC_DBNumber(reservedOrders[needReserveKey], 0) + 1
			end
			changed = changed + 1
			if #details < 10 then
				table.insert(details, city:GetName()..": "..productionType)
			end
			end
		end
	end
	return changed, details
end

local function SC_GetPolicyScore(policy, player)
	local doctrine = SC_GetConfig("Doctrine", "BALANCED")
	local score = 0
	for row in SC_GameInfoRows("Policy_Flavors", {PolicyType = policy.Type}) do
		local flavor = row.FlavorType
		local value = row.Flavor or 0
		if doctrine == "SCIENCE" and flavor == "FLAVOR_SCIENCE" then
			score = score + value * 5
		elseif doctrine == "INDUSTRY" and flavor == "FLAVOR_PRODUCTION" then
			score = score + value * 5
		elseif doctrine == "WAR" and (flavor == "FLAVOR_OFFENSE" or flavor == "FLAVOR_DEFENSE" or flavor == "FLAVOR_MILITARY_TRAINING") then
			score = score + value * 5
		else
			score = score + value
		end
	end
	if policy.PolicyBranchType == "POLICY_BRANCH_RATIONALISM" then score = score + 8 end
	if policy.PolicyBranchType == "POLICY_BRANCH_ORDER" then score = score + 5 end
	if policy.PolicyBranchType == "POLICY_BRANCH_AUTOCRACY" and doctrine == "WAR" then score = score + 12 end
	if SC_StrategyScorePolicy ~= nil then
		score = SC_StrategyScorePolicy(player, policy, score)
	end
	return score
end

local function SC_GetAutoIdeologyBranchID()
	local war = SC_GetConfig("WarProfile", "ADVANCE")
	local economy = SC_GetConfig("EconomyProfile", "BALANCED")
	local build = SC_GetConfig("BuildProfile", "INFRASTRUCTURE")
	local diplomacy = SC_GetConfig("DiplomacyProfile", "BALANCED")
	local branchType = "POLICY_BRANCH_ORDER"
	local national = nil
	if SC_StrategyGetNationalPlan ~= nil then national = SC_StrategyGetNationalPlan() end
	if national ~= nil and national.victory == "conquest" then
		branchType = "POLICY_BRANCH_AUTOCRACY"
	elseif national ~= nil and (national.victory == "science" or national.victory == "industry") then
		branchType = "POLICY_BRANCH_ORDER"
	elseif war == "ASSAULT" or war == "NAVAL" then
		branchType = "POLICY_BRANCH_AUTOCRACY"
	elseif diplomacy == "FRIENDLY" or economy == "TREASURY" then
		branchType = "POLICY_BRANCH_FREEDOM"
	elseif economy == "SCIENCE" or build == "SCIENCE" then
		branchType = "POLICY_BRANCH_ORDER"
	end
	return GameInfoTypes[branchType]
end

local function SC_AutomateIdeology(player)
	if player == nil or Network == nil then
		return 0
	end
	local currentIdeology = SC_GetSafeNumber(function() return player:GetLateGamePolicyTree() end, -1)
	if currentIdeology ~= nil and currentIdeology >= 0 then
		return 0
	end
	local branchID = SC_GetAutoIdeologyBranchID()
	if branchID == nil then
		return 0
	end
	local canChoose = false
	pcall(function()
		canChoose = player:CanUnlockPolicyBranch(branchID)
	end)
	if not canChoose then
		canChoose = SC_GetSafeNumber(function() return Game.GetNumFreePolicies(branchID) end, 0) > 0
	end
	if not canChoose then
		return 0
	end
	local ok = pcall(function()
		Network.SendIdeologyChoice(Game.GetActivePlayer(), branchID)
	end)
	if ok then
		return 1
	end
	return 0
end

function SC_IsPurchaseByLevelPolicy(policy)
	if policy == nil or policy.PolicyBranchType == nil then
		return false
	end
	local branch = nil
	pcall(function() branch = GameInfo.PolicyBranchTypes[policy.PolicyBranchType] end)
	return branch ~= nil and (branch.PurchaseByLevel == true or branch.PurchaseByLevel == 1 or branch.PurchaseByLevel == "1")
end

function SC_HasPolicy(player, policyID)
	local has = false
	pcall(function() has = player:HasPolicy(policyID) end)
	return has
end

function SC_TenetStillAvailable(player, policyID, level)
	if player == nil or policyID == nil or player.GetAvailableTenets == nil then
		return false
	end
	local available = nil
	pcall(function() available = player:GetAvailableTenets(level) end)
	if available == nil then
		return false
	end
	for _, tenetID in ipairs(available) do
		if tenetID == policyID then
			return true
		end
	end
	return false
end

function SC_PlayerCanChooseTenetLevel(player, level)
	if player == nil or player.GetTenet == nil then
		return false
	end
	local ideology = SC_GetSafeNumber(function() return player:GetLateGamePolicyTree() end, -1)
	if ideology == nil or ideology < 0 then
		return false
	end
	local hasCurrency = false
	pcall(function()
		hasCurrency = player:GetJONSCulture() >= player:GetNextPolicyCost() or player:GetNumFreePolicies() > 0 or player:GetNumFreeTenets() > 0
	end)
	if not hasCurrency then
		return false
	end
	if level == 1 then
		local previous = -1
		for slot = 1, 7, 1 do
			local current = SC_GetSafeNumber(function() return player:GetTenet(ideology, 1, slot) end, -1)
			if current < 0 and (slot == 1 or previous >= 0) then
				return true
			end
			previous = current
		end
	elseif level == 2 then
		for slot = 1, 4, 1 do
			local current = SC_GetSafeNumber(function() return player:GetTenet(ideology, 2, slot) end, -1)
			local required = SC_GetSafeNumber(function() return player:GetTenet(ideology, 1, slot + 1) end, -1)
			if current < 0 and required >= 0 then
				return true
			end
		end
	elseif level == 3 then
		for slot = 1, 3, 1 do
			local current = SC_GetSafeNumber(function() return player:GetTenet(ideology, 3, slot) end, -1)
			local required = SC_GetSafeNumber(function() return player:GetTenet(ideology, 2, slot + 1) end, -1)
			if current < 0 and required >= 0 then
				return true
			end
		end
	end
	return false
end

function SC_AutomateTenets(player)
	if not SC_GetConfig("AutoPolicy", true) or player == nil or Network == nil or player.GetAvailableTenets == nil then
		return 0
	end
	for level = 3, 1, -1 do
		if SC_PlayerCanChooseTenetLevel(player, level) then
			local available = nil
			pcall(function() available = player:GetAvailableTenets(level) end)
			if available ~= nil and #available > 0 then
				if not SC_POLICY_FAILED_THIS_TURN["T:DEFER_TO_POPUP"] then
					SC_POLICY_FAILED_THIS_TURN["T:DEFER_TO_POPUP"] = true
					SC_Debug("tenet defer-to-popup level="..tostring(level).." available="..tostring(#available))
				end
				SC_POLICY_PENDING_THIS_TURN = true
				return 0
			end
		end
	end
	return 0
end

local function SC_AutomatePolicy(player)
	if not SC_GetConfig("AutoPolicy", true) or player == nil then
		return 0
	end
	if SC_POLICY_PENDING_THIS_TURN then
		SC_Debug("policy pending-skip reason=await-next-turn")
		return 0
	end
	local function canAdoptPolicy(policyID)
		local canAdopt = false
		pcall(function() canAdopt = player:CanAdoptPolicy(policyID) end)
		return canAdopt
	end
	local function hasPolicy(policyID)
		return SC_HasPolicy(player, policyID)
	end
	local function branchUnlocked(branchID)
		local unlocked = false
		pcall(function() unlocked = player:IsPolicyBranchUnlocked(branchID) end)
		return unlocked
	end
	local adopted = SC_AutomateTenets(player)
	if SC_POLICY_PENDING_THIS_TURN then
		SC_Debug("policy defer-for-tenet-popup")
		return adopted
	end
	for loop = 1, 8, 1 do
		local bestPolicy = nil
		local bestScore = -99999
		for policy in GameInfo.Policies() do
			local failedKey = "P:"..tostring(policy.ID)
			if not SC_IsPurchaseByLevelPolicy(policy) and not SC_POLICY_FAILED_THIS_TURN[failedKey] and canAdoptPolicy(policy.ID) then
				local score = SC_GetPolicyScore(policy, player)
				if score > bestScore then
					bestScore = score
					bestPolicy = policy.ID
				end
			end
		end
		if bestPolicy ~= nil then
			if SC_StrategyLogPolicyChoice ~= nil then SC_StrategyLogPolicyChoice(bestPolicy) end
			local ok = pcall(function() Network.SendUpdatePolicies(bestPolicy, true, true) end)
			local verified = hasPolicy(bestPolicy) or not canAdoptPolicy(bestPolicy)
			if ok and verified then
				adopted = adopted + 1
			else
				SC_POLICY_FAILED_THIS_TURN["P:"..tostring(bestPolicy)] = true
				SC_POLICY_PENDING_THIS_TURN = ok
				local policyInfo = GameInfo.Policies[bestPolicy]
				SC_Debug("policy send-unverified policy="..tostring(policyInfo and policyInfo.Type or bestPolicy).." ok="..SC_BoolText(ok).." verified="..SC_BoolText(verified))
				break
			end
		else
			local bestBranch = nil
			local bestBranchScore = -999999
			local branchOrder = {"POLICY_BRANCH_RATIONALISM", "POLICY_BRANCH_ORDER", "POLICY_BRANCH_AUTOCRACY", "POLICY_BRANCH_COMMERCE", "POLICY_BRANCH_EXPLORATION", "POLICY_BRANCH_TRADITION", "POLICY_BRANCH_HONOR"}
			for branchIndex, branchType in ipairs(branchOrder) do
				local branchID = GameInfoTypes[branchType]
				if branchID ~= nil then
					local branchInfo = GameInfo.PolicyBranchTypes[branchID]
					local canUnlock = false
					pcall(function() canUnlock = player:CanUnlockPolicyBranch(branchID) end)
					local purchaseByLevel = branchInfo ~= nil and (branchInfo.PurchaseByLevel == true or branchInfo.PurchaseByLevel == 1 or branchInfo.PurchaseByLevel == "1")
					if canUnlock and not SC_POLICY_FAILED_THIS_TURN["B:"..tostring(branchID)] and not purchaseByLevel then
						local branchScore = 100 - branchIndex
						if SC_StrategyScorePolicyBranch ~= nil then branchScore = SC_StrategyScorePolicyBranch(player, branchInfo, branchScore) end
						if branchScore > bestBranchScore then
							bestBranch = branchID
							bestBranchScore = branchScore
						end
					end
				end
			end
			if bestBranch ~= nil then
				local ok = pcall(function() Network.SendUpdatePolicies(bestBranch, false, true) end)
				local canStillUnlock = false
				pcall(function() canStillUnlock = player:CanUnlockPolicyBranch(bestBranch) end)
				local verified = branchUnlocked(bestBranch) or not canStillUnlock
				if ok and verified then
					adopted = adopted + 1
				else
					SC_POLICY_FAILED_THIS_TURN["B:"..tostring(bestBranch)] = true
					SC_POLICY_PENDING_THIS_TURN = ok
					SC_Debug("policy branch-unverified branch="..tostring(bestBranch).." ok="..SC_BoolText(ok).." verified="..SC_BoolText(verified))
					break
				end
			else
				break
			end
		end
	end
	return adopted
end

local function SC_ShouldDelegatePolicyPopupToUI(player)
	if not SC_GetConfig("AutoPolicy", true) or player == nil then
		return false
	end
	for level = 3, 1, -1 do
		if SC_PlayerCanChooseTenetLevel(player, level) then
			local available = nil
			pcall(function() available = player:GetAvailableTenets(level) end)
			if available ~= nil and #available > 0 then
				return true
			end
		end
	end
	for policy in GameInfo.Policies() do
		local canAdopt = false
		pcall(function()
			canAdopt = policy ~= nil and not SC_IsPurchaseByLevelPolicy(policy) and player:CanAdoptPolicy(policy.ID)
		end)
		if canAdopt then
			return true
		end
	end
	return false
end

function SC_UnitCanPromoteNow(unit)
	if unit == nil then
		return false
	end
	if SC_GetSafeNumber(function() return unit:IsPromotionReady() and 1 or 0 end, 0) > 0 then
		return true
	end
	return SC_GetSafeNumber(function() return unit:CanPromote() and 1 or 0 end, 0) > 0
end

function SC_GetPromotionDebugName(promotionID)
	if promotionID == nil then
		return "nil"
	end
	local promotion = nil
	pcall(function() promotion = GameInfo.UnitPromotions[promotionID] end)
	if promotion ~= nil and promotion.Type ~= nil then
		return tostring(promotion.Type).."("..tostring(promotionID)..")"
	end
	return tostring(promotionID)
end

function SC_GetGameInfoField(row, key, defaultValue)
	if row == nil or key == nil then
		return defaultValue
	end
	local ok, value = pcall(function()
		for rowKey, rowValue in pairs(row) do
			if rowKey == key then
				return rowValue
			end
		end
		return defaultValue
	end)
	if ok then
		return value
	end
	return defaultValue
end

function SC_GetGameInfoNumber(row, key)
	local value = SC_GetGameInfoField(row, key, 0)
	if value == true then
		return 1
	end
	if value == nil or value == false then
		return 0
	end
	return tonumber(value) or 0
end

function SC_ScorePromotionForUnit(unit, unitInfo, role, promotion)
	if unit == nil or promotion == nil then
		return -999999
	end
	local score = 0
	local promotionType = SC_GetGameInfoField(promotion, "Type", "") or ""
	if SC_GetGameInfoField(promotion, "HealIfDestroyExcludesBarbarians", false) or SC_GetGameInfoNumber(promotion, "HPHealedIfDestroy") > 0 then score = score + 10 end
	score = score + SC_GetGameInfoNumber(promotion, "RangedAttackModifier") / 5
	score = score + SC_GetGameInfoNumber(promotion, "CombatPercent") / 5
	score = score + SC_GetGameInfoNumber(promotion, "CityAttack") / 5
	score = score + SC_GetGameInfoNumber(promotion, "OpenAttack") / 5
	score = score + SC_GetGameInfoNumber(promotion, "RoughAttack") / 5
	score = score + SC_GetGameInfoNumber(promotion, "ExtraAttacks") * 20
	if SC_GetGameInfoField(promotion, "Blitz", false) then score = score + 25 end
	score = score + SC_GetGameInfoNumber(promotion, "RangeChange") * 25
	score = score + SC_GetGameInfoNumber(promotion, "MovesChange") * 8
	if role == "carrier" then
		if SC_TextHas(promotionType, "CARRIER") then score = score + 60 end
		if SC_TextHas(promotionType, "SUPPLY") then score = score + 45 end
		if SC_TextHas(promotionType, "ANTI_AIR") or SC_TextHas(promotionType, "INTERCEPTION") then score = score + 35 end
	elseif role == "missile_carrier" or role == "naval_ranged" then
		if SC_TextHas(promotionType, "NAVAL") then score = score + 30 end
		if SC_TextHas(promotionType, "RANGE") then score = score + 45 end
		if SC_TextHas(promotionType, "BOMBARD") or SC_TextHas(promotionType, "CITY") then score = score + 25 end
		if SC_TextHas(promotionType, "SPLASH") or SC_TextHas(promotionType, "CLUSTER") then score = score + 35 end
	elseif role == "submarine" then
		if SC_TextHas(promotionType, "SUBMARINE") or SC_TextHas(promotionType, "AMBUSH") then score = score + 45 end
		if SC_TextHas(promotionType, "NAVAL") then score = score + 20 end
	elseif role == "fighter" or role == "bomber" or role == "carrier_air" then
		if SC_TextHas(promotionType, "AIR") then score = score + 35 end
		if SC_TextHas(promotionType, "BOMB") or SC_TextHas(promotionType, "TARGET") then score = score + 35 end
		if SC_TextHas(promotionType, "RANGE") then score = score + 35 end
		if role == "fighter" and (SC_TextHas(promotionType, "INTERCEPTION") or SC_TextHas(promotionType, "ANTI_AIR")) then score = score + 35 end
	elseif role == "siege" or role == "land_ranged" then
		if SC_TextHas(promotionType, "RANGE") then score = score + 50 end
		if SC_TextHas(promotionType, "BARRAGE") or SC_TextHas(promotionType, "CITY") then score = score + 35 end
		if SC_TextHas(promotionType, "SPLASH") or SC_TextHas(promotionType, "CLUSTER") then score = score + 35 end
	elseif role == "fast_assault" or role == "assault" or role == "naval_melee" then
		if SC_TextHas(promotionType, "MOBILITY") then score = score + 35 end
		if SC_TextHas(promotionType, "BLITZ") then score = score + 35 end
		if SC_TextHas(promotionType, "SHOCK") or SC_TextHas(promotionType, "DRILL") then score = score + 25 end
	end
	if score <= 0 then
		score = 1
	end
	return score
end

function SC_FindBestPromotionForUnit(unit, unitInfo, role)
	local bestPromotion = nil
	local bestScore = -999999
	local candidateCount = 0
	if unit == nil or GameInfo == nil or GameInfo.UnitPromotions == nil then
		return nil, bestScore, candidateCount
	end
	for promotion in GameInfo.UnitPromotions() do
		local canAcquire = false
		pcall(function() canAcquire = unit:CanAcquirePromotion(promotion.ID) end)
		if canAcquire then
			candidateCount = candidateCount + 1
			local score = SC_ScorePromotionForUnit(unit, unitInfo, role, promotion)
			if score > bestScore then
				bestScore = score
				bestPromotion = promotion.ID
			end
		end
	end
	return bestPromotion, bestScore, candidateCount
end

function SC_TryPromotionAction(unit, preferredPromotion, reason)
	if unit == nil or GameInfoActions == nil or Game == nil or Game.HandleAction == nil or ActionSubTypes == nil then
		return false
	end
	local selected = pcall(function() UI.SelectUnit(unit) end)
	if not selected then
		SC_Debug("promotion action select-failed unit="..SC_GetUnitDebugLabel(unit).." reason="..tostring(reason))
		return false
	end
	local allowAny = preferredPromotion == nil and SC_GetConfig("PromotionActionAllowAnyFallback", true)
	local matched = 0
	for iAction = 0, #GameInfoActions, 1 do
		local action = GameInfoActions[iAction]
		if action ~= nil and action.Visible and action.SubType == ActionSubTypes.ACTIONSUBTYPE_PROMOTION then
			local actionPromotion = action.CommandData
			if (preferredPromotion ~= nil and actionPromotion == preferredPromotion) or allowAny then
				matched = matched + 1
				local canHandle = false
				pcall(function() canHandle = Game.CanHandleAction(iAction) end)
				if canHandle then
					local ok, err = pcall(function() Game.HandleAction(iAction) end)
					local acquired = false
					if actionPromotion ~= nil then
						pcall(function() acquired = unit:IsHasPromotion(actionPromotion) end)
					end
					local canPromoteAfter = SC_UnitCanPromoteNow(unit)
					SC_Debug("promotion action unit="..SC_GetUnitDebugLabel(unit)..
						" index="..tostring(iAction)..
						" promotion="..SC_GetPromotionDebugName(actionPromotion)..
						" preferred="..SC_GetPromotionDebugName(preferredPromotion)..
						" reason="..tostring(reason)..
						" ok="..SC_BoolText(ok)..
						" err="..tostring(err)..
						" acquired="..SC_BoolText(acquired)..
						" canPromoteAfter="..SC_BoolText(canPromoteAfter))
					if ok and (acquired or not canPromoteAfter) then
						SC_Debug("promotion success unit="..SC_GetUnitDebugLabel(unit)..
							" method=action promotion="..SC_GetPromotionDebugName(actionPromotion)..
							" reason="..tostring(reason))
						return true
					end
				elseif SC_GetConfig("DebugPromotionCannotHandleDetails", false) then
					local logKey = tostring(SC_GetUnitTurnKey(unit) or SC_GetUnitDebugLabel(unit)).."|"..tostring(actionPromotion).."|"..tostring(reason)
					if not SC_PROMOTION_ACTION_LOGGED_THIS_TURN[logKey] then
						SC_PROMOTION_ACTION_LOGGED_THIS_TURN[logKey] = true
						SC_Debug("promotion action cannot-handle unit="..SC_GetUnitDebugLabel(unit)..
							" index="..tostring(iAction)..
							" promotion="..SC_GetPromotionDebugName(actionPromotion)..
							" preferred="..SC_GetPromotionDebugName(preferredPromotion)..
							" reason="..tostring(reason))
					end
				end
			end
		end
	end
	if matched == 0 then
		SC_Debug("promotion action no-match unit="..SC_GetUnitDebugLabel(unit)..
			" preferred="..SC_GetPromotionDebugName(preferredPromotion)..
			" reason="..tostring(reason))
	end
	return false
end

function SC_TryDirectGrantPromotion(unit, promotionID, reason)
	if unit == nil or promotionID == nil or not SC_GetConfig("DirectPromotionGrantFallback", true) then
		return false
	end
	local unitKey = SC_GetUnitTurnKey(unit) or SC_GetUnitDebugLabel(unit)
	local cacheKey = tostring(unitKey).."|"..tostring(promotionID)
	if SC_PROMOTION_DIRECT_GRANTED_THIS_TURN[cacheKey] then
		return false
	end
	local canAcquire = false
	pcall(function() canAcquire = unit:CanAcquirePromotion(promotionID) end)
	if not canAcquire then
		SC_Debug("promotion direct-grant skip unit="..SC_GetUnitDebugLabel(unit)..
			" promotion="..SC_GetPromotionDebugName(promotionID)..
			" reason="..tostring(reason)..
			" canAcquire=false")
		return false
	end
	SC_PROMOTION_DIRECT_GRANTED_THIS_TURN[cacheKey] = true
	local okGrant, grantErr = pcall(function()
		unit:SetHasPromotion(promotionID, true)
	end)
	local okReady, readyErr = pcall(function()
		unit:SetPromotionReady(false)
	end)
	local acquired = false
	pcall(function() acquired = unit:IsHasPromotion(promotionID) end)
	local canPromoteAfter = SC_UnitCanPromoteNow(unit)
	SC_Debug("promotion direct-grant unit="..SC_GetUnitDebugLabel(unit)..
		" promotion="..SC_GetPromotionDebugName(promotionID)..
		" reason="..tostring(reason)..
		" ok="..SC_BoolText(okGrant)..
		" err="..tostring(grantErr)..
		" setReadyOk="..SC_BoolText(okReady)..
		" setReadyErr="..tostring(readyErr)..
		" acquired="..SC_BoolText(acquired)..
		" canPromoteAfter="..SC_BoolText(canPromoteAfter))
	if okGrant and acquired then
		SC_Debug("promotion success unit="..SC_GetUnitDebugLabel(unit)..
			" method=direct-grant promotion="..SC_GetPromotionDebugName(promotionID)..
			" reason="..tostring(reason))
		return true
	end
	return false
end

function SC_TryPromoteUnit(unit, reason)
	if not SC_GetConfig("AutoPromoteUnits", true) or unit == nil or unit:IsDead() then
		return false
	end
	local unitKey = SC_GetUnitTurnKey(unit)
	local handledCount = 0
	local perUnitPromotionCap = SC_GetConfig("MaxAutoPromotionsPerUnitPerTurn", 20)
	if unitKey ~= nil then
		handledCount = tonumber(SC_PROMOTION_HANDLED_THIS_TURN[unitKey]) or 0
		if handledCount >= perUnitPromotionCap then
			SC_Debug("promotion per-unit-cap unit="..SC_GetUnitDebugLabel(unit)..
				" handled="..tostring(handledCount)..
				" cap="..tostring(perUnitPromotionCap)..
				" reason="..tostring(reason)..
				" state="..SC_GetUnitOrderDebug(unit))
			return false
		end
	end
	if unitKey ~= nil and SC_PROMOTION_FAILED_THIS_TURN[unitKey] and reason ~= "notification" then
		return false
	end
	local unitInfo = SC_GetUnitInfo(unit)
	local role = SC_GetUnitRole(unit, unitInfo)
	if not SC_UnitCanPromoteNow(unit) then
		if SC_GetConfig("PromotionActionFallbackWhenNotReady", true) then
			return SC_TryPromotionAction(unit, nil, tostring(reason).."-not-ready-scan")
		end
		return false
	end
	local bestPromotion, bestScore, candidateCount = SC_FindBestPromotionForUnit(unit, unitInfo, role)
	SC_Debug("promotion ready unit="..SC_GetUnitDebugLabel(unit)..
		" role="..tostring(role)..
		" reason="..tostring(reason)..
		" candidates="..tostring(candidateCount)..
		" best="..SC_GetPromotionDebugName(bestPromotion)..
		" score="..tostring(bestScore))
	if bestPromotion == nil or candidateCount <= 0 then
		local actionPromoted = SC_TryPromotionAction(unit, nil, tostring(reason).."-no-candidate-action")
		if actionPromoted then
			return true
		end
		SC_Debug("promotion no-candidate unit="..SC_GetUnitDebugLabel(unit)..
			" role="..tostring(role)..
			" reason="..tostring(reason))
		return false
	end

	local didPromote = false
	if CommandTypes ~= nil and CommandTypes.COMMAND_PROMOTION ~= nil then
		local data2Attempts = {0, -1}
		for _, commandData2 in ipairs(data2Attempts) do
			local ownerID, identityUnitID, unitLabel = SC_GetUnitIdentity(unit)
			local ok, commandStatus, liveUnit = SC_SendUnitCommand(unit, CommandTypes.COMMAND_PROMOTION, bestPromotion, commandData2)
			if commandStatus == "unit-removed" then
				SC_Debug("promotion resolved-by-removal unit="..tostring(unitLabel)..
					" promotion="..SC_GetPromotionDebugName(bestPromotion)..
					" reason="..tostring(reason))
				return ok
			end
			unit = liveUnit or SC_ResolveLiveUnit(ownerID, identityUnitID)
			if unit == nil then return ok end
			local acquired = false
			local stillCanAcquire = true
			pcall(function() acquired = unit:IsHasPromotion(bestPromotion) end)
			pcall(function() stillCanAcquire = unit:CanAcquirePromotion(bestPromotion) end)
			local canPromoteAfter = SC_UnitCanPromoteNow(unit)
			SC_Debug("promotion command unit="..SC_GetUnitDebugLabel(unit)..
				" promotion="..SC_GetPromotionDebugName(bestPromotion)..
				" reason="..tostring(reason)..
				" data2="..tostring(commandData2)..
				" ok="..SC_BoolText(ok)..
				" acquired="..SC_BoolText(acquired)..
				" stillCanAcquire="..SC_BoolText(stillCanAcquire)..
				" canPromoteAfter="..SC_BoolText(canPromoteAfter))
			if ok and (acquired or not stillCanAcquire or not canPromoteAfter) then
				didPromote = true
				SC_Debug("promotion success unit="..SC_GetUnitDebugLabel(unit)..
					" method=command promotion="..SC_GetPromotionDebugName(bestPromotion)..
					" reason="..tostring(reason)..
					" data2="..tostring(commandData2))
				break
			end
		end
	end

	if not didPromote then
		didPromote = SC_TryPromotionAction(unit, bestPromotion, reason)
	end
	if not didPromote and SC_GetConfig("PromotionActionFallbackAnyAfterCandidateFail", false) then
		didPromote = SC_TryPromotionAction(unit, nil, tostring(reason).."-fallback-any")
	end
	if not didPromote then
		didPromote = SC_TryDirectGrantPromotion(unit, bestPromotion, reason)
	end
	if not didPromote then
		if unitKey ~= nil then
			SC_PROMOTION_FAILED_THIS_TURN[unitKey] = true
		end
		SC_Debug("promotion unresolved unit="..SC_GetUnitDebugLabel(unit)..
			" role="..tostring(role)..
			" reason="..tostring(reason)..
			" best="..SC_GetPromotionDebugName(bestPromotion)..
			" candidates="..tostring(candidateCount)..
			" state="..SC_GetUnitOrderDebug(unit))
	elseif unitKey ~= nil then
		SC_PROMOTION_HANDLED_THIS_TURN[unitKey] = handledCount + 1
	end
	return didPromote
end

function SC_ShouldPromotionActionScanUnit(unit)
	if unit == nil or unit:IsDead() then
		return false
	end
	if SC_UnitCanPromoteNow(unit) then
		return true
	end
	if not SC_GetConfig("PromotionActionScanAllCombatUnits", true) then
		return false
	end
	local isCombat = false
	local xp = 0
	local level = 0
	pcall(function() isCombat = unit:IsCombatUnit() end)
	pcall(function() xp = unit:GetExperience() end)
	pcall(function() level = unit:GetLevel() end)
	return isCombat and ((xp or 0) > 0 or (level or 0) > 1)
end

function SC_AutomateUnitPromotions(player)
	if not SC_GetConfig("AutoPromoteUnits", true) or player == nil then
		return 0
	end
	local promoted = 0
	local maxPromotions = SC_GetConfig("MaxAutoPromotionsPerTurn", 80)
	local perUnitPromotionCap = SC_GetConfig("MaxAutoPromotionsPerUnitPerTurn", 20)
	for unit in player:Units() do
		if promoted >= maxPromotions then
			break
		end
		local safety = 0
		while unit ~= nil and not unit:IsDead() and promoted < maxPromotions and safety < perUnitPromotionCap and SC_UnitCanPromoteNow(unit) do
			safety = safety + 1
			if SC_TryPromoteUnit(unit, "sweep") then
				promoted = promoted + 1
			else
				break
			end
		end
		if promoted < maxPromotions and SC_ShouldPromotionActionScanUnit(unit) then
			local unitKey = SC_GetUnitTurnKey(unit)
			if unitKey == nil or not SC_PROMOTION_SCAN_ATTEMPTED_THIS_TURN[unitKey] then
				if unitKey ~= nil then
					SC_PROMOTION_SCAN_ATTEMPTED_THIS_TURN[unitKey] = true
				end
				if SC_TryPromoteUnit(unit, "sweep-action-scan") then
					promoted = promoted + 1
				end
			end
		end
	end
	return promoted
end

local function SC_ScoreStrategicTarget(player, unit, role, unitPlot, targetPlot, enemyUnit, enemyCity)
	if unitPlot == nil or targetPlot == nil then
		return -999999, "missing-plot"
	end
	local distance = Map.PlotDistance(unitPlot:GetX(), unitPlot:GetY(), targetPlot:GetX(), targetPlot:GetY())
	local score = 1000 - distance * 12
	local reasons = {"dist"..tostring(distance)}
	local coastalTarget = SC_IsCoastalAssaultPlot(targetPlot)
	local unitInfo = SC_GetUnitInfo(unit)
	local unitTag = SC_GetUnitCombatTag(unit, unitInfo, role)
	local doctrineClass = SC_GetUnitDoctrineClass(unit, unitInfo, role)
	local combatTempo = SC_StrategyGetCombatTempo ~= nil and SC_StrategyGetCombatTempo(unit) or "legacy"
	local focusPlot = SC_GetOperationFocusPlot(player, unit, unitInfo, SC_GetUnitCapabilityProfile(unit, unitInfo, role))
	if focusPlot ~= nil then
		local focusDistance = Map.PlotDistance(targetPlot:GetX(), targetPlot:GetY(), focusPlot:GetX(), focusPlot:GetY())
		if focusDistance <= SC_GetConfig("OperationFocusRadius", 5) then
			local focusScore = 620 - focusDistance * 80
			if combatTempo == "blitz" then focusScore = focusScore + SC_GetConfig("BlitzOperationFocusBonus", 900) end
			score = score + focusScore
			SC_AddScoreReason(reasons, "operationFocus", focusScore)
			if focusDistance == 0 then
				local decapitationPlot, strikeReadiness = SC_GetDecapitationFocusPlot(player)
				local isDecapitationTarget = decapitationPlot ~= nil
					and targetPlot:GetX() == decapitationPlot:GetX()
					and targetPlot:GetY() == decapitationPlot:GetY()
				if isDecapitationTarget and strikeReadiness >= SC_GetConfig("DecapitationReadinessThreshold", 0.55) then
					local decapitationScore = math.floor(420 + strikeReadiness * 380)
					score = score + decapitationScore
					SC_AddScoreReason(reasons, "decapitation", decapitationScore)
				end
			end
		end
	end
	if enemyCity ~= nil then
		local cityDamage, cityMaxHP, cityDamageRatio = SC_GetCityDamageInfo(enemyCity)
		local enemyScreen = SC_CountEnemyCombatPresenceNearPlot(player, targetPlot, SC_GetConfig("OperationEnemyScreenRadius", 4), 6)
		score = score + 260
		SC_AddScoreReason(reasons, "city", 260)
		if enemyScreen > 0 and cityDamageRatio < SC_GetConfig("CityCaptureReadyDamageRatio", 0.92) then
			local screenPenalty = math.min(enemyScreen, 4) * 340
			if doctrineClass == "siege_artillery" or doctrineClass == "arsenal_capital" then
				screenPenalty = math.floor(screenPenalty * 0.4)
			end
			score = score - screenPenalty
			SC_AddScoreReason(reasons, "destroyScreenFirst", -screenPenalty)
		end
		local cityDamageScore = cityDamage * 3
		score = score + cityDamageScore
		SC_AddScoreReason(reasons, "cityDamage", cityDamageScore)
		if cityDamageRatio >= 0.75 then
			score = score + 650
			SC_AddScoreReason(reasons, "captureReady", 650)
		elseif cityDamageRatio >= 0.45 then
			score = score + 360
			SC_AddScoreReason(reasons, "damagedCity", 360)
		end
		local supportCount, captureCount = SC_GetAssaultSupportNearPlot(player, targetPlot)
		if supportCount >= 2 then
			local focusScore = math.min(supportCount, 5) * 55
			score = score + focusScore
			SC_AddScoreReason(reasons, "fleetNear", focusScore)
		end
		if SC_IsDedicatedCityCaptureUnit(unit, unitInfo, role) then
			local captureScore = 220
			if cityDamageRatio >= 0.65 then
				captureScore = captureScore + 760
			elseif cityDamageRatio >= 0.35 then
				captureScore = captureScore + 380
			else
				captureScore = captureScore - 120
			end
			if captureCount > 0 then
				captureScore = captureScore + math.min(captureCount, 3) * 80
			end
			score = score + captureScore
			SC_AddScoreReason(reasons, "captureRole", captureScore)
		end
		if role == "carrier" then
			local carrierScore = 120
			if coastalTarget then
				carrierScore = carrierScore + 240
			end
			score = score + carrierScore
			SC_AddScoreReason(reasons, "carrierSupport", carrierScore)
		elseif unitTag == "arsenal_ship" then
			local arsenalScore = 520
			if coastalTarget then
				arsenalScore = arsenalScore + 260
			end
			if cityDamageRatio >= 0.35 then
				arsenalScore = arsenalScore + 180
			end
			score = score + arsenalScore
			SC_AddScoreReason(reasons, "arsenalSiegePlan", arsenalScore)
		elseif role == "missile_carrier" or role == "naval_ranged" then
			local shipScore = 220
			if coastalTarget then
				shipScore = shipScore + 300
			end
			if cityDamageRatio >= 0.45 then
				shipScore = shipScore + 180
			end
			if unitTag == "missile_screen" and cityDamageRatio >= 0.55 then
				shipScore = shipScore + 220
			end
			score = score + shipScore
			SC_AddScoreReason(reasons, "shipSiege", shipScore)
		elseif role == "submarine" then
			local subScore = 120
			if coastalTarget then
				subScore = subScore + 180
			end
			score = score + subScore
			SC_AddScoreReason(reasons, "subCoast", subScore)
			if cityDamageRatio >= SC_GetConfig("CityCaptureReadyDamageRatio", 0.92) then
				score = score - 360
				SC_AddScoreReason(reasons, "subNoCapture", -360)
			end
		elseif role == "siege" or role == "land_ranged" then
			local rangedScore = 160
			if unitTag == "siege_artillery" then
				rangedScore = rangedScore + 220
			end
			score = score + rangedScore
			SC_AddScoreReason(reasons, "rangedSiege", rangedScore)
		end
		if unitTag == "fast_breakthrough" and cityDamageRatio >= 0.45 then
			score = score + 260
			SC_AddScoreReason(reasons, "breakthroughCapture", 260)
		end
		if cityDamageRatio >= SC_GetConfig("CityCaptureReadyDamageRatio", 0.92) and not SC_IsDedicatedCityCaptureUnit(unit, unitInfo, role) then
			score = score - 180
			SC_AddScoreReason(reasons, "needsCaptureUnit", -180)
		end
		if doctrineClass == "fleet_carrier" or doctrineClass == "ballistic_submarine" then
			score = score - 620
			SC_AddScoreReason(reasons, "protectedAssetNoSiege", -620)
		end
		if SC_GetSafeNumber(function() return enemyCity:IsCapital() and 1 or 0 end, 0) > 0 then
			score = score + 120
			SC_AddScoreReason(reasons, "capital", 120)
		end
	elseif enemyUnit ~= nil then
		local enemyInfo = SC_GetUnitInfo(enemyUnit)
		local enemyRole = SC_GetUnitRole(enemyUnit, enemyInfo)
		local enemyClass = SC_GetUnitDoctrineClass(enemyUnit, enemyInfo, enemyRole)
		local doctrineScore = SC_GetDoctrineTargetModifier(unit, unitInfo, role, enemyUnit, enemyInfo, enemyRole, reasons)
		score = score + doctrineScore
		local protectedThreatScore = SC_GetProtectedAssetThreatScore(player, unit, targetPlot, enemyUnit, enemyInfo, enemyRole, role, unitTag, reasons)
		score = score + protectedThreatScore
		local enemyDamage = SC_GetSafeNumber(function() return enemyUnit:GetDamage() end, 0)
		score = score + 120 + enemyDamage * 6
		SC_AddScoreReason(reasons, "unit", 120 + enemyDamage * 6)
		if enemyDamage >= 70 then
			score = score + 240
			SC_AddScoreReason(reasons, "finishUnit", 240)
		elseif enemyDamage >= 45 then
			score = score + 120
			SC_AddScoreReason(reasons, "woundedUnit", 120)
		end
		if role == "submarine" and enemyInfo ~= nil and enemyInfo.Domain == "DOMAIN_SEA" then
			local subScore = 360
			if enemyRole == "carrier" or enemyRole == "missile_carrier" or enemyRole == "submarine" then
				subScore = subScore + 260
			end
			score = score + subScore
			SC_AddScoreReason(reasons, "subHuntNavy", subScore)
		elseif role == "naval_melee" and enemyInfo ~= nil and enemyInfo.Domain == "DOMAIN_SEA" then
			score = score + 220
			SC_AddScoreReason(reasons, "navalMelee", 220)
		elseif role == "fast_assault" and enemyInfo ~= nil and enemyInfo.Domain == "DOMAIN_LAND" then
			score = score + 160
			SC_AddScoreReason(reasons, "fastVsLand", 160)
		end
		if enemyRole == "carrier" or enemyRole == "missile_carrier" or enemyRole == "siege" or enemyRole == "land_ranged" then
			score = score + 200
			SC_AddScoreReason(reasons, "highValueUnit", 200)
		end
		if combatTempo == "blitz" then
			if enemyClass == "siege_artillery" or enemyClass == "surface_fire_support" or enemyClass == "arsenal_capital" then
				local blitzScore = SC_GetConfig("BlitzSiegeTargetBonus", 1100)
				score = score + blitzScore
				SC_AddScoreReason(reasons, "blitzKillSiege", blitzScore)
			elseif enemyClass == "ranged_support" or enemyClass == "strike_aircraft" or enemyClass == "air_superiority" then
				local blitzScore = SC_GetConfig("BlitzRangedTargetBonus", 650)
				score = score + blitzScore
				SC_AddScoreReason(reasons, "blitzSuppressFire", blitzScore)
			end
		end
		if unitTag == "missile_screen" and enemyInfo ~= nil and enemyInfo.Domain == "DOMAIN_SEA" then
			score = score + 340
			SC_AddScoreReason(reasons, "screenIntercept", 340)
		elseif unitTag == "air_wing" and (enemyInfo ~= nil and (enemyInfo.Domain == "DOMAIN_SEA" or enemyRole == "siege" or enemyRole == "land_ranged")) then
			score = score + 260
			SC_AddScoreReason(reasons, "airInterdiction", 260)
		elseif unitTag == "fast_breakthrough" and enemyDamage >= 45 then
			score = score + 180
			SC_AddScoreReason(reasons, "breakthroughFinish", 180)
		end
		if role == "carrier" and (enemyRole == "carrier" or enemyRole == "missile_carrier" or enemyRole == "naval_ranged") then
			score = score + 180
			SC_AddScoreReason(reasons, "carrierThreat", 180)
		elseif (role == "missile_carrier" or role == "naval_ranged") and enemyInfo ~= nil and (enemyInfo.Domain == "DOMAIN_SEA" or enemyRole == "siege" or enemyRole == "land_ranged") then
			score = score + 240
			SC_AddScoreReason(reasons, "shipFireTarget", 240)
		end
		if coastalTarget and (role == "missile_carrier" or role == "naval_ranged" or role == "submarine" or role == "naval_melee") then
			score = score + 160
			SC_AddScoreReason(reasons, "coastalFront", 160)
		end
	end
	return score, SC_JoinScoreReasons(reasons)
end

local function SC_FindStrategicTarget(player, unit)
	local bestPlot = nil
	local bestScore = -999999
	local unitPlot = unit:GetPlot()
	if unitPlot == nil then
		return nil
	end
	local team = Teams[player:GetTeam()]
	local unitInfo = SC_GetUnitInfo(unit)
	local role = SC_GetUnitRole(unit, unitInfo)
	for otherID, otherPlayer in pairs(Players) do
		if otherPlayer ~= nil and otherPlayer:IsAlive() and otherPlayer:GetID() ~= player:GetID() and team ~= nil and team:IsAtWar(otherPlayer:GetTeam()) then
			for city in otherPlayer:Cities() do
				local plot = city:Plot()
				if plot ~= nil then
					local score = SC_ScoreStrategicTarget(player, unit, role, unitPlot, plot, nil, city)
					if score > bestScore then
						bestScore = score
						bestPlot = plot
					end
				end
			end
			for enemyUnit in otherPlayer:Units() do
				local plot = enemyUnit:GetPlot()
				if plot ~= nil then
					local score = SC_ScoreStrategicTarget(player, unit, role, unitPlot, plot, enemyUnit, nil)
					if score > bestScore then
						bestScore = score
						bestPlot = plot
					end
				end
			end
		end
	end
	return bestPlot
end

function SC_IsStrategicRangedMoveRole(role)
	return role == "carrier" or role == "missile_carrier" or role == "naval_ranged" or role == "submarine" or role == "siege" or role == "land_ranged"
end

function SC_IsStrategicRangedUnit(unit, unitInfo, role, profile)
	profile = profile or SC_GetUnitCapabilityProfile(unit, unitInfo, role)
	return SC_IsStrategicRangedMoveRole(role)
		or (profile.canRange and (profile.range or 0) >= 2 and not profile.canCapture)
end

function SC_GetUnitRangeValue(unit, unitInfo)
	local range = 0
	pcall(function() range = unit:Range() end)
	if range == nil or range <= 0 then
		range = unitInfo and (unitInfo.Range or 0) or 0
	end
	if range == nil or range <= 0 then
		range = 2
	end
	return range
end

function SC_GetNearbyPlot(x, y, dx, dy, range)
	if Map == nil then
		return nil
	end
	local ok, plot = pcall(function()
		return Map.PlotXYWithRangeCheck(x, y, dx, dy, range)
	end)
	if ok and plot ~= nil then
		return plot
	end
	ok, plot = pcall(function()
		return Map.GetPlot(x + dx, y + dy)
	end)
	if ok then
		return plot
	end
	return nil
end

function SC_PlotHasEnemyUnit(player, plot)
	if player == nil or plot == nil then
		return false
	end
	local team = Teams[player:GetTeam()]
	if team == nil then
		return false
	end
	local count = SC_GetSafeNumber(function() return plot:GetNumUnits() end, 0)
	for i = 0, count - 1, 1 do
		local otherUnit = nil
		pcall(function() otherUnit = plot:GetUnit(i) end)
		if otherUnit ~= nil then
			local owner = SC_GetSafeNumber(function() return otherUnit:GetOwner() end, -1)
			local otherPlayer = Players[owner]
			if otherPlayer ~= nil and otherPlayer:IsAlive() and team:IsAtWar(otherPlayer:GetTeam()) then
				return true
			end
		end
	end
	return false
end

function SC_PlotWouldRequireNewWar(player, plot)
	if player == nil or plot == nil then
		return false
	end
	local owner = SC_GetSafeNumber(function() return plot:GetOwner() end, -1)
	if owner == nil or owner < 0 or owner == player:GetID() then
		return false
	end
	local otherPlayer = Players[owner]
	if otherPlayer == nil or not otherPlayer:IsAlive() then
		return false
	end
	local team = Teams[player:GetTeam()]
	if team == nil then
		return true
	end
	if team:IsAtWar(otherPlayer:GetTeam()) then
		return false
	end
	return true
end

function SC_IsCombatTargetAuthorized(unit, plot)
	if unit == nil or plot == nil then
		return false
	end
	local ownerID = SC_GetSafeNumber(function() return unit:GetOwner() end, -1)
	local player = Players[ownerID]
	if player == nil then
		return false
	end
	local team = Teams[player:GetTeam()]
	if team == nil then
		return false
	end
	local foundWarTarget = false
	local city = nil
	pcall(function() city = plot:GetPlotCity() end)
	if city ~= nil then
		local cityOwner = SC_GetSafeNumber(function() return city:GetOwner() end, -1)
		local cityPlayer = Players[cityOwner]
		if cityPlayer == nil or not cityPlayer:IsAlive() or not team:IsAtWar(cityPlayer:GetTeam()) then
			return false
		end
		foundWarTarget = true
	end
	local count = SC_GetSafeNumber(function() return plot:GetNumUnits() end, 0)
	for i = 0, count - 1, 1 do
		local targetUnit = nil
		pcall(function() targetUnit = plot:GetUnit(i) end)
		if targetUnit ~= nil then
			local targetOwner = SC_GetSafeNumber(function() return targetUnit:GetOwner() end, -1)
			if targetOwner ~= ownerID then
				local targetPlayer = Players[targetOwner]
				if targetPlayer == nil or not targetPlayer:IsAlive() or not team:IsAtWar(targetPlayer:GetTeam()) then
					return false
				end
				foundWarTarget = true
			end
		end
	end
	return foundWarTarget
end

function SC_PlotMatchesUnitDomain(unitInfo, plot)
	if unitInfo == nil or plot == nil then
		return false
	end
	if unitInfo.Domain == "DOMAIN_SEA" then
		return SC_GetSafeNumber(function() return plot:IsWater() and 1 or 0 end, 0) > 0
	end
	if unitInfo.Domain == "DOMAIN_LAND" then
		return SC_GetSafeNumber(function() return plot:IsWater() and 1 or 0 end, 0) <= 0
	end
	if unitInfo.Domain == "DOMAIN_HOVER" then
		return true
	end
	return false
end

function SC_GetUnitStackLayer(unit)
	if unit == nil then
		return "unknown"
	end
	local domain = nil
	pcall(function() domain = unit:GetDomainType() end)
	if DomainTypes ~= nil and domain == DomainTypes.DOMAIN_AIR then
		return "air"
	end
	local combat = false
	pcall(function() combat = unit:IsCombatUnit() end)
	if combat then
		return "combat"
	end
	return "civilian"
end

local function SC_GetPlotIndexSafe(plot)
	if plot == nil then
		return nil
	end
	local ok, index = pcall(function() return plot:GetPlotIndex() end)
	if ok then
		return index
	end
	return nil
end

function SC_GetMoveReserveKey(plot, layer)
	local plotIndex = SC_GetPlotIndexSafe(plot)
	if plotIndex == nil or layer == nil then
		return nil
	end
	return tostring(plotIndex).."|"..tostring(layer)
end

function SC_IsMovePlotReserved(reserved, plot, layer)
	if reserved == nil then
		return false
	end
	local reserveKey = SC_GetMoveReserveKey(plot, layer)
	return reserveKey ~= nil and reserved[reserveKey] == true
end

function SC_ReserveMovePlot(reserved, plot, layer)
	if reserved == nil then
		return
	end
	local reserveKey = SC_GetMoveReserveKey(plot, layer)
	if reserveKey ~= nil then
		reserved[reserveKey] = true
	end
end

function SC_BumpMoveReject(stats, name)
	if stats ~= nil and name ~= nil then
		stats[name] = (stats[name] or 0) + 1
	end
end

function SC_IsRejectedMovePlot(rejected, plot)
	if rejected == nil then
		return false
	end
	local plotIndex = SC_GetPlotIndexSafe(plot)
	return plotIndex ~= nil and rejected[plotIndex] == true
end

local function SC_PlotHasOwnStackLayer(player, plot, layer, ignoreUnit)
	if player == nil or plot == nil or layer == nil then
		return false
	end
	local playerID = player:GetID()
	local count = SC_GetSafeNumber(function() return plot:GetNumUnits() end, 0)
	for i = 0, count - 1, 1 do
		local otherUnit = nil
		pcall(function() otherUnit = plot:GetUnit(i) end)
		if otherUnit ~= nil and otherUnit ~= ignoreUnit then
			local owner = SC_GetSafeNumber(function() return otherUnit:GetOwner() end, -1)
			if owner == playerID and SC_GetUnitStackLayer(otherUnit) == layer then
				return true
			end
		end
	end
	return false
end

function SC_MoveCandidateIsUsable(player, unit, unitInfo, sourcePlot, plot, layer, reserved, rejected, stats)
	if player == nil or unit == nil or unitInfo == nil or sourcePlot == nil or plot == nil then
		SC_BumpMoveReject(stats, "moveNoPlot")
		return false, nil
	end
	if plot == sourcePlot then
		SC_BumpMoveReject(stats, "moveStationary")
		return false, nil
	end
	if SC_PlotWouldRequireNewWar(player, plot) then
		SC_BumpMoveReject(stats, "newWar")
		return false, nil
	end
	if SC_PlotHasEnemyUnit(player, plot) then
		SC_BumpMoveReject(stats, "hostile")
		return false, nil
	end
	local impassable = false
	pcall(function() impassable = plot:IsImpassable() end)
	if impassable then
		SC_BumpMoveReject(stats, "blocked")
		return false, nil
	end
	local domainMatches = SC_PlotMatchesUnitDomain(unitInfo, plot)
	if SC_IsUnitEmbarked ~= nil and SC_IsUnitEmbarked(unit) then
		domainMatches = SC_GetSafeNumber(function() return plot:IsWater() and 1 or 0 end, 0) > 0
			or SC_PlotMatchesUnitDomain(unitInfo, plot)
	end
	if not domainMatches then
		SC_BumpMoveReject(stats, "domain")
		return false, nil
	end
	if SC_PlotHasOwnStackLayer(player, plot, layer, unit) then
		SC_BumpMoveReject(stats, "sameLayer")
		return false, nil
	end
	if SC_IsMovePlotReserved(reserved, plot, layer) then
		SC_BumpMoveReject(stats, "reserved")
		return false, nil
	end
	if SC_IsRejectedMovePlot(rejected, plot) then
		SC_BumpMoveReject(stats, "rejected")
		return false, nil
	end
	local distance = Map.PlotDistance(sourcePlot:GetX(), sourcePlot:GetY(), plot:GetX(), plot:GetY())
	if distance <= 1 then
		local checked, canMoveInto = pcall(function() return unit:CanMoveInto(plot, 0) end)
		if not checked or not canMoveInto then
			SC_BumpMoveReject(stats, "blocked")
			return false, distance
		end
	end
	return true, distance
end

function SC_GetMoveRejectStatsDebug(stats)
	if stats == nil then
		return "reject=nil"
	end
	return "rejectDomain="..tostring(stats.domain or 0)..
		" rejectNoPlot="..tostring(stats.moveNoPlot or 0)..
		" rejectStationary="..tostring(stats.moveStationary or 0)..
		" rejectSameLayer="..tostring(stats.sameLayer or 0)..
		" rejectReserved="..tostring(stats.reserved or 0)..
		" rejectRejected="..tostring(stats.rejected or 0)..
		" rejectBlocked="..tostring(stats.blocked or 0)..
		" rejectHostile="..tostring(stats.hostile or 0)..
		" rejectNewWar="..tostring(stats.newWar or 0)
end

function SC_FindSafeAdvanceWaypoint(player, unit, destinationPlot, reserved, stats, maxRadius, rejected)
	if player == nil or unit == nil or destinationPlot == nil then
		return nil
	end
	local sourcePlot = unit:GetPlot()
	local unitInfo = SC_GetUnitInfo(unit)
	if sourcePlot == nil or unitInfo == nil then
		return nil
	end
	local sourceDistance = Map.PlotDistance(sourcePlot:GetX(), sourcePlot:GetY(), destinationPlot:GetX(), destinationPlot:GetY())
	local radius = math.max(1, maxRadius or SC_GetConfig("StrategicWaypointRadius", 5))
	local layer = SC_GetUnitStackLayer(unit)
	local profile = SC_GetUnitCapabilityProfile(unit, unitInfo)
	local bestPlot = nil
	local bestScore = -999999
	for dx = -radius, radius, 1 do
		for dy = -radius, radius, 1 do
			local plot = SC_GetNearbyPlot(sourcePlot:GetX(), sourcePlot:GetY(), dx, dy, radius)
			local usable, moveDistance = SC_MoveCandidateIsUsable(player, unit, unitInfo, sourcePlot, plot, layer, reserved, rejected, stats)
			if usable and moveDistance ~= nil and moveDistance <= radius then
				local canEnter = true
				if moveDistance <= 1 then
					local checked = false
					checked, canEnter = pcall(function() return unit:CanMoveInto(plot, 0) end)
					canEnter = checked and canEnter
				end
				if canEnter then
					local targetDistance = Map.PlotDistance(plot:GetX(), plot:GetY(), destinationPlot:GetX(), destinationPlot:GetY())
					local progress = sourceDistance - targetDistance
					if progress > 0 then
						local score = progress * 220 - moveDistance * 12
						local destinationIsLand = SC_GetSafeNumber(function() return destinationPlot:IsWater() and 1 or 0 end, 0) <= 0
						local candidateIsLand = SC_GetSafeNumber(function() return plot:IsWater() and 1 or 0 end, 0) <= 0
						if SC_IsUnitEmbarked(unit) and destinationIsLand and candidateIsLand
							and sourceDistance <= SC_GetConfig("AmphibiousLandingTriggerDistance", 9) then
							score = score + 2600
						end
						local protectionTier = SC_GetUnitProtectionTier(unit, unitInfo, nil, profile)
						local owner = SC_GetSafeNumber(function() return plot:GetOwner() end, -1)
						if owner == player:GetID() then
							score = score + 140
						elseif owner < 0 then
							score = score + 60
						end
						if unitInfo.Domain == "DOMAIN_SEA" then
							local threats = SC_CountEnemySeaThreatsNearPlot ~= nil and SC_CountEnemySeaThreatsNearPlot(player, plot, SC_GetConfig("FleetStandoffThreatRadius", 4)) or 0
							local escorts = SC_CountFriendlyNavalEscortsNearPlot ~= nil and SC_CountFriendlyNavalEscortsNearPlot(player, plot, 2) or 0
							if SC_IsProtectedDoctrineClass(profile.doctrineClass) then
								score = score - threats * 320
								if threats > 0 and escorts < SC_GetConfig("HighValueSeaTransitMinEscorts", 1) then score = score - 5000 end
							elseif SC_IsScreenDoctrineClass(profile.doctrineClass) then
								score = score - threats * 35
							else
								score = score - threats * 100
							end
						elseif unitInfo.Domain == "DOMAIN_LAND" and protectionTier >= 2 then
							local enemyDistance = SC_GetNearestEnemyCombatDistance(player, plot, SC_GetConfig("HighValueThreatRadius", 8))
							local cover = SC_CountFriendlyRoleNearPlot(player, plot, 2, "capture", 4)
							if enemyDistance <= 2 and cover < 2 then
								score = score - 5200
							elseif enemyDistance <= 4 and cover <= 0 then
								score = score - 1800
							end
							score = score + math.min(cover, 3) * 220
						end
						if score > bestScore then
							bestScore = score
							bestPlot = plot
						end
					end
				end
			end
		end
	end
	return bestPlot
end

local function SC_FindStackEscapePlot(player, unit, sourcePlot, reserved, rejected, stats)
	if player == nil or unit == nil or sourcePlot == nil then
		return nil
	end
	local unitInfo = SC_GetUnitInfo(unit)
	local layer = SC_GetUnitStackLayer(unit)
	local sourceX = sourcePlot:GetX()
	local sourceY = sourcePlot:GetY()
	local bestPlot = nil
	local bestScore = -999999
	local maxRadius = SC_GetConfig("StackEscapeSearchRadius", 8)
	for radius = 1, maxRadius, 1 do
		for dx = -radius, radius, 1 do
			for dy = -radius, radius, 1 do
				local plot = SC_GetNearbyPlot(sourceX, sourceY, dx, dy, radius)
				local usable, distance = SC_MoveCandidateIsUsable(player, unit, unitInfo, sourcePlot, plot, layer, reserved, rejected, stats)
				if usable then
						local score = 1000 - distance * 25
						local owner = SC_GetSafeNumber(function() return plot:GetOwner() end, -1)
						if owner == player:GetID() then
							score = score + 100
						elseif owner == -1 then
							score = score + 30
						end
						if score > bestScore then
							bestScore = score
							bestPlot = plot
						end
				end
			end
		end
		if bestPlot ~= nil then
			return bestPlot
		end
	end
	return nil
end

local function SC_AutomateStackedUnits(player)
	if player == nil or not SC_GetConfig("AutoResolveStackedUnits", true) then
		return 0
	end
	local moved = 0
	local maxMoves = SC_GetConfig("MaxStackedUnitMovesPerTurn", 20)
	local maxAttempts = SC_GetConfig("MaxStackEscapeAttemptsPerUnitPerTurn", 8)
	local maxCandidates = SC_GetConfig("MaxStackEscapeCandidatesPerUnit", 10)
	local stacks = {}
	for unit in player:Units() do
		if unit ~= nil and not unit:IsDead() then
			local plot = unit:GetPlot()
			local plotIndex = SC_GetPlotIndexSafe(plot)
			local layer = SC_GetUnitStackLayer(unit)
			if plot ~= nil and plotIndex ~= nil and layer ~= "air" then
				local key = tostring(plotIndex).."|"..layer
				if stacks[key] == nil then
					stacks[key] = { Plot = plot, Layer = layer, Units = {} }
				end
				table.insert(stacks[key].Units, unit)
			end
		end
	end
	local reserved = {}
	for _, stack in pairs(stacks) do
		local units = stack.Units or {}
		if #units > 1 then
			SC_Debug("stacked found plot="..SC_GetPlotDebug(stack.Plot).." layer="..tostring(stack.Layer).." count="..tostring(#units))
			for i = 2, #units, 1 do
				if moved >= maxMoves then
					return moved
				end
				local unit = units[i]
				local unitKey = SC_GetUnitTurnKey(unit)
				local attemptCount = 0
				if unitKey ~= nil and SC_STACK_MOVE_ATTEMPTED_THIS_TURN[unitKey] ~= nil then
					attemptCount = tonumber(SC_STACK_MOVE_ATTEMPTED_THIS_TURN[unitKey]) or 0
				end
				if unitKey ~= nil and attemptCount >= maxAttempts then
					SC_Debug("stacked turn-skip unit="..SC_GetUnitDebugLabel(unit).." attempts="..tostring(attemptCount).." plot="..SC_GetPlotDebug(stack.Plot))
					if SC_UnitNeedsOrder ~= nil and SC_UnitNeedsOrder(unit) and SC_TryForceClearUnitOrder ~= nil and SC_TryForceClearUnitOrder(unit, "stacked-attempt-cap") then
						moved = moved + 1
						SC_Debug("stacked force-clear unit="..SC_GetUnitDebugLabel(unit).." reason=attempt-cap plot="..SC_GetPlotDebug(stack.Plot))
					end
				elseif SC_IsGreatPersonLike(SC_GetUnitInfo(unit)) then
					if unitKey ~= nil then
						SC_STACK_MOVE_ATTEMPTED_THIS_TURN[unitKey] = maxAttempts
					end
					SC_Debug("stacked great-person-skip unit="..SC_GetUnitDebugLabel(unit).." plot="..SC_GetPlotDebug(stack.Plot))
					if SC_UnitNeedsOrder ~= nil and SC_UnitNeedsOrder(unit) and SC_TryForceClearUnitOrder ~= nil and SC_TryForceClearUnitOrder(unit, "stacked-great-person") then
						moved = moved + 1
						SC_Debug("stacked force-clear unit="..SC_GetUnitDebugLabel(unit).." reason=great-person plot="..SC_GetPlotDebug(stack.Plot))
					end
				elseif SC_IsTradeLike(SC_GetUnitInfo(unit)) then
					if unitKey ~= nil then
						SC_STACK_MOVE_ATTEMPTED_THIS_TURN[unitKey] = maxAttempts
					end
					SC_Debug("stacked trade-skip unit="..SC_GetUnitDebugLabel(unit).." plot="..SC_GetPlotDebug(stack.Plot))
					if SC_UnitNeedsOrder ~= nil and SC_UnitNeedsOrder(unit) and SC_TryForceClearUnitOrder ~= nil and SC_TryForceClearUnitOrder(unit, "stacked-trade") then
						moved = moved + 1
						SC_Debug("stacked force-clear unit="..SC_GetUnitDebugLabel(unit).." reason=trade plot="..SC_GetPlotDebug(stack.Plot))
					end
				elseif unit ~= nil and unit:CanMove() then
					if unitKey ~= nil then
						SC_STACK_MOVE_ATTEMPTED_THIS_TURN[unitKey] = attemptCount + 1
					end
					local rejected = {}
					local searchStats = {}
					local movedThisUnit = false
					for candidateAttempt = 1, maxCandidates, 1 do
						local movePlot = SC_FindStackEscapePlot(player, unit, stack.Plot, reserved, rejected, searchStats)
						if movePlot == nil then
							if candidateAttempt == 1 then
								SC_Debug("stacked no-destination unit="..SC_GetUnitDebugLabel(unit)..
									" attempts="..tostring(attemptCount + 1)..
									" plot="..SC_GetPlotDebug(stack.Plot)..
									" noPlot="..tostring(searchStats.moveNoPlot or 0)..
									" stationary="..tostring(searchStats.moveStationary or 0)..
									" domain="..tostring(searchStats.domain or 0)..
									" sameLayer="..tostring(searchStats.sameLayer or 0)..
									" reserved="..tostring(searchStats.reserved or 0)..
									" rejected="..tostring(searchStats.rejected or 0)..
									" blocked="..tostring(searchStats.blocked or 0)..
									" hostile="..tostring(searchStats.hostile or 0)..
									" newWar="..tostring(searchStats.newWar or 0))
							end
							break
						end
						local moveOK, moveStatus, liveUnit = SC_TryMoveMission(unit, movePlot, "stacked", true)
						if moveStatus == "unit-removed" then
							if unitKey ~= nil then SC_STACK_MOVE_ATTEMPTED_THIS_TURN[unitKey] = maxAttempts end
							movedThisUnit = true
							SC_Debug("stacked unit-removed key="..tostring(unitKey).." from="..SC_GetPlotDebug(stack.Plot).." to="..SC_GetPlotDebug(movePlot))
							break
						elseif liveUnit ~= nil then
							unit = liveUnit
						end
						if moveOK then
							SC_ReserveMovePlot(reserved, movePlot, SC_GetUnitStackLayer(unit))
							if unitKey ~= nil then
								SC_STACK_MOVE_ATTEMPTED_THIS_TURN[unitKey] = maxAttempts
							end
							moved = moved + 1
							movedThisUnit = true
							SC_Debug("stacked move unit="..SC_GetUnitDebugLabel(unit).." from="..SC_GetPlotDebug(stack.Plot).." to="..SC_GetPlotDebug(movePlot).." layer="..tostring(stack.Layer))
							break
						end
						SC_Debug("stacked stationary-reject unit="..SC_GetUnitDebugLabel(unit).." attempt="..tostring(candidateAttempt).." from="..SC_GetPlotDebug(stack.Plot).." to="..SC_GetPlotDebug(movePlot).." state="..SC_GetUnitOrderDebug(unit))
						if SC_UnitNeedsOrder ~= nil and not SC_UnitNeedsOrder(unit) then
							if unitKey ~= nil then
								SC_STACK_MOVE_ATTEMPTED_THIS_TURN[unitKey] = maxAttempts
							end
							moved = moved + 1
							movedThisUnit = true
							SC_Debug("stacked queued-stationary unit="..SC_GetUnitDebugLabel(unit).." from="..SC_GetPlotDebug(stack.Plot).." to="..SC_GetPlotDebug(movePlot).." layer="..tostring(stack.Layer))
							break
						end
						local rejectedIndex = SC_GetPlotIndexSafe(movePlot)
						if rejectedIndex ~= nil then
							rejected[rejectedIndex] = true
						end
						SC_Debug("stacked move-failed unit="..SC_GetUnitDebugLabel(unit).." attempt="..tostring(candidateAttempt).." from="..SC_GetPlotDebug(stack.Plot).." to="..SC_GetPlotDebug(movePlot))
					end
					if movedThisUnit and moved >= maxMoves then
						return moved
					end
					if not movedThisUnit and SC_UnitNeedsOrder ~= nil and SC_UnitNeedsOrder(unit) and SC_TryForceClearUnitOrder ~= nil and SC_TryForceClearUnitOrder(unit, "stacked-no-move") then
						if unitKey ~= nil then
							SC_STACK_MOVE_ATTEMPTED_THIS_TURN[unitKey] = maxAttempts
						end
						moved = moved + 1
						SC_Debug("stacked force-clear unit="..SC_GetUnitDebugLabel(unit).." reason=no-move plot="..SC_GetPlotDebug(stack.Plot))
						if moved >= maxMoves then
							return moved
						end
					end
				else
					if unitKey ~= nil then
						SC_STACK_MOVE_ATTEMPTED_THIS_TURN[unitKey] = maxAttempts
					end
					SC_Debug("stacked cannot-move unit="..SC_GetUnitDebugLabel(unit).." plot="..SC_GetPlotDebug(stack.Plot))
					if SC_UnitNeedsOrder ~= nil and SC_UnitNeedsOrder(unit) and SC_TryForceClearUnitOrder ~= nil and SC_TryForceClearUnitOrder(unit, "stacked-cannot-move") then
						moved = moved + 1
						SC_Debug("stacked force-clear unit="..SC_GetUnitDebugLabel(unit).." reason=cannot-move plot="..SC_GetPlotDebug(stack.Plot))
					end
				end
			end
		end
	end
	return moved
end

function SC_FindStandoffMovePlot(player, unit, role, targetPlot, reserved, stats)
	if player == nil or unit == nil or targetPlot == nil then
		return nil
	end
	local unitPlot = unit:GetPlot()
	local unitInfo = SC_GetUnitInfo(unit)
	if unitPlot == nil or unitInfo == nil then
		return nil
	end
	local unitTag = SC_GetUnitCombatTag(unit, unitInfo, role)
	local range = SC_GetUnitRangeValue(unit, unitInfo)
	local minRange = 2
	local maxRange = math.max(range, 3)
	local desiredRange = range
	if role == "carrier" or unitTag == "fleet_flagship" then
		minRange = SC_GetConfig("CarrierStandoffMinDistance", 6)
		maxRange = SC_GetConfig("CarrierStandoffMaxDistance", 10)
		desiredRange = math.floor((minRange + maxRange) / 2 + 0.5)
	elseif unitTag == "arsenal_ship" then
		minRange = SC_GetConfig("ArsenalShipStandoffMinDistance", 5)
		maxRange = SC_GetConfig("ArsenalShipStandoffMaxDistance", 8)
		desiredRange = math.min(math.max(range, minRange), maxRange)
	elseif unitTag == "strategic_submarine" then
		minRange = SC_GetConfig("BallisticSubmarineStandoffMinDistance", 6)
		maxRange = SC_GetConfig("BallisticSubmarineStandoffMaxDistance", 10)
		desiredRange = math.floor((minRange + maxRange) / 2 + 0.5)
	elseif unitTag == "missile_screen" then
		minRange = SC_GetConfig("MissileScreenStandoffMinDistance", 1)
		maxRange = SC_GetConfig("MissileScreenStandoffMaxDistance", 3)
		if range > maxRange then
			maxRange = math.min(range, 4)
		end
		desiredRange = math.max(minRange, math.min(range, maxRange))
	elseif unitTag == "sub_hunter" then
		minRange = SC_GetConfig("SubmarineStandoffMinDistance", 2)
		maxRange = SC_GetConfig("SubmarineStandoffMaxDistance", 4)
		desiredRange = math.floor((minRange + maxRange) / 2 + 0.5)
	elseif role == "missile_carrier" or role == "naval_ranged" then
		minRange = math.max(2, math.min(range, 4))
		maxRange = math.max(range, 4)
		desiredRange = math.max(range, minRange)
	elseif unitTag == "siege_artillery" or role == "siege" or role == "land_ranged" then
		minRange = math.max(2, range - SC_GetConfig("ArtilleryStandoffRangeBuffer", 1))
		maxRange = math.max(range, 3)
		desiredRange = math.max(range, minRange)
	end
	if SC5 then minRange, maxRange, desiredRange = SC5.Standoff(unit, minRange, maxRange, desiredRange) end
	local currentDistance = Map.PlotDistance(unitPlot:GetX(), unitPlot:GetY(), targetPlot:GetX(), targetPlot:GetY())
	local bestPlot = nil
	local bestScore = -999999
	local searchRange = math.max(maxRange + 2, 5)
	local layer = SC_GetUnitStackLayer(unit)
	for dx = -searchRange, searchRange, 1 do
		for dy = -searchRange, searchRange, 1 do
			local plot = SC_GetNearbyPlot(targetPlot:GetX(), targetPlot:GetY(), dx, dy, searchRange)
			if plot ~= nil and plot ~= targetPlot then
				local targetDistance = Map.PlotDistance(plot:GetX(), plot:GetY(), targetPlot:GetX(), targetPlot:GetY())
				if targetDistance >= minRange and targetDistance <= maxRange then
					local usable, moveDistance = SC_MoveCandidateIsUsable(player, unit, unitInfo, unitPlot, plot, layer, reserved, nil, stats)
					if usable and moveDistance > 0 then
						local score = 1000 - moveDistance * 8 - math.abs(targetDistance - desiredRange) * 35
						local protectionTier = SC_GetUnitProtectionTier(unit, unitInfo, role)
						if protectionTier >= 2 and unitInfo.Domain == "DOMAIN_LAND" then
							local enemyDistance = SC_GetNearestEnemyCombatDistance(player, plot, SC_GetConfig("ExposedRangedThreatRadius", 4) + 1)
							local cover = SC_CountFriendlyRoleNearPlot(player, plot, 2, "capture", 3)
							if enemyDistance <= 2 and cover <= 0 then
								score = score - 2600
							elseif enemyDistance <= SC_GetConfig("ExposedRangedThreatRadius", 4) and cover <= 0 then
								score = score - 1100
							elseif enemyDistance <= SC_GetConfig("ExposedRangedThreatRadius", 4) then
								score = score - 260
							end
							score = score + math.min(cover, 3) * 180
						end
						if role == "naval_ranged" or role == "missile_carrier" then
							score = score + 80
						end
						if role == "carrier" or unitTag == "fleet_flagship" then
							score = score + 120
							local owner = SC_GetSafeNumber(function() return plot:GetOwner() end, -1)
							if owner == player:GetID() then
								score = score + 120
							elseif owner < 0 then
								score = score + 50
							end
							if targetDistance <= minRange then
								score = score - 180
							end
						elseif unitTag == "arsenal_ship" or unitTag == "strategic_submarine" then
							score = score + 120
							if targetDistance >= minRange then
								score = score + 100
							end
						elseif unitTag == "missile_screen" then
							score = score + 120
							if targetDistance <= 2 then
								score = score + 120
							end
						elseif unitTag == "sub_hunter" then
							score = score + 80
						end
						if (role == "naval_ranged" or role == "missile_carrier" or role == "carrier") and SC_IsCoastalAssaultPlot(plot) then
							score = score + 70
						end
						if currentDistance < minRange and targetDistance > currentDistance then
							score = score + 160
						elseif currentDistance > maxRange and targetDistance < currentDistance then
							score = score + 120
						end
						if role == "siege" or role == "land_ranged" then
							score = score + 60
						end
						if SC_CountEnemySeaThreatsNearPlot ~= nil and unitInfo.Domain == "DOMAIN_SEA" then
							local threatRadius = SC_GetConfig("FleetStandoffThreatRadius", 4)
							local threats = SC_CountEnemySeaThreatsNearPlot(player, plot, threatRadius)
							if threats > 0 then
								if unitTag == "fleet_flagship" or unitTag == "arsenal_ship" then
									score = score - threats * 240
								elseif unitTag == "missile_screen" or unitTag == "sub_hunter" then
									score = score - threats * 40
								else
									score = score - threats * 90
								end
							end
						end
						if score > bestScore then
							bestScore = score
							bestPlot = plot
						end
					end
				end
			end
		end
	end
	return bestPlot
end

function SC_FindSupportFormationMovePlan(player, unit, reserved, stats)
	if player == nil or unit == nil then
		return nil, stats
	end
	local unitPlot = unit:GetPlot()
	local unitInfo = SC_GetUnitInfo(unit)
	local role = SC_GetUnitRole(unit, unitInfo)
	local profile = SC_GetUnitCapabilityProfile(unit, unitInfo, role)
	if unitPlot == nil or unitInfo == nil or not SC_IsScreenDoctrineClass(profile.doctrineClass) then
		return nil, stats
	end
	stats = stats or { candidates = 0, noPlot = 0, noMovePlot = 0, stationary = 0 }
	local bestAnchor = nil
	local bestAnchorScore = -999999
	for otherUnit in player:Units() do
		if otherUnit ~= nil and otherUnit ~= unit and not otherUnit:IsDead() then
			local otherInfo = SC_GetUnitInfo(otherUnit)
			local otherPlot = otherUnit:GetPlot()
			if otherInfo ~= nil and otherPlot ~= nil then
				local otherProfile = SC_GetUnitCapabilityProfile(otherUnit, otherInfo)
				local anchorValue = 0
				if SC_IsProtectedDoctrineClass(otherProfile.doctrineClass) and otherInfo.Domain == unitInfo.Domain then
					anchorValue = 900
				elseif SC_IsFragileTransportUnit ~= nil and SC_IsFragileTransportUnit(otherUnit, otherInfo) and unitInfo.Domain == "DOMAIN_SEA" then
					anchorValue = 1100
				elseif profile.doctrineClass == "mobile_air_defense"
					and (otherProfile.doctrineClass == "siege_artillery" or otherProfile.doctrineClass == "ranged_support" or otherProfile.doctrineClass == "super_heavy") then
					anchorValue = 700
				end
				if anchorValue > 0 then
					local distance = Map.PlotDistance(unitPlot:GetX(), unitPlot:GetY(), otherPlot:GetX(), otherPlot:GetY())
					local score = anchorValue - distance * 25 + (otherProfile.power or 0)
					if score > bestAnchorScore then
						bestAnchorScore = score
						bestAnchor = otherUnit
					end
				end
			end
		end
	end
	if bestAnchor == nil then
		return nil, stats
	end
	local anchorPlot = bestAnchor:GetPlot()
	local currentDistance = Map.PlotDistance(unitPlot:GetX(), unitPlot:GetY(), anchorPlot:GetX(), anchorPlot:GetY())
	local desiredRadius = SC_GetConfig("SupportFormationRadius", 2)
	if currentDistance <= desiredRadius then
		return nil, stats
	end
	local layer = SC_GetUnitStackLayer(unit)
	local bestPlot = nil
	local bestScore = -999999
	local searchRadius = math.max(desiredRadius, 2)
	for dx = -searchRadius, searchRadius, 1 do
		for dy = -searchRadius, searchRadius, 1 do
			local plot = SC_GetNearbyPlot(anchorPlot:GetX(), anchorPlot:GetY(), dx, dy, searchRadius)
			local usable, moveDistance = SC_MoveCandidateIsUsable(player, unit, unitInfo, unitPlot, plot, layer, reserved, nil, stats)
			if usable and moveDistance ~= nil then
				local anchorDistance = Map.PlotDistance(plot:GetX(), plot:GetY(), anchorPlot:GetX(), anchorPlot:GetY())
				if anchorDistance >= 1 and anchorDistance <= desiredRadius then
					local score = 2300 - moveDistance * 12 - anchorDistance * 90
					if profile.intercept > 0 then
						score = score + 180
					end
					if score > bestScore then
						bestScore = score
						bestPlot = plot
					end
				end
			end
		end
	end
	if bestPlot == nil then
		return nil, stats
	end
	stats.bestScore = bestScore
	stats.bestKind = "formation"
	stats.bestReason = "protect:"..SC_GetUnitDebugLabel(bestAnchor)
	return {
		targetPlot = anchorPlot,
		movePlot = bestPlot,
		mode = "formation",
		kind = "formation",
		reason = stats.bestReason,
		targetScore = bestAnchorScore,
		planScore = bestScore,
		moveDistance = Map.PlotDistance(unitPlot:GetX(), unitPlot:GetY(), bestPlot:GetX(), bestPlot:GetY()),
		targetDistance = currentDistance
	}, stats
end

function SC_CanUnitMoveIntoPlotForCapture(unit, plot)
	if unit == nil or plot == nil then
		return false
	end
	local ok, canMove = pcall(function() return unit:CanMoveInto(plot, true) end)
	if ok and canMove then
		return true
	end
	ok, canMove = pcall(function() return unit:CanMoveInto(plot, 1) end)
	if ok and canMove then
		return true
	end
	ok, canMove = pcall(function() return unit:CanMoveInto(plot, 0) end)
	if ok and canMove then
		return true
	end
	ok, canMove = pcall(function() return unit:CanMoveInto(plot) end)
	return ok and canMove
end

function SC_GetCityCaptureOneTurnReach(unit, unitInfo)
	unitInfo = unitInfo or SC_GetUnitInfo(unit)
	local minimum = SC_GetConfig("CityCaptureDirectReach", 4)
	if unitInfo == nil then return minimum end
	local profile = SC_GetUnitCapabilityProfile(unit, unitInfo)
	local movement = math.max(SC_DBNumber(profile.moves, 0), SC_DBNumber(unitInfo.Moves, 0))
	return math.max(minimum, math.min(movement, SC_GetConfig("CityCaptureMaximumOneTurnReach", 12)))
end

function SC_GetCityCaptureCandidateScore(player, unit, unitInfo, role, cityPlot, task)
	if player == nil or unit == nil or unitInfo == nil or cityPlot == nil then
		return nil, "missing"
	end
	if SC5 and SC5.IsWithdrawing(unit) then return nil, "withdrawal-reserved" end
	local unitPlot = unit:GetPlot()
	if unitPlot == nil then
		return nil, "no-plot"
	end
	local profile = SC_GetUnitCapabilityProfile(unit, unitInfo, role)
	local distance = Map.PlotDistance(unitPlot:GetX(), unitPlot:GetY(), cityPlot:GetX(), cityPlot:GetY())
	local maxDistance = unitInfo.Domain == "DOMAIN_SEA"
		and SC_GetConfig("CityCaptureAssignmentSeaDistance", 12)
		or SC_GetConfig("CityCaptureAssignmentLandDistance", 10)
	local directReach = SC_GetCityCaptureOneTurnReach(unit, unitInfo)
	if distance > maxDistance then
		return nil, "too-far:"..tostring(distance)..">"..tostring(maxDistance)
	end
	if unitInfo.Domain == "DOMAIN_SEA" and not SC_IsCoastalAssaultPlot(cityPlot) then
		return nil, "inland-city"
	end
	local damage = SC_GetSafeNumber(function() return unit:GetDamage() end, 0)
	if damage >= SC_GetConfig("CityCaptureMaxUnitDamage", 65) then
		return nil, "damage:"..tostring(damage)
	end
	local score = 6200 - distance * 145 - damage * 24
		+ math.max(SC_DBNumber(profile.power, 0), 0) * 4
		+ math.max(SC_DBNumber(profile.moves, 0), 0) * 18
	local assignedOperation = SC_StrategyGetOperationForUnit ~= nil and SC_StrategyGetOperationForUnit(unit) or nil
	if assignedOperation ~= nil and assignedOperation.kind == "city_assault" then
		if task ~= nil and task.operationID ~= nil and assignedOperation.id ~= task.operationID then
			if task.directOpportunity or task.opportunity then
				score = score - 1200
			else
				return nil, "other-operation:"..tostring(assignedOperation.id)
			end
		elseif task ~= nil and assignedOperation.id == task.operationID then
			score = score + 20000
		end
	end
	if distance <= directReach then
		score = score + 4200
	end
	if profile.doctrineClass == "mobile_breakthrough" or profile.doctrineClass == "super_heavy" then
		score = score + 700
	elseif unitInfo.CombatClass == "UNITCOMBAT_NAVALMELEE" then
		score = score + 620
	elseif unitInfo.CombatClass == "UNITCOMBAT_RECON" then
		score = score + 260
	end
	if profile.moveAfterAttack then score = score + 220 end
	if SC_IsUnitEmbarked ~= nil and SC_IsUnitEmbarked(unit) then score = score - 1800 end
	return score, "distance="..tostring(distance)..
		" damage="..tostring(damage)..
		" power="..tostring(profile.power or 0)..
		" class="..tostring(profile.doctrineClass)
end

function SC_BuildCityCaptureTasks(player)
	local previousAssignments = SC_CITY_CAPTURE_ASSIGNMENTS_THIS_TURN or {}
	SC_CITY_CAPTURE_TASKS_THIS_TURN = {}
	SC_CITY_CAPTURE_ASSIGNMENTS_THIS_TURN = {}
	if player == nil then return SC_CITY_CAPTURE_TASKS_THIS_TURN end
	local strategyPlan = nil
	if SC_StrategyGetNationalPlan ~= nil then
		local ok, _, plan = pcall(SC_StrategyGetNationalPlan)
		if ok then strategyPlan = plan end
	end
	local assaultOperations = {}
	for _, operation in ipairs(strategyPlan and strategyPlan.operations or {}) do
		if operation.kind == "city_assault" and operation.target ~= nil and operation.target.plot ~= nil then
			table.insert(assaultOperations, operation)
		end
	end
	local function getTaskOperation(cityPlot)
		local bestOperation = nil
		local bestDistance = 999
		for _, operation in ipairs(assaultOperations) do
			local distance = Map.PlotDistance(cityPlot:GetX(), cityPlot:GetY(), operation.target.plot:GetX(), operation.target.plot:GetY())
			if distance < bestDistance then bestOperation, bestDistance = operation, distance end
		end
		return bestOperation, bestDistance
	end
	local function hasDirectCapturer(cityPlot)
		for unit in player:Units() do
			if unit ~= nil and not unit:IsDead() and unit:CanMove() then
				local unitInfo = SC_GetUnitInfo(unit)
				local role = SC_GetUnitRole(unit, unitInfo)
				local unitPlot = unit:GetPlot()
				local directDistance = SC_GetCityCaptureOneTurnReach(unit, unitInfo)
				if unitPlot ~= nil and SC_IsDedicatedCityCaptureUnit(unit, unitInfo, role)
					and Map.PlotDistance(unitPlot:GetX(), unitPlot:GetY(), cityPlot:GetX(), cityPlot:GetY()) <= directDistance then
					return true
				end
			end
		end
		return false
	end
	local targetPool = SC_GetEnemyTargetPool(player)
	local opportunityCount = 0
	for _, city in ipairs(targetPool.cities or {}) do
		if SC_IsEnemyTargetCityValid(player, city) and (SC_IsCityReadyForCapture(city)
			or (SC5 and SC5.CityHasFinisher(player, city))) then
			local cityPlot = city:Plot()
			if cityPlot ~= nil then
				local operation, operationDistance = getTaskOperation(cityPlot)
				local focus = operation ~= nil and operationDistance == 0
				local theaterOpportunity = operation ~= nil
					and operationDistance <= SC_GetConfig("CityCaptureOpportunityRadius", 4)
				local directOpportunity = not focus and hasDirectCapturer(cityPlot)
				local damage, maxHP, ratio = SC_GetCityDamageInfo(city)
				local opportunity = not focus and not theaterOpportunity
				if opportunity then opportunityCount = opportunityCount + 1 end
				table.insert(SC_CITY_CAPTURE_TASKS_THIS_TURN, {
					city = city,
					plot = cityPlot,
					targetKey = SC_GetStrategicTargetKey(cityPlot, "capture"),
					damage = damage,
					maxHP = maxHP,
					ratio = ratio,
					capital = SC_GetSafeNumber(function() return city:IsCapital() and 1 or 0 end, 0),
					focus = focus, operationID = operation ~= nil and operation.id or nil,
					operationDistance = operationDistance, directOpportunity = directOpportunity,
					opportunity = opportunity,
					assigned = {},
					excluded = { distance = 0, damage = 0, domain = 0, other = 0 }
				})
			end
		end
	end
	table.sort(SC_CITY_CAPTURE_TASKS_THIS_TURN, function(a, b)
		if a.directOpportunity ~= b.directOpportunity then return a.directOpportunity end
		if a.focus ~= b.focus then return a.focus end
		if a.operationDistance ~= b.operationDistance then return a.operationDistance < b.operationDistance end
		if a.ratio ~= b.ratio then return a.ratio > b.ratio end
		if a.capital ~= b.capital then return a.capital > b.capital end
		return tostring(a.targetKey) < tostring(b.targetKey)
	end)
	local maxTasks = math.max(1, SC_GetConfig("CityCaptureMaxActiveTasks", 2))
	while #SC_CITY_CAPTURE_TASKS_THIS_TURN > maxTasks do table.remove(SC_CITY_CAPTURE_TASKS_THIS_TURN) end
	SC_Debug("captureTaskBoard active="..tostring(#SC_CITY_CAPTURE_TASKS_THIS_TURN)..
		" assaultOperations="..tostring(#assaultOperations).." opportunities="..tostring(opportunityCount)..
		" maxTasks="..tostring(maxTasks))
	if #SC_CITY_CAPTURE_TASKS_THIS_TURN <= 0 then return SC_CITY_CAPTURE_TASKS_THIS_TURN end
	local candidates = {}
	for unit in player:Units() do
		if unit ~= nil and not unit:IsDead() then
			local unitInfo = SC_GetUnitInfo(unit)
			local role = SC_GetUnitRole(unit, unitInfo)
			local unitKey = SC_GetUnitTurnKey(unit)
			local previous = unitKey ~= nil and previousAssignments[unitKey] or nil
			if SC_IsDedicatedCityCaptureUnit(unit, unitInfo, role) and unit:CanMove() then
				table.insert(candidates, {
					unit = unit, info = unitInfo, role = role, key = unitKey,
					previousTargetKey = previous ~= nil and previous.targetKey or nil
				})
			end
		end
	end
	local used = {}
	local slots = math.max(1, SC_GetConfig("StrategicCityCaptureTargetCapacity", 2))
	for slot = 1, slots, 1 do
		for _, task in ipairs(SC_CITY_CAPTURE_TASKS_THIS_TURN) do
			local best = nil
			local bestScore = -999999
			local bestReason = "none"
			for _, candidate in ipairs(candidates) do
				if candidate.key ~= nil and not used[candidate.key] then
					local score, reason = SC_GetCityCaptureCandidateScore(player, candidate.unit, candidate.info, candidate.role, task.plot, task)
					if score ~= nil and candidate.previousTargetKey == task.targetKey then
						score = score + 1500
						reason = tostring(reason).." previous-assignment"
					end
					if score ~= nil and score > bestScore then
						best = candidate
						bestScore = score
						bestReason = reason
					elseif score == nil then
						if string.sub(tostring(reason), 1, 7) == "too-far" then task.excluded.distance = task.excluded.distance + 1
						elseif string.sub(tostring(reason), 1, 6) == "damage" then task.excluded.damage = task.excluded.damage + 1
						elseif reason == "inland-city" then task.excluded.domain = task.excluded.domain + 1
						else task.excluded.other = task.excluded.other + 1 end
					end
				end
			end
			if best ~= nil then
				used[best.key] = true
				local assignment = {
					unit = best.unit, ownerID = best.unit:GetOwner(), unitID = best.unit:GetID(),
					info = best.info, role = best.role, unitKey = best.key,
					task = task, targetKey = task.targetKey, slot = slot,
					score = bestScore, reason = bestReason
				}
				table.insert(task.assigned, assignment)
				SC_CITY_CAPTURE_ASSIGNMENTS_THIS_TURN[best.key] = assignment
			end
		end
	end
	for _, task in ipairs(SC_CITY_CAPTURE_TASKS_THIS_TURN) do
		local labels = {}
		for _, assignment in ipairs(task.assigned) do
			table.insert(labels, tostring(assignment.slot)..":"..SC_GetUnitDebugLabel(assignment.unit)..":"..tostring(math.floor(assignment.score)))
		end
		local signature = tostring(task.damage).."/"..tostring(task.maxHP).."|"..table.concat(labels, ",")
		if SC_CITY_CAPTURE_TASK_LOGGED_THIS_TURN[task.targetKey] ~= signature then
			SC_CITY_CAPTURE_TASK_LOGGED_THIS_TURN[task.targetKey] = signature
			SC_Debug("captureTask city="..SC_GetPlotDebug(task.plot)..
				" damage="..tostring(task.damage).."/"..tostring(task.maxHP)..
				" ratio="..tostring(task.ratio)..
				" focus="..SC_BoolText(task.focus == true)..
				" operation="..tostring(task.operationID or "opportunity")..
				" operationDistance="..tostring(task.operationDistance or 999)..
				" state="..(#task.assigned > 0 and "reserved" or "no-capturer")..
				" assigned="..(#labels > 0 and table.concat(labels, ",") or "none")..
				" excluded=distance:"..tostring(task.excluded.distance)..
				",damage:"..tostring(task.excluded.damage)..
				",domain:"..tostring(task.excluded.domain)..
				",other:"..tostring(task.excluded.other))
		end
	end
	return SC_CITY_CAPTURE_TASKS_THIS_TURN
end

function SC_FindCityCaptureMovePlot(player, unit, role, targetPlot, reserved, stats)
	if player == nil or unit == nil or targetPlot == nil then
		return nil, "capture-missing"
	end
	local sourcePlot = unit:GetPlot()
	local unitInfo = SC_GetUnitInfo(unit)
	if sourcePlot == nil or unitInfo == nil then
		return nil, "capture-no-source"
	end
	local layer = SC_GetUnitStackLayer(unit)
	local targetDistanceFromSource = Map.PlotDistance(sourcePlot:GetX(), sourcePlot:GetY(), targetPlot:GetX(), targetPlot:GetY())
	if targetDistanceFromSource <= SC_GetCityCaptureOneTurnReach(unit, unitInfo)
		and not SC_IsMovePlotReserved(reserved, targetPlot, layer)
		and not SC_PlotHasOwnStackLayer(player, targetPlot, layer, unit) then
		return targetPlot, "capture-direct"
	end
	local bestPlot = nil
	local bestScore = -999999
	local searchRadius = SC_GetConfig("CityCaptureStagingSearchRadius", 2)
	for radius = 1, searchRadius, 1 do
		for dx = -radius, radius, 1 do
			for dy = -radius, radius, 1 do
				local plot = SC_GetNearbyPlot(targetPlot:GetX(), targetPlot:GetY(), dx, dy, radius)
				if plot ~= nil and plot ~= targetPlot then
					local targetDistance = Map.PlotDistance(plot:GetX(), plot:GetY(), targetPlot:GetX(), targetPlot:GetY())
					if targetDistance >= 1 and targetDistance <= searchRadius then
						local usable, moveDistance = SC_MoveCandidateIsUsable(player, unit, unitInfo, sourcePlot, plot, layer, reserved, nil, stats)
						if usable and moveDistance ~= nil and moveDistance > 0 then
							local score = 1200 - moveDistance * 8 - targetDistance * 90
							if unitInfo.Domain == "DOMAIN_SEA" and SC_IsCoastalAssaultPlot(plot) then
								score = score + 160
							elseif unitInfo.Domain == "DOMAIN_LAND" and SC_GetSafeNumber(function() return plot:IsWater() and 1 or 0 end, 0) <= 0 then
								score = score + 120
							end
							if targetDistanceFromSource <= 3 then
								score = score + 180
							end
							local owner = SC_GetSafeNumber(function() return plot:GetOwner() end, -1)
							if owner == player:GetID() then
								score = score + 90
							elseif owner < 0 then
								score = score + 30
							end
							if score > bestScore then
								bestScore = score
								bestPlot = plot
							end
						end
					end
				end
			end
		end
		if bestPlot ~= nil then
			return bestPlot, "capture-stage"
		end
	end
	return nil, "capture-no-plot"
end

function SC_TryCaptureReadyCity(player, unit, role, city, cityPlot, source)
	if player == nil or unit == nil or city == nil or cityPlot == nil then
		return false, "missing"
	end
	if not SC_IsCityReadyForCapture(city) and not (SC5 and SC5.CanFinishCity(player, unit, city)) then
		return false, "not-ready"
	end
	local unitInfo = SC_GetUnitInfo(unit)
	if not SC_IsDedicatedCityCaptureUnit(unit, unitInfo, role) then
		return false, "not-capture-unit"
	end
	local unitPlot = unit:GetPlot()
	if unitPlot == nil then
		return false, "no-unit-plot"
	end
	local distance = Map.PlotDistance(unitPlot:GetX(), unitPlot:GetY(), cityPlot:GetX(), cityPlot:GetY())
	if distance > SC_GetCityCaptureOneTurnReach(unit, unitInfo) then
		return false, "too-far"
	end
	local secure, enemyCount, friendlyCover, securityReason, friendlyPower, enemyPower = SC_GetCityCaptureSecurity(player, cityPlot, unit)
	if not secure then
		SC_Debug("captureSecurity hold unit="..SC_GetUnitDebugLabel(unit)..
			" city="..SC_GetPlotDebug(cityPlot)..
			" enemies="..tostring(enemyCount).." cover="..tostring(friendlyCover)..
			" power="..tostring(math.floor(friendlyPower or 0)).."/"..tostring(math.floor(enemyPower or 0))..
			" reason="..tostring(securityReason))
		return false, "unsafe-screen:"..tostring(enemyCount)
	end
	local damage, maxHP, ratio = SC_GetCityDamageInfo(city)
	local beforeOwner = SC_GetSafeNumber(function() return city:GetOwner() end, -1)
	if beforeOwner == player:GetID() then
		return false, "already-captured"
	end
	local _, _, unitLabel = SC_GetUnitIdentity(unit)
	local ok, moveStatus, liveUnit = SC_TryMoveMission(unit, cityPlot, tostring(source or "captureFinish"), true)
	local afterOwner = SC_GetSafeNumber(function()
		local afterCity = cityPlot:GetPlotCity()
		if afterCity ~= nil then
			return afterCity:GetOwner()
		end
		return cityPlot:GetOwner()
	end, -1)
	local captured = afterOwner == player:GetID()
	SC_Debug("captureFinish try unit="..tostring(unitLabel)..
		" role="..tostring(role)..
		" source="..tostring(source or "captureFinish")..
		" cityPlot="..SC_GetPlotDebug(cityPlot)..
		" distance="..tostring(distance)..
		" damage="..tostring(damage).."/"..tostring(maxHP)..
		" ratio="..tostring(ratio)..
		" beforeOwner=P"..tostring(beforeOwner)..
		" afterOwner=P"..tostring(afterOwner)..
		" missionOk="..SC_BoolText(ok)..
		" captured="..SC_BoolText(captured)..
		" moveStatus="..tostring(moveStatus)..
		" state="..(liveUnit ~= nil and SC_GetUnitOrderDebug(liveUnit) or "unit-removed"))
	if moveStatus == "unit-removed" then
		return false, "unit-removed"
	end
	return ok, captured and "captured" or "attempted"
end

function SC_AutomateCityCaptureFinishers(player, atWar)
	if player == nil or not atWar or not SC_GetConfig("AutoCityCaptureFinishers", true) then
		return 0
	end
	local actions = 0
	local maxActions = SC_GetConfig("MaxCityCaptureFinishersPerTurn", 20)
	local debugLimit = SC_GetConfig("DebugUnitDecisionLimit", 60)
	local debugCount = 0
	local function debugCapture(text)
		if SC_GetConfig("DebugUnitDecisions", true) and debugCount < debugLimit then
			debugCount = debugCount + 1
			SC_Debug(text)
		end
	end
	local reservedMovePlots = {}
	local tasks = SC_BuildCityCaptureTasks(player)
	for _, task in ipairs(tasks) do
		if actions >= maxActions then break end
		for _, assignment in ipairs(task.assigned or {}) do
			task.city = task.plot:GetPlotCity()
			if actions >= maxActions or not SC_IsEnemyTargetCityValid(player, task.city) then break end
			local unit = SC_ResolveLiveUnit(assignment.ownerID, assignment.unitID)
			local unitKey = assignment.unitKey
			if unit ~= nil and not unit:IsDead() and unit:CanMove() then
				local unitPlot = unit:GetPlot()
				if unitPlot ~= nil then
					local distance = Map.PlotDistance(unitPlot:GetX(), unitPlot:GetY(), task.plot:GetX(), task.plot:GetY())
					local direct = distance <= SC_GetCityCaptureOneTurnReach(unit, assignment.info)
					if direct then
						local ok, status = SC_TryCaptureReadyCity(player, unit, assignment.role, task.city, task.plot, "captureTask:"..tostring(assignment.slot))
						unit = SC_ResolveLiveUnit(assignment.ownerID, assignment.unitID)
						if ok and unit ~= nil then
							if unitKey ~= nil then
								SC_RecordStrategicOrder(unitKey)
								SC_RecordStrategicTargetCommitment(unitKey, task.targetKey)
								SC_RecordStrategicTargetMemory(unit, unitKey, task.targetKey, task.plot, "capture")
								SC_TACTICAL_NO_TARGET_THIS_TURN[unitKey] = nil
								SC_TACTICAL_QUEUED_THIS_TURN[unitKey] = nil
							end
							actions = actions + 1
						elseif unit ~= nil and status ~= "already-captured" then
							debugCapture("captureTask direct-hold unit="..SC_GetUnitDebugLabel(unit)..
								" slot="..tostring(assignment.slot)..
								" city="..SC_GetPlotDebug(task.plot)..
								" status="..tostring(status)..
								" score="..tostring(math.floor(assignment.score)))
						end
					else
						local movePlot, mode = SC_FindCityCaptureMovePlot(player, unit, assignment.role, task.plot, reservedMovePlots, {})
						if movePlot ~= nil and movePlot ~= task.plot then
							local moveDistance = Map.PlotDistance(unitPlot:GetX(), unitPlot:GetY(), movePlot:GetX(), movePlot:GetY())
							if moveDistance > SC_GetConfig("StrategicWaypointTriggerDistance", 5) then
								local waypoint = SC_FindSafeAdvanceWaypoint(player, unit, movePlot, reservedMovePlots, {}, SC_GetConfig("StrategicWaypointRadius", 5))
								if waypoint ~= nil then
									movePlot = waypoint
									mode = tostring(mode or "capture-stage").."-waypoint"
								end
							end
							local ok, status, liveUnit = SC_TryMoveMission(unit, movePlot, "captureStage:"..tostring(assignment.slot), true)
							unit = SC_ResolveLiveUnit(assignment.ownerID, assignment.unitID)
							if ok and unit ~= nil then
								SC_ReserveMovePlot(reservedMovePlots, movePlot, SC_GetUnitStackLayer(unit))
								if unitKey ~= nil then
									SC_RecordStrategicOrder(unitKey)
									SC_RecordStrategicTargetCommitment(unitKey, task.targetKey)
									SC_RecordStrategicTargetMemory(unit, unitKey, task.targetKey, task.plot, "capture")
								end
								actions = actions + 1
								debugCapture("captureTask stage unit="..SC_GetUnitDebugLabel(unit)..
									" slot="..tostring(assignment.slot)..
									" city="..SC_GetPlotDebug(task.plot)..
									" moveTo="..SC_GetPlotDebug(movePlot)..
									" mode="..tostring(mode)..
									" distance="..tostring(distance)..
									" status="..tostring(status))
							else
								debugCapture("captureTask stage-failed unit="..SC_GetUnitDebugLabel(unit)..
									" slot="..tostring(assignment.slot)..
									" city="..SC_GetPlotDebug(task.plot)..
									" moveTo="..SC_GetPlotDebug(movePlot)..
									" status="..tostring(status))
							end
						else
							debugCapture("captureTask no-stage unit="..SC_GetUnitDebugLabel(unit)..
								" slot="..tostring(assignment.slot)..
								" city="..SC_GetPlotDebug(task.plot)..
								" distance="..tostring(distance)..
								" reason="..tostring(mode))
						end
					end
				end
			end
		end
	end
	return actions
end

function SC_IsWaterOrCoastalStrategicPlot(plot)
	if plot == nil then
		return false
	end
	if SC_GetSafeNumber(function() return plot:IsWater() and 1 or 0 end, 0) > 0 then
		return true
	end
	local x = plot:GetX()
	local y = plot:GetY()
	for dx = -1, 1, 1 do
		for dy = -1, 1, 1 do
			if dx ~= 0 or dy ~= 0 then
				local nearPlot = SC_GetNearbyPlot(x, y, dx, dy, 1)
				if nearPlot ~= nil and SC_GetSafeNumber(function() return nearPlot:IsWater() and 1 or 0 end, 0) > 0 then
					return true
				end
			end
		end
	end
	return false
end

function SC_GetStrategicTargetKey(plot, kind)
	if plot == nil then
		return nil
	end
	local plotIndex = nil
	pcall(function() plotIndex = plot:GetPlotIndex() end)
	if plotIndex == nil then
		plotIndex = tostring(plot:GetX())..","..tostring(plot:GetY())
	end
	return tostring(kind or "target").."|"..tostring(plotIndex)
end

function SC_GetCurrentGameTurn()
	return SC_GetSafeNumber(function() return Game.GetGameTurn() end, -1)
end

function SC_GetStrategicTargetMemoryMatch(unitKey, targetKey, targetPlot)
	if unitKey == nil or targetPlot == nil then
		return false, nil, nil
	end
	local memory = SC_STRATEGIC_TARGET_MEMORY[unitKey]
	if memory == nil then
		return false, nil, nil
	end
	local age = SC_GetCurrentGameTurn() - (memory.turn or -9999)
	if age < 0 or age > SC_GetConfig("StrategicTargetMemoryTurns", 5) then
		SC_STRATEGIC_TARGET_MEMORY[unitKey] = nil
		return false, nil, age
	end
	local sameKey = targetKey ~= nil and memory.targetKey == targetKey
	local samePlot = memory.x == targetPlot:GetX() and memory.y == targetPlot:GetY()
	return sameKey or samePlot, memory, age
end

function SC_GetStrategicTargetMemoryBonus(unitKey, targetKey, targetPlot)
	local matched, memory, age = SC_GetStrategicTargetMemoryMatch(unitKey, targetKey, targetPlot)
	if not matched then
		return 0, memory, age
	end
	local bonus = SC_GetConfig("StrategicTargetMemoryBonus", 1800)
		- (age or 0) * SC_GetConfig("StrategicTargetMemoryDecayPerTurn", 250)
	return math.max(0, bonus), memory, age
end

function SC_RecordStrategicTargetMemory(unit, unitKey, targetKey, targetPlot, kind)
	if unitKey == nil or targetPlot == nil then
		return
	end
	local turn = SC_GetCurrentGameTurn()
	local old = SC_STRATEGIC_TARGET_MEMORY[unitKey]
	local changed = old ~= nil and old.targetKey ~= targetKey
		and (old.x ~= targetPlot:GetX() or old.y ~= targetPlot:GetY())
	if changed then
		local age = turn - (old.turn or turn)
		SC_Debug("strategicTarget switch unit="..SC_GetUnitDebugLabel(unit)..
			" from="..tostring(old.x)..","..tostring(old.y)..
			" to="..SC_GetPlotDebug(targetPlot)..
			" oldKind="..tostring(old.kind).." newKind="..tostring(kind)..
			" age="..tostring(age))
	elseif old == nil then
		SC_Debug("strategicTarget assign unit="..SC_GetUnitDebugLabel(unit)..
			" target="..SC_GetPlotDebug(targetPlot).." kind="..tostring(kind))
	end
	SC_STRATEGIC_TARGET_MEMORY[unitKey] = {
		targetKey = targetKey,
		x = targetPlot:GetX(),
		y = targetPlot:GetY(),
		kind = kind,
		turn = turn
	}
end

function SC_GetStrategicTargetCapacity(enemyUnit, enemyCity, kind)
	if kind == "city" or enemyCity ~= nil then
		return SC_GetConfig("StrategicCityTargetCapacity", 7)
	end
	local capacity = SC_GetConfig("StrategicUnitTargetCapacity", 2)
	if enemyUnit ~= nil then
		local enemyInfo = SC_GetUnitInfo(enemyUnit)
		local enemyProfile = SC_GetUnitCapabilityProfile(enemyUnit, enemyInfo)
		if enemyProfile.power >= SC_GetConfig("StrategicHighValueUnitPower", 300)
			or SC_IsProtectedDoctrineClass(enemyProfile.doctrineClass) then
			capacity = SC_GetConfig("StrategicHighValueUnitTargetCapacity", 4)
		end
	end
	return capacity
end

function SC_GetStrategicCommitmentPenalty(unitKey, targetKey, capacity, targetPlot)
	if targetKey == nil then
		return 0, 0
	end
	local committed = SC_STRATEGIC_TARGET_COMMITMENTS_THIS_TURN[targetKey] or 0
	if unitKey ~= nil and SC_STRATEGIC_UNIT_TARGET_THIS_TURN[unitKey] == targetKey then
		return 0, committed
	end
	if committed < capacity then
		return 0, committed
	end
	local penalty = SC_GetConfig("StrategicTargetSaturationPenalty", 3600)
		+ (committed - capacity) * SC_GetConfig("StrategicTargetOverfillPenalty", 900)
	return penalty, committed
end

function SC_RecordStrategicTargetCommitment(unitKey, targetKey)
	if unitKey == nil or targetKey == nil then
		return
	end
	local oldKey = SC_STRATEGIC_UNIT_TARGET_THIS_TURN[unitKey]
	if oldKey == targetKey then
		return
	end
	if oldKey ~= nil then
		SC_STRATEGIC_TARGET_COMMITMENTS_THIS_TURN[oldKey] = math.max(0, (SC_STRATEGIC_TARGET_COMMITMENTS_THIS_TURN[oldKey] or 1) - 1)
	end
	SC_STRATEGIC_UNIT_TARGET_THIS_TURN[unitKey] = targetKey
	SC_STRATEGIC_TARGET_COMMITMENTS_THIS_TURN[targetKey] = (SC_STRATEGIC_TARGET_COMMITMENTS_THIS_TURN[targetKey] or 0) + 1
end

function SC_GetStrategicPlanStatsDebug(stats)
	if stats == nil then
		return "stats=nil"
	end
	return "candidates="..tostring(stats.candidates or 0)..
		" filteredDistantUnits="..tostring(stats.filteredDistantUnits or 0)..
		" captureUnassigned="..tostring(stats.captureUnassigned or 0)..
		" captureSaturated="..tostring(stats.captureSaturated or 0)..
		" belowScore="..tostring(stats.belowScore or 0)..
		" noPlot="..tostring(stats.noPlot or 0)..
		" noMovePlot="..tostring(stats.noMovePlot or 0)..
		" stationary="..tostring(stats.stationary or 0)..
		" operation="..tostring(stats.operation or "legacy")..
		" bestScore="..tostring(stats.bestScore or "nil")..
		" bestKind="..tostring(stats.bestKind or "nil")..
		" bestReason="..tostring(stats.bestReason or "nil")..
		" "..SC_GetMoveRejectStatsDebug(stats)
end

function SC_FindParadropStagingPlot(player, unit, targetPlot, reserved, stats)
	if player == nil or unit == nil or targetPlot == nil then
		return nil
	end
	local sourcePlot = unit:GetPlot()
	local unitInfo = SC_GetUnitInfo(unit)
	local profile = SC_GetUnitCapabilityProfile(unit, unitInfo)
	if sourcePlot == nil or unitInfo == nil or (profile.dropRange or 0) <= 0 then
		return nil
	end
	local layer = SC_GetUnitStackLayer(unit)
	local bestPlot = nil
	local bestScore = -999999
	for radius = 1, 2, 1 do
		for dx = -radius, radius, 1 do
			for dy = -radius, radius, 1 do
				local plot = SC_GetNearbyPlot(targetPlot:GetX(), targetPlot:GetY(), dx, dy, radius)
				if plot ~= nil then
					local sourceDistance = Map.PlotDistance(sourcePlot:GetX(), sourcePlot:GetY(), plot:GetX(), plot:GetY())
					local targetDistance = Map.PlotDistance(plot:GetX(), plot:GetY(), targetPlot:GetX(), targetPlot:GetY())
					if sourceDistance <= profile.dropRange and targetDistance >= 1 and targetDistance <= 2 then
						local usable = SC_MoveCandidateIsUsable(player, unit, unitInfo, sourcePlot, plot, layer, reserved, nil, stats)
						if usable then
							local canDrop = true
							local checked, result = pcall(function() return unit:CanParadropAt(plot:GetX(), plot:GetY()) end)
							if checked then
								canDrop = result
							end
							if canDrop then
								local score = 1600 - targetDistance * 160 - sourceDistance * 5
								local owner = SC_GetSafeNumber(function() return plot:GetOwner() end, -1)
								if owner == player:GetID() then
									score = score + 160
								elseif owner < 0 then
									score = score + 80
								end
								if score > bestScore then
									bestScore = score
									bestPlot = plot
								end
							end
						end
					end
				end
			end
		end
	end
	return bestPlot
end

function SC_ShouldPursueStrategicEnemyUnit(player, unit, unitInfo, role, unitPlot, enemyUnit, targetPlot)
	if player == nil or unit == nil or unitInfo == nil or unitPlot == nil or enemyUnit == nil or targetPlot == nil then
		return false, "missing"
	end
	local distance = Map.PlotDistance(unitPlot:GetX(), unitPlot:GetY(), targetPlot:GetX(), targetPlot:GetY())
	local profile = SC_GetUnitCapabilityProfile(unit, unitInfo, role)
	local pursuit = unitInfo.Domain == "DOMAIN_SEA"
		and SC_GetConfig("StrategicUnitPursuitSeaDistance", 14)
		or SC_GetConfig("StrategicUnitPursuitLandDistance", 10)
	if SC_IsHighValueCombatAsset(unit, unitInfo, role, profile)
		or SC_IsStrategicRangedUnit(unit, unitInfo, role, profile) then
		pursuit = math.min(pursuit, SC_GetConfig("StrategicProtectedUnitPursuitDistance", 7))
	end
	local enemyInfo = SC_GetUnitInfo(enemyUnit)
	local enemyProfile = SC_GetUnitCapabilityProfile(enemyUnit, enemyInfo)
	if SC_GetUnitProtectionTier(enemyUnit, enemyInfo, nil, enemyProfile) >= 2
		or (enemyProfile.power or 0) >= SC_GetConfig("StrategicHighValueUnitPower", 300) then
		pursuit = pursuit + SC_GetConfig("StrategicHighValueTargetPursuitBonus", 4)
	end
	if distance > pursuit then
		return false, "distant-unit:"..tostring(distance)..">"..tostring(pursuit)
	end
	return true, "local-unit:"..tostring(distance).."/"..tostring(pursuit)
end

function SC_FindStrategicMovePlan(player, unit, reservedMovePlots)
	if player == nil or unit == nil then
		return nil, nil
	end
	local team = Teams[player:GetTeam()]
	local unitPlot = unit:GetPlot()
	if team == nil or unitPlot == nil then
		return nil, nil
	end
	local unitInfo = SC_GetUnitInfo(unit)
	local role = SC_GetUnitRole(unit, unitInfo)
	local unitTag = SC_GetUnitCombatTag(unit, unitInfo, role)
	local unitProfile = SC_GetUnitCapabilityProfile(unit, unitInfo, role)
	local unitKey = SC_GetUnitTurnKey(unit)
	local bestPlan = nil
	local bestScore = -999999
	local stats = {
		candidates = 0,
		noPlot = 0,
		noMovePlot = 0,
		stationary = 0,
		filteredDistantUnits = 0,
		captureUnassigned = 0,
		captureSaturated = 0,
		rejectedMovePlot = 0,
		belowScore = 0,
		bestScore = nil,
		bestKind = nil
	}
	local function considerTarget(targetPlot, enemyUnit, enemyCity, kind, preScore, preReason)
		stats.candidates = stats.candidates + 1
		if targetPlot == nil then
			stats.noPlot = stats.noPlot + 1
			return
		end
		if enemyUnit ~= nil then
			local pursue, pursueReason = SC_ShouldPursueStrategicEnemyUnit(player, unit, unitInfo, role, unitPlot, enemyUnit, targetPlot)
			if not pursue then
				stats.filteredDistantUnits = stats.filteredDistantUnits + 1
				return
			end
		end
		local targetScore, targetReason = preScore, preReason
		if targetScore == nil then targetScore, targetReason = SC_ScoreStrategicTarget(player, unit, role, unitPlot, targetPlot, enemyUnit, enemyCity) end
		local captureMover = kind == "city" and enemyCity ~= nil and SC_IsDedicatedCityCaptureUnit(unit, unitInfo, role)
		local captureReady = captureMover and (SC_IsCityReadyForCapture(enemyCity) or (SC5 ~= nil and SC5.CanFinishCity(player, unit, enemyCity)))
		local commitmentKind = captureReady and "capture" or kind
		local targetKey = SC_GetStrategicTargetKey(targetPlot, commitmentKind)
		if enemyUnit ~= nil then
			local enemyOwner = SC_GetSafeNumber(function() return enemyUnit:GetOwner() end, -1)
			local enemyID = SC_GetSafeNumber(function() return enemyUnit:GetID() end, -1)
			targetKey = "unit|"..tostring(enemyOwner)..":"..tostring(enemyID)
		end
		local targetCapacity = captureReady and SC_GetConfig("StrategicCityCaptureTargetCapacity", 2)
			or SC_GetStrategicTargetCapacity(enemyUnit, enemyCity, kind)
		if captureReady then
			local assignment = unitKey ~= nil and SC_CITY_CAPTURE_ASSIGNMENTS_THIS_TURN[unitKey] or nil
			if assignment == nil or assignment.targetKey ~= targetKey then
				-- The task board is a preference. A live, executable capture chance
				-- must never be discarded because the old plan chose another unit.
				stats.captureUnassigned = stats.captureUnassigned + 1
				targetScore = targetScore + SC_GetConfig("OpportunisticCaptureBonus", 1800)
				targetReason = tostring(targetReason or "base")..",captureSubstitute:1800"
			else
				targetScore = targetScore + SC_GetConfig("AssignedCaptureBonus", 900)
				targetReason = tostring(targetReason or "base")..",captureAssigned:900"
			end
			local committedNow = SC_STRATEGIC_TARGET_COMMITMENTS_THIS_TURN[targetKey] or 0
			local alreadyCommitted = unitKey ~= nil and SC_STRATEGIC_UNIT_TARGET_THIS_TURN[unitKey] == targetKey
			if not alreadyCommitted and committedNow >= targetCapacity then
				stats.captureSaturated = stats.captureSaturated + 1
				return
			end
		end
		local memoryBonus, _, memoryAge = SC_GetStrategicTargetMemoryBonus(unitKey, targetKey, targetPlot)
		if memoryBonus > 0 then
			targetScore = targetScore + memoryBonus
			targetReason = tostring(targetReason or "base")..",targetMemory:"..tostring(memoryBonus)..":age"..tostring(memoryAge or 0)
		end
		local commitmentPenalty, committed = SC_GetStrategicCommitmentPenalty(unitKey, targetKey, targetCapacity, targetPlot)
		if commitmentPenalty > 0 then
			targetScore = targetScore - commitmentPenalty
			targetReason = tostring(targetReason or "base")..",saturated:"..tostring(committed).."/"..tostring(targetCapacity)..":-"..tostring(commitmentPenalty)
		end
		if (role == "carrier" or role == "missile_carrier" or role == "naval_ranged" or role == "submarine" or role == "naval_melee") and SC_IsWaterOrCoastalStrategicPlot(targetPlot) then
			targetScore = targetScore + 160
			targetReason = tostring(targetReason or "base")..",waterCoast:160"
		end
		local movePlot = targetPlot
		local mode = "direct"
		local targetDistance = Map.PlotDistance(unitPlot:GetX(), unitPlot:GetY(), targetPlot:GetX(), targetPlot:GetY())
		local theaterReach = unitInfo.Domain == "DOMAIN_SEA"
			and SC_GetConfig("StrategicSeaTheaterReach", 28)
			or SC_GetConfig("StrategicLandTheaterReach", 18)
		if targetDistance > theaterReach then
			local theaterPenalty = math.min(
				(targetDistance - theaterReach) * SC_GetConfig("StrategicOutOfTheaterPenaltyPerTile", 18),
				SC_GetConfig("StrategicOutOfTheaterPenaltyCap", 600))
			targetScore = targetScore - theaterPenalty
			targetReason = tostring(targetReason or "base")..",outOfTheater:-"..tostring(theaterPenalty)
		end
		if captureReady then
			local capturePriority = SC_GetConfig("StrategicCityCapturePriorityBonus", 2800)
			targetScore = targetScore + capturePriority
			targetReason = tostring(targetReason or "base")..",captureTask:"..tostring(capturePriority)
		end
		if unitProfile.doctrineClass == "airborne_raider" and targetDistance <= (unitProfile.dropRange or 0) and targetDistance > 2 then
			movePlot = SC_FindParadropStagingPlot(player, unit, targetPlot, reservedMovePlots, stats)
			mode = "paradrop"
			targetReason = tostring(targetReason or "base")..",airborneStaging"
		elseif captureReady then
			local captureMode = nil
			movePlot, captureMode = SC_FindCityCaptureMovePlot(player, unit, role, targetPlot, reservedMovePlots, stats)
			if movePlot ~= nil then
				mode = captureMode or "capture"
				targetScore = targetScore + 720
				targetReason = tostring(targetReason or "base")..",captureFinish:720"
			elseif SC_GetConfig("EnableRangedReposition", true) and SC_IsStrategicRangedUnit(unit, unitInfo, role, unitProfile) then
				movePlot = SC_FindStandoffMovePlot(player, unit, role, targetPlot, reservedMovePlots, stats)
				mode = "standoff"
				targetReason = tostring(targetReason or "base")..",captureFallbackStandoff"
			end
		elseif SC_GetConfig("EnableRangedReposition", true) and SC_IsStrategicRangedUnit(unit, unitInfo, role, unitProfile) then
			movePlot = SC_FindStandoffMovePlot(player, unit, role, targetPlot, reservedMovePlots, stats)
			mode = "standoff"
		end
		if movePlot ~= nil and mode ~= "paradrop" then
			local directMoveDistance = Map.PlotDistance(unitPlot:GetX(), unitPlot:GetY(), movePlot:GetX(), movePlot:GetY())
			if directMoveDistance > SC_GetConfig("StrategicWaypointTriggerDistance", 5) then
				local rejected = unitKey ~= nil and SC_EXECUTION_REJECTED_MOVE_PLOTS_THIS_TURN[unitKey] or nil
				local waypoint = SC_FindSafeAdvanceWaypoint(player, unit, movePlot, reservedMovePlots, stats, nil, rejected)
				if waypoint ~= nil then
					movePlot = waypoint
					mode = tostring(mode).."-waypoint"
					targetReason = tostring(targetReason or "base")..",safeWaypoint"
				else
					-- Let the native pathfinder advance toward the real objective when
					-- the conservative local waypoint search cannot find a candidate.
					mode = tostring(mode).."-native"
					targetReason = tostring(targetReason or "base")..",nativePathFallback"
				end
		end
		end
		if movePlot == nil then
			stats.noMovePlot = stats.noMovePlot + 1
			return
		end
		local moveDistance = Map.PlotDistance(unitPlot:GetX(), unitPlot:GetY(), movePlot:GetX(), movePlot:GetY())
		local rejected = unitKey ~= nil and SC_EXECUTION_REJECTED_MOVE_PLOTS_THIS_TURN[unitKey] or nil
		local movePlotKey = SC_GetStablePlotKey(movePlot)
		if rejected ~= nil and rejected[movePlotKey] then
			stats.rejectedMovePlot = stats.rejectedMovePlot + 1
			return
		end
		if moveDistance <= 0 then
			stats.stationary = stats.stationary + 1
			return
		end
		local planScore = targetScore - moveDistance * 7
		if role == "carrier" then
			planScore = planScore + 120
			if kind == "city" and SC_IsWaterOrCoastalStrategicPlot(targetPlot) then
				planScore = planScore + 120
			end
		elseif unitTag == "arsenal_ship" then
			planScore = planScore + 170
		elseif unitTag == "missile_screen" then
			planScore = planScore + 150
		elseif unitTag == "sub_hunter" then
			planScore = planScore + 120
		elseif role == "missile_carrier" or role == "naval_ranged" then
			planScore = planScore + 90
		elseif role == "fast_assault" or role == "naval_melee" then
			planScore = planScore + math.max(0, 160 - targetDistance * 8)
		end
		if unitTag == "fast_breakthrough" and kind == "city" and enemyCity ~= nil and SC_IsCityReadyForCapture(enemyCity) then
			planScore = planScore + 180
			targetReason = tostring(targetReason or "base")..",breakthroughReadyCity:180"
		end
		local minimumPlanScore = kind == "city"
			and SC_GetConfig("MinimumStrategicCityPlanScore", -2000)
			or SC_GetConfig("MinimumStrategicPlanScore", 250)
		if planScore < minimumPlanScore then
			stats.belowScore = stats.belowScore + 1
			return
		end
		if planScore > bestScore then
			bestScore = planScore
			bestPlan = {
				targetPlot = targetPlot,
				movePlot = movePlot,
				mode = mode,
				kind = kind,
				reason = targetReason,
				targetScore = targetScore,
				planScore = planScore,
				moveDistance = moveDistance,
				targetDistance = targetDistance,
				targetKey = targetKey,
				targetCapacity = targetCapacity,
				targetCommitted = committed,
				targetMemoryBonus = memoryBonus,
				targetMemoryAge = memoryAge
				, movePlotKey = movePlotKey
			}
			stats.bestScore = planScore
			stats.bestKind = kind
			stats.bestReason = targetReason
		end
	end
	local targetPool = nil
	local operationDebug = "legacy"
	if SCX_GetExecutionTargetPool ~= nil then
		targetPool, operationDebug = SCX_GetExecutionTargetPool(player, unit, "strategic")
	elseif SC_StrategyGetTargetPoolForUnit ~= nil then
		targetPool, operationDebug = SC_StrategyGetTargetPoolForUnit(player, unit, SC_GetEnemyTargetPool(player))
	else
		targetPool = SC_GetEnemyTargetPool(player)
	end
	stats.operation = operationDebug
	local shortlist = {}
	local function shortlistTarget(plot, enemyUnit, city, kind)
		if plot == nil then return end
		if enemyUnit ~= nil and not SC_ShouldPursueStrategicEnemyUnit(player, unit, unitInfo, role, unitPlot, enemyUnit, plot) then
			stats.filteredDistantUnits = stats.filteredDistantUnits + 1
			return
		end
		local score, reason = SC_ScoreStrategicTarget(player, unit, role, unitPlot, plot, enemyUnit, city)
		local priority = score - Map.PlotDistance(unitPlot:GetX(), unitPlot:GetY(), plot:GetX(), plot:GetY()) * 18
		if city ~= nil and SC_IsDedicatedCityCaptureUnit(unit, unitInfo, role)
			and (SC_IsCityReadyForCapture(city) or (SC5 ~= nil and SC5.CanFinishCity(player, unit, city))) then priority = priority + 5000 end
		shortlist[#shortlist + 1] = { plot = plot, unit = enemyUnit, city = city, kind = kind, score = score,
			reason = reason, priority = priority, key = kind..":"..tostring(plot:GetX())..":"..tostring(plot:GetY()) }
	end
	for _, city in ipairs(targetPool.cities) do
		if SC_IsEnemyTargetCityValid(player, city) then
			shortlistTarget(city:Plot(), nil, city, "city")
		end
	end
	for _, enemyUnit in ipairs(targetPool.units) do
		if SC_IsEnemyTargetUnitValid(player, enemyUnit) then
			shortlistTarget(enemyUnit:GetPlot(), enemyUnit, nil, "unit")
		end
	end
	-- Bound expensive firing-position/path searches, not the visible-world scan.
	table.sort(shortlist, function(a, b)
		if a.priority ~= b.priority then return a.priority > b.priority end
		return a.key < b.key
	end)
	local searchLimit = math.min(#shortlist, math.max(3, SC_GetConfig("StrategicPositionSearchLimit", 6)))
	for i = 1, searchLimit do
		local c = shortlist[i]
		considerTarget(c.plot, c.unit, c.city, c.kind, c.score, c.reason)
	end
	stats.shortlisted, stats.availableTargets = searchLimit, #shortlist
	SC_Debug("decision5 movement unit="..tostring(unitKey).." available="..tostring(#shortlist).." searched="..tostring(searchLimit)
		.." chosen="..tostring(bestPlan and bestPlan.targetKey or "none").." noPosition="..tostring(stats.noMovePlot)
		.." stationary="..tostring(stats.stationary).." reason="..tostring(bestPlan and bestPlan.reason or "no-feasible-shortlisted-target"))
	return bestPlan, stats
end

function SC_FindTaskRallyMovePlan(player, unit, reservedMovePlots, stats)
	if player == nil or unit == nil or SC_StrategyGetUnitTask == nil then return nil, stats end
	local task = SC_StrategyGetUnitTask(unit)
	local targetPlot = task ~= nil and task.targetPlot or nil
	local unitPlot = unit:GetPlot()
	local unitInfo = SC_GetUnitInfo(unit)
	if targetPlot == nil or unitPlot == nil or unitInfo == nil then return nil, stats end
	local distance = Map.PlotDistance(unitPlot:GetX(), unitPlot:GetY(), targetPlot:GetX(), targetPlot:GetY())
	local rallyRadius = SC_GetConfig("OperationRallyRadius", 3)
	if distance <= rallyRadius then return nil, stats end
	stats = stats or {}
	local role = SC_GetUnitRole(unit, unitInfo)
	local profile = SC_GetUnitCapabilityProfile(unit, unitInfo, role)
	local movePlot = nil
	local mode = "rally"
	if SC_IsStrategicRangedUnit(unit, unitInfo, role, profile) then
		movePlot = SC_FindStandoffMovePlot(player, unit, role, targetPlot, reservedMovePlots, stats)
		mode = "rally-standoff"
	end
	if movePlot == nil then
		movePlot = SC_FindSafeAdvanceWaypoint(player, unit, targetPlot, reservedMovePlots, stats, SC_GetConfig("StrategicWaypointRadius", 5))
		mode = "rally-waypoint"
	end
	if movePlot == nil then return nil, stats end
	local moveDistance = Map.PlotDistance(unitPlot:GetX(), unitPlot:GetY(), movePlot:GetX(), movePlot:GetY())
	if moveDistance <= 0 then return nil, stats end
	local score = 1800 - distance * 10 - moveDistance * 5
	stats.bestScore = score
	stats.bestKind = "rally"
	stats.bestReason = "task-rally:"..tostring(task.kind)..":"..tostring(task.operationID or "-")
	return {
		targetPlot = targetPlot, movePlot = movePlot, mode = mode, kind = "rally",
		reason = stats.bestReason, targetScore = score, planScore = score,
		moveDistance = moveDistance, targetDistance = distance,
		targetKey = "rally|"..SC_GetStablePlotKey(targetPlot), targetCapacity = 999, targetCommitted = 0
	}, stats
end

local function SC_CanStrategicMoveRole(role)
	local war = SC_GetConfig("WarProfile", "ADVANCE")
	if role == "fighter" or role == "bomber" or role == "carrier_air" or role == "missile" or role == "nuke" then
		return false
	end
	if war == "DEFENSE" then
		return false
	end
	if war == "NAVAL" then
		return role == "carrier" or role == "naval_melee" or role == "submarine" or role == "missile_carrier" or role == "naval_ranged"
	end
	if war == "ASSAULT" then
		return role == "carrier" or role == "fast_assault" or role == "assault" or role == "naval_melee" or role == "submarine" or role == "missile_carrier" or role == "naval_ranged" or role == "siege" or role == "land_ranged"
	end
	return role == "carrier" or role == "fast_assault" or role == "assault" or role == "naval_melee" or role == "submarine" or role == "missile_carrier" or role == "naval_ranged" or role == "siege" or role == "land_ranged"
end

function SC_StrategicMoveRequiresSeaTransit(unit, unitInfo, sourcePlot, movePlot)
	if unit == nil or unitInfo == nil or sourcePlot == nil or movePlot == nil or unitInfo.Domain ~= "DOMAIN_LAND" then
		return false
	end
	local sourceWater = SC_GetSafeNumber(function() return sourcePlot:IsWater() and 1 or 0 end, 0) > 0
	local moveWater = SC_GetSafeNumber(function() return movePlot:IsWater() and 1 or 0 end, 0) > 0
	if sourceWater or moveWater or SC_IsUnitEmbarked(unit) then
		return true
	end
	local sourceArea = SC_GetSafeNumber(function() return sourcePlot:GetArea() end, -1)
	local moveArea = SC_GetSafeNumber(function() return movePlot:GetArea() end, -1)
	return sourceArea >= 0 and moveArea >= 0 and sourceArea ~= moveArea
end

function SC_GetAirliftBuildingIDs()
	if SC_AIRLIFT_BUILDING_IDS ~= nil then
		return SC_AIRLIFT_BUILDING_IDS
	end
	SC_AIRLIFT_BUILDING_IDS = {}
	if GameInfo == nil or GameInfo.Buildings == nil then
		return SC_AIRLIFT_BUILDING_IDS
	end
	local ok, err = pcall(function()
		for buildingInfo in GameInfo.Buildings() do
			if buildingInfo ~= nil and buildingInfo.ID ~= nil and SC_DBFlag(buildingInfo.Airlift) then
				table.insert(SC_AIRLIFT_BUILDING_IDS, buildingInfo.ID)
			end
		end
	end)
	if not ok then
		SC_Debug("airlift network building-scan-failed err="..tostring(err))
	end
	return SC_AIRLIFT_BUILDING_IDS
end

function SC_CityHasAirliftFacility(city)
	if city == nil then
		return false, nil
	end
	for _, buildingID in ipairs(SC_GetAirliftBuildingIDs()) do
		local hasBuilding = false
		local ok = pcall(function() hasBuilding = city:IsHasBuilding(buildingID) end)
		if ok and hasBuilding then
			local buildingType = tostring(buildingID)
			pcall(function()
				local info = GameInfo.Buildings[buildingID]
				if info ~= nil and info.Type ~= nil then
					buildingType = info.Type
				end
			end)
			return true, buildingType
		end
	end
	return false, nil
end

function SC_GetPlayerAirliftCities(player)
	local cities = {}
	if player == nil then
		return cities
	end
	for city in player:Cities() do
		local hasFacility, facilityType = SC_CityHasAirliftFacility(city)
		if hasFacility then
			table.insert(cities, {
				city = city,
				plot = city:Plot(),
				facilityType = facilityType
			})
		end
	end
	return cities
end

function SC_IsAirliftCityEntryAtPlot(entry, plot)
	if entry == nil or entry.plot == nil or plot == nil then
		return false
	end
	return entry.plot:GetX() == plot:GetX() and entry.plot:GetY() == plot:GetY()
end

function SC_GetSafePlotIndex(plot)
	if plot == nil then
		return -1
	end
	return SC_GetSafeNumber(function() return plot:GetPlotIndex() end, -1)
end

function SC_ResolvePendingAirlift(unit)
	local unitKey = SC_GetUnitTurnKey(unit)
	local pending = unitKey ~= nil and SC_AIRLIFT_PENDING[unitKey] or nil
	if pending == nil then
		return nil
	end
	local currentPlot = unit:GetPlot()
	local currentIndex = SC_GetSafePlotIndex(currentPlot)
	local turn = SC_GetCurrentGameTurn()
	if currentIndex == pending.destinationIndex or (currentIndex >= 0 and currentIndex ~= pending.sourceIndex) then
		SC_Debug("strategicMove airlift confirmed unit="..SC_GetUnitDebugLabel(unit)..
			" source="..tostring(pending.sourceX)..","..tostring(pending.sourceY)..
			" destination="..tostring(pending.destinationX)..","..tostring(pending.destinationY)..
			" actual="..SC_GetPlotDebug(currentPlot)..
			" delay="..tostring(math.max(0, turn - (pending.turn or turn))))
		SC_AIRLIFT_PENDING[unitKey] = nil
		return "confirmed"
	end
	if turn <= (pending.turn or turn) then
		return "pending"
	end
	SC_Debug("strategicMove airlift expired unit="..SC_GetUnitDebugLabel(unit)..
		" source="..tostring(pending.sourceX)..","..tostring(pending.sourceY)..
		" destination="..tostring(pending.destinationX)..","..tostring(pending.destinationY)..
		" actual="..SC_GetPlotDebug(currentPlot)..
		" queuedTurn="..tostring(pending.turn).." currentTurn="..tostring(turn))
	SC_AIRLIFT_PENDING[unitKey] = nil
	return "expired"
end

function SC_GetBestAirliftDestination(player, unit, sourceEntry, targetPlot, airliftCities, requireNativeCheck)
	if player == nil or unit == nil or sourceEntry == nil or sourceEntry.plot == nil or targetPlot == nil then
		return nil, nil, nil
	end
	local sourcePlot = sourceEntry.plot
	local sourceTargetDistance = Map.PlotDistance(sourcePlot:GetX(), sourcePlot:GetY(), targetPlot:GetX(), targetPlot:GetY())
	local targetArea = SC_GetSafeNumber(function() return targetPlot:GetArea() end, -1)
	local bestEntry = nil
	local bestScore = -999999
	local bestSaved = nil
	local unitKey = SC_GetUnitTurnKey(unit)
	local recentRoute = unitKey ~= nil and SC_AIRLIFT_RECENT_ROUTE[unitKey] or nil
	local recentAge = recentRoute ~= nil and SC_GetCurrentGameTurn() - (recentRoute.turn or -9999) or 9999
	for _, entry in ipairs(airliftCities or {}) do
		if entry ~= nil and entry.plot ~= nil and not SC_IsAirliftCityEntryAtPlot(entry, sourcePlot) then
			local ownerID = SC_GetSafeNumber(function() return entry.plot:GetOwner() end, -1)
			local legal = ownerID == player:GetID()
			local entryIndex = SC_GetSafePlotIndex(entry.plot)
			if legal and recentRoute ~= nil
				and recentAge >= 0 and recentAge <= SC_GetConfig("AirliftReverseCooldownTurns", 3)
				and entryIndex == recentRoute.sourceIndex then
				legal = false
			end
			if legal and requireNativeCheck then
				local checked, result = pcall(function()
					return unit:CanAirliftAt(sourcePlot, entry.plot:GetX(), entry.plot:GetY())
				end)
				legal = checked and result == true
			end
			if legal then
				local destinationDistance = Map.PlotDistance(entry.plot:GetX(), entry.plot:GetY(), targetPlot:GetX(), targetPlot:GetY())
				local saved = sourceTargetDistance - destinationDistance
				local destinationArea = SC_GetSafeNumber(function() return entry.plot:GetArea() end, -1)
				local score = saved * 100 - destinationDistance * 4
				if targetArea >= 0 and destinationArea == targetArea then
					score = score + 2400
				end
				if score > bestScore then
					bestScore = score
					bestEntry = entry
					bestSaved = saved
				end
			end
		end
	end
	return bestEntry, bestSaved, bestScore
end

function SC_FindStrategicAirliftPlan(player, unit, unitInfo, targetPlot, airliftCities, reservedMovePlots, stats)
	if not SC_GetConfig("PreferAirliftOverSeaTransit", true)
		or player == nil or unit == nil or unitInfo == nil or targetPlot == nil
		or unitInfo.Domain ~= "DOMAIN_LAND" or SC_IsUnitEmbarked(unit) then
		return nil, "ineligible"
	end
	if airliftCities == nil or #airliftCities < 2 then
		return nil, "network-too-small:"..tostring(airliftCities ~= nil and #airliftCities or 0)
	end
	local unitPlot = unit:GetPlot()
	if unitPlot == nil then
		return nil, "no-unit-plot"
	end
	local currentArea = SC_GetSafeNumber(function() return unitPlot:GetArea() end, -1)
	local targetArea = SC_GetSafeNumber(function() return targetPlot:GetArea() end, -1)
	local crossAreaTarget = currentArea >= 0 and targetArea >= 0 and currentArea ~= targetArea
	local minSaved = SC_GetConfig("AirliftMinDistanceSaved", 12)
	local currentTargetDistance = Map.PlotDistance(unitPlot:GetX(), unitPlot:GetY(), targetPlot:GetX(), targetPlot:GetY())

	for _, sourceEntry in ipairs(airliftCities) do
		if SC_IsAirliftCityEntryAtPlot(sourceEntry, unitPlot) then
			local canAirlift = false
			local checked = pcall(function() canAirlift = unit:CanAirlift(unitPlot, false) end)
			if not checked or not canAirlift then
				return nil, "source-native-check-failed"
			end
			local destination, saved = SC_GetBestAirliftDestination(player, unit, sourceEntry, targetPlot, airliftCities, true)
			if destination ~= nil and (saved >= minSaved or (crossAreaTarget and saved > 0)) then
				return {
					mode = "airlift",
					movePlot = destination.plot,
					sourceEntry = sourceEntry,
					destinationEntry = destination,
					distanceSaved = saved,
					crossAreaTarget = crossAreaTarget
				}, "direct"
			end
			return nil, destination == nil and "no-legal-destination" or "insufficient-distance-saved:"..tostring(saved)
		end
	end

	local bestSource = nil
	local bestDestination = nil
	local bestSaved = nil
	local bestScore = -999999
	local stageMaxDistance = SC_GetConfig("AirliftStageMaxDistance", 24)
	for _, sourceEntry in ipairs(airliftCities) do
		if sourceEntry.plot ~= nil then
			local sourceArea = SC_GetSafeNumber(function() return sourceEntry.plot:GetArea() end, -1)
			local sourceDistance = Map.PlotDistance(unitPlot:GetX(), unitPlot:GetY(), sourceEntry.plot:GetX(), sourceEntry.plot:GetY())
			if sourceArea == currentArea and sourceDistance > 0 and sourceDistance <= stageMaxDistance then
				local usable = SC_MoveCandidateIsUsable(player, unit, unitInfo, unitPlot, sourceEntry.plot, SC_GetUnitStackLayer(unit), reservedMovePlots, nil, stats)
				if usable then
					local destination = SC_GetBestAirliftDestination(player, unit, sourceEntry, targetPlot, airliftCities, false)
					local destinationDistance = destination ~= nil
						and Map.PlotDistance(destination.plot:GetX(), destination.plot:GetY(), targetPlot:GetX(), targetPlot:GetY()) or 9999
					local effectiveSaved = currentTargetDistance - sourceDistance - destinationDistance
					if destination ~= nil and effectiveSaved >= minSaved then
						local score = effectiveSaved * 100 - sourceDistance * 15
						if score > bestScore then
							bestScore = score
							bestSource = sourceEntry
							bestDestination = destination
							bestSaved = effectiveSaved
						end
						end
					end
			end
		end
	end
	if bestSource == nil then
		return nil, "no-reachable-source"
	end
	local stagePlot = bestSource.plot
	local sourceDistance = Map.PlotDistance(unitPlot:GetX(), unitPlot:GetY(), stagePlot:GetX(), stagePlot:GetY())
	if sourceDistance > SC_GetConfig("AirliftWaypointTriggerDistance", 5) then
		local waypoint = SC_FindSafeAdvanceWaypoint(player, unit, stagePlot, reservedMovePlots, stats)
		if waypoint == nil then
			return nil, "no-safe-source-waypoint"
		end
		stagePlot = waypoint
	end
	return {
		mode = "airlift-stage",
		movePlot = stagePlot,
		sourceEntry = bestSource,
		destinationEntry = bestDestination,
		distanceSaved = bestSaved,
		crossAreaTarget = crossAreaTarget
	}, "stage"
end

function SC_TryStrategicAirlift(player, unit, sourceEntry, destinationEntry)
	if player == nil or unit == nil or sourceEntry == nil or destinationEntry == nil
		or sourceEntry.plot == nil or destinationEntry.plot == nil then
		return false
	end
	local ownerID, identityUnitID, unitLabel = SC_GetUnitIdentity(unit)
	local unitPlot = unit:GetPlot()
	if unitPlot == nil or not SC_IsAirliftCityEntryAtPlot(sourceEntry, unitPlot)
		or SC_GetSafeNumber(function() return destinationEntry.plot:GetOwner() end, -1) ~= player:GetID() then
		SC_Debug("strategicMove airlift rejected unit="..SC_GetUnitDebugLabel(unit).." reason=invalid-endpoints")
		return false
	end
	local canSource = false
	local sourceChecked = pcall(function() canSource = unit:CanAirlift(unitPlot, false) end)
	local canDestination = false
	local destinationChecked = pcall(function()
		canDestination = unit:CanAirliftAt(unitPlot, destinationEntry.plot:GetX(), destinationEntry.plot:GetY())
	end)
	if not sourceChecked or not canSource or not destinationChecked or not canDestination then
		SC_Debug("strategicMove airlift rejected unit="..SC_GetUnitDebugLabel(unit)..
			" reason=native-check source="..SC_BoolText(sourceChecked and canSource)..
			" destination="..SC_BoolText(destinationChecked and canDestination))
		return false
	end
	local mission = SC_GetMissionID("MISSION_AIRLIFT")
	if mission == nil then
		SC_Debug("strategicMove airlift rejected unit="..SC_GetUnitDebugLabel(unit).." reason=missing-mission")
		return false
	end
	local beforeIndex = SC_GetSafePlotIndex(unitPlot)
	local destinationIndex = SC_GetSafePlotIndex(destinationEntry.plot)
	local sent, missionStatus, liveUnit = SC_SendUnitMission(unit, mission, destinationEntry.plot:GetX(), destinationEntry.plot:GetY())
	if missionStatus == "unit-removed" then
		SC_Debug("strategicMove airlift unit-removed unit="..tostring(unitLabel)..
			" source="..SC_GetPlotDebug(sourceEntry.plot)..
			" destination="..SC_GetPlotDebug(destinationEntry.plot))
		return sent
	end
	unit = liveUnit or SC_ResolveLiveUnit(ownerID, identityUnitID)
	if unit == nil then return sent end
	if not sent then
		SC_Debug("strategicMove airlift send-failed unit="..tostring(unitLabel)..
			" source="..SC_GetPlotDebug(sourceEntry.plot)..
			" destination="..SC_GetPlotDebug(destinationEntry.plot))
		return false
	end
	local unitKey = SC_GetUnitTurnKey(unit)
	if unitKey ~= nil then
		SC_AIRLIFT_PENDING[unitKey] = {
			sourceIndex = beforeIndex,
			destinationIndex = destinationIndex,
			sourceX = sourceEntry.plot:GetX(),
			sourceY = sourceEntry.plot:GetY(),
			destinationX = destinationEntry.plot:GetX(),
			destinationY = destinationEntry.plot:GetY(),
			turn = SC_GetCurrentGameTurn()
		}
		SC_AIRLIFT_RECENT_ROUTE[unitKey] = {
			sourceIndex = beforeIndex,
			destinationIndex = destinationIndex,
			turn = SC_GetCurrentGameTurn()
		}
	end
	SC_Debug("strategicMove airlift queued unit="..tostring(unitLabel)..
		" source="..SC_GetPlotDebug(sourceEntry.plot)..
		" destination="..SC_GetPlotDebug(destinationEntry.plot)..
		" sourceFacility="..tostring(sourceEntry.facilityType)..
		" destinationFacility="..tostring(destinationEntry.facilityType)..
		" sourceIndex="..tostring(beforeIndex).." destinationIndex="..tostring(destinationIndex))
	SC_ResolvePendingAirlift(unit)
	return true
end

function SC_EvaluateStrategicSeaTransit(player, unit, unitInfo, role, sourcePlot, movePlot, mode)
	if mode == "paradrop" or mode == "airlift" or not SC_StrategicMoveRequiresSeaTransit(unit, unitInfo, sourcePlot, movePlot) then
		return true, 0, 0, 0, "land-route"
	end
	local threatRadius = SC_GetConfig("TransportThreatRadius", 6)
	local threatsAtSource = SC_CountEnemySeaThreatsNearPlot(player, sourcePlot, threatRadius)
	local threatsAtDestination = SC_CountEnemySeaThreatsNearPlot(player, movePlot, threatRadius)
	local threats = math.max(threatsAtSource, threatsAtDestination)
	local protectionTier = SC_GetUnitProtectionTier(unit, unitInfo, role)
	local required = 0
	if threats > 0 then
		required = SC_GetConfig("HighValueSeaTransitMinEscorts", 1)
	end
	if threats >= SC_GetConfig("HighValueSeaTransitSevereThreatCount", 2) and protectionTier >= 2 then
		required = math.max(required, SC_GetConfig("HighValueSeaTransitSevereEscorts", 2))
	end
	local coverage = math.max(
		SC_CountFriendlyNavalEscortsNearPlot(player, sourcePlot, SC_GetConfig("TransportEscortRadius", 2)),
		SC_CountFriendlyNavalEscortsNearPlot(player, movePlot, SC_GetConfig("TransportEscortRadius", 2)))
	local safe = coverage >= required
	if SC_IsUnitEmbarked(unit) and threats > 0 and SC_GetConfig("TransportNeverAdvanceUnderThreat", false)
		and coverage < required then
		safe = false
	end
	return safe, threats, coverage, required, "tier="..tostring(protectionTier)..",sourceThreats="..tostring(threatsAtSource)..",destinationThreats="..tostring(threatsAtDestination)
end

function SC_TryStageStrategicSeaEscort(player, transport, destinationPlot, reserved)
	if player == nil or transport == nil or destinationPlot == nil or SC_FindTransportEscortMovePlot == nil then
		return false, nil, nil
	end
	local bestEscort = nil
	local bestMovePlot = nil
	local bestScore = -999999
	for escort in player:Units() do
		if escort ~= nil and escort ~= transport and not escort:IsDead() and escort:CanMove() then
			local escortInfo = SC_GetUnitInfo(escort)
			local escortRole = SC_GetUnitRole(escort, escortInfo)
			local escortKey = SC_GetUnitTurnKey(escort)
			if SC_IsNavalEscortUnit(escort, escortInfo, escortRole)
				and (escortKey == nil or not SC_TRANSPORT_ESCORT_ORDERED_THIS_TURN[escortKey]) then
				local escortPlot = escort:GetPlot()
				local movePlot = escortPlot ~= nil and SC_FindTransportEscortMovePlot(player, escort, destinationPlot, reserved, {}) or nil
				if movePlot ~= nil then
					local distance = Map.PlotDistance(escortPlot:GetX(), escortPlot:GetY(), destinationPlot:GetX(), destinationPlot:GetY())
					local profile = SC_GetUnitCapabilityProfile(escort, escortInfo, escortRole)
					local score = 2200 - distance * 35 + (profile.intercept or 0)
					if profile.doctrineClass == "air_defense_screen" then score = score + 420 end
					if score > bestScore then
						bestScore = score
						bestEscort = escort
						bestMovePlot = movePlot
					end
				end
			end
		end
	end
	local escortMoved, escortStatus, liveEscort = false, nil, nil
	if bestEscort ~= nil and bestMovePlot ~= nil then
		escortMoved, escortStatus, liveEscort = SC_TryMoveMission(bestEscort, bestMovePlot, "sea-transit-screen", true)
	end
	if escortStatus == "unit-removed" then
		return false, nil, bestMovePlot
	end
	if not escortMoved then
		return false, bestEscort, bestMovePlot
	end
	bestEscort = liveEscort or bestEscort
	local escortKey = SC_GetUnitTurnKey(bestEscort)
	if escortKey ~= nil then
		SC_TRANSPORT_ESCORT_ORDERED_THIS_TURN[escortKey] = true
		SC_MarkStrategicUnitDone(bestEscort)
	end
	SC_ReserveMovePlot(reserved, bestMovePlot, SC_GetUnitStackLayer(bestEscort))
	return true, bestEscort, bestMovePlot
end

local function SC_AutomateStrategicMovement(player, atWar)
	if not SC_GetConfig("AutoStrategicMove", true) or not atWar or player == nil then
		SC_Debug("strategicMove skip enabled="..SC_BoolText(SC_GetConfig("AutoStrategicMove", true)).." atWar="..SC_BoolText(atWar).." playerNil="..SC_BoolText(player == nil))
		return 0
	end
	if SC_GetConfig("WarProfile", "ADVANCE") == "DEFENSE" then
		SC_Debug("strategicMove skip reason=defense-profile")
		return 0
	end
	local moved = 0
	local maxMoves = SC_GetConfig("MaxStrategicMovesPerTurn", 80)
	local debugCount = 0
	local debugLimit = SC_GetConfig("DebugUnitDecisionLimit", 60)
	local skipDebugCount = 0
	local skipDebugLimit = SC_GetConfig("DebugCachedUnitDecisionLimit", 8)
	local reservedMovePlots = {}
	local airliftCities = SC_GetPlayerAirliftCities(player)
	local function debugMove(text)
		if SC_GetConfig("DebugUnitDecisions", true) and debugCount < debugLimit then
			debugCount = debugCount + 1
			SC_Debug(text)
		end
	end
	local function debugSkip(text)
		if skipDebugCount < skipDebugLimit then
			skipDebugCount = skipDebugCount + 1
			debugMove(text)
		end
	end
	local orderedUnits = {}
	local pendingAirliftUnits = {}
	for unit in player:Units() do
		local taskAllowed = true
		if unit ~= nil and SC_StrategyUnitAllowsModule ~= nil then taskAllowed = SC_StrategyUnitAllowsModule(unit, "strategicMovement") end
		if unit ~= nil and taskAllowed then
			local pendingStatus = SC_ResolvePendingAirlift(unit)
			local pendingKey = SC_GetUnitTurnKey(unit)
			if pendingStatus == "pending" and pendingKey ~= nil then
				pendingAirliftUnits[pendingKey] = true
			end
			local unitInfo = SC_GetUnitInfo(unit)
			local profile = SC_GetUnitCapabilityProfile(unit, unitInfo)
			local ownerID, unitID = SC_GetUnitIdentity(unit)
			table.insert(orderedUnits, {
				ownerID = ownerID, unitID = unitID,
				phase = SC_GetStrategicMovementPhase(unit, unitInfo),
				power = profile.power or 0
			})
		end
	end
	table.sort(orderedUnits, function(a, b)
		if a.phase ~= b.phase then
			return a.phase < b.phase
		end
		return a.power > b.power
	end)
	SC_Debug("strategicMove start maxMoves="..tostring(maxMoves)..
		" warProfile="..tostring(SC_GetConfig("WarProfile", "ADVANCE"))..
		" airliftCities="..tostring(#airliftCities)..
		" airliftBuildingTypes="..tostring(#SC_GetAirliftBuildingIDs()))
	for _, identity in ipairs(orderedUnits) do
		if moved >= maxMoves then
			break
		end
		local unit = SC_ResolveLiveUnit(identity.ownerID, identity.unitID)
		if unit ~= nil and unit:CanMove() and SC_UnitIsFitForCombat(unit, SC_GetUnitInfo(unit)) then
			local unitInfo = SC_GetUnitInfo(unit)
			local role = SC_GetUnitRole(unit, unitInfo)
			local doctrineClass = SC_GetUnitDoctrineClass(unit, unitInfo, role)
			local unitKey = SC_GetUnitTurnKey(unit)
			local strategicCount = SC_GetStrategicOrderCount(unitKey)
			local strategicCap = SC_GetStrategicOrderCapForUnit(unit, unitInfo, role)
			local taskAllowed, taskKind = true, "legacy"
			if SC_StrategyUnitAllowsModule ~= nil then taskAllowed, taskKind = SC_StrategyUnitAllowsModule(unit, "strategicMovement") end
			if not taskAllowed then
				if unitKey ~= nil then SC_STRATEGIC_ORDERED_THIS_TURN[unitKey] = strategicCap end
				debugSkip("strategicMove task-skip unit="..SC_GetUnitDebugLabel(unit).." task="..tostring(taskKind).." directive="..tostring(SC_StrategyGetUnitTaskDebug and SC_StrategyGetUnitTaskDebug(unit) or "-"))
			elseif not SC_IsCombatAutomationUnit(unit, unitInfo) then
				debugSkip("strategicMove noncombat-skip unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role))
			elseif unitKey ~= nil and pendingAirliftUnits[unitKey] then
				SC_STRATEGIC_ORDERED_THIS_TURN[unitKey] = strategicCap
				debugSkip("strategicMove pending-airlift-skip unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role))
			elseif unitKey ~= nil and strategicCount >= strategicCap then
				debugSkip("strategicMove turn-skip unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role).." class="..tostring(doctrineClass).." orders="..tostring(strategicCount).."/"..tostring(strategicCap))
			elseif SC_IsFragileTransportUnit ~= nil and SC_IsFragileTransportUnit(unit, unitInfo)
				and unitKey ~= nil and SC_TRANSPORT_ESCORT_ORDERED_THIS_TURN[unitKey] then
				if unitKey ~= nil then
					SC_STRATEGIC_ORDERED_THIS_TURN[unitKey] = strategicCap
				end
				debugSkip("strategicMove convoy-owned-skip unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role))
			elseif SC_CanStrategicMoveRole(role) then
				local plan = nil
				local planStats = nil
				if SC_IsScreenDoctrineClass(doctrineClass) then
					plan, planStats = SC_FindSupportFormationMovePlan(player, unit, reservedMovePlots, {})
				end
				if plan == nil then
					plan, planStats = SC_FindStrategicMovePlan(player, unit, reservedMovePlots)
				end
				if plan == nil then
					plan, planStats = SC_FindTaskRallyMovePlan(player, unit, reservedMovePlots, planStats)
				end
				local unitPlot = unit:GetPlot()
				if plan ~= nil and unitPlot ~= nil then
					local targetPlot = plan.targetPlot
					local movePlot = plan.movePlot
					local mode = plan.mode or "direct"
					local airliftPlan = nil
					local airliftReason = "formation-local"
					if plan.kind ~= "formation" then
						airliftPlan, airliftReason = SC_FindStrategicAirliftPlan(player, unit, unitInfo, targetPlot, airliftCities, reservedMovePlots, planStats)
					end
					if airliftPlan ~= nil then
						movePlot = airliftPlan.movePlot
						mode = airliftPlan.mode
						plan.movePlotKey = SC_GetStablePlotKey(movePlot)
						plan.airliftPlan = airliftPlan
						plan.reason = tostring(plan.reason or "base")..
							",airlift:"..tostring(airliftReason)..
							",saved:"..tostring(airliftPlan.distanceSaved)
					elseif SC_StrategicMoveRequiresSeaTransit(unit, unitInfo, unitPlot, targetPlot) and #airliftCities >= 2 then
						debugMove("strategicMove airlift-unavailable unit="..SC_GetUnitDebugLabel(unit)..
							" target="..SC_GetPlotDebug(targetPlot)..
							" reason="..tostring(airliftReason).." fallback=escorted-sea-transit")
					end
					if movePlot ~= nil then
						local distance = Map.PlotDistance(unitPlot:GetX(), unitPlot:GetY(), movePlot:GetX(), movePlot:GetY())
						if distance > 0 then
							local seaSafe, seaThreats, seaCoverage, seaRequired, seaReason = SC_EvaluateStrategicSeaTransit(player, unit, unitInfo, role, unitPlot, movePlot, mode)
							if not seaSafe then
								local escortMoved, escort, escortPlot = SC_TryStageStrategicSeaEscort(player, unit, movePlot, reservedMovePlots)
								local held = SC_TryHoldTransport(unit, "blocked-sea-transit")
								if unitKey ~= nil and (escortMoved or held) then
									SC_STRATEGIC_ORDERED_THIS_TURN[unitKey] = strategicCap
								end
								debugMove("strategicMove blocked-sea-transit unit="..SC_GetUnitDebugLabel(unit)..
									" class="..tostring(doctrineClass)..
									" tier="..tostring(SC_GetUnitProtectionTier(unit, unitInfo, role))..
									" from="..SC_GetPlotDebug(unitPlot)..
									" moveTo="..SC_GetPlotDebug(movePlot)..
									" threats="..tostring(seaThreats)..
									" coverage="..tostring(seaCoverage).."/"..tostring(seaRequired)..
									" escortMoved="..SC_BoolText(escortMoved)..
									" escort="..SC_GetUnitDebugLabel(escort)..
									" escortTo="..SC_GetPlotDebug(escortPlot)..
									" held="..SC_BoolText(held)..
									" reason="..tostring(seaReason))
								if escortMoved or held then
									if SC_StrategyRecordTaskAction ~= nil then SC_StrategyRecordTaskAction(unit, "strategicMovement", held and "convoy-hold" or "escort-stage") end
									moved = moved + 1
								end
							else
							debugMove("strategicMove order unit="..SC_GetUnitDebugLabel(unit)..
								" role="..tostring(role)..
								" class="..tostring(doctrineClass)..
								" tag="..tostring(SC_GetUnitCombatTag(unit, unitInfo, role))..
								" mode="..mode..
								" kind="..tostring(plan.kind)..
								" from="..SC_GetPlotDebug(unitPlot)..
								" target="..SC_GetPlotDebug(targetPlot)..
								" moveTo="..SC_GetPlotDebug(movePlot)..
								" distance="..tostring(distance)..
								" targetDistance="..tostring(plan.targetDistance)..
								" commitment="..tostring(plan.targetCommitted or 0).."/"..tostring(plan.targetCapacity or "-")..
								" orders="..tostring(strategicCount).."/"..tostring(strategicCap)..
								" score="..tostring(plan.planScore)..
								" reason="..tostring(plan.reason or "nil")..
								" "..SC_GetStrategicPlanStatsDebug(planStats))
							local ok = false
							local moveStatus = nil
							local ownerID, identityUnitID, unitLabel = SC_GetUnitIdentity(unit)
							if mode == "airlift" then
								ok = SC_TryStrategicAirlift(player, unit, plan.airliftPlan.sourceEntry, plan.airliftPlan.destinationEntry)
							elseif mode == "paradrop" then
								local paradropMission = SC_GetMissionID("MISSION_PARADROP")
								ok = paradropMission ~= nil and SC_SendUnitMission(unit, paradropMission, movePlot:GetX(), movePlot:GetY())
								if not ok and paradropMission ~= nil and SC_TryDirectTargetedMission ~= nil then
									ok = SC_TryDirectTargetedMission(unit, paradropMission, movePlot, "strategic-paradrop")
								end
							else
								local liveUnit = nil
								ok, moveStatus, liveUnit = SC_TryMoveMission(unit, movePlot, "strategic", true)
								if liveUnit ~= nil then unit = liveUnit end
							end
							local resolvedUnit = SC_ResolveLiveUnit(ownerID, identityUnitID)
							if moveStatus == "unit-removed" or resolvedUnit == nil then
								if unitKey ~= nil then SC_STRATEGIC_ORDERED_THIS_TURN[unitKey] = strategicCap end
								debugMove("strategicMove unit-removed unit="..tostring(unitLabel)..
									" mode="..tostring(mode).." target="..SC_GetPlotDebug(targetPlot)..
									" moveTo="..SC_GetPlotDebug(movePlot).." status="..tostring(moveStatus))
							elseif ok then
								unit = resolvedUnit
								if mode == "airlift" or string.sub(tostring(mode), 1, 13) == "airlift-stage" or mode == "paradrop" or mode == "formation" or string.sub(tostring(mode), 1, 8) == "standoff" or string.sub(tostring(mode), 1, 7) == "capture" then
									SC_ReserveMovePlot(reservedMovePlots, movePlot, SC_GetUnitStackLayer(unit))
								end
								if unitKey ~= nil then
									SC_RecordStrategicOrder(unitKey)
									if plan.kind ~= "formation" then
										SC_RecordStrategicTargetCommitment(unitKey, plan.targetKey)
										SC_RecordStrategicTargetMemory(unit, unitKey, plan.targetKey, targetPlot, plan.kind)
									end
									SC_TACTICAL_NO_TARGET_THIS_TURN[unitKey] = nil
									SC_TACTICAL_QUEUED_THIS_TURN[unitKey] = nil
								end
								if SC_StrategyRecordTaskAction ~= nil then SC_StrategyRecordTaskAction(unit, "strategicMovement", mode) end
								moved = moved + 1
							else
								if unitKey ~= nil and plan.movePlotKey ~= nil then
									SC_EXECUTION_REJECTED_MOVE_PLOTS_THIS_TURN[unitKey] = SC_EXECUTION_REJECTED_MOVE_PLOTS_THIS_TURN[unitKey] or {}
									SC_EXECUTION_REJECTED_MOVE_PLOTS_THIS_TURN[unitKey][plan.movePlotKey] = true
								end
								debugMove("strategicMove mission-failed unit="..SC_GetUnitDebugLabel(unit)..
									" role="..tostring(role)..
									" tag="..tostring(SC_GetUnitCombatTag(unit, unitInfo, role))..
									" mode="..mode..
									" kind="..tostring(plan.kind)..
									" target="..SC_GetPlotDebug(targetPlot)..
									" moveTo="..SC_GetPlotDebug(movePlot)..
									" reason="..tostring(plan.reason or "nil")..
									" state="..SC_GetUnitOrderDebug(unit)..
									" "..SC_GetStrategicPlanStatsDebug(planStats))
								-- Rejected orders are not completed orders. Allow later waves to
								-- rebuild the live world and try a different executable plan.
							end
							end
						else
							debugMove("strategicMove already-positioned unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role).." plot="..SC_GetPlotDebug(unitPlot).." "..SC_GetStrategicPlanStatsDebug(planStats))
							if unitKey ~= nil then
								SC_STRATEGIC_ORDERED_THIS_TURN[unitKey] = strategicCap
							end
						end
					else
						debugMove("strategicMove no-move-plot unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role).." target="..SC_GetPlotDebug(targetPlot).." range="..tostring(SC_GetUnitRangeValue(unit, unitInfo)).." "..SC_GetStrategicPlanStatsDebug(planStats))
					end
				else
					debugMove("strategicMove no-plan unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role).." "..SC_GetStrategicPlanStatsDebug(planStats))
				end
			else
				debugSkip("strategicMove role-skip unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role))
			end
		end
	end
	SC_Debug("strategicMove end moved="..tostring(moved))
	return moved
end

SC_UnitNeedsOrder = function(unit)
	if unit == nil then
		return false
	end
	local isDead = false
	pcall(function() isDead = unit:IsDead() end)
	if isDead then
		return false
	end
	local ok, ready = pcall(function()
		return unit:IsReadyToMove()
	end)
	if ok then
		return ready == true
	end
	ok, ready = pcall(function()
		return unit:ReadyToMove()
	end)
	if ok then
		return ready == true
	end
	ok, ready = pcall(function()
		return unit:IsWaiting()
	end)
	if ok and ready then
		return false
	end
	ok, ready = pcall(function()
		return unit:IsAutomated()
	end)
	if ok and ready then
		return false
	end
	return false
end

SC_GetUnitOrderDebug = function(unit)
	if unit == nil then
		return "nil-unit"
	end
	local parts = {}
	local function addBool(name, fn)
		local ok, value = pcall(fn)
		if ok then
			table.insert(parts, name.."="..SC_BoolText(value == true))
		else
			table.insert(parts, name.."=?")
		end
	end
	local function addValue(name, fn)
		local ok, value = pcall(fn)
		if ok then
			table.insert(parts, name.."="..tostring(value))
		else
			table.insert(parts, name.."=?")
		end
	end
	addBool("ready", function() return unit:IsReadyToMove() end)
	addBool("readyLegacy", function() return unit:ReadyToMove() end)
	addBool("waiting", function() return unit:IsWaiting() end)
	addBool("automated", function() return unit:IsAutomated() end)
	addBool("canMove", function() return unit:CanMove() end)
	addValue("moves", function() return unit:MovesLeft() end)
	addValue("activity", function() return unit:GetActivityType() end)
	addValue("damage", function() return unit:GetDamage() end)
	return table.concat(parts, ",")
end

SC_TryDirectTargetedMission = function(unit, missionType, targetPlot, reason)
	if unit == nil or missionType == nil or targetPlot == nil or not SC_GetConfig("DirectPushTargetedMissionFallback", true) then
		return false
	end
	local ownerID, unitID, unitLabel = SC_GetUnitIdentity(unit)
	local unitPlot = nil
	pcall(function() unitPlot = unit:GetPlot() end)
	local ok, err = pcall(function()
		unit:PushMission(missionType, targetPlot:GetX(), targetPlot:GetY(), 0, 0, 1, -1)
	end)
	local liveUnit = SC_ResolveLiveUnit(ownerID, unitID)
	if liveUnit == nil then
		SC_Debug("mission direct-target unit-removed unit="..tostring(unitLabel)..
			" mission="..SC_GetEnumDebugName(MissionTypes, missionType)..
			" target="..SC_GetPlotDebug(targetPlot)..
			" reason="..tostring(reason)..
			" ok="..SC_BoolText(ok).." err="..tostring(err))
		return ok, "unit-removed", nil
	end
	if SC_GetConfig("DebugUnitCommands", true) then
		SC_Debug("mission direct-target unit="..tostring(unitLabel)..
			" mission="..SC_GetEnumDebugName(MissionTypes, missionType)..
			" target="..SC_GetPlotDebug(targetPlot)..
			" reason="..tostring(reason)..
			" ok="..SC_BoolText(ok)..
			" err="..tostring(err)..
			" state="..SC_GetUnitOrderDebug(liveUnit))
	end
	if ok and SC_UnitNeedsOrder(liveUnit) and SC_GetConfig("DebugUnitCommands", true) then
		SC_Debug("mission direct-target-pending unit="..tostring(unitLabel)..
			" mission="..SC_GetEnumDebugName(MissionTypes, missionType)..
			" target="..SC_GetPlotDebug(targetPlot)..
			" state="..SC_GetUnitOrderDebug(liveUnit))
	end
	return ok and not SC_UnitNeedsOrder(liveUnit), ok and "sent" or "send-failed", liveUnit
end

local function SC_TryDirectTargetlessMission(unit, missionType, reason)
	if unit == nil or missionType == nil or not SC_GetConfig("DirectPushMissionFallback", true) then
		return false
	end
	if not SC_IsTargetlessUnitMission(missionType) then
		return false
	end
	if SC_GetMissionID("MISSION_HEAL") == missionType then
		return false
	end
	local ownerID, unitID, unitLabel = SC_GetUnitIdentity(unit)
	local unitKey = SC_GetUnitTurnKey(unit)
	local cacheKey = tostring(unitKey or unitLabel).."|"..tostring(missionType)
	if SC_DIRECT_PUSH_FAILED_THIS_TURN[cacheKey] then
		if SC_GetConfig("DebugUnitCommands", true) then
			SC_Debug("mission direct-push-skip unit="..SC_GetUnitDebugLabel(unit)..
				" mission="..SC_GetEnumDebugName(MissionTypes, missionType)..
				" reason=cached-pending")
		end
		return false
	end
	local ok, err = pcall(function()
		unit:PushMission(missionType)
	end)
	local liveUnit = SC_ResolveLiveUnit(ownerID, unitID)
	if liveUnit == nil then
		SC_Debug("mission direct-push unit-removed unit="..tostring(unitLabel)..
			" mission="..SC_GetEnumDebugName(MissionTypes, missionType)..
			" reason="..tostring(reason)..
			" ok="..SC_BoolText(ok).." err="..tostring(err))
		return ok, "unit-removed", nil
	end
	if SC_GetConfig("DebugUnitCommands", true) then
		SC_Debug("mission direct-push unit="..tostring(unitLabel)..
			" mission="..SC_GetEnumDebugName(MissionTypes, missionType)..
			" reason="..tostring(reason)..
			" ok="..SC_BoolText(ok)..
			" err="..tostring(err)..
			" state="..SC_GetUnitOrderDebug(liveUnit))
	end
	if ok and SC_UnitNeedsOrder(liveUnit) and SC_GetConfig("DebugUnitCommands", true) then
		SC_Debug("mission direct-push-pending unit="..tostring(unitLabel)..
			" mission="..SC_GetEnumDebugName(MissionTypes, missionType)..
			" state="..SC_GetUnitOrderDebug(liveUnit))
	end
	if ok and not SC_UnitNeedsOrder(liveUnit) then
		return true, "sent", liveUnit
	end
	if ok then
		SC_DIRECT_PUSH_FAILED_THIS_TURN[cacheKey] = true
	end
	return false, ok and "pending" or "send-failed", liveUnit
end

local function SC_TryUnitMission(unit, missionType, x, y, allowDirectPush)
	if unit == nil or missionType == nil then
		return false
	end
	local ownerID, unitID, unitLabel = SC_GetUnitIdentity(unit)
	local ok, status, liveUnit = SC_SendUnitMission(unit, missionType, x, y)
	if status == "unit-removed" then
		SC_Debug("mission resolved-by-removal unit="..tostring(unitLabel).." mission="..SC_GetEnumDebugName(MissionTypes, missionType))
		return ok
	end
	unit = liveUnit or SC_ResolveLiveUnit(ownerID, unitID)
	if unit == nil then
		return ok
	end
	if ok then
		if SC_UnitNeedsOrder(unit) and SC_GetConfig("DebugUnitCommands", true) then
			SC_Debug("mission pending-clear unit="..SC_GetUnitDebugLabel(unit).." mission="..SC_GetEnumDebugName(MissionTypes, missionType).." state="..SC_GetUnitOrderDebug(unit))
		end
		if allowDirectPush ~= false and SC_UnitNeedsOrder(unit) then
			local directOK, directStatus = SC_TryDirectTargetlessMission(unit, missionType, "pending-after-net-message")
			if directStatus == "unit-removed" then return directOK end
		end
		return not SC_UnitNeedsOrder(unit)
	end
	return false
end

local function SC_TryUnitCommand(unit, commandType, data1, data2)
	if unit == nil or commandType == nil then
		return false
	end
	local ownerID, unitID, unitLabel = SC_GetUnitIdentity(unit)
	local ok, status, liveUnit = SC_SendUnitCommand(unit, commandType, data1, data2)
	if status == "unit-removed" then
		SC_Debug("command resolved-by-removal unit="..tostring(unitLabel).." command="..SC_GetEnumDebugName(CommandTypes, commandType))
		return ok
	end
	unit = liveUnit or SC_ResolveLiveUnit(ownerID, unitID)
	if unit == nil then return ok end
	if ok and SC_UnitNeedsOrder(unit) and SC_GetConfig("DebugUnitCommands", true) then
		SC_Debug("command pending-clear unit="..SC_GetUnitDebugLabel(unit).." command="..SC_GetEnumDebugName(CommandTypes, commandType).." state="..SC_GetUnitOrderDebug(unit))
	end
	return ok and not SC_UnitNeedsOrder(unit)
end

local function SC_TryUnitActionByType(unit, wantedTypes)
	if unit == nil or GameInfoActions == nil or Game == nil or Game.HandleAction == nil or wantedTypes == nil then
		return false
	end
	local ownerID, unitID, unitLabel = SC_GetUnitIdentity(unit)
	local selected = pcall(function()
		UI.SelectUnit(unit)
	end)
	if not selected then
		return false
	end
	for iAction = 0, #GameInfoActions, 1 do
		local action = GameInfoActions[iAction]
		if action ~= nil and action.Visible and wantedTypes[action.Type] then
			local canHandle = false
			pcall(function() canHandle = Game.CanHandleAction(iAction) end)
			if not canHandle then
				pcall(function() canHandle = Game.CanHandleAction(iAction, 0, 1) end)
			end
			if canHandle then
				local ok, err = pcall(function() Game.HandleAction(iAction) end)
				local liveUnit = SC_ResolveLiveUnit(ownerID, unitID)
				if liveUnit == nil then
					SC_Debug("action unit-removed unit="..tostring(unitLabel).." action="..tostring(action.Type).." index="..tostring(iAction).." ok="..SC_BoolText(ok).." err="..tostring(err))
					return ok
				end
				unit = liveUnit
				if SC_GetConfig("DebugUnitCommands", true) then
					SC_Debug("action unit="..tostring(unitLabel).." action="..tostring(action.Type).." index="..tostring(iAction).." ok="..SC_BoolText(ok).." err="..tostring(err).." state="..SC_GetUnitOrderDebug(unit))
				end
				if ok then
					if SC_UnitNeedsOrder(unit) and SC_GetConfig("DebugUnitCommands", true) then
						SC_Debug("action pending-clear unit="..tostring(unitLabel).." action="..tostring(action.Type).." state="..SC_GetUnitOrderDebug(unit))
					end
					if SC_UnitNeedsOrder(unit) then
						local directOK, directStatus = SC_TryDirectTargetlessMission(unit, SC_GetMissionID(action.Type), "pending-after-action")
						if directStatus == "unit-removed" then return directOK end
					end
					return not SC_UnitNeedsOrder(unit)
				end
			elseif SC_GetConfig("DebugUnitCommands", true) then
				SC_Debug("action cannot-handle unit="..SC_GetUnitDebugLabel(unit).." action="..tostring(action.Type).." index="..tostring(iAction).." state="..SC_GetUnitOrderDebug(unit))
			end
		end
	end
	return false
end

function SC_TryForceClearUnitOrder(unit, reason)
	if unit == nil or not SC_GetConfig("ForceClearStuckUnitOrders", true) then
		return false
	end
	if SC_UnitNeedsOrder ~= nil and not SC_UnitNeedsOrder(unit) then
		return true
	end
	local before = SC_GetUnitOrderDebug(unit)
	local okFinish, errFinish = pcall(function()
		unit:FinishMoves()
	end)
	local afterFinishNeeds = true
	if SC_UnitNeedsOrder ~= nil then
		afterFinishNeeds = SC_UnitNeedsOrder(unit)
	end
	SC_Debug("forceClear unit="..SC_GetUnitDebugLabel(unit)..
		" reason="..tostring(reason)..
		" method=FinishMoves ok="..SC_BoolText(okFinish)..
		" err="..tostring(errFinish)..
		" before="..tostring(before)..
		" after="..SC_GetUnitOrderDebug(unit))
	if okFinish and not afterFinishNeeds then
		SC_Debug("forceClear success unit="..SC_GetUnitDebugLabel(unit).." reason="..tostring(reason).." method=FinishMoves")
		return true
	end
	local okMoves, errMoves = pcall(function()
		unit:SetMoves(0)
	end)
	local afterMovesNeeds = true
	if SC_UnitNeedsOrder ~= nil then
		afterMovesNeeds = SC_UnitNeedsOrder(unit)
	end
	SC_Debug("forceClear unit="..SC_GetUnitDebugLabel(unit)..
		" reason="..tostring(reason)..
		" method=SetMoves0 ok="..SC_BoolText(okMoves)..
		" err="..tostring(errMoves)..
		" before="..tostring(before)..
		" after="..SC_GetUnitOrderDebug(unit))
	if okMoves and not afterMovesNeeds then
		SC_Debug("forceClear success unit="..SC_GetUnitDebugLabel(unit).." reason="..tostring(reason).." method=SetMoves0")
		return true
	end
	return false
end

function SC_GetGreatPersonActionPriority(unitInfo, actionType)
	if unitInfo == nil or actionType == nil then
		return -999999
	end
	local unitType = unitInfo.Type or ""
	local profile = SC_GetConfig("GreatPersonProfile", "AUTO")
	if profile == "SLEEP" then
		return -999999
	end
	local priority = -999999
	if string.find(unitType, "WRITER") ~= nil then
		if actionType == "MISSION_GIVE_POLICIES" then priority = profile == "CULTURE" and 125 or 105 end
		if actionType == "MISSION_CREATE_GREAT_WORK" then priority = profile == "CULTURE" and 120 or 100 end
		if actionType == "MISSION_GOLDEN_AGE" then priority = 20 end
	elseif string.find(unitType, "ARTIST") ~= nil then
		if actionType == "MISSION_GOLDEN_AGE" then priority = 105 end
		if actionType == "MISSION_CREATE_GREAT_WORK" then priority = profile == "CULTURE" and 120 or 100 end
		if actionType == "MISSION_CULTURE_BOMB" then priority = 15 end
	elseif string.find(unitType, "MUSICIAN") ~= nil then
		if actionType == "MISSION_ONE_SHOT_TOURISM" then priority = profile == "CULTURE" and 130 or 105 end
		if actionType == "MISSION_CREATE_GREAT_WORK" then priority = profile == "CULTURE" and 120 or 100 end
		if actionType == "MISSION_GOLDEN_AGE" then priority = 20 end
	elseif string.find(unitType, "SCIENTIST") ~= nil then
		if actionType == "MISSION_DISCOVER" then priority = profile == "SCIENCE" and 140 or 120 end
		if actionType == "MISSION_GOLDEN_AGE" then priority = 10 end
	elseif string.find(unitType, "ENGINEER") ~= nil then
		if actionType == "MISSION_HURRY" then priority = profile == "ENGINEER" and 140 or 120 end
		if actionType == "MISSION_GOLDEN_AGE" then priority = 5 end
	elseif string.find(unitType, "MERCHANT") ~= nil then
		if actionType == "MISSION_TRADE" then priority = 125 end
		if actionType == "MISSION_SELL_EXOTIC_GOODS" then priority = 95 end
		if actionType == "MISSION_BUY_CITY_STATE" then priority = 115 end
		if actionType == "MISSION_GOLDEN_AGE" then priority = 5 end
	elseif string.find(unitType, "ADMIRAL") ~= nil then
		if actionType == "MISSION_REPAIR_FLEET" then priority = 130 end
	elseif string.find(unitType, "PROPHET") ~= nil then
		if actionType == "MISSION_FOUND_RELIGION" then priority = 100 end
		if actionType == "MISSION_ENHANCE_RELIGION" then priority = 95 end
		if actionType == "MISSION_SPREAD_RELIGION" then priority = 80 end
	end
	if priority > -999999 then
		return priority
	end
	if string.find(unitType, "GENERAL") ~= nil or string.find(unitType, "ADMIRAL") ~= nil then
		return -999999
	end
	local genericPriority = {
		MISSION_CREATE_GREAT_WORK = 70,
		MISSION_DISCOVER = 70,
		MISSION_HURRY = 70,
		MISSION_GIVE_POLICIES = 70,
		MISSION_ONE_SHOT_TOURISM = 70,
		MISSION_TRADE = 65,
		MISSION_SELL_EXOTIC_GOODS = 65,
		MISSION_BUY_CITY_STATE = 65,
		MISSION_FOUND_RELIGION = 60,
		MISSION_ENHANCE_RELIGION = 60,
		MISSION_SPREAD_RELIGION = 45,
		MISSION_GOLDEN_AGE = 30,
		MISSION_JOIN = 20,
		MISSION_CULTURE_BOMB = 5,
		MISSION_LEAD = 5,
		MISSION_REPAIR_FLEET = 80,
	}
	return genericPriority[actionType] or -999999
end

function SC_TryGreatPersonActionFallback(unit, unitInfo, reason)
	if unit == nil or unitInfo == nil or not SC_GetConfig("GreatPersonActionFallbackWhenBlocked", true) then
		return false
	end
	if GameInfoActions == nil or Game == nil or Game.HandleAction == nil then
		return false
	end
	local unitKey = SC_GetUnitTurnKey(unit) or SC_GetUnitDebugLabel(unit)
	local modalKey = unitKey.."|"..tostring(unitInfo.Type)
	if SC_GREAT_PERSON_MODAL_PENDING[modalKey] then
		SC_Debug("greatPerson modal-pending-skip unit="..SC_GetUnitDebugLabel(unit).." type="..tostring(unitInfo.Type).." reason="..tostring(reason))
		return false
	end
	if SC_GREAT_PERSON_ACTION_ATTEMPTED_THIS_TURN[unitKey] then
		return false
	end
	SC_GREAT_PERSON_ACTION_ATTEMPTED_THIS_TURN[unitKey] = true
	local selected = pcall(function()
		UI.SelectUnit(unit)
	end)
	if not selected then
		SC_Debug("greatPerson action select-failed unit="..SC_GetUnitDebugLabel(unit).." reason="..tostring(reason))
		return false
	end
	local candidates = {}
	local minScore = SC_GetConfig("GreatPersonMinActionScore", 20)
	for iAction = 0, #GameInfoActions, 1 do
		local action = GameInfoActions[iAction]
		if action ~= nil and action.Visible and action.Type ~= nil and (ActionSubTypes == nil or action.SubType ~= ActionSubTypes.ACTIONSUBTYPE_PROMOTION) then
			local score = SC_GetGreatPersonActionPriority(unitInfo, action.Type)
			if score >= minScore then
				local canHandle = false
				pcall(function() canHandle = Game.CanHandleAction(iAction) end)
				if canHandle then
					table.insert(candidates, { index = iAction, actionType = action.Type, score = score })
				end
			end
		end
	end
	table.sort(candidates, function(a, b) return a.score > b.score end)
	if #candidates <= 0 then
		SC_Debug("greatPerson action no-legal-action unit="..SC_GetUnitDebugLabel(unit).." type="..tostring(unitInfo.Type).." reason="..tostring(reason))
		return false
	end
	local candidateNames = {}
	for i = 1, math.min(#candidates, 6), 1 do
		table.insert(candidateNames, candidates[i].actionType..":"..tostring(candidates[i].score))
	end
	SC_Debug("greatPerson candidates unit="..SC_GetUnitDebugLabel(unit).." type="..tostring(unitInfo.Type).." choices="..table.concat(candidateNames, ",").." reason="..tostring(reason))
	local ownerID, identityUnitID, unitLabel = SC_GetUnitIdentity(unit)
	local function getState()
		local liveUnit = SC_ResolveLiveUnit(ownerID, identityUnitID)
		if liveUnit == nil then
			return true, -1, false
		end
		unit = liveUnit
		local dead = false
		local moves = -1
		local needs = false
		pcall(function() dead = unit:IsDead() end)
		if not dead then
			pcall(function() moves = unit:MovesLeft() end)
			needs = SC_UnitNeedsOrder(unit)
		end
		return dead, moves, needs
	end
	for _, candidate in ipairs(candidates) do
		local beforeDead, beforeMoves, beforeNeeds = getState()
		if beforeDead then
			return true
		end
		local missionType = SC_GetMissionID(candidate.actionType)
		local missionOK = false
		local missionStatus = nil
		if missionType ~= nil then
			local missionUnit = nil
			missionOK, missionStatus, missionUnit = SC_SendUnitMission(unit, missionType)
			if missionUnit ~= nil then unit = missionUnit end
		end
		local opensModal = candidate.actionType == "MISSION_FOUND_RELIGION" or candidate.actionType == "MISSION_ENHANCE_RELIGION"
		if missionOK and opensModal then
			SC_GREAT_PERSON_MODAL_PENDING[modalKey] = candidate.actionType
			SC_Debug("greatPerson modal-pending unit="..tostring(unitLabel)..
				" type="..tostring(unitInfo.Type)..
				" action="..tostring(candidate.actionType)..
				" reason="..tostring(reason))
			return true
		end
		local dead, moves, needs = getState()
		local resolved = dead or moves < beforeMoves or (beforeNeeds and not needs)
		local actionOK = false
		local actionErr = nil
		if not resolved then
			actionOK, actionErr = pcall(function() Game.HandleAction(candidate.index) end)
			dead, moves, needs = getState()
			resolved = dead or moves < beforeMoves or (beforeNeeds and not needs)
		end
		SC_Debug("greatPerson attempt unit="..tostring(unitLabel)..
			" type="..tostring(unitInfo.Type)..
			" action="..tostring(candidate.actionType)..
			" score="..tostring(candidate.score)..
			" missionOK="..SC_BoolText(missionOK)..
			" missionStatus="..tostring(missionStatus)..
			" actionOK="..SC_BoolText(actionOK)..
			" actionErr="..tostring(actionErr)..
			" moves="..tostring(beforeMoves).."->"..tostring(moves)..
			" dead="..SC_BoolText(dead)..
			" needs="..SC_BoolText(needs)..
			" resolved="..SC_BoolText(resolved))
		if resolved then
			return true
		end
	end
	return false
end

function SC_GetGreatPersonKind(unitInfo)
	local unitType = unitInfo ~= nil and (unitInfo.Type or "") or ""
	if string.find(unitType, "GREAT_GENERAL") ~= nil or string.find(unitType, "GENERAL") ~= nil then return "general" end
	if string.find(unitType, "GREAT_ADMIRAL") ~= nil or string.find(unitType, "ADMIRAL") ~= nil then return "admiral" end
	if string.find(unitType, "ENGINEER") ~= nil then return "engineer" end
	if string.find(unitType, "MERCHANT") ~= nil then return "merchant" end
	if string.find(unitType, "SCIENTIST") ~= nil then return "scientist" end
	if string.find(unitType, "WRITER") ~= nil then return "writer" end
	if string.find(unitType, "ARTIST") ~= nil then return "artist" end
	if string.find(unitType, "MUSICIAN") ~= nil then return "musician" end
	if string.find(unitType, "PROPHET") ~= nil then return "prophet" end
	return "other"
end

function SC_GetCommanderPlotSafety(player, plot, kind)
	if player == nil or plot == nil then
		return false, 0, 0, "missing"
	end
	local enemyDistance = SC_GetNearestEnemyCombatDistance(player, plot, 12)
	local minimumDistance = SC_GetConfig("GreatPersonMinEnemyDistance", 4)
	local cover = 0
	for dx = -1, 1, 1 do
		for dy = -1, 1, 1 do
			local nearbyPlot = SC_GetNearbyPlot(plot:GetX(), plot:GetY(), dx, dy, 1)
			if nearbyPlot ~= nil and Map.PlotDistance(plot:GetX(), plot:GetY(), nearbyPlot:GetX(), nearbyPlot:GetY()) <= 1 then
				local unitCount = SC_GetSafeNumber(function() return nearbyPlot:GetNumUnits() end, 0)
				for i = 0, unitCount - 1, 1 do
					local nearbyUnit = nil
					pcall(function() nearbyUnit = nearbyPlot:GetUnit(i) end)
					if nearbyUnit ~= nil and not nearbyUnit:IsDead()
						and SC_GetSafeNumber(function() return nearbyUnit:GetOwner() end, -1) == player:GetID() then
						local nearbyInfo = SC_GetUnitInfo(nearbyUnit)
						local domainSafe = nearbyInfo ~= nil and ((kind == "admiral" and nearbyInfo.Domain == "DOMAIN_SEA")
							or (kind == "general" and nearbyInfo.Domain == "DOMAIN_LAND" and not SC_IsUnitEmbarked(nearbyUnit)))
						if domainSafe and ((nearbyInfo.Combat or 0) > 0 or (nearbyInfo.RangedCombat or 0) > 0) then
							cover = cover + 1
						end
					end
				end
			end
		end
	end
	local safe = enemyDistance >= minimumDistance and cover >= SC_GetConfig("GreatPersonMinimumCover", 1)
	return safe, enemyDistance, cover,
		"enemyDistance="..tostring(enemyDistance).." cover="..tostring(cover).." kind="..tostring(kind)
end

function SC_FindGreatPersonAdjacentPlot(player, unit, targetPlot, radius)
	if player == nil or unit == nil or targetPlot == nil then
		return nil
	end
	radius = radius or SC_GetConfig("GreatPersonSupportRadius", 2)
	local sourcePlot = unit:GetPlot()
	local unitInfo = SC_GetUnitInfo(unit)
	if sourcePlot == nil or unitInfo == nil then
		return nil
	end
	local kind = SC_GetGreatPersonKind ~= nil and SC_GetGreatPersonKind(unitInfo) or "other"
	local isCommander = kind == "general" or kind == "admiral"
	local layer = SC_GetUnitStackLayer(unit)
	local bestPlot = nil
	local bestScore = -999999
	for dx = -radius, radius, 1 do
		for dy = -radius, radius, 1 do
			local plot = SC_GetNearbyPlot(targetPlot:GetX(), targetPlot:GetY(), dx, dy, radius)
			if plot ~= nil then
				local targetDistance = Map.PlotDistance(plot:GetX(), plot:GetY(), targetPlot:GetX(), targetPlot:GetY())
				if targetDistance >= (isCommander and 0 or 1) and targetDistance <= radius then
					local usable, moveDistance = SC_MoveCandidateIsUsable(player, unit, unitInfo, sourcePlot, plot, layer, nil, nil, nil)
					local isWater = SC_GetSafeNumber(function() return plot:IsWater() and 1 or 0 end, 0) > 0
					local domainSafe = not isCommander or (kind == "general" and not isWater) or (kind == "admiral" and isWater)
					local commanderSafe = true
					local enemyDistance = SC_GetNearestEnemyCombatDistance(player, plot, 8)
					local commanderCover = 0
					if isCommander then
						commanderSafe, enemyDistance, commanderCover = SC_GetCommanderPlotSafety(player, plot, kind)
					end
					if usable and domainSafe and commanderSafe and moveDistance ~= nil and moveDistance > 0 then
						local score = 1800 - moveDistance * 18 - targetDistance * 80
						local owner = SC_GetSafeNumber(function() return plot:GetOwner() end, -1)
						if owner == player:GetID() then score = score + 180 elseif owner < 0 then score = score + 50 end
						if isCommander then
							score = score + math.min(enemyDistance, SC_GetConfig("GreatPersonPreferredEnemyDistance", 7)) * 90
							score = score + math.min(commanderCover, 2) * 420
							if targetDistance == 0 then score = score + 520 end
						elseif enemyDistance <= 1 then
							score = score - 1200
						elseif enemyDistance <= 2 then
							score = score - 500
						end
						if score > bestScore then
							bestScore = score
							bestPlot = plot
						end
					end
				end
			end
		end
	end
	return bestPlot
end

function SC_GetGreatPersonTargetKey(kind, plot)
	if plot == nil then return nil end
	return tostring(kind)..":"..SC_GetPlotDebug(plot)
end

function SC_GetGreatPersonTargetLimit(kind)
	if kind == "merchant" then return 2 end
	return 1
end

function SC_GreatPersonTargetAvailable(kind, plot)
	local key = SC_GetGreatPersonTargetKey(kind, plot)
	if key == nil then return false end
	return SC_DBNumber(SC_GREAT_PERSON_TARGET_RESERVED_THIS_TURN[key], 0) < SC_GetGreatPersonTargetLimit(kind)
end

function SC_ReserveGreatPersonTarget(kind, plot)
	local key = SC_GetGreatPersonTargetKey(kind, plot)
	if key ~= nil then
		SC_GREAT_PERSON_TARGET_RESERVED_THIS_TURN[key] = SC_DBNumber(SC_GREAT_PERSON_TARGET_RESERVED_THIS_TURN[key], 0) + 1
	end
end

function SC_FindGreatPersonSupportTarget(player, unit, kind, atWar)
	if player == nil or unit == nil then
		return nil, nil, "missing"
	end
	local sourcePlot = unit:GetPlot()
	if sourcePlot == nil then
		return nil, nil, "no-source"
	end
	local wantedDomain = kind == "admiral" and "DOMAIN_SEA" or "DOMAIN_LAND"
	local bestAnchor = nil
	local bestScore = -999999
	for combatUnit in player:Units() do
		if combatUnit ~= nil and combatUnit ~= unit and not combatUnit:IsDead() and combatUnit:IsCombatUnit() then
			local combatInfo = SC_GetUnitInfo(combatUnit)
			local combatPlot = combatUnit:GetPlot()
			if combatInfo ~= nil and combatPlot ~= nil and combatInfo.Domain == wantedDomain
				and not SC_IsUnitEmbarked(combatUnit)
				and combatUnit:GetDamage() < 35
				and SC_GreatPersonTargetAvailable(kind, combatPlot) then
				local distance = Map.PlotDistance(sourcePlot:GetX(), sourcePlot:GetY(), combatPlot:GetX(), combatPlot:GetY())
				local profile = SC_GetUnitCapabilityProfile(combatUnit, combatInfo)
				local enemyDistance = atWar and SC_GetNearestEnemyCombatDistance(player, combatPlot, 12) or 12
				local frontScore = 0
				if atWar then
					if enemyDistance < SC_GetConfig("GreatPersonMinEnemyDistance", 4) then
						frontScore = -5000
					elseif enemyDistance <= SC_GetConfig("GreatPersonPreferredEnemyDistance", 7) then
						frontScore = 520 - math.abs(enemyDistance - 6) * 90
					else
						frontScore = math.max(0, 260 - (enemyDistance - 7) * 40)
					end
				end
				local score = (profile.power or 0) * 2 + frontScore - distance * 18
				if SC_GetUnitProtectionTier(combatUnit, combatInfo, nil, profile) >= 2 then score = score + 240 end
				if score > bestScore then
					bestScore = score
					bestAnchor = combatUnit
				end
			end
		end
	end
	if bestAnchor == nil then
		local rearPlot = SC_FindRetreatPlot(player, unit)
		local rearSafe = rearPlot ~= nil and (not atWar or SC_GetCommanderPlotSafety(player, rearPlot, kind))
		return rearPlot, rearSafe and rearPlot or nil,
			rearSafe and "rear-area:no-safe-formation" or "no-safe-formation"
	end
	local anchorPlot = bestAnchor:GetPlot()
	local distance = Map.PlotDistance(sourcePlot:GetX(), sourcePlot:GetY(), anchorPlot:GetX(), anchorPlot:GetY())
	if distance <= SC_GetConfig("GreatPersonSupportRadius", 2) then
		local sourceSafe = not atWar or SC_GetCommanderPlotSafety(player, sourcePlot, kind)
		if sourceSafe then
			return anchorPlot, nil, "support-hold:"..SC_GetUnitDebugLabel(bestAnchor)
		end
	end
	local movePlot = SC_FindGreatPersonAdjacentPlot(player, unit, anchorPlot, SC_GetConfig("GreatPersonSupportRadius", 2))
	if movePlot == nil then
		local rearPlot = SC_FindRetreatPlot(player, unit)
		local rearSafe = rearPlot ~= nil and (not atWar or SC_GetCommanderPlotSafety(player, rearPlot, kind))
		return rearPlot, rearSafe and rearPlot or nil, rearSafe and "rear-area:unsafe-approach" or "no-safe-commander-plot"
	end
	return anchorPlot, movePlot, "support:"..SC_GetUnitDebugLabel(bestAnchor)
end

function SC_FindGreatEngineerTarget(player, unit)
	if player == nil or unit == nil then return nil, nil, "missing" end
	local sourcePlot = unit:GetPlot()
	local bestCity = nil
	local bestScore = -999999
	for city in player:Cities() do
		local buildingID = SC_GetSafeNumber(function() return city:GetProductionBuilding() end, -1)
		local building = buildingID ~= nil and buildingID >= 0 and GameInfo.Buildings[buildingID] or nil
		local buildingClass = building ~= nil and GameInfo.BuildingClasses[building.BuildingClass] or nil
		local isWonder = buildingClass ~= nil and ((buildingClass.MaxGlobalInstances or -1) > 0 or (buildingClass.MaxTeamInstances or -1) > 0)
		if isWonder and SC_GreatPersonTargetAvailable("engineer", city:Plot()) then
			local cityPlot = city:Plot()
			local distance = sourcePlot ~= nil and Map.PlotDistance(sourcePlot:GetX(), sourcePlot:GetY(), cityPlot:GetX(), cityPlot:GetY()) or 99
			local turnsLeft = SC_GetSafeNumber(function() return city:GetProductionTurnsLeft() end, 99)
			local score = 3000 - distance * 30 - turnsLeft * 8
			if score > bestScore then bestScore = score bestCity = city end
		end
	end
	if bestCity == nil then return nil, nil, "no-wonder" end
	local cityPlot = bestCity:Plot()
	local movePlot = nil
	local sourcePlot = unit:GetPlot()
	local unitInfo = SC_GetUnitInfo(unit)
	if sourcePlot ~= nil and unitInfo ~= nil then
		local usable = SC_MoveCandidateIsUsable(player, unit, unitInfo, sourcePlot, cityPlot, SC_GetUnitStackLayer(unit), nil, nil, nil)
		if usable then movePlot = cityPlot end
	end
	if movePlot == nil then movePlot = SC_FindGreatPersonAdjacentPlot(player, unit, cityPlot, 1) end
	return cityPlot, movePlot, "wonder:"..tostring(bestCity:GetName())
end

function SC_FindGreatMerchantTarget(player, unit)
	if player == nil or unit == nil then return nil, nil, "missing" end
	local sourcePlot = unit:GetPlot()
	local team = Teams[player:GetTeam()]
	local bestCityPlot = nil
	local bestDistance = 999999
	for _, minor in pairs(Players) do
		if minor ~= nil and minor:IsAlive() and minor:IsMinorCiv() and (team == nil or not team:IsAtWar(minor:GetTeam())) then
			local city = minor:GetCapitalCity()
			local cityPlot = city ~= nil and city:Plot() or nil
			if sourcePlot ~= nil and cityPlot ~= nil and SC_GreatPersonTargetAvailable("merchant", cityPlot) then
				local distance = Map.PlotDistance(sourcePlot:GetX(), sourcePlot:GetY(), cityPlot:GetX(), cityPlot:GetY())
				if distance < bestDistance then bestDistance = distance bestCityPlot = cityPlot end
			end
		end
	end
	if bestCityPlot == nil then return nil, nil, "no-city-state" end
	local movePlot = SC_FindGreatPersonAdjacentPlot(player, unit, bestCityPlot, 2)
	return bestCityPlot, movePlot, "city-state"
end

function SC_AutomateGreatPeople(player, atWar)
	if player == nil or not SC_GetConfig("AutoUseGreatPeople", true) or SC_GetConfig("GreatPersonProfile", "AUTO") == "SLEEP" then
		return 0
	end
	local handled = 0
	local maxActions = SC_GetConfig("GreatPersonMaxActionsPerTurn", 30)
	for unit in player:Units() do
		if handled >= maxActions then break end
		local unitInfo = SC_GetUnitInfo(unit)
		if unit ~= nil and not unit:IsDead() and unit:CanMove() and SC_IsGreatPersonLike(unitInfo) then
			local unitKey = SC_GetUnitTurnKey(unit) or SC_GetUnitDebugLabel(unit)
			local _, _, unitLabel = SC_GetUnitIdentity(unit)
			if SC_TryGreatPersonActionFallback(unit, unitInfo, "greatPerson-module") then
				handled = handled + 1
			elseif not SC_GREAT_PERSON_POSITIONED_THIS_TURN[unitKey] then
				local kind = SC_GetGreatPersonKind(unitInfo)
				local targetPlot = nil
				local movePlot = nil
				local positionReason = "no-position-role"
				if kind == "general" or kind == "admiral" then
					targetPlot, movePlot, positionReason = SC_FindGreatPersonSupportTarget(player, unit, kind, atWar)
				elseif kind == "engineer" then
					targetPlot, movePlot, positionReason = SC_FindGreatEngineerTarget(player, unit)
				elseif kind == "merchant" then
					targetPlot, movePlot, positionReason = SC_FindGreatMerchantTarget(player, unit)
				end
				if targetPlot ~= nil then SC_ReserveGreatPersonTarget(kind, targetPlot) end
				local positioned = false
				local unitRemoved = false
				if movePlot == nil and targetPlot ~= nil and kind ~= "general" and kind ~= "admiral"
					and string.sub(positionReason, 1, 12) ~= "support-hold" then
					movePlot = SC_FindSafeAdvanceWaypoint(player, unit, targetPlot, nil, {})
					if movePlot ~= nil then positionReason = positionReason..":approach" end
				end
				if movePlot ~= nil then
					local sourcePlot = unit:GetPlot()
					if sourcePlot ~= nil and Map.PlotDistance(sourcePlot:GetX(), sourcePlot:GetY(), movePlot:GetX(), movePlot:GetY()) > SC_GetConfig("StrategicWaypointTriggerDistance", 5) then
						local waypoint = SC_FindSafeAdvanceWaypoint(player, unit, movePlot, nil, {})
						if waypoint ~= nil then movePlot = waypoint positionReason = positionReason..":waypoint" end
					end
					if (kind == "general" or kind == "admiral") and atWar then
						local commanderSafe, enemyDistance, cover, safetyReason = SC_GetCommanderPlotSafety(player, movePlot, kind)
						if not commanderSafe then
							local unsafePlot = movePlot
							local retreatPlot = SC_FindRetreatPlot(player, unit)
							local retreatSafe = retreatPlot ~= nil and SC_GetCommanderPlotSafety(player, retreatPlot, kind)
							SC_Debug("greatPerson commander-unsafe unit="..SC_GetUnitDebugLabel(unit)..
								" moveTo="..SC_GetPlotDebug(movePlot).." enemyDistance="..tostring(enemyDistance)..
								" cover="..tostring(cover).." reason="..tostring(safetyReason)..
								" retreat="..SC_GetPlotDebug(retreatPlot).." retreatSafe="..SC_BoolText(retreatSafe))
							if retreatSafe then
								movePlot = retreatPlot
								positionReason = "rear-area:unsafe-waypoint:"..SC_GetPlotDebug(unsafePlot)
							else
								movePlot = nil
								positionReason = "unsafe-commander-waypoint"
							end
						end
					end
					if movePlot ~= nil then
						local moveStatus, liveUnit = nil, nil
						positioned, moveStatus, liveUnit = SC_TryMoveMission(unit, movePlot, "greatPerson-"..kind, false)
						unitRemoved = moveStatus == "unit-removed"
						if liveUnit ~= nil then unit = liveUnit end
						if unitRemoved then positioned = true end
					end
				elseif targetPlot ~= nil and string.sub(positionReason, 1, 12) == "support-hold" then
					positioned = SC_TryUnitActionByType(unit, {MISSION_ALERT = true, MISSION_SKIP = true})
				end
				SC_GREAT_PERSON_POSITIONED_THIS_TURN[unitKey] = true
				SC_Debug("greatPerson position unit="..tostring(unitLabel).." kind="..tostring(kind).." target="..SC_GetPlotDebug(targetPlot).." moveTo="..SC_GetPlotDebug(movePlot).." reason="..tostring(positionReason).." positioned="..SC_BoolText(positioned).." removed="..SC_BoolText(unitRemoved))
				if positioned then
					if kind == "engineer" or kind == "merchant" then
						SC_GREAT_PERSON_ACTION_ATTEMPTED_THIS_TURN[unitKey] = nil
					end
					handled = handled + 1
				end
			end
		end
	end
	return handled
end

local function SC_IsWorkerLike(unitInfo)
	if unitInfo == nil then
		return false
	end
	return unitInfo.WorkRate ~= nil and unitInfo.WorkRate > 0
end

local function SC_IsExploreLike(unitInfo)
	if unitInfo == nil then
		return false
	end
	local ai = unitInfo.DefaultUnitAI
	return ai == "UNITAI_EXPLORE" or ai == "UNITAI_EXPLORE_SEA"
end

SC_IsTradeLike = function(unitInfo)
	if unitInfo == nil then
		return false
	end
	local ai = unitInfo.DefaultUnitAI or ""
	local unitType = unitInfo.Type or ""
	return ai == "UNITAI_TRADE_UNIT" or string.find(unitType, "CARAVAN") ~= nil or string.find(unitType, "CARGO_SHIP") ~= nil or string.find(unitType, "TRADE") ~= nil
end

SC_IsGreatPersonLike = function(unitInfo)
	if unitInfo == nil then
		return false
	end
	if unitInfo.Special == "SPECIALUNIT_PEOPLE" then
		return true
	end
	local unitType = unitInfo.Type or ""
	return string.find(unitType, "GREAT") ~= nil or string.find(unitType, "SCIENTIST") ~= nil or string.find(unitType, "ENGINEER") ~= nil or string.find(unitType, "MERCHANT") ~= nil or string.find(unitType, "ARTIST") ~= nil or string.find(unitType, "WRITER") ~= nil or string.find(unitType, "MUSICIAN") ~= nil or string.find(unitType, "PROPHET") ~= nil
end

local function SC_GetRouteYield(route, yieldType)
	if route == nil or route.Yields == nil or yieldType == nil then
		return 0, 0
	end
	local entry = route.Yields[yieldType + 1]
	if entry == nil then
		return 0, 0
	end
	return entry.Mine or 0, entry.Theirs or 0
end

local function SC_GetTradeRouteScore(player, route)
	if route == nil then
		return -999999
	end
	local profile = SC_GetConfig("TradeProfile", "BALANCED")
	local gold = 0
	local science = 0
	local food = 0
	local production = 0
	if YieldTypes ~= nil then
		gold = select(1, SC_GetRouteYield(route, YieldTypes.YIELD_GOLD))
		science = select(1, SC_GetRouteYield(route, YieldTypes.YIELD_SCIENCE))
		food = select(1, SC_GetRouteYield(route, YieldTypes.YIELD_FOOD))
		production = select(1, SC_GetRouteYield(route, YieldTypes.YIELD_PRODUCTION))
	end
	local score = gold + science + food + production
	local owner = -1
	pcall(function()
		local plot = Map.GetPlot(route.X, route.Y)
		if plot ~= nil and plot:GetPlotCity() ~= nil then
			owner = plot:GetPlotCity():GetOwner()
		end
	end)
	if profile == "GOLD" then
		score = gold * 4 + science + food + production
	elseif profile == "SCIENCE" then
		score = science * 5 + gold + food + production
	elseif profile == "INTERNAL" then
		if player ~= nil and owner == player:GetID() then
			score = score + 5000 + food * 3 + production * 3
		else
			score = score - 5000
		end
	else
		if player ~= nil and owner == player:GetID() then
			score = score + food + production
		else
			score = score + gold + science
		end
	end
	if SC_StrategyScoreTradeRoute ~= nil then
		score = SC_StrategyScoreTradeRoute(player, route, score)
	end
	return score
end

local function SC_AutomateTradeRoutes(player)
	if player == nil or not SC_GetConfig("AutoTradeRoutes", true) then
		return 0
	end
	local handled = 0
	for unit in player:Units() do
		if unit ~= nil and not unit:IsDead() and unit:CanMove() then
			local unitInfo = GameInfo.Units[unit:GetUnitType()]
			if SC_IsTradeLike(unitInfo) then
				local bestRoute = nil
				local bestScore = -999999
				local routes = nil
				pcall(function() routes = player:GetPotentialInternationalTradeRouteDestinations(unit) end)
				if routes ~= nil then
					for _, route in ipairs(routes) do
						local score = SC_GetTradeRouteScore(player, route)
						if score > bestScore then
							bestScore = score
							bestRoute = route
						end
					end
				end
				if bestRoute ~= nil then
					SC_Debug("tradeDecision unit="..SC_GetUnitDebugLabel(unit).." destination="..tostring(bestRoute.X)..","..tostring(bestRoute.Y).." score="..tostring(bestScore))
					local ok = pcall(function()
						UI.SelectUnit(unit)
						local plot = Map.GetPlot(bestRoute.X, bestRoute.Y)
						if plot ~= nil then
							Game.SelectionListGameNetMessage(GameMessageTypes.GAMEMESSAGE_PUSH_MISSION, MissionTypes.MISSION_ESTABLISH_TRADE_ROUTE, plot:GetPlotIndex(), bestRoute.TradeConnectionType, 0, false, nil)
						end
					end)
					if ok then
						handled = handled + 1
					end
				end
			end
		end
	end
	return handled
end

function SC_IsUnitEmbarked(unit)
	if unit == nil then
		return false
	end
	local ok, embarked = pcall(function() return unit:IsEmbarked() end)
	return ok and embarked
end

function SC_IsFragileTransportUnit(unit, unitInfo)
	unitInfo = unitInfo or SC_GetUnitInfo(unit)
	if unit == nil or unitInfo == nil then
		return false
	end
	if SC_IsUnitEmbarked(unit) then
		return true
	end
	return unitInfo.Domain == "DOMAIN_SEA" and SC_IsTradeLike(unitInfo)
end

function SC_GetTransportMissionClass(unit, unitInfo)
	unitInfo = unitInfo or SC_GetUnitInfo(unit)
	if unit == nil or unitInfo == nil then
		return "none"
	end
	if SC_IsTradeLike(unitInfo) then
		return "trade"
	end
	if not SC_IsUnitEmbarked(unit) then
		return "none"
	end
	local combat = false
	pcall(function() combat = unit:IsCombatUnit() end)
	if combat or SC_GetUnitPowerScore(unitInfo) > 0 then
		return "combat"
	end
	if SC_IsWorkerLike(unitInfo) then
		return "worker"
	end
	if unitInfo.DefaultUnitAI == "UNITAI_SETTLE" then
		return "settler"
	end
	return "civilian"
end

function SC_IsNavalEscortUnit(unit, unitInfo, role)
	unitInfo = unitInfo or SC_GetUnitInfo(unit)
	if unit == nil or unitInfo == nil or unitInfo.Domain ~= "DOMAIN_SEA" then
		return false
	end
	if SC_IsTradeLike(unitInfo) or SC_IsFragileTransportUnit(unit, unitInfo) then
		return false
	end
	role = role or SC_GetUnitRole(unit, unitInfo)
	local profile = SC_GetUnitCapabilityProfile(unit, unitInfo, role)
	if SC_IsProtectedDoctrineClass(profile.doctrineClass) then
		return false
	end
	return SC_IsScreenDoctrineClass(profile.doctrineClass)
		or profile.doctrineClass == "naval_assault"
		or profile.doctrineClass == "surface_fire_support"
end

function SC_CountFriendlyNavalEscortsNearPlot(player, targetPlot, radius)
	if player == nil or targetPlot == nil then
		return 0
	end
	radius = radius or SC_GetConfig("TransportEscortRadius", 2)
	local playerID = player:GetID()
	local count = 0
	for dx = -radius, radius, 1 do
		for dy = -radius, radius, 1 do
			local plot = SC_GetNearbyPlot(targetPlot:GetX(), targetPlot:GetY(), dx, dy, radius)
			if plot ~= nil and Map.PlotDistance(targetPlot:GetX(), targetPlot:GetY(), plot:GetX(), plot:GetY()) <= radius then
				local unitCount = SC_GetSafeNumber(function() return plot:GetNumUnits() end, 0)
				for i = 0, unitCount - 1, 1 do
					local otherUnit = nil
					pcall(function() otherUnit = plot:GetUnit(i) end)
					if otherUnit ~= nil and SC_GetSafeNumber(function() return otherUnit:GetOwner() end, -1) == playerID then
						local otherInfo = SC_GetUnitInfo(otherUnit)
						if SC_IsNavalEscortUnit(otherUnit, otherInfo, SC_GetUnitRole(otherUnit, otherInfo)) then
							count = count + 1
						end
					end
				end
			end
		end
	end
	return count
end

function SC_CountEnemySeaThreatsNearPlot(player, targetPlot, radius)
	if player == nil or targetPlot == nil then
		return 0
	end
	radius = radius or SC_GetConfig("TransportThreatRadius", 6)
	local plotIndex = nil
	pcall(function() plotIndex = targetPlot:GetPlotIndex() end)
	local cacheKey = plotIndex ~= nil and tostring(player:GetID()).."|"..tostring(plotIndex).."|"..tostring(radius) or nil
	if cacheKey ~= nil and SC_SEA_THREAT_CACHE_THIS_TURN[cacheKey] ~= nil then
		return SC_SEA_THREAT_CACHE_THIS_TURN[cacheKey]
	end
	local team = Teams[player:GetTeam()]
	if team == nil then
		return 0
	end
	local count = 0
	for otherID, otherPlayer in pairs(Players) do
		if otherPlayer ~= nil and otherPlayer:IsAlive() and otherPlayer:GetID() ~= player:GetID() and team:IsAtWar(otherPlayer:GetTeam()) then
			for enemyUnit in otherPlayer:Units() do
				local enemyPlot = enemyUnit ~= nil and enemyUnit:GetPlot() or nil
				if enemyPlot ~= nil then
					local distance = Map.PlotDistance(targetPlot:GetX(), targetPlot:GetY(), enemyPlot:GetX(), enemyPlot:GetY())
					if distance <= radius then
						local enemyInfo = SC_GetUnitInfo(enemyUnit)
						local enemyRole = SC_GetUnitRole(enemyUnit, enemyInfo)
						if (enemyInfo ~= nil and enemyInfo.Domain == "DOMAIN_SEA") or SC_IsUnitEmbarked(enemyUnit) or enemyRole == "carrier_air" or enemyRole == "bomber" then
							count = count + 1
						end
					end
				end
			end
		end
	end
	if cacheKey ~= nil then
		SC_SEA_THREAT_CACHE_THIS_TURN[cacheKey] = count
	end
	return count
end

function SC_FindTransportOperationTarget(player, transport, missionClass)
	if player == nil or transport == nil then
		return nil, "missing"
	end
	local team = Teams[player:GetTeam()]
	local transportPlot = transport:GetPlot()
	if team == nil or transportPlot == nil then
		return nil, "no-team-or-plot"
	end
	local bestPlot = nil
	local bestScore = -999999
	local bestReason = "none"
	missionClass = missionClass or SC_GetTransportMissionClass(transport, SC_GetUnitInfo(transport))
	if missionClass == "combat" then
		local task = SC_StrategyGetUnitTask ~= nil and SC_StrategyGetUnitTask(transport) or nil
		if task ~= nil and task.targetPlot ~= nil then
			return task.targetPlot, "task:"..tostring(task.kind)..":"..tostring(task.operationID or "-")
		end
		if SC_StrategyGetPrimaryOffensiveTarget ~= nil then
			local primaryPlot, _, primaryReason = SC_StrategyGetPrimaryOffensiveTarget()
			if primaryPlot ~= nil then return primaryPlot, "primary:"..tostring(primaryReason) end
		end
	end
	if missionClass ~= "combat" then
		if not SC_GetConfig("TransportCivilianRetreatUnderThreat", true) then
			return nil, "civilian-retreat-disabled"
		end
		for city in player:Cities() do
			local cityPlot = city:Plot()
			local coastal = false
			pcall(function() coastal = city:IsCoastal() end)
			if cityPlot ~= nil and coastal then
				local distance = Map.PlotDistance(transportPlot:GetX(), transportPlot:GetY(), cityPlot:GetX(), cityPlot:GetY())
				local score = 2000 - distance * 40
				if score > bestScore then
					bestScore = score
					bestPlot = cityPlot
					bestReason = "friendly-coast"
				end
			end
		end
		return bestPlot, bestReason
	end
	for otherID, otherPlayer in pairs(Players) do
		if otherPlayer ~= nil and otherPlayer:IsAlive() and otherPlayer:GetID() ~= player:GetID() and team:IsAtWar(otherPlayer:GetTeam()) then
			for city in otherPlayer:Cities() do
				local cityPlot = city:Plot()
				if cityPlot ~= nil and SC_IsWaterOrCoastalStrategicPlot(cityPlot) then
					local distance = Map.PlotDistance(transportPlot:GetX(), transportPlot:GetY(), cityPlot:GetX(), cityPlot:GetY())
					local damage = SC_GetSafeNumber(function() return city:GetDamage() end, 0)
					local score = 2800 - distance * 18 + damage * 2
					if SC_GetSafeNumber(function() return city:IsCapital() and 1 or 0 end, 0) > 0 then
						score = score + 180
					end
					if score > bestScore then
						bestScore = score
						bestPlot = cityPlot
						bestReason = "coastal-city"
					end
				end
			end
			for enemyUnit in otherPlayer:Units() do
				local enemyPlot = enemyUnit ~= nil and enemyUnit:GetPlot() or nil
				local enemyInfo = SC_GetUnitInfo(enemyUnit)
				if enemyPlot ~= nil and enemyInfo ~= nil and (enemyInfo.Domain == "DOMAIN_SEA" or SC_IsUnitEmbarked(enemyUnit)) then
					local distance = Map.PlotDistance(transportPlot:GetX(), transportPlot:GetY(), enemyPlot:GetX(), enemyPlot:GetY())
					local score = 1600 - distance * 20
					if score > bestScore then
						bestScore = score
						bestPlot = enemyPlot
						bestReason = "sea-front"
					end
				end
			end
		end
	end
	return bestPlot, bestReason
end

function SC_PlotHasAdjacentWater(plot)
	if plot == nil then return false end
	for dx = -1, 1, 1 do
		for dy = -1, 1, 1 do
			local nearby = SC_GetNearbyPlot(plot:GetX(), plot:GetY(), dx, dy, 1)
			if nearby ~= nil and nearby ~= plot
				and SC_GetSafeNumber(function() return nearby:IsWater() and 1 or 0 end, 0) > 0 then
				return true
			end
		end
	end
	return false
end

function SC_FindEmbarkedLandingPlot(player, transport, targetPlot, reserved)
	if player == nil or transport == nil or targetPlot == nil or not SC_IsUnitEmbarked(transport) then
		return nil, "not-embarked"
	end
	local sourcePlot = transport:GetPlot()
	local unitInfo = SC_GetUnitInfo(transport)
	if sourcePlot == nil or unitInfo == nil then return nil, "missing" end
	local radius = SC_GetConfig("AmphibiousLandingSearchRadius", 5)
	local layer = SC_GetUnitStackLayer(transport)
	local bestPlot, bestScore = nil, -999999
	local candidates, unsafe, blocked = 0, 0, 0
	for dx = -radius, radius, 1 do
		for dy = -radius, radius, 1 do
			local plot = SC_GetNearbyPlot(targetPlot:GetX(), targetPlot:GetY(), dx, dy, radius)
			local targetDistance = plot ~= nil and Map.PlotDistance(targetPlot:GetX(), targetPlot:GetY(), plot:GetX(), plot:GetY()) or 999
			if plot ~= nil and targetDistance <= radius
				and SC_GetSafeNumber(function() return plot:IsWater() and 1 or 0 end, 0) <= 0
				and SC_PlotHasAdjacentWater(plot) then
				local city = SC_GetSafeNumber(function() return plot:IsCity() and 1 or 0 end, 0) > 0
				local owner = SC_GetSafeNumber(function() return plot:GetOwner() end, -1)
				if city and owner ~= player:GetID() then
					blocked = blocked + 1
				else
					local usable = SC_MoveCandidateIsUsable(player, transport, unitInfo, sourcePlot, plot, layer, reserved, nil, {})
					if usable then
						candidates = candidates + 1
						local sourceDistance = Map.PlotDistance(sourcePlot:GetX(), sourcePlot:GetY(), plot:GetX(), plot:GetY())
						local enemyPressure = SC_CountEnemyCombatPresenceNearPlot(player, plot, 2, 6)
						local cover = SC_CountFriendlyRoleNearPlot(player, plot, 2, "capture", 4)
						local score = 4200 - targetDistance * 260 - sourceDistance * 12 + math.min(cover, 3) * 180
						if owner == player:GetID() then score = score + 260 elseif owner < 0 then score = score + 120 end
						if enemyPressure >= 4 then score = score - 3200; unsafe = unsafe + 1
						elseif enemyPressure >= 2 then score = score - 1100
						elseif enemyPressure == 1 then score = score - 320 end
						if score > bestScore then bestPlot, bestScore = plot, score end
					else
						blocked = blocked + 1
					end
				end
			end
		end
	end
	return bestPlot, "candidates="..tostring(candidates)..",unsafe="..tostring(unsafe)..",blocked="..tostring(blocked)..",score="..tostring(math.floor(bestScore))
end

function SC_FindLocalEmbarkedLandingPlot(player, transport, targetPlot, reserved)
	if player == nil or transport == nil or not SC_IsUnitEmbarked(transport) then
		return nil, "not-embarked"
	end
	local sourcePlot = transport:GetPlot()
	local unitInfo = SC_GetUnitInfo(transport)
	if sourcePlot == nil or unitInfo == nil then return nil, "missing" end
	local radius = math.max(1, SC_GetConfig("EmbarkedLocalLandingSearchRadius", 4))
	local layer = SC_GetUnitStackLayer(transport)
	local bestPlot, bestScore = nil, -999999
	local candidates, unsafe = 0, 0
	local currentTargetDistance = targetPlot ~= nil
		and Map.PlotDistance(sourcePlot:GetX(), sourcePlot:GetY(), targetPlot:GetX(), targetPlot:GetY()) or 0
	for dx = -radius, radius, 1 do
		for dy = -radius, radius, 1 do
			local plot = SC_GetNearbyPlot(sourcePlot:GetX(), sourcePlot:GetY(), dx, dy, radius)
			local sourceDistance = plot ~= nil
				and Map.PlotDistance(sourcePlot:GetX(), sourcePlot:GetY(), plot:GetX(), plot:GetY()) or 999
			if plot ~= nil and sourceDistance >= 1 and sourceDistance <= radius
				and SC_GetSafeNumber(function() return plot:IsWater() and 1 or 0 end, 0) <= 0
				and SC_PlotHasAdjacentWater(plot) then
				local owner = SC_GetSafeNumber(function() return plot:GetOwner() end, -1)
				local city = SC_GetSafeNumber(function() return plot:IsCity() and 1 or 0 end, 0) > 0
				if not city or owner == player:GetID() then
					local usable = SC_MoveCandidateIsUsable(player, transport, unitInfo, sourcePlot, plot, layer, reserved, nil, {})
					if usable then
						candidates = candidates + 1
						local pressure = SC_CountEnemyCombatPresenceNearPlot(player, plot, 2, 6)
						local targetDistance = targetPlot ~= nil
							and Map.PlotDistance(plot:GetX(), plot:GetY(), targetPlot:GetX(), targetPlot:GetY()) or 0
						local improvement = currentTargetDistance - targetDistance
						local score = 3600 - sourceDistance * 260 + improvement * 35 - pressure * 1100
						if owner == player:GetID() then score = score + 420 elseif owner < 0 then score = score + 180 end
						if pressure > 0 then unsafe = unsafe + 1 end
						if score > bestScore then bestPlot, bestScore = plot, score end
					end
				end
			end
		end
	end
	return bestPlot, "candidates="..tostring(candidates)..",unsafe="..tostring(unsafe)..",score="..tostring(math.floor(bestScore))
end

function SC_TryAdvanceEscortedTransport(player, transport, reserved)
	if player == nil or transport == nil or not transport:CanMove() then
		return 0, "cannot-move"
	end
	local transportPlot = transport:GetPlot()
	local transportInfo = SC_GetUnitInfo(transport)
	if transportPlot == nil or transportInfo == nil then
		return 0, "missing-plot"
	end
	local missionClass = SC_GetTransportMissionClass(transport, transportInfo)
	local targetPlot, targetReason = SC_FindTransportOperationTarget(player, transport, missionClass)
	if targetPlot == nil then
		return 0, "defer-no-target class="..tostring(missionClass)
	end
	local navigationTarget = targetPlot
	local landingPlot, landingReason = SC_FindEmbarkedLandingPlot(player, transport, targetPlot, reserved)
	local sourceThreats = SC_CountEnemySeaThreatsNearPlot(player, transportPlot, SC_GetConfig("TransportThreatRadius", 6))
	local profile = SC_GetUnitCapabilityProfile(transport, transportInfo)
	local protectedTransport = SC_GetUnitProtectionTier(transport, transportInfo, nil, profile) >= 2
	local localLanding, localLandingReason = SC_FindLocalEmbarkedLandingPlot(player, transport, targetPlot, reserved)
	local localLandingSelected = localLanding ~= nil and (sourceThreats > 0 or protectedTransport)
	if localLandingSelected then
		landingPlot = localLanding
		landingReason = "local-safe:"..tostring(localLandingReason)
		navigationTarget = localLanding
		targetReason = tostring(targetReason)..",local-landing"
	elseif landingPlot ~= nil then
		navigationTarget = landingPlot
		targetReason = tostring(targetReason)..",landing:"..tostring(landingReason)
	end
	if localLandingSelected then
		local localDistance = Map.PlotDistance(transportPlot:GetX(), transportPlot:GetY(), localLanding:GetX(), localLanding:GetY())
		if localDistance <= 1 then
			local landed, landStatus, liveTransport = SC_TryMoveMission(transport, localLanding, "convoy-emergency-land", true)
			if landed then
				transport = liveTransport or transport
				local transportKey = SC_GetUnitTurnKey(transport)
				if transportKey ~= nil then
					SC_TRANSPORT_ESCORT_ORDERED_THIS_TURN[transportKey] = true
					SC_MarkStrategicUnitDone(transport)
				end
				SC_ReserveMovePlot(reserved, localLanding, SC_GetUnitStackLayer(transport))
				return 1, (not SC_IsUnitEmbarked(transport) and "emergency-landed" or "emergency-advance")..
					" target="..tostring(targetReason).." status="..tostring(landStatus)
			elseif landStatus == "unit-removed" then
				return 0, "transport-destroyed-emergency-land"
			end
		end
	end
	local waypointStats = {}
	local waypoint = SC_FindSafeAdvanceWaypoint(player, transport, navigationTarget, reserved, waypointStats, SC_GetConfig("TransportConvoyWaypointRadius", 3))
	if waypoint == nil then
		local targetDistance = Map.PlotDistance(transportPlot:GetX(), transportPlot:GetY(), navigationTarget:GetX(), navigationTarget:GetY())
		local finalMoved, finalStatus, liveTransport = false, nil, nil
		if targetDistance <= 3 then
			finalMoved, finalStatus, liveTransport = SC_TryMoveMission(transport, navigationTarget, landingPlot ~= nil and "convoy-land" or "convoy-final", true)
		end
		if finalStatus == "unit-removed" then
			return 0, "transport-destroyed-final"
		end
		if finalMoved then
			transport = liveTransport or transport
			local transportKey = SC_GetUnitTurnKey(transport)
			if transportKey ~= nil then
				SC_TRANSPORT_ESCORT_ORDERED_THIS_TURN[transportKey] = true
				SC_MarkStrategicUnitDone(transport)
			end
			local landed = landingPlot ~= nil and not SC_IsUnitEmbarked(transport)
			return 1, (landed and "landed" or "advance-final").." target="..tostring(targetReason).." class="..tostring(missionClass)
		end
		return 0, "defer-no-waypoint class="..tostring(missionClass).." "..SC_GetMoveRejectStatsDebug(waypointStats)
	end
	local threats = SC_CountEnemySeaThreatsNearPlot(player, waypoint, SC_GetConfig("TransportThreatRadius", 6))
	threats = math.max(threats, sourceThreats)
	local requiredEscorts = 0
	if threats > 0 then
		requiredEscorts = SC_GetConfig("TransportMinimumEscorts", 1)
	end
	if threats >= SC_GetConfig("TransportSevereThreatCount", 2) then
		requiredEscorts = SC_GetConfig("TransportEscortsUnderThreat", 2)
	end
	if localLandingSelected then requiredEscorts = 0 end
	local coverage = math.max(
		SC_CountFriendlyNavalEscortsNearPlot(player, transportPlot, SC_GetConfig("TransportEscortRadius", 2)),
		SC_CountFriendlyNavalEscortsNearPlot(player, waypoint, SC_GetConfig("TransportEscortRadius", 2)))
	local actions = 0
	if SC_IsUnitEmbarked(transport) and threats > 0 and SC_GetConfig("TransportNeverAdvanceUnderThreat", false)
		and coverage < requiredEscorts then
		local held = SC_TryHoldTransport(transport, "convoy-threat-lock")
		local transportKey = SC_GetUnitTurnKey(transport)
		if transportKey ~= nil then
			SC_TRANSPORT_ESCORT_ORDERED_THIS_TURN[transportKey] = true
			SC_MarkStrategicUnitDone(transport)
		end
		return held and 1 or 0, "hold-under-threat threats="..tostring(threats).." coverage="..tostring(coverage)
	end
	local assemblyRadius = SC_GetConfig("TransportConvoyAssemblyRadius", 4)
	while coverage < requiredEscorts do
		local bestEscort = nil
		local bestMovePlot = nil
		local bestScore = -999999
		for escort in player:Units() do
			if escort ~= nil and not escort:IsDead() and escort:CanMove() then
				local escortInfo = SC_GetUnitInfo(escort)
				local escortRole = SC_GetUnitRole(escort, escortInfo)
				local escortKey = SC_GetUnitTurnKey(escort)
				local escortPlot = escort:GetPlot()
				if escortPlot ~= nil and SC_IsNavalEscortUnit(escort, escortInfo, escortRole)
					and (escortKey == nil or not SC_TRANSPORT_ESCORT_ORDERED_THIS_TURN[escortKey]) then
					local assemblyDistance = Map.PlotDistance(escortPlot:GetX(), escortPlot:GetY(), transportPlot:GetX(), transportPlot:GetY())
					if assemblyDistance <= assemblyRadius then
						local movePlot = SC_FindTransportEscortMovePlot(player, escort, waypoint, reserved, {})
						if movePlot ~= nil then
							local profile = SC_GetUnitCapabilityProfile(escort, escortInfo, escortRole)
							local score = 1600 - assemblyDistance * 30 + (profile.intercept or 0) * 2
							if profile.doctrineClass == "air_defense_screen" then
								score = score + 420
							elseif profile.doctrineClass == "escort_screen" or profile.doctrineClass == "naval_assault" then
								score = score + 260
							elseif profile.doctrineClass == "attack_submarine" then
								score = score + 120
							elseif SC_IsProtectedDoctrineClass(profile.doctrineClass) then
								score = score - 500
							end
							if score > bestScore then
								bestScore = score
								bestEscort = escort
								bestMovePlot = movePlot
							end
						end
					end
				end
			end
		end
		local escortMoved, escortStatus, liveEscort = false, nil, nil
		if bestEscort ~= nil and bestMovePlot ~= nil then
			escortMoved, escortStatus, liveEscort = SC_TryMoveMission(bestEscort, bestMovePlot, "convoy-screen", true)
		end
		if escortStatus == "unit-removed" then
			actions = actions + 1
			break
		end
		if not escortMoved then
			break
		end
		bestEscort = liveEscort or bestEscort
		local escortKey = SC_GetUnitTurnKey(bestEscort)
		if escortKey ~= nil then
			SC_TRANSPORT_ESCORT_ORDERED_THIS_TURN[escortKey] = true
			SC_MarkStrategicUnitDone(bestEscort)
		end
		SC_ReserveMovePlot(reserved, bestMovePlot, SC_GetUnitStackLayer(bestEscort))
		actions = actions + 1
		coverage = SC_CountFriendlyNavalEscortsNearPlot(player, waypoint, SC_GetConfig("TransportEscortRadius", 2))
	end
	if coverage < requiredEscorts then
		SC_TryHoldTransport(transport, "convoy-insufficient-screen")
		local transportKey = SC_GetUnitTurnKey(transport)
		if transportKey ~= nil then
			SC_TRANSPORT_ESCORT_ORDERED_THIS_TURN[transportKey] = true
			SC_MarkStrategicUnitDone(transport)
		end
		return actions + 1, "hold-coverage="..tostring(coverage).."/"..tostring(requiredEscorts).." threats="..tostring(threats)
	end
	local transportMoved, transportStatus, liveTransport = SC_TryMoveMission(transport, waypoint, "convoy-advance", true)
	if transportStatus == "unit-removed" then
		return actions, "transport-destroyed-advance"
	end
	if not transportMoved then
		SC_TryHoldTransport(transport, "convoy-move-failed")
		return actions + 1, "hold-move-failed"
	end
	transport = liveTransport or transport
	local transportKey = SC_GetUnitTurnKey(transport)
	if transportKey ~= nil then
		SC_TRANSPORT_ESCORT_ORDERED_THIS_TURN[transportKey] = true
		SC_MarkStrategicUnitDone(transport)
	end
	SC_ReserveMovePlot(reserved, waypoint, SC_GetUnitStackLayer(transport))
	local landed = landingPlot ~= nil and not SC_IsUnitEmbarked(transport)
	return actions + 1, (landed and "landed" or "advance").." target="..tostring(targetReason).." class="..tostring(missionClass).." waypoint="..SC_GetPlotDebug(waypoint).." coverage="..tostring(coverage).." threats="..tostring(threats)
end

function SC_FindTransportEscortMovePlot(player, escort, transportPlot, reserved, stats)
	if player == nil or escort == nil or transportPlot == nil then
		return nil
	end
	local escortPlot = escort:GetPlot()
	local escortInfo = SC_GetUnitInfo(escort)
	if escortPlot == nil or escortInfo == nil then
		return nil
	end
	local layer = SC_GetUnitStackLayer(escort)
	local searchRadius = SC_GetConfig("TransportEscortSearchRadius", 2)
	local bestPlot = nil
	local bestScore = -999999
	for radius = 1, searchRadius, 1 do
		for dx = -radius, radius, 1 do
			for dy = -radius, radius, 1 do
				local plot = SC_GetNearbyPlot(transportPlot:GetX(), transportPlot:GetY(), dx, dy, radius)
				if plot ~= nil then
					local escortDistance = Map.PlotDistance(plot:GetX(), plot:GetY(), transportPlot:GetX(), transportPlot:GetY())
					if escortDistance <= searchRadius then
						local usable, moveDistance = SC_MoveCandidateIsUsable(player, escort, escortInfo, escortPlot, plot, layer, reserved, nil, stats)
						if usable and moveDistance ~= nil and moveDistance > 0 then
							local score = 1400 - moveDistance * 9 - escortDistance * 120
							if escortDistance == 1 then
								score = score + 220
							end
							local owner = SC_GetSafeNumber(function() return plot:GetOwner() end, -1)
							if owner == player:GetID() then
								score = score + 80
							end
							if score > bestScore then
								bestScore = score
								bestPlot = plot
							end
						end
					end
				end
			end
		end
		if bestPlot ~= nil then
			return bestPlot
		end
	end
	return nil
end

function SC_TryHoldTransport(unit, reason)
	if unit == nil then
		return false
	end
	return SC_TryUnitActionByType(unit, {MISSION_ALERT = true, MISSION_SKIP = true})
		or SC_TryUnitMission(unit, MissionTypes.MISSION_ALERT)
		or SC_TryUnitMission(unit, GameInfoTypes.MISSION_ALERT)
		or SC_TryUnitMission(unit, MissionTypes.MISSION_SKIP)
		or SC_TryUnitMission(unit, GameInfoTypes.MISSION_SKIP)
end

function SC_AutomateTransportEscort(player, atWar)
	if player == nil or not atWar or not SC_GetConfig("AutoTransportEscort", true) then
		return 0
	end
	local handled = 0
	local maxMoves = SC_GetConfig("MaxTransportEscortMovesPerTurn", 30)
	local escortRadius = SC_GetConfig("TransportEscortRadius", 2)
	local threatRadius = SC_GetConfig("TransportThreatRadius", 6)
	local reserved = {}
	local debugCount = 0
	local debugLimit = SC_GetConfig("DebugUnitDecisionLimit", 60)
	local function debugEscort(text)
		if SC_GetConfig("DebugUnitDecisions", true) and debugCount < debugLimit then
			debugCount = debugCount + 1
			SC_Debug(text)
		end
	end
	for transport in player:Units() do
		if handled >= maxMoves then
			return handled
		end
		if transport ~= nil and not transport:IsDead() then
			local transportInfo = SC_GetUnitInfo(transport)
			if SC_IsFragileTransportUnit(transport, transportInfo) then
				local transportKey = SC_GetUnitTurnKey(transport)
				local transportPlot = transport:GetPlot()
				if transportPlot ~= nil
					and (transportKey == nil or not SC_TRANSPORT_ESCORT_ORDERED_THIS_TURN[transportKey])
					and (SC_GetSafeNumber(function() return transportPlot:IsWater() and 1 or 0 end, 0) > 0 or SC_IsUnitEmbarked(transport)) then
					local escorts = SC_CountFriendlyNavalEscortsNearPlot(player, transportPlot, escortRadius)
					local threats = SC_CountEnemySeaThreatsNearPlot(player, transportPlot, threatRadius)
					local missionClass = SC_GetTransportMissionClass(transport, transportInfo)
					if missionClass == "trade" then
						if transportKey == nil or not SC_TRANSPORT_RELEASE_LOGGED_THIS_TURN[transportKey] then
							debugEscort("transportEscort release transport="..SC_GetUnitDebugLabel(transport).." class="..tostring(missionClass).." threats="..tostring(threats).." reason=trade-route-managed")
							if transportKey ~= nil then SC_TRANSPORT_RELEASE_LOGGED_THIS_TURN[transportKey] = true end
						end
					elseif threats <= 0 and SC_GetConfig("TransportEscortOnlyWhenThreatened", true) then
						local transportLabel = SC_GetUnitDebugLabel(transport)
						local convoyActions, convoyStatus = SC_TryAdvanceEscortedTransport(player, transport, reserved)
						handled = handled + convoyActions
						debugEscort("transportEscort unopposed-advance transport="..tostring(transportLabel)..
							" class="..tostring(missionClass).." escorts="..tostring(escorts)..
							" actions="..tostring(convoyActions).." status="..tostring(convoyStatus))
						if convoyActions <= 0 and transportKey ~= nil then
							SC_TRANSPORT_RELEASE_LOGGED_THIS_TURN[transportKey] = true
						end
					elseif escorts <= 0 then
						local bestEscort = nil
						local bestMovePlot = nil
						local bestPairKey = nil
						local bestScore = -999999
						local searchStats = {}
						for escort in player:Units() do
							if escort ~= nil and not escort:IsDead() and escort:CanMove() then
								local escortInfo = SC_GetUnitInfo(escort)
								local escortRole = SC_GetUnitRole(escort, escortInfo)
								local escortKey = SC_GetUnitTurnKey(escort)
								local pairKey = tostring(escortKey or SC_GetUnitDebugLabel(escort)).."|"..tostring(transportKey or SC_GetUnitDebugLabel(transport))
								if SC_IsNavalEscortUnit(escort, escortInfo, escortRole)
									and (escortKey == nil or not SC_TRANSPORT_ESCORT_ORDERED_THIS_TURN[escortKey])
									and not SC_TRANSPORT_ESCORT_FAILED_THIS_TURN[pairKey] then
									local escortPlot = escort:GetPlot()
									if escortPlot ~= nil then
										local distance = Map.PlotDistance(escortPlot:GetX(), escortPlot:GetY(), transportPlot:GetX(), transportPlot:GetY())
										local movePlot = SC_FindTransportEscortMovePlot(player, escort, transportPlot, reserved, searchStats)
										if movePlot ~= nil then
											local score = 2200 - distance * 10 + threats * 180
											local escortTag = SC_GetUnitCombatTag(escort, escortInfo, escortRole)
											if escortTag == "missile_screen" then
												score = score + 360
											elseif escortRole == "naval_melee" or escortTag == "surface_screen" then
												score = score + 260
											elseif escortTag == "sub_hunter" then
												score = score + 150
											elseif escortTag == "arsenal_ship" then
												score = score - 160
											end
											if score > bestScore then
												bestScore = score
												bestEscort = escort
												bestMovePlot = movePlot
												bestPairKey = pairKey
											end
										end
									end
								end
							end
						end
						local escortMoved, escortStatus, liveEscort = false, nil, nil
						local _, _, escortLabel = SC_GetUnitIdentity(bestEscort)
						if bestEscort ~= nil and bestMovePlot ~= nil then
							escortMoved, escortStatus, liveEscort = SC_TryMoveMission(bestEscort, bestMovePlot, "transportEscort", true)
						end
						if liveEscort ~= nil then bestEscort = liveEscort end
						if escortMoved then
							local escortKey = SC_GetUnitTurnKey(bestEscort)
							if escortKey ~= nil then
								SC_TRANSPORT_ESCORT_ORDERED_THIS_TURN[escortKey] = true
								SC_MarkStrategicUnitDone(bestEscort)
							end
							SC_ReserveMovePlot(reserved, bestMovePlot, SC_GetUnitStackLayer(bestEscort))
							handled = handled + 1
							local held = SC_TryHoldTransport(transport, "escort-assembling")
							if transportKey ~= nil then
								SC_TRANSPORT_ESCORT_ORDERED_THIS_TURN[transportKey] = true
								SC_MarkStrategicUnitDone(transport)
							end
							if held then
								handled = handled + 1
							end
							debugEscort("transportEscort order escort="..SC_GetUnitDebugLabel(bestEscort)..
								" transport="..SC_GetUnitDebugLabel(transport)..
								" transportPlot="..SC_GetPlotDebug(transportPlot)..
								" moveTo="..SC_GetPlotDebug(bestMovePlot)..
								" threats="..tostring(threats)..
								" escorts="..tostring(escorts)..
								" class="..tostring(missionClass)..
								" score="..tostring(bestScore)..
								" transportHeld="..SC_BoolText(held))
						elseif escortStatus == "unit-removed" then
							handled = handled + 1
							debugEscort("transportEscort escort-removed escort="..tostring(escortLabel).." transport="..SC_GetUnitDebugLabel(transport).." moveTo="..SC_GetPlotDebug(bestMovePlot))
						else
							if bestPairKey ~= nil then
								SC_TRANSPORT_ESCORT_FAILED_THIS_TURN[bestPairKey] = true
								debugEscort("transportEscort escort-failed-cached escort="..SC_GetUnitDebugLabel(bestEscort).." transport="..SC_GetUnitDebugLabel(transport).." moveTo="..SC_GetPlotDebug(bestMovePlot))
							end
						end
						if not escortMoved and SC_GetConfig("TransportHoldWithoutEscort", true) and transport:CanMove() then
							if SC_TryHoldTransport(transport, "no-escort") then
								if transportKey ~= nil then
									SC_TRANSPORT_ESCORT_ORDERED_THIS_TURN[transportKey] = true
									SC_MarkStrategicUnitDone(transport)
								end
								handled = handled + 1
								debugEscort("transportEscort hold transport="..SC_GetUnitDebugLabel(transport).." threats="..tostring(threats).." escorts="..tostring(escorts).." reason=no-escort")
							else
								debugEscort("transportEscort no-escort transport="..SC_GetUnitDebugLabel(transport).." threats="..tostring(threats).." escorts="..tostring(escorts).." reject="..SC_GetMoveRejectStatsDebug(searchStats))
							end
						elseif not escortMoved then
							debugEscort("transportEscort no-escort transport="..SC_GetUnitDebugLabel(transport).." threats="..tostring(threats).." escorts="..tostring(escorts).." reject="..SC_GetMoveRejectStatsDebug(searchStats))
						end
					else
						local transportOwnerID, transportUnitID, transportLabel = SC_GetUnitIdentity(transport)
						local convoyActions, convoyStatus = SC_TryAdvanceEscortedTransport(player, transport, reserved)
						local liveTransport = SC_ResolveLiveUnit(transportOwnerID, transportUnitID)
						if liveTransport == nil then
							handled = handled + convoyActions
							debugEscort("transportEscort convoy-removed transport="..tostring(transportLabel).." class="..tostring(missionClass).." status="..tostring(convoyStatus))
						else
							transport = liveTransport
						if convoyActions <= 0 and threats > 0 and SC_GetConfig("TransportHoldWithoutEscort", true) and transport:CanMove() then
							if SC_TryHoldTransport(transport, "convoy-deferred-under-threat") then
								convoyActions = 1
								convoyStatus = "hold-after-"..tostring(convoyStatus)
							end
						end
						handled = handled + convoyActions
						if transportKey ~= nil and convoyActions > 0 then
							SC_TRANSPORT_ESCORT_ORDERED_THIS_TURN[transportKey] = true
							SC_MarkStrategicUnitDone(transport)
						end
						debugEscort("transportEscort convoy transport="..SC_GetUnitDebugLabel(transport).." class="..tostring(missionClass).." plot="..SC_GetPlotDebug(transportPlot).." escorts="..tostring(escorts).." threats="..tostring(threats).." actions="..tostring(convoyActions).." status="..tostring(convoyStatus))
						end
					end
				end
			end
		end
	end
	return handled
end

function SC_GetSettlementPlotScore(player, plot)
	if player == nil or plot == nil then return -999999, "missing" end
	local canFound = false
	pcall(function() canFound = player:CanFound(plot:GetX(), plot:GetY()) end)
	if not canFound then return -999999, "cannot-found" end
	local score = 0
	local yieldTotal = 0
	for dx = -2, 2, 1 do
		for dy = -2, 2, 1 do
			local nearby = SC_GetNearbyPlot(plot:GetX(), plot:GetY(), dx, dy, 2)
			if nearby ~= nil then
				for _, yieldType in ipairs({YieldTypes and YieldTypes.YIELD_FOOD, YieldTypes and YieldTypes.YIELD_PRODUCTION, YieldTypes and YieldTypes.YIELD_GOLD, YieldTypes and YieldTypes.YIELD_SCIENCE}) do
					if yieldType ~= nil then yieldTotal = yieldTotal + SC_GetSafeNumber(function() return nearby:GetYield(yieldType) end, 0) end
				end
				local resource = SC_GetSafeNumber(function() return nearby:GetResourceType(player:GetTeam()) end, -1)
				if resource ~= nil and resource >= 0 then score = score + 85 end
			end
		end
	end
	score = score + yieldTotal * 9
	if SC_GetSafeNumber(function() return plot:IsRiver() and 1 or 0 end, 0) > 0 then score = score + 160 end
	if SC_GetSafeNumber(function() return plot:IsCoastalLand() and 1 or 0 end, 0) > 0 then score = score + 130 end
	local nearestCity = 999
	for city in player:Cities() do
		local cityPlot = city:Plot()
		if cityPlot ~= nil then nearestCity = math.min(nearestCity, Map.PlotDistance(plot:GetX(), plot:GetY(), cityPlot:GetX(), cityPlot:GetY())) end
	end
	if nearestCity < 4 then score = score - 1200
	elseif nearestCity <= 7 then score = score + 240
	elseif nearestCity > 14 then score = score - (nearestCity - 14) * 35 end
	local enemyDistance = SC_GetNearestEnemyCombatDistance(player, plot, 12)
	if enemyDistance <= 5 then score = score - (6 - enemyDistance) * 450 end
	return score, "yield="..tostring(yieldTotal).." cityDistance="..tostring(nearestCity).." enemyDistance="..tostring(enemyDistance)
end

function SC_TryHandleSettler(player, unit, atWar)
	if player == nil or unit == nil or unit:GetPlot() == nil then return false end
	local source = unit:GetPlot()
	local localThreat = SC_GetNearestEnemyCombatDistance(player, source, 8)
	if atWar and localThreat <= 5 then
		SC_Debug("settlerDecision hold unit="..SC_GetUnitDebugLabel(unit).." reason=enemy-near distance="..tostring(localThreat))
		return SC_TryUnitActionByType(unit, {MISSION_SKIP = true}) or SC_TryUnitMission(unit, MissionTypes.MISSION_SKIP)
	end
	local bestPlot, bestScore, bestReason = nil, -999999, "none"
	local radius = SC_GetConfig("SettlementSearchRadius", 8)
	for dx = -radius, radius, 1 do
		for dy = -radius, radius, 1 do
			local plot = SC_GetNearbyPlot(source:GetX(), source:GetY(), dx, dy, radius)
			if plot ~= nil and SC_GetSafeNumber(function() return plot:IsWater() and 1 or 0 end, 0) <= 0 then
				local score, reason = SC_GetSettlementPlotScore(player, plot)
				local distance = Map.PlotDistance(source:GetX(), source:GetY(), plot:GetX(), plot:GetY())
				score = score - distance * 12
				if score > bestScore then bestPlot, bestScore, bestReason = plot, score, reason end
			end
		end
	end
	if bestPlot == nil or bestScore < SC_GetConfig("SettlementMinimumScore", 120) then
		SC_Debug("settlerDecision hold unit="..SC_GetUnitDebugLabel(unit).." reason=no-valuable-site score="..tostring(bestScore))
		return SC_TryUnitActionByType(unit, {MISSION_SKIP = true}) or SC_TryUnitMission(unit, MissionTypes.MISSION_SKIP)
	end
	local distance = Map.PlotDistance(source:GetX(), source:GetY(), bestPlot:GetX(), bestPlot:GetY())
	if distance <= 0 then
		local founded = SC_TryUnitActionByType(unit, {MISSION_FOUND = true})
			or SC_TryUnitMission(unit, MissionTypes.MISSION_FOUND, source:GetX(), source:GetY(), true)
		SC_Debug("settlerDecision found unit="..SC_GetUnitDebugLabel(unit).." plot="..SC_GetPlotDebug(source).." score="..tostring(math.floor(bestScore)).." reason="..tostring(bestReason).." success="..SC_BoolText(founded))
		return founded
	end
	local moved = SC_TryMoveMission(unit, bestPlot, "settler-site", true)
	SC_Debug("settlerDecision move unit="..SC_GetUnitDebugLabel(unit).." target="..SC_GetPlotDebug(bestPlot).." distance="..tostring(distance).." score="..tostring(math.floor(bestScore)).." reason="..tostring(bestReason).." success="..SC_BoolText(moved == true))
	return moved == true
end

local function SC_AutomateFinalUnitOrders(player, atWar)
	if not SC_GetConfig("AutoIdlePosture", true) or player == nil then
		return 0
	end
	local handled = 0
	local maxOrders = SC_GetConfig("MaxFinalUnitOrdersPerTurn", 120)
	local maxRounds = SC_GetConfig("MaxFinalUnitOrderRounds", 4)
	local debugCount = 0
	local debugLimit = SC_GetConfig("DebugUnitDecisionLimit", 60)
	local function debugFinal(text)
		if SC_GetConfig("DebugUnitDecisions", true) and debugCount < debugLimit then
			debugCount = debugCount + 1
			SC_Debug(text)
		end
	end
	SC_Debug("finalOrders start maxOrders="..tostring(maxOrders).." maxRounds="..tostring(maxRounds).." atWar="..SC_BoolText(atWar).." tasks="..tostring(SC_StrategyTaskMetricsDebug and SC_StrategyTaskMetricsDebug() or "legacy"))
	local function unitStillFirstReady(unit)
		local firstReady = nil
		pcall(function() firstReady = player:GetFirstReadyUnit() end)
		return firstReady ~= nil and firstReady == unit
	end
	local function finishUnit(unit, forceReady)
		if unit == nil then
			return false
		end
		if not forceReady and not SC_UnitNeedsOrder(unit) then
			return false
		end
		local unitKey = SC_GetUnitTurnKey(unit)
		local attemptCount = 0
		if unitKey ~= nil and SC_FINAL_ORDER_ATTEMPTED_THIS_TURN[unitKey] ~= nil then
			attemptCount = SC_FINAL_ORDER_ATTEMPTED_THIS_TURN[unitKey]
			if attemptCount == true then
				attemptCount = 1
			end
		end
		local maxAttemptsForUnit = SC_GetConfig("MaxFinalOrderAttemptsPerUnitPerTurn", 5)
		if attemptCount >= maxAttemptsForUnit then
			return SC_TryForceClearUnitOrder(unit, "finalOrders-attempt-cap")
		end
		if unitKey ~= nil then
			SC_FINAL_ORDER_ATTEMPTED_THIS_TURN[unitKey] = attemptCount + 1
		end
		local unitInfo = GameInfo.Units[unit:GetUnitType()]
		local role = SC_GetUnitRole(unit, unitInfo)
		local unitTag = SC_GetUnitCombatTag(unit, unitInfo, role)
		local taskDebug = SC_StrategyGetUnitTaskDebug ~= nil and SC_StrategyGetUnitTaskDebug(unit) or "legacy"
		local retreatThreshold = SC_GetUnitRetreatDamageThreshold(unit, unitInfo, role)
		local done = false
		if unitKey ~= nil and unit:GetDamage() >= retreatThreshold
			and (SC_HEAL_HANDLED_THIS_TURN[unitKey] or SC_HEAL_FAILED_THIS_TURN[unitKey])
			or (SC5 and SC5.IsWithdrawing(unit)) then
			done = SC_TryUnitActionByType(unit, {MISSION_ALERT = true, MISSION_SKIP = true})
				or SC_TryUnitMission(unit, MissionTypes.MISSION_ALERT)
				or SC_TryUnitMission(unit, GameInfoTypes.MISSION_ALERT)
				or SC_TryUnitMission(unit, MissionTypes.MISSION_SKIP)
				or SC_TryUnitMission(unit, GameInfoTypes.MISSION_SKIP)
			debugFinal("finalOrders preserve-retreat unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role).." damage="..tostring(unit:GetDamage()).." threshold="..tostring(retreatThreshold).." healHandled="..SC_BoolText(SC_HEAL_HANDLED_THIS_TURN[unitKey]).." healFailed="..SC_BoolText(SC_HEAL_FAILED_THIS_TURN[unitKey]).." done="..SC_BoolText(done).." state="..SC_GetUnitOrderDebug(unit))
			if done then
				return true
			end
		end
		if SC_UnitCanPromoteNow(unit) then
			done = SC_TryPromoteUnit(unit, "finalOrders")
			if done then
				debugFinal("finalOrders promoted unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role).." tag="..tostring(unitTag).." attempt="..tostring(attemptCount + 1).." state="..SC_GetUnitOrderDebug(unit))
				return true
			end
			debugFinal("finalOrders promotion-unresolved unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role).." tag="..tostring(unitTag).." attempt="..tostring(attemptCount + 1).." state="..SC_GetUnitOrderDebug(unit))
			return false
		end
		-- The final-order pass is cleanup only. Tactical attacks belong to the combat modules,
		-- otherwise the same unit can rescan and fire after its operation has already finished.
		if SC_IsGreatPersonLike(unitInfo) then
			if SC_GetConfig("GreatPersonProfile", "AUTO") ~= "SLEEP" then
				done = SC_TryGreatPersonActionFallback(unit, unitInfo, "finalOrders-blocked")
			end
			if not done then
				done = SC_TryUnitActionByType(unit, {MISSION_SLEEP = true, COMMAND_SLEEP = true}) or SC_TryUnitCommand(unit, CommandTypes.COMMAND_SLEEP) or SC_TryUnitMission(unit, MissionTypes.MISSION_SLEEP) or SC_TryUnitMission(unit, GameInfoTypes.MISSION_SLEEP) or SC_TryUnitActionByType(unit, {MISSION_SKIP = true}) or SC_TryUnitMission(unit, MissionTypes.MISSION_SKIP) or SC_TryUnitMission(unit, GameInfoTypes.MISSION_SKIP)
			end
		end
		if not done and SC_IsTradeLike(unitInfo) then
			done = SC_TryUnitActionByType(unit, {MISSION_SKIP = true}) or SC_TryUnitMission(unit, MissionTypes.MISSION_SKIP) or SC_TryUnitMission(unit, GameInfoTypes.MISSION_SKIP)
		end
		if not done and atWar and SC_IsFragileTransportUnit(unit, unitInfo) then
			local transportPlot = unit:GetPlot()
			local escorts = SC_CountFriendlyNavalEscortsNearPlot(player, transportPlot, SC_GetConfig("TransportEscortRadius", 2))
			local threats = SC_CountEnemySeaThreatsNearPlot(player, transportPlot, SC_GetConfig("TransportThreatRadius", 6))
			if threats > 0 and escorts <= 0 and SC_GetConfig("TransportHoldWithoutEscort", true) then
				done = SC_TryHoldTransport(unit, "finalOrders-no-escort")
				debugFinal("finalOrders transport-hold unit="..SC_GetUnitDebugLabel(unit).." escorts="..tostring(escorts).." threats="..tostring(threats).." done="..SC_BoolText(done).." state="..SC_GetUnitOrderDebug(unit))
			else
				if unitKey == nil or not SC_TRANSPORT_RELEASE_LOGGED_THIS_TURN[unitKey] then
					debugFinal("finalOrders transport-release unit="..SC_GetUnitDebugLabel(unit).." escorts="..tostring(escorts).." threats="..tostring(threats).." reason="..(threats <= 0 and "no-local-threat" or "covered"))
					if unitKey ~= nil then SC_TRANSPORT_RELEASE_LOGGED_THIS_TURN[unitKey] = true end
				end
			end
		end
		if not done and unit:GetDamage() >= retreatThreshold and unit:IsCombatUnit() then
			if unitKey ~= nil and SC_HEAL_FAILED_THIS_TURN[unitKey] then
				debugFinal("finalOrders heal-cached-skip unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role).." attempt="..tostring(attemptCount + 1).." state="..SC_GetUnitOrderDebug(unit))
			else
				local healMission = nil
				if MissionTypes ~= nil then
					healMission = MissionTypes.MISSION_HEAL
				end
				if healMission == nil and GameInfoTypes ~= nil then
					healMission = GameInfoTypes.MISSION_HEAL
				end
				done = SC_TryUnitActionByType(unit, {MISSION_HEAL = true})
				if not done and healMission ~= nil then
					done = SC_TryUnitMission(unit, healMission, nil, nil, false)
				end
				if not done then
					if unitKey ~= nil then
						SC_HEAL_FAILED_THIS_TURN[unitKey] = true
					end
					debugFinal("finalOrders heal-unresolved unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role).." attempt="..tostring(attemptCount + 1).." state="..SC_GetUnitOrderDebug(unit))
				end
			end
		end
		if not done and unitInfo ~= nil and unitInfo.DefaultUnitAI == "UNITAI_SETTLE" then
			done = SC_TryHandleSettler(player, unit, atWar)
		end
		if not done and SC_IsWorkerLike(unitInfo) then
			local workerSafe = not SC_IsFragileTransportUnit(unit, unitInfo)
			if not workerSafe then
				local workerPlot = unit:GetPlot()
				local workerThreats = workerPlot ~= nil and SC_CountEnemySeaThreatsNearPlot(player, workerPlot, SC_GetConfig("TransportThreatRadius", 6)) or 0
				workerSafe = workerThreats <= 0
				debugFinal("finalOrders worker-transport unit="..SC_GetUnitDebugLabel(unit).." threats="..tostring(workerThreats).." automate="..SC_BoolText(workerSafe))
			end
			if workerSafe then
				done = SC_TryUnitCommand(unit, CommandTypes.COMMAND_AUTOMATE, GameInfoTypes.AUTOMATE_BUILD, -1)
			end
		end
		if not done and SC_IsExploreLike(unitInfo) then
			done = SC_TryUnitCommand(unit, CommandTypes.COMMAND_AUTOMATE, GameInfoTypes.AUTOMATE_EXPLORE, -1)
		end
		if not done and unit:IsCombatUnit() then
			if atWar then
				if role == "fighter" or role == "carrier_air" then
					done = SC_TryUnitActionByType(unit, {MISSION_AIRPATROL = true, MISSION_INTERCEPT = true, MISSION_ALERT = true, MISSION_SKIP = true}) or SC_TryUnitMission(unit, MissionTypes.MISSION_AIRPATROL) or SC_TryUnitMission(unit, GameInfoTypes.MISSION_AIRPATROL) or SC_TryUnitMission(unit, MissionTypes.MISSION_INTERCEPT) or SC_TryUnitMission(unit, GameInfoTypes.MISSION_INTERCEPT) or SC_TryUnitMission(unit, MissionTypes.MISSION_SKIP) or SC_TryUnitMission(unit, GameInfoTypes.MISSION_SKIP)
				else
					done = SC_TryUnitActionByType(unit, {MISSION_ALERT = true, MISSION_SKIP = true}) or SC_TryUnitMission(unit, MissionTypes.MISSION_ALERT) or SC_TryUnitMission(unit, GameInfoTypes.MISSION_ALERT) or SC_TryUnitMission(unit, MissionTypes.MISSION_SKIP) or SC_TryUnitMission(unit, GameInfoTypes.MISSION_SKIP)
				end
			else
				done = SC_TryUnitActionByType(unit, {MISSION_SLEEP = true, MISSION_ALERT = true}) or SC_TryUnitMission(unit, MissionTypes.MISSION_SLEEP) or SC_TryUnitMission(unit, GameInfoTypes.MISSION_SLEEP) or SC_TryUnitMission(unit, MissionTypes.MISSION_ALERT) or SC_TryUnitMission(unit, GameInfoTypes.MISSION_ALERT)
			end
		end
		if not done and atWar and (role == "fighter" or role == "carrier_air") then
			done = SC_TryUnitActionByType(unit, {MISSION_AIRPATROL = true, MISSION_INTERCEPT = true, MISSION_SKIP = true}) or SC_TryUnitMission(unit, MissionTypes.MISSION_AIRPATROL) or SC_TryUnitMission(unit, GameInfoTypes.MISSION_AIRPATROL) or SC_TryUnitMission(unit, MissionTypes.MISSION_INTERCEPT) or SC_TryUnitMission(unit, GameInfoTypes.MISSION_INTERCEPT) or SC_TryUnitMission(unit, MissionTypes.MISSION_SKIP) or SC_TryUnitMission(unit, GameInfoTypes.MISSION_SKIP)
		end
		if not done then
			done = SC_TryUnitActionByType(unit, {MISSION_SKIP = true}) or SC_TryUnitMission(unit, MissionTypes.MISSION_SKIP) or SC_TryUnitMission(unit, GameInfoTypes.MISSION_SKIP)
		end
		if not done then
			done = SC_TryUnitActionByType(unit, {MISSION_SLEEP = true}) or SC_TryUnitMission(unit, MissionTypes.MISSION_SLEEP) or SC_TryUnitMission(unit, GameInfoTypes.MISSION_SLEEP)
		end
		if not done then
			done = SC_TryUnitActionByType(unit, {MISSION_SKIP = true, MISSION_SLEEP = true, MISSION_ALERT = true, COMMAND_SLEEP = true, COMMAND_ALERT = true})
		end
		if SC_UnitNeedsOrder(unit) and ((not done) or (attemptCount + 1) >= maxAttemptsForUnit) then
			local forced = SC_TryForceClearUnitOrder(unit, "finalOrders-pending")
			if forced then
				done = true
			end
		end
		local stillNeeds = SC_UnitNeedsOrder(unit) or unitStillFirstReady(unit)
		if done and not stillNeeds then
			debugFinal("finalOrders handled unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role).." task="..tostring(taskDebug).." attempt="..tostring(attemptCount + 1).." forceReady="..SC_BoolText(forceReady == true).." state="..SC_GetUnitOrderDebug(unit))
		elseif done then
			debugFinal("finalOrders sent unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role).." task="..tostring(taskDebug).." attempt="..tostring(attemptCount + 1).." forceReady="..SC_BoolText(forceReady == true).." pendingClear=true state="..SC_GetUnitOrderDebug(unit))
		else
			debugFinal("finalOrders failed unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role).." task="..tostring(taskDebug).." attempt="..tostring(attemptCount + 1).." forceReady="..SC_BoolText(forceReady == true).." stillNeeds="..SC_BoolText(stillNeeds).." state="..SC_GetUnitOrderDebug(unit))
		end
		return done
	end
	for round = 1, maxRounds, 1 do
		local roundHandled = 0
		for readyIndex = 1, maxOrders, 1 do
			if handled >= maxOrders then
				break
			end
			local firstReady = nil
			pcall(function() firstReady = player:GetFirstReadyUnit() end)
			if firstReady == nil then
				break
			end
			if finishUnit(firstReady, true) then
				handled = handled + 1
				roundHandled = roundHandled + 1
			else
				break
			end
		end
		for unit in player:Units() do
			if handled >= maxOrders then
				break
			end
			if finishUnit(unit, false) then
				handled = handled + 1
				roundHandled = roundHandled + 1
			end
		end
		if roundHandled == 0 or handled >= maxOrders then
			break
		end
	end
	SC_Debug("finalOrders end handled="..tostring(handled))
	return handled
end

local function SC_GetLeagueByIndex(index)
	local league = nil
	pcall(function() league = Game.GetLeague(index) end)
	return league
end

local function SC_GetChoiceForLeagueDecision(league, decisionType, activePlayerID, resolutionType)
	if league == nil or decisionType == nil or decisionType == "RESOLUTION_DECISION_NONE" then
		return -1
	end
	local decision = GameInfo.ResolutionDecisions[decisionType]
	if decision == nil then
		return -1
	end
	local choices = nil
	pcall(function() choices = league:GetChoicesForDecision(decision.ID, activePlayerID) end)
	if choices == nil then
		return -1
	end
	for _, choiceID in ipairs(choices) do
		if choiceID == activePlayerID then
			if resolutionType == nil or SC_GetSafeNumber(function() return league:CanProposeEnact(resolutionType, activePlayerID, choiceID) and 1 or 0 end, 1) > 0 then
				return choiceID
			end
		end
	end
	for _, choiceID in ipairs(choices) do
		if resolutionType == nil or SC_GetSafeNumber(function() return league:CanProposeEnact(resolutionType, activePlayerID, choiceID) and 1 or 0 end, 1) > 0 then
			return choiceID
		end
	end
	return -1
end

local function SC_AutomateLeagueProposalsForLeague(leagueID, league, activePlayerID)
	if league == nil or Network == nil or not SC_GetConfig("AutoPopupHandling", true) then
		return 0
	end
	local remaining = SC_GetSafeNumber(function() return league:GetRemainingProposalsForMember(activePlayerID) end, 0)
	if remaining <= 0 or SC_GetSafeNumber(function() return league:CanPropose(activePlayerID) and 1 or 0 end, 0) <= 0 then
		return 0
	end
	local made = 0
	for i = 1, remaining, 1 do
		local sent = false
		local inactive = nil
		pcall(function() inactive = league:GetInactiveResolutions() end)
		if inactive ~= nil then
			for _, resolution in ipairs(inactive) do
				local resolutionType = resolution.Type
				if resolutionType ~= nil and SC_GetSafeNumber(function() return league:CanProposeEnactAnyChoice(resolutionType, activePlayerID) and 1 or 0 end, 0) > 0 then
					local decisionType = GameInfo.Resolutions[resolutionType] and GameInfo.Resolutions[resolutionType].ProposerDecision
					local choiceID = SC_GetChoiceForLeagueDecision(league, decisionType, activePlayerID, resolutionType)
					local ok = pcall(function()
						Network.SendLeagueProposeEnact(leagueID, resolutionType, activePlayerID, choiceID)
					end)
					if ok then
						made = made + 1
						sent = true
						break
					end
				end
			end
		end
		if not sent then
			local active = nil
			pcall(function() active = league:GetActiveResolutions() end)
			if active ~= nil then
				for _, resolution in ipairs(active) do
					local resolutionID = resolution.ID
					if resolutionID ~= nil and SC_GetSafeNumber(function() return league:CanProposeRepeal(resolutionID, activePlayerID) and 1 or 0 end, 0) > 0 then
						local ok = pcall(function()
							Network.SendLeagueProposeRepeal(leagueID, resolutionID, activePlayerID)
						end)
						if ok then
							made = made + 1
							sent = true
							break
						end
					end
				end
			end
		end
		if not sent then
			break
		end
	end
	return made
end

local function SC_AutomateLeagueVotesForLeague(leagueID, league, activePlayerID)
	if league == nil or Network == nil or not SC_GetConfig("AutoPopupHandling", true) then
		return 0
	end
	if SC_GetSafeNumber(function() return league:IsInSession() and 1 or 0 end, 0) <= 0 then
		return 0
	end
	local votes = SC_GetSafeNumber(function() return league:GetRemainingVotesForMember(activePlayerID) end, 0)
	if votes <= 0 then
		return 0
	end
	local enact = nil
	pcall(function() enact = league:GetEnactProposals() end)
	if enact ~= nil then
		for _, proposal in ipairs(enact) do
			local choiceID = 1
			local decisionType = GameInfo.Resolutions[proposal.Type] and GameInfo.Resolutions[proposal.Type].VoterDecision
			if decisionType ~= nil and decisionType ~= "RESOLUTION_DECISION_YES_OR_NO" then
				choiceID = SC_GetChoiceForLeagueDecision(league, decisionType, activePlayerID, nil)
			end
			local ok = pcall(function()
				Network.SendLeagueVoteEnact(leagueID, proposal.ID, activePlayerID, votes, choiceID)
			end)
			if ok then
				return votes
			end
		end
	end
	local repeal = nil
	pcall(function() repeal = league:GetRepealProposals() end)
	if repeal ~= nil then
		for _, proposal in ipairs(repeal) do
			local choiceID = 1
			local decisionType = GameInfo.Resolutions[proposal.Type] and GameInfo.Resolutions[proposal.Type].VoterDecision
			if decisionType ~= nil and decisionType ~= "RESOLUTION_DECISION_YES_OR_NO" then
				choiceID = SC_GetChoiceForLeagueDecision(league, decisionType, activePlayerID, nil)
			end
			local ok = pcall(function()
				Network.SendLeagueVoteRepeal(leagueID, proposal.ID, activePlayerID, votes, choiceID)
			end)
			if ok then
				return votes
			end
		end
	end
	local ok = pcall(function()
		Network.SendLeagueVoteAbstain(leagueID, activePlayerID, votes)
	end)
	if ok then
		return votes
	end
	return 0
end

local function SC_AutomateLeagues(player)
	if player == nil or Game == nil or Game.GetNumActiveLeagues == nil then
		return 0
	end
	local activePlayerID = player:GetID()
	local handled = 0
	local leagueCount = SC_GetSafeNumber(function() return Game.GetNumActiveLeagues() end, 0)
	for leagueID = 0, leagueCount - 1, 1 do
		local league = SC_GetLeagueByIndex(leagueID)
		if league ~= nil then
			handled = handled + SC_AutomateLeagueProposalsForLeague(leagueID, league, activePlayerID)
			handled = handled + SC_AutomateLeagueVotesForLeague(leagueID, league, activePlayerID)
		end
	end
	return handled
end

local function SC_AutomateDiploVote(player)
	if player == nil or Network == nil or Network.SendDiploVote == nil then
		return 0
	end
	local activePlayerID = player:GetID()
	local votePlayerID = nil
	local activeTeam = Teams[player:GetTeam()]
	for otherID, otherPlayer in pairs(Players) do
		if otherPlayer ~= nil and otherPlayer:IsAlive() and not otherPlayer:IsMinorCiv() and otherID ~= activePlayerID then
			local met = true
			if activeTeam ~= nil then
				pcall(function() met = activeTeam:IsHasMet(otherPlayer:GetTeam()) end)
			end
			if met then
				votePlayerID = otherID
				break
			end
		end
	end
	if votePlayerID == nil then
		votePlayerID = activePlayerID
	end
	local ok = pcall(function()
		Network.SendDiploVote(votePlayerID)
	end)
	if ok then
		return 1
	end
	return 0
end

local function SC_MatchesEndTurnBlock(blocking, name)
	return EndTurnBlockingTypes ~= nil and EndTurnBlockingTypes[name] ~= nil and blocking == EndTurnBlockingTypes[name]
end

local function SC_BlockingIsAny(blocking, names)
	for _, name in ipairs(names) do
		if SC_MatchesEndTurnBlock(blocking, name) then
			return true
		end
	end
	return false
end

local function SC_ActivateBlockingNotification(player)
	if player == nil or UI == nil or UI.ActivateNotification == nil then
		return 0
	end
	local notificationID = SC_GetSafeNumber(function() return player:GetEndTurnBlockingNotificationIndex() end, -1)
	if notificationID == nil or notificationID < 0 then
		return 0
	end
	local ok = pcall(function()
		UI.ActivateNotification(notificationID)
	end)
	if ok then
		return 1
	end
	return 0
end

local function SC_HandleEndTurnBlocker(player, atWar, allowNotificationActivation)
	if player == nil or EndTurnBlockingTypes == nil then
		return 0
	end
	if SCV3_HandleEndTurnBlocker ~= nil and SC_GetV3Adapters ~= nil then
		return SCV3_HandleEndTurnBlocker(player, atWar, allowNotificationActivation, SC_GetV3Adapters())
	end
	if allowNotificationActivation == nil then
		allowNotificationActivation = true
	end
	local blocking = SC_GetSafeNumber(function() return player:GetEndTurnBlockingType() end, -999)
	if blocking == EndTurnBlockingTypes.NO_ENDTURN_BLOCKING_TYPE then
		return 0
	end
	local handled = 0
	if SC_MatchesEndTurnBlock(blocking, "ENDTURN_BLOCKING_UNIT_PROMOTION") then
		handled = handled + SC_AutomateUnitPromotions(player)
	elseif SC_MatchesEndTurnBlock(blocking, "ENDTURN_BLOCKING_STACKED_UNITS") then
		handled = handled + SC_AutomateStackedUnits(player)
		if handled == 0 then
			handled = handled + SC_AutomateFinalUnitOrders(player, atWar)
		end
	elseif SC_BlockingIsAny(blocking, {"ENDTURN_BLOCKING_UNIT_NEEDS_ORDERS", "ENDTURN_BLOCKING_UNITS"}) then
		handled = handled + SC_AutomateStackedUnits(player)
		handled = handled + SC_AutomateFinalUnitOrders(player, atWar)
	elseif SC_MatchesEndTurnBlock(blocking, "ENDTURN_BLOCKING_CITY_RANGE_ATTACK") then
		handled = handled + SC_AutomateCityRangedStrike(player, atWar)
	elseif SC_BlockingIsAny(blocking, {"ENDTURN_BLOCKING_RESEARCH", "ENDTURN_BLOCKING_FREE_TECH", "ENDTURN_BLOCKING_STEAL_TECH"}) then
		handled = handled + SC_AutomateResearch(player)
	elseif SC_MatchesEndTurnBlock(blocking, "ENDTURN_BLOCKING_PRODUCTION") then
		local cityOrders = 0
		cityOrders = SC_AutomateCities(player, atWar)
		handled = handled + cityOrders
	elseif SC_BlockingIsAny(blocking, {"ENDTURN_BLOCKING_POLICY", "ENDTURN_BLOCKING_FREE_POLICY", "ENDTURN_BLOCKING_CHOOSE_IDEOLOGY"}) then
		local policyHandled = SC_AutomateIdeology(player) + SC_AutomatePolicy(player)
		handled = handled + policyHandled
		if policyHandled <= 0 and SC_ShouldDelegatePolicyPopupToUI(player) then
			local ok = pcall(function() SC_OpenPolicies() end)
			if ok then
				handled = handled + 1
				SC_Debug("policy blocker opened-ui blocker="..SC_GetEnumDebugName(EndTurnBlockingTypes, blocking))
			end
		end
	elseif SC_MatchesEndTurnBlock(blocking, "ENDTURN_BLOCKING_DIPLO_VOTE") then
		handled = handled + SC_AutomateDiploVote(player) + SC_AutomateLeagues(player)
	elseif SC_BlockingIsAny(blocking, {"ENDTURN_BLOCKING_LEAGUE_CALL_FOR_PROPOSALS", "ENDTURN_BLOCKING_LEAGUE_CALL_FOR_VOTES"}) then
		handled = handled + SC_AutomateLeagues(player)
	end
	local after = SC_GetSafeNumber(function() return player:GetEndTurnBlockingType() end, blocking)
	if handled > 0 and SC_BlockingIsAny(after, {"ENDTURN_BLOCKING_DIPLO_VOTE", "ENDTURN_BLOCKING_LEAGUE_CALL_FOR_PROPOSALS", "ENDTURN_BLOCKING_LEAGUE_CALL_FOR_VOTES"}) then
		SC_Debug("league blocker pending blocker="..SC_GetEnumDebugName(EndTurnBlockingTypes, after).." handled="..tostring(handled))
		SC_ActivateBlockingNotification(player)
	end
	if allowNotificationActivation and after ~= EndTurnBlockingTypes.NO_ENDTURN_BLOCKING_TYPE and handled == 0 then
		if SC_ActivateBlockingNotification(player) > 0 then
			SC_Debug("blocker notification-activated blocker="..SC_GetEnumDebugName(EndTurnBlockingTypes, after))
		end
	end
	return handled
end

function SC_RunCountModule(moduleName, callback)
	local started = nil
	if SC_GetConfig("DebugPerformance", true) and os ~= nil and os.clock ~= nil then
		pcall(function() started = os.clock() end)
	end
	local ok, count, detail = pcall(callback)
	if started ~= nil then
		local finished = nil
		pcall(function() finished = os.clock() end)
		if finished ~= nil then
			local elapsedMs = math.floor(math.max(0, finished - started) * 1000 + 0.5)
			if elapsedMs >= SC_GetConfig("DebugPerformanceThresholdMs", 50) then
				SC_Debug("performance module="..tostring(moduleName).." elapsedMs="..tostring(elapsedMs)..
					" result="..tostring(ok and count or "error"))
			end
		end
	end
	if not ok then
		SC_Debug("module error name="..tostring(moduleName).." err="..tostring(count).." recovery=continue")
		return 0, nil, 1
	end
	local normalized = tonumber(count)
	if normalized == nil then
		SC_Debug("module invalid-result name="..tostring(moduleName).." value="..tostring(count).." recovery=zero")
		normalized = 0
	end
	return normalized, detail, 0
end

local function SC_BuildAutomationResults(player, atWar, fullAutomation)
	if fullAutomation == false then
		return SC_BuildLightweightAutomationResults(player, atWar)
	end
	local rosterOK, roster = pcall(function() return SC_GetDoctrineRosterDebug(player) end)
	if rosterOK then
		SC_Debug("doctrineRoster "..tostring(roster))
	else
		SC_Debug("module error name=doctrineRoster err="..tostring(roster).." recovery=continue")
	end
	local results = {
		cityOrders = 0,
		capitalActions = 0,
		ideologies = 0,
		research = 0,
		policies = 0,
		upgrades = 0,
		promotions = 0,
		greatPeople = 0,
		purchases = 0,
		heals = 0,
		defenseActions = 0,
		captureFinishers = 0,
		cityStrikes = 0,
		strategicMoves = 0,
		stackedMoves = 0,
		transportEscort = 0,
		idlePosture = 0,
		tradeRoutes = 0,
		finalOrders = 0,
		notifications = 0,
		leagues = 0,
		blockers = 0,
		popups = 0,
		diplo = 0,
		moduleErrors = rosterOK and 0 or 1
	}
	local cityDetails = {}
	local maxSweeps = SC_GetConfig("MaxTakeoverInnerSweeps", 3)
	for sweep = 1, maxSweeps, 1 do
		SC_Debug("sweep begin index="..tostring(sweep).." mode=full blocker="..SC_GetBlockingDebug(player))
		local before = results.cityOrders + results.capitalActions + results.ideologies + results.research + results.policies + results.upgrades + results.promotions + results.greatPeople + results.purchases + results.heals + results.captureFinishers + results.defenseActions + results.cityStrikes + results.transportEscort + results.strategicMoves + results.stackedMoves + results.idlePosture + results.tradeRoutes + results.finalOrders + results.leagues + results.blockers
		local count = 0
		local _ = nil
		local moduleErrors = 0
		if sweep == 1 then
			count, _, moduleErrors = SC_RunCountModule("capitalDeployment", function() return SC_AutomateCapitalDeployment(player, atWar) end)
			results.capitalActions = results.capitalActions + count
			results.moduleErrors = results.moduleErrors + moduleErrors
			local cityOrders, details = 0, nil
			cityOrders, details, moduleErrors = SC_RunCountModule("cities", function() return SC_AutomateCities(player, atWar) end)
			results.moduleErrors = results.moduleErrors + moduleErrors
			results.cityOrders = results.cityOrders + cityOrders
			if details ~= nil then
				for _, detail in ipairs(details) do
					if #cityDetails < 10 then
						table.insert(cityDetails, detail)
					end
				end
			end
			count, _, moduleErrors = SC_RunCountModule("militaryPurchase", function() return SC_AutomateMilitaryPurchases(player, atWar) end)
			results.purchases = results.purchases + count
			results.moduleErrors = results.moduleErrors + moduleErrors
			count, _, moduleErrors = SC_RunCountModule("ideology", function() return SC_AutomateIdeology(player) end)
			results.ideologies = results.ideologies + count
			results.moduleErrors = results.moduleErrors + moduleErrors
			count, _, moduleErrors = SC_RunCountModule("research", function() return SC_AutomateResearch(player) end)
			results.research = results.research + count
			results.moduleErrors = results.moduleErrors + moduleErrors
			count, _, moduleErrors = SC_RunCountModule("policy", function() return SC_AutomatePolicy(player) end)
			results.policies = results.policies + count
			results.moduleErrors = results.moduleErrors + moduleErrors
			count, _, moduleErrors = SC_RunCountModule("upgrade", function() return SC_AutomateUnitUpgrades(player) end)
			results.upgrades = results.upgrades + count
			results.moduleErrors = results.moduleErrors + moduleErrors
			count, _, moduleErrors = SC_RunCountModule("promotion", function() return SC_AutomateUnitPromotions(player) end)
			results.promotions = results.promotions + count
			results.moduleErrors = results.moduleErrors + moduleErrors
			count, _, moduleErrors = SC_RunCountModule("greatPeople", function() return SC_AutomateGreatPeople(player, atWar) end)
			results.greatPeople = results.greatPeople + count
			results.moduleErrors = results.moduleErrors + moduleErrors
			count, _, moduleErrors = SC_RunCountModule("healing", function() return SC_AutomateDamagedUnitHealing(player) end)
			results.heals = results.heals + count
			results.moduleErrors = results.moduleErrors + moduleErrors
			count, _, moduleErrors = SC_RunCountModule("transportEscort", function() return SC_AutomateTransportEscort(player, atWar) end)
			results.transportEscort = results.transportEscort + count
			results.moduleErrors = results.moduleErrors + moduleErrors
			count, _, moduleErrors = SC_RunCountModule("airRebase", function() return SC_AutomateAirRebase(player, atWar) end)
			results.strategicMoves = results.strategicMoves + count
			results.moduleErrors = results.moduleErrors + moduleErrors
		end
		count, _, moduleErrors = SC_RunCountModule("captureFinishers", function() return SC_AutomateCityCaptureFinishers(player, atWar) end)
		results.captureFinishers = results.captureFinishers + count
		results.moduleErrors = results.moduleErrors + moduleErrors
		count, _, moduleErrors = SC_RunCountModule("airSuperiority", function() return SC_AutomateAirSuperiority(player, atWar) end)
		results.defenseActions = results.defenseActions + count
		results.moduleErrors = results.moduleErrors + moduleErrors
		count, _, moduleErrors = SC_RunCountModule("localDefense", function() return SC_AutomateLocalDefense(player, atWar) end)
		results.defenseActions = results.defenseActions + count
		results.moduleErrors = results.moduleErrors + moduleErrors
		-- Ranged and air actions may have reduced a city during this sweep.  Run
		-- the reserved finisher immediately, before any strategic movement can
		-- spend the capturer's remaining movement on a different objective.
		count, _, moduleErrors = SC_RunCountModule("captureAfterFire", function() return SC_AutomateCityCaptureFinishers(player, atWar) end)
		results.captureFinishers = results.captureFinishers + count
		results.moduleErrors = results.moduleErrors + moduleErrors
		count, _, moduleErrors = SC_RunCountModule("cityStrike", function() return SC_AutomateCityRangedStrike(player, atWar) end)
		results.cityStrikes = results.cityStrikes + count
		results.moduleErrors = results.moduleErrors + moduleErrors
		if sweep == 1 then
			count, _, moduleErrors = SC_RunCountModule("strategicMovement", function() return SC_AutomateStrategicMovement(player, atWar) end)
			results.strategicMoves = results.strategicMoves + count
			results.moduleErrors = results.moduleErrors + moduleErrors
			count, _, moduleErrors = SC_RunCountModule("stackedUnits", function() return SC_AutomateStackedUnits(player) end)
			results.stackedMoves = results.stackedMoves + count
			results.moduleErrors = results.moduleErrors + moduleErrors
			count, _, moduleErrors = SC_RunCountModule("idlePosture", function() return SC_AutomateIdlePosture(player) end)
			results.idlePosture = results.idlePosture + count
			results.moduleErrors = results.moduleErrors + moduleErrors
			count, _, moduleErrors = SC_RunCountModule("tradeRoutes", function() return SC_AutomateTradeRoutes(player) end)
			results.tradeRoutes = results.tradeRoutes + count
			results.moduleErrors = results.moduleErrors + moduleErrors
		end
		count, _, moduleErrors = SC_RunCountModule("finalOrders", function() return SC_AutomateFinalUnitOrders(player, atWar) end)
		results.finalOrders = results.finalOrders + count
		results.moduleErrors = results.moduleErrors + moduleErrors
		if sweep == 1 then
			count, _, moduleErrors = SC_RunCountModule("leagues", function() return SC_AutomateLeagues(player) end)
			results.leagues = results.leagues + count
			results.moduleErrors = results.moduleErrors + moduleErrors
		end
		count, _, moduleErrors = SC_RunCountModule("endTurnBlocker", function() return SC_HandleEndTurnBlocker(player, atWar) end)
		results.blockers = results.blockers + count
		results.moduleErrors = results.moduleErrors + moduleErrors
		local after = results.cityOrders + results.capitalActions + results.ideologies + results.research + results.policies + results.upgrades + results.promotions + results.greatPeople + results.purchases + results.heals + results.captureFinishers + results.defenseActions + results.cityStrikes + results.transportEscort + results.strategicMoves + results.stackedMoves + results.idlePosture + results.tradeRoutes + results.finalOrders + results.leagues + results.blockers
		local blocking = SC_GetSafeNumber(function() return player:GetEndTurnBlockingType() end, -999)
		SC_Debug("sweep end index="..tostring(sweep)..
			" city="..tostring(results.cityOrders)..
			" capital="..tostring(results.capitalActions)..
			" ideology="..tostring(results.ideologies)..
			" research="..tostring(results.research)..
			" policy="..tostring(results.policies)..
			" promote="..tostring(results.promotions)..
			" greatPeople="..tostring(results.greatPeople)..
			" purchases="..tostring(results.purchases)..
			" captureFinish="..tostring(results.captureFinishers)..
			" tactical="..tostring(results.defenseActions)..
			" cityStrike="..tostring(results.cityStrikes)..
			" transportEscort="..tostring(results.transportEscort)..
			" strategicMove="..tostring(results.strategicMoves)..
			" stacked="..tostring(results.stackedMoves)..
			" finalOrders="..tostring(results.finalOrders)..
			" leagues="..tostring(results.leagues)..
			" blockers="..tostring(results.blockers)..
			" moduleErrors="..tostring(results.moduleErrors)..
			" blockerNow="..SC_GetEnumName(EndTurnBlockingTypes, blocking))
		if after == before and (EndTurnBlockingTypes == nil or blocking == EndTurnBlockingTypes.NO_ENDTURN_BLOCKING_TYPE) then
			break
		end
	end
	results.popups = SC_LAST_POPUPS_HANDLED
	results.diplo = SC_LAST_DIPLO_HANDLED
	SC_LAST_POPUPS_HANDLED = 0
	SC_LAST_DIPLO_HANDLED = 0
	return results, cityDetails
end

local function SC_SendNationalBrief(player, results, cityDetails, atWar)
	if player == nil or not SC_GetConfig("NationalBrief", true) then
		return
	end
	local interval = math.max(SC_GetConfig("InterventionInterval", 5), 1)
	local turn = Game.GetGameTurn()
	if turn % interval ~= 0 then
		return
	end
	results = results or {}
	cityDetails = cityDetails or {}
	local lines = {}
	table.insert(lines, "战略指挥部简报")
	table.insert(lines, "回合: "..tostring(turn))
	table.insert(lines, "城市安排: "..tostring(results.cityOrders or 0))
	table.insert(lines, "科研选择: "..tostring(results.research or 0))
	table.insert(lines, "政策选择: "..tostring(results.policies or 0))
	table.insert(lines, "单位升级: "..tostring(results.upgrades or 0))
	table.insert(lines, "单位晋升: "..tostring(results.promotions or 0))
	table.insert(lines, "伟人使用: "..tostring(results.greatPeople or 0))
	table.insert(lines, "金币购军: "..tostring(results.purchases or 0))
	table.insert(lines, "治疗命令: "..tostring(results.heals or 0))
	table.insert(lines, "收城动作: "..tostring(results.captureFinishers or 0))
	table.insert(lines, "单位远程攻击: "..tostring(results.defenseActions or 0))
	table.insert(lines, "城市炮击: "..tostring(results.cityStrikes or 0))
	table.insert(lines, "运输护航: "..tostring(results.transportEscort or 0))
	table.insert(lines, "战略机动: "..tostring(results.strategicMoves or 0))
	table.insert(lines, "贸易路线: "..tostring(results.tradeRoutes or 0))
	table.insert(lines, "世界议会: "..tostring(results.leagues or 0))
	table.insert(lines, "待命姿态: "..tostring(results.idlePosture or 0))
	table.insert(lines, "残留单位处理: "..tostring(results.finalOrders or 0))
	table.insert(lines, "弹窗处理: "..tostring(results.popups or 0))
	table.insert(lines, "外交打断处理: "..tostring(results.diplo or 0))
	table.insert(lines, "可行动作战单位: "..tostring(SC_CountIdleCombatUnits(player)))
	table.insert(lines, "快乐: "..tostring(SC_GetSafeNumber(function() return player:GetExcessHappiness() end, 0)))
	table.insert(lines, "国库: "..tostring(SC_GetSafeNumber(function() return player:GetGold() end, 0)))
	if atWar then
		table.insert(lines, "战争状态: 正在与 "..table.concat(SC_GetWarSummary(player), ", ").." 交战")
	else
		table.insert(lines, "战争状态: 和平")
	end
	if #cityDetails > 0 then
		table.insert(lines, "最近城市安排:")
		for i = 1, math.min(#cityDetails, 6), 1 do
			table.insert(lines, cityDetails[i])
		end
	end
	SC_SendNotification(player, "战略指挥部", table.concat(lines, "[NEWLINE]"))
end

local function SC_SendNationalBriefNow(player, results, cityDetails, atWar)
	if player == nil then
		return
	end
	local oldBrief = SC_GetConfig("NationalBrief", true)
	local oldInterval = SC_GetConfig("InterventionInterval", 5)
	SC_CONFIG.NationalBrief = true
	SC_CONFIG.InterventionInterval = 1
	SC_SendNationalBrief(player, results or {}, cityDetails or {}, atWar)
	SC_CONFIG.InterventionInterval = oldInterval
	SC_CONFIG.NationalBrief = oldBrief
end

local SC_PROFILE_OPTIONS = {
	DiplomacyProfile = {
		{ Key = "BALANCED", Text = "均衡" },
		{ Key = "FRIENDLY", Text = "友好" },
		{ Key = "HARDLINE", Text = "强硬" },
		{ Key = "ISOLATION", Text = "孤立" },
	},
	EconomyProfile = {
		{ Key = "BALANCED", Text = "均衡" },
		{ Key = "SCIENCE", Text = "科研" },
		{ Key = "TREASURY", Text = "财政" },
		{ Key = "EXPANSION", Text = "扩张" },
	},
	BuildProfile = {
		{ Key = "INFRASTRUCTURE", Text = "基建" },
		{ Key = "HAPPINESS", Text = "幸福" },
		{ Key = "SCIENCE", Text = "科研" },
		{ Key = "DEFENSE", Text = "防御" },
	},
	DevelopmentProfile = {
		{ Key = "AUTO", Text = "自动" },
		{ Key = "PRODUCTION", Text = "产能" },
		{ Key = "RAIL", Text = "铁路" },
		{ Key = "SAFE", Text = "保守" },
	},
	ProductionProfile = {
		{ Key = "BUILDINGS", Text = "建筑" },
		{ Key = "MILITARY", Text = "军队" },
		{ Key = "AIRSEA", Text = "海空" },
		{ Key = "WONDERS", Text = "奇观" },
	},
	WarProfile = {
		{ Key = "DEFENSE", Text = "防守" },
		{ Key = "ADVANCE", Text = "推进" },
		{ Key = "ASSAULT", Text = "总攻" },
		{ Key = "NAVAL", Text = "海权" },
	},
	CapturedCityAction = {
		{ Key = "PUPPET", Text = "傀儡" },
		{ Key = "SMART", Text = "智能" },
		{ Key = "ANNEX", Text = "吞并" },
		{ Key = "RAZE", Text = "焚城" },
	},
	GreatPersonProfile = {
		{ Key = "AUTO", Text = "自动" },
		{ Key = "SCIENCE", Text = "科研" },
		{ Key = "ENGINEER", Text = "工程" },
		{ Key = "CULTURE", Text = "文化" },
		{ Key = "SLEEP", Text = "保留" },
	},
	ReligionProfile = {
		{ Key = "PRODUCTION", Text = "产能" },
		{ Key = "SCIENCE", Text = "科研" },
		{ Key = "GOLD", Text = "金币" },
		{ Key = "CULTURE", Text = "文化" },
	},
	TradeProfile = {
		{ Key = "BALANCED", Text = "均衡" },
		{ Key = "GOLD", Text = "金币" },
		{ Key = "SCIENCE", Text = "科研" },
		{ Key = "INTERNAL", Text = "内运" },
	},
	EspionageProfile = {
		{ Key = "DEFENSE", Text = "反谍" },
		{ Key = "TECH", Text = "窃技" },
		{ Key = "CITYSTATE", Text = "城邦" },
		{ Key = "DIPLO", Text = "外交" },
	},
}

local SC_PROFILE_LABELS = {
	DiplomacyProfile = "外交",
	EconomyProfile = "经济",
	BuildProfile = "建设",
	DevelopmentProfile = "开发",
	ProductionProfile = "生产",
	WarProfile = "战争",
	CapturedCityAction = "占城",
	GreatPersonProfile = "伟人",
	ReligionProfile = "宗教",
	TradeProfile = "贸易",
	EspionageProfile = "间谍",
}

local function SC_IsTakeoverActive()
	return SC_GetSafeNumber(function() return SC_CONFIG.TakeoverTurnsRemaining end, 0) > 0
end

local function SC_GetProfileText(profileKey)
	local options = SC_PROFILE_OPTIONS[profileKey]
	local value = SC_GetConfig(profileKey, nil)
	if options ~= nil then
		for _, option in ipairs(options) do
			if option.Key == value then
				return option.Text
			end
		end
		return options[1].Text
	end
	return tostring(value or "")
end

local function SC_CycleProfile(profileKey)
	local options = SC_PROFILE_OPTIONS[profileKey]
	if options == nil or #options == 0 then
		return
	end
	local current = SC_GetConfig(profileKey, options[1].Key)
	local nextIndex = 1
	for i, option in ipairs(options) do
		if option.Key == current then
			nextIndex = i + 1
			break
		end
	end
	if nextIndex > #options then
		nextIndex = 1
	end
	SC_CONFIG[profileKey] = options[nextIndex].Key
end

local function SC_SelectProfile(profileKey)
	if SC_PROFILE_OPTIONS[profileKey] == nil then
		return
	end
	SC_CONFIG.SelectedProfileKey = profileKey
end

local SC_ApplyStrategicProfiles

local function SC_SetProfileOption(profileKey, optionIndex)
	local options = SC_PROFILE_OPTIONS[profileKey]
	if options == nil or options[optionIndex] == nil then
		return
	end
	SC_CONFIG[profileKey] = options[optionIndex].Key
	SC_ApplyStrategicProfiles()
	SC_SaveTakeoverState()
end

local function SC_GetProfileButtonText(profileKey)
	local label = SC_PROFILE_LABELS[profileKey] or profileKey
	local prefix = ""
	if SC_GetConfig("SelectedProfileKey", "DiplomacyProfile") == profileKey then
		prefix = "> "
	end
	return prefix..label.."："..SC_GetProfileText(profileKey)
end

function SC_ApplyStrategicProfiles()
	local economy = SC_GetConfig("EconomyProfile", "BALANCED")
	local build = SC_GetConfig("BuildProfile", "INFRASTRUCTURE")
	local production = SC_GetConfig("ProductionProfile", "BUILDINGS")
	local war = SC_GetConfig("WarProfile", "ADVANCE")
	
	if economy == "SCIENCE" or build == "SCIENCE" then
		SC_CONFIG.Doctrine = "SCIENCE"
	elseif production == "MILITARY" or production == "AIRSEA" or war == "ASSAULT" or war == "NAVAL" then
		SC_CONFIG.Doctrine = "WAR"
	elseif build == "INFRASTRUCTURE" or economy == "EXPANSION" then
		SC_CONFIG.Doctrine = "INDUSTRY"
	else
		SC_CONFIG.Doctrine = "BALANCED"
	end
	
	SC_CONFIG.AutoResearch = true
	SC_CONFIG.AutoPolicy = true
	SC_CONFIG.AutoCityProduction = true
	SC_CONFIG.AutoLocalDefense = true
	SC_CONFIG.AutoCityRangedStrike = true
	SC_CONFIG.AutoUpgradeUnits = true
	SC_CONFIG.AutoPromoteUnits = true
	SC_CONFIG.AutoHealDamagedUnits = true
	SC_CONFIG.AutoStrategicMove = true
	SC_CONFIG.AutoIdlePosture = true
	SC_CONFIG.AutoPopupHandling = true
	SC_CONFIG.AutoReligion = true
	SC_CONFIG.AutoArchaeology = true
	SC_CONFIG.AutoTradeRoutes = true
	SC_CONFIG.AutoEspionage = true
	SC_CONFIG.AutoCityCaptureFinishers = true
	SC_CONFIG.AutoTransportEscort = true
	SC_CONFIG.DirectPushMissionFallback = true
	SC_CONFIG.DirectPushTargetedMissionFallback = true
	SC_CONFIG.DirectPushMoveMissionFallback = true
	SC_CONFIG.AvoidObsoleteFallbackUnits = true
	SC_CONFIG.MaxFallbackUnitEraGap = 2
	SC_CONFIG.MinLateGameFallbackCombatPower = 45
	SC_CONFIG.RepeatedUnitReservationPenalty = 220
	SC_CONFIG.MaxAutoEndTurnSendsPerTurn = 6
	SC_CONFIG.MaxStackEscapeAttemptsPerUnitPerTurn = 8
	SC_CONFIG.MaxStackEscapeCandidatesPerUnit = 10
	SC_CONFIG.MaxUnitTacticalStrikeRounds = 3
	SC_CONFIG.MaxTacticalActionsPerUnitPerTurn = 2
	SC_CONFIG.MaxAirTacticalActionsPerUnitPerTurn = 5
	SC_CONFIG.MaxMissileTacticalActionsPerUnitPerTurn = 2
	SC_CONFIG.MaxNavalTacticalActionsPerUnitPerTurn = 4
	SC_CONFIG.MaxLandRangedTacticalActionsPerUnitPerTurn = 3
	SC_CONFIG.MaxAutoPromotionsPerUnitPerTurn = 20
	SC_CONFIG.PromotionActionFallbackWhenNotReady = false
	SC_CONFIG.PromotionActionScanAllCombatUnits = false
	SC_CONFIG.PromotionActionAllowAnyFallback = true
	SC_CONFIG.PromotionActionFallbackAnyAfterCandidateFail = false
	SC_CONFIG.DirectPromotionGrantFallback = true
	SC_CONFIG.DebugPromotionCannotHandleDetails = false
	SC_CONFIG.DebugCityProduction = true
	SC_CONFIG.GreatPersonActionFallbackWhenBlocked = true
	SC_CONFIG.MaxFinalUnitOrderRounds = 6
	SC_CONFIG.MaxFinalOrderAttemptsPerUnitPerTurn = 5
	SC_CONFIG.MaxTakeoverInnerSweeps = 2
	SC_CONFIG.MaxLightweightInnerSweeps = 1
	SC_CONFIG.MaxFinalUnitOrdersPerTurn = 240
	SC_CONFIG.MaxTakeoverPassesPerTurn = 6
	SC_CONFIG.MaxFullAutomationPassesPerTurn = 1
	SC_CONFIG.ForceClearStuckUnitOrders = true
	SC_CONFIG.StackEscapeSearchRadius = 8
	SC_CONFIG.CityCaptureDirectMaxDistance = 2
	SC_CONFIG.CaptureReadyAdjacentFirePenalty = 4200
	SC_CONFIG.ProtectedAssetThreatRadius = 6
	SC_CONFIG.CarrierStandoffMinDistance = 6
	SC_CONFIG.CarrierStandoffMaxDistance = 10
	SC_CONFIG.ArsenalShipStandoffMinDistance = 5
	SC_CONFIG.ArsenalShipStandoffMaxDistance = 8
	SC_CONFIG.MissileScreenStandoffMinDistance = 1
	SC_CONFIG.MissileScreenStandoffMaxDistance = 3
	SC_CONFIG.SubmarineStandoffMinDistance = 2
	SC_CONFIG.SubmarineStandoffMaxDistance = 4
	SC_CONFIG.FleetStandoffThreatRadius = 4
	if SC_CONFIG.AutoEndTurn == nil then
		SC_CONFIG.AutoEndTurn = true
	end
	SC_CONFIG.PostEndTurnQuietMode = true
	
	SC_CONFIG.TargetCityQueueLength = 2
	if SC_GetConfig("DiplomacyProfile", "BALANCED") == "ISOLATION" then
		SC_CONFIG.AutoPopupHandling = true
	end
	if war == "ASSAULT" then
		SC_CONFIG.HealDamageThreshold = 65
		SC_CONFIG.MaxStrategicMovesPerTurn = 160
		SC_CONFIG.MaxUnitTacticalStrikesPerTurn = 100
		SC_CONFIG.MaxAirTacticalActionsPerUnitPerTurn = 6
		SC_CONFIG.MaxNavalTacticalActionsPerUnitPerTurn = 4
	elseif war == "DEFENSE" then
		SC_CONFIG.HealDamageThreshold = 35
		SC_CONFIG.MaxStrategicMovesPerTurn = 40
		SC_CONFIG.MaxUnitTacticalStrikesPerTurn = 80
		SC_CONFIG.MaxAirTacticalActionsPerUnitPerTurn = 4
		SC_CONFIG.MaxNavalTacticalActionsPerUnitPerTurn = 3
	elseif war == "NAVAL" then
		SC_CONFIG.HealDamageThreshold = 45
		SC_CONFIG.MaxStrategicMovesPerTurn = 160
		SC_CONFIG.MaxUnitTacticalStrikesPerTurn = 110
		SC_CONFIG.MaxAirTacticalActionsPerUnitPerTurn = 6
		SC_CONFIG.MaxNavalTacticalActionsPerUnitPerTurn = 5
	else
		SC_CONFIG.HealDamageThreshold = 45
		SC_CONFIG.MaxStrategicMovesPerTurn = 140
		SC_CONFIG.MaxUnitTacticalStrikesPerTurn = 100
		SC_CONFIG.MaxAirTacticalActionsPerUnitPerTurn = 5
		SC_CONFIG.MaxNavalTacticalActionsPerUnitPerTurn = 4
	end
end

local function SC_ResetTakeoverPassCounterForTurn()
	local turn = SC_GetSafeNumber(function() return Game.GetGameTurn() end, -1)
	if SC_LAST_TAKEOVER_PASS_TURN ~= turn then
		SC_LAST_TAKEOVER_PASS_TURN = turn
		SC_LAST_TAKEOVER_PASS_COUNT = 0
		SC_FULL_AUTOMATION_PASS_COUNT = 0
		SC_STRATEGIC_ORDERED_THIS_TURN = {}
		SC_TACTICAL_ORDERED_THIS_TURN = {}
		SC_TACTICAL_NO_TARGET_THIS_TURN = {}
		SC_TACTICAL_QUEUED_THIS_TURN = {}
		SC_ASSAULT_SUPPORT_CACHE_THIS_TURN = {}
		SC_PROTECTED_ASSET_CACHE_THIS_TURN = {}
		SC_OPERATION_TARGET_CACHE_THIS_TURN = {}
		SC_ENEMY_TARGET_POOL_THIS_TURN = {}
		SC_OPERATION_FOCUS_THIS_TURN = {}
		SC_OPERATION_FOCUS_LOGGED_THIS_TURN = {}
		SC_STRATEGIC_TARGET_COMMITMENTS_THIS_TURN = {}
		SC_STRATEGIC_UNIT_TARGET_THIS_TURN = {}
		SC_CITY_CAPTURE_TASKS_THIS_TURN = {}
		SC_CITY_CAPTURE_ASSIGNMENTS_THIS_TURN = {}
		SC_CITY_CAPTURE_TASK_LOGGED_THIS_TURN = {}
		SC_DECAPITATION_FOCUS_THIS_TURN = {}
		SC_RETREAT_THREAT_CACHE_THIS_TURN = {}
		SC_SEA_THREAT_CACHE_THIS_TURN = {}
		SC_MILITARY_ROSTER_CACHE_THIS_TURN = {}
		SC_AIR_SUPERIORITY_BUDGET_THIS_TURN = {}
		SC_AIR_REBASED_THIS_TURN = {}
		SC_AIR_REBASE_DESTINATION_COUNT_THIS_TURN = {}
		SC_AIR_REBASE_NO_DEST_THIS_TURN = {}
		SC_RANGE_TARGET_STRIKE_COUNT_THIS_TURN = {}
		SC_STACK_MOVE_ATTEMPTED_THIS_TURN = {}
		SC_FINAL_ORDER_ATTEMPTED_THIS_TURN = {}
		SC_TRANSPORT_ESCORT_ORDERED_THIS_TURN = {}
		SC_TRANSPORT_ESCORT_FAILED_THIS_TURN = {}
		SC_TRANSPORT_RELEASE_LOGGED_THIS_TURN = {}
		SC_DIRECT_PUSH_FAILED_THIS_TURN = {}
		SC_EXECUTION_REJECTED_MOVE_PLOTS_THIS_TURN = {}
		SC_HEAL_FAILED_THIS_TURN = {}
		SC_HEAL_HANDLED_THIS_TURN = {}
		SC_RANGE_FAILED_THIS_TURN = {}
		SC_POPUP_LOGGED_THIS_TURN = {}
		SC_PROMOTION_SCAN_ATTEMPTED_THIS_TURN = {}
		SC_PROMOTION_FAILED_THIS_TURN = {}
		SC_PROMOTION_HANDLED_THIS_TURN = {}
		SC_PROMOTION_DIRECT_GRANTED_THIS_TURN = {}
		SC_PROMOTION_ACTION_LOGGED_THIS_TURN = {}
		SC_GREAT_PERSON_ACTION_ATTEMPTED_THIS_TURN = {}
		SC_GREAT_PERSON_POSITIONED_THIS_TURN = {}
		SC_GREAT_PERSON_TARGET_RESERVED_THIS_TURN = {}
		SC_MILITARY_PURCHASE_FAILED_THIS_TURN = {}
		SC_USER_INPUT_LOG_COUNT_THIS_TURN = 0
		SC_DEMO_LOG_COUNT_THIS_TURN = 0
		SC_RECENT_PLAYER_INPUT_EVENTS = 0
		SC_POLICY_FAILED_THIS_TURN = {}
		SC_POLICY_PENDING_THIS_TURN = false
		SC_AUTO_END_SEND_COUNT_THIS_TURN = 0
		SC_AUTO_END_STALL_LOGGED_THIS_TURN = false
		SC_AUTO_END_POST_SEND_LOGGED_THIS_TURN = false
	end
end

function SC_GetTurnBlockReason(player)
	if player == nil then
		return "nil-player"
	end
	local blocking = SC_GetSafeNumber(function() return player:GetEndTurnBlockingType() end, -999)
	if EndTurnBlockingTypes ~= nil and blocking ~= EndTurnBlockingTypes.NO_ENDTURN_BLOCKING_TYPE then
		return SC_GetEnumName(EndTurnBlockingTypes, blocking)
	end
	if Game ~= nil and Game.IsProcessingMessages ~= nil then
		local ok, processing = pcall(function() return Game.IsProcessingMessages() end)
		if ok and processing then
			return "Game.IsProcessingMessages=true"
		end
	end
	if UI ~= nil and UI.CanEndTurn ~= nil then
		local ok, canEnd = pcall(function() return UI.CanEndTurn() end)
		if ok and not canEnd then
			return "UI.CanEndTurn=false"
		end
	end
	return "clear"
end

local function SC_IsTurnUnblocked(player)
	if SC_GetTurnBlockReason(player) ~= "clear" then
		return false
	end
	return true
end

local function SC_ShouldStayQuietAfterEndSent(player, reason)
	if reason == "clear" or reason == "Game.IsProcessingMessages=true" then
		return true
	end
	if reason == "UI.CanEndTurn=false" then
		local blocking = SC_GetSafeNumber(function() return player:GetEndTurnBlockingType() end, -999)
		return EndTurnBlockingTypes ~= nil and blocking == EndTurnBlockingTypes.NO_ENDTURN_BLOCKING_TYPE
	end
	return false
end

local function SC_TryAutoEndTurn(player, allowRepeatAfterHandledBlocker)
	if SCV3 and SCV3.criticalFault then return false end
	if player == nil or not SC_IsTakeoverActive() or not SC_GetConfig("AutoEndTurn", true) then
		SC_Debug("autoEndTurn skip active="..SC_BoolText(SC_IsTakeoverActive()).." enabled="..SC_BoolText(SC_GetConfig("AutoEndTurn", true)))
		return false
	end
	local active = false
	pcall(function() active = player:IsTurnActive() end)
	if not active then
		SC_Debug("autoEndTurn skip reason=not-active-turn")
		return false
	end
	local turn = SC_GetSafeNumber(function() return Game.GetGameTurn() end, -1)
	if SC_GetConfig("PostEndTurnQuietMode", true) and SC_LAST_AUTO_END_TURN == turn and SC_AUTO_END_SEND_COUNT_THIS_TURN > 0 and allowRepeatAfterHandledBlocker ~= true then
		local quietReason = SC_GetTurnBlockReason(player)
		if SC_ShouldStayQuietAfterEndSent(player, quietReason) then
			if not SC_AUTO_END_POST_SEND_LOGGED_THIS_TURN then
				SC_AUTO_END_POST_SEND_LOGGED_THIS_TURN = true
				SC_Debug("autoEndTurn skip reason=post-send-quiet turn="..tostring(turn).." sends="..tostring(SC_AUTO_END_SEND_COUNT_THIS_TURN).." waitReason="..tostring(quietReason).." blocker="..SC_GetBlockingDebug(player))
			end
			return false
		end
		SC_AUTO_END_POST_SEND_LOGGED_THIS_TURN = false
		SC_Debug("autoEndTurn resume-after-end-sent reason="..tostring(quietReason).." sends="..tostring(SC_AUTO_END_SEND_COUNT_THIS_TURN).." blocker="..SC_GetBlockingDebug(player))
	elseif SC_LAST_AUTO_END_TURN == turn and SC_AUTO_END_SEND_COUNT_THIS_TURN > 0 and allowRepeatAfterHandledBlocker == true then
		SC_AUTO_END_POST_SEND_LOGGED_THIS_TURN = false
		SC_Debug("autoEndTurn repeat-after-handled-blocker sends="..tostring(SC_AUTO_END_SEND_COUNT_THIS_TURN).." blocker="..SC_GetBlockingDebug(player))
	end
	local maxSends = SC_GetConfig("MaxAutoEndTurnSendsPerTurn", 6)
	if SC_LAST_AUTO_END_TURN == turn and SC_AUTO_END_SEND_COUNT_THIS_TURN >= maxSends then
		SC_Debug("autoEndTurn skip reason=max-sends turn="..tostring(turn).." sends="..tostring(SC_AUTO_END_SEND_COUNT_THIS_TURN).." max="..tostring(maxSends))
		return false
	end
	local blockReason = SC_GetTurnBlockReason(player)
	if blockReason ~= "clear" then
		local atWar = SC_PlayerAtWar(player)
		local handled = SC_HandleEndTurnBlocker(player, atWar, false)
		if blockReason == "UI.CanEndTurn=false" then
			handled = handled + SC_AutomateStackedUnits(player)
			handled = handled + SC_AutomateFinalUnitOrders(player, atWar)
		end
		local retryReason = SC_GetTurnBlockReason(player)
		if retryReason ~= "clear" then
			local retryBlocking = SC_GetSafeNumber(function() return player:GetEndTurnBlockingType() end, -999)
			if retryReason == "UI.CanEndTurn=false" and EndTurnBlockingTypes ~= nil and retryBlocking == EndTurnBlockingTypes.NO_ENDTURN_BLOCKING_TYPE and SC_GetConfig("ForceEndTurnWhenBlockerClear", true) then
				SC_Debug("autoEndTurn force-clear-ui blocker="..SC_GetBlockingDebug(player).." preReason="..tostring(blockReason).." preHandled="..tostring(handled))
			else
			SC_Debug("autoEndTurn blocked reason="..retryReason.." blocker="..SC_GetBlockingDebug(player).." preReason="..tostring(blockReason).." preHandled="..tostring(handled))
			return false
			end
		end
	end
	if not SC_IsTurnUnblocked(player) then
		local finalReason = SC_GetTurnBlockReason(player)
		local finalBlocking = SC_GetSafeNumber(function() return player:GetEndTurnBlockingType() end, -999)
		if not (finalReason == "UI.CanEndTurn=false" and EndTurnBlockingTypes ~= nil and finalBlocking == EndTurnBlockingTypes.NO_ENDTURN_BLOCKING_TYPE and SC_GetConfig("ForceEndTurnWhenBlockerClear", true)) then
			SC_Debug("autoEndTurn blocked reason="..finalReason.." blocker="..SC_GetBlockingDebug(player))
			return false
		end
		SC_Debug("autoEndTurn force-clear-ui finalReason="..tostring(finalReason).." blocker="..SC_GetBlockingDebug(player))
	end
	local control = GameInfoTypes.CONTROL_ENDTURN
	if control == nil then
		SC_Debug("autoEndTurn skip reason=no-control-id")
		return false
	end
	local ok = pcall(function()
		Game.DoControl(control)
	end)
	if ok then
		if SC_LAST_AUTO_END_TURN ~= turn then
			SC_AUTO_END_SEND_COUNT_THIS_TURN = 0
		end
		SC_LAST_AUTO_END_TURN = turn
		SC_AUTO_END_SEND_COUNT_THIS_TURN = SC_AUTO_END_SEND_COUNT_THIS_TURN + 1
		SC_Debug("autoEndTurn sent turn="..tostring(turn).." sends="..tostring(SC_AUTO_END_SEND_COUNT_THIS_TURN))
		return true
	end
	SC_Debug("autoEndTurn failed turn="..tostring(turn))
	return false
end

local function SC_OnAutomationUpdate(deltaSeconds)
	if not SC_GetConfig("AutoEndTurnRetry", true) or not SC_IsTakeoverActive() then
		return
	end
	SC_AUTO_RETRY_ACCUMULATOR = SC_AUTO_RETRY_ACCUMULATOR + (deltaSeconds or 0)
	local interval = SC_GetConfig("AutoEndTurnRetryInterval", 0.75)
	if SC_AUTO_RETRY_ACCUMULATOR < interval then
		return
	end
	SC_AUTO_RETRY_ACCUMULATOR = 0
	if SC_AUTO_RETRY_RUNNING then
		return
	end
	SC_AUTO_RETRY_RUNNING = true
	local ok, err = pcall(function()
		if SC_DIPLO_CLOSE_PENDING_TICKS > 0 and SC_TryCloseDiplomacy ~= nil then
			SC_DIPLO_CLOSE_PENDING_TICKS = SC_DIPLO_CLOSE_PENDING_TICKS - 1
			SC_TryCloseDiplomacy("retry:"..tostring(SC_DIPLO_CLOSE_PENDING_TICKS))
		end
		local player = SC_GetActiveHuman()
		if player == nil or not player:IsTurnActive() then
			return
		end
		local turn = SC_GetSafeNumber(function() return Game.GetGameTurn() end, -1)
		local postSendReason = nil
		if SC_GetConfig("PostEndTurnQuietMode", true) and SC_LAST_AUTO_END_TURN == turn and SC_AUTO_END_SEND_COUNT_THIS_TURN > 0 then
			postSendReason = SC_GetTurnBlockReason(player)
			if SC_ShouldStayQuietAfterEndSent(player, postSendReason) then
				if not SC_AUTO_END_POST_SEND_LOGGED_THIS_TURN then
					SC_AUTO_END_POST_SEND_LOGGED_THIS_TURN = true
					SC_Debug("autoRetry wait-after-end-sent reason=post-send-quiet waitReason="..tostring(postSendReason).." sends="..tostring(SC_AUTO_END_SEND_COUNT_THIS_TURN).." blocker="..SC_GetBlockingDebug(player))
				end
				return
			end
			SC_AUTO_END_POST_SEND_LOGGED_THIS_TURN = false
			SC_Debug("autoRetry resume-after-end-sent reason="..tostring(postSendReason).." sends="..tostring(SC_AUTO_END_SEND_COUNT_THIS_TURN).." blocker="..SC_GetBlockingDebug(player))
		end
		if SC_LAST_AUTO_END_TURN == turn then
			postSendReason = postSendReason or SC_GetTurnBlockReason(player)
			if postSendReason == "clear" or postSendReason == "Game.IsProcessingMessages=true" then
				return
			end
			local postBlocking = SC_GetSafeNumber(function() return player:GetEndTurnBlockingType() end, -999)
			local maxSends = SC_GetConfig("MaxAutoEndTurnSendsPerTurn", 6)
			if postSendReason == "UI.CanEndTurn=false" and EndTurnBlockingTypes ~= nil and postBlocking == EndTurnBlockingTypes.NO_ENDTURN_BLOCKING_TYPE and SC_AUTO_END_SEND_COUNT_THIS_TURN >= maxSends then
				if not SC_AUTO_END_STALL_LOGGED_THIS_TURN then
					SC_AUTO_END_STALL_LOGGED_THIS_TURN = true
					SC_Debug("autoRetry wait-after-max-sends reason="..tostring(postSendReason).." sends="..tostring(SC_AUTO_END_SEND_COUNT_THIS_TURN).." blocker="..SC_GetBlockingDebug(player))
				end
				return
			end
			SC_Debug("autoRetry after-sent reason="..tostring(postSendReason).." sends="..tostring(SC_AUTO_END_SEND_COUNT_THIS_TURN).." blocker="..SC_GetBlockingDebug(player))
		end
		if Game ~= nil and Game.IsProcessingMessages ~= nil then
			local processing = false
			pcall(function() processing = Game.IsProcessingMessages() end)
			if processing then
				return
			end
		end
		if SC_ProcessNotificationQueue ~= nil then
			SC_ProcessNotificationQueue(player, "autoRetry")
		end
		local reason = SC_GetTurnBlockReason(player)
		local handled = 0
		if reason ~= "clear" then
			local atWar = SC_PlayerAtWar(player)
			handled = SC_HandleEndTurnBlocker(player, atWar, false)
			SC_Debug("autoRetry blocker reason="..tostring(reason).." handled="..tostring(handled).." blocker="..SC_GetBlockingDebug(player))
		end
		SC_TryAutoEndTurn(player, handled > 0)
	end)
	SC_AUTO_RETRY_RUNNING = false
	if not ok then
		SC_Debug("autoRetry error="..tostring(err))
	end
end

-- Late dispatchers repair the lightweight sweep's forward-scope boundary.
function SC_LightAutomateIdeology(player) return SC_AutomateIdeology(player) end
function SC_LightAutomatePolicy(player) return SC_AutomatePolicy(player) end
function SC_LightAutomateFinalUnitOrders(player, atWar) return SC_AutomateFinalUnitOrders(player, atWar) end
function SC_LightAutomateLeagues(player) return SC_AutomateLeagues(player) end
function SC_LightHandleEndTurnBlocker(player, atWar) return SC_HandleEndTurnBlocker(player, atWar) end

if ContextPtr ~= nil and ContextPtr.SetUpdate ~= nil then
	ContextPtr:SetUpdate(SC_OnAutomationUpdate)
end

include("StrategicCommand_Decisions.lua")
include("StrategicCommand_CombatModel.lua")
include("StrategicCommand_Development.lua")
include("StrategicCommand_Strategy.lua")
include("StrategicCommand_ExecutionWorld.lua")
include("StrategicCommand_V3_State.lua")
include("StrategicCommand_V3_City.lua")
include("StrategicCommand_V3_Blockers.lua")
include("StrategicCommand_V3_SpecialWeapons.lua")
include("StrategicCommand_V3_Military.lua")
include("StrategicCommand_ExecutionMilitary.lua")
include("StrategicCommand_V3_Engine.lua")

function SC_V3RefreshTacticalWorld(player, reason)
	local playerID = player ~= nil and SC_GetSafeNumber(function() return player:GetID() end, -1) or -1
	if playerID >= 0 then
		SC_ENEMY_TARGET_POOL_THIS_TURN[playerID] = nil
	else
		SC_ENEMY_TARGET_POOL_THIS_TURN = {}
	end
	SC_ASSAULT_SUPPORT_CACHE_THIS_TURN = {}
	SC_PROTECTED_ASSET_CACHE_THIS_TURN = {}
	SC_RETREAT_THREAT_CACHE_THIS_TURN = {}
	SC_SEA_THREAT_CACHE_THIS_TURN = {}
	SC_MILITARY_ROSTER_CACHE_THIS_TURN = {}
	SC_CITY_CAPTURE_TASKS_THIS_TURN = {}
	-- Fire-only refreshes preserve no-target results for units that stayed put. A
	-- completed movement wave may reveal or bring enemies into range, so invalidate
	-- once per wave rather than after every individual action.
	if string.find(tostring(reason or ""), "execution-after-move-", 1, true) == 1 then
		SC_TACTICAL_NO_TARGET_THIS_TURN = {}
	end
	if SCX_InvalidateExecutionWorld ~= nil then SCX_InvalidateExecutionWorld(reason) end
	SC_Debug("V3 tacticalRefresh reason="..tostring(reason or "unspecified").." player=P"..tostring(playerID))
end

function SC_GetV3Adapters()
	return {
		log = SC_Debug,
		haltTakeover = function(reason)
			SC_CONFIG.TakeoverTurnsRemaining = 0
			SC_SaveTakeoverState()
			local p = SC_GetActiveHuman()
			if p then SC_SendNotification(p, "托管已暂停", "军事决策发生异常，已保留本回合控制权。请检查日志后再继续。") end
			SC_Debug("takeover safety-stop reason="..tostring(reason))
		end,
		runCount = SC_RunCountModule,
		getTurn = function() return SC_GetSafeNumber(function() return Game.GetGameTurn() end, -1) end,
		getBlockerName = function(player)
			if player == nil or EndTurnBlockingTypes == nil then return "clear" end
			local blocking = SC_GetSafeNumber(function() return player:GetEndTurnBlockingType() end, -999)
			return SC_GetEnumName(EndTurnBlockingTypes, blocking)
		end,
		automateCities = SC_AutomateCities,
		capital = SC_AutomateCapitalDeployment,
		purchases = SC_AutomateMilitaryPurchases,
		ideology = SC_AutomateIdeology,
		research = SC_AutomateResearch,
		policy = SC_AutomatePolicy,
		upgrades = SC_AutomateUnitUpgrades,
		promotions = SC_AutomateUnitPromotions,
		greatPeople = SC_AutomateGreatPeople,
		healing = SC_AutomateDamagedUnitHealing,
		survival = function(p, war) return SC5 and SC5.RunSurvival(p, war, SC_GetV3Adapters()) or 0 end,
		survivalMove = function(unit, plot) return SC_TryMoveMission(unit, plot, "survival-withdraw", true) end,
		reserveWithdrawal = function(unit)
			local key = SC_GetUnitTurnKey(unit)
			if key then SC_HEAL_HANDLED_THIS_TURN[key] = true end
			SC_MarkStrategicUnitDone(unit)
		end,
		transportEscort = SC_AutomateTransportEscort,
		airRebase = SC_AutomateAirRebase,
		getConfig = SC_GetConfig,
		plotDistance = function(a, b)
			if a == nil or b == nil then return 999 end
			return Map.PlotDistance(a:GetX(), a:GetY(), b:GetX(), b:GetY())
		end,
		countEnemyCombatPresenceNearPlot = SC_CountEnemyCombatPresenceNearPlot,
		markStrategicUnitDone = SC_MarkStrategicUnitDone,
		getUnitInfo = SC_GetUnitInfo,
		getUnitRole = SC_GetUnitRole,
		getUnitCapabilityProfile = SC_GetUnitCapabilityProfile,
		getUnitDebugLabel = SC_GetUnitDebugLabel,
		getUnitTurnKey = SC_GetUnitTurnKey,
		getEnemyTargetPool = SC_GetEnemyTargetPool,
		getExecutionTargetPool = SCX_GetExecutionTargetPool,
		isEnemyUnitValid = SC_IsEnemyTargetUnitValid,
		isCombatTargetAuthorized = SC_IsCombatTargetAuthorized,
		isPotentialRangeStrikeAt = SC_IsPotentialRangeStrikeAt,
		rangeStrike = SC_RangeStrike,
		recordTacticalAction = SC_RecordTacticalAction,
		refreshTacticalWorld = SC_V3RefreshTacticalWorld,
		capture = SC_AutomateCityCaptureFinishers,
		airSuperiority = SC_AutomateAirSuperiority,
		localDefense = SC_AutomateLocalDefense,
		cityStrike = SC_AutomateCityRangedStrike,
		strategicMovement = SC_AutomateStrategicMovement,
		stacked = SC_AutomateStackedUnits,
		idlePosture = SC_AutomateIdlePosture,
		finalOrders = SC_AutomateFinalUnitOrders,
		tradeRoutes = SC_AutomateTradeRoutes,
		leagues = SC_AutomateLeagues,
		diploVote = function(player) return SC_AutomateDiploVote(player) end,
		activateBlockingNotification = SC_ActivateBlockingNotification,
		takePopupCount = function()
			local count = SC_LAST_POPUPS_HANDLED or 0
			SC_LAST_POPUPS_HANDLED = 0
			return count
		end,
		takeDiploCount = function()
			local count = SC_LAST_DIPLO_HANDLED or 0
			SC_LAST_DIPLO_HANDLED = 0
			return count
		end,
	}
end

function SC_RunV3Once(player, atWar, reason)
	if player == nil then return {}, {} end
	SC_ApplyStrategicProfiles()
	if SC_StrategyBeginTurn ~= nil then
		local ok, err = pcall(function()
			SC_StrategyBeginTurn(player, atWar, reason or "manual", true)
		end)
		if not ok then
			SC_Debug("module error name=v3ManualStrategy err="..tostring(err).." recovery=continue")
		end
	end
	return SCV3_RunEngine(player, atWar, true, reason or "manual", SC_GetV3Adapters())
end

local function SC_RunTakeoverPass(player, reason, allowEndTurn)
	local passStarted = nil
	if SC_GetConfig("DebugPerformance", true) and os ~= nil and os.clock ~= nil then
		pcall(function() passStarted = os.clock() end)
	end
	if player == nil then
		SC_Debug("pass skip reason="..tostring(reason).." cause=nil-player")
		return nil, {}, false
	end
	if not SC_IsTakeoverActive() then
		SC_Debug("pass skip reason="..tostring(reason).." cause=inactive remaining="..tostring(SC_GetConfig("TakeoverTurnsRemaining", 0)))
		return nil, {}, false
	end
	SC_ResetTakeoverPassCounterForTurn()
	if SC_LAST_TAKEOVER_PASS_COUNT >= SC_GetConfig("MaxTakeoverPassesPerTurn", 6) then
		SC_Debug("pass cap reason="..tostring(reason)..
			" count="..tostring(SC_LAST_TAKEOVER_PASS_COUNT)..
			" max="..tostring(SC_GetConfig("MaxTakeoverPassesPerTurn", 6))..
			" blocker="..SC_GetBlockingDebug(player))
		if allowEndTurn then
			SC_TryAutoEndTurn(player)
		end
		return nil, {}, SC_PlayerAtWar(player)
	end
	SC_LAST_TAKEOVER_PASS_COUNT = SC_LAST_TAKEOVER_PASS_COUNT + 1
	local fullEligible = reason ~= "popup"
	local fullAutomation = fullEligible
		and SC_FULL_AUTOMATION_PASS_COUNT < SC_GetConfig("MaxFullAutomationPassesPerTurn", 1)
	if fullAutomation then
		SC_FULL_AUTOMATION_PASS_COUNT = SC_FULL_AUTOMATION_PASS_COUNT + 1
	end
	SC_ApplyStrategicProfiles()
	local atWar = SC_PlayerAtWar(player)
	if SC_StrategyBeginTurn ~= nil then
		local strategyOK, strategyErr = pcall(function()
			SC_StrategyBeginTurn(player, atWar, reason, fullAutomation)
		end)
		if not strategyOK then
			SC_Debug("module error name=strategyPlan err="..tostring(strategyErr).." recovery=legacy")
		end
	end
	SC_Debug("pass begin reason="..tostring(reason)..
		" count="..tostring(SC_LAST_TAKEOVER_PASS_COUNT)..
		" remaining="..tostring(SC_GetConfig("TakeoverTurnsRemaining", 0))..
		" atWar="..SC_BoolText(atWar)..
		" mode="..(fullAutomation and "full" or "light")..
		" allowEndTurn="..SC_BoolText(allowEndTurn)..
		" blocker="..SC_GetBlockingDebug(player))
	local auditOK, auditErr = true, nil
	if fullAutomation then
		auditOK, auditErr = pcall(function()
			SC_AuditPlayerUnits(player, "pass-begin:"..tostring(reason), SC_GetConfig("DebugUnitAuditFullPassBegin", true))
		end)
	end
	if not auditOK then
		SC_Debug("module error name=passBeginAudit err="..tostring(auditErr).." recovery=continue")
	end
	local notificationHandled = 0
	local _ = nil
	if SC_ProcessNotificationQueue ~= nil then
		local notificationErrors = 0
		notificationHandled, _, notificationErrors = SC_RunCountModule("notifications", function()
			return SC_ProcessNotificationQueue(player, "pass:"..tostring(reason))
		end)
		if notificationErrors > 0 then
			SC_Debug("pass notification recovery errors="..tostring(notificationErrors))
		end
	end
	local buildOK, results, cityDetails = pcall(function()
		return SCV3_RunEngine(player, atWar, fullAutomation, reason, SC_GetV3Adapters())
	end)
	if not buildOK then
		SC_Debug("module error name=v3Engine err="..tostring(results).." recovery=stop-takeover")
		SCV3_HaltMilitary(SC_GetV3Adapters(), "engine:"..tostring(results))
		results = { moduleErrors = 1 }
		cityDetails = {}
	end
	if results ~= nil then
		results.notifications = notificationHandled
	end
	if allowEndTurn then
		local autoEndOK, autoEndErr = pcall(function() SC_TryAutoEndTurn(player) end)
		if not autoEndOK then
			SC_Debug("module error name=autoEndTurn err="..tostring(autoEndErr).." recovery=retry-tick")
		end
	end
	results = results or {}
	if fullAutomation then
		auditOK, auditErr = pcall(function() SC_AuditPlayerUnits(player, "pass-end:"..tostring(reason), false) end)
	end
	if not auditOK then
		SC_Debug("module error name=passEndAudit err="..tostring(auditErr).." recovery=continue")
	end
	SC_Debug("pass end reason="..tostring(reason)..
		" city="..tostring(results.cityOrders or 0)..
		" research="..tostring(results.research or 0)..
		" policy="..tostring(results.policies or 0)..
		" promote="..tostring(results.promotions or 0)..
		" greatPeople="..tostring(results.greatPeople or 0)..
		" purchases="..tostring(results.purchases or 0)..
		" captureFinish="..tostring(results.captureFinishers or 0)..
		" tactical="..tostring(results.defenseActions or 0)..
		" cityStrike="..tostring(results.cityStrikes or 0)..
		" transportEscort="..tostring(results.transportEscort or 0)..
		" strategicMove="..tostring(results.strategicMoves or 0)..
		" stacked="..tostring(results.stackedMoves or 0)..
		" finalOrders="..tostring(results.finalOrders or 0)..
		" notifications="..tostring(results.notifications or 0)..
		" popups="..tostring(results.popups or 0)..
		" diplo="..tostring(results.diplo or 0)..
		" moduleErrors="..tostring(results.moduleErrors or 0)..
		" blocker="..SC_GetBlockingDebug(player))
	if passStarted ~= nil then
		local passFinished = nil
		pcall(function() passFinished = os.clock() end)
		if passFinished ~= nil then
			SC_Debug("performance pass reason="..tostring(reason)..
				" mode="..(fullAutomation and "full" or "light")..
				" elapsedMs="..tostring(math.floor(math.max(0, passFinished - passStarted) * 1000 + 0.5)))
		end
	end
	return results, cityDetails, atWar
end

local function SC_StartTakeover(turns)
	if SCV3 then SCV3.criticalFault = nil end
	SC_CONFIG.TakeoverTurnsRemaining = turns
	SC_SaveTakeoverState()
	SC_ApplyStrategicProfiles()
	SC_Debug("takeover start turns="..tostring(turns))
	local player = SC_GetActiveHuman()
	if player ~= nil then
		local results, cityDetails, atWar = SC_RunTakeoverPass(player, "start", false)
		results = results or {}
		cityDetails = cityDetails or {}
		SC_SendNotification(player, "战略托管", "已开始接管 "..tostring(turns).." 回合[NEWLINE]方针: "..SC_GetDoctrineDisplayName(SC_GetConfig("Doctrine", "BALANCED")))
		SC_SendNationalBriefNow(player, results, cityDetails, atWar)
	end
end

local function SC_StopTakeover()
	SC_CONFIG.TakeoverTurnsRemaining = 0
	SC_SaveTakeoverState()
	SC_Debug("takeover stop")
	local player = SC_GetActiveHuman()
	if player ~= nil then
		SC_SendNotification(player, "战略托管", "托管已停止。")
	end
end

local function SC_UpdatePanel()
	if Controls == nil then
		return
	end
	local player = SC_GetActiveHuman()
	local atWar = SC_PlayerAtWar(player)
	local function boolText(key)
		if SC_GetConfig(key, true) then return "开" end
		return "关"
	end
	SC_SetLabel(Controls.CommandButton, "战略")
	SC_SetLabel(Controls.Takeover5Button, "5回合")
	SC_SetLabel(Controls.Takeover10Button, "10回合")
	SC_SetLabel(Controls.Takeover20Button, "20回合")
	SC_SetLabel(Controls.Takeover50Button, "50回合")
	SC_SetLabel(Controls.DiplomacyProfileButton, SC_GetProfileButtonText("DiplomacyProfile"))
	SC_SetLabel(Controls.EconomyProfileButton, SC_GetProfileButtonText("EconomyProfile"))
	SC_SetLabel(Controls.BuildProfileButton, SC_GetProfileButtonText("BuildProfile"))
	SC_SetLabel(Controls.DevelopmentProfileButton, SC_GetProfileButtonText("DevelopmentProfile"))
	SC_SetLabel(Controls.ProductionProfileButton, SC_GetProfileButtonText("ProductionProfile"))
	SC_SetLabel(Controls.WarProfileButton, SC_GetProfileButtonText("WarProfile"))
	SC_SetLabel(Controls.CapturedCityProfileButton, SC_GetProfileButtonText("CapturedCityAction"))
	SC_SetLabel(Controls.GreatPersonProfileButton, SC_GetProfileButtonText("GreatPersonProfile"))
	SC_SetLabel(Controls.ReligionProfileButton, SC_GetProfileButtonText("ReligionProfile"))
	SC_SetLabel(Controls.TradeProfileButton, SC_GetProfileButtonText("TradeProfile"))
	local selectedProfile = SC_GetConfig("SelectedProfileKey", "DiplomacyProfile")
	local selectedLabel = SC_PROFILE_LABELS[selectedProfile] or "预设"
	SC_SetLabel(Controls.ProfileListTitle, selectedLabel.."选项")
	local options = SC_PROFILE_OPTIONS[selectedProfile] or {}
	for i = 1, 4, 1 do
		local control = Controls["ProfileOption"..tostring(i).."Button"]
		local option = options[i]
		if control ~= nil and option ~= nil then
			local marker = "  "
			if SC_GetConfig(selectedProfile, "") == option.Key then
				marker = "> "
			end
			SC_SetLabel(control, marker..option.Text)
			control:SetHide(false)
		elseif control ~= nil then
			control:SetHide(true)
		end
	end
	SC_SetLabel(Controls.RunOnceButton, "立即执行")
	SC_SetLabel(Controls.StopTakeoverButton, "停止托管")
	SC_SetLabel(Controls.BriefButton, "立即简报")
	SC_SetLabel(Controls.OpenTechButton, "科技树")
	SC_SetLabel(Controls.OpenPolicyButton, "政策树")
	SC_SetLabel(Controls.CloseButton, "关闭")
	SC_SetLabel(Controls.DoctrineLabel, SC_GetDoctrineDisplayName(SC_GetConfig("Doctrine", "BALANCED")))
	SC_SetLabel(Controls.ResearchAutomationButton, "科研："..boolText("AutoResearch"))
	SC_SetLabel(Controls.PolicyAutomationButton, "政策："..boolText("AutoPolicy"))
	SC_SetLabel(Controls.CityAutomationButton, "生产："..boolText("AutoCityProduction"))
	SC_SetLabel(Controls.DefenseAutomationButton, "防御："..boolText("AutoLocalDefense"))
	SC_SetLabel(Controls.CityStrikeAutomationButton, "城市炮击："..boolText("AutoCityRangedStrike"))
	SC_SetLabel(Controls.UpgradeAutomationButton, "升级："..boolText("AutoUpgradeUnits"))
	SC_SetLabel(Controls.PromoteAutomationButton, "晋升："..boolText("AutoPromoteUnits"))
	SC_SetLabel(Controls.HealAutomationButton, "治疗："..boolText("AutoHealDamagedUnits"))
	SC_SetLabel(Controls.MoveAutomationButton, "机动："..boolText("AutoStrategicMove"))
	SC_SetLabel(Controls.AutoEndTurnButton, "自动结束："..boolText("AutoEndTurn"))
	SC_SetLabel(Controls.PopupAutomationButton, "弹窗："..boolText("AutoPopupHandling"))
	SC_SetLabel(Controls.IdlePostureAutomationButton, "待命姿态："..boolText("AutoIdlePosture"))
	local remaining = SC_GetSafeNumber(function() return SC_CONFIG.TakeoverTurnsRemaining end, 0)
	if player ~= nil then
		local status = "托管剩余: "..tostring(remaining).." 回合   城市: "..tostring(player:GetNumCities())
		status = status.."[NEWLINE]国库: "..tostring(SC_GetSafeNumber(function() return player:GetGold() end, 0))
		status = status.."[NEWLINE]可行动作战单位: "..tostring(SC_CountIdleCombatUnits(player)).."   空队列: "..tostring(SC_CountEmptyCityQueues(player))
		status = status.."[NEWLINE]自动结束: "..boolText("AutoEndTurn").."   未处理弹窗: "..tostring(SC_LAST_UNHANDLED_POPUP)
		if atWar then
			status = status.."[NEWLINE]战争状态: 战争中"
		else
			status = status.."[NEWLINE]战争状态: 和平"
		end
		SC_SetLabel(Controls.StatusLabel, status)
	else
		SC_SetLabel(Controls.StatusLabel, "没有有效的人类玩家。")
	end
end

local function SC_TogglePanel()
	if Controls == nil or Controls.MainPanel == nil then
		return
	end
	Controls.MainPanel:SetHide(not Controls.MainPanel:IsHidden())
	SC_UpdatePanel()
end

local function SC_SetDoctrine(doctrine)
	SC_CONFIG.Doctrine = doctrine
	SC_UpdatePanel()
end

local function SC_ToggleResearchAutomation()
	SC_CONFIG.AutoResearch = not SC_GetConfig("AutoResearch", true)
	SC_UpdatePanel()
end

local function SC_ToggleCityAutomation()
	SC_CONFIG.AutoCityProduction = not SC_GetConfig("AutoCityProduction", true)
	SC_UpdatePanel()
end

local function SC_ToggleDefenseAutomation()
	SC_CONFIG.AutoLocalDefense = not SC_GetConfig("AutoLocalDefense", true)
	SC_UpdatePanel()
end

local function SC_ToggleCityStrikeAutomation()
	SC_CONFIG.AutoCityRangedStrike = not SC_GetConfig("AutoCityRangedStrike", true)
	SC_UpdatePanel()
end

local function SC_ToggleUpgradeAutomation()
	SC_CONFIG.AutoUpgradeUnits = not SC_GetConfig("AutoUpgradeUnits", true)
	SC_UpdatePanel()
end

local function SC_TogglePolicyAutomation()
	SC_CONFIG.AutoPolicy = not SC_GetConfig("AutoPolicy", true)
	SC_UpdatePanel()
end

local function SC_TogglePromoteAutomation()
	SC_CONFIG.AutoPromoteUnits = not SC_GetConfig("AutoPromoteUnits", true)
	SC_UpdatePanel()
end

local function SC_ToggleHealAutomation()
	SC_CONFIG.AutoHealDamagedUnits = not SC_GetConfig("AutoHealDamagedUnits", true)
	SC_UpdatePanel()
end

local function SC_ToggleMoveAutomation()
	SC_CONFIG.AutoStrategicMove = not SC_GetConfig("AutoStrategicMove", true)
	SC_UpdatePanel()
end

local function SC_TogglePopupAutomation()
	SC_CONFIG.AutoPopupHandling = not SC_GetConfig("AutoPopupHandling", true)
	SC_UpdatePanel()
end

local function SC_ToggleAutoEndTurn()
	SC_CONFIG.AutoEndTurn = not SC_GetConfig("AutoEndTurn", true)
	SC_UpdatePanel()
end

local function SC_ToggleIdlePostureAutomation()
	SC_CONFIG.AutoIdlePosture = not SC_GetConfig("AutoIdlePosture", true)
	SC_UpdatePanel()
end

local function SC_RunOnce()
	local player = SC_GetActiveHuman()
	if player == nil then
		return
	end
	local atWar = SC_PlayerAtWar(player)
	local results, cityDetails = SC_RunV3Once(player, atWar, "manual")
	SC_SendNotification(player, "战略指挥部", "手动执行完成[NEWLINE]城市安排: "..tostring(results.cityOrders or 0).."[NEWLINE]意识形态: "..tostring(results.ideologies or 0).."[NEWLINE]科研选择: "..tostring(results.research or 0).."[NEWLINE]政策选择: "..tostring(results.policies or 0).."[NEWLINE]单位升级: "..tostring(results.upgrades or 0).."[NEWLINE]单位晋升: "..tostring(results.promotions or 0).."[NEWLINE]伟人使用: "..tostring(results.greatPeople or 0).."[NEWLINE]金币购军: "..tostring(results.purchases or 0).."[NEWLINE]战略机动: "..tostring(results.strategicMoves or 0).."[NEWLINE]贸易路线: "..tostring(results.tradeRoutes or 0).."[NEWLINE]世界议会: "..tostring(results.leagues or 0).."[NEWLINE]残留单位处理: "..tostring(results.finalOrders or 0).."[NEWLINE]弹窗处理: "..tostring(results.popups or 0))
	SC_SendNationalBriefNow(player, results, cityDetails, atWar)
	SC_UpdatePanel()
end

local function SC_BriefNow()
	local player = SC_GetActiveHuman()
	if player == nil then
		return
	end
	SC_SendNationalBriefNow(player, {}, {}, SC_PlayerAtWar(player))
	SC_UpdatePanel()
end

local function SC_MarkPopupProcessed(popupType)
	SC_LAST_UNHANDLED_POPUP = "none"
	local ok = pcall(function()
		Events.SerialEventGameMessagePopupProcessed.CallImmediate(popupType, 0)
	end)
	if not ok then
		pcall(function() Events.SerialEventGameMessagePopupProcessed(popupType, 0) end)
	end
end

local function SC_HandleCapturedCityPopup(popupInfo)
	if popupInfo == nil or popupInfo.Data1 == nil then
		return false
	end
	local cityID = popupInfo.Data1
	local action = SC_GetConfig("CapturedCityAction", "PUPPET")
	local taskType = TaskTypes.TASK_CREATE_PUPPET
	if action == "ANNEX" then
		taskType = TaskTypes.TASK_ANNEX_PUPPET
	elseif action == "RAZE" then
		taskType = TaskTypes.TASK_RAZE
	end
	return pcall(function()
		Network.SendDoTask(cityID, taskType, -1, -1, false, false, false, false)
	end)
end

local function SC_GetIdeologyBranchID()
	local war = SC_GetConfig("WarProfile", "ADVANCE")
	local economy = SC_GetConfig("EconomyProfile", "BALANCED")
	local build = SC_GetConfig("BuildProfile", "INFRASTRUCTURE")
	local diplomacy = SC_GetConfig("DiplomacyProfile", "BALANCED")
	local branchType = "POLICY_BRANCH_ORDER"
	if war == "ASSAULT" or war == "NAVAL" then
		branchType = "POLICY_BRANCH_AUTOCRACY"
	elseif diplomacy == "FRIENDLY" or economy == "TREASURY" then
		branchType = "POLICY_BRANCH_FREEDOM"
	elseif economy == "SCIENCE" or build == "SCIENCE" then
		branchType = "POLICY_BRANCH_ORDER"
	end
	return GameInfoTypes[branchType]
end

local function SC_HandleChooseIdeologyPopup()
	local branchID = SC_GetIdeologyBranchID()
	if branchID == nil then
		return false
	end
	return pcall(function()
		Network.SendIdeologyChoice(Game.GetActivePlayer(), branchID)
	end)
end

local function SC_GetGreatPersonScore(unitInfo)
	if unitInfo == nil then
		return -9999
	end
	local unitType = unitInfo.Type or ""
	local profile = SC_GetConfig("GreatPersonProfile", "SLEEP")
	local score = 0
	if string.find(unitType, "SCIENTIST") ~= nil then score = score + 1000 end
	if string.find(unitType, "ENGINEER") ~= nil then score = score + 900 end
	if string.find(unitType, "GENERAL") ~= nil then score = score + 800 end
	if string.find(unitType, "ADMIRAL") ~= nil then score = score + 760 end
	if string.find(unitType, "MERCHANT") ~= nil then score = score + 620 end
	if string.find(unitType, "WRITER") ~= nil then score = score + 560 end
	if string.find(unitType, "ARTIST") ~= nil then score = score + 540 end
	if string.find(unitType, "MUSICIAN") ~= nil then score = score + 520 end
	if string.find(unitType, "PROPHET") ~= nil then score = score + 220 end
	if profile == "ENGINEER" and string.find(unitType, "ENGINEER") ~= nil then score = score + 1000 end
	if profile == "SCIENCE" and string.find(unitType, "SCIENTIST") ~= nil then score = score + 1000 end
	if profile == "CULTURE" and (string.find(unitType, "WRITER") ~= nil or string.find(unitType, "ARTIST") ~= nil or string.find(unitType, "MUSICIAN") ~= nil) then score = score + 1000 end
	score = score + math.max(unitInfo.Cost or 0, 0) / 10
	return score
end

local function SC_CanChooseFaithGreatPerson(player, unitInfo)
	if player == nil or unitInfo == nil then
		return false
	end
	local canTrain = false
	pcall(function()
		canTrain = player:CanTrain(unitInfo.ID, true, true, true, false)
	end)
	if not canTrain then
		return false
	end
	local unitType = unitInfo.Type or ""
	if unitType == "UNIT_PROPHET" then
		return SC_GetSafeNumber(function() return player:HasCreatedPantheon() and 1 or 0 end, 0) > 0
	elseif unitType == "UNIT_MERCHANT" then
		return SC_GetSafeNumber(function() return player:IsPolicyBranchFinished(GameInfoTypes.POLICY_BRANCH_COMMERCE) and 1 or 0 end, 0) > 0
	elseif unitType == "UNIT_SCIENTIST" then
		return SC_GetSafeNumber(function() return player:IsPolicyBranchFinished(GameInfoTypes.POLICY_BRANCH_RATIONALISM) and 1 or 0 end, 0) > 0
	elseif unitType == "UNIT_WRITER" or unitType == "UNIT_ARTIST" or unitType == "UNIT_MUSICIAN" then
		return SC_GetSafeNumber(function() return player:IsPolicyBranchFinished(GameInfoTypes.POLICY_BRANCH_AESTHETICS) and 1 or 0 end, 0) > 0
	elseif unitType == "UNIT_GREAT_GENERAL" then
		return SC_GetSafeNumber(function() return player:IsPolicyBranchFinished(GameInfoTypes.POLICY_BRANCH_HONOR) and 1 or 0 end, 0) > 0
	elseif unitType == "UNIT_GREAT_ADMIRAL" then
		return SC_GetSafeNumber(function() return player:IsPolicyBranchFinished(GameInfoTypes.POLICY_BRANCH_EXPLORATION) and 1 or 0 end, 0) > 0
	elseif unitType == "UNIT_ENGINEER" then
		return SC_GetSafeNumber(function() return player:IsPolicyBranchFinished(GameInfoTypes.POLICY_BRANCH_TRADITION) and 1 or 0 end, 0) > 0
	end
	return true
end

local function SC_GetBestGreatPersonID(player, faithChoice)
	local bestID = nil
	local bestScore = -9999
	for unitInfo in GameInfo.Units{Special = "SPECIALUNIT_PEOPLE"} do
		local valid = false
		if faithChoice then
			valid = SC_CanChooseFaithGreatPerson(player, unitInfo)
		else
			pcall(function()
				valid = player:CanTrain(unitInfo.ID, true, true, true, false)
			end)
			if unitInfo.FoundReligion and SC_GetSafeNumber(function() return player:HasCreatedPantheon() and 1 or 0 end, 0) <= 0 then
				valid = false
			end
		end
		if valid then
			local score = SC_GetGreatPersonScore(unitInfo)
			if score > bestScore then
				bestScore = score
				bestID = unitInfo.ID
			end
		end
	end
	return bestID
end

local function SC_HandleFreeGreatPersonPopup(player, faithChoice)
	local unitID = SC_GetBestGreatPersonID(player, faithChoice)
	if unitID == nil then
		return false
	end
	if faithChoice then
		return pcall(function()
			Network.SendFaithGreatPersonChoice(Game.GetActivePlayer(), unitID)
		end)
	end
	return pcall(function()
		Network.SendGreatPersonChoice(Game.GetActivePlayer(), unitID)
	end)
end

local function SC_HandleMayaBonusPopup(player)
	local unitID = SC_GetBestGreatPersonID(player, false)
	if unitID == nil then
		return false
	end
	return pcall(function()
		Network.SendMayaBonusChoice(Game.GetActivePlayer(), unitID)
	end)
end

local function SC_GetGoodyScore(goody)
	if goody == nil then
		return 0
	end
	local text = tostring(goody.Type or "").." "..tostring(goody.Description or "").." "..tostring(goody.ChooseDescription or "")
	local score = 0
	if string.find(text, "TECH") ~= nil then score = score + 100 end
	if string.find(text, "POPULATION") ~= nil then score = score + 80 end
	if string.find(text, "CULTURE") ~= nil then score = score + 70 end
	if string.find(text, "FAITH") ~= nil then score = score + 60 end
	if string.find(text, "GOLD") ~= nil then score = score + 55 end
	if string.find(text, "MAP") ~= nil then score = score + 20 end
	return score
end

local function SC_HandleGoodyChoicePopup(popupInfo)
	if popupInfo == nil then
		return false
	end
	local player = Players[popupInfo.Data1]
	if player == nil then
		return false
	end
	local unit = player:GetUnitByID(popupInfo.Data2)
	if unit == nil then
		return false
	end
	local plot = unit:GetPlot()
	if plot == nil then
		return false
	end
	local bestGoody = nil
	local bestScore = -9999
	local index = 0
	for goody in GameInfo.GoodyHuts() do
		local canGet = false
		pcall(function() canGet = player:CanGetGoody(plot, index, unit) end)
		if canGet then
			local score = SC_GetGoodyScore(goody)
			if score > bestScore then
				bestScore = score
				bestGoody = index
			end
		end
		index = index + 1
	end
	if bestGoody == nil then
		return false
	end
	return pcall(function()
		Network.SendGoodyChoice(popupInfo.Data1, plot:GetX(), plot:GetY(), bestGoody, unit:GetID())
	end)
end

local function SC_GetBeliefScore(belief)
	if belief == nil then
		return -9999
	end
	local profile = SC_GetConfig("ReligionProfile", "PRODUCTION")
	local text = tostring(belief.Type or "").." "..tostring(belief.ShortDescription or "").." "..tostring(belief.Description or "")
	local score = 0
	local function addIf(pattern, value)
		if string.find(text, pattern) ~= nil then
			score = score + value
		end
	end
	if profile == "PRODUCTION" then
		addIf("PRODUCTION", 100)
		addIf("GROWTH", 35)
		addIf("FOOD", 25)
	elseif profile == "SCIENCE" then
		addIf("SCIENCE", 120)
		addIf("GROWTH", 30)
	elseif profile == "GOLD" then
		addIf("GOLD", 120)
		addIf("TITHE", 80)
		addIf("TRADE", 35)
	elseif profile == "CULTURE" then
		addIf("CULTURE", 120)
		addIf("TOURISM", 80)
		addIf("ART", 30)
	end
	score = score + SC_GetSafeNumber(function() return belief.FaithFromKills end, 0)
	score = score + SC_GetSafeNumber(function() return belief.MinPopulation end, 0)
	return score
end

local function SC_PickBelief(beliefs, used)
	local bestID = nil
	local bestScore = -99999
	if beliefs == nil then
		return nil
	end
	for _, beliefID in ipairs(beliefs) do
		if beliefID ~= nil and (used == nil or not used[beliefID]) then
			local belief = GameInfo.Beliefs[beliefID]
			local score = SC_GetBeliefScore(belief)
			if score > bestScore then
				bestScore = score
				bestID = beliefID
			end
		end
	end
	if bestID ~= nil and used ~= nil then
		used[bestID] = true
	end
	return bestID
end

local function SC_GetAvailableBeliefs(callbackName)
	local beliefs = {}
	if Game == nil or Game[callbackName] == nil then
		return beliefs
	end
	pcall(function()
		for _, beliefID in ipairs(Game[callbackName]()) do
			table.insert(beliefs, beliefID)
		end
	end)
	return beliefs
end

local function SC_HandlePantheonPopup(popupInfo)
	if popupInfo == nil or not SC_GetConfig("AutoReligion", true) then
		return false
	end
	local listName = "GetAvailablePantheonBeliefs"
	if popupInfo.Data2 == false or popupInfo.Data2 == 0 then
		listName = "GetAvailableReformationBeliefs"
	end
	local beliefID = SC_PickBelief(SC_GetAvailableBeliefs(listName), {})
	if beliefID == nil then
		return false
	end
	return pcall(function()
		Network.SendFoundPantheon(Game.GetActivePlayer(), beliefID)
	end)
end

local function SC_GetBestReligionID()
	for religion in GameInfo.Religions() do
		if religion ~= nil and religion.ID ~= nil and religion.ID > 0 then
			local taken = false
			pcall(function() taken = Game.GetFounder(religion.ID, -1) ~= -1 end)
			if not taken then
				return religion.ID
			end
		end
	end
	return nil
end

local function SC_HandleReligionPopup(player, popupInfo)
	if player == nil or popupInfo == nil or not SC_GetConfig("AutoReligion", true) then
		return false
	end
	local noBelief = BeliefTypes ~= nil and BeliefTypes.NO_BELIEF or -1
	local used = {}
	local cityX = popupInfo.Data1 or -1
	local cityY = popupInfo.Data2 or -1
	local founding = popupInfo.Option1
	if founding then
		local religionID = SC_GetBestReligionID()
		if religionID == nil then
			return false
		end
		local beliefs = {}
		if SC_GetSafeNumber(function() return player:HasCreatedPantheon() and 1 or 0 end, 0) <= 0 then
			local pantheon = SC_PickBelief(SC_GetAvailableBeliefs("GetAvailablePantheonBeliefs"), used)
			if pantheon == nil then
				return false
			end
			table.insert(beliefs, pantheon)
		end
		local founder = SC_PickBelief(SC_GetAvailableBeliefs("GetAvailableFounderBeliefs"), used)
		local follower = SC_PickBelief(SC_GetAvailableBeliefs("GetAvailableFollowerBeliefs"), used)
		if founder == nil or follower == nil then
			return false
		end
		table.insert(beliefs, founder)
		table.insert(beliefs, follower)
		if SC_GetSafeNumber(function() return player:IsTraitBonusReligiousBelief() and 1 or 0 end, 0) > 0 then
			local bonus = SC_PickBelief(SC_GetAvailableBeliefs("GetAvailableBonusBeliefs"), used)
			if bonus == nil then
				return false
			end
			table.insert(beliefs, bonus)
		end
		while #beliefs < 4 do
			table.insert(beliefs, noBelief)
		end
		SC_Debug("religion found send religion="..tostring(religionID).." beliefs="..table.concat(beliefs, ",").." city="..tostring(cityX)..","..tostring(cityY))
		return pcall(function()
			Network.SendFoundReligion(Game.GetActivePlayer(), religionID, nil, beliefs[1], beliefs[2], beliefs[3], beliefs[4], cityX, cityY)
		end)
	end
	local religionID = SC_GetSafeNumber(function() return player:GetReligionCreatedByPlayer() end, -1)
	if ReligionTypes ~= nil and religionID <= ReligionTypes.RELIGION_PANTHEON then
		return false
	end
	local b4 = SC_PickBelief(SC_GetAvailableBeliefs("GetAvailableFollowerBeliefs"), used)
	local b5 = SC_PickBelief(SC_GetAvailableBeliefs("GetAvailableEnhancerBeliefs"), used)
	if b4 == nil or b5 == nil then
		return false
	end
	return pcall(function()
		Network.SendEnhanceReligion(Game.GetActivePlayer(), religionID, nil, b4, b5, cityX, cityY)
	end)
end

local function SC_HandleArchaeologyPopup(player, popupInfo)
	if player == nil or popupInfo == nil or not SC_GetConfig("AutoArchaeology", true) then
		return false
	end
	local choice = 1
	pcall(function()
		local plot = player:GetNextDigCompletePlot()
		local written = plot ~= nil and plot:HasWrittenArtifact()
		if written then
			local hasSlot = player:HasAvailableGreatWorkSlot(GameInfo.GreatWorkSlots.GREAT_WORK_SLOT_LITERATURE.ID)
			if hasSlot then
				choice = 5
			else
				choice = 4
			end
		else
			local hasSlot = player:HasAvailableGreatWorkSlot(GameInfo.GreatWorkSlots.GREAT_WORK_SLOT_ART_ARTIFACT.ID)
			if hasSlot and SC_GetConfig("ReligionProfile", "PRODUCTION") ~= "CULTURE" then
				choice = 2
			else
				choice = 1
			end
		end
	end)
	return pcall(function()
		Network.SendArchaeologyChoice(Game.GetActivePlayer(), popupInfo.Data2, choice)
	end)
end

local function SC_OnPopupAutoHandle(popupInfo)
	if popupInfo ~= nil and popupInfo.Type ~= nil and SC_IsDemonstrationLoggingActive ~= nil and SC_IsDemonstrationLoggingActive() then
		SC_DemoLog("popup", "event=SerialEventGameMessagePopup type="..SC_GetEnumDebugName(ButtonPopupTypes, popupInfo.Type)..
			" data1="..tostring(popupInfo.Data1)..
			" data2="..tostring(popupInfo.Data2)..
			" data3="..tostring(popupInfo.Data3)..
			" option1="..SC_BoolText(popupInfo.Option1 == true)..
			" option2="..SC_BoolText(popupInfo.Option2 == true))
	end
	if popupInfo == nil or popupInfo.Type == nil or not SC_IsTakeoverActive() or not SC_GetConfig("AutoPopupHandling", true) then
		return
	end
	local player = SC_GetActiveHuman()
	if player == nil then
		return
	end
	local popupType = popupInfo.Type
	SC_LAST_UNHANDLED_POPUP = tostring(popupType)
	local popupCountBefore = SC_LAST_POPUPS_HANDLED
	local runPassAfterPopup = true
	local popupKey = tostring(popupType).."|"..tostring(popupInfo.Data1).."|"..tostring(popupInfo.Data2).."|"..tostring(popupInfo.Data3).."|"..tostring(popupInfo.Option1)
	local popupAlreadyLogged = SC_POPUP_LOGGED_THIS_TURN[popupKey] == true
	if not popupAlreadyLogged then
		SC_POPUP_LOGGED_THIS_TURN[popupKey] = true
		SC_Debug("popup seen type="..SC_GetEnumDebugName(ButtonPopupTypes, popupType)..
			" data1="..tostring(popupInfo.Data1)..
			" data2="..tostring(popupInfo.Data2)..
			" data3="..tostring(popupInfo.Data3)..
			" option1="..tostring(popupInfo.Option1)..
			" blocker="..SC_GetBlockingDebug(player))
	end
	if popupType == ButtonPopupTypes.BUTTONPOPUP_CITY_CAPTURED then
		if SC_HandleCapturedCityPopup(popupInfo) then
			SC_LAST_POPUPS_HANDLED = SC_LAST_POPUPS_HANDLED + 1
			SC_MarkPopupProcessed(popupType)
		end
	elseif popupType == ButtonPopupTypes.BUTTONPOPUP_ANNEX_CITY then
		SC_LAST_POPUPS_HANDLED = SC_LAST_POPUPS_HANDLED + 1
		SC_MarkPopupProcessed(popupType)
	elseif popupType == ButtonPopupTypes.BUTTONPOPUP_CHOOSE_IDEOLOGY then
		if SC_HandleChooseIdeologyPopup() then
			SC_LAST_POPUPS_HANDLED = SC_LAST_POPUPS_HANDLED + 1
			SC_MarkPopupProcessed(popupType)
		end
	elseif popupType == ButtonPopupTypes.BUTTONPOPUP_CHOOSE_FREE_GREAT_PERSON then
		if SC_HandleFreeGreatPersonPopup(player, false) then
			SC_LAST_POPUPS_HANDLED = SC_LAST_POPUPS_HANDLED + 1
			SC_MarkPopupProcessed(popupType)
		end
	elseif popupType == ButtonPopupTypes.BUTTONPOPUP_CHOOSE_FAITH_GREAT_PERSON then
		if SC_HandleFreeGreatPersonPopup(player, true) then
			SC_LAST_POPUPS_HANDLED = SC_LAST_POPUPS_HANDLED + 1
			SC_MarkPopupProcessed(popupType)
		end
	elseif popupType == ButtonPopupTypes.BUTTONPOPUP_CHOOSE_MAYA_BONUS then
		if SC_HandleMayaBonusPopup(player) then
			SC_LAST_POPUPS_HANDLED = SC_LAST_POPUPS_HANDLED + 1
			SC_MarkPopupProcessed(popupType)
		end
	elseif popupType == ButtonPopupTypes.BUTTONPOPUP_CHOOSE_GOODY_HUT_REWARD then
		if SC_HandleGoodyChoicePopup(popupInfo) then
			SC_LAST_POPUPS_HANDLED = SC_LAST_POPUPS_HANDLED + 1
			SC_MarkPopupProcessed(popupType)
		end
	elseif popupType == ButtonPopupTypes.BUTTONPOPUP_FOUND_PANTHEON then
		if SC_HandlePantheonPopup(popupInfo) then
			SC_LAST_POPUPS_HANDLED = SC_LAST_POPUPS_HANDLED + 1
			SC_MarkPopupProcessed(popupType)
		end
	elseif popupType == ButtonPopupTypes.BUTTONPOPUP_FOUND_RELIGION then
		if SC_HandleReligionPopup(player, popupInfo) then
			SC_LAST_POPUPS_HANDLED = SC_LAST_POPUPS_HANDLED + 1
			SC_MarkPopupProcessed(popupType)
		end
	elseif popupType == ButtonPopupTypes.BUTTONPOPUP_CHOOSE_ARCHAEOLOGY then
		if SC_HandleArchaeologyPopup(player, popupInfo) then
			SC_LAST_POPUPS_HANDLED = SC_LAST_POPUPS_HANDLED + 1
			SC_MarkPopupProcessed(popupType)
		end
	elseif popupType == ButtonPopupTypes.BUTTONPOPUP_CHOOSE_INTERNATIONAL_TRADE_ROUTE then
		if SC_AutomateTradeRoutes(player) > 0 then
			SC_LAST_POPUPS_HANDLED = SC_LAST_POPUPS_HANDLED + 1
			SC_MarkPopupProcessed(popupType)
		end
	elseif popupType == ButtonPopupTypes.BUTTONPOPUP_CONFIRM_POLICY_BRANCH_SWITCH then
		if popupInfo.Data1 ~= nil then
			pcall(function() Network.SendUpdatePolicies(popupInfo.Data1, false, true) end)
		end
		SC_LAST_POPUPS_HANDLED = SC_LAST_POPUPS_HANDLED + 1
		SC_MarkPopupProcessed(popupType)
	elseif popupType == ButtonPopupTypes.BUTTONPOPUP_CHOOSEPRODUCTION then
		local atWar = SC_PlayerAtWar(player)
		SC_AutomateCities(player, atWar)
		SC_LAST_POPUPS_HANDLED = SC_LAST_POPUPS_HANDLED + 1
		SC_MarkPopupProcessed(popupType)
	elseif popupType == ButtonPopupTypes.BUTTONPOPUP_CHOOSEPOLICY then
		local policyHandled = SC_AutomatePolicy(player)
		if policyHandled > 0 then
			SC_LAST_POPUPS_HANDLED = SC_LAST_POPUPS_HANDLED + 1
			SC_MarkPopupProcessed(popupType)
		elseif SC_ShouldDelegatePolicyPopupToUI(player) then
			SC_Debug("policy popup delegated-to-ui")
			SC_LAST_POPUPS_HANDLED = SC_LAST_POPUPS_HANDLED + 1
			SC_MarkPopupProcessed(popupType)
			runPassAfterPopup = false
		end
	elseif popupType == ButtonPopupTypes.BUTTONPOPUP_TECH_TREE or popupType == ButtonPopupTypes.BUTTONPOPUP_CHOOSETECH then
		if SC_AutomateResearch(player) > 0 then
			SC_LAST_POPUPS_HANDLED = SC_LAST_POPUPS_HANDLED + 1
			SC_MarkPopupProcessed(popupType)
		end
	elseif popupType == ButtonPopupTypes.BUTTONPOPUP_LEAGUE_OVERVIEW then
		SC_AutomateLeagues(player)
		SC_LAST_POPUPS_HANDLED = SC_LAST_POPUPS_HANDLED + 1
		SC_MarkPopupProcessed(popupType)
	elseif popupType == ButtonPopupTypes.BUTTONPOPUP_DIPLO_VOTE then
		SC_AutomateDiploVote(player)
		SC_LAST_POPUPS_HANDLED = SC_LAST_POPUPS_HANDLED + 1
		SC_MarkPopupProcessed(popupType)
	elseif popupType == ButtonPopupTypes.BUTTONPOPUP_DECLAREWARMOVE
		or popupType == ButtonPopupTypes.BUTTONPOPUP_DECLAREWARRANGESTRIKE
		or popupType == ButtonPopupTypes.BUTTONPOPUP_DECLAREWAR_PLUNDER_TRADE_ROUTE then
		SC_Debug("popup reject-new-war type="..SC_GetEnumDebugName(ButtonPopupTypes, popupType)..
			" rivalTeam="..tostring(popupInfo.Data1)..
			" target="..tostring(popupInfo.Data2)..","..tostring(popupInfo.Data3))
		pcall(function() UI.SetInterfaceMode(InterfaceModeTypes.INTERFACEMODE_SELECTION) end)
		SC_LAST_POPUPS_HANDLED = SC_LAST_POPUPS_HANDLED + 1
		SC_MarkPopupProcessed(popupType)
		runPassAfterPopup = false
	elseif popupType == ButtonPopupTypes.BUTTONPOPUP_DIPLO_VOTE or popupType == ButtonPopupTypes.BUTTONPOPUP_VOTE_RESULTS or popupType == ButtonPopupTypes.BUTTONPOPUP_TECH_AWARD or popupType == ButtonPopupTypes.BUTTONPOPUP_NEW_ERA or popupType == ButtonPopupTypes.BUTTONPOPUP_LEAGUE_SPLASH or popupType == ButtonPopupTypes.BUTTONPOPUP_LEAGUE_PROJECT_COMPLETED or popupType == ButtonPopupTypes.BUTTONPOPUP_GREAT_PERSON_REWARD or popupType == ButtonPopupTypes.BUTTONPOPUP_GOLDEN_AGE_REWARD or popupType == ButtonPopupTypes.BUTTONPOPUP_BARBARIAN_CAMP_REWARD or popupType == ButtonPopupTypes.BUTTONPOPUP_WHOS_WINNING or popupType == ButtonPopupTypes.BUTTONPOPUP_GREAT_WORK_COMPLETED_ACTIVE_PLAYER or popupType == ButtonPopupTypes.BUTTONPOPUP_CITY_STATE_GREETING or popupType == ButtonPopupTypes.BUTTONPOPUP_CITY_STATE_MESSAGE or popupType == ButtonPopupTypes.BUTTONPOPUP_MINOR_GOLD_GIFT or popupType == ButtonPopupTypes.BUTTONPOPUP_NATURAL_WONDER_REWARD or popupType == ButtonPopupTypes.BUTTONPOPUP_GOODY_HUT_REWARD or popupType == ButtonPopupTypes.BUTTONPOPUP_ADVISOR_COUNSEL or popupType == ButtonPopupTypes.BUTTONPOPUP_EVENT or popupType == ButtonPopupTypes.BUTTONPOPUP_WONDER_COMPLETED_ACTIVE_PLAYER or popupType == ButtonPopupTypes.BUTTONPOPUP_WONDER_COMPLETED or popupType == ButtonPopupTypes.BUTTONPOPUP_TEXT or popupType == ButtonPopupTypes.BUTTONPOPUP_DECLAREWARMOVE or popupType == ButtonPopupTypes.BUTTONPOPUP_DECLAREWARRANGESTRIKE or popupType == ButtonPopupTypes.BUTTONPOPUP_DECLAREWAR_PLUNDER_TRADE_ROUTE then
		SC_LAST_POPUPS_HANDLED = SC_LAST_POPUPS_HANDLED + 1
		SC_MarkPopupProcessed(popupType)
		runPassAfterPopup = false
	elseif popupType == ButtonPopupTypes.BUTTONPOPUP_DIPLOMACY then
		SC_LAST_POPUPS_HANDLED = SC_LAST_POPUPS_HANDLED + 1
		SC_MarkPopupProcessed(popupType)
		runPassAfterPopup = false
	end
	if SC_LAST_POPUPS_HANDLED == popupCountBefore and SC_GetConfig("AggressivePopupDismissal", true) then
		local atWar = SC_PlayerAtWar(player)
		local blockerBefore = SC_GetBlockingDebug(player)
		local blockerHandled = SC_HandleEndTurnBlocker(player, atWar, false)
		local blockerAfter = SC_GetBlockingDebug(player)
		if blockerHandled > 0 and blockerAfter ~= blockerBefore then
			SC_MarkPopupProcessed(popupType)
			SC_LAST_POPUPS_HANDLED = SC_LAST_POPUPS_HANDLED + 1
			runPassAfterPopup = false
			SC_Debug("popup aggressive-processed type="..SC_GetEnumDebugName(ButtonPopupTypes, popupType)..
				" blockerHandled="..tostring(blockerHandled)..
				" blockerBefore="..tostring(blockerBefore)..
				" blockerNow="..tostring(blockerAfter))
		else
			runPassAfterPopup = false
			SC_Debug("popup aggressive-skip type="..SC_GetEnumDebugName(ButtonPopupTypes, popupType)..
				" blockerHandled="..tostring(blockerHandled)..
				" blockerBefore="..tostring(blockerBefore)..
				" blockerNow="..tostring(blockerAfter))
		end
	end
	if SC_LAST_POPUPS_HANDLED > popupCountBefore then
		SC_LAST_UNHANDLED_POPUP = "none"
		if not popupAlreadyLogged then
			SC_Debug("popup handled type="..SC_GetEnumDebugName(ButtonPopupTypes, popupType).." runPass="..SC_BoolText(runPassAfterPopup))
		end
		if runPassAfterPopup then
			SC_RunTakeoverPass(player, "popup", false)
		end
		SC_UpdatePanel()
	else
		SC_Debug("popup unhandled type="..SC_GetEnumDebugName(ButtonPopupTypes, popupType).." blocker="..SC_GetBlockingDebug(player))
	end
end
Events.SerialEventGameMessagePopup.Add(SC_OnPopupAutoHandle)

local function SC_ShouldRemoveNotification(notificationType)
	if NotificationTypes == nil or notificationType == nil then
		return false
	end
	return notificationType == NotificationTypes.NOTIFICATION_UNIT_PROMOTION
		or notificationType == NotificationTypes.NOTIFICATION_BARBARIAN
		or notificationType == NotificationTypes.NOTIFICATION_TECH
		or notificationType == NotificationTypes.NOTIFICATION_PRODUCTION
		or notificationType == NotificationTypes.NOTIFICATION_FREE_TECH
		or notificationType == NotificationTypes.NOTIFICATION_SPY_STOLE_TECH
		or notificationType == NotificationTypes.NOTIFICATION_FREE_POLICY
		or notificationType == NotificationTypes.NOTIFICATION_FREE_GREAT_PERSON
		or notificationType == NotificationTypes.NOTIFICATION_FOUND_PANTHEON
		or notificationType == NotificationTypes.NOTIFICATION_FOUND_RELIGION
		or notificationType == NotificationTypes.NOTIFICATION_ENHANCE_RELIGION
		or notificationType == NotificationTypes.NOTIFICATION_ADD_REFORMATION_BELIEF
		or notificationType == NotificationTypes.NOTIFICATION_MAYA_LONG_COUNT
		or notificationType == NotificationTypes.NOTIFICATION_FAITH_GREAT_PERSON
		or notificationType == NotificationTypes.NOTIFICATION_CITY_RANGE_ATTACK
		or notificationType == NotificationTypes.NOTIFICATION_DIPLO_VOTE
		or notificationType == NotificationTypes.NOTIFICATION_TECH_AWARD
		or notificationType == NotificationTypes.NOTIFICATION_WONDER_COMPLETED_ACTIVE_PLAYER
		or notificationType == NotificationTypes.NOTIFICATION_WONDER_COMPLETED
		or notificationType == NotificationTypes.NOTIFICATION_WONDER_BEATEN
		or notificationType == NotificationTypes.NOTIFICATION_PROJECT_COMPLETED
		or notificationType == NotificationTypes.NOTIFICATION_GOLDEN_AGE_BEGUN_ACTIVE_PLAYER
		or notificationType == NotificationTypes.NOTIFICATION_GOLDEN_AGE_ENDED_ACTIVE_PLAYER
		or notificationType == NotificationTypes.NOTIFICATION_GREAT_PERSON_ACTIVE_PLAYER
		or notificationType == NotificationTypes.NOTIFICATION_OTHER_PLAYER_NEW_ERA
		or notificationType == NotificationTypes.NOTIFICATION_LEAGUE_CALL_FOR_PROPOSALS
		or notificationType == NotificationTypes.NOTIFICATION_LEAGUE_CALL_FOR_VOTES
		or notificationType == NotificationTypes.NOTIFICATION_LEAGUE_VOTING_SOON
		or notificationType == NotificationTypes.NOTIFICATION_LEAGUE_VOTING_DONE
		or notificationType == NotificationTypes.NOTIFICATION_LEAGUE_PROJECT_COMPLETE
		or notificationType == NotificationTypes.NOTIFICATION_LEAGUE_PROJECT_PROGRESS
		or notificationType == NotificationTypes.NOTIFICATION_GREAT_WORK_COMPLETED_ACTIVE_PLAYER
		or notificationType == NotificationTypes.NOTIFICATION_CHOOSE_ARCHAEOLOGY
		or notificationType == NotificationTypes.NOTIFICATION_CHOOSE_IDEOLOGY
end

function SC_GetNotificationDebugName(notificationType)
	return SC_GetEnumDebugName(NotificationTypes, notificationType)
end

function SC_QueueNotification(id, notificationType, toolTip, summary, gameValue, extraGameData)
	if id == nil or notificationType == nil then
		return false
	end
	local key = tostring(id).."|"..tostring(notificationType)
	if SC_NOTIFICATION_QUEUE_KEYS[key] then
		return false
	end
	SC_NOTIFICATION_QUEUE_KEYS[key] = true
	table.insert(SC_NOTIFICATION_QUEUE, {
		id = id,
		notificationType = notificationType,
		toolTip = toolTip,
		summary = summary,
		gameValue = gameValue,
		extraGameData = extraGameData,
		key = key
	})
	SC_Debug("notification queued id="..tostring(id)..
		" type="..SC_GetNotificationDebugName(notificationType)..
		" summary="..tostring(summary)..
		" gameValue="..tostring(gameValue)..
		" extra="..tostring(extraGameData))
	return true
end

function SC_RemoveNotification(id, reason)
	if id == nil or id < 0 then
		return false
	end
	local removed = false
	if UI ~= nil and UI.RemoveNotification ~= nil then
		local ok = pcall(function() UI.RemoveNotification(id) end)
		removed = removed or ok
	end
	if not removed and Events ~= nil and Events.NotificationRemoved ~= nil then
		local ok = pcall(function() Events.NotificationRemoved(id) end)
		removed = removed or ok
	end
	SC_Debug("notification remove id="..tostring(id)..
		" reason="..tostring(reason)..
		" ok="..SC_BoolText(removed))
	return removed
end

function SC_GetPlayerUnitByID(player, unitID)
	if player == nil or unitID == nil or unitID < 0 then
		return nil
	end
	for unit in player:Units() do
		if unit ~= nil and not unit:IsDead() then
			local id = nil
			pcall(function() id = unit:GetID() end)
			if id == unitID then
				return unit
			end
		end
	end
	return nil
end

function SC_HandleNotificationDecision(player, notificationType, gameValue, extraGameData)
	if player == nil or NotificationTypes == nil then
		return 0
	end
	if notificationType == NotificationTypes.NOTIFICATION_UNIT_PROMOTION then
		local unit = SC_GetPlayerUnitByID(player, extraGameData)
		if unit ~= nil then
			return SC_TryPromoteUnit(unit, "notification") and 1 or 0
		end
		return SC_AutomateUnitPromotions(player)
	elseif notificationType == NotificationTypes.NOTIFICATION_TECH
		or notificationType == NotificationTypes.NOTIFICATION_FREE_TECH
		or notificationType == NotificationTypes.NOTIFICATION_SPY_STOLE_TECH then
		return SC_AutomateResearch(player)
	elseif notificationType == NotificationTypes.NOTIFICATION_PRODUCTION then
		return SC_AutomateCities(player, SC_PlayerAtWar(player))
	elseif notificationType == NotificationTypes.NOTIFICATION_CITY_RANGE_ATTACK then
		return SC_AutomateCityRangedStrike(player, SC_PlayerAtWar(player))
	elseif notificationType == NotificationTypes.NOTIFICATION_GREAT_PERSON_ACTIVE_PLAYER then
		return SC_AutomateFinalUnitOrders(player, SC_PlayerAtWar(player))
	elseif notificationType == NotificationTypes.NOTIFICATION_FREE_POLICY then
		return SC_AutomateIdeology(player) + SC_AutomatePolicy(player)
	elseif notificationType == NotificationTypes.NOTIFICATION_FREE_GREAT_PERSON then
		return SC_HandleFreeGreatPersonPopup(player, false) and 1 or 0
	elseif notificationType == NotificationTypes.NOTIFICATION_FAITH_GREAT_PERSON then
		return SC_HandleFreeGreatPersonPopup(player, true) and 1 or 0
	elseif notificationType == NotificationTypes.NOTIFICATION_MAYA_LONG_COUNT then
		return SC_HandleMayaBonusPopup(player) and 1 or 0
	elseif notificationType == NotificationTypes.NOTIFICATION_FOUND_PANTHEON then
		return SC_HandlePantheonPopup({Data2 = true}) and 1 or 0
	elseif notificationType == NotificationTypes.NOTIFICATION_ADD_REFORMATION_BELIEF then
		return SC_HandlePantheonPopup({Data2 = false}) and 1 or 0
	elseif notificationType == NotificationTypes.NOTIFICATION_FOUND_RELIGION or notificationType == NotificationTypes.NOTIFICATION_ENHANCE_RELIGION then
		local city = player:GetCapitalCity()
		if city == nil then
			return 0
		end
		local popupInfo = {Data1 = city:GetX(), Data2 = city:GetY(), Option1 = notificationType == NotificationTypes.NOTIFICATION_FOUND_RELIGION}
		return SC_HandleReligionPopup(player, popupInfo) and 1 or 0
	elseif notificationType == NotificationTypes.NOTIFICATION_CHOOSE_ARCHAEOLOGY then
		local artifactID = extraGameData
		if artifactID == nil or artifactID < 0 then
			artifactID = gameValue
		end
		if artifactID == nil or artifactID < 0 then
			return 0
		end
		return SC_HandleArchaeologyPopup(player, {Data2 = artifactID}) and 1 or 0
	elseif notificationType == NotificationTypes.NOTIFICATION_CHOOSE_IDEOLOGY then
		return SC_AutomateIdeology(player)
	elseif notificationType == NotificationTypes.NOTIFICATION_DIPLO_VOTE then
		return SC_AutomateDiploVote(player)
	end
	return 0
end

SC_ProcessNotificationQueue = function(player, reason)
	if player == nil or not SC_IsTakeoverActive() or not SC_GetConfig("AutoPopupHandling", true) then
		return 0
	end
	if SC_NOTIFICATION_PROCESSING then
		return 0
	end
	if SC_NOTIFICATION_QUEUE == nil or #SC_NOTIFICATION_QUEUE == 0 then
		return 0
	end
	SC_NOTIFICATION_PROCESSING = true
	local processed = 0
	local kept = {}
	local maxPerPass = SC_GetConfig("MaxNotificationsPerPass", 40)
	for _, item in ipairs(SC_NOTIFICATION_QUEUE) do
		if processed < maxPerPass then
			local handled = 0
			local okHandle, handleResult = pcall(function()
				return SC_HandleNotificationDecision(player, item.notificationType, item.gameValue, item.extraGameData)
			end)
			if okHandle then
				handled = handleResult or 0
			else
				SC_Debug("notification decision-error id="..tostring(item.id)..
					" type="..SC_GetNotificationDebugName(item.notificationType)..
					" err="..tostring(handleResult))
			end
			local removed = false
			if SC_ShouldRemoveNotification(item.notificationType) then
				removed = SC_RemoveNotification(item.id, reason)
			end
			SC_Debug("notification processed id="..tostring(item.id)..
				" type="..SC_GetNotificationDebugName(item.notificationType)..
				" reason="..tostring(reason)..
				" handled="..tostring(handled)..
				" removed="..SC_BoolText(removed))
			SC_NOTIFICATION_QUEUE_KEYS[item.key] = nil
			processed = processed + 1
		else
			table.insert(kept, item)
		end
	end
	SC_NOTIFICATION_QUEUE = kept
	SC_NOTIFICATION_PROCESSING = false
	return processed
end

local function SC_OnNotificationAdded(id, notificationType, toolTip, summary, gameValue, extraGameData)
	if SC_IsDemonstrationLoggingActive ~= nil and SC_IsDemonstrationLoggingActive() then
		SC_DemoLog("notification", "id="..tostring(id)..
			" type="..SC_GetNotificationDebugName(notificationType)..
			" summary="..SC_SanitizeDemoText(summary)..
			" gameValue="..tostring(gameValue)..
			" extra="..tostring(extraGameData))
	end
	if not SC_IsTakeoverActive() or not SC_GetConfig("AutoPopupHandling", true) then
		return
	end
	SC_QueueNotification(id, notificationType, toolTip, summary, gameValue, extraGameData)
end
-- Running the full takeover pass from NotificationAdded is unsafe: Civ V can
-- raise notifications while combat, popups, or turn activation are mid-stack.
-- Queue only here; normal takeover passes and retry ticks process the queue.
Events.NotificationAdded.Add(SC_OnNotificationAdded)

SC_TryCloseDiplomacy = function(reason)
	local rootBefore = "?"
	local rootAfter = "?"
	pcall(function() rootBefore = SC_BoolText(UI.GetLeaderHeadRootUp()) end)
	local rootOK, rootErr = pcall(function() UI.SetLeaderHeadRootUp(false) end)
	local leaveOK, leaveErr = pcall(function() UI.RequestLeaveLeader() end)
	pcall(function() rootAfter = SC_BoolText(UI.GetLeaderHeadRootUp()) end)
	SC_Debug("diplomacy close reason="..tostring(reason)..
		" player=P"..tostring(SC_DIPLO_CLOSE_PLAYER)..
		" root="..tostring(rootBefore).."->"..tostring(rootAfter)..
		" rootOK="..SC_BoolText(rootOK)..
		" leaveOK="..SC_BoolText(leaveOK)..
		" err="..tostring(rootErr or leaveErr))
	return rootOK or leaveOK
end

local function SC_OnAILeaderMessage(iPlayer, iDiploUIState, szLeaderMessage, iAnimationAction, iData1)
	if SC_IsDemonstrationLoggingActive ~= nil and SC_IsDemonstrationLoggingActive() then
		SC_DemoLog("diplomacy", "event=AILeaderMessage player=P"..tostring(iPlayer)..
			" state="..tostring(iDiploUIState)..
			" animation="..tostring(iAnimationAction)..
			" data1="..tostring(iData1)..
			" message="..SC_SanitizeDemoText(szLeaderMessage))
	end
	if not SC_IsTakeoverActive() or not SC_GetConfig("AutoPopupHandling", true) then
		return
	end
	local activePlayer = SC_GetActiveHuman()
	if activePlayer == nil or iPlayer == nil or iPlayer == Game.GetActivePlayer() then
		return
	end
	SC_LAST_DIPLO_HANDLED = SC_LAST_DIPLO_HANDLED + 1
	SC_DIPLO_CLOSE_PLAYER = iPlayer
	SC_DIPLO_CLOSE_PENDING_TICKS = 8
	SC_TryCloseDiplomacy("leader-message:state="..tostring(iDiploUIState))
end
Events.AILeaderMessage.Add(SC_OnAILeaderMessage)

function SC_OnDemoPlayerDoTurn(playerID)
	local ok, err = pcall(function()
		if not SC_IsDemonstrationLoggingActive() then
			return
		end
		local player = Players[playerID]
		if player == nil then
			SC_DemoLog("turn", "event=PlayerDoTurn player=P"..tostring(playerID).." missing=true")
			return
		end
		SC_DemoLog("turn", "event=PlayerDoTurn "..SC_GetPlayerDemoLabel(player)..
			" alive="..SC_BoolText(player:IsAlive())..
			" active="..SC_BoolText(playerID == Game.GetActivePlayer())..
			" units="..tostring(SC_CountPlayerUnits(player))..
			" cities="..tostring(SC_CountPlayerCities(player))..
			" atWarActive="..SC_BoolText(SC_PlayerAtWarWithActive(player)))
		if SC_GetConfig("DemonstrationSnapshotOnEveryPlayerDoTurn", false) and player:IsAlive() then
			SC_DemoAuditWorld("playerDoTurn:P"..tostring(playerID), SC_GetConfig("DemonstrationFullSnapshots", true))
		end
	end)
	if not ok then
		SC_Debug("DEMO category=error event=PlayerDoTurn err="..tostring(err))
	end
end

GameEvents.PlayerDoTurn.Add(SC_OnDemoPlayerDoTurn)

local function SC_OnPlayerDoTurnV11(playerID)
	local ok, err = pcall(function()
		if not SC_GetConfig("Enabled", true) or not SC_IsHumanActivePlayer(playerID) then
			return
		end
		if SC_IsDemonstrationLoggingActive ~= nil and SC_IsDemonstrationLoggingActive() then
			SC_DemoAuditWorld("humanPlayerDoTurn:P"..tostring(playerID), SC_GetConfig("DemonstrationFullSnapshots", true))
		end
		SC_Debug("PlayerDoTurn event player="..tostring(playerID).." remaining="..tostring(SC_GetConfig("TakeoverTurnsRemaining", 0)))
		if not SC_IsTakeoverActive() then
			SC_Debug("PlayerDoTurn inactive")
			SC_UpdatePanel()
			return
		end
		local currentTurn = Game.GetGameTurn()
		if SC_LOAD_TURN >= 0 and currentTurn <= SC_LOAD_TURN + SC_GetConfig("StartDelayTurns", 1) then
			SC_Debug("PlayerDoTurn delayed currentTurn="..tostring(currentTurn).." loadTurn="..tostring(SC_LOAD_TURN))
			return
		end
		local player = Players[playerID]
		local results, cityDetails, atWar = SC_RunTakeoverPass(player, "playerDoTurn", false)
		results = results or {}
		cityDetails = cityDetails or {}
		SC_SendNationalBrief(player, results, cityDetails, atWar)
		local remaining = math.max(SC_GetSafeNumber(function() return SC_CONFIG.TakeoverTurnsRemaining end, 0) - 1, 0)
		SC_CONFIG.TakeoverTurnsRemaining = remaining
		SC_SaveTakeoverState()
		if remaining <= 0 and player ~= nil then
			SC_SendNotification(player, "战略托管", "本轮托管已完成。")
		end
		SC_UpdatePanel()
	end)
	if not ok then
		SC_Log("v1.1 PlayerDoTurn failed: "..tostring(err))
	end
end
GameEvents.PlayerDoTurn.Add(SC_OnPlayerDoTurnV11)

local function SC_OnActivePlayerTurnStartV11()
	local ok, err = pcall(function()
		local player = SC_GetActiveHuman()
		if player == nil or not SC_GetConfig("Enabled", true) then
			return
		end
		if SC_IsDemonstrationLoggingActive ~= nil and SC_IsDemonstrationLoggingActive() then
			SC_DemoAuditWorld("activePlayerTurnStart", SC_GetConfig("DemonstrationFullSnapshots", true))
		end
		SC_Debug("ActivePlayerTurnStart event remaining="..tostring(SC_GetConfig("TakeoverTurnsRemaining", 0)))
		if not SC_IsTakeoverActive() then
			SC_Debug("ActivePlayerTurnStart inactive")
			SC_UpdatePanel()
			return
		end
		SC_RunTakeoverPass(player, "activeTurnStart", true)
		SC_UpdatePanel()
	end)
	if not ok then
		SC_Log("v1.1 ActivePlayerTurnStart failed: "..tostring(err))
	end
end
Events.ActivePlayerTurnStart.Add(SC_OnActivePlayerTurnStartV11)

function SC_AuditInputSafe(action, detail)
	local ok, err = pcall(function()
		SC_AuditUserInput(action, detail)
	end)
	if not ok then
		SC_Debug("USERINPUT audit-error action="..tostring(action).." err="..tostring(err))
	end
end

function SC_AuditMsgEquals(enumTable, key, value)
	return enumTable ~= nil and enumTable[key] ~= nil and value == enumTable[key]
end

function SC_InputAuditHandler(uiMsg, wParam, lParam)
	local action = nil
	if SC_AuditMsgEquals(MouseEvents, "LButtonDown", uiMsg) then
		action = "mouse-left-down"
	elseif SC_AuditMsgEquals(MouseEvents, "LButtonUp", uiMsg) then
		action = "mouse-left-up"
	elseif SC_AuditMsgEquals(MouseEvents, "LButtonDoubleClick", uiMsg) then
		action = "mouse-left-double"
	elseif SC_AuditMsgEquals(MouseEvents, "RButtonDown", uiMsg) then
		action = "mouse-right-down"
	elseif SC_AuditMsgEquals(MouseEvents, "RButtonUp", uiMsg) then
		action = "mouse-right-up"
	elseif SC_AuditMsgEquals(KeyEvents, "KeyDown", uiMsg) then
		action = "key-down"
	elseif SC_AuditMsgEquals(KeyEvents, "KeyUp", uiMsg) then
		action = "key-up"
	elseif SC_AuditMsgEquals(KeyEvents, "WM_KEYDOWN", uiMsg) then
		action = "key-down"
	elseif SC_AuditMsgEquals(KeyEvents, "WM_KEYUP", uiMsg) then
		action = "key-up"
	end
	if action ~= nil then
		SC_RECENT_PLAYER_INPUT_EVENTS = 4
		SC_AuditInputSafe(action, "uiMsg="..SC_GetEnumDebugName(MouseEvents, uiMsg)..
			" keyMsg="..SC_GetEnumDebugName(KeyEvents, uiMsg)..
			" wParam="..SC_GetEnumDebugName(Keys, wParam)..
			" lParam="..tostring(lParam))
	end
	return false
end

function SC_OnUnitSelectionAudit(playerID, unitID, hexX, hexY, unitType, isSelected, isEditable)
	if isSelected ~= true or playerID ~= Game.GetActivePlayer() then
		return
	end
	local demoActive = SC_IsDemonstrationLoggingActive ~= nil and SC_IsDemonstrationLoggingActive()
	if SC_RECENT_PLAYER_INPUT_EVENTS <= 0 and not demoActive then
		return
	end
	if SC_RECENT_PLAYER_INPUT_EVENTS > 0 then
		SC_RECENT_PLAYER_INPUT_EVENTS = SC_RECENT_PLAYER_INPUT_EVENTS - 1
	end
	SC_AuditInputSafe("unit-selection", "player="..tostring(playerID)..
		" unit="..tostring(unitID)..
		" hex="..tostring(hexX)..","..tostring(hexY)..
		" editable="..SC_BoolText(isEditable == true))
end

function SC_OnUnitSelectionClearedAudit()
	local demoActive = SC_IsDemonstrationLoggingActive ~= nil and SC_IsDemonstrationLoggingActive()
	if SC_RECENT_PLAYER_INPUT_EVENTS <= 0 and not demoActive then
		return
	end
	if SC_RECENT_PLAYER_INPUT_EVENTS > 0 then
		SC_RECENT_PLAYER_INPUT_EVENTS = SC_RECENT_PLAYER_INPUT_EVENTS - 1
	end
	SC_AuditInputSafe("unit-selection-cleared", "")
end

function SC_OnEnterCityScreenAudit()
	SC_AuditInputSafe("enter-city-screen", "")
end

function SC_OnExitCityScreenAudit()
	SC_AuditInputSafe("exit-city-screen", "")
end

function SC_OnPopupProcessedAudit(popupType, data)
	if SC_LAST_UNHANDLED_POPUP == nil or SC_LAST_UNHANDLED_POPUP == "none" then
		return
	end
	SC_AuditInputSafe("popup-processed", "type="..SC_GetEnumDebugName(ButtonPopupTypes, popupType).." data="..tostring(data).." lastUnhandled="..tostring(SC_LAST_UNHANDLED_POPUP))
end

function SC_AuditControlCallback(name, callback)
	return function()
		SC_AuditInputSafe("sc-button", tostring(name))
		if callback ~= nil then
			return callback()
		end
	end
end

function SC_DemoLogArgs(category, eventName, ...)
	if not SC_IsDemonstrationLoggingActive() then
		return
	end
	local parts = {"event="..tostring(eventName)}
	for i = 1, select("#", ...), 1 do
		table.insert(parts, "a"..tostring(i).."="..SC_SanitizeDemoText(select(i, ...)))
	end
	SC_DemoLog(category, table.concat(parts, " "))
end

function SC_RegisterDemoEvent(sourceTable, eventName, category)
	if sourceTable == nil or eventName == nil or sourceTable[eventName] == nil or sourceTable[eventName].Add == nil then
		return false
	end
	local ok = pcall(function()
		sourceTable[eventName].Add(function(...)
			SC_DemoLogArgs(category or "event", eventName, ...)
		end)
	end)
	return ok
end

if ContextPtr ~= nil and ContextPtr.SetInputHandler ~= nil then
	ContextPtr:SetInputHandler(SC_InputAuditHandler)
end

if Events ~= nil then
	SC_RegisterDemoEvent(Events, "SerialEventUnitCreated", "unitEvent")
	SC_RegisterDemoEvent(Events, "SerialEventUnitDestroyed", "unitEvent")
	SC_RegisterDemoEvent(Events, "SerialEventUnitMoveToHexes", "unitEvent")
	SC_RegisterDemoEvent(Events, "SerialEventUnitSetDamage", "unitEvent")
	SC_RegisterDemoEvent(Events, "SerialEventCityCreated", "cityEvent")
	SC_RegisterDemoEvent(Events, "SerialEventCityDestroyed", "cityEvent")
	SC_RegisterDemoEvent(Events, "SerialEventCityInfoDirty", "cityEvent")
	SC_RegisterDemoEvent(Events, "SerialEventHexCultureChanged", "mapEvent")
	SC_RegisterDemoEvent(Events, "WarStateChanged", "diplomacy")
	SC_RegisterDemoEvent(Events, "ResearchCompleted", "research")
	SC_RegisterDemoEvent(Events, "TechAcquired", "research")
	if Events.UnitSelectionChanged ~= nil then
		pcall(function() Events.UnitSelectionChanged.Add(SC_OnUnitSelectionAudit) end)
	end
	if Events.UnitSelectionCleared ~= nil then
		pcall(function() Events.UnitSelectionCleared.Add(SC_OnUnitSelectionClearedAudit) end)
	end
	if Events.SerialEventEnterCityScreen ~= nil then
		pcall(function() Events.SerialEventEnterCityScreen.Add(SC_OnEnterCityScreenAudit) end)
	end
	if Events.SerialEventExitCityScreen ~= nil then
		pcall(function() Events.SerialEventExitCityScreen.Add(SC_OnExitCityScreenAudit) end)
	end
	if Events.SerialEventGameMessagePopupProcessed ~= nil then
		pcall(function() Events.SerialEventGameMessagePopupProcessed.Add(SC_OnPopupProcessedAudit) end)
	end
end

local function SC_OnCityCaptureCompleteStrategic(oldOwner, isCapital, x, y, newOwner, pop, conquest)
	local ok, err = pcall(function()
		local activeID = -1
		pcall(function() activeID = Game.GetActivePlayer() end)
		if newOwner ~= activeID or Map == nil then
			return
		end
		local plot = Map.GetPlot(x, y)
		if plot == nil then
			return
		end
		local city = nil
		pcall(function() city = plot:GetPlotCity() end)
		if city == nil then
			return
		end
		local damage, maxHP, ratio = SC_GetCityDamageInfo(city)
		if maxHP == nil or maxHP <= 0 then
			return
		end
		local targetDamage = math.floor(maxHP * SC_GetConfig("CapturedCityMaxDamageRatio", 0.45))
		if damage <= targetDamage then
			SC_Debug("capturedCity secure-skip plot="..SC_GetPlotDebug(plot).." damage="..tostring(damage).."/"..tostring(maxHP).." ratio="..tostring(ratio))
			return
		end
		local fixed = false
		local setOk = pcall(function() city:SetDamage(targetDamage) end)
		if setOk then
			fixed = true
		else
			local change = targetDamage - damage
			local changeOk = pcall(function() city:ChangeDamage(change) end)
			fixed = changeOk
		end
		SC_Debug("capturedCity secure plot="..SC_GetPlotDebug(plot).." oldOwner=P"..tostring(oldOwner).." newOwner=P"..tostring(newOwner).." damage="..tostring(damage).."->"..tostring(targetDamage).." maxHP="..tostring(maxHP).." fixed="..SC_BoolText(fixed))
	end)
	if not ok then
		SC_Debug("capturedCity secure-error err="..tostring(err))
	end
end

if GameEvents ~= nil then
	if GameEvents.CityCaptureComplete ~= nil then
		pcall(function() GameEvents.CityCaptureComplete.Add(SC_OnCityCaptureCompleteStrategic) end)
	end
	SC_RegisterDemoEvent(GameEvents, "UnitSetXY", "unitEvent")
	SC_RegisterDemoEvent(GameEvents, "UnitCreated", "unitEvent")
	SC_RegisterDemoEvent(GameEvents, "UnitPrekill", "unitEvent")
	if GameEvents.UnitPrekill ~= nil then
		pcall(function()
			GameEvents.UnitPrekill.Add(function(playerID, unitID, unitType)
				if SC_StrategyRecordUnitLoss ~= nil then SC_StrategyRecordUnitLoss(playerID, unitID, unitType) end
			end)
		end)
	end
	SC_RegisterDemoEvent(GameEvents, "UnitKilledInCombat", "unitEvent")
	SC_RegisterDemoEvent(GameEvents, "UnitPromoted", "unitEvent")
	SC_RegisterDemoEvent(GameEvents, "CityFounded", "cityEvent")
	SC_RegisterDemoEvent(GameEvents, "CityCaptureComplete", "cityEvent")
	SC_RegisterDemoEvent(GameEvents, "CityTrained", "cityEvent")
	SC_RegisterDemoEvent(GameEvents, "TeamSetHasTech", "research")
	SC_RegisterDemoEvent(GameEvents, "PlayerAdoptPolicy", "policy")
	SC_RegisterDemoEvent(GameEvents, "PlayerAdoptPolicyBranch", "policy")
	SC_RegisterDemoEvent(GameEvents, "PlayerGoldenAge", "playerEvent")
	SC_RegisterDemoEvent(GameEvents, "PlayerDoneTurn", "turn")
end

if Controls ~= nil then
	Controls.CommandButton:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("CommandButton", SC_TogglePanel))
	Controls.CloseButton:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("CloseButton", SC_ClosePanel))
	Controls.Takeover5Button:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("Takeover5Button", function() SC_StartTakeover(5) SC_UpdatePanel() end))
	Controls.Takeover10Button:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("Takeover10Button", function() SC_StartTakeover(10) SC_UpdatePanel() end))
	Controls.Takeover20Button:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("Takeover20Button", function() SC_StartTakeover(20) SC_UpdatePanel() end))
	Controls.Takeover50Button:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("Takeover50Button", function() SC_StartTakeover(50) SC_UpdatePanel() end))
	Controls.StopTakeoverButton:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("StopTakeoverButton", function() SC_StopTakeover() SC_UpdatePanel() end))
	Controls.DiplomacyProfileButton:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("DiplomacyProfileButton", function() SC_SelectProfile("DiplomacyProfile") SC_UpdatePanel() end))
	Controls.EconomyProfileButton:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("EconomyProfileButton", function() SC_SelectProfile("EconomyProfile") SC_UpdatePanel() end))
	Controls.BuildProfileButton:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("BuildProfileButton", function() SC_SelectProfile("BuildProfile") SC_UpdatePanel() end))
	Controls.DevelopmentProfileButton:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("DevelopmentProfileButton", function() SC_SelectProfile("DevelopmentProfile") SC_UpdatePanel() end))
	Controls.ProductionProfileButton:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("ProductionProfileButton", function() SC_SelectProfile("ProductionProfile") SC_UpdatePanel() end))
	Controls.WarProfileButton:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("WarProfileButton", function() SC_SelectProfile("WarProfile") SC_UpdatePanel() end))
	Controls.CapturedCityProfileButton:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("CapturedCityProfileButton", function() SC_SelectProfile("CapturedCityAction") SC_UpdatePanel() end))
	Controls.GreatPersonProfileButton:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("GreatPersonProfileButton", function() SC_SelectProfile("GreatPersonProfile") SC_UpdatePanel() end))
	Controls.ReligionProfileButton:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("ReligionProfileButton", function() SC_SelectProfile("ReligionProfile") SC_UpdatePanel() end))
	Controls.TradeProfileButton:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("TradeProfileButton", function() SC_SelectProfile("TradeProfile") SC_UpdatePanel() end))
	Controls.ProfileOption1Button:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("ProfileOption1Button", function() SC_SetProfileOption(SC_GetConfig("SelectedProfileKey", "DiplomacyProfile"), 1) SC_UpdatePanel() end))
	Controls.ProfileOption2Button:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("ProfileOption2Button", function() SC_SetProfileOption(SC_GetConfig("SelectedProfileKey", "DiplomacyProfile"), 2) SC_UpdatePanel() end))
	Controls.ProfileOption3Button:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("ProfileOption3Button", function() SC_SetProfileOption(SC_GetConfig("SelectedProfileKey", "DiplomacyProfile"), 3) SC_UpdatePanel() end))
	Controls.ProfileOption4Button:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("ProfileOption4Button", function() SC_SetProfileOption(SC_GetConfig("SelectedProfileKey", "DiplomacyProfile"), 4) SC_UpdatePanel() end))
	Controls.BalancedButton:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("BalancedButton", function() SC_SetDoctrine("BALANCED") end))
	Controls.ScienceButton:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("ScienceButton", function() SC_SetDoctrine("SCIENCE") end))
	Controls.IndustryButton:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("IndustryButton", function() SC_SetDoctrine("INDUSTRY") end))
	Controls.WarButton:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("WarButton", function() SC_SetDoctrine("WAR") end))
	Controls.ResearchAutomationButton:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("ResearchAutomationButton", SC_ToggleResearchAutomation))
	Controls.PolicyAutomationButton:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("PolicyAutomationButton", SC_TogglePolicyAutomation))
	Controls.CityAutomationButton:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("CityAutomationButton", SC_ToggleCityAutomation))
	Controls.DefenseAutomationButton:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("DefenseAutomationButton", SC_ToggleDefenseAutomation))
	Controls.CityStrikeAutomationButton:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("CityStrikeAutomationButton", SC_ToggleCityStrikeAutomation))
	Controls.UpgradeAutomationButton:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("UpgradeAutomationButton", SC_ToggleUpgradeAutomation))
	Controls.PromoteAutomationButton:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("PromoteAutomationButton", SC_TogglePromoteAutomation))
	Controls.HealAutomationButton:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("HealAutomationButton", SC_ToggleHealAutomation))
	Controls.MoveAutomationButton:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("MoveAutomationButton", SC_ToggleMoveAutomation))
	Controls.AutoEndTurnButton:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("AutoEndTurnButton", SC_ToggleAutoEndTurn))
	Controls.PopupAutomationButton:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("PopupAutomationButton", SC_TogglePopupAutomation))
	Controls.IdlePostureAutomationButton:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("IdlePostureAutomationButton", SC_ToggleIdlePostureAutomation))
	Controls.RunOnceButton:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("RunOnceButton", SC_RunOnce))
	Controls.BriefButton:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("BriefButton", SC_BriefNow))
	Controls.OpenTechButton:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("OpenTechButton", SC_OpenTechTree))
	Controls.OpenPolicyButton:RegisterCallback(Mouse.eLClick, SC_AuditControlCallback("OpenPolicyButton", SC_OpenPolicies))
	SC_LoadTakeoverState()
	SC_UpdatePanel()
end

SC_Log("Strategic Command v"..SC_VERSION.." loaded.")
