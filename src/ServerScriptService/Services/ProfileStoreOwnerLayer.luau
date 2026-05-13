--!strict

local ProfileStoreOwnerLayer = {}

type GatewayResult = {
	ok: boolean,
	operation: string,
	reason: string?,
	retryable: boolean?,
	profileKey: string?,
	data: any?,
}

export type CreateConfig = {
	profileStoreModule: any,
	playerStoreName: string,
	playerProfileTemplate: any,
}

export type ProfileOwnerLayer = {
	LoadPlayerProfile: (profileKey: string, userId: number) -> GatewayResult,
	SavePlayerProfile: (profileKey: string, userId: number, data: any) -> GatewayResult,
	ReleasePlayerProfile: (profileKey: string, userId: number) -> GatewayResult,
	LoadGiantRealmProfile: (profileKey: string, ownerUserId: number) -> GatewayResult,
	SaveGiantRealmProfile: (profileKey: string, ownerUserId: number, saveRoot: any) -> GatewayResult,
}

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

local function isNonEmptyString(value: any): boolean
	return type(value) == "string" and value ~= ""
end

local function isProfileObject(value: any): boolean
	return type(value) == "table" and type(value.EndSession) == "function" and type(value.Data) == "table"
end

local function cloneTable(value: any): any
	if type(value) ~= "table" then
		return value
	end

	local result = {}
	for key, child in pairs(value) do
		result[key] = cloneTable(child)
	end
	return result
end

local function validateCreateConfig(config: any): (boolean, string?)
	if type(config) ~= "table" then
		return false, "config_missing"
	end
	if type(config.profileStoreModule) ~= "table" then
		return false, "profile_store_module_missing"
	end
	if type(config.profileStoreModule.New) ~= "function" then
		return false, "profile_store_new_missing"
	end
	if not isNonEmptyString(config.playerStoreName) then
		return false, "player_store_name_invalid"
	end
	if type(config.playerProfileTemplate) ~= "table" then
		return false, "player_profile_template_invalid"
	end
	return true, nil
end

function ProfileStoreOwnerLayer.ResetForTests()
	-- This adapter keeps state per Create() instance; reset is present for test symmetry.
end

function ProfileStoreOwnerLayer.Create(config: any): ProfileOwnerLayer
	local configValid, configReason = validateCreateConfig(config)
	if not configValid then
		error(configReason or "config_invalid")
	end

	local playerStore = config.profileStoreModule.New(config.playerStoreName, cloneTable(config.playerProfileTemplate))
	if type(playerStore) ~= "table" then
		error("player_store_invalid")
	end
	if type(playerStore.StartSessionAsync) ~= "function" then
		error("player_store_start_session_missing")
	end

	local activeProfilesByUserId: { [number]: any } = {}
	local activeUserIdByProfileKey: { [string]: number } = {}

	local ownerLayer = {}

	function ownerLayer.LoadPlayerProfile(profileKey: string, userId: number): GatewayResult
		if not isNonEmptyString(profileKey) then
			return makeFailure("LoadPlayerProfile", "profile_key_invalid", nil, false)
		end
		if not isValidUserId(userId) then
			return makeFailure("LoadPlayerProfile", "invalid_user_id", profileKey, false)
		end
		if activeProfilesByUserId[userId] ~= nil or activeUserIdByProfileKey[profileKey] ~= nil then
			return makeFailure("LoadPlayerProfile", "profile_session_already_active", profileKey, false)
		end

		local profile = playerStore:StartSessionAsync(profileKey, {})
		if not isProfileObject(profile) then
			return makeFailure("LoadPlayerProfile", "profile_session_start_failed", profileKey, true)
		end

		activeProfilesByUserId[userId] = profile
		activeUserIdByProfileKey[profileKey] = userId

		return makeSuccess("LoadPlayerProfile", profileKey, profile.Data)
	end

	function ownerLayer.SavePlayerProfile(profileKey: string, userId: number, data: any): GatewayResult
		if not isNonEmptyString(profileKey) then
			return makeFailure("SavePlayerProfile", "profile_key_invalid", nil, false)
		end
		if not isValidUserId(userId) then
			return makeFailure("SavePlayerProfile", "invalid_user_id", profileKey, false)
		end

		local profile = activeProfilesByUserId[userId]
		if not isProfileObject(profile) or activeUserIdByProfileKey[profileKey] ~= userId then
			return makeFailure("SavePlayerProfile", "profile_session_not_active", profileKey, false)
		end
		if type(data) ~= "table" then
			return makeFailure("SavePlayerProfile", "profile_data_invalid", profileKey, false)
		end

		profile.Data = cloneTable(data)

		return makeSuccess("SavePlayerProfile", profileKey, profile.Data)
	end

	function ownerLayer.ReleasePlayerProfile(profileKey: string, userId: number): GatewayResult
		if not isNonEmptyString(profileKey) then
			return makeFailure("ReleasePlayerProfile", "profile_key_invalid", nil, false)
		end
		if not isValidUserId(userId) then
			return makeFailure("ReleasePlayerProfile", "invalid_user_id", profileKey, false)
		end

		local profile = activeProfilesByUserId[userId]
		if not isProfileObject(profile) or activeUserIdByProfileKey[profileKey] ~= userId then
			return makeFailure("ReleasePlayerProfile", "profile_session_not_active", profileKey, false)
		end

		profile:EndSession()
		activeProfilesByUserId[userId] = nil
		activeUserIdByProfileKey[profileKey] = nil

		return makeSuccess("ReleasePlayerProfile", profileKey, nil)
	end

	function ownerLayer.LoadGiantRealmProfile(profileKey: string, _ownerUserId: number): GatewayResult
		return makeFailure(
			"LoadGiantRealmProfile",
			"giant_realm_profiles_not_supported_in_this_slice",
			profileKey,
			false
		)
	end

	function ownerLayer.SaveGiantRealmProfile(profileKey: string, _ownerUserId: number, _saveRoot: any): GatewayResult
		return makeFailure(
			"SaveGiantRealmProfile",
			"giant_realm_profiles_not_supported_in_this_slice",
			profileKey,
			false
		)
	end

	return ownerLayer :: ProfileOwnerLayer
end

function ProfileStoreOwnerLayer.CreateDefault(profileStoreModule: any?): ProfileOwnerLayer
	local resolvedProfileStoreModule = profileStoreModule
	if resolvedProfileStoreModule == nil then
		resolvedProfileStoreModule = require(script.Parent.ThirdParty.ProfileStore)
	end

	return ProfileStoreOwnerLayer.Create({
		profileStoreModule = resolvedProfileStoreModule,
		playerStoreName = "TinyfolkPlayerProfiles",
		playerProfileTemplate = {
			schemaVersion = 1,
		},
	})
end

return ProfileStoreOwnerLayer
