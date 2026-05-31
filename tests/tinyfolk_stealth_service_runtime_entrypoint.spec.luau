--!nocheck

local globalEnv: any = _G

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(
			string.format("assertEqual failed [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual))
		)
	end
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local function assertFalse(value: boolean, label: string)
	assertEqual(value, false, label)
end

local StealthShrinkState = require("../src/ReplicatedStorage/Shared/TinyfolkStealth/StealthShrinkState")
globalEnv._TinyfolkStealth_TestModules = {
	StealthShrinkState = StealthShrinkState,
}

globalEnv._TinyfolkStealthService_QueryAPI = nil

local roleByUserId = {
	[401] = "Tinyfolk",
	[402] = "Giant",
}

local players = {
	{
		UserId = 401,
		GetAttribute = function(_self, key: string): any
			if key == "Role" then
				return roleByUserId[401]
			end
			return nil
		end,
	},
	{
		UserId = 402,
		GetAttribute = function(_self, key: string): any
			if key == "Role" then
				return roleByUserId[402]
			end
			return nil
		end,
	},
}

local Players = {
	GetPlayerByUserId = function(_self, userId: number)
		for _, player in ipairs(players) do
			if player.UserId == userId then
				return player
			end
		end
		return nil
	end,
	PlayerRemoving = {
		Connect = function(_self, _callback)
			return { Disconnect = function() end }
		end,
	},
}

globalEnv.game = {
	GetService = function(_self, serviceName: string)
		if serviceName == "Players" then
			return Players
		end
		if serviceName == "ReplicatedStorage" then
			return {
				Shared = {
					TinyfolkStealth = {
						StealthShrinkState = StealthShrinkState,
					},
				},
			}
		end
		return nil
	end,
}

require("../src/ServerScriptService/Services/TinyfolkStealthService.server")

local api = globalEnv._TinyfolkStealthService_QueryAPI
assertTrue(type(api) == "table", "query api published")
assertTrue(type(api.RequestStealthShrink) == "function", "RequestStealthShrink published")
assertTrue(type(api.CancelStealthShrink) == "function", "CancelStealthShrink published")
assertTrue(type(api.CanPerformMajorAction) == "function", "CanPerformMajorAction published")
assertTrue(type(api.TickStealthShrink) == "function", "TickStealthShrink published")

local now = 100
local blockedInteraction = false
local invalidByUser = {}
local carriedByUser = {}
local hidingByUser = {}
local statusAllowedByUser = {}
local downedByUser = {}
local statusSnapshotByUser = {}

api.ConfigureForTests({
	now = function()
		return now
	end,
	stealthDurationSeconds = 12,
	blockedActions = { "objective_work", "final_exit_open", "rescue_contract", "heavy_tool_use" },
	roleResolver = function(userId: number): string?
		return roleByUserId[userId]
	end,
	roleServiceApi = {
		CanPlayerPerformInteraction = function(_userId: number, interactionName: string): boolean
			if blockedInteraction and interactionName == "stealthShrink" then
				return false
			end
			return true
		end,
		IsPlayerDowned = function(userId: number): boolean
			return downedByUser[userId] == true
		end,
	},
	grabServiceApi = {
		IsPlayerCarried = function(userId: number): boolean
			return carriedByUser[userId] == true
		end,
	},
	hidingServiceApi = {
		IsPlayerHiding = function(userId: number): boolean
			return hidingByUser[userId] == true
		end,
	},
	statusResolver = function(userId: number, _at: number): (boolean, string?)
		if statusAllowedByUser[userId] == false then
			return false, "status_forbidden"
		end
		return true, nil
	end,
	statusServiceApi = {
		GetStatusSnapshot = function(userId: number, _at: number): any
			if statusSnapshotByUser[userId] == true then
				return { stunActive = true }
			end
			return { stunActive = false }
		end,
	},
	invalidStateResolver = function(userId: number): (boolean, string?)
		if invalidByUser[userId] == true then
			return true, "cancelled_invalid_state"
		end
		return false, nil
	end,
})

local invalidRequest = api.RequestStealthShrink(nil)
assertFalse(invalidRequest.accepted, "invalid request rejected")
assertEqual(invalidRequest.reason, "request_invalid", "invalid request reason")

local invalidUser = api.RequestStealthShrink({ userId = 0 })
assertFalse(invalidUser.accepted, "invalid user rejected")
assertEqual(invalidUser.reason, "user_id_invalid", "invalid user reason")

local nonTinyfolk = api.RequestStealthShrink({ userId = 402 })
assertFalse(nonTinyfolk.accepted, "non tinyfolk rejected")
assertEqual(nonTinyfolk.reason, "role_forbidden", "non tinyfolk reason")

blockedInteraction = true
local interactionForbidden = api.RequestStealthShrink({ userId = 401 })
assertFalse(interactionForbidden.accepted, "interaction forbidden rejected")
assertEqual(interactionForbidden.reason, "interaction_forbidden", "interaction forbidden reason")
blockedInteraction = false

hidingByUser[401] = true
local hidingForbidden = api.RequestStealthShrink({ userId = 401 })
assertFalse(hidingForbidden.accepted, "hiding forbidden rejected")
assertEqual(hidingForbidden.reason, "hiding_forbidden", "hiding forbidden reason")
hidingByUser[401] = false

statusAllowedByUser[401] = false
local statusForbidden = api.RequestStealthShrink({ userId = 401 })
assertFalse(statusForbidden.accepted, "status forbidden rejected")
assertEqual(statusForbidden.reason, "status_forbidden", "status forbidden reason")
statusAllowedByUser[401] = true

statusSnapshotByUser[401] = true
statusAllowedByUser[401] = false
local statusSnapshotForbidden = api.RequestStealthShrink({ userId = 401 })
assertFalse(statusSnapshotForbidden.accepted, "status snapshot forbidden rejected")
assertEqual(statusSnapshotForbidden.reason, "status_snapshot_forbidden", "status snapshot reason")
statusSnapshotByUser[401] = false
statusAllowedByUser[401] = true

blockedInteraction = true
hidingByUser[401] = true
statusAllowedByUser[401] = false
local activationPrecedenceInteraction = api.RequestStealthShrink({ userId = 401 })
assertFalse(activationPrecedenceInteraction.accepted, "activation precedence rejects interaction first")
assertEqual(
	activationPrecedenceInteraction.reason,
	"interaction_forbidden",
	"activation precedence interaction before hiding/status"
)
blockedInteraction = false
hidingByUser[401] = false
statusAllowedByUser[401] = true

hidingByUser[401] = true
statusAllowedByUser[401] = false
local activationPrecedenceHiding = api.RequestStealthShrink({ userId = 401 })
assertFalse(activationPrecedenceHiding.accepted, "activation precedence rejects hiding before status")
assertEqual(activationPrecedenceHiding.reason, "hiding_forbidden", "activation precedence hiding before status")
hidingByUser[401] = false
statusAllowedByUser[401] = true

local activate = api.RequestStealthShrink({ userId = 401 })
assertTrue(activate.accepted, "activate accepted")
assertEqual(activate.reason, "accepted", "activate reason")

local duplicate = api.RequestStealthShrink({ userId = 401 })
assertFalse(duplicate.accepted, "duplicate activation rejected")
assertEqual(duplicate.reason, "already_active", "duplicate activation reason")

local snapshotActive = api.GetStealthShrinkSnapshot({ userId = 401 })
assertTrue(snapshotActive.isActive, "snapshot active")
assertEqual(snapshotActive.remainingSeconds, 12, "snapshot remaining seconds")

local majorAllowed = api.CanPerformMajorAction({ userId = 401, actionName = "signal_only" })
assertTrue(majorAllowed.accepted, "non blocked action accepted while active")

local majorBlocked = api.CanPerformMajorAction({ userId = 401, actionName = "objective_work" })
assertFalse(majorBlocked.accepted, "blocked action rejected")
assertEqual(majorBlocked.reason, "cancelled_invalid_action", "blocked action cancellation reason")

local snapshotAfterBlocked = api.GetStealthShrinkSnapshot({ userId = 401 })
assertFalse(snapshotAfterBlocked.isActive, "blocked action cancels stealth")
assertEqual(snapshotAfterBlocked.lastReason, "cancelled_invalid_action", "blocked action reason tracked")

local cancelNotActive = api.CancelStealthShrink({ userId = 401 })
assertFalse(cancelNotActive.accepted, "cancel not active rejected")
assertEqual(cancelNotActive.reason, "not_active", "cancel not active reason")

local activateForInvalidState = api.RequestStealthShrink({ userId = 401 })
assertTrue(activateForInvalidState.accepted, "reactivate for invalid state")
invalidByUser[401] = true
local tickInvalid = api.TickStealthShrink({ at = 105 })
assertTrue(tickInvalid.accepted, "tick accepted invalid state pass")
local snapshotAfterInvalidState = api.GetStealthShrinkSnapshot({ userId = 401 })
assertFalse(snapshotAfterInvalidState.isActive, "invalid state cancels stealth")
assertEqual(snapshotAfterInvalidState.lastReason, "cancelled_invalid_state", "invalid state reason tracked")
invalidByUser[401] = false

local activateForRoleDrift = api.RequestStealthShrink({ userId = 401 })
assertTrue(activateForRoleDrift.accepted, "reactivate for role drift")
roleByUserId[401] = "Giant"
local tickRoleDrift = api.TickStealthShrink({ at = 106 })
assertTrue(tickRoleDrift.accepted, "tick accepted role drift pass")
local snapshotAfterRoleDrift = api.GetStealthShrinkSnapshot({ userId = 401 })
assertFalse(snapshotAfterRoleDrift.isActive, "role drift cancels stealth")
assertEqual(snapshotAfterRoleDrift.lastReason, "cancelled_role_mismatch", "role drift reason tracked")
roleByUserId[401] = "Tinyfolk"

local activateForCarried = api.RequestStealthShrink({ userId = 401 })
assertTrue(activateForCarried.accepted, "reactivate for carried invalidation")
carriedByUser[401] = true
local tickCarried = api.TickStealthShrink({ at = 107 })
assertTrue(tickCarried.accepted, "tick accepted carried invalidation pass")
local snapshotAfterCarried = api.GetStealthShrinkSnapshot({ userId = 401 })
assertFalse(snapshotAfterCarried.isActive, "carried state cancels stealth")
assertEqual(snapshotAfterCarried.lastReason, "cancelled_carried", "carried state reason tracked")
carriedByUser[401] = false

local activateForHidingConflict = api.RequestStealthShrink({ userId = 401 })
assertTrue(activateForHidingConflict.accepted, "reactivate for hiding conflict")
hidingByUser[401] = true
local tickHidingConflict = api.TickStealthShrink({ at = 108 })
assertTrue(tickHidingConflict.accepted, "tick accepted hiding conflict pass")
local snapshotAfterHidingConflict = api.GetStealthShrinkSnapshot({ userId = 401 })
assertFalse(snapshotAfterHidingConflict.isActive, "hiding conflict cancels stealth")
assertEqual(snapshotAfterHidingConflict.lastReason, "cancelled_hiding_conflict", "hiding conflict reason tracked")
hidingByUser[401] = false

local activateForStatusConflict = api.RequestStealthShrink({ userId = 401 })
assertTrue(activateForStatusConflict.accepted, "reactivate for status conflict")
statusAllowedByUser[401] = false
local tickStatusConflict = api.TickStealthShrink({ at = 109 })
assertTrue(tickStatusConflict.accepted, "tick accepted status conflict pass")
local snapshotAfterStatusConflict = api.GetStealthShrinkSnapshot({ userId = 401 })
assertFalse(snapshotAfterStatusConflict.isActive, "status conflict cancels stealth")
assertEqual(snapshotAfterStatusConflict.lastReason, "cancelled_status_forbidden", "status conflict reason tracked")
statusAllowedByUser[401] = true

local activateForStatusSnapshotConflict = api.RequestStealthShrink({ userId = 401 })
assertTrue(activateForStatusSnapshotConflict.accepted, "reactivate for status snapshot conflict")
statusSnapshotByUser[401] = true
statusAllowedByUser[401] = false
local tickStatusSnapshotConflict = api.TickStealthShrink({ at = 109.5 })
assertTrue(tickStatusSnapshotConflict.accepted, "tick accepted status snapshot conflict pass")
local snapshotAfterStatusSnapshotConflict = api.GetStealthShrinkSnapshot({ userId = 401 })
assertFalse(snapshotAfterStatusSnapshotConflict.isActive, "status snapshot conflict cancels stealth")
assertEqual(
	snapshotAfterStatusSnapshotConflict.lastReason,
	"cancelled_status_snapshot_forbidden",
	"status snapshot conflict reason tracked"
)
statusSnapshotByUser[401] = false
statusAllowedByUser[401] = true

local activateForInvalidPrecedence = api.RequestStealthShrink({ userId = 401 })
assertTrue(activateForInvalidPrecedence.accepted, "reactivate for invalid precedence matrix")
invalidByUser[401] = true
roleByUserId[401] = "Giant"
downedByUser[401] = true
carriedByUser[401] = true
hidingByUser[401] = true
statusAllowedByUser[401] = false
local tickInvalidPrecedence = api.TickStealthShrink({ at = 110 })
assertTrue(tickInvalidPrecedence.accepted, "tick accepted invalid precedence matrix")
local snapshotAfterInvalidPrecedence = api.GetStealthShrinkSnapshot({ userId = 401 })
assertFalse(snapshotAfterInvalidPrecedence.isActive, "invalid precedence matrix cancels stealth")
assertEqual(
	snapshotAfterInvalidPrecedence.lastReason,
	"cancelled_invalid_state",
	"invalid resolver precedence before all other branches"
)
invalidByUser[401] = false
roleByUserId[401] = "Tinyfolk"
downedByUser[401] = false
carriedByUser[401] = false
hidingByUser[401] = false
statusAllowedByUser[401] = true

local activateForRolePrecedence = api.RequestStealthShrink({ userId = 401 })
assertTrue(activateForRolePrecedence.accepted, "reactivate for role precedence matrix")
roleByUserId[401] = "Giant"
downedByUser[401] = true
carriedByUser[401] = true
hidingByUser[401] = true
statusAllowedByUser[401] = false
local tickRolePrecedence = api.TickStealthShrink({ at = 111 })
assertTrue(tickRolePrecedence.accepted, "tick accepted role precedence matrix")
local snapshotAfterRolePrecedence = api.GetStealthShrinkSnapshot({ userId = 401 })
assertFalse(snapshotAfterRolePrecedence.isActive, "role precedence matrix cancels stealth")
assertEqual(
	snapshotAfterRolePrecedence.lastReason,
	"cancelled_role_mismatch",
	"role precedence before downed/carried/hiding/status"
)
roleByUserId[401] = "Tinyfolk"
downedByUser[401] = false
carriedByUser[401] = false
hidingByUser[401] = false
statusAllowedByUser[401] = true

local activateForDownedPrecedence = api.RequestStealthShrink({ userId = 401 })
assertTrue(activateForDownedPrecedence.accepted, "reactivate for downed precedence matrix")
downedByUser[401] = true
carriedByUser[401] = true
hidingByUser[401] = true
statusAllowedByUser[401] = false
local tickDownedPrecedence = api.TickStealthShrink({ at = 112 })
assertTrue(tickDownedPrecedence.accepted, "tick accepted downed precedence matrix")
local snapshotAfterDownedPrecedence = api.GetStealthShrinkSnapshot({ userId = 401 })
assertFalse(snapshotAfterDownedPrecedence.isActive, "downed precedence matrix cancels stealth")
assertEqual(
	snapshotAfterDownedPrecedence.lastReason,
	"cancelled_downed",
	"downed precedence before carried/hiding/status"
)
downedByUser[401] = false
carriedByUser[401] = false
hidingByUser[401] = false
statusAllowedByUser[401] = true

local activateForCarriedPrecedence = api.RequestStealthShrink({ userId = 401 })
assertTrue(activateForCarriedPrecedence.accepted, "reactivate for carried precedence matrix")
carriedByUser[401] = true
hidingByUser[401] = true
statusSnapshotByUser[401] = true
statusAllowedByUser[401] = false
local tickCarriedPrecedence = api.TickStealthShrink({ at = 113 })
assertTrue(tickCarriedPrecedence.accepted, "tick accepted carried precedence matrix")
local snapshotAfterCarriedPrecedence = api.GetStealthShrinkSnapshot({ userId = 401 })
assertFalse(snapshotAfterCarriedPrecedence.isActive, "carried precedence matrix cancels stealth")
assertEqual(snapshotAfterCarriedPrecedence.lastReason, "cancelled_carried", "carried precedence before hiding/status")
carriedByUser[401] = false
hidingByUser[401] = false
statusSnapshotByUser[401] = false
statusAllowedByUser[401] = true

local activateForHidingPrecedence = api.RequestStealthShrink({ userId = 401 })
assertTrue(activateForHidingPrecedence.accepted, "reactivate for hiding precedence matrix")
hidingByUser[401] = true
statusSnapshotByUser[401] = true
statusAllowedByUser[401] = false
local tickHidingPrecedence = api.TickStealthShrink({ at = 114 })
assertTrue(tickHidingPrecedence.accepted, "tick accepted hiding precedence matrix")
local snapshotAfterHidingPrecedence = api.GetStealthShrinkSnapshot({ userId = 401 })
assertFalse(snapshotAfterHidingPrecedence.isActive, "hiding precedence matrix cancels stealth")
assertEqual(snapshotAfterHidingPrecedence.lastReason, "cancelled_hiding_conflict", "hiding precedence before status")
hidingByUser[401] = false
statusSnapshotByUser[401] = false
statusAllowedByUser[401] = true

local activateForStatusSnapshotPrecedence = api.RequestStealthShrink({ userId = 401 })
assertTrue(activateForStatusSnapshotPrecedence.accepted, "reactivate for status snapshot precedence matrix")
statusSnapshotByUser[401] = true
statusAllowedByUser[401] = false
local tickStatusSnapshotPrecedence = api.TickStealthShrink({ at = 114.5 })
assertTrue(tickStatusSnapshotPrecedence.accepted, "tick accepted status snapshot precedence matrix")
local snapshotAfterStatusSnapshotPrecedence = api.GetStealthShrinkSnapshot({ userId = 401 })
assertFalse(snapshotAfterStatusSnapshotPrecedence.isActive, "status snapshot precedence matrix cancels stealth")
assertEqual(
	snapshotAfterStatusSnapshotPrecedence.lastReason,
	"cancelled_status_snapshot_forbidden",
	"status snapshot precedence before status resolver"
)
statusSnapshotByUser[401] = false
statusAllowedByUser[401] = true

local activateForExpiry = api.RequestStealthShrink({ userId = 401 })
assertTrue(activateForExpiry.accepted, "reactivate for expiry")
now = 200
local tickExpiry = api.TickStealthShrink({ at = 200 })
assertTrue(tickExpiry.accepted, "tick accepted expiry pass")
local snapshotExpired = api.GetStealthShrinkSnapshot({ userId = 401 })
assertFalse(snapshotExpired.isActive, "expiry ends stealth")
assertEqual(snapshotExpired.lastReason, "expired", "expiry reason tracked")

local activateForCancel = api.RequestStealthShrink({ userId = 401 })
assertTrue(activateForCancel.accepted, "reactivate for cancel")
local cancelAccepted = api.CancelStealthShrink({ userId = 401 })
assertTrue(cancelAccepted.accepted, "cancel accepted")
assertEqual(cancelAccepted.reason, "cancelled_by_request", "cancel accepted reason")

local diagnostics = api.GetStealthShrinkDiagnostics()
assertTrue(diagnostics.activationAttempts >= 23, "diagnostics activation attempts")
assertTrue(diagnostics.activationSucceeded >= 15, "diagnostics activation succeeded")
assertTrue(diagnostics.activationFailed >= 8, "diagnostics activation failed")
assertTrue(diagnostics.cancelAttempts >= 2, "diagnostics cancel attempts")
assertTrue(diagnostics.cancelSucceeded >= 1, "diagnostics cancel succeeded")
assertTrue(diagnostics.cancelFailed >= 1, "diagnostics cancel failed")
assertTrue(diagnostics.invalidActionCancelled >= 1, "diagnostics invalid action cancelled")
assertTrue(diagnostics.invalidStateCancelled >= 12, "diagnostics invalid state cancelled")
assertTrue(diagnostics.tickExpired >= 1, "diagnostics tick expired")
assertEqual(diagnostics.lastReason, "cancelled_by_request", "diagnostics last reason")
assertEqual(diagnostics.lastUserId, 401, "diagnostics last user")

api.ResetForTests()
local resetSnapshot = api.GetStealthShrinkSnapshot({ userId = 401 })
assertFalse(resetSnapshot.isActive, "reset clears active state")
local resetDiagnostics = api.GetStealthShrinkDiagnostics()
assertEqual(resetDiagnostics.lastReason, "reset", "reset diagnostics reason")

print("tinyfolk_stealth_service_runtime_entrypoint: all checks passed")
