--!strict

local ProfilePersistenceGateway: any = {}

local EventStateOwnershipModel = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("EventStateOwnershipModel")
	)
	else require("../../ReplicatedStorage/Shared/GiantRealm/EventStateOwnershipModel")

local ReputationState = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("Reputation")
			:WaitForChild("ReputationState")
	)
	else require("../../ReplicatedStorage/Shared/Reputation/ReputationState")

export type GatewayResult = {
	ok: boolean,
	operation: string,
	reason: string?,
	retryable: boolean?,
	profileKey: string?,
	data: any?,
}

export type ProfileOwnerLayer = {
	LoadPlayerProfile: (profileKey: string, userId: number) -> GatewayResult,
	SavePlayerProfile: (profileKey: string, userId: number, data: any) -> GatewayResult,
	ReleasePlayerProfile: (profileKey: string, userId: number) -> GatewayResult,
	LoadGiantRealmProfile: (profileKey: string, ownerUserId: number) -> GatewayResult,
	SaveGiantRealmProfile: (profileKey: string, ownerUserId: number, saveRoot: any) -> GatewayResult,
	ReleaseGiantRealmProfile: (profileKey: string, ownerUserId: number) -> GatewayResult,
}

local activePlayerProfileDataByUserId: { [number]: any } = {}
local ownerLayer: ProfileOwnerLayer?

local function makeFailure(operation: string, reason: string, profileKey: string?, retryable: boolean?): GatewayResult
	return {
		ok = false,
		operation = operation,
		reason = reason,
		retryable = retryable,
		profileKey = profileKey,
		data = nil,
	}
end

local function makeSuccess(operation: string, profileKey: string?, data: any?): GatewayResult
	return {
		ok = true,
		operation = operation,
		reason = nil,
		retryable = nil,
		profileKey = profileKey,
		data = data,
	}
end

local function isValidUserId(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	if value <= 0 or value % 1 ~= 0 then
		return false
	end
	return true
end

local function getPlayerUserId(player: any): number?
	if type(player) ~= "table" and typeof(player) ~= "Instance" then
		return nil
	end

	local userId = player.UserId
	if not isValidUserId(userId) then
		return nil
	end

	return userId
end

local function playerProfileKey(userId: number): string
	return string.format("PlayerProfile:%d", userId)
end

local function giantRealmProfileKey(ownerUserId: number): string
	return string.format("GiantRealmProfile:%d", ownerUserId)
end

local function makeDefaultPlayerProfileData(userId: number): any
	return {
		schemaVersion = 1,
		userId = userId,
		reputationState = {
			schemaVersion = 1,
			byTrackId = {},
			recentOutcomeAtByKey = {},
			unlockedCosmeticIds = {},
			unlockedLoadoutTraitIds = {},
		},
		giantTraitState = {
			unlockedTraitIds = {},
		},
		roleLoadoutState = {
			selectedByRole = {
				Giant = {},
				Tinyfolk = {},
			},
		},
		tinyfolkToolLoadoutState = {
			schemaVersion = 1,
			selectedByRole = {
				Tinyfolk = {},
			},
		},
	}
end

local function copyDefaultPlayerProfileData(data: any): any
	local giantTraitState: any = data.giantTraitState
	local reputationState: any = data.reputationState
	local roleLoadoutState: any = data.roleLoadoutState
	local tinyfolkToolLoadoutState: any = data.tinyfolkToolLoadoutState
	local unlockedTraitIds = {}
	local unlockedTraitIdsValue: any = if type(giantTraitState) == "table"
		then giantTraitState["unlockedTraitIds"]
		else nil
	if type(unlockedTraitIdsValue) == "table" then
		for _, traitId in ipairs(unlockedTraitIdsValue) do
			if type(traitId) == "string" and traitId ~= "" then
				table.insert(unlockedTraitIds, traitId)
			end
		end
	end

	local function copySelectedByRole(roleName: string): { [string]: string }
		local copied = {}
		local selectedByRole: any = if type(roleLoadoutState) == "table"
			then roleLoadoutState["selectedByRole"]
			else nil
		local selectedSlots: any = if type(selectedByRole) == "table" then selectedByRole[roleName] else nil
		if type(selectedSlots) ~= "table" then
			return copied
		end
		for slotId, traitId in pairs(selectedSlots) do
			if type(slotId) == "string" and slotId ~= "" and type(traitId) == "string" and traitId ~= "" then
				copied[slotId] = traitId
			end
		end
		return copied
	end

	local function copyTinyfolkToolSelectedByRole(roleName: string): { [string]: string }
		local copied = {}
		local selectedByRole: any = if type(tinyfolkToolLoadoutState) == "table"
			then tinyfolkToolLoadoutState["selectedByRole"]
			else nil
		local selectedSlots: any = if type(selectedByRole) == "table" then selectedByRole[roleName] else nil
		if type(selectedSlots) ~= "table" then
			return copied
		end
		for slotId, toolId in pairs(selectedSlots) do
			if type(slotId) == "string" and slotId ~= "" and type(toolId) == "string" and toolId ~= "" then
				copied[slotId] = toolId
			end
		end
		return copied
	end

	local function copyStringList(value: any): { string }
		local copied = {}
		if type(value) ~= "table" then
			return copied
		end
		local seen: { [string]: boolean } = {}
		for _, entry in ipairs(value) do
			if type(entry) == "string" and entry ~= "" and seen[entry] ~= true then
				seen[entry] = true
				table.insert(copied, entry)
			end
		end
		return copied
	end

	local cloneAny: (value: any) -> any
	cloneAny = function(value: any): any
		if type(value) ~= "table" then
			return value
		end
		local copied = {}
		for key, child in pairs(value) do
			copied[key] = cloneAny(child)
		end
		return copied
	end

	return {
		schemaVersion = data.schemaVersion,
		userId = data.userId,
		reputationState = {
			schemaVersion = if type(reputationState) == "table"
					and type(reputationState["schemaVersion"]) == "number"
				then reputationState["schemaVersion"]
				else 1,
			byTrackId = if type(reputationState) == "table" and type(reputationState["byTrackId"]) == "table"
				then cloneAny(reputationState["byTrackId"])
				else {},
			recentOutcomeAtByKey = if type(reputationState) == "table"
					and type(reputationState["recentOutcomeAtByKey"]) == "table"
				then cloneAny(reputationState["recentOutcomeAtByKey"])
				else {},
			unlockedCosmeticIds = copyStringList(
				if type(reputationState) == "table" then reputationState["unlockedCosmeticIds"] else nil
			),
			unlockedLoadoutTraitIds = copyStringList(
				if type(reputationState) == "table" then reputationState["unlockedLoadoutTraitIds"] else nil
			),
		},
		giantTraitState = {
			unlockedTraitIds = unlockedTraitIds,
		},
		roleLoadoutState = {
			selectedByRole = {
				Giant = copySelectedByRole("Giant"),
				Tinyfolk = copySelectedByRole("Tinyfolk"),
			},
		},
		tinyfolkToolLoadoutState = {
			schemaVersion = if type(tinyfolkToolLoadoutState) == "table"
					and type(tinyfolkToolLoadoutState["schemaVersion"]) == "number"
				then tinyfolkToolLoadoutState["schemaVersion"]
				else 1,
			selectedByRole = {
				Tinyfolk = copyTinyfolkToolSelectedByRole("Tinyfolk"),
			},
		},
	}
end

local cloneTable: (value: any) -> any
cloneTable = function(value: any): any
	if type(value) ~= "table" then
		return value
	end

	local result = {}
	for key, child in pairs(value) do
		result[key] = cloneTable(child)
	end
	return result
end

local function getConfiguredOwnerLayer(_operation: string, _profileKey: string): ProfileOwnerLayer?
	if ownerLayer == nil then
		return nil
	end
	return ownerLayer
end

local function getGiantBuildModeQueryApi(operation: string, profileKey: string): (any?, GatewayResult?)
	local queryApi = _G._GiantBuildModeService_QueryAPI
	if type(queryApi) ~= "table" then
		return nil, makeFailure(operation, "giant_build_mode_query_api_missing", profileKey, false)
	end
	return queryApi, nil
end

local function getEventStateOwnershipModel(): any
	local overrideModel = _G._EventStateOwnershipModel_QueryAPI
	if type(overrideModel) == "table" then
		return overrideModel
	end

	return EventStateOwnershipModel
end

function ProfilePersistenceGateway.ConfigureOwnerLayer(newOwnerLayer: any)
	ownerLayer = newOwnerLayer :: ProfileOwnerLayer
end

function ProfilePersistenceGateway.ResetForTests()
	ownerLayer = nil
	activePlayerProfileDataByUserId = {}
end

function ProfilePersistenceGateway.LoadDefaultPlayerProfile(userId: any): GatewayResult
	if not isValidUserId(userId) then
		return makeFailure("LoadDefaultPlayerProfile", "invalid_user_id", nil, false)
	end

	local key = playerProfileKey(userId)
	local data = makeDefaultPlayerProfileData(userId)
	return makeSuccess("LoadDefaultPlayerProfile", key, data)
end

function ProfilePersistenceGateway.ResolveEventOutcomeWriteBack(input: any): any
	local model = getEventStateOwnershipModel()
	if type(model.ResolveWriteBackPlan) ~= "function" then
		return {
			accepted = false,
			reason = "event_state_write_back_resolver_missing",
		}
	end

	return model.ResolveWriteBackPlan(input)
end

function ProfilePersistenceGateway.ResolveReconnectRestoreAction(input: any): any
	local model = getEventStateOwnershipModel()
	if type(model.ResolveReconnectRestore) ~= "function" then
		return {
			accepted = false,
			reason = "event_state_reconnect_resolver_missing",
		}
	end

	return model.ResolveReconnectRestore(input)
end

function ProfilePersistenceGateway.LoadPlayerProfile(player: any): GatewayResult
	local userId = getPlayerUserId(player)
	if userId == nil then
		return makeFailure("LoadPlayerProfile", "invalid_player_user_id", nil, false)
	end

	local key = playerProfileKey(userId)
	local configuredOwnerLayer = getConfiguredOwnerLayer("LoadPlayerProfile", key)
	if configuredOwnerLayer == nil then
		return makeFailure("LoadPlayerProfile", "owner_layer_not_configured", key, true)
	end

	local result = configuredOwnerLayer.LoadPlayerProfile(key, userId)
	if result.ok then
		activePlayerProfileDataByUserId[userId] = result.data
	end
	return result
end

function ProfilePersistenceGateway.GetLoadedPlayerProfileData(player: any): GatewayResult
	local userId = getPlayerUserId(player)
	if userId == nil then
		return makeFailure("GetLoadedPlayerProfileData", "invalid_player_user_id", nil, false)
	end

	local key = playerProfileKey(userId)
	local data = activePlayerProfileDataByUserId[userId]
	if type(data) ~= "table" then
		return makeFailure("GetLoadedPlayerProfileData", "player_profile_not_loaded", key, false)
	end

	return makeSuccess("GetLoadedPlayerProfileData", key, cloneTable(data))
end

function ProfilePersistenceGateway.GetLoadedPlayerReputationTitleIds(player: any): GatewayResult
	local profileResult = ProfilePersistenceGateway.GetLoadedPlayerProfileData(player)
	if not profileResult.ok then
		return makeFailure(
			"GetLoadedPlayerReputationTitleIds",
			profileResult.reason or "player_profile_not_loaded",
			profileResult.profileKey,
			false
		)
	end

	local titleIds = ReputationState.GetUnlockedCosmeticIds(profileResult.data)
	return makeSuccess("GetLoadedPlayerReputationTitleIds", profileResult.profileKey, {
		titleIds = titleIds,
	})
end

function ProfilePersistenceGateway.UpdateLoadedPlayerProfileData(player: any, updater: any): GatewayResult
	local userId = getPlayerUserId(player)
	if userId == nil then
		return makeFailure("UpdateLoadedPlayerProfileData", "invalid_player_user_id", nil, false)
	end

	local key = playerProfileKey(userId)
	local data = activePlayerProfileDataByUserId[userId]
	if type(data) ~= "table" then
		return makeFailure("UpdateLoadedPlayerProfileData", "player_profile_not_loaded", key, false)
	end
	if type(updater) ~= "function" then
		return makeFailure("UpdateLoadedPlayerProfileData", "profile_update_updater_invalid", key, false)
	end

	local updateOk, newData, updateReason = pcall(updater, cloneTable(data))
	if not updateOk then
		return makeFailure("UpdateLoadedPlayerProfileData", "profile_update_failed", key, false)
	end
	if type(newData) ~= "table" then
		return makeFailure(
			"UpdateLoadedPlayerProfileData",
			if type(updateReason) == "string" and updateReason ~= ""
				then updateReason
				else "profile_update_data_invalid",
			key,
			false
		)
	end

	activePlayerProfileDataByUserId[userId] = cloneTable(newData)
	return makeSuccess("UpdateLoadedPlayerProfileData", key, cloneTable(activePlayerProfileDataByUserId[userId]))
end

function ProfilePersistenceGateway.SavePlayerProfile(player: any): GatewayResult
	local userId = getPlayerUserId(player)
	if userId == nil then
		return makeFailure("SavePlayerProfile", "invalid_player_user_id", nil, false)
	end

	local key = playerProfileKey(userId)
	local configuredOwnerLayer = getConfiguredOwnerLayer("SavePlayerProfile", key)
	if configuredOwnerLayer == nil then
		return makeFailure("SavePlayerProfile", "owner_layer_not_configured", key, true)
	end

	local data = activePlayerProfileDataByUserId[userId]
	if data == nil then
		data = copyDefaultPlayerProfileData(makeDefaultPlayerProfileData(userId))
	end

	return configuredOwnerLayer.SavePlayerProfile(key, userId, data)
end

function ProfilePersistenceGateway.ReleasePlayerProfile(player: any): GatewayResult
	local userId = getPlayerUserId(player)
	if userId == nil then
		return makeFailure("ReleasePlayerProfile", "invalid_player_user_id", nil, false)
	end

	local key = playerProfileKey(userId)
	local configuredOwnerLayer = getConfiguredOwnerLayer("ReleasePlayerProfile", key)
	if configuredOwnerLayer == nil then
		return makeFailure("ReleasePlayerProfile", "owner_layer_not_configured", key, true)
	end

	local result = configuredOwnerLayer.ReleasePlayerProfile(key, userId)
	if result.ok then
		activePlayerProfileDataByUserId[userId] = nil
	end
	return result
end

function ProfilePersistenceGateway.SaveGiantRealmProfile(ownerUserId: any): GatewayResult
	if not isValidUserId(ownerUserId) then
		return makeFailure("SaveGiantRealmProfile", "invalid_owner_user_id", nil, false)
	end

	local key = giantRealmProfileKey(ownerUserId)
	local queryApi, queryApiFailure = getGiantBuildModeQueryApi("SaveGiantRealmProfile", key)
	if queryApiFailure ~= nil then
		return queryApiFailure
	end

	if type(queryApi.BuildSaveSnapshot) ~= "function" then
		return makeFailure("SaveGiantRealmProfile", "build_save_snapshot_missing", key, false)
	end

	local saveRoot, snapshotReason = queryApi.BuildSaveSnapshot(ownerUserId)
	if saveRoot == nil then
		return makeFailure("SaveGiantRealmProfile", snapshotReason or "build_save_snapshot_failed", key, false)
	end

	local configuredOwnerLayer = getConfiguredOwnerLayer("SaveGiantRealmProfile", key)
	if configuredOwnerLayer == nil then
		return makeFailure("SaveGiantRealmProfile", "owner_layer_not_configured", key, true)
	end

	return configuredOwnerLayer.SaveGiantRealmProfile(key, ownerUserId, saveRoot)
end

function ProfilePersistenceGateway.LoadGiantRealmProfile(ownerUserId: any): GatewayResult
	if not isValidUserId(ownerUserId) then
		return makeFailure("LoadGiantRealmProfile", "invalid_owner_user_id", nil, false)
	end

	local key = giantRealmProfileKey(ownerUserId)
	local configuredOwnerLayer = getConfiguredOwnerLayer("LoadGiantRealmProfile", key)
	if configuredOwnerLayer == nil then
		return makeFailure("LoadGiantRealmProfile", "owner_layer_not_configured", key, true)
	end

	local ownerResult = configuredOwnerLayer.LoadGiantRealmProfile(key, ownerUserId)
	if not ownerResult.ok then
		return ownerResult
	end
	if ownerResult.data == nil then
		return makeFailure("LoadGiantRealmProfile", "giant_realm_save_root_missing", key, false)
	end

	local queryApi, queryApiFailure = getGiantBuildModeQueryApi("LoadGiantRealmProfile", key)
	if queryApiFailure ~= nil then
		return queryApiFailure
	end

	if type(queryApi.ApplySaveSnapshot) ~= "function" then
		return makeFailure("LoadGiantRealmProfile", "apply_save_snapshot_missing", key, false)
	end

	local applied, applyReason = queryApi.ApplySaveSnapshot(ownerResult.data)
	if not applied then
		return makeFailure("LoadGiantRealmProfile", applyReason or "apply_save_snapshot_failed", key, false)
	end

	return makeSuccess("LoadGiantRealmProfile", key, ownerResult.data)
end

function ProfilePersistenceGateway.ReleaseGiantRealmProfile(ownerUserId: any): GatewayResult
	if not isValidUserId(ownerUserId) then
		return makeFailure("ReleaseGiantRealmProfile", "invalid_owner_user_id", nil, false)
	end

	local key = giantRealmProfileKey(ownerUserId)
	local configuredOwnerLayer = getConfiguredOwnerLayer("ReleaseGiantRealmProfile", key)
	if configuredOwnerLayer == nil then
		return makeFailure("ReleaseGiantRealmProfile", "owner_layer_not_configured", key, true)
	end

	if type(configuredOwnerLayer.ReleaseGiantRealmProfile) ~= "function" then
		return makeFailure("ReleaseGiantRealmProfile", "release_giant_realm_profile_missing", key, false)
	end

	return configuredOwnerLayer.ReleaseGiantRealmProfile(key, ownerUserId)
end

return ProfilePersistenceGateway
