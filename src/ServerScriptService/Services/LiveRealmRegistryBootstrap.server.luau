--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local LiveRealmRegistryState = require(GiantRealm:WaitForChild("LiveRealmRegistryState"))
local LiveRealmRegistryStore = require(script.Parent:WaitForChild("LiveRealmRegistryStore"))
local LiveRealmRegistryService = require(script.Parent.LiveRealmRegistryService)
local MemoryStoreAdapter = require(script.Parent:WaitForChild("MemoryStoreAdapter"))
local MemoryStoreStructurePolicy = require(script.Parent:WaitForChild("MemoryStoreStructurePolicy"))

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

	local liveRegistryPolicy = MemoryStoreStructurePolicy.GetPolicy("liveRealmRegistry")
	local activeCapacityPolicy = MemoryStoreStructurePolicy.GetPolicy("activeRealmCapacity")
	local liveRegistryMapName = if type(liveRegistryPolicy) == "table" then liveRegistryPolicy.name else nil
	local activeCapacityMapName = if type(activeCapacityPolicy) == "table" then activeCapacityPolicy.name else nil

	return MemoryStoreAdapter.CreateDefault({
		activeRealmCapacityMapName = activeCapacityMapName,
		liveRealmRegistryMapName = liveRegistryMapName,
	})
end

local function resolvePlayerCount(): number
	local playersService = game:GetService("Players")
	local players = playersService:GetPlayers()
	return #players
end

LiveRealmRegistryService.Start({
	registryState = LiveRealmRegistryState,
	structurePolicy = MemoryStoreStructurePolicy,
	storeModule = LiveRealmRegistryStore,
	adapter = resolveAdapter(),
	getPlayerCount = resolvePlayerCount,
})

if game ~= nil and type(game.BindToClose) == "function" then
	game:BindToClose(function()
		local roleApi = getGlobalTable("_RoleService_QueryAPI")
		if type(roleApi) == "table" and type(roleApi.GetActiveGiantRealmOwnerUserId) == "function" then
			local ownerUserId = roleApi.GetActiveGiantRealmOwnerUserId()
			if type(ownerUserId) == "number" and ownerUserId > 0 then
				pcall(LiveRealmRegistryService.PruneActiveRealm, {
					ownerUserId = ownerUserId,
				})
			end
		end
	end)
end

globalEnv._LiveRealmRegistry_QueryAPI = {
	PublishActiveRealm = function(input: any): any
		return LiveRealmRegistryService.PublishActiveRealm(input)
	end,
	RefreshActiveRealm = function(input: any): any
		return LiveRealmRegistryService.RefreshActiveRealm(input)
	end,
	PruneActiveRealm = function(input: any): any
		return LiveRealmRegistryService.PruneActiveRealm(input)
	end,
	GetRegistrySnapshot = function(realmId: any): any
		return LiveRealmRegistryService.GetRegistrySnapshot(realmId)
	end,
	ListLiveRegistryEntries = function(limit: any, exclusiveStartKey: any?): any
		return LiveRealmRegistryService.ListLiveRegistryEntries(limit, exclusiveStartKey)
	end,
	GetDiagnostics = function(): any
		return LiveRealmRegistryService.GetDiagnostics()
	end,
	ConfigureForTests = function(config: any): any
		return LiveRealmRegistryService.ConfigureForTests(config)
	end,
	ResetForTests = function()
		LiveRealmRegistryService.ResetForTests()
	end,
}

globalEnv._LiveRealmRegistryHubSurface_QueryAPI = {
	ListLiveRealmAvailability = function(limit: any, at: number?): { any }
		return LiveRealmRegistryService.ListLiveRealmAvailability(limit, at)
	end,
}

if type(_G) == "table" then
	rawset(_G, "_LiveRealmRegistry_QueryAPI", globalEnv._LiveRealmRegistry_QueryAPI)
	rawset(_G, "_LiveRealmRegistryHubSurface_QueryAPI", globalEnv._LiveRealmRegistryHubSurface_QueryAPI)
end

return globalEnv._LiveRealmRegistry_QueryAPI
