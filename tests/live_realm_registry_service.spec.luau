--!strict

local LiveRealmRegistryService = require("../src/ServerScriptService/Services/LiveRealmRegistryService")
local LiveRealmRegistryState = require("../src/ReplicatedStorage/Shared/GiantRealm/LiveRealmRegistryState")
local LiveRealmRegistryStore = require("../src/ServerScriptService/Services/LiveRealmRegistryStore")
local MemoryStoreStructurePolicy = require("../src/ServerScriptService/Services/MemoryStoreStructurePolicy")

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

local notifications: { any } = {}
local now = 1000

local function makeFanout()
	return {
		PublishRealmStatus = function(_eventName: string, payload: any): any
			table.insert(notifications, payload)
			return {
				accepted = true,
				reason = "accepted",
			}
		end,
	}
end

local function makeStoreAdapter()
	local storage: { [string]: { value: string, sortKey: number } } = {}
	local adapter: any = {}
	adapter.SortedMapSetAsync = function(_mapName: string, key: string, value: string, sortKey: number, _ttl: number)
		storage[key] = { value = value, sortKey = sortKey }
	end
	adapter.SortedMapGetAsync = function(_mapName: string, key: string): string?
		local stored = storage[key]
		return if stored ~= nil then stored.value else nil
	end
	adapter.SortedMapRemoveAsync = function(_mapName: string, key: string)
		storage[key] = nil
	end
	adapter.SortedMapGetRangeAsync = function(_mapName: string, _direction: string, count: number): { any }
		local items = {}
		for key, stored in pairs(storage) do
			table.insert(items, { key = key, value = stored.value, sortKey = stored.sortKey })
		end
		table.sort(items, function(left: any, right: any): boolean
			return left.sortKey > right.sortKey
		end)
		local result = {}
		for index, item in ipairs(items) do
			if index > count then
				break
			end
			table.insert(result, item)
		end
		return result
	end
	return adapter
end

LiveRealmRegistryService.ResetForTests()
local startResult = LiveRealmRegistryService.ConfigureForTests({
	registryState = LiveRealmRegistryState,
	structurePolicy = MemoryStoreStructurePolicy,
	storeModule = LiveRealmRegistryStore,
	adapter = makeStoreAdapter(),
	queueNotificationFanout = makeFanout(),
	enableHeartbeat = false,
	now = function()
		return now
	end,
	jobId = "job-service-1",
	privateServerId = "ps-service-1",
	getPlayerCount = function(): number
		return 4
	end,
})
assertTrue(startResult.ok, "service start")

local publish = LiveRealmRegistryService.PublishActiveRealm({
	ownerUserId = 9001,
})
assertTrue(publish.accepted, "publish active realm")
assertEqual(publish.snapshot.realmId, "giant_realm_9001", "published realm id")
assertEqual(publish.snapshot.jobId, "job-service-1", "published job id")
assertEqual(publish.snapshot.lifecycle, LiveRealmRegistryState.Lifecycle.Active, "published lifecycle")
assertTrue(#notifications >= 2, "status notifications published")

local registrySnapshot = LiveRealmRegistryService.GetRegistrySnapshot("giant_realm_9001")
assertTrue(registrySnapshot.accepted, "registry snapshot accepted")
assertEqual(registrySnapshot.snapshot.privateServerId, "ps-service-1", "stable private server id")

now = 1010
local refresh = LiveRealmRegistryService.RefreshActiveRealm({
	ownerUserId = 9001,
})
assertTrue(refresh.accepted, "refresh active realm")
assertEqual(refresh.snapshot.playerCount, 4, "refresh player count")

local availability = LiveRealmRegistryService.ListLiveRealmAvailability(10, now)
assertEqual(#availability, 1, "availability count")
assertTrue(availability[1].isAvailable, "availability online")
assertEqual(availability[1].realmId, "giant_realm_9001", "availability realm id")

local prune = LiveRealmRegistryService.PruneActiveRealm({
	ownerUserId = 9001,
})
assertTrue(prune.accepted, "prune active realm")

local offlineAvailability = LiveRealmRegistryService.ListLiveRealmAvailability(10, now)
assertEqual(#offlineAvailability, 0, "pruned realm not listed")

local diagnostics = LiveRealmRegistryService.GetDiagnostics()
assertTrue(diagnostics.publishSucceeded >= 1, "publish diagnostics")
assertTrue(diagnostics.pruneSucceeded >= 1, "prune diagnostics")

LiveRealmRegistryService.ResetForTests()
print("live_realm_registry_service.spec.luau: all checks passed")
