--!strict

local DiscoveredRealmsProfileState = require("../src/ReplicatedStorage/Shared/GiantRealm/DiscoveredRealmsProfileState")

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

local function makeValidEntry(realmId: string, firstDiscoveredAt: number): any
	return {
		realmId = realmId,
		firstDiscoveredAt = firstDiscoveredAt,
	}
end

do
	assertFalse(DiscoveredRealmsProfileState.HasPersistedState(nil), "nil profile not persisted")
	assertFalse(DiscoveredRealmsProfileState.HasPersistedState({}), "empty profile not persisted")
	assertFalse(
		DiscoveredRealmsProfileState.HasPersistedState({
			discoveredRealms = {},
		}),
		"empty discovered realms not persisted"
	)
end

do
	local profileData = {
		discoveredRealms = {
			makeValidEntry("realm-main-01", 10),
		},
	}
	assertTrue(DiscoveredRealmsProfileState.HasPersistedState(profileData), "valid discoveries persisted")
	local discoveries = DiscoveredRealmsProfileState.GetDiscoveries(profileData)
	assertEqual(#discoveries, 1, "discovery count")
	assertEqual(discoveries[1].realmId, "realm-main-01", "discovery realm id")
	assertEqual(discoveries[1].firstDiscoveredAt, 10, "discovery timestamp")
	assertTrue(DiscoveredRealmsProfileState.IsDiscovered(profileData, "realm-main-01"), "realm discovered")
	assertFalse(DiscoveredRealmsProfileState.IsDiscovered(profileData, "realm-other"), "other realm not discovered")
end

do
	local profileData = {
		discoveredRealms = {
			{
				realmId = "",
				firstDiscoveredAt = 10,
			},
		},
	}
	assertFalse(DiscoveredRealmsProfileState.HasPersistedState(profileData), "empty realm id rejected")
end

do
	local profileData = {
		discoveredRealms = {
			{
				realmId = "realm-main-01",
				firstDiscoveredAt = -1,
			},
		},
	}
	assertFalse(DiscoveredRealmsProfileState.HasPersistedState(profileData), "invalid timestamp rejected")
end

do
	local profileData = {
		discoveredRealms = {
			makeValidEntry("realm-main-01", 10),
			makeValidEntry("realm-main-01", 20),
			makeValidEntry("realm-main-02", 15),
		},
	}
	local discoveries = DiscoveredRealmsProfileState.GetDiscoveries(profileData)
	assertEqual(#discoveries, 2, "duplicate realm ids deduped")
	assertEqual(discoveries[1].realmId, "realm-main-01", "first duplicate keeps earliest entry")
	assertEqual(discoveries[1].firstDiscoveredAt, 10, "first duplicate keeps earliest timestamp")
end

do
	local copied = DiscoveredRealmsProfileState.CopyProfileField({
		discoveredRealms = {
			makeValidEntry("realm-main-01", 10),
			invalidField = "ignored",
		},
		invalidField = "ignored",
	})
	assertTrue(type(copied) == "table", "copy returns table")
	assertEqual(#copied, 1, "copy entry count")
	assertEqual(copied[1].realmId, "realm-main-01", "copy keeps realm id")
	assertTrue(copied[1].invalidField == nil, "copy drops invalid fields")
end

do
	local recordFirst = DiscoveredRealmsProfileState.RecordDiscovery({}, makeValidEntry("realm-main-01", 10))
	assertTrue(recordFirst.accepted, "record first discovery accepted")
	assertEqual(recordFirst.reason, "accepted", "record first discovery reason")
	assertTrue(recordFirst.recorded == true, "record first discovery recorded")
	assertTrue(
		DiscoveredRealmsProfileState.HasPersistedState(recordFirst.profileData),
		"record first discovery writes profile"
	)

	local recordDuplicate =
		DiscoveredRealmsProfileState.RecordDiscovery(recordFirst.profileData, makeValidEntry("realm-main-01", 99))
	assertTrue(recordDuplicate.accepted, "duplicate discovery accepted")
	assertEqual(recordDuplicate.reason, "already_discovered", "duplicate discovery reason")
	assertFalse(recordDuplicate.recorded == true, "duplicate discovery not re-recorded")
	assertEqual(
		DiscoveredRealmsProfileState.GetDiscoveries(recordDuplicate.profileData)[1].firstDiscoveredAt,
		10,
		"duplicate discovery preserves first timestamp"
	)
end

do
	local rejected = DiscoveredRealmsProfileState.RecordDiscovery({}, {
		realmId = "",
		firstDiscoveredAt = 10,
	})
	assertFalse(rejected.accepted, "invalid record rejected")
	assertEqual(rejected.reason, "discovered_realms_input_invalid", "invalid record reason")
end

do
	local boundedProfile = {}
	for index = 1, DiscoveredRealmsProfileState.GetDefaultDiscoveryLimit() + 5 do
		local recordResult = DiscoveredRealmsProfileState.RecordDiscovery(boundedProfile, {
			realmId = string.format("realm-%03d", index),
			firstDiscoveredAt = index,
		})
		assertTrue(recordResult.accepted, "bounded record accepted")
		boundedProfile = recordResult.profileData
	end

	local boundedDiscoveries = DiscoveredRealmsProfileState.GetDiscoveries(boundedProfile)
	assertEqual(
		#boundedDiscoveries,
		DiscoveredRealmsProfileState.GetDefaultDiscoveryLimit(),
		"bounded discoveries trimmed to limit"
	)
	assertEqual(boundedDiscoveries[1].realmId, "realm-006", "bounded discoveries drop oldest entries")
	assertEqual(
		boundedDiscoveries[#boundedDiscoveries].realmId,
		string.format("realm-%03d", DiscoveredRealmsProfileState.GetDefaultDiscoveryLimit() + 5),
		"bounded discoveries keep newest entries"
	)
end

print("discovered_realms_profile_state: all checks passed")
