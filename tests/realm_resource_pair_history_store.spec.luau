--!strict

local MemoryStoreStructurePolicy = require("../src/ServerScriptService/Services/MemoryStoreStructurePolicy")
local RealmResourcePairHistoryStore = require("../src/ServerScriptService/Services/RealmResourcePairHistoryStore")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

local store = RealmResourcePairHistoryStore.Create({
	structurePolicy = MemoryStoreStructurePolicy,
	now = function()
		return 200
	end,
})

local pairKey = "9402.101.defense_escape_outcome"

do
	assertEqual(store.ReadPairCount(pairKey, 200), 0, "initial pair count")
	store.WritePairCount(pairKey, 1, 200)
	assertEqual(store.ReadPairCount(pairKey, 210), 1, "stored pair count")
	store.WritePairCount(pairKey, 2, 220)
	assertEqual(store.ReadPairCount(pairKey, 230), 2, "updated pair count")
end

do
	store.WritePairCount("9402.202.defense_escape_outcome", 1, 100)
	assertEqual(store.ReadPairCount("9402.202.defense_escape_outcome", 500), 0, "expired in-memory pair count")
end

print("realm_resource_pair_history_store.spec.luau: all checks passed")
