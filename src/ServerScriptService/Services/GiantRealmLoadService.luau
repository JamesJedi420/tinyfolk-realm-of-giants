--!strict

local GiantRealmLoadConfig = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("Config")
			:WaitForChild("GiantRealmLoadConfig")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/Config/GiantRealmLoadConfig")

local GiantRealmLoadState = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("GiantRealmLoadState")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/GiantRealmLoadState")

local RealmTransferState = if script ~= nil and script.Parent ~= nil
	then require(
		game:GetService("ReplicatedStorage")
			:WaitForChild("Shared")
			:WaitForChild("GiantRealm")
			:WaitForChild("RealmTransferState")
	)
	else (require :: any)("../../ReplicatedStorage/Shared/GiantRealm/RealmTransferState")

local ProfilePersistenceGateway = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("ProfilePersistenceGateway"))
	else (require :: any)("./ProfilePersistenceGateway")

local GiantRealmLoadService: any = {}
local globalEnv: any = getfenv()

export type LoadDiagnostics = {
	totalLoadAttempts: number,
	totalLoadSucceeded: number,
	totalLoadFailed: number,
	totalReleaseAttempts: number,
	totalReleaseSucceeded: number,
	lastLoadOutcome: string,
	lastReason: string,
	lastOwnerUserId: number?,
}

local loadedRealmByOwnerUserId: { [number]: {
	profileKey: string,
	realmId: string,
	loadOutcome: string,
	recoveryReason: string?,
} } =
	{}

local diagnostics: LoadDiagnostics = {
	totalLoadAttempts = 0,
	totalLoadSucceeded = 0,
	totalLoadFailed = 0,
	totalReleaseAttempts = 0,
	totalReleaseSucceeded = 0,
	lastLoadOutcome = "none",
	lastReason = "not_started",
	lastOwnerUserId = nil,
}

local profileGatewayOverride: any = nil

local function cloneDiagnostics(): LoadDiagnostics
	return {
		totalLoadAttempts = diagnostics.totalLoadAttempts,
		totalLoadSucceeded = diagnostics.totalLoadSucceeded,
		totalLoadFailed = diagnostics.totalLoadFailed,
		totalReleaseAttempts = diagnostics.totalReleaseAttempts,
		totalReleaseSucceeded = diagnostics.totalReleaseSucceeded,
		lastLoadOutcome = diagnostics.lastLoadOutcome,
		lastReason = diagnostics.lastReason,
		lastOwnerUserId = diagnostics.lastOwnerUserId,
	}
end

local function debugLog(message: string)
	print(string.format("[GiantRealmLoadService] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[GiantRealmLoadService] %s", message))
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

local function getProfileGateway(): any
	if profileGatewayOverride ~= nil then
		return profileGatewayOverride
	end
	return ProfilePersistenceGateway
end

local function recordLoadFailure(ownerUserId: number, reason: string)
	diagnostics.totalLoadFailed += 1
	diagnostics.lastLoadOutcome = "failed"
	diagnostics.lastReason = reason
	diagnostics.lastOwnerUserId = ownerUserId
end

function GiantRealmLoadService.ResetForTests()
	loadedRealmByOwnerUserId = {}
	diagnostics = {
		totalLoadAttempts = 0,
		totalLoadSucceeded = 0,
		totalLoadFailed = 0,
		totalReleaseAttempts = 0,
		totalReleaseSucceeded = 0,
		lastLoadOutcome = "none",
		lastReason = "reset",
		lastOwnerUserId = nil,
	}
	profileGatewayOverride = nil
end

function GiantRealmLoadService.SetTestOverrides(overrides: any)
	if type(overrides) ~= "table" then
		return
	end
	if overrides.profileGateway ~= nil then
		profileGatewayOverride = overrides.profileGateway
	end
end

function GiantRealmLoadService.IsRealmLoaded(ownerUserId: any): boolean
	if not isValidUserId(ownerUserId) then
		return false
	end
	return loadedRealmByOwnerUserId[ownerUserId] ~= nil
end

function GiantRealmLoadService.GetLoadedRealmSnapshot(ownerUserId: any): any
	if not isValidUserId(ownerUserId) then
		return {
			accepted = false,
			reason = "owner_user_id_invalid",
		}
	end

	local loaded = loadedRealmByOwnerUserId[ownerUserId]
	if loaded == nil then
		return {
			accepted = false,
			reason = "realm_not_loaded",
		}
	end

	return {
		accepted = true,
		reason = "accepted",
		ownerUserId = ownerUserId,
		profileKey = loaded.profileKey,
		realmId = loaded.realmId,
		loadOutcome = loaded.loadOutcome,
		recoveryReason = loaded.recoveryReason,
	}
end

function GiantRealmLoadService.LoadAndInitialize(ownerUserId: any): any
	if not isValidUserId(ownerUserId) then
		return {
			accepted = false,
			reason = "owner_user_id_invalid",
		}
	end

	diagnostics.totalLoadAttempts += 1
	diagnostics.lastOwnerUserId = ownerUserId

	if loadedRealmByOwnerUserId[ownerUserId] ~= nil then
		recordLoadFailure(ownerUserId, "realm_already_loaded_in_service")
		return {
			accepted = false,
			reason = "realm_already_loaded_in_service",
		}
	end

	local profileKey = GiantRealmLoadConfig.FormatProfileKey(ownerUserId)
	local gateway = getProfileGateway()
	local loadResult = gateway.LoadGiantRealmProfile(ownerUserId)
	if loadResult.ok ~= true then
		local reason = if type(loadResult.reason) == "string"
			then loadResult.reason
			else "load_giant_realm_profile_failed"
		recordLoadFailure(ownerUserId, reason)
		debugWarn(
			string.format(
				"Giant realm load failed ownerUserId=%d profileKey=%s reason=%s",
				ownerUserId,
				profileKey,
				reason
			)
		)
		return {
			accepted = false,
			reason = reason,
			retryable = loadResult.retryable == true,
			profileKey = profileKey,
		}
	end

	local meta = if type(loadResult.meta) == "table" then loadResult.meta else {}
	local loadOutcome = if type(meta.loadOutcome) == "string"
		then meta.loadOutcome
		else GiantRealmLoadState.LoadOutcome.LoadedExisting
	local recoveryReason = if type(meta.recoveryReason) == "string" then meta.recoveryReason else nil
	local realmId = RealmTransferState.FormatRealmId(ownerUserId)

	loadedRealmByOwnerUserId[ownerUserId] = {
		profileKey = profileKey,
		realmId = realmId,
		loadOutcome = loadOutcome,
		recoveryReason = recoveryReason,
	}

	diagnostics.totalLoadSucceeded += 1
	diagnostics.lastLoadOutcome = loadOutcome
	diagnostics.lastReason = if recoveryReason ~= nil then recoveryReason else "accepted"

	debugLog(
		string.format(
			"Giant realm initialized ownerUserId=%d profileKey=%s realmId=%s outcome=%s",
			ownerUserId,
			profileKey,
			realmId,
			loadOutcome
		)
	)

	return {
		accepted = true,
		reason = "accepted",
		ownerUserId = ownerUserId,
		profileKey = profileKey,
		realmId = realmId,
		loadOutcome = loadOutcome,
		recoveryReason = recoveryReason,
		saveRoot = loadResult.data,
	}
end

function GiantRealmLoadService.SaveAndRelease(ownerUserId: any, reason: any?): any
	if not isValidUserId(ownerUserId) then
		return {
			accepted = false,
			reason = "owner_user_id_invalid",
		}
	end

	diagnostics.totalReleaseAttempts += 1
	local cleanupReason = if type(reason) == "string" then reason else "unspecified"

	if loadedRealmByOwnerUserId[ownerUserId] == nil then
		return {
			accepted = false,
			reason = "realm_not_loaded_in_service",
		}
	end

	local gateway = getProfileGateway()
	local saveResult = gateway.SaveGiantRealmProfile(ownerUserId)
	if saveResult.ok ~= true then
		debugWarn(
			string.format(
				"Giant realm save failed ownerUserId=%d reason=%s cleanupReason=%s",
				ownerUserId,
				tostring(saveResult.reason),
				cleanupReason
			)
		)
	end

	local releaseResult = gateway.ReleaseGiantRealmProfile(ownerUserId)
	if releaseResult.ok ~= true then
		debugWarn(
			string.format(
				"Giant realm release failed ownerUserId=%d reason=%s cleanupReason=%s",
				ownerUserId,
				tostring(releaseResult.reason),
				cleanupReason
			)
		)
		return {
			accepted = false,
			reason = if type(releaseResult.reason) == "string"
				then releaseResult.reason
				else "release_giant_realm_failed",
			saveOk = saveResult.ok == true,
		}
	end

	loadedRealmByOwnerUserId[ownerUserId] = nil
	diagnostics.totalReleaseSucceeded += 1
	debugLog(string.format("Giant realm released ownerUserId=%d cleanupReason=%s", ownerUserId, cleanupReason))

	return {
		accepted = true,
		reason = "accepted",
		saveOk = saveResult.ok == true,
	}
end

function GiantRealmLoadService.GetDiagnostics(): LoadDiagnostics
	return cloneDiagnostics()
end

globalEnv._GiantRealmLoadService_QueryAPI = {
	LoadAndInitialize = function(ownerUserId: any): any
		return GiantRealmLoadService.LoadAndInitialize(ownerUserId)
	end,
	SaveAndRelease = function(ownerUserId: any, reason: any?): any
		return GiantRealmLoadService.SaveAndRelease(ownerUserId, reason)
	end,
	IsRealmLoaded = function(ownerUserId: any): boolean
		return GiantRealmLoadService.IsRealmLoaded(ownerUserId)
	end,
	GetLoadedRealmSnapshot = function(ownerUserId: any): any
		return GiantRealmLoadService.GetLoadedRealmSnapshot(ownerUserId)
	end,
	GetDiagnostics = function(): LoadDiagnostics
		return GiantRealmLoadService.GetDiagnostics()
	end,
	ResetForTests = function()
		GiantRealmLoadService.ResetForTests()
	end,
	SetTestOverrides = function(overrides: any)
		GiantRealmLoadService.SetTestOverrides(overrides)
	end,
}

if type(_G) == "table" then
	rawset(_G, "_GiantRealmLoadService_QueryAPI", globalEnv._GiantRealmLoadService_QueryAPI)
end

return GiantRealmLoadService
