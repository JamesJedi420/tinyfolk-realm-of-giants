--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local GiantDwellingConfig = require(Config:WaitForChild("GiantDwellingConfig"))
local StationConfig = require(Config:WaitForChild("StationConfig"))
local GiantHousingCapacityState = require(GiantRealm:WaitForChild("GiantHousingCapacityState"))

local DWELLING_FOLDER_PATH = { "Map", "Stations" }
local globalEnv: any = getfenv()

local dwellingPartById: { [string]: BasePart } = {}

local function debugLog(message: string)
	print(string.format("[GiantDwellingService] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[GiantDwellingService] %s", message))
end

local function startsWithPrefix(value: string, prefix: string): boolean
	return string.sub(value, 1, #prefix) == prefix
end

local function findStationsRoot(): Instance?
	local current: Instance? = Workspace
	for _, childName in ipairs(DWELLING_FOLDER_PATH) do
		if current == nil then
			return nil
		end
		current = current:FindFirstChild(childName)
	end
	return current
end

local function shouldTrackDwellingPart(part: BasePart): boolean
	return startsWithPrefix(part.Name, StationConfig.GiantDwellingNamePrefix)
end

local function resolveHousingCapacityMultiplier(dwellingId: string): number
	local upgradeApi = globalEnv._VillageWorksiteUpgradeService_QueryAPI
	if type(upgradeApi) ~= "table" and type(_G) == "table" then
		upgradeApi = (_G :: any)._VillageWorksiteUpgradeService_QueryAPI
	end

	if type(upgradeApi) == "table" and type(upgradeApi.GetGiantHousingCapacityMultiplier) == "function" then
		local resolvedMultiplier = upgradeApi.GetGiantHousingCapacityMultiplier(dwellingId)
		if type(resolvedMultiplier) == "number" and resolvedMultiplier > 0 then
			return resolvedMultiplier
		end
	end

	return 1
end

local function resolvePublishedHousingCapacity(dwellingId: string): number
	return GiantHousingCapacityState.ResolvePublishedCapacity(
		GiantDwellingConfig.BaseGiantHousingCapacity,
		resolveHousingCapacityMultiplier(dwellingId)
	)
end

local function buildEffectOwnerSnapshot(dwellingId: string): any
	return {
		effectOwner = dwellingId,
		effectKind = GiantDwellingConfig.EffectKind,
		effectScope = GiantDwellingConfig.EffectScope,
		sourceType = GiantDwellingConfig.SourceType,
		stationPath = GiantDwellingConfig.StationPath,
		publishedGiantHousingCapacity = resolvePublishedHousingCapacity(dwellingId),
	}
end

local function registerDwellingPart(part: BasePart)
	local dwellingId = part.Name
	if dwellingPartById[dwellingId] ~= nil then
		return
	end

	dwellingPartById[dwellingId] = part
	debugLog(string.format("Registered dwelling id=%s", dwellingId))
end

local function registerDwellingsFromWorkspace()
	local stationsRoot = findStationsRoot()
	if stationsRoot == nil then
		debugWarn("No stations root found at Workspace.Map.Stations")
		return
	end

	for _, descendant in stationsRoot:GetDescendants() do
		if descendant:IsA("BasePart") and shouldTrackDwellingPart(descendant) then
			registerDwellingPart(descendant)
		end
	end

	if next(dwellingPartById) == nil then
		debugWarn("No giant dwelling parts registered under Workspace.Map.Stations")
	end
end

local function GetGiantHousingCapacity(dwellingId: string): number
	if not startsWithPrefix(dwellingId, StationConfig.GiantDwellingNamePrefix) then
		return GiantHousingCapacityState.ResolvePublishedCapacity(GiantDwellingConfig.BaseGiantHousingCapacity, 1)
	end
	if dwellingPartById[dwellingId] == nil then
		return GiantHousingCapacityState.ResolvePublishedCapacity(GiantDwellingConfig.BaseGiantHousingCapacity, 1)
	end
	return resolvePublishedHousingCapacity(dwellingId)
end

local function GetDwellingSnapshot(dwellingId: string): any?
	local part = dwellingPartById[dwellingId]
	if part == nil then
		return nil
	end

	return {
		dwellingId = dwellingId,
		registered = true,
		effect = buildEffectOwnerSnapshot(dwellingId),
	}
end

local function GetRegisteredDwellingIds(): { string }
	local ids = {}
	for dwellingId in pairs(dwellingPartById) do
		table.insert(ids, dwellingId)
	end
	table.sort(ids)
	return ids
end

registerDwellingsFromWorkspace()

globalEnv._GiantDwellingService_QueryAPI = {
	GetGiantHousingCapacity = GetGiantHousingCapacity,
	GetDwellingSnapshot = GetDwellingSnapshot,
	GetRegisteredDwellingIds = GetRegisteredDwellingIds,
	ResetForTests = function()
		dwellingPartById = {}
		registerDwellingsFromWorkspace()
	end,
}

if type(_G) == "table" then
	(_G :: any)._GiantDwellingService_QueryAPI = globalEnv._GiantDwellingService_QueryAPI
end

debugLog("GiantDwellingService initialized")
