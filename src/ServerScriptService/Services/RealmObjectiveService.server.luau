--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local RealmObjectiveState = require(GiantRealm:WaitForChild("RealmObjectiveState"))

local ROLE_ATTRIBUTE = "Role"

local OBJECTIVE_PATH = { "Map", "Objectives" }

local state = RealmObjectiveState.NewState({
	BaseRequiredCompletions = 1,
	MinimumRequiredCompletions = 1,
})

local function getNow(): number
	return os.clock()
end

local function getPathNode(root: any, path: { string }): any?
	local current = root
	for _, segment in ipairs(path) do
		if current == nil or type(current.WaitForChild) ~= "function" then
			return nil
		end
		current = current:WaitForChild(segment)
	end
	return current
end

local function getObjectiveSiteType(siteName: string): string
	if string.find(siteName, "ConstructionSite", 1, true) ~= nil then
		return "construction"
	end
	if string.find(siteName, "Station", 1, true) ~= nil then
		return "station"
	end
	if string.find(siteName, "Shrine", 1, true) ~= nil then
		return "shrine"
	end
	return "generic"
end

local function countActiveTinyfolk(): number
	local count = 0
	for _, player in Players:GetPlayers() do
		if player:GetAttribute(ROLE_ATTRIBUTE) == "Tinyfolk" then
			count += 1
		end
	end
	return count
end

local function recomputeRequirement()
	state = RealmObjectiveState.RecomputeRequiredCompletions(state, countActiveTinyfolk())
end

local function registerObjectiveSite(siteId: string, siteType: string)
	local transition = RealmObjectiveState.RegisterSite(state, siteId, siteType, countActiveTinyfolk())
	state = transition.state
	return transition
end

local function discoverWorkspaceObjectiveSites()
	local objectivesFolder = getPathNode(Workspace, OBJECTIVE_PATH)
	if objectivesFolder == nil or type(objectivesFolder.GetChildren) ~= "function" then
		return
	end

	for _, child in ipairs(objectivesFolder:GetChildren()) do
		local siteId = nil
		if type(child.GetAttribute) == "function" then
			local attributedSiteId = child:GetAttribute("ObjectiveSiteId")
			if type(attributedSiteId) == "string" and string.len(attributedSiteId) > 0 then
				siteId = attributedSiteId
			end
		end

		if siteId == nil and type(child.Name) == "string" then
			if string.find(child.Name, "ConstructionSite", 1, true) ~= nil then
				siteId = child.Name
			elseif string.find(child.Name, "Station", 1, true) ~= nil then
				siteId = child.Name
			elseif string.find(child.Name, "Shrine", 1, true) ~= nil then
				siteId = child.Name
			elseif string.find(child.Name, "ObjectiveSite", 1, true) ~= nil then
				siteId = child.Name
			end
		end

		if siteId ~= nil then
			registerObjectiveSite(siteId, getObjectiveSiteType(siteId))
		end
	end

	recomputeRequirement()
end

discoverWorkspaceObjectiveSites()

_G._RealmObjectiveService_QueryAPI = {
	GetObjectiveSnapshot = function(): any
		recomputeRequirement()
		return RealmObjectiveState.GetSnapshot(state)
	end,
	GetUnresolvedObjectiveSiteIds = function(): { string }
		recomputeRequirement()
		local snapshot = RealmObjectiveState.GetSnapshot(state)
		return snapshot.unresolvedSiteIds
	end,
	IsEscapeObjectiveThresholdMet = function(): boolean
		recomputeRequirement()
		local snapshot = RealmObjectiveState.GetSnapshot(state)
		return snapshot.escapeReady == true
	end,
	RecordObjectiveCompletion = function(siteId: string, completedByUserId: number?, at: number?): any
		recomputeRequirement()
		local transition = RealmObjectiveState.RecordCompletion(
			state,
			siteId,
			completedByUserId,
			if type(at) == "number" then at else getNow()
		)
		state = transition.state
		return {
			accepted = transition.accepted,
			reason = transition.reason,
			alert = transition.alert,
			snapshot = RealmObjectiveState.GetSnapshot(state),
		}
	end,
	RegisterObjectiveSiteForTests = function(siteId: string, siteType: string?): any
		local transition = registerObjectiveSite(siteId, if type(siteType) == "string" then siteType else "generic")
		return {
			accepted = transition.accepted,
			reason = transition.reason,
			snapshot = RealmObjectiveState.GetSnapshot(transition.state),
		}
	end,
	ResetForTests = function()
		state = RealmObjectiveState.NewState({
			BaseRequiredCompletions = 1,
			MinimumRequiredCompletions = 1,
		})
		discoverWorkspaceObjectiveSites()
	end,
}
