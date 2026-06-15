--!strict

local RealmTradeConversionConfig = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("Config")
			:WaitForChild("RealmTradeConversionConfig")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/Config/RealmTradeConversionConfig")

local RealmTradeConversionState = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("RealmTradeConversionState")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/RealmTradeConversionState")

local RealmTradeConversionCrossRealmSyncState = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("RealmTradeConversionCrossRealmSyncState")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/RealmTradeConversionCrossRealmSyncState")

local RealmTransferState = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("RealmTransferState")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/RealmTransferState")

local MemoryStoreStructurePolicy = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("MemoryStoreStructurePolicy"))
	else (require :: any)("./MemoryStoreStructurePolicy")

local RealmTradeConversionPendingStore = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("RealmTradeConversionPendingStore"))
	else (require :: any)("./RealmTradeConversionPendingStore")

local RealmTradeConversionService: any = {}
local globalEnv: any = getfenv()

local sessionLedgerByRealmOwnerUserId: { [number]: any } = {}
local lastConversionSnapshot: any? = nil
local pendingConversionStore: any = nil

local function isPositiveInteger(value: any): boolean
	if type(value) ~= "number" or value <= 0 or value % 1 ~= 0 then
		return false
	end
	return true
end

local function getPendingConversionStore(): any
	if pendingConversionStore ~= nil then
		return pendingConversionStore
	end
	pendingConversionStore = RealmTradeConversionPendingStore.Create({
		syncState = RealmTradeConversionCrossRealmSyncState,
		structurePolicy = MemoryStoreStructurePolicy,
	})
	return pendingConversionStore
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

local function getActiveRealmOwnerUserId(): number?
	local buildModeApi = getGiantBuildModeQueryApi()
	if type(buildModeApi) ~= "table" or type(buildModeApi.GetRealmOwnerUserId) ~= "function" then
		return nil
	end
	local ownerUserId = buildModeApi.GetRealmOwnerUserId()
	if isPositiveInteger(ownerUserId) then
		return math.floor(ownerUserId)
	end
	return nil
end

local function getPlayerByUserId(userId: number): any?
	if game == nil or type(game.GetService) ~= "function" then
		return nil
	end
	local ok, playersService = pcall(function()
		return game:GetService("Players")
	end)
	if not ok or type(playersService) ~= "table" or type(playersService.GetPlayers) ~= "function" then
		return nil
	end
	for _, player in playersService:GetPlayers() do
		if type(player) == "table" and player.UserId == userId then
			return player
		end
	end
	return nil
end

local function ensureSessionLedger(realmOwnerUserId: number): any
	local ledger = sessionLedgerByRealmOwnerUserId[realmOwnerUserId]
	if type(ledger) ~= "table" then
		ledger = RealmTradeConversionState.CreateEmptySessionLedger()
		sessionLedgerByRealmOwnerUserId[realmOwnerUserId] = ledger
	end
	return ledger
end

local function projectDebugAttributes(realmOwnerUserId: number, conversion: any?)
	local owner = getPlayerByUserId(realmOwnerUserId)
	if owner == nil or type(owner.SetAttribute) ~= "function" then
		return
	end

	local attrs = RealmTradeConversionConfig.DebugAttributes
	local ledger = ensureSessionLedger(realmOwnerUserId)
	owner:SetAttribute(attrs.SessionEssence, ledger.essence)
	owner:SetAttribute(attrs.SessionWood, ledger.wood)
	owner:SetAttribute(attrs.SessionStone, ledger.stone)
	owner:SetAttribute(attrs.UpdatedAt, os.time())

	if type(conversion) ~= "table" then
		return
	end

	owner:SetAttribute(attrs.LastOperationId, conversion.operationId)
	owner:SetAttribute(attrs.LastRole, conversion.role)
	owner:SetAttribute(attrs.LastEssence, conversion.essence)
	owner:SetAttribute(attrs.LastWood, conversion.wood)
	owner:SetAttribute(attrs.LastStone, conversion.stone)
end

local function ackPendingConversionEvents(realmId: string?, sessionLedger: any, at: number)
	if type(realmId) ~= "string" or realmId == "" then
		return
	end

	local acknowledgedOperationIds =
		RealmTradeConversionCrossRealmSyncState.CollectAcknowledgedOperationIds(sessionLedger)
	if next(acknowledgedOperationIds) == nil then
		return
	end

	getPendingConversionStore().UpdatePendingBuffer(realmId, function(currentBuffer: any?)
		local nextBuffer = RealmTradeConversionCrossRealmSyncState.PruneAcknowledgedOperationIds(
			currentBuffer,
			acknowledgedOperationIds,
			at
		)
		return {
			accepted = true,
			reason = "accepted",
			pendingBuffer = nextBuffer,
		}
	end)
end

local function publishPendingConversionEvent(realmId: string?, record: any, at: number)
	if type(realmId) ~= "string" or realmId == "" or type(record) ~= "table" then
		return
	end

	local updateResult = getPendingConversionStore().UpdatePendingBuffer(realmId, function(currentBuffer: any?)
		local nextBuffer, appendReason =
			RealmTradeConversionCrossRealmSyncState.AppendPendingConversion(currentBuffer, record, at, realmId)
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
		print(
			string.format(
				"[RealmTradeConversionService] Pending conversion publish failed realmId=%s operationId=%s reason=%s",
				realmId,
				tostring(record.operationId),
				tostring(if type(updateResult) == "table" then updateResult.reason else "unknown")
			)
		)
	end
end

local function buildPendingConversionRecord(
	role: string,
	baseOperationId: string,
	realmOwnerUserId: number,
	counterpartyUserId: number?,
	convertedAt: number
): any?
	local operationId = RealmTradeConversionState.BuildOperationId(baseOperationId, role, realmOwnerUserId)
	local amounts = RealmTradeConversionState.ResolveAwardAmounts(role)
	if amounts.accepted ~= true then
		return nil
	end
	return {
		operationId = operationId,
		role = role,
		realmOwnerUserId = realmOwnerUserId,
		counterpartyUserId = counterpartyUserId,
		convertedAt = convertedAt,
		essence = amounts.essence,
		wood = amounts.wood,
		stone = amounts.stone,
	}
end

local function applyLocalConversion(
	realmOwnerUserId: number,
	role: string,
	baseOperationId: string,
	counterpartyUserId: number?,
	convertedAt: number
): any
	local operationId = RealmTradeConversionState.BuildOperationId(baseOperationId, role, realmOwnerUserId)
	local ledger = ensureSessionLedger(realmOwnerUserId)
	local applyResult = RealmTradeConversionState.ApplyConversion(ledger, {
		operationId = operationId,
		role = role,
		realmOwnerUserId = realmOwnerUserId,
		counterpartyUserId = counterpartyUserId,
		convertedAt = convertedAt,
	})
	if type(applyResult) ~= "table" then
		return { accepted = false, reason = "conversion_apply_invalid", operationId = operationId, role = role }
	end
	if applyResult.accepted == true and type(applyResult.ledger) == "table" then
		sessionLedgerByRealmOwnerUserId[realmOwnerUserId] = applyResult.ledger
		local realmId = RealmTransferState.FormatRealmId(realmOwnerUserId)
		ackPendingConversionEvents(realmId, applyResult.ledger, convertedAt)
	end
	if applyResult.accepted == true and applyResult.duplicate ~= true and type(applyResult.conversion) == "table" then
		lastConversionSnapshot = applyResult.conversion
		projectDebugAttributes(realmOwnerUserId, applyResult.conversion)
	end
	return {
		accepted = applyResult.accepted == true,
		reason = applyResult.reason,
		duplicate = applyResult.duplicate == true,
		operationId = operationId,
		role = role,
		conversion = applyResult.conversion,
	}
end

local function mergePendingConversionsForOwner(realmOwnerUserId: number): any
	local realmId = RealmTransferState.FormatRealmId(realmOwnerUserId)
	local pendingResult = getPendingConversionStore().GetPendingBuffer(realmId)
	local pendingBuffer = if type(pendingResult) == "table" and pendingResult.accepted == true
		then pendingResult.pendingBuffer
		else nil

	local ledger = ensureSessionLedger(realmOwnerUserId)
	local merged = RealmTradeConversionCrossRealmSyncState.MergeSessionLedgerWithPending(ledger, pendingBuffer)
	if type(merged) ~= "table" or merged.accepted ~= true or type(merged.ledger) ~= "table" then
		return {
			accepted = false,
			reason = if type(merged) == "table" then merged.reason else "merge_failed",
		}
	end

	sessionLedgerByRealmOwnerUserId[realmOwnerUserId] = merged.ledger
	ackPendingConversionEvents(realmId, merged.ledger, os.time())
	projectDebugAttributes(realmOwnerUserId, nil)
	return {
		accepted = true,
		reason = "accepted",
		ledger = merged.ledger,
	}
end

function RealmTradeConversionService.MergePendingConversions(realmOwnerUserId: any): any
	if not isPositiveInteger(realmOwnerUserId) then
		return { accepted = false, reason = "realm_owner_invalid" }
	end
	return mergePendingConversionsForOwner(math.floor(realmOwnerUserId))
end

function RealmTradeConversionService.RecordTradeSuccess(input: any): any
	if type(input) ~= "table" then
		return { accepted = false, reason = "trade_input_invalid" }
	end

	local baseOperationId = input.operationId
	if type(baseOperationId) ~= "string" or baseOperationId == "" then
		return { accepted = false, reason = "operation_id_invalid" }
	end

	local sourceRealmOwnerUserId = input.sourceRealmOwnerUserId
	local destinationRealmOwnerUserId = input.destinationRealmOwnerUserId
	if not isPositiveInteger(sourceRealmOwnerUserId) then
		return { accepted = false, reason = "source_owner_invalid" }
	end
	if not isPositiveInteger(destinationRealmOwnerUserId) then
		return { accepted = false, reason = "destination_owner_invalid" }
	end

	sourceRealmOwnerUserId = math.floor(sourceRealmOwnerUserId)
	destinationRealmOwnerUserId = math.floor(destinationRealmOwnerUserId)
	local convertedAt = if type(input.convertedAt) == "number" then input.convertedAt else os.time()
	local activeOwnerUserId = getActiveRealmOwnerUserId()

	if activeOwnerUserId == destinationRealmOwnerUserId then
		mergePendingConversionsForOwner(destinationRealmOwnerUserId)
	end
	if activeOwnerUserId == sourceRealmOwnerUserId then
		mergePendingConversionsForOwner(sourceRealmOwnerUserId)
	end

	local sourceRealmId = if type(input.sourceRealmId) == "string"
		then input.sourceRealmId
		else RealmTransferState.FormatRealmId(sourceRealmOwnerUserId)
	local destinationRealmId = if type(input.destinationRealmId) == "string"
		then input.destinationRealmId
		else RealmTransferState.FormatRealmId(destinationRealmOwnerUserId)

	local destinationResult = nil
	local sourceResult = nil
	if activeOwnerUserId == destinationRealmOwnerUserId then
		destinationResult = applyLocalConversion(
			destinationRealmOwnerUserId,
			RealmTradeConversionConfig.Roles.Destination,
			baseOperationId,
			sourceRealmOwnerUserId,
			convertedAt
		)
	end
	if activeOwnerUserId == sourceRealmOwnerUserId then
		sourceResult = applyLocalConversion(
			sourceRealmOwnerUserId,
			RealmTradeConversionConfig.Roles.Source,
			baseOperationId,
			destinationRealmOwnerUserId,
			convertedAt
		)
	end

	local pendingDestinationRecord = buildPendingConversionRecord(
		RealmTradeConversionConfig.Roles.Destination,
		baseOperationId,
		destinationRealmOwnerUserId,
		sourceRealmOwnerUserId,
		convertedAt
	)
	local pendingSourceRecord = buildPendingConversionRecord(
		RealmTradeConversionConfig.Roles.Source,
		baseOperationId,
		sourceRealmOwnerUserId,
		destinationRealmOwnerUserId,
		convertedAt
	)

	if type(pendingDestinationRecord) == "table" and activeOwnerUserId ~= destinationRealmOwnerUserId then
		publishPendingConversionEvent(destinationRealmId, pendingDestinationRecord, convertedAt)
	end
	if type(pendingSourceRecord) == "table" and activeOwnerUserId ~= sourceRealmOwnerUserId then
		publishPendingConversionEvent(sourceRealmId, pendingSourceRecord, convertedAt)
	end

	local appliedLocally = (type(destinationResult) == "table" and destinationResult.accepted == true)
		or (type(sourceResult) == "table" and sourceResult.accepted == true)
	local publishedRemote = activeOwnerUserId ~= destinationRealmOwnerUserId
		or activeOwnerUserId ~= sourceRealmOwnerUserId

	return {
		accepted = appliedLocally or publishedRemote,
		reason = if appliedLocally or publishedRemote then "accepted" else "trade_conversion_not_applied",
		destinationResult = destinationResult,
		sourceResult = sourceResult,
		sourceRealmId = sourceRealmId,
		destinationRealmId = destinationRealmId,
	}
end

function RealmTradeConversionService.GetLastConversionSnapshot(): any?
	return lastConversionSnapshot
end

function RealmTradeConversionService.GetSessionLedgerSnapshot(realmOwnerUserId: any): any
	if not isPositiveInteger(realmOwnerUserId) then
		return { accepted = false, reason = "realm_owner_invalid" }
	end

	local ownerUserId = math.floor(realmOwnerUserId)
	local activeOwnerUserId = getActiveRealmOwnerUserId()
	if activeOwnerUserId == ownerUserId then
		mergePendingConversionsForOwner(ownerUserId)
	end

	local ledger = ensureSessionLedger(ownerUserId)
	return {
		accepted = true,
		reason = "accepted",
		ledger = {
			essence = ledger.essence,
			wood = ledger.wood,
			stone = ledger.stone,
			recentConversionCount = if type(ledger.recentConversions) == "table" then #ledger.recentConversions else 0,
		},
	}
end

function RealmTradeConversionService.ResetForTests()
	sessionLedgerByRealmOwnerUserId = {}
	lastConversionSnapshot = nil
	if pendingConversionStore ~= nil and type(pendingConversionStore.ResetForTests) == "function" then
		pendingConversionStore.ResetForTests()
	end
end

globalEnv._RealmTradeConversionService_QueryAPI = {
	RecordTradeSuccess = function(input: any): any
		return RealmTradeConversionService.RecordTradeSuccess(input)
	end,
	MergePendingConversions = function(realmOwnerUserId: any): any
		return RealmTradeConversionService.MergePendingConversions(realmOwnerUserId)
	end,
	GetLastConversionSnapshot = function(): any?
		return RealmTradeConversionService.GetLastConversionSnapshot()
	end,
	GetSessionLedgerSnapshot = function(realmOwnerUserId: any): any
		return RealmTradeConversionService.GetSessionLedgerSnapshot(realmOwnerUserId)
	end,
	ResetForTests = function()
		RealmTradeConversionService.ResetForTests()
	end,
}

return RealmTradeConversionService
