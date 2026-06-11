--!strict

local EscapeHistoryProfileState = require("../src/ReplicatedStorage/Shared/Escape/EscapeHistoryProfileState")

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
		escapedAt = 10,
		sourceKind = "final_exit",
		sourceId = "EscapeRoute_A",
		routeId = "EscapeRoute_A",
		realmId = "giant_realm_9001",
		realmOwnerUserId = 9001,
		difficulty = 2,
		reward = {
			points = 125,
			basePoints = 100,
			difficulty = 2,
			lootValue = 3,
		},
		loot = {
			items = { "glimmer" },
			wood = 2,
			stone = 1,
			value = 3,
		},
	}
end

do
	assertFalse(EscapeHistoryProfileState.HasPersistedState(nil), "nil profile not persisted")
	assertFalse(EscapeHistoryProfileState.HasPersistedState({}), "empty profile not persisted")
	assertFalse(
		EscapeHistoryProfileState.HasPersistedState({
			escapeHistory = {},
		}),
		"empty history not persisted"
	)
end

do
	local profileData = {
		escapeHistory = { makeValidEntry("op-1") },
	}
	assertTrue(EscapeHistoryProfileState.HasPersistedState(profileData), "valid history persisted")
	local history = EscapeHistoryProfileState.GetHistory(profileData)
	assertEqual(#history, 1, "history length")
	assertEqual(history[1].operationId, "op-1", "history operation id")
	assertEqual(history[1].sourceKind, "final_exit", "history source kind")
	assertEqual(history[1].realmOwnerUserId, 9001, "history realm owner")
end

do
	local profileData = {
		escapeHistory = {
			{
				operationId = "op-invalid",
				escapedAt = -1,
				sourceKind = "",
				sourceId = "EscapeRoute_A",
			},
			makeValidEntry("op-valid"),
		},
	}
	local history = EscapeHistoryProfileState.GetHistory(profileData)
	assertEqual(#history, 1, "invalid entries filtered")
	assertEqual(history[1].operationId, "op-valid", "valid entry preserved")
end

do
	local profileData = {
		escapeHistory = {
			makeValidEntry("op-dup"),
			{
				operationId = "op-dup",
				escapedAt = 20,
				sourceKind = "transport",
				sourceId = "Transport_A",
				difficulty = 1,
			},
			makeValidEntry("op-2"),
		},
	}
	local copied = EscapeHistoryProfileState.CopyProfileField(profileData)
	assertEqual(#copied, 2, "copy dedupes operation ids")
	assertEqual(copied[1].operationId, "op-dup", "copy keeps first duplicate")
	assertEqual(copied[1].sourceKind, "final_exit", "copy keeps first duplicate payload")
	assertEqual(copied[2].operationId, "op-2", "copy keeps second entry")
end

do
	local appendFirst = EscapeHistoryProfileState.AppendEntry({}, makeValidEntry("op-append-1"))
	assertTrue(appendFirst.accepted, "append accepted")
	assertEqual(#appendFirst.profileData.escapeHistory, 1, "append writes one entry")

	local appendSecond = EscapeHistoryProfileState.AppendEntry(appendFirst.profileData, {
		operationId = "op-append-2",
		escapedAt = 11,
		sourceKind = "route_escape",
		sourceId = "EscapeRoute_B",
		routeId = "EscapeRoute_B",
		difficulty = 1,
	})
	assertTrue(appendSecond.accepted, "append second accepted")
	assertEqual(#appendSecond.profileData.escapeHistory, 2, "append keeps prior entries")
	assertEqual(appendSecond.profileData.escapeHistory[2].operationId, "op-append-2", "append appends newest")

	local appendReplace = EscapeHistoryProfileState.AppendEntry(appendSecond.profileData, {
		operationId = "op-append-1",
		escapedAt = 99,
		sourceKind = "transport",
		sourceId = "Transport_A",
		difficulty = 1,
	})
	assertTrue(appendReplace.accepted, "append replace accepted")
	assertEqual(#appendReplace.profileData.escapeHistory, 2, "append replace keeps count")
	assertEqual(appendReplace.profileData.escapeHistory[2].operationId, "op-append-1", "append replace updates tail")
	assertEqual(appendReplace.profileData.escapeHistory[2].sourceKind, "transport", "append replace updates payload")
end

do
	local boundedProfile: any = {
		escapeHistory = {},
	}
	for index = 1, 26 do
		local appendResult = EscapeHistoryProfileState.AppendEntry(boundedProfile, {
			operationId = "op-" .. tostring(index),
			escapedAt = index,
			sourceKind = "route_escape",
			sourceId = "EscapeRoute_A",
			difficulty = 1,
		})
		assertTrue(appendResult.accepted, "bounded append accepted " .. tostring(index))
		boundedProfile = appendResult.profileData
	end

	assertEqual(
		#boundedProfile.escapeHistory,
		EscapeHistoryProfileState.GetDefaultHistoryLimit(),
		"bounded history enforces default limit"
	)
	assertEqual(boundedProfile.escapeHistory[1].operationId, "op-2", "bounded history drops oldest")
	assertEqual(
		boundedProfile.escapeHistory[EscapeHistoryProfileState.GetDefaultHistoryLimit()].operationId,
		"op-26",
		"bounded history keeps newest"
	)
end

do
	local rejected = EscapeHistoryProfileState.AppendEntry({}, {
		operationId = "",
		escapedAt = 10,
		sourceKind = "final_exit",
		sourceId = "EscapeRoute_A",
	})
	assertFalse(rejected.accepted, "invalid append rejected")
	assertEqual(rejected.reason, "escape_history_entry_invalid", "invalid append reason")
end

print("escape_history_profile_state: all checks passed")
