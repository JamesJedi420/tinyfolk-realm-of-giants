--!nocheck
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local GiantLevelConfig = require(Config:WaitForChild("GiantLevelConfig"))
local GiantLevelState = require(GiantRealm:WaitForChild("GiantLevelState"))
local GiantLevelCrossRealmSyncState = require(GiantRealm:WaitForChild("GiantLevelCrossRealmSyncState"))
local RealmTransferState = require(GiantRealm:WaitForChild("RealmTransferState"))
local MemoryStoreStructurePolicy = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("MemoryStoreStructurePolicy"))
	else (require :: any)("./MemoryStoreStructurePolicy")
local GiantLevelPendingXpStore = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("GiantLevelPendingXpStore"))
	else (require :: any)("./GiantLevelPendingXpStore")

local globalEnv: any = getfenv()

local levelState = GiantLevelState.CreateEmptyState()
local levelUpSignalCounter = 0
local pendingXpStore: any = nil

local function debugLog(message: string)
	print(string.format("[GiantLevelService] %s", message))
end

local function getPendingXpStore(): any
	if pendingXpStore ~= nil then
		return pendingXpStore
	end
	pendingXpStore = GiantLevelPendingXpStore.Create({
		syncState = GiantLevelCrossRealmSyncState,
		structurePolicy = MemoryStoreStructurePolicy,
	})
	return pendingXpStore
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

local function getActiveRealmId(): string?
	local ownerUserId = getRealmOwnerUserId()
	if ownerUserId == nil then
		return nil
	end
	return RealmTransferState.FormatRealmId(ownerUserId)
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

local function publishPendingXpEvent(realmId: string?, record: any, at: number)
	if type(realmId) ~= "string" or realmId == "" or type(record) ~= "table" then
		return
	end

	local store = getPendingXpStore()
	local updateResult = store.UpdatePendingBuffer(realmId, function(currentBuffer: any?)
		local nextBuffer, appendReason =
			GiantLevelCrossRealmSyncState.AppendPendingEvent(currentBuffer, record, at, realmId)
		if nextBuffer == nil then
			return {
				accepted = false,
				reason = appendReason or "pending_append_failed",
				pendingBuffer = currentBuffer,
			}
		end
		if appendReason == "duplicate" then
			return {
				accepted = true,
				reason = "duplicate",
				pendingBuffer = nextBuffer,
			}
		end
		return {
			accepted = true,
			reason = "accepted",
			pendingBuffer = nextBuffer,
		}
	end)
	if type(updateResult) ~= "table" or updateResult.accepted ~= true then
		debugLog(
			string.format(
				"Pending XP publish failed realmId=%s operationId=%s reason=%s",
				realmId,
				tostring(record.operationId),
				tostring(if type(updateResult) == "table" then updateResult.reason else "unknown")
			)
		)
	end
end

local function ackPendingXpEvents(realmId: string?, persistenceRaw: any, at: number)
	if type(realmId) ~= "string" or realmId == "" then
		return
	end

	local acknowledgedOperationIds = GiantLevelCrossRealmSyncState.CollectAcknowledgedOperationIds(persistenceRaw)
	if next(acknowledgedOperationIds) == nil then
		return
	end

	local store = getPendingXpStore()
	store.UpdatePendingBuffer(realmId, function(currentBuffer: any?)
		local nextBuffer =
			GiantLevelCrossRealmSyncState.PruneAcknowledgedOperationIds(currentBuffer, acknowledgedOperationIds, at)
		return {
			accepted = true,
			reason = "accepted",
			pendingBuffer = nextBuffer,
		}
	end)
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

		if type(result.record) == "table" then
			local realmId = getActiveRealmId()
			local awardedAt = if type(input.awardedAt) == "number" then input.awardedAt else os.time()
			publishPendingXpEvent(realmId, result.record, awardedAt)
		end

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

local function buildTradeOperationId(baseOperationId: string, role: string, realmOwnerUserId: number): string
	return string.format("trade-%s-%s-%d", role, baseOperationId, realmOwnerUserId)
end

local function recordTradeSuccess(input: any): any
	if type(input) ~= "table" then
		return { accepted = false, reason = "trade_input_invalid" }
	end

	local baseOperationId = input.operationId
	if type(baseOperationId) ~= "string" or baseOperationId == "" then
		return { accepted = false, reason = "operation_id_invalid" }
	end

	local sourceRealmOwnerUserId = input.sourceRealmOwnerUserId
	local destinationRealmOwnerUserId = input.destinationRealmOwnerUserId
	if type(sourceRealmOwnerUserId) ~= "number" or sourceRealmOwnerUserId <= 0 then
		return { accepted = false, reason = "source_owner_invalid" }
	end
	if type(destinationRealmOwnerUserId) ~= "number" or destinationRealmOwnerUserId <= 0 then
		return { accepted = false, reason = "destination_owner_invalid" }
	end

	local awardedAt = if type(input.awardedAt) == "number" then input.awardedAt else os.time()
	local sourceRealmId = if type(input.sourceRealmId) == "string"
		then input.sourceRealmId
		else RealmTransferState.FormatRealmId(sourceRealmOwnerUserId)
	local destinationRealmId = if type(input.destinationRealmId) == "string"
		then input.destinationRealmId
		else RealmTransferState.FormatRealmId(destinationRealmOwnerUserId)

	local activeOwnerUserId = getRealmOwnerUserId()
	local destinationResult = nil
	local sourceResult = nil

	if activeOwnerUserId == destinationRealmOwnerUserId then
		destinationResult = grantXpEvent({
			operationId = buildTradeOperationId(baseOperationId, "dest", destinationRealmOwnerUserId),
			eventKind = GiantLevelConfig.EventKinds.TradeSuccess,
			awardedAt = awardedAt,
		})
	end

	if activeOwnerUserId == sourceRealmOwnerUserId then
		sourceResult = grantXpEvent({
			operationId = buildTradeOperationId(baseOperationId, "source", sourceRealmOwnerUserId),
			eventKind = GiantLevelConfig.EventKinds.TradeSuccess,
			awardedAt = awardedAt,
		})
	end

	local pendingDestinationRecord = {
		operationId = buildTradeOperationId(baseOperationId, "dest", destinationRealmOwnerUserId),
		eventKind = GiantLevelConfig.EventKinds.TradeSuccess,
		xpAwarded = GiantLevelState.ResolveXpAward(GiantLevelConfig.EventKinds.TradeSuccess),
		awardedAt = awardedAt,
	}
	local pendingSourceRecord = {
		operationId = buildTradeOperationId(baseOperationId, "source", sourceRealmOwnerUserId),
		eventKind = GiantLevelConfig.EventKinds.TradeSuccess,
		xpAwarded = GiantLevelState.ResolveXpAward(GiantLevelConfig.EventKinds.TradeSuccess),
		awardedAt = awardedAt,
	}

	if type(pendingDestinationRecord.xpAwarded) == "number" and activeOwnerUserId ~= destinationRealmOwnerUserId then
		publishPendingXpEvent(destinationRealmId, pendingDestinationRecord, awardedAt)
	end
	if type(pendingSourceRecord.xpAwarded) == "number" and activeOwnerUserId ~= sourceRealmOwnerUserId then
		publishPendingXpEvent(sourceRealmId, pendingSourceRecord, awardedAt)
	end

	local grantedLocally = (type(destinationResult) == "table" and destinationResult.accepted == true)
		or (type(sourceResult) == "table" and sourceResult.accepted == true)
	local publishedRemote = activeOwnerUserId ~= destinationRealmOwnerUserId
		or activeOwnerUserId ~= sourceRealmOwnerUserId

	return {
		accepted = grantedLocally or publishedRemote,
		reason = if grantedLocally or publishedRemote then "accepted" else "trade_xp_not_applied",
		destinationResult = destinationResult,
		sourceResult = sourceResult,
	}
end

local function BuildPersistenceState(): any
	local persistence = GiantLevelState.SerializePersistenceState(levelState)
	local realmId = getActiveRealmId()
	if realmId ~= nil then
		ackPendingXpEvents(realmId, persistence, os.time())
	end
	return persistence
end

local function ApplyPersistenceState(raw: any): (boolean, string?)
	local realmId = getActiveRealmId()
	local pendingBuffer = nil
	if realmId ~= nil then
		local pendingResult = getPendingXpStore().GetPendingBuffer(realmId)
		if type(pendingResult) == "table" and pendingResult.accepted == true then
			pendingBuffer = pendingResult.pendingBuffer
		end
	end

	local applied = GiantLevelCrossRealmSyncState.MergePersistenceWithPending(raw, pendingBuffer)
	if applied.accepted ~= true then
		local fallback = GiantLevelState.ApplyPersistenceState(raw)
		if fallback.accepted ~= true then
			return false, fallback.reason or applied.reason or "giant_level_apply_failed"
		end
		applied = fallback
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
	RecordTradeSuccess = recordTradeSuccess,
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
		if pendingXpStore ~= nil and type(pendingXpStore.ResetForTests) == "function" then
			pendingXpStore.ResetForTests()
		end
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
