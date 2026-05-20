--!strict

local MockPlayer = require("../tests/mocks/MockPlayer")
local MatchSimulation: any = require("../tests/harness/MatchSimulation")

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

local escapeRoutesFolder: any = {
	ClassName = "Folder",
}

function escapeRoutesFolder:FindFirstChild(_childName: string): any
	return nil
end

function escapeRoutesFolder:GetDescendants(): { any }
	return { routePart }
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
									ThroughGapReachAllowedAttribute = "ThroughGapReachAllowed",
									RouteTypeAttribute = "RouteType",
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
									FinalExitPoweredDurationSeconds = 1,
									FinalExitOpeningDurationSeconds = 1,
									FinalExitBlockedDurationSeconds = 2,
									FinalExitReopenDurationSeconds = 1,
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

_G.game = MockGame
local currentTime = 100
local crossingHooks: { string } = {}
local downedByUserId: { [number]: boolean } = {}
local carriedByUserId: { [number]: boolean } = {}
local carrierEncumberedByUserId: { [number]: boolean } = {}
local objectiveThresholdMet = false
_G._RoleService_QueryAPI = {
	IsPlayerDowned = function(userId: number): boolean
		return downedByUserId[userId] == true
	end,
	CanPlayerPerformInteraction = function(userId: number, interactionName: string): boolean
		if downedByUserId[userId] == true and interactionName == "escapeAttempt" then
			return false
		end
		return true
	end,
}
_G._GrabService_QueryAPI = {
	IsPlayerCarried = function(userId: number): boolean
		return carriedByUserId[userId] == true
	end,
	CanGiantPerformCarryInteraction = function(userId: number, _interactionName: string): any
		if carrierEncumberedByUserId[userId] == true then
			return { accepted = false, reason = "carrier_encumbered" }
		end
		return { accepted = true, reason = "accepted" }
	end,
}
_G._RealmObjectiveService_QueryAPI = {
	IsEscapeObjectiveThresholdMet = function(): boolean
		return objectiveThresholdMet == true
	end,
}
local transportDepartureOutcome: any = {
	accepted = false,
	reason = "transport_not_departed",
	outcome = nil,
}
_G._TransportEscapeService_QueryAPI = {
	ResolveTransportDepartureOutcome = function(_endpointId: string, _candidateTinyfolkUserIds: { number }): any
		return transportDepartureOutcome
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
			table.insert(crossingHooks, routeId)
		end,
	},
})

local function resetRouteDefaults()
	routeAttributes.ThroughGapReachAllowed = true
	routeAttributes.RouteType = "TraversalGap"
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
	currentTime = 100
	crossingHooks = {}
	downedByUserId = {}
	carriedByUserId = {}
	carrierEncumberedByUserId = {}
	objectiveThresholdMet = false
	EscapeService.ResetTraversalGapBlocksForTests()
	EscapeService.ResetEscapeAttemptStateForTests()
	EscapeService.ResetFinalExitForTests()
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
	local protected = _G._EscapeService_QueryAPI.ResolveRescueEntryRoute(1101, 9402)
	assertEqual(protected.accepted, false, "query rescue entry route rejects protected route")
	assertEqual(protected.reason, "rescue_entry_route_missing", "protected rescue entry route reason")
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
	local originalObjectiveApi = _G._RealmObjectiveService_QueryAPI
	_G._RealmObjectiveService_QueryAPI = {
		IsEscapeObjectiveThresholdMet = function(): boolean
			error("objective query fault")
			return false
		end,
	}

	local tinyfolk = MockPlayer.new(77, "FaultyObjectiveTinyfolk", { role = "Tinyfolk" })
	local attempt = EscapeService.requestEscapeAttempt(tinyfolk, "EscapeRoute_A")
	assertEqual(attempt.accepted, false, "objective query error does not crash escape attempt")
	assertEqual(attempt.reason, "final_exit_dormant", "objective query error falls back to dormant gate")

	_G._RealmObjectiveService_QueryAPI = originalObjectiveApi
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
