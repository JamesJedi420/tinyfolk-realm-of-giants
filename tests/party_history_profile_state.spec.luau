--!strict

local PartyHistoryProfileState = require("../src/ReplicatedStorage/Shared/GiantRealm/PartyHistoryProfileState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local function assertFalse(value: boolean, label: string)
	assertEqual(value, false, label)
end

local function makeValidEntry(operationId: string): any
	return {
		operationId = operationId,
		partyId = "party-42",
		targetRealmId = "realm-9402",
		entryType = "rescue_contract",
		formedAt = 100,
		partySize = 2,
		partyMemberUserIds = { 7101, 7102 },
	}
end

do
	assertFalse(PartyHistoryProfileState.HasPersistedState(nil), "nil profile not persisted")
	assertFalse(PartyHistoryProfileState.HasPersistedState({}), "empty profile not persisted")
	assertFalse(
		PartyHistoryProfileState.HasPersistedState({
			partyHistory = {},
		}),
		"empty party history not persisted"
	)
end

do
	local profileData = {
		partyHistory = { makeValidEntry("op-1") },
	}
	assertTrue(PartyHistoryProfileState.HasPersistedState(profileData), "valid history persisted")
	local history = PartyHistoryProfileState.GetHistory(profileData)
	assertEqual(#history, 1, "history length")
	assertEqual(history[1].operationId, "op-1", "history operation id")
	assertEqual(history[1].partyId, "party-42", "history party id")
	assertEqual(history[1].entryType, "rescue_contract", "history entry type")
	assertEqual(#history[1].partyMemberUserIds, 2, "history member count")
	assertEqual(history[1].partyMemberUserIds[1], 7101, "history members sorted")
	assertEqual(history[1].partyMemberUserIds[2], 7102, "history members sorted")
end

do
	local profileData = {
		partyHistory = {
			{
				operationId = "op-invalid",
				partyId = "",
				targetRealmId = "realm-9402",
				entryType = "rescue_contract",
				formedAt = 100,
				partySize = 2,
				partyMemberUserIds = { 7101, 7102 },
			},
			makeValidEntry("op-valid"),
		},
	}
	local history = PartyHistoryProfileState.GetHistory(profileData)
	assertEqual(#history, 1, "invalid entries filtered")
	assertEqual(history[1].operationId, "op-valid", "valid entry kept")
end

do
	local profileData = {
		partyHistory = {
			makeValidEntry("op-1"),
			makeValidEntry("op-1"),
			makeValidEntry("op-2"),
		},
	}
	local history = PartyHistoryProfileState.GetHistory(profileData)
	assertEqual(#history, 2, "duplicate operation ids deduped")
end

do
	local copied = PartyHistoryProfileState.CopyProfileField({
		partyHistory = {
			makeValidEntry("op-1"),
			invalidField = "ignored",
		},
		invalidField = "ignored",
	})
	assertTrue(type(copied) == "table", "copy returns table")
	assertEqual(#copied, 1, "copy entry count")
	assertEqual(copied[1].operationId, "op-1", "copy keeps operation id")
	assertTrue(copied[1].invalidField == nil, "copy drops invalid fields")
end

do
	local appendFirst = PartyHistoryProfileState.AppendEntry({}, makeValidEntry("op-1"))
	assertTrue(appendFirst.accepted, "append first entry accepted")
	assertEqual(appendFirst.reason, "accepted", "append first entry reason")
	assertTrue(PartyHistoryProfileState.HasPersistedState(appendFirst.profileData), "append writes profile")

	local appendDuplicate = PartyHistoryProfileState.AppendEntry(appendFirst.profileData, makeValidEntry("op-1"))
	assertTrue(appendDuplicate.accepted, "duplicate append accepted")
	assertEqual(
		#PartyHistoryProfileState.GetHistory(appendDuplicate.profileData),
		1,
		"duplicate replaces same operation"
	)
end

do
	local rejected = PartyHistoryProfileState.AppendEntry({}, {
		operationId = "op-invalid",
		partyId = "party-42",
		targetRealmId = "realm-9402",
		entryType = "unknown_type",
		formedAt = 100,
		partySize = 2,
		partyMemberUserIds = { 7101, 7102 },
	})
	assertFalse(rejected.accepted, "invalid entry rejected")
	assertEqual(rejected.reason, "party_history_entry_invalid", "invalid entry reason")
end

do
	local boundedProfile = {}
	for index = 1, PartyHistoryProfileState.GetDefaultHistoryLimit() + 5 do
		local appendResult = PartyHistoryProfileState.AppendEntry(boundedProfile, {
			operationId = string.format("op-%03d", index),
			partyId = string.format("party-%03d", index),
			targetRealmId = "realm-9402",
			entryType = "standard",
			formedAt = index,
			partySize = 1,
			partyMemberUserIds = { 7000 + index },
		})
		assertTrue(appendResult.accepted, "bounded append accepted")
		boundedProfile = appendResult.profileData
	end

	local boundedHistory = PartyHistoryProfileState.GetHistory(boundedProfile)
	assertEqual(#boundedHistory, PartyHistoryProfileState.GetDefaultHistoryLimit(), "bounded history trimmed to limit")
	assertEqual(boundedHistory[1].operationId, "op-006", "bounded history drops oldest entries")
	assertEqual(
		boundedHistory[#boundedHistory].operationId,
		string.format("op-%03d", PartyHistoryProfileState.GetDefaultHistoryLimit() + 5),
		"bounded history keeps newest entries"
	)
end

print("party_history_profile_state: all checks passed")
