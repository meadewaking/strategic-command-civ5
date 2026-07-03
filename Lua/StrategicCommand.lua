-- Strategic Command
-- A high-level automation layer for late-game play.

include("StrategicCommand_Config.lua")

local SC_VERSION = "1.29"
local SC_LOAD_TURN = -1
local SC_SAVE_DATA = nil
local SC_TAKEOVER_SAVE_KEY = "SC_TAKEOVER_REMAINING"
local SC_CAPTURED_CITY_SAVE_KEY = "SC_CAPTURED_CITY_ACTION"
local SC_LAST_TAKEOVER_PASS_TURN = -1
local SC_LAST_TAKEOVER_PASS_COUNT = 0
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
SC_RANGE_TARGET_STRIKE_COUNT_THIS_TURN = {}
SC_STACK_MOVE_ATTEMPTED_THIS_TURN = {}
SC_FINAL_ORDER_ATTEMPTED_THIS_TURN = {}
SC_DIRECT_PUSH_FAILED_THIS_TURN = {}
SC_HEAL_FAILED_THIS_TURN = {}
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
SC_NOTIFICATION_QUEUE = {}
SC_NOTIFICATION_QUEUE_KEYS = {}
SC_NOTIFICATION_PROCESSING = false
local SC_UnitNeedsOrder = nil
local SC_GetUnitOrderDebug = nil
local SC_TryDirectTargetedMission = nil
SC_ProcessNotificationQueue = nil

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
	if SC_GetConfig("DebugUnitCommands", true) then
		local afterPlot = nil
		local afterMoves = "?"
		local afterActivity = "?"
		pcall(function() afterPlot = unit:GetPlot() end)
		pcall(function() afterMoves = tostring(unit:MovesLeft()) end)
		pcall(function() afterActivity = tostring(unit:GetActivityType()) end)
		SC_Debug("mission unit="..SC_GetUnitDebugLabel(unit)..
			" mission="..SC_GetEnumDebugName(MissionTypes, missionType)..
			" data="..tostring(data1)..","..tostring(data2)..
			" sentData="..tostring(sendData1)..","..tostring(sendData2)..
			" flags="..tostring(flags or 0)..
			" ok="..SC_BoolText(ok)..
			" err="..tostring(err)..
			" before="..SC_GetPlotDebug(beforePlot).."/m"..beforeMoves.."/a"..beforeActivity..
			" after="..SC_GetPlotDebug(afterPlot).."/m"..afterMoves.."/a"..afterActivity)
	end
	return ok
end

local function SC_SendUnitCommand(unit, commandType, data1, data2)
	if unit == nil or commandType == nil or Game == nil or Game.SelectionListGameNetMessage == nil or GameMessageTypes == nil then
		SC_Debug("command skip unit="..SC_GetUnitDebugLabel(unit).." command="..tostring(commandType).." reason=missing-api")
		return false
	end
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
	if SC_GetConfig("DebugUnitCommands", true) then
		local afterPlot = nil
		local afterMoves = "?"
		local afterActivity = "?"
		pcall(function() afterPlot = unit:GetPlot() end)
		pcall(function() afterMoves = tostring(unit:MovesLeft()) end)
		pcall(function() afterActivity = tostring(unit:GetActivityType()) end)
		SC_Debug("command unit="..SC_GetUnitDebugLabel(unit)..
			" command="..SC_GetEnumDebugName(CommandTypes, commandType)..
			" data="..tostring(data1)..","..tostring(data2)..
			" sentData="..tostring(sendData1)..","..tostring(sendData2)..
			" ok="..SC_BoolText(ok)..
			" err="..tostring(err)..
			" before="..SC_GetPlotDebug(beforePlot).."/m"..beforeMoves.."/a"..beforeActivity..
			" after="..SC_GetPlotDebug(afterPlot).."/m"..afterMoves.."/a"..afterActivity)
	end
	return ok
end

local function SC_TryMoveMission(unit, plot, reason, requirePlotChange)
	if unit == nil or plot == nil then
		return false
	end
	local mission = SC_GetMissionID("MISSION_MOVE_TO")
	if mission == nil then
		return false
	end
	local beforePlot = nil
	local beforeIndex = nil
	pcall(function() beforePlot = unit:GetPlot() end)
	pcall(function()
		if beforePlot ~= nil then
			beforeIndex = beforePlot:GetPlotIndex()
		end
	end)
	local ok = SC_SendUnitMission(unit, mission, plot:GetX(), plot:GetY())
	if not ok then
		return false
	end
	local afterPlot = nil
	local afterIndex = nil
	pcall(function() afterPlot = unit:GetPlot() end)
	pcall(function()
		if afterPlot ~= nil then
			afterIndex = afterPlot:GetPlotIndex()
		end
	end)
	local needsOrder = false
	if SC_UnitNeedsOrder ~= nil then
		needsOrder = SC_UnitNeedsOrder(unit)
	end
	local changedPlot = beforeIndex ~= nil and afterIndex ~= nil and beforeIndex ~= afterIndex
	local accepted = changedPlot or (not requirePlotChange and not needsOrder)
	if SC_GetConfig("DebugUnitCommands", true) then
		SC_Debug("moveMission unit="..SC_GetUnitDebugLabel(unit)..
			" reason="..tostring(reason)..
			" target="..SC_GetPlotDebug(plot)..
			" accepted="..SC_BoolText(accepted)..
			" changedPlot="..SC_BoolText(changedPlot)..
			" requirePlotChange="..SC_BoolText(requirePlotChange == true)..
			" state="..SC_GetUnitOrderDebug(unit))
	end
	if not accepted and SC_GetConfig("DirectPushMoveMissionFallback", true) then
		local directOk, directErr = pcall(function()
			unit:PushMission(mission, plot:GetX(), plot:GetY(), 0, 0, 1, mission, beforePlot, unit)
		end)
		local directAfterPlot = nil
		local directAfterIndex = nil
		pcall(function() directAfterPlot = unit:GetPlot() end)
		pcall(function()
			if directAfterPlot ~= nil then
				directAfterIndex = directAfterPlot:GetPlotIndex()
			end
		end)
		local directNeedsOrder = false
		if SC_UnitNeedsOrder ~= nil then
			directNeedsOrder = SC_UnitNeedsOrder(unit)
		end
		local directChangedPlot = beforeIndex ~= nil and directAfterIndex ~= nil and beforeIndex ~= directAfterIndex
		local directAccepted = directOk and (directChangedPlot or (not requirePlotChange and not directNeedsOrder))
		if SC_GetConfig("DebugUnitCommands", true) then
			SC_Debug("moveMission direct-fallback unit="..SC_GetUnitDebugLabel(unit)..
				" reason="..tostring(reason)..
				" target="..SC_GetPlotDebug(plot)..
				" ok="..SC_BoolText(directOk)..
				" err="..tostring(directErr)..
				" accepted="..SC_BoolText(directAccepted)..
				" changedPlot="..SC_BoolText(directChangedPlot)..
				" requirePlotChange="..SC_BoolText(requirePlotChange == true)..
				" state="..SC_GetUnitOrderDebug(unit))
		end
		if directAccepted then
			return true
		end
	end
	return accepted
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

local function SC_GetSafeNumber(callback, defaultValue)
	local ok, value = pcall(callback)
	if ok and value ~= nil then
		return value
	end
	return defaultValue or 0
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

function SC_GetUnitAuditSnapshot(unit)
	if unit == nil then
		return nil
	end
	local unitInfo = SC_GetUnitInfo(unit)
	local plot = nil
	pcall(function() plot = unit:GetPlot() end)
	local snapshot = {
		key = SC_GetUnitTurnKey(unit),
		label = SC_GetUnitDebugLabel(unit),
		role = SC_GetUnitRole(unit, unitInfo),
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
		" type="..tostring(snapshot.unitType)..
		" domain="..tostring(snapshot.domain)..
		" ai="..tostring(snapshot.ai)..
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
	if role == "carrier_air" or role == "fighter" or role == "bomber" then
		return SC_GetConfig("MaxAirTacticalActionsPerUnitPerTurn", 5)
	end
	if role == "missile" then
		return SC_GetConfig("MaxMissileTacticalActionsPerUnitPerTurn", 2)
	end
	if role == "missile_carrier" or role == "naval_ranged" or role == "submarine" then
		return SC_GetConfig("MaxNavalTacticalActionsPerUnitPerTurn", 4)
	end
	if role == "siege" or role == "land_ranged" then
		return SC_GetConfig("MaxLandRangedTacticalActionsPerUnitPerTurn", 3)
	end
	return defaultCap
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
		ERA_POSTMODERN = 6,
		ERA_FUTURE = 7
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
	if unitInfo.Era ~= nil then
		local directRank = SC_GetEraRank(unitInfo.Era)
		if directRank >= 0 then
			return directRank
		end
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

local function SC_GetBestTrainableUnit(city, preferSea, preferAir, reservedOrders)
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
						local unitEraRank = SC_GetUnitEraRank(unitInfo)
						local power = SC_GetUnitPowerScore(unitInfo)
						local score = power * 2.2 + rangedCombat * 0.7 + math.max(cost, 0) / 10 + (unitInfo.Range or 0) * 18 + (unitInfo.Moves or 0) * 5 + math.max(unitEraRank, 0) * 35
						if reservedOrders ~= nil and reservedOrders[reserveKey] then
							reservedCount = reservedCount + 1
							score = score - SC_GetConfig("RepeatedUnitReservationPenalty", 15)
						end
						if playerEraRank >= 0 and unitEraRank >= playerEraRank - 1 then
							score = score + 90
						end
						if production == "AIRSEA" or war == "NAVAL" then
							if role == "carrier" then
								score = score + 260
							elseif role == "missile_carrier" then
								score = score + 230
							elseif role == "naval_ranged" then
								score = score + 170
							elseif role == "submarine" then
								score = score + 130
							elseif role == "fighter" or role == "bomber" or role == "carrier_air" then
								score = score + 160
							end
						elseif production == "MILITARY" or war == "ASSAULT" then
							if role == "fast_assault" then
								score = score + 150
							elseif role == "siege" or role == "land_ranged" then
								score = score + 110
							elseif role == "assault" then
								score = score + 60
							end
						elseif war == "DEFENSE" then
							if role == "land_ranged" or role == "siege" or role == "fighter" then
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

local function SC_ShouldBuildMilitary(player, city, atWar)
	local production = SC_GetConfig("ProductionProfile", "BUILDINGS")
	local war = SC_GetConfig("WarProfile", "ADVANCE")
	if not atWar and production ~= "MILITARY" and production ~= "AIRSEA" and war ~= "ASSAULT" then
		return false
	end
	local cityCount = math.max(SC_GetSafeNumber(function() return player:GetNumCities() end, 1), 1)
	local militaryCount = SC_GetSafeNumber(function() return player:GetNumMilitaryUnits() end, 0)
	local targetMilitary = math.max(cityCount * 5, 12)
	if SC_GetConfig("Doctrine", "BALANCED") == "WAR" then
		targetMilitary = math.max(cityCount * 8, 18)
	end
	if production == "MILITARY" or production == "AIRSEA" then
		targetMilitary = math.max(cityCount * 10, 24)
	end
	if war == "ASSAULT" then
		targetMilitary = math.max(cityCount * 12, 30)
	elseif war == "NAVAL" then
		targetMilitary = math.max(cityCount * 9, 24)
	end
	return militaryCount < targetMilitary
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

local function SC_RangeStrike(unit, plot)
	if unit == nil or plot == nil then
		return false
	end
	local unitInfo = SC_GetUnitInfo(unit)
	local role = SC_GetUnitRole(unit, unitInfo)
	local isAirAttack = unitInfo ~= nil and unitInfo.Domain == "DOMAIN_AIR"
	local moveMission = SC_GetMissionID("MISSION_MOVE_TO")
	local rangeMission = SC_GetMissionID("MISSION_RANGE_ATTACK")
	local unitKey = SC_GetUnitTurnKey(unit)
	local targetKey = tostring(plot:GetX())..","..tostring(plot:GetY())
	local cacheKey = tostring(unitKey or SC_GetUnitDebugLabel(unit)).."|"..targetKey
	local function getStrikeSnapshot()
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
		return after.moves < before.moves
			or after.damage ~= before.damage
			or after.activity ~= before.activity
			or after.x ~= before.x
			or after.y ~= before.y
	end
	local function finishIfStrikeResolved(before, method, allowOrderClear)
		local after = getStrikeSnapshot()
		local changed = strikeStateChanged(before, after)
		local needsOrder = SC_UnitNeedsOrder(unit)
		if changed or (allowOrderClear and not needsOrder) then
			local status = "queued"
			if changed then
				status = "fired"
			end
			SC_Debug("rangeStrike resolved unit="..SC_GetUnitDebugLabel(unit)..
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
		if SC_SendUnitMission(unit, missionType, plot:GetX(), plot:GetY()) then
			local resolved, status = finishIfStrikeResolved(before, reason, false)
			if resolved then
				return true, status
			end
			local directTried = false
			if SC_TryDirectTargetedMission ~= nil and SC_TryDirectTargetedMission(unit, missionType, plot, reason) then
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
	SC_Debug("rangeStrike native unit="..SC_GetUnitDebugLabel(unit)..
		" target="..SC_GetPlotDebug(plot)..
		" ok="..SC_BoolText(ok)..
		" err="..tostring(err))
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
	if SC_IsAssaultCaptureRole(role) then
		return true
	end
	unitInfo = unitInfo or SC_GetUnitInfo(unit)
	if unitInfo == nil or unitInfo.Domain ~= "DOMAIN_SEA" then
		return false
	end
	if role ~= "missile_carrier" and role ~= "naval_ranged" then
		return false
	end
	local unitType = unitInfo.Type or ""
	return SC_TextHas(unitType, "052D")
		or SC_TextHas(unitType, "DESTROYER")
		or SC_TextHas(unitType, "KIROV")
		or SC_TextHas(unitType, "CRUISER")
		or SC_TextHas(unitType, "BATTLECRUISER")
		or SC_TextHas(unitType, "BATTLESHIP")
		or SC_TextHas(unitType, "DREADNOUGHT")
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
	return cityMaxHP ~= nil and cityMaxHP > 0 and cityDamageRatio >= SC_GetConfig("CityCaptureReadyDamageRatio", 0.72)
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
							if (roleKind == "capture" and SC_CanActAsCityCaptureUnit(nearbyUnit, nearbyInfo, nearbyRole))
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
	if unitPlot == nil or targetPlot == nil then
		return -999999, "missing-plot"
	end
	local distance = Map.PlotDistance(unitPlot:GetX(), unitPlot:GetY(), targetPlot:GetX(), targetPlot:GetY())
	local score = 1000 - distance * 8
	local reasons = {"dist"..tostring(distance)}
	local coastalTarget = SC_IsCoastalAssaultPlot(targetPlot)
	local supportCount = 0
	local captureCount = 0
	if enemyUnit ~= nil then
		local enemyInfo = SC_GetUnitInfo(enemyUnit)
		local enemyRole = SC_GetUnitRole(enemyUnit, enemyInfo)
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
		local cityStrikeCount = SC_GetRangeTargetStrikeCount(targetPlot, "city", "all")
		local roleStrikeBucket = SC_GetRangeRoleStrikeBucket(role)
		local roleStrikeCount = SC_GetRangeTargetStrikeCount(targetPlot, "city", roleStrikeBucket)
		score = score + 700
		SC_AddScoreReason(reasons, "city", 700)
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
		if SC_GetSafeNumber(function() return enemyCity:IsCapital() and 1 or 0 end, 0) > 0 then
			score = score + 120
			SC_AddScoreReason(reasons, "capital", 120)
		end
		if cityDamageRatio >= SC_GetConfig("CityCaptureReadyDamageRatio", 0.72) and cityStrikeCount >= 2 then
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
	local bestPlot = nil
	local bestScore = -999999
	local stats = {
		enemyUnits = 0,
		enemyCities = 0,
		inRangeUnits = 0,
		inRangeCities = 0,
		outOfRange = 0,
		noPlot = 0,
		bestScore = nil,
		bestKind = nil
	}
	for otherID, otherPlayer in pairs(Players) do
		if otherPlayer ~= nil and otherPlayer:IsAlive() and team:IsAtWar(otherPlayer:GetTeam()) then
			for enemyUnit in otherPlayer:Units() do
				stats.enemyUnits = stats.enemyUnits + 1
				local plot = enemyUnit:GetPlot()
				if plot == nil then
					stats.noPlot = stats.noPlot + 1
				elseif SC_CanRangeStrikeAt(unit, plot) then
					stats.inRangeUnits = stats.inRangeUnits + 1
					local score, reason = SC_ScoreRangeTarget(player, unit, role, unitPlot, plot, enemyUnit, nil)
					if score > bestScore then
						bestScore = score
						bestPlot = plot
						stats.bestScore = score
						stats.bestKind = "unit"
						stats.bestReason = reason
					end
				else
					stats.outOfRange = stats.outOfRange + 1
				end
			end
			for city in otherPlayer:Cities() do
				stats.enemyCities = stats.enemyCities + 1
				local plot = city:Plot()
				if plot == nil then
					stats.noPlot = stats.noPlot + 1
				elseif SC_CanRangeStrikeAt(unit, plot) then
					stats.inRangeCities = stats.inRangeCities + 1
					local score, reason = SC_ScoreRangeTarget(player, unit, role, unitPlot, plot, nil, city)
					if score > bestScore then
						bestScore = score
						bestPlot = plot
						stats.bestScore = score
						stats.bestKind = "city"
						stats.bestReason = reason
					end
				else
					stats.outOfRange = stats.outOfRange + 1
				end
			end
		end
	end
	return bestPlot, bestScore, stats
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
	local function debugUnit(text)
		if SC_GetConfig("DebugUnitDecisions", true) and debugCount < debugLimit then
			debugCount = debugCount + 1
			SC_Debug(text)
		end
	end
	SC_Debug("localDefense start maxActions="..tostring(maxActions).." maxRounds="..tostring(maxRounds))
	for round = 1, maxRounds, 1 do
		local roundActions = 0
		for unit in player:Units() do
			if actions >= maxActions then
				SC_Debug("localDefense cap actions="..tostring(actions))
				return actions
			end
			if unit ~= nil then
				local unitInfo = SC_GetUnitInfo(unit)
				local role = SC_GetUnitRole(unit, unitInfo)
				local unitKey = SC_GetUnitTurnKey(unit)
				if SC_IsCombatAutomationUnit(unit, unitInfo) and unit:GetDamage() < SC_GetConfig("HealDamageThreshold", 45) then
					local canAct = SC_CanUnitActForTactical(unit, unitInfo)
					local actionCount = SC_GetTacticalActionCount(unitKey)
					local actionCap = SC_GetTacticalActionCapForUnit(unit, unitInfo, role)
					if unitKey ~= nil and actionCount >= actionCap then
						debugUnit("localDefense unit-cap unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role).." count="..tostring(actionCount).." cap="..tostring(actionCap))
					elseif canAct and SC_IsRangedAttackUnit(unit, unitInfo, role) then
						local cachedQueued = SC_GetValidTacticalQueuedCache(unit, unitKey)
						if cachedQueued ~= nil then
							debugUnit("localDefense queued-cached unit="..SC_GetUnitDebugLabel(unit).." "..SC_FormatTacticalQueuedCache(cachedQueued))
						else
						local cachedNoTarget = SC_GetValidTacticalNoTargetCache(unit, unitKey)
						if cachedNoTarget ~= nil then
							debugUnit("localDefense no-target-cached unit="..SC_GetUnitDebugLabel(unit).." "..SC_FormatTacticalNoTargetCache(cachedNoTarget))
						else
							local targetPlot, targetScore, targetStats = SC_FindRangeTarget(player, unit)
							local strikeDone = false
							local strikeStatus = "none"
							if targetPlot ~= nil then
								strikeDone, strikeStatus = SC_RangeStrike(unit, targetPlot)
							end
							if targetPlot ~= nil and strikeDone then
								local newCount = SC_RecordTacticalAction(unitKey)
								SC_RecordRangeTargetStrike(targetPlot, role, targetStats and targetStats.bestKind or nil)
								local label = "queued"
								if SC_IsStrikeStatusFired(strikeStatus) then
									label = "fired"
								end
								debugUnit("localDefense "..label.." round="..tostring(round).." unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role).." status="..tostring(strikeStatus).." count="..tostring(newCount).."/"..tostring(actionCap).." target="..SC_GetPlotDebug(targetPlot).." score="..tostring(targetScore).." reason="..tostring(targetStats and targetStats.bestReason or "nil"))
								if unitKey ~= nil then
									SC_TACTICAL_ORDERED_THIS_TURN[unitKey] = newCount
									if SC_IsStrikeStatusQueued(strikeStatus) then
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
								debugUnit("localDefense no-target unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role).." "..SC_GetRangeTargetStatsDebug(targetStats))
							else
								local newCount = SC_RecordTacticalAction(unitKey)
								debugUnit("localDefense fire-failed unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role).." status="..tostring(strikeStatus).." count="..tostring(newCount).."/"..tostring(actionCap).." target="..SC_GetPlotDebug(targetPlot).." score="..tostring(targetScore).." reason="..tostring(targetStats and targetStats.bestReason or "nil"))
								if unitKey ~= nil then
									SC_TACTICAL_ORDERED_THIS_TURN[unitKey] = newCount
								end
							end
						end
						end
					elseif not canAct then
						debugUnit("localDefense cannot-act unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role))
					else
						debugUnit("localDefense not-ranged unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role))
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
			if doctrine == "WAR" then
				score = score + SC_TechKeywordScore(techType, {"MILITARY", "BALLISTICS", "COMBUSTION", "FLIGHT", "RADAR", "ROCKETRY", "LASER", "STEALTH", "NUCLEAR", "ROBOTICS"}, 600)
			elseif doctrine == "SCIENCE" then
				score = score + SC_TechKeywordScore(techType, {"EDUCATION", "SCIENTIFIC", "ELECTRICITY", "PLASTICS", "COMPUTERS", "SATELLITES", "NANOTECHNOLOGY"}, 600)
			elseif doctrine == "INDUSTRY" then
				score = score + SC_TechKeywordScore(techType, {"METAL", "INDUSTRIALIZATION", "STEAM", "RAILROAD", "ELECTRICITY", "REPLACEABLE", "PLASTICS", "ECOLOGY"}, 600)
			else
				score = score + SC_TechKeywordScore(techType, {"EDUCATION", "INDUSTRIALIZATION", "ELECTRICITY", "PLASTICS", "RADAR", "COMPUTERS"}, 350)
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

local function SC_AutomateDamagedUnitHealing(player)
	if not SC_GetConfig("AutoHealDamagedUnits", false) or player == nil then
		return 0
	end
	local healed = 0
	local maxHeals = SC_GetConfig("MaxAutoHealsPerTurn", 12)
	local threshold = SC_GetConfig("HealDamageThreshold", 45)
	for unit in player:Units() do
		if healed >= maxHeals then
			return healed
		end
		if unit ~= nil and unit:IsCombatUnit() and unit:CanMove() and unit:GetDamage() >= threshold then
			local unitKey = SC_GetUnitTurnKey(unit)
			if unitKey ~= nil and SC_HEAL_FAILED_THIS_TURN[unitKey] then
				if SC_GetConfig("DebugUnitCommands", true) then
					SC_Debug("heal cached-skip unit="..SC_GetUnitDebugLabel(unit).." state="..SC_GetUnitOrderDebug(unit))
				end
			else
				local ok = SC_SendUnitMission(unit, GameInfoTypes.MISSION_HEAL)
				if ok and (SC_UnitNeedsOrder == nil or not SC_UnitNeedsOrder(unit)) then
					healed = healed + 1
				else
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

local function SC_BuildAutomationResults(player, atWar)
	local cityOrders, cityDetails = SC_AutomateCities(player, atWar)
	local results = {
		cityOrders = cityOrders,
		research = SC_AutomateResearch(player),
		upgrades = SC_AutomateUnitUpgrades(player),
		heals = SC_AutomateDamagedUnitHealing(player),
		defenseActions = SC_AutomateLocalDefense(player, atWar),
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
GameEvents.PlayerDoTurn.Add(SC_OnPlayerDoTurn)

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
	local defenseActions = SC_AutomateLocalDefense(player, atWar)
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
	local results, cityDetails = SC_BuildAutomationResults(player, atWar)
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
	return weights
end

local function SC_GetBestConstructibleBuilding(player, city, atWar, reservedOrders)
	local bestID = nil
	local bestScore = -999999
	local bestIsWonder = false
	local candidateCount = 0
	local reservedCount = 0
	local wanted = SC_GetWantedBuildingWeights(player, city, atWar)
	local production = SC_GetConfig("ProductionProfile", "BUILDINGS")
	for building in GameInfo.Buildings() do
		local reserveKey = "B:"..tostring(building.ID)
		if reservedOrders ~= nil and reservedOrders[reserveKey] then
			reservedCount = reservedCount + 1
		elseif SC_CityCanConstruct(city, building.ID) then
			candidateCount = candidateCount + 1
			local score = 10 + SC_GetBuildingFlavorScore(building.Type, wanted)
			score = score + (building.Happiness or 0) * wanted.FLAVOR_HAPPINESS
			score = score + (building.Defense or 0) / 40
			score = score + (building.Experience or 0) / 2
			score = score + math.max(building.Cost or 0, 0) / 80
			score = score - (building.GoldMaintenance or 0) * 8
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
			if score > bestScore then
				bestScore = score
				bestID = building.ID
				bestIsWonder = isWonder
			end
		end
	end
	return bestID, bestScore, candidateCount, bestIsWonder, reservedCount
end

local function SC_ChooseCityProduction(player, city, atWar, reservedOrders)
	if city == nil or city:IsPuppet() or city:IsResistance() then
		return nil
	end
	local queueLength = SC_GetSafeNumber(function() return city:GetOrderQueueLength() end, 0)
	local cityName = "CITY"
	pcall(function() cityName = city:GetName() end)
	if queueLength > 0 then
		local orderType = nil
		pcall(function()
			orderType = city:GetOrderFromQueue(0)
		end)
		if orderType == OrderTypes.ORDER_MAINTAIN then
			pcall(function() city:ClearOrderQueue() end)
			if SC_GetConfig("DebugCityProduction", true) then
				SC_Debug("cityProduction clear-maintain city="..tostring(cityName).." queueBefore="..tostring(queueLength))
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
	local buildMilitary = SC_ShouldBuildMilitary(player, city, atWar)
	if buildMilitary then
		local ok, coastal = pcall(function() return city:IsCoastal() end)
		local unitID = nil
		local unitScore = nil
		local unitCandidates = nil
		local unitRole = nil
		local unitReserved = nil
		local unitRejected = nil
		local unitEra = nil
		if production == "AIRSEA" then
			if ok and coastal then
				unitID, unitScore, unitCandidates, unitRole, unitReserved, unitRejected, unitEra = SC_GetBestTrainableUnit(city, true, false, reservedOrders)
			end
			if unitID == nil then
				unitID, unitScore, unitCandidates, unitRole, unitReserved, unitRejected, unitEra = SC_GetBestTrainableUnit(city, false, true, reservedOrders)
			end
		end
		if unitID == nil then
			unitID, unitScore, unitCandidates, unitRole, unitReserved, unitRejected, unitEra = SC_GetBestTrainableUnit(city, ok and coastal, false, reservedOrders)
		end
		if unitID == nil and ok and coastal then
			unitID, unitScore, unitCandidates, unitRole, unitReserved, unitRejected, unitEra = SC_GetBestTrainableUnit(city, false, false, reservedOrders)
		end
		if unitID ~= nil and SC_PushCityOrder(city, OrderTypes.ORDER_TRAIN, unitID) then
			local unitInfo = GameInfo.Units[unitID]
			local reserveKey = "U:"..tostring(unitID)
			if SC_GetConfig("DebugCityProduction", true) then
				SC_Debug("cityProduction choose city="..tostring(cityName).." category=military item="..tostring(unitInfo and unitInfo.Type or "UNIT").." role="..tostring(unitRole).." score="..tostring(unitScore).." candidates="..tostring(unitCandidates).." reserved="..tostring(unitReserved).." rejectedOutdated="..tostring(unitRejected).." playerEra="..tostring(unitEra).." reason=military-target queue="..tostring(queueLength))
			end
			return unitInfo and unitInfo.Type or "UNIT", reserveKey
		end
		if unitID == nil and SC_GetConfig("DebugCityProduction", true) then
			SC_Debug("cityProduction military-no-unit city="..tostring(cityName).." candidates="..tostring(unitCandidates).." reserved="..tostring(unitReserved).." rejectedOutdated="..tostring(unitRejected).." playerEra="..tostring(unitEra).." reason=no-viable-modern-unit")
		end
	elseif SC_GetConfig("DebugCityProduction", true) then
		SC_Debug("cityProduction military-skip city="..tostring(cityName).." reason=force-not-needed profile="..tostring(production).." atWar="..SC_BoolText(atWar))
	end
	
	local buildingID, buildingScore, buildingCandidates, buildingWonder, buildingReserved = SC_GetBestConstructibleBuilding(player, city, atWar, reservedOrders)
	if buildingID ~= nil and SC_PushCityOrder(city, OrderTypes.ORDER_CONSTRUCT, buildingID) then
		local buildingInfo = GameInfo.Buildings[buildingID]
		local reserveKey = "B:"..tostring(buildingID)
		if SC_GetConfig("DebugCityProduction", true) then
			SC_Debug("cityProduction choose city="..tostring(cityName).." category=building item="..tostring(buildingInfo and buildingInfo.Type or "BUILDING").." score="..tostring(buildingScore).." candidates="..tostring(buildingCandidates).." reserved="..tostring(buildingReserved).." wonder="..SC_BoolText(buildingWonder).." queue="..tostring(queueLength))
		end
		return buildingInfo and buildingInfo.Type or "BUILDING", reserveKey
	end
	
	local unitID, unitScore, unitCandidates, unitRole, unitReserved, unitRejected, unitEra = nil, nil, nil, nil, nil, nil, nil
	local warProfile = SC_GetConfig("WarProfile", "ADVANCE")
	local allowFallbackUnit = buildMilitary or production == "MILITARY" or production == "AIRSEA" or warProfile == "ASSAULT" or warProfile == "NAVAL"
	if allowFallbackUnit then
		unitID, unitScore, unitCandidates, unitRole, unitReserved, unitRejected, unitEra = SC_GetBestTrainableUnit(city, false, false, reservedOrders)
		if unitID ~= nil and SC_PushCityOrder(city, OrderTypes.ORDER_TRAIN, unitID) then
			local unitInfo = GameInfo.Units[unitID]
			local reserveKey = "U:"..tostring(unitID)
			if SC_GetConfig("DebugCityProduction", true) then
				SC_Debug("cityProduction choose city="..tostring(cityName).." category=fallback-unit item="..tostring(unitInfo and unitInfo.Type or "UNIT").." role="..tostring(unitRole).." score="..tostring(unitScore).." candidates="..tostring(unitCandidates).." reserved="..tostring(unitReserved).." rejectedOutdated="..tostring(unitRejected).." playerEra="..tostring(unitEra).." reason=no-building militaryFallback=true queue="..tostring(queueLength))
			end
			return unitInfo and unitInfo.Type or "UNIT", reserveKey
		end
		if unitID == nil and SC_GetConfig("DebugCityProduction", true) then
			SC_Debug("cityProduction fallback-no-unit city="..tostring(cityName).." candidates="..tostring(unitCandidates).." reserved="..tostring(unitReserved).." rejectedOutdated="..tostring(unitRejected).." playerEra="..tostring(unitEra).." reason=no-viable-fallback-unit")
		end
	elseif SC_GetConfig("DebugCityProduction", true) then
		SC_Debug("cityProduction fallback-skip city="..tostring(cityName).." reason=non-military-profile profile="..tostring(production).." warProfile="..tostring(warProfile))
	end
	
	local processType = "PROCESS_WEALTH"
	if (SC_GetConfig("Doctrine", "BALANCED") == "SCIENCE" or SC_GetConfig("EconomyProfile", "BALANCED") == "SCIENCE") and SC_GetSafeNumber(function() return player:CalculateGoldRate() end, 0) >= 0 then
		processType = "PROCESS_RESEARCH"
	end
	local processID = SC_GetID(processType)
	if SC_CityCanMaintain(city, processID) and SC_PushCityOrder(city, OrderTypes.ORDER_MAINTAIN, processID) then
		if SC_GetConfig("DebugCityProduction", true) then
			SC_Debug("cityProduction choose city="..tostring(cityName).." category=process item="..tostring(processType).." reason=no-unit-or-building goldRate="..tostring(SC_GetSafeNumber(function() return player:CalculateGoldRate() end, 0)).." queue="..tostring(queueLength))
		end
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
	local targetQueue = SC_GetConfig("TargetCityQueueLength", SC_GetConfig("MinCityQueueLength", 1))
	for city in player:Cities() do
		local safety = 0
		local reservedOrders = {}
		while city ~= nil and safety < targetQueue do
			local queueLength = SC_GetSafeNumber(function() return city:GetOrderQueueLength() end, 0)
			if queueLength >= targetQueue then
				break
			end
			local productionType, reserveKey = SC_ChooseCityProduction(player, city, atWar, reservedOrders)
			if productionType == nil then
				break
			end
			if reserveKey ~= nil then
				reservedOrders[reserveKey] = true
			end
			changed = changed + 1
			if #details < 10 then
				table.insert(details, city:GetName()..": "..productionType)
			end
			safety = safety + 1
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
	return score
end

local function SC_GetAutoIdeologyBranchID()
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
			local branchOrder = {"POLICY_BRANCH_RATIONALISM", "POLICY_BRANCH_ORDER", "POLICY_BRANCH_AUTOCRACY", "POLICY_BRANCH_COMMERCE", "POLICY_BRANCH_EXPLORATION", "POLICY_BRANCH_TRADITION", "POLICY_BRANCH_HONOR"}
			for _, branchType in ipairs(branchOrder) do
				local branchID = GameInfoTypes[branchType]
				if branchID ~= nil then
					local branchInfo = GameInfo.PolicyBranchTypes[branchID]
					local canUnlock = false
					pcall(function() canUnlock = player:CanUnlockPolicyBranch(branchID) end)
					local purchaseByLevel = branchInfo ~= nil and (branchInfo.PurchaseByLevel == true or branchInfo.PurchaseByLevel == 1 or branchInfo.PurchaseByLevel == "1")
					if canUnlock and not SC_POLICY_FAILED_THIS_TURN["B:"..tostring(branchID)] and not purchaseByLevel then
						bestBranch = branchID
						break
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
			local ok = SC_SendUnitCommand(unit, CommandTypes.COMMAND_PROMOTION, bestPromotion, commandData2)
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
	if enemyCity ~= nil then
		local cityDamage, cityMaxHP, cityDamageRatio = SC_GetCityDamageInfo(enemyCity)
		score = score + 260
		SC_AddScoreReason(reasons, "city", 260)
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
		if SC_CanActAsCityCaptureUnit(unit, unitInfo, role) then
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
		elseif role == "missile_carrier" or role == "naval_ranged" then
			local shipScore = 220
			if coastalTarget then
				shipScore = shipScore + 300
			end
			if cityDamageRatio >= 0.45 then
				shipScore = shipScore + 180
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
			if cityDamageRatio >= SC_GetConfig("CityCaptureReadyDamageRatio", 0.72) then
				score = score - 360
				SC_AddScoreReason(reasons, "subNoCapture", -360)
			end
		elseif role == "siege" or role == "land_ranged" then
			score = score + 160
			SC_AddScoreReason(reasons, "rangedSiege", 160)
		end
		if SC_GetSafeNumber(function() return enemyCity:IsCapital() and 1 or 0 end, 0) > 0 then
			score = score + 120
			SC_AddScoreReason(reasons, "capital", 120)
		end
	elseif enemyUnit ~= nil then
		local enemyInfo = SC_GetUnitInfo(enemyUnit)
		local enemyRole = SC_GetUnitRole(enemyUnit, enemyInfo)
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
			score = score + 360
			SC_AddScoreReason(reasons, "subHuntNavy", 360)
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
	return false
end

local function SC_GetUnitStackLayer(unit)
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
	if not SC_PlotMatchesUnitDomain(unitInfo, plot) then
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
						if SC_TryMoveMission(unit, movePlot, "stacked", true) then
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
	local range = SC_GetUnitRangeValue(unit, unitInfo)
	local minRange = 2
	local maxRange = math.max(range, 3)
	local desiredRange = range
	if role == "carrier" then
		minRange = SC_GetConfig("CarrierStandoffMinDistance", 5)
		maxRange = SC_GetConfig("CarrierStandoffMaxDistance", 8)
		desiredRange = math.floor((minRange + maxRange) / 2 + 0.5)
	elseif role == "missile_carrier" or role == "naval_ranged" then
		minRange = math.max(2, math.min(range, 4))
		maxRange = math.max(range, 4)
		desiredRange = math.max(range, minRange)
	elseif role == "siege" or role == "land_ranged" then
		minRange = math.max(2, math.min(range, 3))
		maxRange = math.max(range, 3)
		desiredRange = math.max(range, minRange)
	end
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
						if role == "naval_ranged" or role == "missile_carrier" then
							score = score + 80
						end
						if role == "carrier" then
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
	if SC_CanUnitMoveIntoPlotForCapture(unit, targetPlot)
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

function SC_GetStrategicPlanStatsDebug(stats)
	if stats == nil then
		return "stats=nil"
	end
	return "candidates="..tostring(stats.candidates or 0)..
		" noPlot="..tostring(stats.noPlot or 0)..
		" noMovePlot="..tostring(stats.noMovePlot or 0)..
		" stationary="..tostring(stats.stationary or 0)..
		" bestScore="..tostring(stats.bestScore or "nil")..
		" bestKind="..tostring(stats.bestKind or "nil")..
		" bestReason="..tostring(stats.bestReason or "nil")..
		" "..SC_GetMoveRejectStatsDebug(stats)
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
	local bestPlan = nil
	local bestScore = -999999
	local stats = {
		candidates = 0,
		noPlot = 0,
		noMovePlot = 0,
		stationary = 0,
		bestScore = nil,
		bestKind = nil
	}
	local function considerTarget(targetPlot, enemyUnit, enemyCity, kind)
		stats.candidates = stats.candidates + 1
		if targetPlot == nil then
			stats.noPlot = stats.noPlot + 1
			return
		end
		local targetScore, targetReason = SC_ScoreStrategicTarget(player, unit, role, unitPlot, targetPlot, enemyUnit, enemyCity)
		if (role == "carrier" or role == "missile_carrier" or role == "naval_ranged" or role == "submarine" or role == "naval_melee") and SC_IsWaterOrCoastalStrategicPlot(targetPlot) then
			targetScore = targetScore + 160
			targetReason = tostring(targetReason or "base")..",waterCoast:160"
		end
		local movePlot = targetPlot
		local mode = "direct"
		local captureMover = kind == "city" and enemyCity ~= nil and SC_CanActAsCityCaptureUnit(unit, unitInfo, role)
		if captureMover and SC_IsCityReadyForCapture(enemyCity) then
			local captureMode = nil
			movePlot, captureMode = SC_FindCityCaptureMovePlot(player, unit, role, targetPlot, reservedMovePlots, stats)
			if movePlot ~= nil then
				mode = captureMode or "capture"
				targetScore = targetScore + 720
				targetReason = tostring(targetReason or "base")..",captureFinish:720"
			elseif SC_GetConfig("EnableRangedReposition", true) and SC_IsStrategicRangedMoveRole(role) then
				movePlot = SC_FindStandoffMovePlot(player, unit, role, targetPlot, reservedMovePlots, stats)
				mode = "standoff"
				targetReason = tostring(targetReason or "base")..",captureFallbackStandoff"
			end
		elseif SC_GetConfig("EnableRangedReposition", true) and SC_IsStrategicRangedMoveRole(role) then
			movePlot = SC_FindStandoffMovePlot(player, unit, role, targetPlot, reservedMovePlots, stats)
			mode = "standoff"
		end
		if movePlot == nil then
			stats.noMovePlot = stats.noMovePlot + 1
			return
		end
		local moveDistance = Map.PlotDistance(unitPlot:GetX(), unitPlot:GetY(), movePlot:GetX(), movePlot:GetY())
		if moveDistance <= 0 then
			stats.stationary = stats.stationary + 1
			return
		end
		local targetDistance = Map.PlotDistance(unitPlot:GetX(), unitPlot:GetY(), targetPlot:GetX(), targetPlot:GetY())
		local planScore = targetScore - moveDistance * 7
		if role == "carrier" then
			planScore = planScore + 120
			if kind == "city" and SC_IsWaterOrCoastalStrategicPlot(targetPlot) then
				planScore = planScore + 120
			end
		elseif role == "missile_carrier" or role == "naval_ranged" then
			planScore = planScore + 90
		elseif role == "fast_assault" or role == "naval_melee" then
			planScore = planScore + math.max(0, 160 - targetDistance * 8)
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
				targetDistance = targetDistance
			}
			stats.bestScore = planScore
			stats.bestKind = kind
			stats.bestReason = targetReason
		end
	end
	for otherID, otherPlayer in pairs(Players) do
		if otherPlayer ~= nil and otherPlayer:IsAlive() and otherPlayer:GetID() ~= player:GetID() and team:IsAtWar(otherPlayer:GetTeam()) then
			for city in otherPlayer:Cities() do
				considerTarget(city:Plot(), nil, city, "city")
			end
			for enemyUnit in otherPlayer:Units() do
				considerTarget(enemyUnit:GetPlot(), enemyUnit, nil, "unit")
			end
		end
	end
	return bestPlan, stats
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
	local reservedMovePlots = {}
	local function debugMove(text)
		if SC_GetConfig("DebugUnitDecisions", true) and debugCount < debugLimit then
			debugCount = debugCount + 1
			SC_Debug(text)
		end
	end
	SC_Debug("strategicMove start maxMoves="..tostring(maxMoves).." warProfile="..tostring(SC_GetConfig("WarProfile", "ADVANCE")))
	for unit in player:Units() do
		if moved >= maxMoves then
			break
		end
		if unit ~= nil and unit:CanMove() and unit:GetDamage() < SC_GetConfig("HealDamageThreshold", 45) then
			local unitInfo = SC_GetUnitInfo(unit)
			local role = SC_GetUnitRole(unit, unitInfo)
			local unitKey = SC_GetUnitTurnKey(unit)
			if not SC_IsCombatAutomationUnit(unit, unitInfo) then
				debugMove("strategicMove noncombat-skip unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role))
			elseif unitKey ~= nil and SC_STRATEGIC_ORDERED_THIS_TURN[unitKey] then
				debugMove("strategicMove turn-skip unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role))
			elseif SC_CanStrategicMoveRole(role) then
				local plan, planStats = SC_FindStrategicMovePlan(player, unit, reservedMovePlots)
				local unitPlot = unit:GetPlot()
				if plan ~= nil and unitPlot ~= nil then
					local targetPlot = plan.targetPlot
					local movePlot = plan.movePlot
					local mode = plan.mode or "direct"
					if movePlot ~= nil then
						local distance = Map.PlotDistance(unitPlot:GetX(), unitPlot:GetY(), movePlot:GetX(), movePlot:GetY())
						if distance > 0 then
							debugMove("strategicMove order unit="..SC_GetUnitDebugLabel(unit)..
								" role="..tostring(role)..
								" mode="..mode..
								" kind="..tostring(plan.kind)..
								" from="..SC_GetPlotDebug(unitPlot)..
								" target="..SC_GetPlotDebug(targetPlot)..
								" moveTo="..SC_GetPlotDebug(movePlot)..
								" distance="..tostring(distance)..
								" targetDistance="..tostring(plan.targetDistance)..
								" score="..tostring(plan.planScore)..
								" reason="..tostring(plan.reason or "nil")..
								" "..SC_GetStrategicPlanStatsDebug(planStats))
							local ok = SC_TryMoveMission(unit, movePlot, "strategic")
							if ok then
								if mode == "standoff" or string.sub(tostring(mode), 1, 7) == "capture" then
									SC_ReserveMovePlot(reservedMovePlots, movePlot, SC_GetUnitStackLayer(unit))
								end
								if unitKey ~= nil then
									SC_STRATEGIC_ORDERED_THIS_TURN[unitKey] = true
									SC_TACTICAL_NO_TARGET_THIS_TURN[unitKey] = nil
									SC_TACTICAL_QUEUED_THIS_TURN[unitKey] = nil
								end
								moved = moved + 1
							else
								debugMove("strategicMove mission-failed unit="..SC_GetUnitDebugLabel(unit)..
									" role="..tostring(role)..
									" mode="..mode..
									" kind="..tostring(plan.kind)..
									" target="..SC_GetPlotDebug(targetPlot)..
									" moveTo="..SC_GetPlotDebug(movePlot)..
									" reason="..tostring(plan.reason or "nil")..
									" state="..SC_GetUnitOrderDebug(unit)..
									" "..SC_GetStrategicPlanStatsDebug(planStats))
								if unitKey ~= nil then
									SC_STRATEGIC_ORDERED_THIS_TURN[unitKey] = true
								end
							end
						else
							debugMove("strategicMove already-positioned unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role).." plot="..SC_GetPlotDebug(unitPlot).." "..SC_GetStrategicPlanStatsDebug(planStats))
							if unitKey ~= nil then
								SC_STRATEGIC_ORDERED_THIS_TURN[unitKey] = true
							end
						end
					else
						debugMove("strategicMove no-move-plot unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role).." target="..SC_GetPlotDebug(targetPlot).." range="..tostring(SC_GetUnitRangeValue(unit, unitInfo)).." "..SC_GetStrategicPlanStatsDebug(planStats))
						if unitKey ~= nil then
							SC_STRATEGIC_ORDERED_THIS_TURN[unitKey] = true
						end
					end
				else
					debugMove("strategicMove no-plan unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role).." "..SC_GetStrategicPlanStatsDebug(planStats))
					if unitKey ~= nil then
						SC_STRATEGIC_ORDERED_THIS_TURN[unitKey] = true
					end
				end
			else
				debugMove("strategicMove role-skip unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role))
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
	local unitPlot = nil
	pcall(function() unitPlot = unit:GetPlot() end)
	local ok, err = pcall(function()
		unit:PushMission(missionType, targetPlot:GetX(), targetPlot:GetY(), 0, 0, 1, missionType, unitPlot, unit)
	end)
	if SC_GetConfig("DebugUnitCommands", true) then
		SC_Debug("mission direct-target unit="..SC_GetUnitDebugLabel(unit)..
			" mission="..SC_GetEnumDebugName(MissionTypes, missionType)..
			" target="..SC_GetPlotDebug(targetPlot)..
			" reason="..tostring(reason)..
			" ok="..SC_BoolText(ok)..
			" err="..tostring(err)..
			" state="..SC_GetUnitOrderDebug(unit))
	end
	if ok and SC_UnitNeedsOrder(unit) and SC_GetConfig("DebugUnitCommands", true) then
		SC_Debug("mission direct-target-pending unit="..SC_GetUnitDebugLabel(unit)..
			" mission="..SC_GetEnumDebugName(MissionTypes, missionType)..
			" target="..SC_GetPlotDebug(targetPlot)..
			" state="..SC_GetUnitOrderDebug(unit))
	end
	return ok and not SC_UnitNeedsOrder(unit)
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
	local unitKey = SC_GetUnitTurnKey(unit)
	local cacheKey = tostring(unitKey or SC_GetUnitDebugLabel(unit)).."|"..tostring(missionType)
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
	if SC_GetConfig("DebugUnitCommands", true) then
		SC_Debug("mission direct-push unit="..SC_GetUnitDebugLabel(unit)..
			" mission="..SC_GetEnumDebugName(MissionTypes, missionType)..
			" reason="..tostring(reason)..
			" ok="..SC_BoolText(ok)..
			" err="..tostring(err)..
			" state="..SC_GetUnitOrderDebug(unit))
	end
	if ok and SC_UnitNeedsOrder(unit) and SC_GetConfig("DebugUnitCommands", true) then
		SC_Debug("mission direct-push-pending unit="..SC_GetUnitDebugLabel(unit)..
			" mission="..SC_GetEnumDebugName(MissionTypes, missionType)..
			" state="..SC_GetUnitOrderDebug(unit))
	end
	if ok and not SC_UnitNeedsOrder(unit) then
		return true
	end
	if ok then
		SC_DIRECT_PUSH_FAILED_THIS_TURN[cacheKey] = true
	end
	return false
end

local function SC_TryUnitMission(unit, missionType, x, y, allowDirectPush)
	if unit == nil or missionType == nil then
		return false
	end
	local wasWaiting = SC_UnitNeedsOrder(unit)
	local ok = SC_SendUnitMission(unit, missionType, x, y)
	if ok then
		if SC_UnitNeedsOrder(unit) and SC_GetConfig("DebugUnitCommands", true) then
			SC_Debug("mission pending-clear unit="..SC_GetUnitDebugLabel(unit).." mission="..SC_GetEnumDebugName(MissionTypes, missionType).." state="..SC_GetUnitOrderDebug(unit))
		end
		if allowDirectPush ~= false and SC_UnitNeedsOrder(unit) then
			SC_TryDirectTargetlessMission(unit, missionType, "pending-after-net-message")
		end
		return not SC_UnitNeedsOrder(unit)
	end
	return false
end

local function SC_TryUnitCommand(unit, commandType, data1, data2)
	if unit == nil or commandType == nil then
		return false
	end
	local wasWaiting = SC_UnitNeedsOrder(unit)
	local ok = SC_SendUnitCommand(unit, commandType, data1, data2)
	if ok and SC_UnitNeedsOrder(unit) and SC_GetConfig("DebugUnitCommands", true) then
		SC_Debug("command pending-clear unit="..SC_GetUnitDebugLabel(unit).." command="..SC_GetEnumDebugName(CommandTypes, commandType).." state="..SC_GetUnitOrderDebug(unit))
	end
	return ok and not SC_UnitNeedsOrder(unit)
end

local function SC_TryUnitActionByType(unit, wantedTypes)
	if unit == nil or GameInfoActions == nil or Game == nil or Game.HandleAction == nil or wantedTypes == nil then
		return false
	end
	local wasWaiting = SC_UnitNeedsOrder(unit)
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
				if SC_GetConfig("DebugUnitCommands", true) then
					SC_Debug("action unit="..SC_GetUnitDebugLabel(unit).." action="..tostring(action.Type).." index="..tostring(iAction).." ok="..SC_BoolText(ok).." err="..tostring(err).." state="..SC_GetUnitOrderDebug(unit))
				end
				if ok then
					if SC_UnitNeedsOrder(unit) and SC_GetConfig("DebugUnitCommands", true) then
						SC_Debug("action pending-clear unit="..SC_GetUnitDebugLabel(unit).." action="..tostring(action.Type).." state="..SC_GetUnitOrderDebug(unit))
					end
					if SC_UnitNeedsOrder(unit) then
						SC_TryDirectTargetlessMission(unit, SC_GetMissionID(action.Type), "pending-after-action")
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
	local priority = -999999
	if string.find(unitType, "WRITER") ~= nil then
		if actionType == "MISSION_CREATE_GREAT_WORK" then priority = 100 end
		if actionType == "MISSION_GIVE_POLICIES" then priority = 95 end
		if actionType == "MISSION_GOLDEN_AGE" then priority = 20 end
	elseif string.find(unitType, "ARTIST") ~= nil then
		if actionType == "MISSION_CREATE_GREAT_WORK" then priority = 100 end
		if actionType == "MISSION_GOLDEN_AGE" then priority = 90 end
		if actionType == "MISSION_CULTURE_BOMB" then priority = 15 end
	elseif string.find(unitType, "MUSICIAN") ~= nil then
		if actionType == "MISSION_ONE_SHOT_TOURISM" then priority = 100 end
		if actionType == "MISSION_CREATE_GREAT_WORK" then priority = 95 end
		if actionType == "MISSION_GOLDEN_AGE" then priority = 20 end
	elseif string.find(unitType, "SCIENTIST") ~= nil then
		if actionType == "MISSION_DISCOVER" then priority = 100 end
		if actionType == "MISSION_GOLDEN_AGE" then priority = 20 end
	elseif string.find(unitType, "ENGINEER") ~= nil then
		if actionType == "MISSION_HURRY" then priority = 100 end
		if actionType == "MISSION_GOLDEN_AGE" then priority = 20 end
	elseif string.find(unitType, "MERCHANT") ~= nil then
		if actionType == "MISSION_TRADE" then priority = 100 end
		if actionType == "MISSION_SELL_EXOTIC_GOODS" then priority = 95 end
		if actionType == "MISSION_BUY_CITY_STATE" then priority = 90 end
		if actionType == "MISSION_GOLDEN_AGE" then priority = 20 end
	elseif string.find(unitType, "PROPHET") ~= nil then
		if actionType == "MISSION_FOUND_RELIGION" then priority = 100 end
		if actionType == "MISSION_ENHANCE_RELIGION" then priority = 95 end
		if actionType == "MISSION_SPREAD_RELIGION" then priority = 80 end
	end
	if priority > -999999 then
		return priority
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
		MISSION_REPAIR_FLEET = 5,
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
	local bestAction = nil
	local bestType = nil
	local bestScore = -999999
	for iAction = 0, #GameInfoActions, 1 do
		local action = GameInfoActions[iAction]
		if action ~= nil and action.Visible and action.Type ~= nil and (ActionSubTypes == nil or action.SubType ~= ActionSubTypes.ACTIONSUBTYPE_PROMOTION) then
			local score = SC_GetGreatPersonActionPriority(unitInfo, action.Type)
			if score > bestScore then
				local canHandle = false
				pcall(function() canHandle = Game.CanHandleAction(iAction) end)
				if canHandle then
					bestAction = iAction
					bestType = action.Type
					bestScore = score
				end
			end
		end
	end
	if bestAction == nil then
		SC_Debug("greatPerson action no-legal-action unit="..SC_GetUnitDebugLabel(unit).." type="..tostring(unitInfo.Type).." reason="..tostring(reason))
		return false
	end
	local ok, err = pcall(function()
		Game.HandleAction(bestAction)
	end)
	local dead = false
	pcall(function() dead = unit:IsDead() end)
	local stillNeeds = false
	if not dead then
		stillNeeds = SC_UnitNeedsOrder(unit)
	end
	SC_Debug("greatPerson action unit="..SC_GetUnitDebugLabel(unit)..
		" type="..tostring(unitInfo.Type)..
		" action="..tostring(bestType)..
		" index="..tostring(bestAction)..
		" score="..tostring(bestScore)..
		" reason="..tostring(reason)..
		" ok="..SC_BoolText(ok)..
		" err="..tostring(err)..
		" dead="..SC_BoolText(dead)..
		" stillNeeds="..SC_BoolText(stillNeeds))
	if ok and not dead and stillNeeds then
		local missionType = SC_GetMissionID(bestType)
		if missionType ~= nil then
			local missionDone = SC_TryUnitMission(unit, missionType, nil, nil, false)
			local missionStillNeeds = false
			if not unit:IsDead() then
				missionStillNeeds = SC_UnitNeedsOrder(unit)
			end
			SC_Debug("greatPerson mission unit="..SC_GetUnitDebugLabel(unit)..
				" type="..tostring(unitInfo.Type)..
				" action="..tostring(bestType)..
				" mission="..SC_GetEnumDebugName(MissionTypes, missionType)..
				" reason="..tostring(reason)..
				" done="..SC_BoolText(missionDone)..
				" stillNeeds="..SC_BoolText(missionStillNeeds))
			if missionDone or not missionStillNeeds then
				return true
			end
		end
	end
	return ok and (dead or not stillNeeds)
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
	SC_Debug("finalOrders start maxOrders="..tostring(maxOrders).." maxRounds="..tostring(maxRounds).." atWar="..SC_BoolText(atWar))
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
		local done = false
		if SC_UnitCanPromoteNow(unit) then
			done = SC_TryPromoteUnit(unit, "finalOrders")
			if done then
				debugFinal("finalOrders promoted unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role).." attempt="..tostring(attemptCount + 1).." state="..SC_GetUnitOrderDebug(unit))
				return true
			end
			debugFinal("finalOrders promotion-unresolved unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role).." attempt="..tostring(attemptCount + 1).." state="..SC_GetUnitOrderDebug(unit))
			return false
		end
		if not done and atWar and SC_IsCombatAutomationUnit(unit, unitInfo) and unit:GetDamage() < SC_GetConfig("HealDamageThreshold", 45) and SC_IsRangedAttackUnit(unit, unitInfo, role) then
			local actionCount = SC_GetTacticalActionCount(unitKey)
			local actionCap = SC_GetTacticalActionCapForUnit(unit, unitInfo, role)
			if unitKey ~= nil and actionCount >= actionCap then
				debugFinal("finalOrders tactical-cap unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role).." attempt="..tostring(attemptCount + 1).." count="..tostring(actionCount).." cap="..tostring(actionCap))
			else
				local cachedQueued = SC_GetValidTacticalQueuedCache(unit, unitKey)
				if cachedQueued ~= nil then
					debugFinal("finalOrders tactical-queued-cached unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role).." attempt="..tostring(attemptCount + 1).." "..SC_FormatTacticalQueuedCache(cachedQueued))
				else
				local cachedNoTarget = SC_GetValidTacticalNoTargetCache(unit, unitKey)
				if cachedNoTarget ~= nil then
					debugFinal("finalOrders tactical-no-target-cached unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role).." attempt="..tostring(attemptCount + 1).." "..SC_FormatTacticalNoTargetCache(cachedNoTarget))
				else
				local targetPlot, targetScore, targetStats = SC_FindRangeTarget(player, unit)
				if targetPlot ~= nil then
					local strikeStatus = "none"
					done, strikeStatus = SC_RangeStrike(unit, targetPlot)
					if done then
						local newCount = SC_RecordTacticalAction(unitKey)
						SC_RecordRangeTargetStrike(targetPlot, role, targetStats and targetStats.bestKind or nil)
						local label = "queued"
						if SC_IsStrikeStatusFired(strikeStatus) then
							label = "fired"
						end
						debugFinal("finalOrders tactical-"..label.." unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role).." attempt="..tostring(attemptCount + 1).." status="..tostring(strikeStatus).." count="..tostring(newCount).."/"..tostring(actionCap).." target="..SC_GetPlotDebug(targetPlot).." score="..tostring(targetScore).." reason="..tostring(targetStats and targetStats.bestReason or "nil"))
						if unitKey ~= nil then
							if SC_IsStrikeStatusQueued(strikeStatus) then
								SC_RecordTacticalQueued(unit, unitKey, role, targetPlot, strikeStatus, "finalOrders")
							else
								SC_TACTICAL_QUEUED_THIS_TURN[unitKey] = nil
								SC_TACTICAL_NO_TARGET_THIS_TURN[unitKey] = nil
							end
						end
					else
						debugFinal("finalOrders tactical-failed unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role).." attempt="..tostring(attemptCount + 1).." status="..tostring(strikeStatus).." target="..SC_GetPlotDebug(targetPlot).." score="..tostring(targetScore).." reason="..tostring(targetStats and targetStats.bestReason or "nil"))
					end
				else
					SC_RecordTacticalNoTarget(unit, unitKey, role, targetStats, "out-of-range")
					debugFinal("finalOrders tactical-no-target unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role).." attempt="..tostring(attemptCount + 1).." "..SC_GetRangeTargetStatsDebug(targetStats))
				end
				end
				end
			end
		end
		if SC_IsGreatPersonLike(unitInfo) then
			done = SC_TryUnitActionByType(unit, {MISSION_SLEEP = true, COMMAND_SLEEP = true}) or SC_TryUnitCommand(unit, CommandTypes.COMMAND_SLEEP) or SC_TryUnitMission(unit, MissionTypes.MISSION_SLEEP) or SC_TryUnitMission(unit, GameInfoTypes.MISSION_SLEEP) or SC_TryUnitActionByType(unit, {MISSION_SKIP = true}) or SC_TryUnitMission(unit, MissionTypes.MISSION_SKIP) or SC_TryUnitMission(unit, GameInfoTypes.MISSION_SKIP)
			if not done then
				done = SC_TryGreatPersonActionFallback(unit, unitInfo, "finalOrders-blocked")
			end
		end
		if not done and SC_IsTradeLike(unitInfo) then
			done = SC_TryUnitActionByType(unit, {MISSION_SKIP = true}) or SC_TryUnitMission(unit, MissionTypes.MISSION_SKIP) or SC_TryUnitMission(unit, GameInfoTypes.MISSION_SKIP)
		end
		if not done and unit:GetDamage() >= SC_GetConfig("HealDamageThreshold", 45) and unit:IsCombatUnit() then
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
		if not done and SC_IsWorkerLike(unitInfo) then
			done = SC_TryUnitCommand(unit, CommandTypes.COMMAND_AUTOMATE, GameInfoTypes.AUTOMATE_BUILD, -1)
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
			debugFinal("finalOrders handled unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role).." attempt="..tostring(attemptCount + 1).." forceReady="..SC_BoolText(forceReady == true).." state="..SC_GetUnitOrderDebug(unit))
		elseif done then
			debugFinal("finalOrders sent unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role).." attempt="..tostring(attemptCount + 1).." forceReady="..SC_BoolText(forceReady == true).." pendingClear=true state="..SC_GetUnitOrderDebug(unit))
		else
			debugFinal("finalOrders failed unit="..SC_GetUnitDebugLabel(unit).." role="..tostring(role).." attempt="..tostring(attemptCount + 1).." forceReady="..SC_BoolText(forceReady == true).." stillNeeds="..SC_BoolText(stillNeeds).." state="..SC_GetUnitOrderDebug(unit))
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

local function SC_BuildAutomationResults(player, atWar)
	local results = {
		cityOrders = 0,
		ideologies = 0,
		research = 0,
		policies = 0,
		upgrades = 0,
		promotions = 0,
		heals = 0,
		defenseActions = 0,
		cityStrikes = 0,
		strategicMoves = 0,
		stackedMoves = 0,
		idlePosture = 0,
		tradeRoutes = 0,
		finalOrders = 0,
		notifications = 0,
		leagues = 0,
		blockers = 0,
		popups = 0,
		diplo = 0
	}
	local cityDetails = {}
	local maxSweeps = SC_GetConfig("MaxTakeoverInnerSweeps", 3)
	for sweep = 1, maxSweeps, 1 do
		SC_Debug("sweep begin index="..tostring(sweep).." blocker="..SC_GetBlockingDebug(player))
		local before = results.cityOrders + results.ideologies + results.research + results.policies + results.upgrades + results.promotions + results.heals + results.defenseActions + results.cityStrikes + results.strategicMoves + results.stackedMoves + results.idlePosture + results.tradeRoutes + results.finalOrders + results.leagues + results.blockers
		local cityOrders, details = SC_AutomateCities(player, atWar)
		results.cityOrders = results.cityOrders + cityOrders
		if details ~= nil then
			for _, detail in ipairs(details) do
				if #cityDetails < 10 then
					table.insert(cityDetails, detail)
				end
			end
		end
		results.ideologies = results.ideologies + SC_AutomateIdeology(player)
		results.research = results.research + SC_AutomateResearch(player)
		results.policies = results.policies + SC_AutomatePolicy(player)
		results.upgrades = results.upgrades + SC_AutomateUnitUpgrades(player)
		results.promotions = results.promotions + SC_AutomateUnitPromotions(player)
		results.heals = results.heals + SC_AutomateDamagedUnitHealing(player)
		results.defenseActions = results.defenseActions + SC_AutomateLocalDefense(player, atWar)
		results.cityStrikes = results.cityStrikes + SC_AutomateCityRangedStrike(player, atWar)
		results.strategicMoves = results.strategicMoves + SC_AutomateStrategicMovement(player, atWar)
		results.stackedMoves = results.stackedMoves + SC_AutomateStackedUnits(player)
		results.idlePosture = results.idlePosture + SC_AutomateIdlePosture(player)
		results.tradeRoutes = results.tradeRoutes + SC_AutomateTradeRoutes(player)
		results.finalOrders = results.finalOrders + SC_AutomateFinalUnitOrders(player, atWar)
		if sweep == 1 then
			results.leagues = results.leagues + SC_AutomateLeagues(player)
		end
		results.blockers = results.blockers + SC_HandleEndTurnBlocker(player, atWar)
		local after = results.cityOrders + results.ideologies + results.research + results.policies + results.upgrades + results.promotions + results.heals + results.defenseActions + results.cityStrikes + results.strategicMoves + results.stackedMoves + results.idlePosture + results.tradeRoutes + results.finalOrders + results.leagues + results.blockers
		local blocking = SC_GetSafeNumber(function() return player:GetEndTurnBlockingType() end, -999)
		SC_Debug("sweep end index="..tostring(sweep)..
			" city="..tostring(results.cityOrders)..
			" ideology="..tostring(results.ideologies)..
			" research="..tostring(results.research)..
			" policy="..tostring(results.policies)..
			" promote="..tostring(results.promotions)..
			" tactical="..tostring(results.defenseActions)..
			" cityStrike="..tostring(results.cityStrikes)..
			" strategicMove="..tostring(results.strategicMoves)..
			" stacked="..tostring(results.stackedMoves)..
			" finalOrders="..tostring(results.finalOrders)..
			" leagues="..tostring(results.leagues)..
			" blockers="..tostring(results.blockers)..
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
	table.insert(lines, "治疗命令: "..tostring(results.heals or 0))
	table.insert(lines, "单位远程攻击: "..tostring(results.defenseActions or 0))
	table.insert(lines, "城市炮击: "..tostring(results.cityStrikes or 0))
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
		{ Key = "SLEEP", Text = "保留" },
		{ Key = "SCIENCE", Text = "科研" },
		{ Key = "ENGINEER", Text = "工程" },
		{ Key = "CULTURE", Text = "文化" },
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
SC_CONFIG.DirectPushMissionFallback = true
SC_CONFIG.DirectPushTargetedMissionFallback = true
SC_CONFIG.DirectPushMoveMissionFallback = true
SC_CONFIG.AvoidObsoleteFallbackUnits = true
SC_CONFIG.MaxFallbackUnitEraGap = 2
SC_CONFIG.MinLateGameFallbackCombatPower = 45
SC_CONFIG.RepeatedUnitReservationPenalty = 15
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
	SC_CONFIG.MaxTakeoverInnerSweeps = 5
	SC_CONFIG.MaxFinalUnitOrdersPerTurn = 240
	SC_CONFIG.MaxTakeoverPassesPerTurn = 6
	SC_CONFIG.ForceClearStuckUnitOrders = true
	SC_CONFIG.StackEscapeSearchRadius = 8
	if SC_CONFIG.AutoEndTurn == nil then
		SC_CONFIG.AutoEndTurn = true
	end
	SC_CONFIG.PostEndTurnQuietMode = true
	
	SC_CONFIG.TargetCityQueueLength = 5
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
		SC_STRATEGIC_ORDERED_THIS_TURN = {}
		SC_TACTICAL_ORDERED_THIS_TURN = {}
		SC_TACTICAL_NO_TARGET_THIS_TURN = {}
		SC_TACTICAL_QUEUED_THIS_TURN = {}
		SC_ASSAULT_SUPPORT_CACHE_THIS_TURN = {}
		SC_RANGE_TARGET_STRIKE_COUNT_THIS_TURN = {}
		SC_STACK_MOVE_ATTEMPTED_THIS_TURN = {}
		SC_FINAL_ORDER_ATTEMPTED_THIS_TURN = {}
		SC_DIRECT_PUSH_FAILED_THIS_TURN = {}
		SC_HEAL_FAILED_THIS_TURN = {}
		SC_RANGE_FAILED_THIS_TURN = {}
		SC_POPUP_LOGGED_THIS_TURN = {}
		SC_PROMOTION_SCAN_ATTEMPTED_THIS_TURN = {}
		SC_PROMOTION_FAILED_THIS_TURN = {}
		SC_PROMOTION_HANDLED_THIS_TURN = {}
		SC_PROMOTION_DIRECT_GRANTED_THIS_TURN = {}
		SC_PROMOTION_ACTION_LOGGED_THIS_TURN = {}
		SC_GREAT_PERSON_ACTION_ATTEMPTED_THIS_TURN = {}
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

if ContextPtr ~= nil and ContextPtr.SetUpdate ~= nil then
	ContextPtr:SetUpdate(SC_OnAutomationUpdate)
end

local function SC_RunTakeoverPass(player, reason, allowEndTurn)
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
	SC_ApplyStrategicProfiles()
	local atWar = SC_PlayerAtWar(player)
	SC_Debug("pass begin reason="..tostring(reason)..
		" count="..tostring(SC_LAST_TAKEOVER_PASS_COUNT)..
		" remaining="..tostring(SC_GetConfig("TakeoverTurnsRemaining", 0))..
		" atWar="..SC_BoolText(atWar)..
		" allowEndTurn="..SC_BoolText(allowEndTurn)..
		" blocker="..SC_GetBlockingDebug(player))
	SC_AuditPlayerUnits(player, "pass-begin:"..tostring(reason), SC_GetConfig("DebugUnitAuditFullPassBegin", true))
	local notificationHandled = 0
	if SC_ProcessNotificationQueue ~= nil then
		notificationHandled = SC_ProcessNotificationQueue(player, "pass:"..tostring(reason))
	end
	local results, cityDetails = SC_BuildAutomationResults(player, atWar)
	if results ~= nil then
		results.notifications = notificationHandled
	end
	if allowEndTurn then
		SC_TryAutoEndTurn(player)
	end
	results = results or {}
	SC_AuditPlayerUnits(player, "pass-end:"..tostring(reason), false)
	SC_Debug("pass end reason="..tostring(reason)..
		" city="..tostring(results.cityOrders or 0)..
		" research="..tostring(results.research or 0)..
		" policy="..tostring(results.policies or 0)..
		" promote="..tostring(results.promotions or 0)..
		" tactical="..tostring(results.defenseActions or 0)..
		" cityStrike="..tostring(results.cityStrikes or 0)..
		" strategicMove="..tostring(results.strategicMoves or 0)..
		" stacked="..tostring(results.stackedMoves or 0)..
		" finalOrders="..tostring(results.finalOrders or 0)..
		" notifications="..tostring(results.notifications or 0)..
		" popups="..tostring(results.popups or 0)..
		" diplo="..tostring(results.diplo or 0)..
		" blocker="..SC_GetBlockingDebug(player))
	return results, cityDetails, atWar
end

local function SC_StartTakeover(turns)
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
	local results, cityDetails = SC_BuildAutomationResults(player, atWar)
	SC_SendNotification(player, "战略指挥部", "手动执行完成[NEWLINE]城市安排: "..tostring(results.cityOrders or 0).."[NEWLINE]意识形态: "..tostring(results.ideologies or 0).."[NEWLINE]科研选择: "..tostring(results.research or 0).."[NEWLINE]政策选择: "..tostring(results.policies or 0).."[NEWLINE]单位升级: "..tostring(results.upgrades or 0).."[NEWLINE]单位晋升: "..tostring(results.promotions or 0).."[NEWLINE]战略机动: "..tostring(results.strategicMoves or 0).."[NEWLINE]贸易路线: "..tostring(results.tradeRoutes or 0).."[NEWLINE]世界议会: "..tostring(results.leagues or 0).."[NEWLINE]残留单位处理: "..tostring(results.finalOrders or 0).."[NEWLINE]弹窗处理: "..tostring(results.popups or 0))
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
		local b1 = noBelief
		if SC_GetSafeNumber(function() return player:HasCreatedPantheon() and 1 or 0 end, 0) <= 0 then
			b1 = SC_PickBelief(SC_GetAvailableBeliefs("GetAvailablePantheonBeliefs"), used) or noBelief
		end
		local b2 = SC_PickBelief(SC_GetAvailableBeliefs("GetAvailableFounderBeliefs"), used) or noBelief
		local b3 = SC_PickBelief(SC_GetAvailableBeliefs("GetAvailableFollowerBeliefs"), used) or noBelief
		local b4 = noBelief
		if SC_GetSafeNumber(function() return player:IsTraitBonusReligiousBelief() and 1 or 0 end, 0) > 0 then
			b4 = SC_PickBelief(SC_GetAvailableBeliefs("GetAvailableBonusBeliefs"), used) or noBelief
		end
		if b2 == noBelief or b3 == noBelief then
			return false
		end
		return pcall(function()
			Network.SendFoundReligion(Game.GetActivePlayer(), religionID, nil, b1, b2, b3, b4, cityX, cityY)
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
	elseif popupType == ButtonPopupTypes.BUTTONPOPUP_DIPLO_VOTE or popupType == ButtonPopupTypes.BUTTONPOPUP_VOTE_RESULTS or popupType == ButtonPopupTypes.BUTTONPOPUP_TECH_AWARD or popupType == ButtonPopupTypes.BUTTONPOPUP_NEW_ERA or popupType == ButtonPopupTypes.BUTTONPOPUP_LEAGUE_SPLASH or popupType == ButtonPopupTypes.BUTTONPOPUP_LEAGUE_PROJECT_COMPLETED or popupType == ButtonPopupTypes.BUTTONPOPUP_GREAT_PERSON_REWARD or popupType == ButtonPopupTypes.BUTTONPOPUP_GOLDEN_AGE_REWARD or popupType == ButtonPopupTypes.BUTTONPOPUP_WHOS_WINNING or popupType == ButtonPopupTypes.BUTTONPOPUP_GREAT_WORK_COMPLETED_ACTIVE_PLAYER or popupType == ButtonPopupTypes.BUTTONPOPUP_CITY_STATE_GREETING or popupType == ButtonPopupTypes.BUTTONPOPUP_CITY_STATE_MESSAGE or popupType == ButtonPopupTypes.BUTTONPOPUP_MINOR_GOLD_GIFT or popupType == ButtonPopupTypes.BUTTONPOPUP_NATURAL_WONDER_REWARD or popupType == ButtonPopupTypes.BUTTONPOPUP_GOODY_HUT_REWARD or popupType == ButtonPopupTypes.BUTTONPOPUP_ADVISOR_COUNSEL or popupType == ButtonPopupTypes.BUTTONPOPUP_EVENT or popupType == ButtonPopupTypes.BUTTONPOPUP_WONDER_COMPLETED_ACTIVE_PLAYER or popupType == ButtonPopupTypes.BUTTONPOPUP_WONDER_COMPLETED or popupType == ButtonPopupTypes.BUTTONPOPUP_TEXT or popupType == ButtonPopupTypes.BUTTONPOPUP_DECLAREWARMOVE or popupType == ButtonPopupTypes.BUTTONPOPUP_DECLAREWARRANGESTRIKE or popupType == ButtonPopupTypes.BUTTONPOPUP_DECLAREWAR_PLUNDER_TRADE_ROUTE then
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
	pcall(function() UI.SetLeaderHeadRootUp(false) end)
	pcall(function() UI.RequestLeaveLeader() end)
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
