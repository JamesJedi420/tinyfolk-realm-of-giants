--!nocheck
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local TrophyConfig = require(Config:WaitForChild("TrophyConfig"))
local TrophyCasePresentation = require(GiantRealm:WaitForChild("TrophyCasePresentation"))
local TrophyState = require(GiantRealm:WaitForChild("TrophyState"))

local globalEnv: any = getfenv()

local trophyState = TrophyState.CreateEmptyState()

local function debugLog(message: string)
	print(string.format("[TrophyService] %s", message))
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

local function getGiantReputationQueryApi(): any?
	local queryApi = globalEnv._GiantReputationService_QueryAPI
	if type(queryApi) == "table" then
		return queryApi
	end
	if type(_G) == "table" and type((_G :: any)._GiantReputationService_QueryAPI) == "table" then
		return (_G :: any)._GiantReputationService_QueryAPI
	end
	return nil
end

local function recordReputationScore(input: any, trophyKind: string)
	local reputationApi = getGiantReputationQueryApi()
	if type(reputationApi) ~= "table" or type(reputationApi.RecordTrophyScore) ~= "function" then
		return
	end
	pcall(reputationApi.RecordTrophyScore, trophyKind, input.operationId, input.awardedAt)
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

local function buildReputationSnapshot(): any
	local reputationApi = getGiantReputationQueryApi()
	if type(reputationApi) ~= "table" then
		return {
			score = 0,
			rank = 1,
			rankTitle = "Unknown Giant",
			scoreToNextRank = 0,
		}
	end

	return {
		score = if type(reputationApi.GetScore) == "function" then reputationApi.GetScore() else 0,
		rank = if type(reputationApi.GetRank) == "function" then reputationApi.GetRank() else 1,
		rankTitle = if type(reputationApi.GetRankTitle) == "function"
			then reputationApi.GetRankTitle()
			else "Unknown Giant",
		scoreToNextRank = if type(reputationApi.GetScoreToNextRank) == "function"
			then reputationApi.GetScoreToNextRank()
			else 0,
	}
end

local function buildCaseModel(): any
	return TrophyCasePresentation.BuildCaseModel(
		trophyState.trophies,
		buildReputationSnapshot(),
		TrophyConfig.CaseDisplayMaxEntries
	)
end

local function projectMapSurfaces(caseModel: any, updatedAt: number)
	if type(caseModel) ~= "table" then
		return
	end

	local surfaceAttrs = TrophyConfig.MapSurfaceAttributes
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute(TrophyConfig.TrophyCaseSurfaceAttribute) == true then
			descendant:SetAttribute(surfaceAttrs.Header, caseModel.header)
			descendant:SetAttribute(surfaceAttrs.Summary, caseModel.body)
			descendant:SetAttribute(surfaceAttrs.Count, caseModel.count)
			descendant:SetAttribute(surfaceAttrs.UpdatedAt, updatedAt)
		end
	end
end

local function projectRealmOwnerAttributes()
	local ownerUserId = getRealmOwnerUserId()
	local caseModel = buildCaseModel()
	local updatedAt = os.clock()
	projectMapSurfaces(caseModel, updatedAt)

	if ownerUserId == nil then
		return
	end

	local owner = getPlayerByUserId(ownerUserId)
	if owner == nil then
		return
	end

	local attrs = TrophyConfig.StateAttributes
	owner:SetAttribute(attrs.Count, caseModel.count)
	owner:SetAttribute(attrs.CaseHeader, caseModel.header)
	owner:SetAttribute(attrs.CaseSummary, caseModel.body)
	owner:SetAttribute(attrs.CaseUpdatedAt, updatedAt)

	local latest = TrophyState.GetLatestRecord(trophyState)
	if latest == nil then
		owner:SetAttribute(attrs.LatestSummary, nil)
		owner:SetAttribute(attrs.LatestKind, nil)
		return
	end

	owner:SetAttribute(attrs.LatestSummary, latest.summary)
	owner:SetAttribute(attrs.LatestKind, latest.trophyKind)
end

local function refreshCaseDisplay()
	projectRealmOwnerAttributes()
end

local function getTrophyDisplayPolicyQueryApi(): any?
	local queryApi = globalEnv._TrophyDisplayPolicyService_QueryAPI
	if type(queryApi) == "table" then
		return queryApi
	end
	if type(_G) == "table" and type((_G :: any)._TrophyDisplayPolicyService_QueryAPI) == "table" then
		return (_G :: any)._TrophyDisplayPolicyService_QueryAPI
	end
	return nil
end

local function resolveTargetOptOutOfNameDisplay(targetUserId: number): boolean
	local policyApi = getTrophyDisplayPolicyQueryApi()
	if type(policyApi) ~= "table" or type(policyApi.GetOptOutForUserId) ~= "function" then
		return false
	end

	local ok, optOut = pcall(policyApi.GetOptOutForUserId, targetUserId)
	if not ok or type(optOut) ~= "boolean" then
		return true
	end

	return optOut
end

local function recordEvent(input: any): any
	if type(input) ~= "table" then
		return { accepted = false, reason = "input_invalid" }
	end

	if type(input.targetUserId) == "number" and input.optOutOfNameDisplay == nil then
		input = table.clone(input)
		input.optOutOfNameDisplay = resolveTargetOptOutOfNameDisplay(input.targetUserId)
	end

	local result = TrophyState.ApplyEvent(trophyState, input)
	if type(result) ~= "table" then
		return { accepted = false, reason = "apply_event_invalid" }
	end
	if result.accepted == true and type(result.state) == "table" then
		trophyState = result.state
		projectRealmOwnerAttributes()
		recordReputationScore(input, tostring(input.trophyKind))
		debugLog(
			string.format(
				"Recorded trophy kind=%s operationId=%s total=%d",
				tostring(input.trophyKind),
				tostring(input.operationId),
				#trophyState.trophies
			)
		)
	end
	return result
end

local function recordCaptureSuccess(custodianUserId: number, targetUserId: number, at: number): any
	return recordEvent({
		operationId = string.format("trophy-capture-%d-%d-%d", custodianUserId, targetUserId, math.floor(at * 1000)),
		trophyKind = TrophyConfig.Kinds.CaptureSuccess,
		awardedAt = at,
		custodianUserId = custodianUserId,
		targetUserId = targetUserId,
	})
end

local function recordRaidDefenseWin(custodianUserId: number, targetUserId: number, trapId: string, at: number): any
	if type(trapId) ~= "string" or trapId == "" then
		return { accepted = false, reason = "trap_id_invalid" }
	end
	return recordEvent({
		operationId = string.format("trophy-raid-defense-%s-%d-%d", trapId, targetUserId, math.floor(at * 1000)),
		trophyKind = TrophyConfig.Kinds.RaidDefenseWin,
		awardedAt = at,
		custodianUserId = custodianUserId,
		targetUserId = targetUserId,
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

	local trophyKind = TrophyState.ResolveKindFromContainmentEnd(endReason)
	if trophyKind == nil then
		return { accepted = false, reason = "end_reason_not_trophy_eligible" }
	end

	local operationId = metadata.operationId
	if type(operationId) ~= "string" or operationId == "" then
		return { accepted = false, reason = "operation_id_invalid" }
	end

	return recordEvent({
		operationId = operationId,
		trophyKind = trophyKind,
		awardedAt = metadata.endedAt,
		custodianUserId = metadata.custodianUserId,
		targetUserId = metadata.targetUserId,
		endReason = endReason,
		heldSeconds = metadata.heldSeconds,
	})
end

local function BuildPersistenceState(): any
	return TrophyState.SerializePersistenceState(trophyState)
end

local function ApplyPersistenceState(raw: any): (boolean, string?)
	local applied = TrophyState.ApplyPersistenceState(raw)
	if applied.accepted ~= true then
		return false, applied.reason or "trophy_apply_failed"
	end
	trophyState = applied.state
	projectRealmOwnerAttributes()
	return true, nil
end

_G._TrophyService_QueryAPI = {
	RecordEvent = recordEvent,
	RecordCaptureSuccess = recordCaptureSuccess,
	RecordRaidDefenseWin = recordRaidDefenseWin,
	RecordContainmentEnd = recordContainmentEnd,
	BuildPersistenceState = BuildPersistenceState,
	ApplyPersistenceState = ApplyPersistenceState,
	GetTrophyCount = function(): number
		return #trophyState.trophies
	end,
	GetLatestRecord = function(): any
		return TrophyState.GetLatestRecord(trophyState)
	end,
	GetCaseModel = function(): any
		return buildCaseModel()
	end,
	RefreshCaseDisplay = refreshCaseDisplay,
	ResetForTests = function()
		trophyState = TrophyState.CreateEmptyState()
		projectRealmOwnerAttributes()
	end,
}

debugLog("TrophyService initialized")
