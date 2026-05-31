--!strict

local StealthShrinkState = require("../src/ReplicatedStorage/Shared/TinyfolkStealth/StealthShrinkState")

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

local state = StealthShrinkState.new()
local activated, activateReason = state:Activate(100, 15)
assertTrue(activated, "activate accepted")
assertEqual(activateReason, "accepted", "activate accepted reason")

local duplicateActivate, duplicateReason = state:Activate(100, 15)
assertFalse(duplicateActivate, "duplicate activate rejected")
assertEqual(duplicateReason, "already_active", "duplicate activate reason")

local beforeExpiry, beforeReason = state:Tick(110)
assertFalse(beforeExpiry, "tick before expiry")
assertEqual(beforeReason, nil, "tick before expiry reason")

local snapshotActive = state:GetSnapshot(110)
assertTrue(snapshotActive.isActive, "snapshot active")
assertEqual(snapshotActive.startedAt, 100, "snapshot startedAt")
assertEqual(snapshotActive.endsAt, 115, "snapshot endsAt")
assertEqual(snapshotActive.remainingSeconds, 5, "snapshot remaining")

local expired, expiredReason = state:Tick(115)
assertTrue(expired, "tick expires at end")
assertEqual(expiredReason, "expired", "tick expiry reason")

local postExpirySnapshot = state:GetSnapshot(116)
assertFalse(postExpirySnapshot.isActive, "post expiry inactive")
assertEqual(postExpirySnapshot.lastReason, "expired", "post expiry reason tracked")

local cancelWhileInactive, cancelInactiveReason = state:Cancel("cancelled_by_request", 120)
assertFalse(cancelWhileInactive, "cancel inactive rejected")
assertEqual(cancelInactiveReason, "not_active", "cancel inactive reason")

local secondActivate, secondActivateReason = state:Activate(130, 20)
assertTrue(secondActivate, "second activate accepted")
assertEqual(secondActivateReason, "accepted", "second activate reason")

local cancelAccepted, cancelReason = state:Cancel("cancelled_by_request", 135)
assertTrue(cancelAccepted, "cancel accepted")
assertEqual(cancelReason, "cancelled_by_request", "cancel reason")

local cancelledSnapshot = state:GetSnapshot(136)
assertFalse(cancelledSnapshot.isActive, "cancelled snapshot inactive")
assertEqual(cancelledSnapshot.lastReason, "cancelled_by_request", "cancelled reason tracked")
assertEqual(cancelledSnapshot.lastChangedAt, 135, "cancelled changed at")

print("stealth_shrink_state: all checks passed")
