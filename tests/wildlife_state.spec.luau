--!strict

local WildlifeState = require("../src/ReplicatedStorage/Shared/GiantRealm/WildlifeState")

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

local accepted, reason, record = WildlifeState.NewRecord({
	wildlifeId = "wildlife_default_1",
	realmTemplateId = "DefaultRealm",
	habitatGroupId = "forest_edge",
	speciesId = "deer",
	spawnedAt = 10,
	expiresAt = 40,
})
assertTrue(accepted, "new record accepted")
assertEqual(reason, "accepted", "new record reason")
assertEqual(record.status, WildlifeState.Status.Active, "new record active status")
assertTrue(WildlifeState.IsActive(record, 20), "new record active before expiry")

local invalidAccepted, invalidReason = WildlifeState.NewRecord({
	wildlifeId = "",
	realmTemplateId = "DefaultRealm",
	habitatGroupId = "forest_edge",
	speciesId = "deer",
	spawnedAt = 10,
	expiresAt = 40,
})
assertFalse(invalidAccepted, "invalid id rejected")
assertEqual(invalidReason, "wildlife_id_invalid", "invalid id reason")

local disturbed, disturbedReason, disturbedRecord = WildlifeState.ResolveDisturbance(record, 22)
assertTrue(disturbed, "disturbance accepted")
assertEqual(disturbedReason, "disturbed", "disturbance reason")
assertEqual(disturbedRecord.status, WildlifeState.Status.Disturbed, "disturbance status")
assertEqual(disturbedRecord.disturbedAt, 22, "disturbance timestamp")

local expired, expiredReason, expiredRecord = WildlifeState.ResolveExpiry(disturbedRecord, 45)
assertTrue(expired, "expiry accepted")
assertEqual(expiredReason, "expired", "expiry reason")
assertEqual(expiredRecord.status, WildlifeState.Status.Expired, "expiry status")
assertFalse(WildlifeState.IsActive(expiredRecord, 46), "expired record not active")

local disturbExpired, disturbExpiredReason = WildlifeState.ResolveDisturbance(expiredRecord, 47)
assertFalse(disturbExpired, "disturbance terminal rejected")
assertEqual(disturbExpiredReason, "wildlife_terminal", "disturbance terminal reason")

local despawned, despawnedReason, despawnedRecord = WildlifeState.ResolveDespawn(record, "manual_cleanup", 30)
assertTrue(despawned, "despawn accepted")
assertEqual(despawnedReason, "manual_cleanup", "despawn reason")
assertEqual(despawnedRecord.status, WildlifeState.Status.Despawned, "despawn status")

local snapshot = WildlifeState.BuildSnapshot(disturbedRecord, 23)
assertEqual(snapshot.wildlifeId, "wildlife_default_1", "snapshot id")
assertTrue(snapshot.active, "snapshot active while disturbed before expiry")
snapshot.habitatGroupId = "mutated"
local cleanSnapshot = WildlifeState.BuildSnapshot(disturbedRecord, 23)
assertEqual(cleanSnapshot.habitatGroupId, "forest_edge", "snapshot clone integrity")

print("wildlife_state: all checks passed")
