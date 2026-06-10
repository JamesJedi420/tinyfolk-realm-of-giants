--!nocheck
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local GiantLevelConfig = require(Config:WaitForChild("GiantLevelConfig"))
local GiantLevelState = require(GiantRealm:WaitForChild("GiantLevelState"))

local globalEnv: any = getfenv()

local levelState = GiantLevelState.CreateEmptyState()

local function debugLog(message: string)
	print(string.format("[GiantLevelService] %s", message))
end

local function getGiantBuildModeQueryApi(): any?
	local queryApi = globalEnv._GiantBuildModeService_QueryAPI
	if type(queryApi) == "table" then
		return queryApi
	end
	if type(_G) == "table" and type((_G :: any)._GiantBuildModeService_QueryAPI) == "table" then
		return (_G :: any)._GiantBuildModeService_QueryAPI
	end
	return nil
end

local function getRealmOwnerUserId(): number?
	local buildModeApi = getGiantBuildModeQueryApi()
	if type(buildModeApi) == "table" and type(buildModeApi.GetActiveGiantRealmOwnerUserId) == "function" then
		local ownerUserId = buildModeApi.GetActiveGiantRealmOwnerUserId()
		if type(ownerUserId) == "number" and ownerUserId > 0 then
			return math.floor(ownerUserId)
		end
	end
	return nil
end

local function getPlayerByUserId(userId: number): Player?
	for _, player in Players:GetPlayers() do
		if player.UserId == userId then
			return player :: any
		end
	end
	return nil
end

local function projectRealmOwnerAttributes()
	local ownerUserId = getRealmOwnerUserId()
	if ownerUserId == nil then
		return
	end

	local owner = getPlayerByUserId(ownerUserId)
	if owner == nil then
		return
	end

	local attrs = GiantLevelConfig.StateAttributes
	owner:SetAttribute(attrs.Xp, levelState.xp)
	owner:SetAttribute(attrs.Level, levelState.level)
	owner:SetAttribute(attrs.XpToNextLevel, GiantLevelState.ResolveXpToNextLevel(levelState.xp, levelState.level))
end

local function grantXpEvent(input: any): any
	local result = GiantLevelState.ApplyXpEvent(levelState, input)
	if type(result) ~= "table" then
		return { accepted = false, reason = "apply_xp_event_invalid" }
	end
	if result.accepted == true and type(result.state) == "table" then
		levelState = result.state
		projectRealmOwnerAttributes()
		debugLog(
			string.format(
				"Granted XP kind=%s operationId=%s xp=%d level=%d",
				tostring(input.eventKind),
				tostring(input.operationId),
				levelState.xp,
				levelState.level
			)
		)
	end
	return result
end

local function recordCaptureSuccess(custodianUserId: number, targetUserId: number, at: number): any
	return grantXpEvent({
		operationId = string.format("trophy-capture-%d-%d-%d", custodianUserId, targetUserId, math.floor(at * 1000)),
		eventKind = GiantLevelConfig.EventKinds.CaptureSuccess,
		awardedAt = at,
	})
end

local function recordContainmentEnd(metadata: any): any
	if type(metadata) ~= "table" then
		return { accepted = false, reason = "metadata_invalid" }
	end

	local endReason = metadata.endReason
	if type(endReason) ~= "string" then
		return { accepted = false, reason = "end_reason_invalid" }
	end

	local eventKind = GiantLevelState.ResolveEventKindFromContainmentEnd(endReason)
	if eventKind == nil then
		return { accepted = false, reason = "end_reason_not_xp_eligible" }
	end

	local operationId = metadata.operationId
	if type(operationId) ~= "string" or operationId == "" then
		return { accepted = false, reason = "operation_id_invalid" }
	end

	return grantXpEvent({
		operationId = operationId,
		eventKind = eventKind,
		awardedAt = metadata.endedAt,
	})
end

local function recordWorksiteUpgrade(operationId: string, at: number): any
	return grantXpEvent({
		operationId = operationId,
		eventKind = GiantLevelConfig.EventKinds.WorksiteUpgrade,
		awardedAt = at,
	})
end

local function BuildPersistenceState(): any
	return GiantLevelState.SerializePersistenceState(levelState)
end

local function ApplyPersistenceState(raw: any): (boolean, string?)
	local applied = GiantLevelState.ApplyPersistenceState(raw)
	if applied.accepted ~= true then
		return false, applied.reason or "giant_level_apply_failed"
	end
	levelState = applied.state
	projectRealmOwnerAttributes()
	return true, nil
end

_G._GiantLevelService_QueryAPI = {
	GrantXpEvent = grantXpEvent,
	RecordCaptureSuccess = recordCaptureSuccess,
	RecordContainmentEnd = recordContainmentEnd,
	RecordWorksiteUpgrade = recordWorksiteUpgrade,
	BuildPersistenceState = BuildPersistenceState,
	ApplyPersistenceState = ApplyPersistenceState,
	GetXp = function(): number
		return levelState.xp
	end,
	GetLevel = function(): number
		return levelState.level
	end,
	GetXpToNextLevel = function(): number
		return GiantLevelState.ResolveXpToNextLevel(levelState.xp, levelState.level)
	end,
	ResetForTests = function()
		levelState = GiantLevelState.CreateEmptyState()
		projectRealmOwnerAttributes()
	end,
}

debugLog("GiantLevelService initialized")
