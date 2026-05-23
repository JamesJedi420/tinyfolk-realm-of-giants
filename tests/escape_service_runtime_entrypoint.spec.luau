--!nocheck

local MockPlayer = require("../tests/mocks/MockPlayer")
local MatchSimulation: any = require("../tests/harness/MatchSimulation")
local globalEnv = getfenv()

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(condition: boolean, label: string)
	assertEqual(condition, true, label)
end

local function assertFalse(condition: boolean, label: string)
	assertEqual(condition, false, label)
end

local routeAttributes: { [string]: any } = {
	ThroughGapReachAllowed = true,
	RouteType = "TraversalGap",
	TinyfolkOnlyRoute = true,
}

local routePart: any = {
	Name = "EscapeRoute_A",
	ClassName = "BasePart",
	Position = { x = 0, y = 0, z = 0 },
}

function routePart:IsA(className: string): boolean
	return className == "BasePart"
end

function routePart:GetAttribute(attributeName: string): any
	return routeAttributes[attributeName]
end

function routePart:SetAttribute(attributeName: string, value: any)
	routeAttributes[attributeName] = value
end

local fallbackRouteAttributes: { [string]: any } = {
	FallbackEscapeCandidate = true,
	FinalExitManaged = false,
	RouteEnabled = false,
	TinyfolkOnlyRoute = true,
}

local fallbackRoutePart: any = {
	Name = "EscapeRoute_B",
	ClassName = "BasePart",
	Position = { x = 5, y = 0, z = 0 },
}

function fallbackRoutePart:IsA(className: string): boolean
	return className == "BasePart"
end

function fallbackRoutePart:GetAttribute(attributeName: string): any
	return fallbackRouteAttributes[attributeName]
end

function fallbackRoutePart:SetAttribute(attributeName: string, value: any)
	fallbackRouteAttributes[attributeName] = value
end

local escapeRoutesFolder: any = {
	ClassName = "Folder",
}

function escapeRoutesFolder:FindFirstChild(_childName: string): any
	return nil
end

function escapeRoutesFolder:GetDescendants(): { any }
	local descendants = {}
	if globalEnv._routePartPresent == true then
		table.insert(descendants, routePart)
	end
	if globalEnv._fallbackRoutePartPresent == true then
		table.insert(descendants, fallbackRoutePart)
	end
	return descendants
end

local mapFolder: any = {
	ClassName = "Folder",
}

local tinyfolkReturnPoint: any = {
	Name = "TinyfolkReturnPoint",
	ClassName = "Part",
	Position = { x = 0, y = 2, z = -50 },
	CFrame = { Position = { x = 0, y = 2, z = -50 } },
}

local tinyfolkWorldFolder: any = {
	ClassName = "Folder",
}

function tinyfolkWorldFolder:FindFirstChild(childName: string): any
	if childName == "TinyfolkReturnPoint" then
		return tinyfolkReturnPoint
	end
	return nil
end

function mapFolder:FindFirstChild(childName: string): any
	if childName == "EscapeRoutes" then
		return escapeRoutesFolder
	end
	if childName == "TinyfolkWorld" then
		return tinyfolkWorldFolder
	end
	return nil
end

local workspaceService: any = {
	ClassName = "Workspace",
}

escapeRoutesFolder.Parent = mapFolder
mapFolder.Parent = workspaceService
routePart.Parent = escapeRoutesFolder
fallbackRoutePart.Parent = escapeRoutesFolder

globalEnv._routePartPresent = true
globalEnv._fallbackRoutePartPresent = false

function workspaceService:FindFirstChild(childName: string): any
	if childName == "Map" then
		return mapFolder
	end
	return nil
end

local playersByUserId: { [number]: any } = {}

local playersService: any = {}
playersService.GetPlayerByUserId = function(userId: number)
	return playersByUserId[userId]
end
playersService.GetPlayers = function()
	local players = {}
	for _, player in pairs(playersByUserId) do
		table.insert(players, player)
	end
	return players
end

local replicatedStorageService: any = {
	WaitForChild = function(_name: string)
		return {
			WaitForChild = function(childName: string)
				if childName == "Config" then
					return {
						WaitForChild = function(configName: string)
							if configName == "RoleConfig" then
								return { Roles = { Giant = "Giant", Tinyfolk = "Tinyfolk" } }
							end
							if configName == "EscapeConfig" then
								return {
									EscapeRouteNamePrefix = "EscapeRoute",
									TriggerRadiusStuds = 10,
									RequestCooldownSeconds = 5,
									DashTriggerRadiusStuds = 15,
									DashCooldownSeconds = 0.2,
									ThroughGapReachAllowedAttribute = "ThroughGapReachAllowed",
									RouteTypeAttribute = "RouteType",
									TinyfolkOnlyRouteAttribute = "TinyfolkOnlyRoute",
									CrossingPhaseAttribute = "CrossingPhase",
									RequiredCrossingPhase = "MidCrossing",
									SafeZoneAttribute = "InSafeZone",
									SafeZoneTypeAttribute = "SafeZoneType",
									SafeZoneProtectionEndsAtAttribute = "SafeZoneProtectionEndsAt",
									SafeZoneTypes = {
										SharedHub = "SharedHub",
										RealmEntry = "RealmEntry",
										RealmExit = "RealmExit",
									},
									SafeZoneAbuseWindowSeconds = 2,
									SafeZoneAbuseThreshold = 3,
									SafeZoneAbuseLockoutSeconds = 1,
									TraversalGapBlockStartupSeconds = 1,
									TraversalGapBlockActiveSeconds = 4,
									TraversalGapBlockRequestCooldownSeconds = 0.25,
									TraversalGapBlockStateAttribute = "TraversalGapBlockState",
									TraversalGapBlockStartupEndsAtAttribute = "TraversalGapBlockStartupEndsAt",
									TraversalGapBlockActiveEndsAtAttribute = "TraversalGapBlockActiveEndsAt",
									TraversalGapBlockExpiresAtAttribute = "TraversalGapBlockExpiresAt",
									TraversalGapBlockedByUserIdAttribute = "TraversalGapBlockedByUserId",
									TraversalGapBlockExemptAttribute = "TraversalGapBlockExempt",
									FinalExitManagedAttribute = "FinalExitManaged",
									FinalExitPhaseAttribute = "FinalExitPhase",
									FinalExitPoweredEndsAtAttribute = "FinalExitPoweredEndsAt",
									FinalExitOpeningEndsAtAttribute = "FinalExitOpeningEndsAt",
									FinalExitBlockedEndsAtAttribute = "FinalExitBlockedEndsAt",
									FinalExitResolvedAtAttribute = "FinalExitResolvedAt",
									FinalExitBlockedByUserIdAttribute = "FinalExitBlockedByUserId",
									FallbackEscapeCandidateAttribute = "FallbackEscapeCandidate",
									FallbackEscapePhaseAttribute = "FallbackEscapePhase",
									FallbackEscapeCueBandAttribute = "FallbackEscapeCueBand",
									FallbackEscapeClosedEndsAtAttribute = "FallbackEscapeClosedEndsAt",
									FallbackEscapeClosedByUserIdAttribute = "FallbackEscapeClosedByUserId",
									FinalExitPoweredDurationSeconds = 1,
									FinalExitOpeningDurationSeconds = 1,
									FinalExitBlockedDurationSeconds = 2,
									FinalExitReopenDurationSeconds = 1,
									FallbackEscapeOpenDelaySeconds = 1,
									FallbackEscapeCloseDurationSeconds = 2,
									SupportedThroughGapRouteTypes = { TraversalGap = true },
								}
							end
							if configName == "RescueContractConfig" then
								return {
									RequestCooldownSeconds = 0.2,
									TargetRealmOwnerUserIdAttribute = "GiantRealmOwnerUserId",
									RescueEntryRouteAttribute = "RescueEntryRoute",
									RescueEntryRouteKind = "RescueEntry",
								}
							end
							return nil
						end,
					}
				end
				return nil
			end,
		}
	end,
}

local MockGame: any = {}
MockGame.GetService = function(serviceName: string)
	if serviceName == "Players" then
		return playersService
	end
	if serviceName == "ReplicatedStorage" then
		return replicatedStorageService
	end
	if serviceName == "Workspace" then
		return workspaceService
	end
	return nil
end

globalEnv.game = MockGame
local currentTime = 100
local crossingHooks: { string } = {}
local downedByUserId: { [number]: boolean } = {}
local carriedByUserId: { [number]: boolean } = {}
local carrierEncumberedByUserId: { [number]: boolean } = {}
local objectiveThresholdMet = false
local roleQueryFault = false
local grabQueryFault = false
local transportQueryFault = false
local scoreQueryFault = false
local movementHookFault = false
globalEnv._RoleService_QueryAPI = {
	IsPlayerDowned = function(userId: number): boolean
		if roleQueryFault == true then
			error("role query fault")
		end
		return downedByUserId[userId] == true
	end,
	CanPlayerPerformInteraction = function(userId: number, interactionName: string): boolean
		if roleQueryFault == true then
			error("role query fault")
		end
		if downedByUserId[userId] == true and interactionName == "escapeAttempt" then
			return false
		end
		return true
	end,
}
globalEnv._GrabService_QueryAPI = {
	IsPlayerCarried = function(userId: number): boolean
		if grabQueryFault == true then
			error("grab query fault")
		end
		return carriedByUserId[userId] == true
	end,
	CanGiantPerformCarryInteraction = function(userId: number, _interactionName: string): any
		if grabQueryFault == true then
			error("grab query fault")
		end
		if carrierEncumberedByUserId[userId] == true then
			return { accepted = false, reason = "carrier_encumbered" }
		end
		return { accepted = true, reason = "accepted" }
	end,
}
globalEnv._RealmObjectiveService_QueryAPI = {
	IsEscapeObjectiveThresholdMet = function(): boolean
		return objectiveThresholdMet == true
	end,
}
local transportDepartureOutcome: any = {
	accepted = false,
	reason = "transport_not_departed",
	outcome = nil,
}
globalEnv._TransportEscapeService_QueryAPI = {
	ResolveTransportDepartureOutcome = function(_endpointId: string, _candidateTinyfolkUserIds: { number }): any
		if transportQueryFault == true then
			error("transport query fault")
		end
		return transportDepartureOutcome
	end,
}
globalEnv._ScoreService_QueryAPI = {
	RequestScoreEvent = function(_userId: number, _eventId: string, _at: number, _metadata: any)
		if scoreQueryFault == true then
			error("score query fault")
		end
		return { accepted = true, reason = "accepted" }
	end,
}
local EscapeService = require("../src/ServerScriptService/Services/EscapeService.server")(MockGame, {
	autoInitialize = true,
	clock = function()
		return currentTime
	end,
	disableBlockExpirationSchedule = true,
	tinyfolkMovementTraitService = {
		OnValidRouteCrossing = function(_player: any, routeId: string)
			if movementHookFault == true then
				error("movement hook fault")
			end
			table.insert(crossingHooks, routeId)
		end,
	},
})

local function resetRouteDefaults()
	routeAttributes.ThroughGapReachAllowed = true
	routeAttributes.RouteType = "TraversalGap"
	routeAttributes.TinyfolkOnlyRoute = true
	routeAttributes.InSafeZone = false
	routeAttributes.SafeZoneType = nil
	routeAttributes.SafeZoneProtectionEndsAt = nil
	routeAttributes.TraversalGapBlockExempt = false
	routeAttributes.TraversalGapBlockState = "Idle"
	routeAttributes.TraversalGapBlockStartupEndsAt = nil
	routeAttributes.TraversalGapBlockActiveEndsAt = nil
	routeAttributes.TraversalGapBlockExpiresAt = nil
	routeAttributes.TraversalGapBlockedByUserId = nil
	routeAttributes.RescueEntryRoute = false
	routeAttributes.GiantRealmOwnerUserId = nil
	routeAttributes.FinalExitManaged = true
	routeAttributes.FinalExitPhase = "Dormant"
	routeAttributes.FinalExitPoweredEndsAt = nil
	routeAttributes.FinalExitOpeningEndsAt = nil
	routeAttributes.FinalExitBlockedEndsAt = nil
	routeAttributes.FinalExitResolvedAt = nil
	routeAttributes.FinalExitBlockedByUserId = nil
	fallbackRouteAttributes.FallbackEscapeCandidate = true
	fallbackRouteAttributes.FinalExitManaged = false
	fallbackRouteAttributes.RouteEnabled = false
	fallbackRouteAttributes.TinyfolkOnlyRoute = true
	fallbackRouteAttributes.FallbackEscapePhase = "Inactive"
	fallbackRouteAttributes.FallbackEscapeCueBand = nil
	fallbackRouteAttributes.FallbackEscapeClosedEndsAt = nil
	fallbackRouteAttributes.FallbackEscapeClosedByUserId = nil
	globalEnv._fallbackRoutePartPresent = false
	fallbackRoutePart.Parent = nil
	currentTime = 100
	crossingHooks = {}
	playersByUserId = {}
	downedByUserId = {}
	carriedByUserId = {}
	carrierEncumberedByUserId = {}
	objectiveThresholdMet = false
	roleQueryFault = false
	grabQueryFault = false
	transportQueryFault = false
	scoreQueryFault = false
	movementHookFault = false
	EscapeService.ResetTraversalGapBlocksForTests()
	EscapeService.ResetEscapeAttemptStateForTests()
	EscapeService.ResetFinalExitForTests()
	EscapeService.ResetFallbackEscapeForTests()
	routeAttributes.RouteEnabled = true
end

local function advanceFinalExitToOpen(routeId: string?)
	local targetRouteId = if type(routeId) == "string" then routeId else "EscapeRoute_A"
	objectiveThresholdMet = true
	EscapeService.RefreshFinalExitStateForTests(targetRouteId)
	currentTime = 102
	EscapeService.RefreshFinalExitStateForTests(targetRouteId)
	currentTime = 105
	return EscapeService.RefreshFinalExitStateForTests(targetRouteId)
end

do
	resetRouteDefaults()
	routeAttributes.RescueEntryRoute = true
	routeAttributes.GiantRealmOwnerUserId = 9402

	local resolved = EscapeService.resolveRescueEntryRoute(1101, 9402)
	assertEqual(resolved.accepted, true, "rescue entry route resolver accepts matching realm route")
	assertEqual(resolved.routeId, "EscapeRoute_A", "rescue entry route resolver returns route id")
	assertEqual(resolved.routeKind, "RescueEntry", "rescue entry route resolver returns route kind")

	local mismatch = EscapeService.resolveRescueEntryRoute(1101, 9403)
	assertEqual(mismatch.accepted, false, "rescue entry route resolver rejects owner mismatch")
	assertEqual(mismatch.reason, "rescue_entry_route_missing", "rescue entry owner mismatch reason")

	routeAttributes.GiantRealmOwnerUserId = 9402
	routeAttributes.InSafeZone = true
	routeAttributes.SafeZoneType = "SharedHub"
	local protected = globalEnv._EscapeService_QueryAPI.ResolveRescueEntryRoute(1101, 9402)
	assertEqual(protected.accepted, false, "query rescue entry route rejects protected route")
	assertEqual(protected.reason, "rescue_entry_route_missing", "protected rescue entry route reason")

	globalEnv._routePartPresent = false
	routePart.Parent = nil
	local removed = EscapeService.resolveRescueEntryRoute(1101, 9402)
	assertEqual(removed.accepted, false, "removed rescue entry route rejects stale cache lookup")
	assertEqual(removed.reason, "rescue_entry_route_missing", "removed rescue entry route reason")
	globalEnv._routePartPresent = true
	routePart.Parent = escapeRoutesFolder
end

do
	resetRouteDefaults()
	routeAttributes.FinalExitManaged = false
	routeAttributes.RouteEnabled = true
	local tinyfolk = MockPlayer.new(60, "AccessTinyfolk", { role = "Tinyfolk" })
	local giant = MockPlayer.new(61, "AccessGiant", { role = "Giant" })

	local invalidAccess = EscapeService.getRouteAccess(tinyfolk, nil)
	assertEqual(invalidAccess.accepted, false, "invalid route access id rejects")
	assertEqual(invalidAccess.reason, "route_id_invalid", "invalid route access id reason")

	local missingAccess = EscapeService.getRouteAccess(tinyfolk, "EscapeRoute_Missing")
	assertEqual(missingAccess.accepted, false, "missing route access rejects")
	assertEqual(missingAccess.reason, "route_not_found", "missing route access reason")

	local tinyfolkAccess = EscapeService.getRouteAccess(tinyfolk, "EscapeRoute_A")
	assertEqual(tinyfolkAccess.accepted, true, "Tinyfolk access query accepts Tinyfolk-only route")
	assertEqual(tinyfolkAccess.tinyfolkOnly, true, "Tinyfolk-only metadata projected")

	routeAttributes.RouteEnabled = false
	local giantAccess = globalEnv._EscapeService_QueryAPI.GetRouteAccess(giant, "EscapeRoute_A")
	assertEqual(giantAccess.accepted, false, "Giant access query rejects Tinyfolk-only route")
	assertEqual(giantAccess.reason, "requester_not_tinyfolk", "Giant access rejection reason")

	routeAttributes.TinyfolkOnlyRoute = false
	local malformedMetadataGiantAccess = EscapeService.getRouteAccess(giant, "EscapeRoute_A")
	assertEqual(
		malformedMetadataGiantAccess.accepted,
		false,
		"Giant access rejects even with malformed Tinyfolk-only metadata"
	)
	assertEqual(malformedMetadataGiantAccess.reason, "requester_not_tinyfolk", "malformed metadata Giant access reason")
	routeAttributes.TinyfolkOnlyRoute = true

	local disabledAccess = EscapeService.getRouteAccess(tinyfolk, "EscapeRoute_A")
	assertEqual(disabledAccess.accepted, false, "disabled route rejects access query")
	assertEqual(disabledAccess.reason, "route_disabled", "disabled route access reason")

	local disabledEscape = EscapeService.requestEscapeAttempt(tinyfolk, "EscapeRoute_A")
	assertEqual(disabledEscape.accepted, false, "disabled route rejects escape attempt")
	assertEqual(disabledEscape.reason, "route_disabled", "disabled route escape reason")

	EscapeService.ResetFinalExitForTests()
	local disabledAfterReset = EscapeService.getRouteAccess(tinyfolk, "EscapeRoute_A")
	assertEqual(disabledAfterReset.accepted, false, "non-managed final-exit reset preserves disabled route")
	assertEqual(disabledAfterReset.reason, "route_disabled", "disabled route preserved reason")
end

do
	resetRouteDefaults()
	routeAttributes.FinalExitManaged = false
	routeAttributes.RouteEnabled = true
	local giant = MockPlayer.new(62, "BlockingAccessGiant", { role = "Giant" })
	local tinyfolk = MockPlayer.new(63, "BlockedAccessTinyfolk", { role = "Tinyfolk" })
	local block = EscapeService.requestTraversalGapBlock(giant, "EscapeRoute_A")
	currentTime = 101
	local blockedAccess = EscapeService.getRouteAccess(tinyfolk, "EscapeRoute_A")

	assertEqual(block.accepted, true, "access block setup accepted")
	assertEqual(blockedAccess.accepted, false, "active block rejects route access query")
	assertEqual(blockedAccess.reason, "traversal_gap_block_active", "active block access reason")
end

do
	resetRouteDefaults()
	routeAttributes.FinalExitManaged = false
	routeAttributes.RouteEnabled = true
	assertTrue(
		EscapeService.getObjectiveSafeRouteMetadata(nil :: any) ~= nil,
		"objective all-route metadata query accepts nil"
	)
	assertTrue(
		EscapeService.getObjectiveSafeRouteMetadata(123 :: any) == nil,
		"objective metadata rejects non-string route id"
	)
	assertTrue(
		EscapeService.getObjectiveSafeRouteMetadata("EscapeRoute_Missing") == nil,
		"objective metadata rejects missing route id"
	)

	local metadata = EscapeService.getObjectiveSafeRouteMetadata("EscapeRoute_A")
	assertEqual(metadata.routeId, "EscapeRoute_A", "objective route metadata includes route id")
	assertEqual(metadata.tinyfolkOnly, true, "objective route metadata includes Tinyfolk-only flag")
	assertEqual(metadata.isEnabled, true, "objective route metadata includes enabled flag")
	assertTrue(metadata.position == nil, "objective route metadata omits exact position")
	assertTrue(metadata.blockedByUserId == nil, "objective route metadata omits blocker identity")
end

do
	resetRouteDefaults()
	local tinyfolk = MockPlayer.new(64, "DormantAccessTinyfolk", { role = "Tinyfolk" })
	local access = EscapeService.getRouteAccess(tinyfolk, "EscapeRoute_A")
	assertEqual(access.accepted, false, "managed dormant final exit rejects route access")
	assertEqual(access.reason, "final_exit_dormant", "managed dormant route access reason")

	objectiveThresholdMet = true
	EscapeService.RefreshFinalExitStateForTests("EscapeRoute_A")
	currentTime = 102
	EscapeService.RefreshFinalExitStateForTests("EscapeRoute_A")
	currentTime = 105
	local openAccess = EscapeService.getRouteAccess(tinyfolk, "EscapeRoute_A")
	assertEqual(openAccess.accepted, true, "managed open final exit accepts route access")
	assertEqual(openAccess.finalExitPhase, "Open", "managed open route access exposes final-exit phase")
end

do
	resetRouteDefaults()
	globalEnv._fallbackRoutePartPresent = true
	fallbackRoutePart.Parent = escapeRoutesFolder
	local firstTinyfolk = MockPlayer.new(6501, "FallbackFirstTinyfolk", { role = "Tinyfolk" })
	local secondTinyfolk = MockPlayer.new(6502, "FallbackSecondTinyfolk", { role = "Tinyfolk" })
	local giant = MockPlayer.new(6503, "FallbackClosingGiant", { role = "Giant" })
	playersByUserId[6501] = firstTinyfolk
	playersByUserId[6502] = secondTinyfolk
	playersByUserId[6503] = giant

	local teamAccess = EscapeService.getRouteAccess(firstTinyfolk, "EscapeRoute_B")
	assertEqual(teamAccess.accepted, false, "fallback route inactive while team has multiple active Tinyfolk")
	assertEqual(teamAccess.reason, "fallback_escape_inactive", "fallback team access reason")

	playersByUserId[6502] = nil
	local searchingAccess = EscapeService.getRouteAccess(firstTinyfolk, "EscapeRoute_B")
	assertEqual(searchingAccess.accepted, false, "last Tinyfolk fallback starts in search phase")
	assertEqual(searchingAccess.reason, "fallback_escape_searching", "fallback searching access reason")
	assertEqual(fallbackRouteAttributes.FallbackEscapePhase, "Searching", "fallback searching phase projected")
	assertEqual(fallbackRouteAttributes.FallbackEscapeCueBand, "local_search", "fallback local cue projected")

	currentTime = 102
	local openAccess = EscapeService.getRouteAccess(firstTinyfolk, "EscapeRoute_B")
	assertEqual(openAccess.reason, "accepted", "last Tinyfolk fallback open access reason")
	assertEqual(openAccess.accepted, true, "last Tinyfolk fallback opens after delay")
	assertEqual(openAccess.fallbackEscapePhase, "Open", "fallback open phase returned")

	local close = EscapeService.requestFallbackEscapeClose(giant, "EscapeRoute_B")
	assertEqual(close.accepted, true, "Giant can close open fallback route")
	assertEqual(close.reason, "closed", "fallback close accepted reason")
	assertEqual(fallbackRouteAttributes.FallbackEscapePhase, "Closed", "fallback close phase projected")
	assertEqual(fallbackRouteAttributes.FallbackEscapeClosedByUserId, giant.UserId, "fallback close user projected")

	currentTime = 103
	local closedEscape = EscapeService.requestEscapeAttempt(firstTinyfolk, "EscapeRoute_B")
	assertEqual(closedEscape.accepted, false, "closed fallback rejects escape")
	assertEqual(closedEscape.reason, "fallback_escape_closed", "closed fallback escape reason")

	currentTime = 107
	local reopenedAccess = EscapeService.getRouteAccess(firstTinyfolk, "EscapeRoute_B")
	assertEqual(reopenedAccess.accepted, true, "fallback reopens after close window")
	assertEqual(reopenedAccess.fallbackEscapePhase, "Open", "fallback reopened phase returned")

	local escaped = EscapeService.requestEscapeAttempt(firstTinyfolk, "EscapeRoute_B")
	assertEqual(escaped.accepted, true, "open fallback accepts last Tinyfolk escape")
	assertEqual(fallbackRouteAttributes.FallbackEscapePhase, "Resolved", "fallback resolves after escape")
	assertEqual(firstTinyfolk:GetAttribute("Escaped"), true, "fallback escape marks Tinyfolk escaped")
	assertEqual(crossingHooks[1], "EscapeRoute_B", "fallback escape preserves route-crossing hook")

	local resolvedAttempt = EscapeService.requestEscapeAttempt(firstTinyfolk, "EscapeRoute_B")
	assertEqual(resolvedAttempt.accepted, false, "resolved fallback rejects later escape")
	assertEqual(resolvedAttempt.reason, "already_escaped", "resolved fallback escaped player reason")
end

do
	resetRouteDefaults()
	globalEnv._fallbackRoutePartPresent = true
	fallbackRoutePart.Parent = escapeRoutesFolder
	local activeTinyfolk = MockPlayer.new(6511, "FallbackActiveTinyfolk", { role = "Tinyfolk" })
	local downedTinyfolk = MockPlayer.new(6512, "FallbackDownedTinyfolk", { role = "Tinyfolk" })
	playersByUserId[6511] = activeTinyfolk
	playersByUserId[6512] = downedTinyfolk
	downedByUserId[6512] = true
	roleQueryFault = true

	local faultedAccess = EscapeService.getRouteAccess(activeTinyfolk, "EscapeRoute_B")
	assertEqual(faultedAccess.accepted, false, "downed query fault keeps fallback inactive with uncertain second Tinyfolk")
	assertEqual(faultedAccess.reason, "fallback_escape_inactive", "downed query fault fallback reason")

	roleQueryFault = false
	local searchingAccess = EscapeService.getRouteAccess(activeTinyfolk, "EscapeRoute_B")
	assertEqual(searchingAccess.accepted, false, "downed second Tinyfolk excluded after query recovers")
	assertEqual(searchingAccess.reason, "fallback_escape_searching", "recovered downed query fallback reason")
end

do
	resetRouteDefaults()
	local dormantTinyfolk = MockPlayer.new(70, "DormantTinyfolk", { role = "Tinyfolk" })
	local dormantAttempt = EscapeService.requestEscapeAttempt(dormantTinyfolk, "EscapeRoute_A")
	assertEqual(dormantAttempt.accepted, false, "dormant final exit rejects route escape")
	assertEqual(dormantAttempt.reason, "final_exit_dormant", "dormant final exit reason")

	objectiveThresholdMet = true
	local poweredTinyfolk = MockPlayer.new(71, "PoweredTinyfolk", { role = "Tinyfolk" })
	local poweredAttempt = EscapeService.requestEscapeAttempt(poweredTinyfolk, "EscapeRoute_A")
	assertEqual(poweredAttempt.accepted, false, "powered final exit rejects route escape")
	assertEqual(poweredAttempt.reason, "final_exit_powered", "powered final exit reason")
	assertEqual(routeAttributes.FinalExitPhase, "Powered", "powered phase projected to route attributes")

	currentTime = 102
	local openingTinyfolk = MockPlayer.new(72, "OpeningTinyfolk", { role = "Tinyfolk" })
	local openingAttempt = EscapeService.requestEscapeAttempt(openingTinyfolk, "EscapeRoute_A")
	assertEqual(openingAttempt.accepted, false, "opening final exit rejects route escape")
	assertEqual(openingAttempt.reason, "final_exit_opening", "opening final exit reason")
	assertEqual(routeAttributes.FinalExitPhase, "Opening", "opening phase projected to route attributes")

	currentTime = 105
	local openTinyfolk = MockPlayer.new(73, "OpenTinyfolk", { role = "Tinyfolk" })
	local openAttempt = EscapeService.requestEscapeAttempt(openTinyfolk, "EscapeRoute_A")
	assertEqual(openAttempt.accepted, true, "open final exit accepts route escape")
	assertEqual(routeAttributes.FinalExitPhase, "Resolved", "successful escape resolves final exit")
	assertEqual(routeAttributes.FinalExitResolvedAt, 105, "resolved timestamp projected to route attributes")

	local resolvedTinyfolk = MockPlayer.new(74, "ResolvedTinyfolk", { role = "Tinyfolk" })
	local resolvedAttempt = EscapeService.requestEscapeAttempt(resolvedTinyfolk, "EscapeRoute_A")
	assertEqual(resolvedAttempt.accepted, false, "resolved final exit rejects later route escape")
	assertEqual(resolvedAttempt.reason, "final_exit_resolved", "resolved final exit reason")
end

do
	resetRouteDefaults()
	roleQueryFault = true
	routeAttributes.FinalExitManaged = false
	local tinyfolk = MockPlayer.new(78, "FaultyRoleTinyfolk", { role = "Tinyfolk" })
	local roleFaultAttempt = EscapeService.requestEscapeAttempt(tinyfolk, "EscapeRoute_A")
	assertEqual(roleFaultAttempt.accepted, false, "role query error does not crash escape attempt")
	assertEqual(roleFaultAttempt.reason, "role_query_fault", "role query fault reason")
end

do
	resetRouteDefaults()
	grabQueryFault = true
	routeAttributes.FinalExitManaged = false
	local tinyfolk = MockPlayer.new(79, "FaultyGrabTinyfolk", { role = "Tinyfolk" })
	local grabFaultAttempt = EscapeService.requestEscapeAttempt(tinyfolk, "EscapeRoute_A")
	assertEqual(grabFaultAttempt.accepted, false, "grab query error does not crash escape attempt")
	assertEqual(grabFaultAttempt.reason, "grab_query_fault", "grab query fault reason")
end

do
	resetRouteDefaults()
	transportQueryFault = true
	local result = EscapeService.resolveTransportDeparture("Transport_A", { 31, 32 })
	assertFalse(result.accepted, "transport query error does not crash departure resolution")
	assertEqual(result.reason, "transport_query_fault", "transport query fault reason")
end

do
	resetRouteDefaults()
	local originalObjectiveApi = globalEnv._RealmObjectiveService_QueryAPI
	globalEnv._RealmObjectiveService_QueryAPI = {
		IsEscapeObjectiveThresholdMet = function(): boolean
			error("objective query fault")
			return false
		end,
	}

	local tinyfolk = MockPlayer.new(77, "FaultyObjectiveTinyfolk", { role = "Tinyfolk" })
	local attempt = EscapeService.requestEscapeAttempt(tinyfolk, "EscapeRoute_A")
	assertEqual(attempt.accepted, false, "objective query error does not crash escape attempt")
	assertEqual(attempt.reason, "final_exit_dormant", "objective query error falls back to dormant gate")

	globalEnv._RealmObjectiveService_QueryAPI = originalObjectiveApi
end

do
	resetRouteDefaults()
	advanceFinalExitToOpen("EscapeRoute_A")
	local giant = MockPlayer.new(75, "BlockingGiant", { role = "Giant" })
	local block = EscapeService.requestTraversalGapBlock(giant, "EscapeRoute_A")
	assertEqual(block.accepted, true, "blocking final exit setup accepted")
	assertEqual(routeAttributes.FinalExitPhase, "Open", "startup block leaves final exit open before active block")

	currentTime = 106
	local blockedSnapshot = EscapeService.RefreshFinalExitStateForTests("EscapeRoute_A")
	assertEqual(blockedSnapshot.phase, "Blocked", "active traversal block pushes final exit to blocked")
	assertEqual(routeAttributes.FinalExitBlockedByUserId, 75, "blocked final exit tracks Giant user id")

	local tinyfolk = MockPlayer.new(76, "BlockedTinyfolk", { role = "Tinyfolk" })
	local blockedAttempt = EscapeService.requestEscapeAttempt(tinyfolk, "EscapeRoute_A")
	assertEqual(blockedAttempt.accepted, false, "blocked final exit rejects route escape")
	assertEqual(blockedAttempt.reason, "final_exit_blocked", "blocked final exit reason")

	currentTime = 110
	local reopeningSnapshot = EscapeService.RefreshFinalExitStateForTests("EscapeRoute_A")
	assertEqual(reopeningSnapshot.phase, "Opening", "blocked final exit re-enters opening after block window")

	currentTime = 112
	local reopenedSnapshot = EscapeService.RefreshFinalExitStateForTests("EscapeRoute_A")
	assertEqual(reopenedSnapshot.phase, "Open", "reopening final exit returns to open")
end

do
	resetRouteDefaults()
	routeAttributes.InSafeZone = true
	routeAttributes.SafeZoneType = "SharedHub"
	routeAttributes.FinalExitManaged = false
	local player = MockPlayer.new(1, "TinyfolkPlayer", { role = "Tinyfolk" })

	local result = EscapeService.requestEscapeAttempt(player, "EscapeRoute_A")
	assertEqual(result.accepted, false, "shared hub safe-zone rejects direct escape")
	assertEqual(result.reason, "shared_hub_no_capture", "shared hub safe-zone escape reason")
end

do
	resetRouteDefaults()
	routeAttributes.InSafeZone = true
	routeAttributes.SafeZoneType = "RealmExit"
	routeAttributes.FinalExitManaged = false
	local player = MockPlayer.new(1, "TinyfolkPlayer", { role = "Tinyfolk" })

	local result = EscapeService.requestEscapeAttempt(player, "EscapeRoute_A")
	assertEqual(result.accepted, false, "realm exit safe-zone rejects direct escape")
	assertEqual(result.reason, "realm_exit_protected", "realm exit safe-zone escape reason")
end

do
	resetRouteDefaults()
	routeAttributes.InSafeZone = true
	routeAttributes.SafeZoneType = "RealmEntry"
	routeAttributes.SafeZoneProtectionEndsAt = 101
	routeAttributes.FinalExitManaged = false
	local player = MockPlayer.new(1, "TinyfolkPlayer", { role = "Tinyfolk" })

	local activeProtectionResult = EscapeService.requestEscapeAttempt(player, "EscapeRoute_A")
	assertEqual(activeProtectionResult.accepted, false, "realm entry active protection rejects direct escape")
	assertEqual(activeProtectionResult.reason, "realm_entry_protected", "realm entry active escape reason")

	currentTime = 102
	local expiredProtectionResult = EscapeService.requestEscapeAttempt(player, "EscapeRoute_A")
	assertEqual(expiredProtectionResult.accepted, true, "realm entry expired protection allows direct escape")
end

do
	resetRouteDefaults()
	routeAttributes.InSafeZone = true
	routeAttributes.SafeZoneType = "InvalidSafeZoneType"
	routeAttributes.FinalExitManaged = false
	local player = MockPlayer.new(1, "TinyfolkPlayer", { role = "Tinyfolk" })

	local result = EscapeService.requestEscapeAttempt(player, "EscapeRoute_A")
	assertEqual(result.accepted, false, "unknown safe-zone type rejects direct escape")
	assertEqual(result.reason, "safe_zone_type_unknown", "unknown safe-zone escape reason")
end

do
	resetRouteDefaults()
	routeAttributes.InSafeZone = true
	routeAttributes.SafeZoneType = nil
	routeAttributes.FinalExitManaged = false
	local player = MockPlayer.new(1, "TinyfolkPlayer", { role = "Tinyfolk" })

	local result = EscapeService.requestEscapeAttempt(player, "EscapeRoute_A")
	assertEqual(result.accepted, false, "missing safe-zone type rejects direct escape")
	assertEqual(result.reason, "safe_zone_type_missing", "missing safe-zone type escape reason")
end

do
	resetRouteDefaults()
	routeAttributes.FinalExitManaged = false
	scoreQueryFault = true
	local tinyfolk = MockPlayer.new(80, "FaultyScoreTinyfolk", { role = "Tinyfolk" })
	local result = EscapeService.requestEscapeAttempt(tinyfolk, "EscapeRoute_A")
	assertEqual(result.accepted, true, "score query fault does not crash escape acceptance")
	assertEqual(result.reason, "accepted", "score query fault keeps accepted reason")
end

do
	resetRouteDefaults()
	routeAttributes.FinalExitManaged = false
	movementHookFault = true
	local tinyfolk = MockPlayer.new(81, "FaultyMovementHookTinyfolk", { role = "Tinyfolk" })
	local result = EscapeService.requestEscapeAttempt(tinyfolk, "EscapeRoute_A")
	assertEqual(result.accepted, true, "movement hook fault does not crash escape acceptance")
	assertEqual(result.reason, "accepted", "movement hook fault keeps accepted reason")
end

do
	resetRouteDefaults()
	routeAttributes.InSafeZone = true
	routeAttributes.SafeZoneType = "SharedHub"
	objectiveThresholdMet = true
	local player = MockPlayer.new(1, "TinyfolkPlayer", { role = "Tinyfolk" })

	local result = EscapeService.requestEscapeAttempt(player, "EscapeRoute_A")
	assertEqual(result.accepted, false, "safe-zone gate takes precedence over final-exit gate")
	assertEqual(result.reason, "shared_hub_no_capture", "safe-zone precedence reason is preserved")
end

do
	resetRouteDefaults()
	local boardedTinyfolk = MockPlayer.new(31, "TinyfolkBoarded", { role = "Tinyfolk" })
	local unboardedTinyfolk = MockPlayer.new(32, "TinyfolkUnboarded", { role = "Tinyfolk" })
	unboardedTinyfolk:SetAttribute("Escaped", true)
	playersByUserId[31] = boardedTinyfolk
	playersByUserId[32] = unboardedTinyfolk

	transportDepartureOutcome = {
		accepted = true,
		reason = "accepted",
		outcome = {
			canResolve = true,
			boardedEscapedUserIds = { 31 },
			unboardedRemainingUserIds = { 32 },
		},
	}

	local result = EscapeService.resolveTransportDeparture("Transport_A", { 31, 32 })
	assertTrue(result.accepted, "transport departure resolution accepted")
	assertEqual(boardedTinyfolk:GetAttribute("Escaped"), true, "boarded tinyfolk marked escaped")
	assertEqual(unboardedTinyfolk:GetAttribute("Escaped"), false, "unboarded tinyfolk remains not escaped")
	assertTrue(unboardedTinyfolk.Character.LastPivotCFrame ~= nil, "unboarded tinyfolk moved to return point")
	assertEqual(
		unboardedTinyfolk.Character.LastPivotCFrame.Position.z,
		-50,
		"unboarded tinyfolk relocated to configured return point"
	)
	assertEqual(#result.escapedUserIds, 1, "transport resolution escaped user count")
	assertEqual(#result.safeReturnedUserIds, 1, "transport resolution safe-return count")
	assertEqual(#result.unresolvedUserIds, 0, "transport resolution leaves no unresolved users")
end

do
	resetRouteDefaults()
	local overlappingTinyfolk = MockPlayer.new(33, "TinyfolkOverlapping", { role = "Tinyfolk" })
	playersByUserId[33] = overlappingTinyfolk

	transportDepartureOutcome = {
		accepted = true,
		reason = "accepted",
		outcome = {
			canResolve = true,
			boardedEscapedUserIds = { 33, 33 },
			unboardedRemainingUserIds = { 33, 33 },
		},
	}

	local result = EscapeService.resolveTransportDeparture("Transport_A", { 33 })
	assertTrue(result.accepted, "transport overlap resolution accepted")
	assertEqual(overlappingTinyfolk:GetAttribute("Escaped"), true, "boarded outcome wins over unboarded overlap")
	assertEqual(#result.escapedUserIds, 1, "transport overlap escaped ids deduplicated")
	assertEqual(#result.safeReturnedUserIds, 0, "transport overlap does not relocate boarded tinyfolk")
	assertEqual(#result.unresolvedUserIds, 0, "transport overlap leaves no unresolved users")
end

do
	resetRouteDefaults()
	local candidateTinyfolk = MockPlayer.new(34, "TinyfolkCandidate", { role = "Tinyfolk" })
	local staleTinyfolk = MockPlayer.new(35, "TinyfolkStale", { role = "Tinyfolk" })
	staleTinyfolk:SetAttribute("Escaped", true)
	playersByUserId[34] = candidateTinyfolk
	playersByUserId[35] = staleTinyfolk

	transportDepartureOutcome = {
		accepted = true,
		reason = "accepted",
		outcome = {
			canResolve = true,
			boardedEscapedUserIds = { 35 },
			unboardedRemainingUserIds = { 35 },
		},
	}

	local result = EscapeService.resolveTransportDeparture("Transport_A", { 34 })
	assertTrue(result.accepted, "transport stale-id resolution accepted")
	assertEqual(#result.escapedUserIds, 0, "transport stale boarded ids ignored")
	assertEqual(#result.safeReturnedUserIds, 0, "transport stale unboarded ids ignored")
	assertEqual(staleTinyfolk:GetAttribute("Escaped"), true, "transport stale ids do not mutate non-candidate state")
	assertEqual(candidateTinyfolk:GetAttribute("Escaped"), nil, "candidate state unchanged when absent from outcome")
end

do
	resetRouteDefaults()
	globalEnv._routePartPresent = false
	routePart.Parent = nil
	local metadataAfterRemoval = EscapeService.getObjectiveSafeRouteMetadata(nil :: any)
	local accessAfterRemoval =
		EscapeService.getRouteAccess(MockPlayer.new(90, "RemovedRouteTinyfolk", { role = "Tinyfolk" }), "EscapeRoute_A")
	assertEqual(#metadataAfterRemoval, 0, "removed route omitted from objective route metadata")
	assertEqual(accessAfterRemoval.accepted, false, "removed route rejects access after cache invalidation")
	assertEqual(accessAfterRemoval.reason, "route_not_found", "removed route lookup reason")
	globalEnv._routePartPresent = true
	routePart.Parent = escapeRoutesFolder
end

do
	resetRouteDefaults()
	advanceFinalExitToOpen("EscapeRoute_A")
	local boardedTinyfolk = MockPlayer.new(41, "TransportFinalExitTinyfolk", { role = "Tinyfolk" })
	playersByUserId[41] = boardedTinyfolk

	transportDepartureOutcome = {
		accepted = true,
		reason = "accepted",
		outcome = {
			canResolve = true,
			routeId = "EscapeRoute_A",
			boardedEscapedUserIds = { 41 },
			unboardedRemainingUserIds = {},
		},
	}

	local result = EscapeService.resolveTransportDeparture("Transport_A", { 41 })
	assertTrue(result.accepted, "transport final-exit convergence accepted")
	assertEqual(result.resolvedTransportFinalExit, true, "transport departure resolves final-exit route")
	assertEqual(routeAttributes.FinalExitPhase, "Resolved", "transport departure marks final-exit as resolved")

	local lateTinyfolk = MockPlayer.new(42, "LateTransportTinyfolk", { role = "Tinyfolk" })
	local lateAttempt = EscapeService.requestEscapeAttempt(lateTinyfolk, "EscapeRoute_A")
	assertEqual(lateAttempt.accepted, false, "resolved final-exit rejects post-transport route escape")
	assertEqual(lateAttempt.reason, "final_exit_resolved", "post-transport route rejection reason")
end

do
	resetRouteDefaults()
	transportDepartureOutcome = {
		accepted = false,
		reason = "transport_not_departed",
		outcome = nil,
	}

	local result = EscapeService.resolveTransportDeparture("Transport_A", { 31, 32 })
	assertFalse(result.accepted, "transport not departed resolution rejected")
	assertEqual(result.reason, "transport_not_departed", "transport not departed rejection reason")
end

local function makeRequest(overrides: any?): any
	local request: any = {
		routeId = "EscapeRoute_A",
		lineOfSightCheck = function()
			return true
		end,
	}

	if overrides ~= nil then
		for key, value in overrides do
			request[key] = value
		end
	end

	return request
end

do
	resetRouteDefaults()
	local player = MockPlayer.new(1, "GiantPlayer")
	local target = MockPlayer.new(2, "TinyfolkPlayer", { crossingPhase = "MidCrossing" })
	playersByUserId[2] = target

	local result = EscapeService.validateThroughGapReach(player, target, makeRequest())
	assertEqual(result, true, "explicit allowed gap accepts valid reach")
end

do
	resetRouteDefaults()
	routeAttributes.ThroughGapReachAllowed = nil
	local player = MockPlayer.new(1, "GiantPlayer")
	local target = MockPlayer.new(2, "TinyfolkPlayer")
	playersByUserId[2] = target

	local result = EscapeService.validateThroughGapReach(player, target, makeRequest())
	assertEqual(result, false, "missing allowlist metadata rejects")
end

do
	resetRouteDefaults()
	routeAttributes.RouteType = "OpenField"
	local player = MockPlayer.new(1, "GiantPlayer")
	local target = MockPlayer.new(2, "TinyfolkPlayer")
	playersByUserId[2] = target

	local result = EscapeService.validateThroughGapReach(player, target, makeRequest())
	assertEqual(result, false, "unsupported route type rejects")
end

do
	resetRouteDefaults()
	local player = MockPlayer.new(1, "TinyfolkPlayer", { role = "Tinyfolk" })
	local target = MockPlayer.new(2, "TinyfolkPlayer")
	playersByUserId[2] = target

	local result = EscapeService.validateThroughGapReach(player, target, makeRequest())
	assertEqual(result, false, "non-Giant caller rejects")
end

do
	resetRouteDefaults()
	local player = MockPlayer.new(1, "GiantPlayer", { role = "Giant" })
	local target = MockPlayer.new(2, "GiantTarget", { role = "Giant" })
	playersByUserId[2] = target

	local result = EscapeService.validateThroughGapReach(player, target, makeRequest())
	assertEqual(result, false, "invalid or non-Tinyfolk target rejects")
end

do
	resetRouteDefaults()
	local player = MockPlayer.new(1, "GiantPlayer", { role = "Giant", hasRoot = false })
	local target = MockPlayer.new(2, "TinyfolkPlayer")
	playersByUserId[2] = target

	local result = EscapeService.validateThroughGapReach(player, target, makeRequest())
	assertEqual(result, false, "missing character/root rejects")
end

do
	resetRouteDefaults()
	local player = MockPlayer.new(1, "GiantPlayer", { role = "Giant", positionZ = 0 })
	local target = MockPlayer.new(2, "TinyfolkPlayer", { positionZ = 40 })
	playersByUserId[2] = target

	local result = EscapeService.validateThroughGapReach(player, target, makeRequest())
	assertEqual(result, false, "out-of-range rejects")
end

do
	resetRouteDefaults()
	local player = MockPlayer.new(1, "GiantPlayer")
	local target = MockPlayer.new(2, "TinyfolkPlayer", { inSafeZone = true })
	playersByUserId[2] = target

	local result = EscapeService.validateThroughGapReach(player, target, makeRequest())
	assertEqual(result, false, "safe-zone target rejects")
end

do
	resetRouteDefaults()
	routeAttributes.InSafeZone = true
	routeAttributes.SafeZoneType = "SharedHub"
	local player = MockPlayer.new(1, "GiantPlayer")
	local target = MockPlayer.new(2, "TinyfolkPlayer", { crossingPhase = "MidCrossing" })
	playersByUserId[2] = target

	local result = EscapeService.validateThroughGapReach(player, target, makeRequest())
	assertEqual(result, false, "safe-zone route rejects through-gap")
end

do
	resetRouteDefaults()
	local player = MockPlayer.new(1, "GiantPlayer")
	local target = MockPlayer.new(2, "TinyfolkPlayer", {
		inSafeZone = true,
		safeZoneType = "RealmEntry",
		safeZoneProtectionEndsAt = 101,
	})
	playersByUserId[2] = target

	local activeProtectionResult = EscapeService.validateThroughGapReach(player, target, makeRequest())
	assertEqual(activeProtectionResult, false, "realm-entry target active protection rejects through-gap")

	currentTime = 102
	local expiredProtectionResult = EscapeService.validateThroughGapReach(player, target, makeRequest())
	assertEqual(expiredProtectionResult, true, "realm-entry target expired protection allows through-gap")
end

do
	resetRouteDefaults()
	local player = MockPlayer.new(1, "GiantPlayer")
	local target = MockPlayer.new(2, "TinyfolkPlayer", {
		inSafeZone = true,
		safeZoneType = "InvalidSafeZoneType",
	})
	playersByUserId[2] = target

	local result = EscapeService.validateThroughGapReach(player, target, makeRequest())
	assertEqual(result, false, "unknown safe-zone type on target rejects through-gap")
end

do
	resetRouteDefaults()
	local player = MockPlayer.new(1, "GiantPlayer")
	local target = MockPlayer.new(2, "TinyfolkPlayer", { crossingPhase = "Idle" })
	playersByUserId[2] = target

	local result = EscapeService.validateThroughGapReach(player, target, makeRequest())
	assertEqual(result, false, "not-crossing target rejects")
end

do
	resetRouteDefaults()
	local player = MockPlayer.new(1, "GiantPlayer")
	local target = MockPlayer.new(2, "TinyfolkPlayer", { crossingPhase = "MidCrossing" })
	playersByUserId[2] = target

	local result = EscapeService.validateThroughGapReach(player, target, makeRequest())
	assertEqual(result, true, "valid crossing-phase target accepts")
end

do
	resetRouteDefaults()
	local player = MockPlayer.new(1, "GiantPlayer")
	local target = MockPlayer.new(2, "TinyfolkPlayer")
	playersByUserId[2] = target

	local result = EscapeService.validateThroughGapReach(
		player,
		target,
		makeRequest({
			lineOfSightCheck = function()
				return false
			end,
		})
	)
	assertEqual(result, false, "blocked LOS/collision callback rejects")
end

do
	resetRouteDefaults()
	local player = MockPlayer.new(1, "GiantPlayer")
	local target = MockPlayer.new(2, "TinyfolkPlayer")
	playersByUserId[2] = target

	local result = EscapeService.validateThroughGapReach(player, target, {
		worldPosition = { x = 0, y = 0, z = 5 },
		lineOfSightCheck = function()
			return true
		end,
	})
	assertEqual(result, false, "generic non-gap/world-position-only attempt rejects")
end

do
	resetRouteDefaults()
	local player = MockPlayer.new(1, "GiantPlayer")
	local target = MockPlayer.new(2, "TinyfolkPlayer")
	playersByUserId[2] = target

	local result = EscapeService.validateThroughGapReach(player, target, makeRequest())
	assertEqual(result, true, "no block preserves TIN-186 reach behavior")
end

do
	resetRouteDefaults()
	local player = MockPlayer.new(1, "GiantPlayer")

	local result = EscapeService.requestTraversalGapBlock(player, "EscapeRoute_A")
	assertEqual(result.accepted, true, "Giant can block valid TraversalGap")
	assertEqual(result.reason, "accepted", "valid block reason")
	assertEqual(routeAttributes.TraversalGapBlockState, "Startup", "valid block exposes Startup attribute")
	assertEqual(routeAttributes.TraversalGapBlockStartupEndsAt, 101, "valid block exposes startup end")
	assertEqual(routeAttributes.TraversalGapBlockActiveEndsAt, 105, "valid block exposes active end")
	assertEqual(routeAttributes.TraversalGapBlockExpiresAt, 105, "valid block exposes expiration")
	assertEqual(routeAttributes.TraversalGapBlockedByUserId, 1, "valid block exposes blocker user id")
end

do
	resetRouteDefaults()
	local player = MockPlayer.new(1, "DashGiant", { positionZ = 12 })

	local result = EscapeService.requestDash(player, "EscapeRoute_A")
	assertEqual(result.accepted, true, "dash accepts within dash trigger radius")
	assertEqual(result.reason, "accepted", "dash accepted reason")
end

do
	resetRouteDefaults()
	local player = MockPlayer.new(1, "DashCooldownGiant")

	local first = EscapeService.requestDash(player, "EscapeRoute_A")
	local second = EscapeService.requestDash(player, "EscapeRoute_A")
	assertEqual(first.accepted, true, "first dash accepted")
	assertEqual(second.accepted, false, "second dash rejected by cooldown")
	assertEqual(second.reason, "dash_cooldown", "dash cooldown reason")

	currentTime = 100.25
	local afterCooldown = EscapeService.requestDash(player, "EscapeRoute_A")
	assertEqual(afterCooldown.accepted, false, "dash cooldown expires before block state")
	assertEqual(afterCooldown.reason, "block_startup", "post-cooldown dash defers to block state")
end

do
	resetRouteDefaults()
	local player = MockPlayer.new(1, "TinyfolkPlayer", { role = "Tinyfolk" })

	local result = EscapeService.requestTraversalGapBlock(player, "EscapeRoute_A")
	assertEqual(result.accepted, false, "non-Giant block caller rejects")
	assertEqual(result.reason, "caller_not_giant", "non-Giant block rejection reason")
end

do
	resetRouteDefaults()
	routeAttributes.ThroughGapReachAllowed = nil
	local player = MockPlayer.new(1, "GiantPlayer")

	local result = EscapeService.requestTraversalGapBlock(player, "EscapeRoute_A")
	assertEqual(result.accepted, false, "missing block metadata rejects")
	assertEqual(result.reason, "route_disallows_through_gap_reach", "missing block metadata reason")
end

do
	resetRouteDefaults()
	routeAttributes.RouteType = "OpenField"
	local player = MockPlayer.new(1, "GiantPlayer")

	local result = EscapeService.requestTraversalGapBlock(player, "EscapeRoute_A")
	assertEqual(result.accepted, false, "unsupported block route type rejects")
	assertEqual(result.reason, "route_type_unsupported", "unsupported block route type reason")
end

do
	resetRouteDefaults()
	local player = MockPlayer.new(1, "GiantPlayer", { role = "Giant", hasRoot = false })

	local result = EscapeService.requestTraversalGapBlock(player, "EscapeRoute_A")
	assertEqual(result.accepted, false, "missing block caller root rejects")
	assertEqual(result.reason, "missing_character_root", "missing block caller root reason")
end

do
	resetRouteDefaults()
	local player = MockPlayer.new(1, "GiantPlayer", { role = "Giant", positionZ = 40 })

	local result = EscapeService.requestTraversalGapBlock(player, "EscapeRoute_A")
	assertEqual(result.accepted, false, "out-of-range block caller rejects")
	assertEqual(result.reason, "caller_out_of_range", "out-of-range block caller reason")
end

do
	resetRouteDefaults()
	routeAttributes.InSafeZone = true
	routeAttributes.SafeZoneType = "SharedHub"
	local player = MockPlayer.new(1, "GiantPlayer")

	local result = EscapeService.requestTraversalGapBlock(player, "EscapeRoute_A")
	assertEqual(result.accepted, false, "safe-zone route block rejects")
	assertEqual(result.reason, "shared_hub_no_capture", "safe-zone route block reason")
end

do
	resetRouteDefaults()
	routeAttributes.InSafeZone = true
	routeAttributes.SafeZoneType = "RealmExit"
	local player = MockPlayer.new(1, "GiantPlayer")

	local result = EscapeService.requestTraversalGapBlock(player, "EscapeRoute_A")
	assertEqual(result.accepted, false, "realm-exit route block rejects")
	assertEqual(result.reason, "realm_exit_protected", "realm-exit route block reason")
end

do
	resetRouteDefaults()
	routeAttributes.InSafeZone = true
	routeAttributes.SafeZoneType = "RealmEntry"
	routeAttributes.SafeZoneProtectionEndsAt = 101
	local player = MockPlayer.new(1, "GiantPlayer")

	local activeProtectionResult = EscapeService.requestTraversalGapBlock(player, "EscapeRoute_A")
	assertEqual(activeProtectionResult.accepted, false, "realm-entry active protection rejects block")
	assertEqual(activeProtectionResult.reason, "realm_entry_protected", "realm-entry active reason")

	currentTime = 102
	local expiredProtectionResult = EscapeService.requestTraversalGapBlock(player, "EscapeRoute_A")
	assertEqual(expiredProtectionResult.accepted, true, "realm-entry expired protection allows block")
end

do
	resetRouteDefaults()
	routeAttributes.InSafeZone = true
	routeAttributes.SafeZoneType = "UnknownZoneType"
	local player = MockPlayer.new(1, "GiantPlayer")

	local result = EscapeService.requestTraversalGapBlock(player, "EscapeRoute_A")
	assertEqual(result.accepted, false, "unknown safe-zone type rejects")
	assertEqual(result.reason, "safe_zone_type_unknown", "unknown safe-zone reason")
end

do
	resetRouteDefaults()
	routeAttributes.InSafeZone = true
	routeAttributes.SafeZoneType = "SharedHub"
	local player = MockPlayer.new(1, "GiantPlayer")

	local first = EscapeService.requestTraversalGapBlock(player, "EscapeRoute_A")
	local second = EscapeService.requestTraversalGapBlock(player, "EscapeRoute_A")
	local third = EscapeService.requestTraversalGapBlock(player, "EscapeRoute_A")

	routeAttributes.InSafeZone = false
	routeAttributes.SafeZoneType = nil
	local locked = EscapeService.requestTraversalGapBlock(player, "EscapeRoute_A")
	assertEqual(first.accepted, false, "safe-zone abuse first rejection")
	assertEqual(second.accepted, false, "safe-zone abuse second rejection")
	assertEqual(third.accepted, false, "safe-zone abuse third rejection")
	assertEqual(locked.accepted, false, "safe-zone abuse lockout rejects immediately")
	assertEqual(locked.reason, "safe_zone_abuse_rate_limited", "safe-zone abuse lockout reason")

	currentTime = 101.1
	local unlocked = EscapeService.requestTraversalGapBlock(player, "EscapeRoute_A")
	assertEqual(unlocked.accepted, true, "safe-zone abuse lockout expires deterministically")
end

do
	resetRouteDefaults()
	local player = MockPlayer.new(1, "GiantPlayer")
	local first = EscapeService.requestTraversalGapBlock(player, "EscapeRoute_A")
	local repeatedStartup = EscapeService.requestTraversalGapBlock(player, "EscapeRoute_A")
	currentTime = 101
	local repeatedActive = EscapeService.requestTraversalGapBlock(player, "EscapeRoute_A")

	assertEqual(first.accepted, true, "repeated block setup accepted")
	assertEqual(repeatedStartup.accepted, false, "repeated Startup block rejects")
	assertEqual(repeatedStartup.reason, "block_startup", "repeated Startup service reason")
	assertEqual(repeatedActive.accepted, false, "repeated Active block rejects")
	assertEqual(repeatedActive.reason, "block_active", "repeated Active service reason")
	assertEqual(routeAttributes.TraversalGapBlockStartupEndsAt, 101, "repeated block does not refresh startup end")
	assertEqual(routeAttributes.TraversalGapBlockActiveEndsAt, 105, "repeated block does not refresh active end")
end

do
	resetRouteDefaults()
	local player = MockPlayer.new(1, "GiantPlayer")
	local first = EscapeService.requestTraversalGapBlock(player, "EscapeRoute_A")
	currentTime = 106
	local second = EscapeService.requestTraversalGapBlock(player, "EscapeRoute_A")

	assertEqual(first.accepted, true, "expired block setup accepted")
	assertEqual(second.accepted, true, "expired block allows new block")
	assertEqual(routeAttributes.TraversalGapBlockStartupEndsAt, 107, "new block after expiration refreshes timing")
end

do
	resetRouteDefaults()
	local giant = MockPlayer.new(1, "GiantPlayer")
	local tinyfolk = MockPlayer.new(20, "TinyfolkPlayer", { role = "Tinyfolk" })
	advanceFinalExitToOpen("EscapeRoute_A")
	local block = EscapeService.requestTraversalGapBlock(giant, "EscapeRoute_A")
	currentTime = 105.5
	local escape = EscapeService.requestEscapeAttempt(tinyfolk, "EscapeRoute_A")

	assertEqual(block.accepted, true, "Startup escape setup block accepted")
	assertEqual(escape.accepted, true, "Startup block allows Tinyfolk escape timing counterplay")
	assertEqual(escape.reason, "accepted", "Startup escape accepted reason")
	assertEqual(crossingHooks[1], "EscapeRoute_A", "Startup escape preserves route-crossing hook")
end

do
	resetRouteDefaults()
	local giant = MockPlayer.new(1, "GiantPlayer")
	local tinyfolk = MockPlayer.new(21, "TinyfolkPlayer", { role = "Tinyfolk" })
	advanceFinalExitToOpen("EscapeRoute_A")
	local block = EscapeService.requestTraversalGapBlock(giant, "EscapeRoute_A")
	currentTime = 106
	local escape = EscapeService.requestEscapeAttempt(tinyfolk, "EscapeRoute_A")

	assertEqual(block.accepted, true, "Active escape rejection setup block accepted")
	assertEqual(escape.accepted, false, "Active block rejects Tinyfolk escape attempt")
	assertEqual(escape.reason, "final_exit_blocked", "Active escape rejection reason")
	assertEqual(#crossingHooks, 0, "Active block does not fire route-crossing hook")
end

do
	resetRouteDefaults()
	local tinyfolk = MockPlayer.new(24, "TinyfolkPlayer", { role = "Tinyfolk" })
	downedByUserId[24] = true
	local escape = EscapeService.requestEscapeAttempt(tinyfolk, "EscapeRoute_A")

	assertEqual(escape.accepted, false, "downed Tinyfolk cannot escape")
	assertEqual(escape.reason, "actor_downed", "downed Tinyfolk rejection reason")
end

do
	resetRouteDefaults()
	local tinyfolk = MockPlayer.new(25, "TinyfolkPlayer", { role = "Tinyfolk" })
	carriedByUserId[25] = true
	local escape = EscapeService.requestEscapeAttempt(tinyfolk, "EscapeRoute_A")

	assertEqual(escape.accepted, false, "carried Tinyfolk cannot escape")
	assertEqual(escape.reason, "actor_carried", "carried Tinyfolk rejection reason")
end

do
	resetRouteDefaults()
	local giant = MockPlayer.new(26, "GiantPlayer", { role = "Giant" })
	carriedByUserId[26] = true
	local block = EscapeService.requestTraversalGapBlock(giant, "EscapeRoute_A")

	assertEqual(block.accepted, false, "carried Giant cannot block traversal")
	assertEqual(block.reason, "actor_carried", "carried Giant block reason")
end

do
	resetRouteDefaults()
	local giant = MockPlayer.new(28, "GiantPlayer", { role = "Giant" })
	carrierEncumberedByUserId[28] = true
	local block = EscapeService.requestTraversalGapBlock(giant, "EscapeRoute_A")

	assertEqual(block.accepted, false, "encumbered Giant cannot block traversal")
	assertEqual(block.reason, "carrier_encumbered", "encumbered Giant block reason")
end

do
	resetRouteDefaults()
	routeAttributes.TraversalGapBlockExempt = true
	local giant = MockPlayer.new(1, "GiantPlayer")
	local tinyfolk = MockPlayer.new(23, "TinyfolkPlayer", { role = "Tinyfolk" })
	advanceFinalExitToOpen("EscapeRoute_A")
	local block = EscapeService.requestTraversalGapBlock(giant, "EscapeRoute_A")
	currentTime = 106
	local escape = EscapeService.requestEscapeAttempt(tinyfolk, "EscapeRoute_A")

	assertEqual(block.accepted, true, "exempt route setup block accepted")
	assertEqual(escape.accepted, false, "final exit block interrupts exempt traversal")
	assertEqual(escape.reason, "final_exit_blocked", "final exit block takes precedence over traversal exemption")
end

do
	resetRouteDefaults()
	local giant = MockPlayer.new(1, "GiantPlayer")
	local target = MockPlayer.new(2, "TinyfolkPlayer", { crossingPhase = "MidCrossing" })
	playersByUserId[2] = target
	local block = EscapeService.requestTraversalGapBlock(giant, "EscapeRoute_A")
	currentTime = 101

	local result = EscapeService.validateThroughGapReach(giant, target, makeRequest())
	assertEqual(block.accepted, true, "Active through-gap rejection setup block accepted")
	assertEqual(result, false, "Active block rejects through-gap reach")
end

do
	resetRouteDefaults()
	local giant = MockPlayer.new(1, "GiantPlayer")
	local target = MockPlayer.new(27, "TinyfolkPlayer", { crossingPhase = "MidCrossing" })
	playersByUserId[27] = target
	carriedByUserId[27] = true

	local result = EscapeService.validateThroughGapReach(giant, target, makeRequest())
	assertEqual(result, false, "carried target rejects through-gap reach")
end

do
	resetRouteDefaults()
	local giant = MockPlayer.new(29, "GiantPlayer", { role = "Giant" })
	local target = MockPlayer.new(30, "TinyfolkPlayer", { crossingPhase = "MidCrossing" })
	playersByUserId[30] = target
	carrierEncumberedByUserId[29] = true

	local result = EscapeService.validateThroughGapReach(giant, target, makeRequest())
	assertEqual(result, false, "encumbered Giant rejects through-gap reach")
end

do
	resetRouteDefaults()
	local giant = MockPlayer.new(1, "GiantPlayer")
	advanceFinalExitToOpen("EscapeRoute_A")
	local block = EscapeService.requestTraversalGapBlock(giant, "EscapeRoute_A")
	local debugState = EscapeService.getDebugState(giant, "EscapeRoute_A")

	assertEqual(block.accepted, true, "debug block setup accepted")
	assertEqual(debugState.routeId, "EscapeRoute_A", "debug includes route id")
	assertEqual(debugState.blockState, "Startup", "debug includes block state")
	assertEqual(debugState.finalExitPhase, "Open", "debug includes final exit phase")
	assertEqual(debugState.blockStartupEndsAt, 106, "debug includes startup end")
	assertEqual(debugState.blockActiveEndsAt, 110, "debug includes active end")
	assertEqual(debugState.blockExpiresAt, 110, "debug includes expiration")
	assertEqual(debugState.blockedByUserId, 1, "debug includes blocker user id")
	assertEqual(debugState.blockExempt, false, "debug includes exemption flag")
end

do
	resetRouteDefaults()
	local giant = MockPlayer.new(1, "GiantPlayer")
	local tinyfolk = MockPlayer.new(22, "TinyfolkPlayer", { role = "Tinyfolk" })
	advanceFinalExitToOpen("EscapeRoute_A")
	local block = EscapeService.requestTraversalGapBlock(giant, "EscapeRoute_A")
	currentTime = 112
	EscapeService.RefreshFinalExitStateForTests("EscapeRoute_A")
	local escape = EscapeService.requestEscapeAttempt(tinyfolk, "EscapeRoute_A")

	assertEqual(block.accepted, true, "expired escape setup block accepted")
	assertEqual(escape.accepted, true, "expired block allows Tinyfolk escape attempt")
end

do
	local sim = MatchSimulation.new({ clock = os.clock })
	sim:addPlayer(1, "GiantPlayer", { role = "Giant" })
	sim:addPlayer(2, "TinyfolkPlayer", { role = "Tinyfolk", inSafeZone = true })

	sim:queueAction(1, "attemptEscape", {
		userId = 2,
		target = sim.players[1],
		worldPosition = { x = 0, y = 0, z = 5 },
		lineOfSightCheck = function()
			return true
		end,
	})

	sim:advanceTick()

	local log = sim:getLog()
	assertEqual(log[3], "[Tick 1] Escape attempt by TinyfolkPlayer: Failure", "Safe-zone escape attempt fails")
end
