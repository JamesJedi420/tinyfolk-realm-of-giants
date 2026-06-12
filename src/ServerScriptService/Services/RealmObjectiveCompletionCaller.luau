--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GiantRealm = Shared:WaitForChild("GiantRealm")
local RealmObjectiveSiteIdResolver = require(GiantRealm:WaitForChild("RealmObjectiveSiteIdResolver"))

local RealmObjectiveCompletionCaller = {}

local function getRealmObjectiveQueryApi(): any?
	local globalValue: any = _G
	if type(globalValue) ~= "table" then
		return nil
	end

	local queryApi = globalValue._RealmObjectiveService_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end

	return queryApi
end

function RealmObjectiveCompletionCaller.RecordContextualTaskCompletion(
	contextualTaskSiteId: string,
	completedByUserId: number,
	at: number?
): any?
	local registeredSiteId = RealmObjectiveSiteIdResolver.ResolveRegisteredSiteId(contextualTaskSiteId)
	if registeredSiteId == nil then
		return nil
	end

	local queryApi = getRealmObjectiveQueryApi()
	if queryApi == nil or type(queryApi.RecordObjectiveCompletion) ~= "function" then
		return nil
	end

	return queryApi.RecordObjectiveCompletion(registeredSiteId, completedByUserId, at)
end

return RealmObjectiveCompletionCaller
