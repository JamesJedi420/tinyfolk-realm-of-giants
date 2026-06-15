--!strict

local MemoryStoreAdapter = require(script.Parent:WaitForChild("MemoryStoreAdapter"))
local MemoryStoreStructurePolicy = require(script.Parent:WaitForChild("MemoryStoreStructurePolicy"))

local globalEnv: any = getfenv()

local function buildAdapter(): any?
	local activeCapacityPolicy = MemoryStoreStructurePolicy.GetPolicy("activeRealmCapacity")
	local mapName = if type(activeCapacityPolicy) == "table" then activeCapacityPolicy.name else nil
	local liveRegistryPolicy = MemoryStoreStructurePolicy.GetPolicy("liveRealmRegistry")
	local liveRegistryMapName = if type(liveRegistryPolicy) == "table" then liveRegistryPolicy.name else nil

	return MemoryStoreAdapter.CreateDefault({
		activeRealmCapacityMapName = mapName,
		liveRealmRegistryMapName = liveRegistryMapName,
	})
end

local adapter = buildAdapter()
if type(adapter) == "table" then
	globalEnv._MemoryStoreAdapter_QueryAPI = adapter
	if type(_G) == "table" then
		rawset(_G, "_MemoryStoreAdapter_QueryAPI", adapter)
	end
end

return globalEnv._MemoryStoreAdapter_QueryAPI
