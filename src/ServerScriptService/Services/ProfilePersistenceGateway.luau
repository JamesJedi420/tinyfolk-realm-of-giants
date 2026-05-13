--!strict

local ProfilePersistenceGateway = {}

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
	}
end

local function makeSuccess(operation: string, profileKey: string?, data: any?): GatewayResult
	return {
		ok = true,
		operation = operation,
		profileKey = profileKey,
		data = data,
	}
end

local function isValidUserId(value: any): boolean
	return type(value) == "number"
		and value == value
		and value ~= math.huge
		and value ~= -math.huge
		and value > 0
		and value % 1 == 0
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
	}
end

local function copyDefaultPlayerProfileData(data: any): any
	return {
		schemaVersion = data.schemaVersion,
		userId = data.userId,
	}
end

local function getConfiguredOwnerLayer(operation: string, profileKey: string): ProfileOwnerLayer?
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
		return makeFailure(
			"SaveGiantRealmProfile",
			snapshotReason or "build_save_snapshot_failed",
			key,
			false
		)
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

return ProfilePersistenceGateway
