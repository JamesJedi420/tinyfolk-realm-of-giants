--!strict

local PartyMatchmakingQueueState = require("../src/ReplicatedStorage/Shared/GiantRealm/PartyMatchmakingQueueState")

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

local function makeEntry(overrides: any?): any
	local entry = {
		operationId = "party_matchmaking_tinyfolk_party_101_1000",
		partyId = "tinyfolk_party:101:1000",
		leaderUserId = 101,
		partySize = 2,
		partyMemberUserIds = { 101, 202 },
		desiredActivity = "raid",
		skillBand = 1,
		toolTier = 0,
		createdAt = 100,
		expiration = 400,
		status = "pending",
	}
	if overrides ~= nil then
		for key, value in pairs(overrides) do
			entry[key] = value
		end
	end
	return entry
end

assertTrue(PartyMatchmakingQueueState.IsRaidBoardSoloPartyId("raid_board:55"), "raid board prefix reserved")
assertFalse(PartyMatchmakingQueueState.IsRaidBoardSoloPartyId("tinyfolk_party:55:1"), "party prefix allowed")

local valid = PartyMatchmakingQueueState.NewEntry(makeEntry())
assertTrue(valid.ok, "valid entry accepted")
assertEqual(valid.entry.desiredActivity, "raid", "desired activity")
assertEqual(valid.entry.partyMemberUserIds[1], 101, "members sorted first")
assertEqual(valid.entry.partyMemberUserIds[2], 202, "members sorted second")

local reservedParty = PartyMatchmakingQueueState.NewEntry(makeEntry({ partyId = "raid_board:77" }))
assertFalse(reservedParty.ok, "raid board namespace rejected")
assertEqual(reservedParty.reason, "party_id_namespace_reserved", "raid board namespace reason")

local invalidActivity = PartyMatchmakingQueueState.NewEntry(makeEntry({ desiredActivity = "unknown" }))
assertFalse(invalidActivity.ok, "invalid activity rejected")
assertEqual(invalidActivity.reason, "desired_activity_invalid", "invalid activity reason")

local leaderMissing = PartyMatchmakingQueueState.NewEntry(makeEntry({ leaderUserId = 999 }))
assertFalse(leaderMissing.ok, "leader not in party rejected")
assertEqual(leaderMissing.reason, "leader_not_in_party", "leader not in party reason")

local matched = PartyMatchmakingQueueState.WithMatch(valid.entry, "realm-42", 250)
assertTrue(matched.ok, "match transition accepted")
assertEqual(matched.entry.status, "matched", "matched status")
assertEqual(matched.entry.targetRealmId, "realm-42", "matched target realm")

local expired = PartyMatchmakingQueueState.WithExpiry(valid.entry, 500, "expired")
assertTrue(expired.ok, "expiry transition accepted")
assertEqual(expired.entry.status, "expired", "expired status")
assertEqual(expired.entry.resolvedReason, "expired", "expired reason")

assertFalse(PartyMatchmakingQueueState.IsExpired(valid.entry, 399), "not expired before timeout")
assertTrue(PartyMatchmakingQueueState.IsExpired(valid.entry, 400), "expired at timeout boundary")
assertFalse(PartyMatchmakingQueueState.IsExpired(matched.entry, 999), "matched entries do not auto-expire")

local clientSnapshot = PartyMatchmakingQueueState.BuildClientSnapshot(valid.entry)
assertEqual(clientSnapshot.partyId, valid.entry.partyId, "client snapshot party id")
assertEqual(clientSnapshot.leaderUserId, 101, "client snapshot leader")

print("party_matchmaking_queue_state: all checks passed")
