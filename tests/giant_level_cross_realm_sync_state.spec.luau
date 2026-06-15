--!strict

local GiantLevelConfig = require("../src/ReplicatedStorage/Shared/Config/GiantLevelConfig")
local GiantLevelCrossRealmSyncState =
	require("../src/ReplicatedStorage/Shared/GiantRealm/GiantLevelCrossRealmSyncState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local realmId = "giant_realm_5001"
local now = 100

local left = GiantLevelCrossRealmSyncState.NewPendingXpBuffer(realmId, now)
local rightBuffer, _appendReason = GiantLevelCrossRealmSyncState.AppendPendingEvent(left, {
	operationId = "capture-a",
	eventKind = GiantLevelConfig.EventKinds.CaptureSuccess,
	xpAwarded = 25,
	awardedAt = 10,
}, now + 1, realmId)
assertTrue(rightBuffer ~= nil, "append first event")

local right, duplicateReason = GiantLevelCrossRealmSyncState.AppendPendingEvent(rightBuffer, {
	operationId = "capture-a",
	eventKind = GiantLevelConfig.EventKinds.CaptureSuccess,
	xpAwarded = 25,
	awardedAt = 10,
}, now + 2, realmId)
assertEqual(duplicateReason, "duplicate", "duplicate append flagged")
assertEqual(#(right :: any).events, 1, "duplicate append does not grow buffer")

local withSecond, _ = GiantLevelCrossRealmSyncState.AppendPendingEvent(right, {
	operationId = "trade-dest-op-9001",
	eventKind = GiantLevelConfig.EventKinds.TradeSuccess,
	xpAwarded = 30,
	awardedAt = 20,
}, now + 3, realmId)
assertEqual(#(withSecond :: any).events, 2, "second unique event appended")

local encoded, encodeReason = GiantLevelCrossRealmSyncState.EncodePendingXpBuffer(withSecond :: any)
assertTrue(encoded ~= nil, "encode pending buffer")
assertEqual(encodeReason, nil, "encode reason nil")

local decoded, decodeReason = GiantLevelCrossRealmSyncState.DecodePendingXpBuffer(encoded)
assertTrue(decoded ~= nil, "decode pending buffer")
assertEqual(decodeReason, nil, "decode reason nil")
assertEqual(decoded.realmId, realmId, "decoded realm id")
assertEqual(#decoded.events, 2, "decoded event count")

local persisted = {
	xp = 25,
	level = 1,
	recentEvents = {
		{
			operationId = "capture-a",
			eventKind = GiantLevelConfig.EventKinds.CaptureSuccess,
			xpAwarded = 25,
			awardedAt = 10,
		},
	},
}

local merged = GiantLevelCrossRealmSyncState.MergePersistenceWithPending(persisted, decoded)
assertTrue(merged.accepted, "merge persistence with pending accepted")
assertEqual(merged.state.xp, 55, "merge replays only unseen pending events")
assertEqual(merged.state.level, 1, "merge level after one new event")

local duplicateMerge = GiantLevelCrossRealmSyncState.MergePersistenceWithPending(persisted, decoded)
assertEqual(duplicateMerge.state.xp, 55, "replay remains idempotent against persisted operation ids")

local acked = GiantLevelCrossRealmSyncState.PruneAcknowledgedOperationIds(
	decoded,
	GiantLevelCrossRealmSyncState.CollectAcknowledgedOperationIds({
		recentEvents = {
			{ operationId = "capture-a" },
			{ operationId = "trade-dest-op-9001" },
		},
	}),
	now + 4
)
assertTrue(acked == nil, "all acknowledged events pruned")

print("giant_level_cross_realm_sync_state.spec.luau: all checks passed")
