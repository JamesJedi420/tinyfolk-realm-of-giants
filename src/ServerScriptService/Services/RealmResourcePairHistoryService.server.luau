--!strict

local MemoryStoreAdapter = require(script.Parent:WaitForChild("MemoryStoreAdapter"))
local MemoryStoreStructurePolicy = require(script.Parent:WaitForChild("MemoryStoreStructurePolicy"))
local RealmResourcePairHistoryStore = require(script.Parent:WaitForChild("RealmResourcePairHistoryStore"))

local globalEnv: any = getfenv()

local function getGlobalTable(name: string): any?
	local fromEnv = rawget(globalEnv, name)
	if type(fromEnv) == "table" then
		return fromEnv
	end
	if type(_G) == "table" then
		local fromGlobal = rawget(_G, name)
		if type(fromGlobal) == "table" then
			return fromGlobal
		end
	end
	return nil
end

local function resolveAdapter(): any?
	local globalAdapter = getGlobalTable("_MemoryStoreAdapter_QueryAPI")
	if globalAdapter ~= nil then
		return globalAdapter
	end

	local policy = MemoryStoreStructurePolicy.GetPolicy("realmResourcePairHistory")
	local mapName = if type(policy) == "table" then policy.name else nil
	return MemoryStoreAdapter.CreateDefault({
		activeRealmCapacityMapName = mapName,
	})
end

local store = RealmResourcePairHistoryStore.Create({
	adapter = resolveAdapter(),
	structurePolicy = MemoryStoreStructurePolicy,
})

globalEnv._RealmResourcePairHistoryStore = store

return store
