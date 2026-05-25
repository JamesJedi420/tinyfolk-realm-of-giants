--!strict

local ActiveRealmCapacityStore = require(script.Parent:WaitForChild("ActiveRealmCapacityStore"))
local ActiveRealmCapacityState = require(script.Parent:WaitForChild("ActiveRealmCapacityState"))
local MemoryStoreStructurePolicy = require(script.Parent:WaitForChild("MemoryStoreStructurePolicy"))
local MemoryStoreAdapter = require(script.Parent:WaitForChild("MemoryStoreAdapter"))

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

	local activeCapacityPolicy = MemoryStoreStructurePolicy.GetPolicy("activeRealmCapacity")
	local mapName = if type(activeCapacityPolicy) == "table" then activeCapacityPolicy.name else nil

	local adapter = MemoryStoreAdapter.CreateDefault({
		activeRealmCapacityMapName = mapName,
	})
	if type(adapter) == "table" then
		return adapter
	end

	return nil
end

local store = ActiveRealmCapacityStore.Create({
	adapter = resolveAdapter(),
	capacityState = ActiveRealmCapacityState,
	structurePolicy = MemoryStoreStructurePolicy,
})

globalEnv._ActiveRealmCapacity_QueryAPI = {
	GetCapacitySnapshot = function(realmId: any): any
		return store.GetCapacitySnapshot(realmId)
	end,
	RefreshCapacity = function(input: any): any
		return store.RefreshCapacity(input)
	end,
	ReserveTinyfolkSlots = function(realmId: any, count: number, now: number): any
		return store.ReserveTinyfolkSlots(realmId, count, now)
	end,
	CommitTinyfolkArrival = function(realmId: any, count: number, now: number): any
		return store.CommitTinyfolkArrival(realmId, count, now)
	end,
	ReleaseReservedSlots = function(realmId: any, count: number, now: number): any
		return store.ReleaseReservedSlots(realmId, count, now)
	end,
}

if type(_G) == "table" then
	rawset(_G, "_ActiveRealmCapacity_QueryAPI", globalEnv._ActiveRealmCapacity_QueryAPI)
end

return globalEnv._ActiveRealmCapacity_QueryAPI
