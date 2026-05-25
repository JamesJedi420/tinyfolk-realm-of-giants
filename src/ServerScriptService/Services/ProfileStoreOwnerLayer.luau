--!strict

local ProfileStoreOwnerLayer: any = {}

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
	giantRealmStoreName: string,
	giantRealmProfileTemplate: any,
	validateGiantRealmSaveRoot: ((saveRoot: any) -> (boolean, string?))?,
}

export type ProfileOwnerLayer = {
	LoadPlayerProfile: (profileKey: string, userId: number) -> GatewayResult,
	SavePlayerProfile: (profileKey: string, userId: number, data: any) -> GatewayResult,
	ReleasePlayerProfile: (profileKey: string, userId: number) -> GatewayResult,
	LoadGiantRealmProfile: (profileKey: string, ownerUserId: number) -> GatewayResult,
	SaveGiantRealmProfile: (profileKey: string, ownerUserId: number, saveRoot: any) -> GatewayResult,
	ReleaseGiantRealmProfile: (profileKey: string, ownerUserId: number) -> GatewayResult,
}

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

local function isNonEmptyString(value: any): boolean
	if type(value) ~= "string" then
		return false
	end
	return value ~= ""
end

local function isProfileObject(value: any): boolean
	if type(value) ~= "table" then
		return false
	end
	if type(value.EndSession) ~= "function" then
		return false
	end
	if type(value.Data) ~= "table" then
		return false
	end
	return true
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
	if not isNonEmptyString(config.giantRealmStoreName) then
		return false, "giant_realm_store_name_invalid"
	end
	if type(config.giantRealmProfileTemplate) ~= "table" then
		return false, "giant_realm_profile_template_invalid"
	end
	if config.validateGiantRealmSaveRoot ~= nil and type(config.validateGiantRealmSaveRoot) ~= "function" then
		return false, "giant_realm_save_root_validator_invalid"
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

	local giantRealmStore =
		config.profileStoreModule.New(config.giantRealmStoreName, cloneTable(config.giantRealmProfileTemplate))
	if type(giantRealmStore) ~= "table" then
		error("giant_realm_store_invalid")
	end
	if type(giantRealmStore.StartSessionAsync) ~= "function" then
		error("giant_realm_store_start_session_missing")
	end

	local activeProfilesByUserId: { [number]: any } = {}
	local activeUserIdByProfileKey: { [string]: number? } = {}
	local activeGiantRealmProfilesByUserId: { [number]: any } = {}
	local activeGiantRealmUserIdByProfileKey: { [string]: number? } = {}
	local validateGiantRealmSaveRoot = config.validateGiantRealmSaveRoot
		or function(saveRoot: any): (boolean, string?)
			if type(saveRoot) ~= "table" then
				return false, "save_root_invalid"
			end

			return true, nil
		end

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

	function ownerLayer.LoadGiantRealmProfile(profileKey: string, ownerUserId: number): GatewayResult
		if not isNonEmptyString(profileKey) then
			return makeFailure("LoadGiantRealmProfile", "profile_key_invalid", nil, false)
		end
		if not isValidUserId(ownerUserId) then
			return makeFailure("LoadGiantRealmProfile", "invalid_owner_user_id", profileKey, false)
		end
		if
			activeGiantRealmProfilesByUserId[ownerUserId] ~= nil
			or activeGiantRealmUserIdByProfileKey[profileKey] ~= nil
		then
			return makeFailure("LoadGiantRealmProfile", "profile_session_already_active", profileKey, false)
		end

		local profile = giantRealmStore:StartSessionAsync(profileKey, {})
		if not isProfileObject(profile) then
			return makeFailure("LoadGiantRealmProfile", "profile_session_start_failed", profileKey, true)
		end

		local loadedData = profile.Data
		local validLoadedRoot, loadedReason = validateGiantRealmSaveRoot(loadedData)
		if not validLoadedRoot then
			profile:EndSession()
			return makeFailure(
				"LoadGiantRealmProfile",
				loadedReason or "giant_realm_save_root_invalid",
				profileKey,
				false
			)
		end

		activeGiantRealmProfilesByUserId[ownerUserId] = profile
		activeGiantRealmUserIdByProfileKey[profileKey] = ownerUserId

		return makeSuccess("LoadGiantRealmProfile", profileKey, loadedData)
	end

	function ownerLayer.SaveGiantRealmProfile(profileKey: string, ownerUserId: number, saveRoot: any): GatewayResult
		if not isNonEmptyString(profileKey) then
			return makeFailure("SaveGiantRealmProfile", "profile_key_invalid", nil, false)
		end
		if not isValidUserId(ownerUserId) then
			return makeFailure("SaveGiantRealmProfile", "invalid_owner_user_id", profileKey, false)
		end

		local profile = activeGiantRealmProfilesByUserId[ownerUserId]
		if not isProfileObject(profile) or activeGiantRealmUserIdByProfileKey[profileKey] ~= ownerUserId then
			return makeFailure("SaveGiantRealmProfile", "profile_session_not_active", profileKey, false)
		end

		local validSaveRoot, saveRootReason = validateGiantRealmSaveRoot(saveRoot)
		if not validSaveRoot then
			return makeFailure(
				"SaveGiantRealmProfile",
				saveRootReason or "giant_realm_save_root_invalid",
				profileKey,
				false
			)
		end

		profile.Data = cloneTable(saveRoot)

		return makeSuccess("SaveGiantRealmProfile", profileKey, profile.Data)
	end

	function ownerLayer.ReleaseGiantRealmProfile(profileKey: string, ownerUserId: number): GatewayResult
		if not isNonEmptyString(profileKey) then
			return makeFailure("ReleaseGiantRealmProfile", "profile_key_invalid", nil, false)
		end
		if not isValidUserId(ownerUserId) then
			return makeFailure("ReleaseGiantRealmProfile", "invalid_owner_user_id", profileKey, false)
		end

		local profile = activeGiantRealmProfilesByUserId[ownerUserId]
		if not isProfileObject(profile) or activeGiantRealmUserIdByProfileKey[profileKey] ~= ownerUserId then
			return makeFailure("ReleaseGiantRealmProfile", "profile_session_not_active", profileKey, false)
		end

		profile:EndSession()
		activeGiantRealmProfilesByUserId[ownerUserId] = nil
		activeGiantRealmUserIdByProfileKey[profileKey] = nil

		return makeSuccess("ReleaseGiantRealmProfile", profileKey, nil)
	end

	return ownerLayer :: ProfileOwnerLayer
end

function ProfileStoreOwnerLayer.CreateDefault(profileStoreModule: any?): ProfileOwnerLayer
	local resolvedProfileStoreModule = profileStoreModule
	if resolvedProfileStoreModule == nil then
		resolvedProfileStoreModule = require(script.Parent.ThirdParty.ProfileStore)
	end

	local function validateGiantRealmSaveRoot(saveRoot: any): (boolean, string?)
		local shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
		local giantRealm = shared:WaitForChild("GiantRealm")
		local schemaModule = require(giantRealm:WaitForChild("GiantRealmSaveSchema"))
		if type(schemaModule) ~= "table" or type(schemaModule.ValidateSaveRoot) ~= "function" then
			return false, "giant_realm_save_schema_unavailable"
		end

		return schemaModule.ValidateSaveRoot(saveRoot)
	end

	return ProfileStoreOwnerLayer.Create({
		profileStoreModule = resolvedProfileStoreModule,
		playerStoreName = "TinyfolkPlayerProfiles",
		playerProfileTemplate = {
			schemaVersion = 1,
		},
		giantRealmStoreName = "TinyfolkGiantRealmProfiles",
		giantRealmProfileTemplate = {
			schemaVersion = 1,
			ownerUserId = 0,
			placedStructures = {},
		},
		validateGiantRealmSaveRoot = validateGiantRealmSaveRoot,
	})
end

return ProfileStoreOwnerLayer
