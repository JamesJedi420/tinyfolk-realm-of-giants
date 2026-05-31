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
assertTrue(diagnostics.activationAttempts >= 8, "diagnostics activation attempts")
assertTrue(diagnostics.activationSucceeded >= 4, "diagnostics activation succeeded")
assertTrue(diagnostics.activationFailed >= 4, "diagnostics activation failed")
assertTrue(diagnostics.cancelAttempts >= 2, "diagnostics cancel attempts")
assertTrue(diagnostics.cancelSucceeded >= 1, "diagnostics cancel succeeded")
assertTrue(diagnostics.cancelFailed >= 1, "diagnostics cancel failed")
assertTrue(diagnostics.invalidActionCancelled >= 1, "diagnostics invalid action cancelled")
assertTrue(diagnostics.invalidStateCancelled >= 1, "diagnostics invalid state cancelled")
assertTrue(diagnostics.tickExpired >= 1, "diagnostics tick expired")
assertEqual(diagnostics.lastReason, "cancelled_by_request", "diagnostics last reason")
assertEqual(diagnostics.lastUserId, 401, "diagnostics last user")

api.ResetForTests()
local resetSnapshot = api.GetStealthShrinkSnapshot({ userId = 401 })
assertFalse(resetSnapshot.isActive, "reset clears active state")
local resetDiagnostics = api.GetStealthShrinkDiagnostics()
assertEqual(resetDiagnostics.lastReason, "reset", "reset diagnostics reason")

print("tinyfolk_stealth_service_runtime_entrypoint: all checks passed")
