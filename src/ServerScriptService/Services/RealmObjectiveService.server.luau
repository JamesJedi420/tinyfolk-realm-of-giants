--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local EmergencyReinforcementConfig = require(Config:WaitForChild("EmergencyReinforcementConfig"))
local RealmObjectiveState = require(GiantRealm:WaitForChild("RealmObjectiveState"))

local ROLE_ATTRIBUTE = "Role"

local OBJECTIVE_PATH = { "Map", "Objectives" }

local state = RealmObjectiveState.NewState({
	BaseRequiredCompletions = 1,
	MinimumRequiredCompletions = 1,
})
local emergencyTokenState: any = {
	lifecycleState = "active",
	revoked = false,
	remainingTokens = 1,
	nextAvailableAt = nil,
	expiresAt = nil,
	scheduleWindows = nil,
	lastConsumedAt = nil,
	lastConsumedByUserId = nil,
}

local function getNow(): number
	return os.clock()
end

local function isFiniteNonNegativeNumber(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	return value >= 0
end

local function resolveAt(at: number?): number
	if isFiniteNonNegativeNumber(at) then
		return at :: number
	end
	return getNow()
end

local function isValidPositiveInteger(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	if value % 1 ~= 0 then
		return false
	end
	return value > 0
end

local function cloneEmergencyTokenState(): any
	local scheduleWindowsClone = nil
	if type(emergencyTokenState.scheduleWindows) == "table" then
		scheduleWindowsClone = {}
		for _, window in ipairs(emergencyTokenState.scheduleWindows) do
			if type(window) == "table" then
				local windowAny: any = window
				table.insert(scheduleWindowsClone, {
					startsAt = windowAny.startsAt,
					endsAt = windowAny.endsAt,
				})
			end
		end
	end

	return {
		lifecycleState = emergencyTokenState.lifecycleState,
		revoked = emergencyTokenState.revoked == true,
		remainingTokens = emergencyTokenState.remainingTokens,
		nextAvailableAt = emergencyTokenState.nextAvailableAt,
		expiresAt = emergencyTokenState.expiresAt,
		scheduleWindows = scheduleWindowsClone,
		lastConsumedAt = emergencyTokenState.lastConsumedAt,
		lastConsumedByUserId = emergencyTokenState.lastConsumedByUserId,
	}
end

local function isEmergencyObjectiveId(objectiveId: any): boolean
	if type(objectiveId) ~= "string" then
		return false
	end

	return objectiveId == EmergencyReinforcementConfig.CallCenterObjectiveId
end

local function evaluateEmergencyTokenGate(at: number): string?
	local lifecycleState = emergencyTokenState.lifecycleState
	if type(lifecycleState) == "string" and lifecycleState ~= "active" then
		return "token_lifecycle_inactive"
	end

	if emergencyTokenState.revoked == true then
		return "token_revoked"
	end

	local remainingTokens = emergencyTokenState.remainingTokens
	if type(remainingTokens) == "number" and remainingTokens <= 0 then
		return "token_unavailable"
	end

	local nextAvailableAt = emergencyTokenState.nextAvailableAt
	if isFiniteNonNegativeNumber(nextAvailableAt) and at < (nextAvailableAt :: number) then
		return "token_not_ready"
	end

	local expiresAt = emergencyTokenState.expiresAt
	if isFiniteNonNegativeNumber(expiresAt) and at >= (expiresAt :: number) then
		return "token_expired"
	end

	local scheduleWindows = emergencyTokenState.scheduleWindows
	if type(scheduleWindows) == "table" then
		local hasActiveWindow = false
		for _, window in ipairs(scheduleWindows) do
			if type(window) == "table" then
				local windowAny: any = window
				local startsAt = windowAny.startsAt
				local endsAt = windowAny.endsAt
				local hasValidStart = isFiniteNonNegativeNumber(startsAt)
				local hasValidEnd = endsAt == nil or isFiniteNonNegativeNumber(endsAt)
				if hasValidStart and hasValidEnd then
					local startValue = startsAt :: number
					local endValue = endsAt :: any
					if at >= startValue and (endValue == nil or at <= (endValue :: number)) then
						hasActiveWindow = true
						break
					end
				end
			end
		end

		if not hasActiveWindow then
			return "token_not_scheduled"
		end
	end

	return nil
end

local function makeEmergencyTokenResponse(accepted: boolean, reason: string): any
	return {
		accepted = accepted,
		reason = reason,
		tokenState = cloneEmergencyTokenState(),
	}
end

local function getPathNode(root: any, path: { string }): any?
	local current = root
	for _, segment in ipairs(path) do
		if current == nil then
			return nil
		end

		if type(current.FindFirstChild) == "function" then
			current = current:FindFirstChild(segment)
		elseif type(current.WaitForChild) == "function" then
			current = current:WaitForChild(segment, 0)
		else
			return nil
		end

		if current == nil then
			return nil
		end
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

local function getEscapeServiceQueryApi(): any?
	local globalValue: any = _G
	if type(globalValue) ~= "table" then
		return nil
	end
	local queryApi = globalValue._EscapeService_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end
	return queryApi
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
	GetObjectiveSafeRouteMetadata = function(routeId: string?): any
		local escapeQueryApi = getEscapeServiceQueryApi()
		if escapeQueryApi == nil or type(escapeQueryApi.GetObjectiveSafeRouteMetadata) ~= "function" then
			return if routeId == nil then {} else nil
		end
		local ok, metadata = pcall(function()
			return escapeQueryApi.GetObjectiveSafeRouteMetadata(routeId)
		end)
		if not ok then
			return if routeId == nil then {} else nil
		end
		return metadata
	end,
	GetEmergencyTokenSnapshot = function(objectiveId: string, at: number?): any
		if not isEmergencyObjectiveId(objectiveId) then
			return makeEmergencyTokenResponse(false, "invalid_objective")
		end

		local gateReason = evaluateEmergencyTokenGate(resolveAt(at))
		if type(gateReason) == "string" then
			return makeEmergencyTokenResponse(false, gateReason)
		end

		return makeEmergencyTokenResponse(true, "accepted")
	end,
	RequestConsumeEmergencyToken = function(requesterUserId: number, objectiveId: string, at: number?): any
		if not isValidPositiveInteger(requesterUserId) then
			return makeEmergencyTokenResponse(false, "requester_user_id_invalid")
		end

		if not isEmergencyObjectiveId(objectiveId) then
			return makeEmergencyTokenResponse(false, "invalid_objective")
		end

		local resolvedAt = resolveAt(at)
		local gateReason = evaluateEmergencyTokenGate(resolvedAt)
		if type(gateReason) == "string" then
			return makeEmergencyTokenResponse(false, gateReason)
		end

		if type(emergencyTokenState.remainingTokens) == "number" then
			emergencyTokenState.remainingTokens = math.max(0, (emergencyTokenState.remainingTokens :: number) - 1)
		end

		emergencyTokenState.lastConsumedAt = resolvedAt
		emergencyTokenState.lastConsumedByUserId = requesterUserId

		local cooldown = EmergencyReinforcementConfig.CallCooldownSeconds
		if isFiniteNonNegativeNumber(cooldown) then
			emergencyTokenState.nextAvailableAt = resolvedAt + (cooldown :: number)
		end

		return makeEmergencyTokenResponse(true, "accepted")
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
	BeginObjectiveProgress = function(siteId: string, userId: number?, at: number?): any
		recomputeRequirement()
		local transition = RealmObjectiveState.BeginProgress(state, siteId, userId, at)
		state = transition.state
		return {
			accepted = transition.accepted,
			reason = transition.reason,
			alert = transition.alert,
			snapshot = RealmObjectiveState.GetSnapshot(state),
		}
	end,
	ApplyObjectiveProgress = function(siteId: string, progressAmount: number, userId: number?, at: number?): any
		recomputeRequirement()
		local transition = RealmObjectiveState.ApplyProgress(state, siteId, progressAmount, userId, at)
		state = transition.state
		return {
			accepted = transition.accepted,
			reason = transition.reason,
			alert = transition.alert,
			snapshot = RealmObjectiveState.GetSnapshot(state),
		}
	end,
	CancelObjectiveProgress = function(siteId: string, at: number?): any
		recomputeRequirement()
		local transition = RealmObjectiveState.CancelProgress(state, siteId, at)
		state = transition.state
		return {
			accepted = transition.accepted,
			reason = transition.reason,
			alert = transition.alert,
			snapshot = RealmObjectiveState.GetSnapshot(state),
		}
	end,
	DisruptObjectiveProgress = function(
		siteId: string,
		userId: number?,
		at: number?,
		regressionWindowSeconds: number?
	): any
		recomputeRequirement()
		local transition = RealmObjectiveState.DisruptProgress(state, siteId, userId, at, regressionWindowSeconds)
		state = transition.state
		return {
			accepted = transition.accepted,
			reason = transition.reason,
			alert = transition.alert,
			snapshot = RealmObjectiveState.GetSnapshot(state),
		}
	end,
	TickObjectiveRegression = function(siteId: string, at: number): any
		recomputeRequirement()
		local transition = RealmObjectiveState.TickRegression(state, siteId, at)
		state = transition.state
		return {
			accepted = transition.accepted,
			reason = transition.reason,
			alert = transition.alert,
			snapshot = RealmObjectiveState.GetSnapshot(state),
		}
	end,
	BlockObjective = function(siteId: string, userId: number?, at: number?, durationSeconds: number?): any
		recomputeRequirement()
		local transition = RealmObjectiveState.BlockObjective(state, siteId, userId, at, durationSeconds)
		state = transition.state
		return {
			accepted = transition.accepted,
			reason = transition.reason,
			alert = transition.alert,
			snapshot = RealmObjectiveState.GetSnapshot(state),
		}
	end,
	SetObjectiveRuleLocked = function(siteId: string, locked: boolean, at: number?): any
		recomputeRequirement()
		local transition = RealmObjectiveState.SetRuleLocked(state, siteId, locked, at)
		state = transition.state
		return {
			accepted = transition.accepted,
			reason = transition.reason,
			alert = transition.alert,
			snapshot = RealmObjectiveState.GetSnapshot(state),
		}
	end,
	UnlockObjective = function(siteId: string, at: number?): any
		recomputeRequirement()
		local transition = RealmObjectiveState.UnlockObjective(state, siteId, at)
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
		emergencyTokenState = {
			lifecycleState = "active",
			revoked = false,
			remainingTokens = 1,
			nextAvailableAt = nil,
			expiresAt = nil,
			scheduleWindows = nil,
			lastConsumedAt = nil,
			lastConsumedByUserId = nil,
		}
		discoverWorkspaceObjectiveSites()
	end,
}
