--!nocheck
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local GiantReputationConfig = require(Config:WaitForChild("GiantReputationConfig"))
local GiantReputationState = require(GiantRealm:WaitForChild("GiantReputationState"))

local globalEnv: any = getfenv()

local reputationState = GiantReputationState.CreateEmptyState()
local rankUpSignalCounter = 0

local function debugLog(message: string)
	print(string.format("[GiantReputationService] %s", message))
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

local function refreshTrophyCaseDisplay()
	local trophyApi = globalEnv._TrophyService_QueryAPI
	if type(trophyApi) == "table" and type(trophyApi.RefreshCaseDisplay) == "function" then
		pcall(trophyApi.RefreshCaseDisplay)
	end
end

local function projectRealmOwnerAttributes(rankUpPayload: any?)
	local ownerUserId = getRealmOwnerUserId()
	if ownerUserId == nil then
		return
	end

	local owner = getPlayerByUserId(ownerUserId)
	if owner == nil then
		return
	end

	local attrs = GiantReputationConfig.StateAttributes
	owner:SetAttribute(attrs.Score, reputationState.score)
	owner:SetAttribute(attrs.Rank, reputationState.rank)
	owner:SetAttribute(attrs.RankTitle, GiantReputationState.ResolveRankTitle(reputationState.rank))
	owner:SetAttribute(
		attrs.ScoreToNextRank,
		GiantReputationState.ResolveScoreToNextRank(reputationState.score, reputationState.rank)
	)

	if type(rankUpPayload) == "table" and type(rankUpPayload.newRank) == "number" then
		rankUpSignalCounter += 1
		owner:SetAttribute(attrs.RankUpSignal, rankUpSignalCounter)
	end

	refreshTrophyCaseDisplay()
end

local function grantScoreEvent(input: any): any
	local result = GiantReputationState.ApplyScoreEvent(reputationState, input)
	if type(result) ~= "table" then
		return { accepted = false, reason = "apply_score_event_invalid" }
	end
	if result.accepted == true and type(result.state) == "table" then
		reputationState = result.state
		local rankUpPayload = nil
		if result.rankedUp == true and type(result.newRank) == "number" then
			rankUpPayload = { newRank = result.newRank }
			debugLog(
				string.format(
					"Rank up previous=%d new=%d title=%s",
					result.previousRank,
					result.newRank,
					GiantReputationState.ResolveRankTitle(result.newRank)
				)
			)
		end
		projectRealmOwnerAttributes(rankUpPayload)
		debugLog(
			string.format(
				"Granted reputation kind=%s operationId=%s score=%d rank=%d",
				tostring(input.trophyKind),
				tostring(input.operationId),
				reputationState.score,
				reputationState.rank
			)
		)
	end
	return result
end

local function recordTrophyScore(trophyKind: string, operationId: string, awardedAt: number): any
	return grantScoreEvent({
		operationId = operationId,
		trophyKind = trophyKind,
		awardedAt = awardedAt,
	})
end

local function BuildPersistenceState(): any
	return GiantReputationState.SerializePersistenceState(reputationState)
end

local function ApplyPersistenceState(raw: any): (boolean, string?)
	local applied = GiantReputationState.ApplyPersistenceState(raw)
	if applied.accepted ~= true then
		return false, applied.reason or "giant_reputation_apply_failed"
	end
	reputationState = applied.state
	projectRealmOwnerAttributes()
	return true, nil
end

_G._GiantReputationService_QueryAPI = {
	GrantScoreEvent = grantScoreEvent,
	RecordTrophyScore = recordTrophyScore,
	BuildPersistenceState = BuildPersistenceState,
	ApplyPersistenceState = ApplyPersistenceState,
	GetScore = function(): number
		return reputationState.score
	end,
	GetRank = function(): number
		return reputationState.rank
	end,
	GetRankTitle = function(): string
		return GiantReputationState.ResolveRankTitle(reputationState.rank)
	end,
	GetScoreToNextRank = function(): number
		return GiantReputationState.ResolveScoreToNextRank(reputationState.score, reputationState.rank)
	end,
	ResetForTests = function()
		reputationState = GiantReputationState.CreateEmptyState()
		rankUpSignalCounter = 0
		projectRealmOwnerAttributes()
	end,
}

debugLog("GiantReputationService initialized")
