--!nocheck
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local GiantLevelConfig = require(Config:WaitForChild("GiantLevelConfig"))
local GiantLevelState = require(GiantRealm:WaitForChild("GiantLevelState"))

local globalEnv: any = getfenv()

local levelState = GiantLevelState.CreateEmptyState()
local levelUpSignalCounter = 0

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

local function getModifierSnapshot(): any
	return GiantLevelState.ResolveModifierSnapshot(levelState)
end

local function projectRealmOwnerAttributes(levelUpPayload: any?)
	local ownerUserId = getRealmOwnerUserId()
	if ownerUserId == nil then
		return
	end

	local owner = getPlayerByUserId(ownerUserId)
	if owner == nil then
		return
	end

	local attrs = GiantLevelConfig.StateAttributes
	local modifierSnapshot = getModifierSnapshot()
	owner:SetAttribute(attrs.Xp, levelState.xp)
	owner:SetAttribute(attrs.Level, levelState.level)
	owner:SetAttribute(attrs.XpToNextLevel, GiantLevelState.ResolveXpToNextLevel(levelState.xp, levelState.level))
	owner:SetAttribute(attrs.ResolvedUnlockCount, #modifierSnapshot.resolvedUnlockIds)
	owner:SetAttribute(attrs.XpAwardMultiplier, modifierSnapshot.xpAwardMultiplier)
	owner:SetAttribute(attrs.ContainmentRewardMultiplier, modifierSnapshot.containmentRewardMultiplier)

	if type(levelUpPayload) == "table" and type(levelUpPayload.newLevel) == "number" then
		levelUpSignalCounter += 1
		owner:SetAttribute(attrs.LevelUpSignal, levelUpSignalCounter)
		owner:SetAttribute(attrs.LastLevelUpLevel, math.floor(levelUpPayload.newLevel))
	end
end

local function resolveUnlocksForLevelRange(fromLevel: number, toLevel: number): any
	local unlockResult = GiantLevelState.ResolveLevelUnlocks(levelState, fromLevel, toLevel)
	if type(unlockResult) ~= "table" or type(unlockResult.state) ~= "table" then
		return { accepted = false, reason = "unlock_resolution_invalid", newlyResolved = {} }
	end
	levelState = unlockResult.state
	return unlockResult
end

local function grantXpEvent(input: any): any
	local result = GiantLevelState.ApplyXpEvent(levelState, input)
	if type(result) ~= "table" then
		return { accepted = false, reason = "apply_xp_event_invalid" }
	end
	if result.accepted == true and type(result.state) == "table" then
		levelState = result.state
		local levelUpPayload = nil
		if
			result.leveledUp == true
			and type(result.previousLevel) == "number"
			and type(result.newLevel) == "number"
		then
			local unlockResult = resolveUnlocksForLevelRange(result.previousLevel + 1, result.newLevel)
			levelUpPayload = {
				newLevel = result.newLevel,
				newlyResolved = if type(unlockResult) == "table" then unlockResult.newlyResolved else {},
			}
			debugLog(
				string.format(
					"Level up previous=%d new=%d unlocks=%d",
					result.previousLevel,
					result.newLevel,
					if type(unlockResult) == "table" and type(unlockResult.newlyResolved) == "table"
						then #unlockResult.newlyResolved
						else 0
				)
			)
		end
		projectRealmOwnerAttributes(levelUpPayload)
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
	if applied.needsEntitlementReconcile == true then
		local reconcileResult = GiantLevelState.ReconcileEntitledUnlocks(levelState)
		if type(reconcileResult) == "table" and type(reconcileResult.state) == "table" then
			levelState = reconcileResult.state
		end
	end
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
	GetModifierSnapshot = getModifierSnapshot,
	GetResolvedUnlockIds = function(): { string }
		return getModifierSnapshot().resolvedUnlockIds
	end,
	ResetForTests = function()
		levelState = GiantLevelState.CreateEmptyState()
		levelUpSignalCounter = 0
		projectRealmOwnerAttributes()
		local ownerUserId = getRealmOwnerUserId()
		if ownerUserId ~= nil then
			local owner = getPlayerByUserId(ownerUserId)
			if owner ~= nil then
				local attrs = GiantLevelConfig.StateAttributes
				owner:SetAttribute(attrs.LevelUpSignal, nil)
				owner:SetAttribute(attrs.LastLevelUpLevel, nil)
			end
		end
	end,
}

debugLog("GiantLevelService initialized")
