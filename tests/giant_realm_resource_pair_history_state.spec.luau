--!strict

local GiantRealmResourcePairHistoryState =
	require("../src/ReplicatedStorage/Shared/GiantRealm/GiantRealmResourcePairHistoryState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

do
	local key = GiantRealmResourcePairHistoryState.BuildPairKey(9402, 101, "containment_custody_end")
	assertEqual(key, "9402.101.containment_custody_end", "pair key format")
end

do
	local encoded = GiantRealmResourcePairHistoryState.EncodeRecord(2, 150)
	local record, reason = GiantRealmResourcePairHistoryState.DecodeRecord(encoded)
	assertEqual(reason, nil, "decode reason")
	assertEqual(record.count, 2, "decoded count")
	assertEqual(record.lastAt, 150, "decoded lastAt")
end

do
	local record = { count = 2, lastAt = 100 }
	assertEqual(GiantRealmResourcePairHistoryState.ResolvePairCount(record, 401, 300), 0, "expired pair count")
	assertEqual(GiantRealmResourcePairHistoryState.ResolvePairCount(record, 350, 300), 2, "active pair count")
end

print("giant_realm_resource_pair_history_state.spec.luau: all checks passed")
