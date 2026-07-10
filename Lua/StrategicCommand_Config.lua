-- Strategic Command configuration
-- Edit these values before loading a save/game.

SC_CONFIG = SC_CONFIG or {}

SC_CONFIG.Enabled = true
SC_CONFIG.InterventionInterval = 5
SC_CONFIG.TakeoverTurnsRemaining = 0

SC_CONFIG.DiplomacyProfile = "BALANCED"
SC_CONFIG.EconomyProfile = "BALANCED"
SC_CONFIG.BuildProfile = "INFRASTRUCTURE"
SC_CONFIG.DevelopmentProfile = "AUTO"
SC_CONFIG.ProductionProfile = "BUILDINGS"
SC_CONFIG.WarProfile = "ADVANCE"
SC_CONFIG.GreatPersonProfile = "SLEEP"
SC_CONFIG.ReligionProfile = "PRODUCTION"
SC_CONFIG.TradeProfile = "BALANCED"
SC_CONFIG.EspionageProfile = "DEFENSE"
SC_CONFIG.SelectedProfileKey = "DiplomacyProfile"
SC_CONFIG.CapturedCityAction = "PUPPET"

-- 默认进入接管模式；需要手动微操时可在面板里关闭对应项目。
SC_CONFIG.AutoCityProduction = true
SC_CONFIG.MinCityQueueLength = 3
SC_CONFIG.TargetCityQueueLength = 3
SC_CONFIG.WarQueueMilitarySlotsPerCity = 2
SC_CONFIG.WarFrontlineUnitsPerCity = 3
SC_CONFIG.WarSiegeUnitsPerCity = 1
SC_CONFIG.WarAirUnitsPerCity = 1
SC_CONFIG.WarNavalUnitsPerCoastalCity = 2
SC_CONFIG.MilitaryNeedScoreBonus = 1200

-- 本土防御：远程单位优先射击可达战争目标。
SC_CONFIG.AutoLocalDefense = true
SC_CONFIG.LocalDefenseMaxActions = 60
SC_CONFIG.MaxUnitTacticalStrikesPerTurn = 100
SC_CONFIG.MaxUnitTacticalStrikeRounds = 3
SC_CONFIG.MaxTacticalActionsPerUnitPerTurn = 2
SC_CONFIG.MaxAirTacticalActionsPerUnitPerTurn = 5
SC_CONFIG.MaxMissileTacticalActionsPerUnitPerTurn = 2
SC_CONFIG.MaxNavalTacticalActionsPerUnitPerTurn = 4
SC_CONFIG.MaxLandRangedTacticalActionsPerUnitPerTurn = 3
SC_CONFIG.MaxMultiAttackTacticalActions = 6
SC_CONFIG.MaxStrategicOrdersPerUnitPerTurn = 4
SC_CONFIG.MaxRangeStrikesPerCityPerTurn = 8
SC_CONFIG.MaxMissileStrikesPerCityPerTurn = 2
SC_CONFIG.MaxAirStrikesPerCityPerTurn = 4
SC_CONFIG.CityCaptureReadyDamageRatio = 0.72
SC_CONFIG.CapturedCityMaxDamageRatio = 0.45
SC_CONFIG.CityCaptureStagingSearchRadius = 2
SC_CONFIG.CaptureReadyAdjacentFirePenalty = 4200
SC_CONFIG.ProtectedAssetThreatRadius = 6
SC_CONFIG.OperationEnemyScreenRadius = 4
SC_CONFIG.OperationFocusRadius = 5
SC_CONFIG.ProtectedAssetRetreatDamage = 20
SC_CONFIG.RetreatThreatRadius = 5
SC_CONFIG.RetreatSearchRadius = 4

SC_CONFIG.AutoResearch = true
SC_CONFIG.AutoPolicy = true
SC_CONFIG.AutoUpgradeUnits = true
SC_CONFIG.AutoPromoteUnits = true
SC_CONFIG.AutoHealDamagedUnits = true
SC_CONFIG.AutoStrategicMove = true
SC_CONFIG.AutoIdlePosture = true
SC_CONFIG.AutoCityRangedStrike = true
SC_CONFIG.AutoPopupHandling = true
SC_CONFIG.AutoEndTurn = true
SC_CONFIG.PostEndTurnQuietMode = true
SC_CONFIG.AutoReligion = true
SC_CONFIG.AutoArchaeology = true
SC_CONFIG.AutoTradeRoutes = true
SC_CONFIG.AutoEspionage = true
SC_CONFIG.AutoCityCaptureFinishers = true
SC_CONFIG.AutoTransportEscort = true

SC_CONFIG.MaxAutoUpgradesPerTurn = 50
SC_CONFIG.MaxAutoPromotionsPerTurn = 80
SC_CONFIG.MaxAutoPromotionsPerUnitPerTurn = 20
SC_CONFIG.MaxAutoHealsPerTurn = 60
SC_CONFIG.MaxStrategicMovesPerTurn = 160
SC_CONFIG.MaxIdlePosturePerTurn = 80
SC_CONFIG.MaxFinalUnitOrdersPerTurn = 240
SC_CONFIG.MaxTakeoverPassesPerTurn = 6
SC_CONFIG.MaxCityStrikesPerTurn = 30
SC_CONFIG.HealDamageThreshold = 45
SC_CONFIG.MaxFinalUnitOrderRounds = 6
SC_CONFIG.MaxFinalOrderAttemptsPerUnitPerTurn = 5
SC_CONFIG.MaxTakeoverInnerSweeps = 5
SC_CONFIG.MaxNotificationsPerPass = 40
SC_CONFIG.MaxCityCaptureFinishersPerTurn = 20
SC_CONFIG.CityCaptureDirectMaxDistance = 2
SC_CONFIG.MaxTransportEscortMovesPerTurn = 30
SC_CONFIG.TransportEscortRadius = 2
SC_CONFIG.TransportThreatRadius = 6
SC_CONFIG.TransportEscortSearchRadius = 2
SC_CONFIG.TransportHoldWithoutEscort = true
SC_CONFIG.TransportMinimumEscorts = 1
SC_CONFIG.TransportEscortsUnderThreat = 2
SC_CONFIG.TransportConvoyAssemblyRadius = 4
SC_CONFIG.TransportConvoyWaypointRadius = 3
SC_CONFIG.TransportEscortOnlyWhenThreatened = true
SC_CONFIG.TransportCivilianRetreatUnderThreat = true
SC_CONFIG.TransportSevereThreatCount = 2
SC_CONFIG.DebugLogging = true
SC_CONFIG.DebugUnitCommands = true
SC_CONFIG.DebugUnitDecisions = true
SC_CONFIG.DebugCityProduction = true
SC_CONFIG.DebugUnitDecisionLimit = 90
SC_CONFIG.DebugUnitAudit = true
SC_CONFIG.DebugUnitAuditFullPassBegin = true
SC_CONFIG.DebugUnitAuditMaxUnitsPerPass = 500
SC_CONFIG.DemonstrationLogging = true
SC_CONFIG.DemonstrationFullSnapshots = true
SC_CONFIG.DemonstrationSnapshotOnEveryPlayerDoTurn = false
SC_CONFIG.DemonstrationMaxLinesPerTurn = 5000
SC_CONFIG.DemonstrationMaxUnitsPerSnapshot = 2500
SC_CONFIG.DemonstrationMaxCitiesPerSnapshot = 500
SC_CONFIG.DemonstrationInputLimitPerTurn = 1200
SC_CONFIG.PromotionActionFallbackWhenNotReady = false
SC_CONFIG.PromotionActionScanAllCombatUnits = false
SC_CONFIG.PromotionActionAllowAnyFallback = true
SC_CONFIG.PromotionActionFallbackAnyAfterCandidateFail = false
SC_CONFIG.DirectPromotionGrantFallback = true
SC_CONFIG.DebugPromotionCannotHandleDetails = false
SC_CONFIG.GreatPersonActionFallbackWhenBlocked = true
SC_CONFIG.AuditUserInput = true
SC_CONFIG.AuditUserInputLimitPerTurn = 120
SC_CONFIG.AggressivePopupDismissal = true
SC_CONFIG.ForceEndTurnWhenBlockerClear = true
SC_CONFIG.AutoEndTurnRetry = true
SC_CONFIG.AutoEndTurnRetryInterval = 0.75
SC_CONFIG.MaxAutoEndTurnSendsPerTurn = 6
SC_CONFIG.DirectPushMissionFallback = true
SC_CONFIG.DirectPushTargetedMissionFallback = true
SC_CONFIG.DirectPushMoveMissionFallback = true
SC_CONFIG.AvoidObsoleteFallbackUnits = true
SC_CONFIG.MaxFallbackUnitEraGap = 2
SC_CONFIG.MinLateGameFallbackCombatPower = 45
SC_CONFIG.RepeatedUnitReservationPenalty = 15
SC_CONFIG.ForceClearStuckUnitOrders = true
SC_CONFIG.AutoResolveStackedUnits = true
SC_CONFIG.MaxStackedUnitMovesPerTurn = 20
SC_CONFIG.MaxStackEscapeAttemptsPerUnitPerTurn = 8
SC_CONFIG.MaxStackEscapeCandidatesPerUnit = 10
SC_CONFIG.StackEscapeSearchRadius = 8
SC_CONFIG.EnableRangedReposition = true
SC_CONFIG.StrategicWaypointRadius = 5
SC_CONFIG.StrategicWaypointTriggerDistance = 5
SC_CONFIG.SupportFormationRadius = 2
SC_CONFIG.CarrierStandoffMinDistance = 6
SC_CONFIG.CarrierStandoffMaxDistance = 10
SC_CONFIG.ArsenalShipStandoffMinDistance = 5
SC_CONFIG.ArsenalShipStandoffMaxDistance = 8
SC_CONFIG.MissileScreenStandoffMinDistance = 1
SC_CONFIG.MissileScreenStandoffMaxDistance = 3
SC_CONFIG.SubmarineStandoffMinDistance = 2
SC_CONFIG.SubmarineStandoffMaxDistance = 4
SC_CONFIG.BallisticSubmarineStandoffMinDistance = 6
SC_CONFIG.BallisticSubmarineStandoffMaxDistance = 10
SC_CONFIG.FleetStandoffThreatRadius = 4

-- City production doctrine. Supported values: BALANCED, SCIENCE, INDUSTRY, WAR.
SC_CONFIG.Doctrine = "BALANCED"

-- If true, the mod posts a national brief every InterventionInterval turns.
SC_CONFIG.NationalBrief = true

-- Wait a little after entering a save before doing any automated work.
SC_CONFIG.StartDelayTurns = 1
