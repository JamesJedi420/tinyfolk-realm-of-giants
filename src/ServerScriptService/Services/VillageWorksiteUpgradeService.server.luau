--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local ShrineConfig = require(Config:WaitForChild("ShrineConfig"))
local StationConfig = require(Config:WaitForChild("StationConfig"))
local VillageWorksiteUpgradeConfig = require(Config:WaitForChild("VillageWorksiteUpgradeConfig"))
local VillageWorksiteUpgradeState = require(GiantRealm:WaitForChild("VillageWorksiteUpgradeState"))

local REMOTES_FOLDER_NAME = "Remotes"
local REQUEST_REMOTE_NAME = "VillageWorksiteUpgradeRequest"
local RESPONSE_REMOTE_NAME = "VillageWorksiteUpgradeResponse"

local ROLE_ATTRIBUTE = "Role"
local globalEnv: any = getfenv()

local upgradeState = VillageWorksiteUpgradeState.CreateEmptyState()
local lastRequestAtByUserId: { [number]: number? } = {}

local function now(): number
	return os.clock()
end

local function debugLog(message: string)
	print(string.format("[VillageWorksiteUpgradeService] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[VillageWorksiteUpgradeService] %s", message))
end

local function ensureRemotesFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = REMOTES_FOLDER_NAME
	folder.Parent = ReplicatedStorage
	return folder
end

local function ensureRemoteEvent(parentFolder: Folder, remoteName: string): RemoteEvent
	local existing = parentFolder:FindFirstChild(remoteName)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = remoteName
	remote.Parent = parentFolder
	return remote
end

local function isCoolingDown(userId: number, at: number): boolean
	local last = lastRequestAtByUserId[userId]
	if last == nil then
		return false
	end
	return (at - last) < VillageWorksiteUpgradeConfig.RequestCooldownSeconds
end

local function getUpgradeBoardQueryApi(): any?
	local queryApi = globalEnv._UpgradeBoardService_QueryAPI
	if type(queryApi) == "table" then
		return queryApi
	end
	if type(_G) == "table" and type((_G :: any)._UpgradeBoardService_QueryAPI) == "table" then
		return (_G :: any)._UpgradeBoardService_QueryAPI
	end
	return nil
end

local function refreshGiantEffectsForRealmOwner(ownerUserId: number?, reason: string)
	if type(ownerUserId) ~= "number" then
		return
	end
	local boardApi = getUpgradeBoardQueryApi()
	if type(boardApi) == "table" and type(boardApi.RefreshGiantEffectsForUser) == "function" then
		boardApi.RefreshGiantEffectsForUser(ownerUserId, reason)
	end
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
	local buildApi = getGiantBuildModeQueryApi()
	if type(buildApi) ~= "table" or type(buildApi.GetRealmOwnerUserId) ~= "function" then
		return nil
	end
	return buildApi.GetRealmOwnerUserId()
end

local function spendUpgradeCost(ownerUserId: number, operationId: string, at: number, cost: any): any
	local buildApi = getGiantBuildModeQueryApi()
	if type(buildApi) ~= "table" or type(buildApi.SpendWorksiteUpgradeCost) ~= "function" then
		return { accepted = false, reason = "ledger_spend_api_unavailable" }
	end

	local spendResult = buildApi.SpendWorksiteUpgradeCost({
		operationId = operationId,
		spentAt = at,
		essence = cost.essence,
		wood = cost.wood,
		stone = cost.stone,
	})
	if type(spendResult) ~= "table" or spendResult.accepted ~= true or spendResult.duplicate == true then
		return {
			accepted = false,
			reason = if type(spendResult) == "table" then spendResult.reason else "ledger_spend_failed",
		}
	end

	return {
		accepted = true,
		reason = "accepted",
		ownerUserId = ownerUserId,
		spentFrom = spendResult.spentFrom,
	}
end

local function refundUpgradeCost(spentFrom: string?, operationId: string, at: number, cost: any)
	local buildApi = getGiantBuildModeQueryApi()
	if type(buildApi) == "table" and type(buildApi.RollbackWorksiteUpgradeSpend) == "function" then
		buildApi.RollbackWorksiteUpgradeSpend(spentFrom, operationId, cost.essence, cost.wood, cost.stone, at)
		return
	end

	if type(buildApi) ~= "table" or type(buildApi.ApplyResourceAward) ~= "function" then
		return
	end

	buildApi.ApplyResourceAward({
		operationId = string.format("refund:%s", operationId),
		sourceKind = "worksite_upgrade_refund",
		awardedAt = at,
		essence = cost.essence,
		wood = cost.wood,
		stone = cost.stone,
		counterpartyUserId = nil,
	})
end

local function rejectUpgrade(player: Player, reason: string, worksiteId: string?, responseRemote: RemoteEvent)
	debugWarn(
		string.format(
			"Rejected VillageWorksiteUpgradeRequest userId=%d worksiteId=%s reason=%s",
			player.UserId,
			tostring(worksiteId),
			reason
		)
	)
	responseRemote:FireClient(player, {
		accepted = false,
		reason = reason,
		worksiteId = worksiteId,
	})
end

local function requestUpgrade(player: Player, worksiteId: any, at: number?, responseRemote: RemoteEvent): any
	local resolvedAt = if type(at) == "number" then at else now()
	if isCoolingDown(player.UserId, resolvedAt) then
		rejectUpgrade(
			player,
			"request_cooldown",
			if type(worksiteId) == "string" then worksiteId else nil,
			responseRemote
		)
		return { accepted = false, reason = "request_cooldown" }
	end
	lastRequestAtByUserId[player.UserId] = resolvedAt

	if player:GetAttribute(ROLE_ATTRIBUTE) ~= RoleConfig.Roles.Giant then
		rejectUpgrade(
			player,
			"requester_not_giant",
			if type(worksiteId) == "string" then worksiteId else nil,
			responseRemote
		)
		return { accepted = false, reason = "requester_not_giant" }
	end

	local ownerUserId = getRealmOwnerUserId()
	if type(ownerUserId) ~= "number" or ownerUserId <= 0 then
		rejectUpgrade(
			player,
			"realm_owner_unavailable",
			if type(worksiteId) == "string" then worksiteId else nil,
			responseRemote
		)
		return { accepted = false, reason = "realm_owner_unavailable" }
	end
	if ownerUserId ~= player.UserId then
		rejectUpgrade(
			player,
			"giant_realm_owner_mismatch",
			if type(worksiteId) == "string" then worksiteId else nil,
			responseRemote
		)
		return { accepted = false, reason = "giant_realm_owner_mismatch" }
	end

	if type(worksiteId) ~= "string" or worksiteId == "" then
		rejectUpgrade(player, "worksite_id_invalid", nil, responseRemote)
		return { accepted = false, reason = "worksite_id_invalid" }
	end

	local transition = VillageWorksiteUpgradeState.ResolveUpgrade(upgradeState, {
		worksiteId = worksiteId,
		at = resolvedAt,
	})
	if transition.accepted ~= true then
		rejectUpgrade(player, transition.reason or "upgrade_rejected", worksiteId, responseRemote)
		return transition
	end

	local operationId = string.format("worksite-upgrade:%s:%d:%.6f", worksiteId, transition.level, resolvedAt)
	local spendResult = spendUpgradeCost(ownerUserId, operationId, resolvedAt, transition.cost)
	if spendResult.accepted ~= true then
		rejectUpgrade(player, spendResult.reason or "insufficient_resources", worksiteId, responseRemote)
		return spendResult
	end

	upgradeState = transition.state
	if worksiteId == ShrineConfig.DefaultShrineId or worksiteId == StationConfig.DefaultGiantDwellingId then
		refreshGiantEffectsForRealmOwner(ownerUserId, "worksite_upgrade")
	end
	responseRemote:FireClient(player, {
		accepted = true,
		reason = "accepted",
		worksiteId = worksiteId,
		level = transition.level,
		cost = transition.cost,
	})
	debugLog(
		string.format(
			"Accepted VillageWorksiteUpgradeRequest userId=%d worksiteId=%s level=%d wood=%d stone=%d essence=%d",
			player.UserId,
			worksiteId,
			transition.level,
			transition.cost.wood,
			transition.cost.stone,
			transition.cost.essence
		)
	)
	return transition
end

local function GetUpgradeLevel(worksiteId: string): number
	return VillageWorksiteUpgradeState.GetUpgradeLevel(upgradeState, worksiteId)
end

local function GetProductionModifiers(worksiteId: string): any
	local level = GetUpgradeLevel(worksiteId)
	return VillageWorksiteUpgradeState.ResolveProductionModifiers(level)
end

local function GetInTransitCapacityMultiplier(worksiteId: string): number
	local worksiteKind = VillageWorksiteUpgradeState.ResolveWorksiteKind(worksiteId)
	if worksiteKind == nil then
		return 1
	end
	if
		VillageWorksiteUpgradeState.ResolveEffectKind(worksiteKind) ~= VillageWorksiteUpgradeState.EffectKinds.Capacity
	then
		return 1
	end
	if
		worksiteKind ~= VillageWorksiteUpgradeState.WorksiteKinds.Warehouse
		and worksiteKind ~= VillageWorksiteUpgradeState.WorksiteKinds.Granary
	then
		return 1
	end
	local modifiers = VillageWorksiteUpgradeState.ResolveCapacityModifiers(GetUpgradeLevel(worksiteId))
	return modifiers.inTransitMultiplier
end

local function GetHeldCapacityMultiplier(penId: string): number
	local worksiteKind = VillageWorksiteUpgradeState.ResolveWorksiteKind(penId)
	if worksiteKind ~= VillageWorksiteUpgradeState.WorksiteKinds.Pen then
		return 1
	end
	local modifiers = VillageWorksiteUpgradeState.ResolveCapacityModifiers(GetUpgradeLevel(penId))
	return modifiers.heldCapacityMultiplier
end

local function GetGiantHousingCapacityMultiplier(dwellingId: string): number
	local worksiteKind = VillageWorksiteUpgradeState.ResolveWorksiteKind(dwellingId)
	if worksiteKind ~= VillageWorksiteUpgradeState.WorksiteKinds.GiantDwelling then
		return 1
	end
	local modifiers = VillageWorksiteUpgradeState.ResolveGiantHousingCapacityModifiers(GetUpgradeLevel(dwellingId))
	return modifiers.housingCapacityMultiplier
end

local function GetDefenseMultiplier(guardTowerId: string): number
	local worksiteKind = VillageWorksiteUpgradeState.ResolveWorksiteKind(guardTowerId)
	if worksiteKind ~= VillageWorksiteUpgradeState.WorksiteKinds.GuardTower then
		return 1
	end
	local modifiers = VillageWorksiteUpgradeState.ResolveDefenseModifiers(GetUpgradeLevel(guardTowerId))
	return modifiers.treasuryAwardMultiplier
end

local function GetEssenceMaxCapacityMultiplier(shrineId: string): number
	local worksiteKind = VillageWorksiteUpgradeState.ResolveWorksiteKind(shrineId)
	if worksiteKind ~= VillageWorksiteUpgradeState.WorksiteKinds.Shrine then
		return 1
	end
	local modifiers = VillageWorksiteUpgradeState.ResolveCapacityModifiers(GetUpgradeLevel(shrineId))
	return modifiers.essenceMaxMultiplier
end

local function BuildPersistenceState(): any
	return VillageWorksiteUpgradeState.SerializePersistenceState(upgradeState)
end

local function ApplyPersistenceState(raw: any): (boolean, string?)
	local applied = VillageWorksiteUpgradeState.ApplyPersistenceState(raw)
	if applied.accepted ~= true then
		return false, applied.reason or "worksite_upgrade_apply_failed"
	end
	upgradeState = applied.state
	refreshGiantEffectsForRealmOwner(getRealmOwnerUserId(), "worksite_persistence_apply")
	return true, nil
end

local remotesFolder = ensureRemotesFolder()
local requestRemote = ensureRemoteEvent(remotesFolder, REQUEST_REMOTE_NAME)
local responseRemote = ensureRemoteEvent(remotesFolder, RESPONSE_REMOTE_NAME)

requestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	local worksiteId: any = nil
	if type(payload) == "string" then
		worksiteId = payload
	elseif type(payload) == "table" then
		worksiteId = (payload :: any).worksiteId
	end
	requestUpgrade(player, worksiteId, nil, responseRemote)
end)

globalEnv._VillageWorksiteUpgradeService_QueryAPI = {
	GetUpgradeLevel = GetUpgradeLevel,
	GetProductionModifiers = GetProductionModifiers,
	GetInTransitCapacityMultiplier = GetInTransitCapacityMultiplier,
	GetHeldCapacityMultiplier = GetHeldCapacityMultiplier,
	GetDefenseMultiplier = GetDefenseMultiplier,
	GetGiantHousingCapacityMultiplier = GetGiantHousingCapacityMultiplier,
	GetEssenceMaxCapacityMultiplier = GetEssenceMaxCapacityMultiplier,
	BuildPersistenceState = BuildPersistenceState,
	ApplyPersistenceState = ApplyPersistenceState,
	RequestUpgradeForTests = requestUpgrade,
	RefundUpgradeCostForTests = refundUpgradeCost,
}

debugLog("VillageWorksiteUpgradeService initialized")
