--!strict

local ActiveRealmCapacityStore = require(script.Parent:WaitForChild("ActiveRealmCapacityStore"))
local ActiveRealmCapacityState = require(script.Parent:WaitForChild("ActiveRealmCapacityState"))
local MemoryStoreStructurePolicy = require(script.Parent:WaitForChild("MemoryStoreStructurePolicy"))

local globalEnv: any = getfenv()
local store = ActiveRealmCapacityStore.Create({
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
