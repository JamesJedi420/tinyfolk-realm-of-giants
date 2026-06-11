--!strict

local ProfilePersistenceGateway = require("../src/ServerScriptService/Services/ProfilePersistenceGateway")
local GiantRealmSaveSchema = require("../src/ReplicatedStorage/Shared/GiantRealm/GiantRealmSaveSchema")
local RoleConfig = require("../src/ReplicatedStorage/Shared/Config/RoleConfig")
local SpecialistConfig = require("../src/ReplicatedStorage/Shared/Config/SpecialistConfig")

local function assertTrue(value: boolean, label: string)
	if not value then
		error("assertTrue failed [" .. label .. "]")
	end
end

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(
			string.format("assertEqual failed [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual))
		)
	end
end

local function assertFailure(result: any, operation: string, reason: string, label: string)
	assertEqual(result.ok, false, label .. " ok")
	assertEqual(result.operation, operation, label .. " operation")
	assertEqual(result.reason, reason, label .. " reason")
end

local function assertSuccess(result: any, operation: string, profileKey: string, label: string)
	assertEqual(result.ok, true, label .. " ok")
	assertEqual(result.operation, operation, label .. " operation")
	assertEqual(result.profileKey, profileKey, label .. " profileKey")
end

local function makePlayer(userId: number): any
	return {
		UserId = userId,
	}
end

local function makeOwnerResult(operation: string, profileKey: string, data: any?): any
	return {
		ok = true,
		operation = operation,
		profileKey = profileKey,
		data = data,
	}
end

local function clearGiantQueryApi()
	_G._GiantBuildModeService_QueryAPI = nil
end

local expectedApi = {
	ConfigureOwnerLayer = true,
	ResetForTests = true,
	ResolveEventOutcomeWriteBack = true,
	ResolveReconnectRestoreAction = true,
	GetLoadedPlayerProfileData = true,
	GetLoadedPlayerReputationTitleIds = true,
	UpdateLoadedPlayerProfileData = true,
	LoadPlayerProfile = true,
	LoadDefaultPlayerProfile = true,
	SavePlayerProfile = true,
	ReleasePlayerProfile = true,
	LoadGiantRealmProfile = true,
	SaveGiantRealmProfile = true,
	ReleaseGiantRealmProfile = true,
}

for key, value in pairs(ProfilePersistenceGateway) do
	assertTrue(expectedApi[key] == true, "public API has expected key " .. tostring(key))
	assertTrue(type(value) == "function", "public API value is function " .. tostring(key))
end
for key in pairs(expectedApi) do
	assertTrue(type(ProfilePersistenceGateway[key]) == "function", "public API exposes " .. key)
end

ProfilePersistenceGateway.ResetForTests()
clearGiantQueryApi()

assertFailure(
	ProfilePersistenceGateway.LoadDefaultPlayerProfile(0),
	"LoadDefaultPlayerProfile",
	"invalid_user_id",
	"default invalid id"
)
assertFailure(
	ProfilePersistenceGateway.LoadPlayerProfile({ UserId = 0 }),
	"LoadPlayerProfile",
	"invalid_player_user_id",
	"load player invalid id"
)
assertFailure(
	ProfilePersistenceGateway.SaveGiantRealmProfile("9402"),
	"SaveGiantRealmProfile",
	"invalid_owner_user_id",
	"save realm invalid id"
)
assertFailure(
	ProfilePersistenceGateway.LoadGiantRealmProfile(-10),
	"LoadGiantRealmProfile",
	"invalid_owner_user_id",
	"load realm invalid id"
)

local missingOwner = ProfilePersistenceGateway.LoadPlayerProfile(makePlayer(9402))
assertFailure(missingOwner, "LoadPlayerProfile", "owner_layer_not_configured", "missing owner")
assertEqual(missingOwner.profileKey, "PlayerProfile:9402", "missing owner profile key")
assertEqual(missingOwner.retryable, true, "missing owner retryable")

assertFailure(
	ProfilePersistenceGateway.GetLoadedPlayerProfileData(makePlayer(9402)),
	"GetLoadedPlayerProfileData",
	"player_profile_not_loaded",
	"get before load"
)
assertFailure(
	ProfilePersistenceGateway.UpdateLoadedPlayerProfileData(makePlayer(9402), function(data: any): any
		return data
	end),
	"UpdateLoadedPlayerProfileData",
	"player_profile_not_loaded",
	"update before load"
)

local defaultA = ProfilePersistenceGateway.LoadDefaultPlayerProfile(9402)
local defaultB = ProfilePersistenceGateway.LoadDefaultPlayerProfile(9402)
assertSuccess(defaultA, "LoadDefaultPlayerProfile", "PlayerProfile:9402", "default A")
assertSuccess(defaultB, "LoadDefaultPlayerProfile", "PlayerProfile:9402", "default B")
assertTrue(defaultA.data ~= defaultB.data, "default profile returns separate tables")
assertEqual(defaultA.data.schemaVersion, defaultB.data.schemaVersion, "default schema stable")
assertEqual(defaultA.data.userId, defaultB.data.userId, "default user stable")
assertTrue(type(defaultA.data.roleLoadoutState) == "table", "default role loadout state exists")
assertTrue(type(defaultA.data.roleLoadoutState.selectedByRole) == "table", "default role loadout selectedByRole exists")
assertTrue(type(defaultA.data.roleLoadoutState.selectedByRole.Giant) == "table", "default giant loadout exists")
assertTrue(type(defaultA.data.roleLoadoutState.selectedByRole.Tinyfolk) == "table", "default tinyfolk loadout exists")
assertTrue(type(defaultA.data.tinyfolkToolLoadoutState) == "table", "default tinyfolk tool loadout state exists")
assertEqual(defaultA.data.tinyfolkToolLoadoutState.schemaVersion, 1, "default tinyfolk tool loadout schema version")
assertTrue(
	type(defaultA.data.tinyfolkToolLoadoutState.selectedByRole.Tinyfolk) == "table",
	"default tinyfolk tool selectedByRole exists"
)
defaultA.data.roleLoadoutState.selectedByRole.Giant.passive_1 = "mutated"
defaultA.data.tinyfolkToolLoadoutState.selectedByRole.Tinyfolk.tool_1 = "mutated"
assertTrue(defaultB.data.roleLoadoutState.selectedByRole.Giant.passive_1 == nil, "default loadout tables cloned")
assertTrue(
	defaultB.data.tinyfolkToolLoadoutState.selectedByRole.Tinyfolk.tool_1 == nil,
	"default tinyfolk tool loadout tables cloned"
)
assertTrue(defaultA.data.inventoryCraftState == nil, "default profile omits inventory craft state")
assertTrue(defaultA.data.rolePreference == nil, "default profile omits role preference")
assertTrue(defaultA.data.specialistPreference == nil, "default profile omits specialist preference")

local calls: { any } = {}
local ownerLayer: any = {}

function ownerLayer.LoadPlayerProfile(profileKey: string, userId: number): any
	table.insert(calls, { method = "LoadPlayerProfile", profileKey = profileKey, userId = userId })
	return makeOwnerResult("LoadPlayerProfile", profileKey, {
		userId = userId,
		loaded = true,
		counters = {
			coins = 10,
		},
	})
end

function ownerLayer.SavePlayerProfile(profileKey: string, userId: number, data: any): any
	table.insert(calls, { method = "SavePlayerProfile", profileKey = profileKey, userId = userId, data = data })
	return makeOwnerResult("SavePlayerProfile", profileKey, data)
end

function ownerLayer.ReleasePlayerProfile(profileKey: string, userId: number): any
	table.insert(calls, { method = "ReleasePlayerProfile", profileKey = profileKey, userId = userId })
	return makeOwnerResult("ReleasePlayerProfile", profileKey, nil)
end

function ownerLayer.LoadGiantRealmProfile(profileKey: string, ownerUserId: number): any
	table.insert(calls, { method = "LoadGiantRealmProfile", profileKey = profileKey, ownerUserId = ownerUserId })
	return makeOwnerResult("LoadGiantRealmProfile", profileKey, {
		schemaVersion = 1,
		ownerUserId = ownerUserId,
		placedStructures = {},
	})
end

function ownerLayer.SaveGiantRealmProfile(profileKey: string, ownerUserId: number, saveRoot: any): any
	table.insert(calls, {
		method = "SaveGiantRealmProfile",
		profileKey = profileKey,
		ownerUserId = ownerUserId,
		saveRoot = saveRoot,
	})
	return makeOwnerResult("SaveGiantRealmProfile", profileKey, saveRoot)
end

function ownerLayer.ReleaseGiantRealmProfile(profileKey: string, ownerUserId: number): any
	table.insert(calls, { method = "ReleaseGiantRealmProfile", profileKey = profileKey, ownerUserId = ownerUserId })
	return makeOwnerResult("ReleaseGiantRealmProfile", profileKey, nil)
end

ProfilePersistenceGateway.ConfigureOwnerLayer(ownerLayer)

local player = makePlayer(9402)
assertSuccess(
	ProfilePersistenceGateway.LoadPlayerProfile(player),
	"LoadPlayerProfile",
	"PlayerProfile:9402",
	"load player"
)
assertEqual(calls[1].method, "LoadPlayerProfile", "load owner method")
assertEqual(calls[1].profileKey, "PlayerProfile:9402", "load owner key")
assertEqual(calls[1].userId, 9402, "load owner id")

local loadedProfile = ProfilePersistenceGateway.GetLoadedPlayerProfileData(player)
assertSuccess(loadedProfile, "GetLoadedPlayerProfileData", "PlayerProfile:9402", "get loaded")
assertEqual(loadedProfile.data.userId, 9402, "get loaded user id")
assertEqual(loadedProfile.data.counters.coins, 10, "get loaded nested data")

loadedProfile.data.loaded = false
loadedProfile.data.counters.coins = 999
local loadedProfileAgain = ProfilePersistenceGateway.GetLoadedPlayerProfileData(player)
assertEqual(loadedProfileAgain.data.loaded, true, "get clone does not mutate active boolean")
assertEqual(loadedProfileAgain.data.counters.coins, 10, "get clone does not mutate active nested")

local updaterReceivedData: any = nil
local updateResult = ProfilePersistenceGateway.UpdateLoadedPlayerProfileData(player, function(currentData: any): any
	updaterReceivedData = currentData
	currentData.counters.coins = 25
	if type(currentData.roleLoadoutState) ~= "table" then
		currentData.roleLoadoutState = { selectedByRole = {} }
	end
	if type(currentData.roleLoadoutState.selectedByRole) ~= "table" then
		currentData.roleLoadoutState.selectedByRole = {}
	end
	currentData.roleLoadoutState.selectedByRole.Giant = {
		passive_1 = "Giant_Builder_WorksiteEfficiency",
	}
	currentData.inventoryCraftState = {
		schemaVersion = 1,
		itemCounts = {
			iron_filings = 3,
		},
	}
	return currentData
end)
assertSuccess(updateResult, "UpdateLoadedPlayerProfileData", "PlayerProfile:9402", "update loaded")
assertEqual(updateResult.data.counters.coins, 25, "update result data")
assertEqual(
	updateResult.data.roleLoadoutState.selectedByRole.Giant.passive_1,
	"Giant_Builder_WorksiteEfficiency",
	"update result loadout data"
)
assertEqual(updateResult.data.inventoryCraftState.itemCounts.iron_filings, 3, "update result inventory craft data")
updaterReceivedData.counters.coins = 333
updaterReceivedData.roleLoadoutState.selectedByRole.Giant.passive_1 = "tampered"
local afterUpdaterMutation = ProfilePersistenceGateway.GetLoadedPlayerProfileData(player)
assertEqual(afterUpdaterMutation.data.counters.coins, 25, "updater receives clone")
assertEqual(
	afterUpdaterMutation.data.roleLoadoutState.selectedByRole.Giant.passive_1,
	"Giant_Builder_WorksiteEfficiency",
	"updater loadout receives clone"
)

local failedUpdate = ProfilePersistenceGateway.UpdateLoadedPlayerProfileData(player, function(_currentData: any): any
	return nil, "refused_by_test"
end)
assertFailure(failedUpdate, "UpdateLoadedPlayerProfileData", "refused_by_test", "update failure")
local afterFailedUpdate = ProfilePersistenceGateway.GetLoadedPlayerProfileData(player)
assertEqual(afterFailedUpdate.data.counters.coins, 25, "update failure does not mutate active")

assertFailure(
	ProfilePersistenceGateway.UpdateLoadedPlayerProfileData(player, "not a function"),
	"UpdateLoadedPlayerProfileData",
	"profile_update_updater_invalid",
	"invalid updater"
)
assertFailure(
	ProfilePersistenceGateway.UpdateLoadedPlayerProfileData(player, function(_currentData: any): any
		return "not profile data"
	end),
	"UpdateLoadedPlayerProfileData",
	"profile_update_data_invalid",
	"invalid returned data"
)
assertFailure(
	ProfilePersistenceGateway.UpdateLoadedPlayerProfileData(player, function(_currentData: any): any
		error("boom")
		return nil
	end),
	"UpdateLoadedPlayerProfileData",
	"profile_update_failed",
	"updater error"
)

assertSuccess(
	ProfilePersistenceGateway.SavePlayerProfile(player),
	"SavePlayerProfile",
	"PlayerProfile:9402",
	"save player"
)
assertEqual(calls[2].method, "SavePlayerProfile", "save owner method")
assertEqual(calls[2].profileKey, "PlayerProfile:9402", "save owner key")
assertEqual(calls[2].userId, 9402, "save owner id")
assertEqual(calls[2].data.loaded, true, "save owner uses loaded data")
assertEqual(calls[2].data.counters.coins, 25, "save owner uses updated active data")
assertEqual(
	calls[2].data.roleLoadoutState.selectedByRole.Giant.passive_1,
	"Giant_Builder_WorksiteEfficiency",
	"save owner uses updated loadout data"
)
assertEqual(
	calls[2].data.inventoryCraftState.itemCounts.iron_filings,
	3,
	"save owner uses updated inventory craft data"
)

assertSuccess(
	ProfilePersistenceGateway.ReleasePlayerProfile(player),
	"ReleasePlayerProfile",
	"PlayerProfile:9402",
	"release player"
)
assertEqual(calls[3].method, "ReleasePlayerProfile", "release owner method")
assertEqual(calls[3].profileKey, "PlayerProfile:9402", "release owner key")
assertEqual(calls[3].userId, 9402, "release owner id")
assertFailure(
	ProfilePersistenceGateway.GetLoadedPlayerProfileData(player),
	"GetLoadedPlayerProfileData",
	"player_profile_not_loaded",
	"get after release"
)
assertFailure(
	ProfilePersistenceGateway.UpdateLoadedPlayerProfileData(player, function(data: any): any
		return data
	end),
	"UpdateLoadedPlayerProfileData",
	"player_profile_not_loaded",
	"update after release"
)

assertFailure(
	ProfilePersistenceGateway.SaveGiantRealmProfile(9402),
	"SaveGiantRealmProfile",
	"giant_build_mode_query_api_missing",
	"missing query API save"
)
assertFailure(
	ProfilePersistenceGateway.LoadGiantRealmProfile(9402),
	"LoadGiantRealmProfile",
	"giant_build_mode_query_api_missing",
	"missing query API load"
)

calls = {}
local queryCalls: { any } = {}
local saveRoot = {
	schemaVersion = 1,
	ownerUserId = 9402,
	placedStructures = {},
}

_G._GiantBuildModeService_QueryAPI = {
	BuildSaveSnapshot = function(ownerUserId: number): (any?, string?)
		table.insert(queryCalls, { method = "BuildSaveSnapshot", ownerUserId = ownerUserId })
		return saveRoot, nil
	end,
	ApplySaveSnapshot = function(root: any): (boolean, string?)
		table.insert(queryCalls, { method = "ApplySaveSnapshot", saveRoot = root })
		return true, nil
	end,
}

local saveRealm = ProfilePersistenceGateway.SaveGiantRealmProfile(9402)
assertSuccess(saveRealm, "SaveGiantRealmProfile", "GiantRealmProfile:9402", "save realm")
assertEqual(queryCalls[1].method, "BuildSaveSnapshot", "save realm build method")
assertEqual(queryCalls[1].ownerUserId, 9402, "save realm build owner")
assertEqual(calls[1].method, "SaveGiantRealmProfile", "save realm owner method")
assertEqual(calls[1].profileKey, "GiantRealmProfile:9402", "save realm owner key")
assertEqual(calls[1].ownerUserId, 9402, "save realm owner id")
assertTrue(calls[1].saveRoot == saveRoot, "save realm passes built root")

local loadRealm = ProfilePersistenceGateway.LoadGiantRealmProfile(9402)
assertSuccess(loadRealm, "LoadGiantRealmProfile", "GiantRealmProfile:9402", "load realm")
assertEqual(calls[2].method, "LoadGiantRealmProfile", "load realm owner method")
assertEqual(calls[2].profileKey, "GiantRealmProfile:9402", "load realm owner key")
assertEqual(calls[2].ownerUserId, 9402, "load realm owner id")
assertEqual(queryCalls[2].method, "ApplySaveSnapshot", "load realm apply method")
assertTrue(queryCalls[2].saveRoot == loadRealm.data, "load realm applies owner save root")

local malformedRoot = {
	schemaVersion = 1,
	ownerUserId = 9402,
	placedStructures = {},
	emergencyReinforcement = {
		used = "bad",
	},
}

local originalApplySaveSnapshot = _G._GiantBuildModeService_QueryAPI.ApplySaveSnapshot
_G._GiantBuildModeService_QueryAPI.ApplySaveSnapshot = function(root: any): (boolean, string?)
	local valid, reason = GiantRealmSaveSchema.ValidateSaveRoot(root)
	if not valid then
		return false, reason
	end

	return true, nil
end

ProfilePersistenceGateway.ConfigureOwnerLayer({
	LoadPlayerProfile = ownerLayer.LoadPlayerProfile,
	SavePlayerProfile = ownerLayer.SavePlayerProfile,
	ReleasePlayerProfile = ownerLayer.ReleasePlayerProfile,
	LoadGiantRealmProfile = function(profileKey: string, _ownerUserId: number): any
		return makeOwnerResult("LoadGiantRealmProfile", profileKey, malformedRoot)
	end,
	SaveGiantRealmProfile = ownerLayer.SaveGiantRealmProfile,
	ReleaseGiantRealmProfile = ownerLayer.ReleaseGiantRealmProfile,
})

assertFailure(
	ProfilePersistenceGateway.LoadGiantRealmProfile(9402),
	"LoadGiantRealmProfile",
	"emergency_reinforcement_used_invalid",
	"load realm malformed emergency record"
)

_G._GiantBuildModeService_QueryAPI.ApplySaveSnapshot = originalApplySaveSnapshot

local releaseRealm = ProfilePersistenceGateway.ReleaseGiantRealmProfile(9402)
assertSuccess(releaseRealm, "ReleaseGiantRealmProfile", "GiantRealmProfile:9402", "release realm")
assertEqual(calls[3].method, "ReleaseGiantRealmProfile", "release realm owner method")
assertEqual(calls[3].profileKey, "GiantRealmProfile:9402", "release realm owner key")
assertEqual(calls[3].ownerUserId, 9402, "release realm owner id")

ProfilePersistenceGateway.ConfigureOwnerLayer({
	LoadPlayerProfile = ownerLayer.LoadPlayerProfile,
	SavePlayerProfile = ownerLayer.SavePlayerProfile,
	ReleasePlayerProfile = ownerLayer.ReleasePlayerProfile,
	ReleaseGiantRealmProfile = ownerLayer.ReleaseGiantRealmProfile,
	LoadGiantRealmProfile = function(profileKey: string, _ownerUserId: number): any
		return {
			ok = false,
			operation = "LoadGiantRealmProfile",
			reason = "mock_owner_load_failed",
			retryable = true,
			profileKey = profileKey,
		}
	end,
	SaveGiantRealmProfile = function(profileKey: string, _ownerUserId: number, _saveRoot: any): any
		return {
			ok = false,
			operation = "SaveGiantRealmProfile",
			reason = "mock_owner_save_failed",
			retryable = true,
			profileKey = profileKey,
		}
	end,
})

assertFailure(
	ProfilePersistenceGateway.SaveGiantRealmProfile(9402),
	"SaveGiantRealmProfile",
	"mock_owner_save_failed",
	"owner save failure propagates"
)
assertFailure(
	ProfilePersistenceGateway.LoadGiantRealmProfile(9402),
	"LoadGiantRealmProfile",
	"mock_owner_load_failed",
	"owner load failure propagates"
)

ProfilePersistenceGateway.ConfigureOwnerLayer({
	LoadPlayerProfile = ownerLayer.LoadPlayerProfile,
	SavePlayerProfile = ownerLayer.SavePlayerProfile,
	ReleasePlayerProfile = ownerLayer.ReleasePlayerProfile,
	ReleaseGiantRealmProfile = ownerLayer.ReleaseGiantRealmProfile,
	LoadGiantRealmProfile = function(profileKey: string, _ownerUserId: number): any
		return makeOwnerResult("LoadGiantRealmProfile", profileKey, nil)
	end,
	SaveGiantRealmProfile = ownerLayer.SaveGiantRealmProfile,
})

assertFailure(
	ProfilePersistenceGateway.LoadGiantRealmProfile(9402),
	"LoadGiantRealmProfile",
	"giant_realm_save_root_missing",
	"owner load missing save root"
)

ProfilePersistenceGateway.ConfigureOwnerLayer({
	LoadPlayerProfile = function(profileKey: string, userId: number): any
		return makeOwnerResult("LoadPlayerProfile", profileKey, {
			userId = userId,
			specialistPreference = {
				specialistRole = SpecialistConfig.SpecialistRoles.Miner,
				assignedStationId = "MiningStation_A",
				lastAssignedAt = 100,
				invalidRole = "InvalidRole",
			},
			counters = {
				coins = 1,
			},
		})
	end,
	SavePlayerProfile = ownerLayer.SavePlayerProfile,
	ReleasePlayerProfile = ownerLayer.ReleasePlayerProfile,
	LoadGiantRealmProfile = ownerLayer.LoadGiantRealmProfile,
	SaveGiantRealmProfile = ownerLayer.SaveGiantRealmProfile,
	ReleaseGiantRealmProfile = ownerLayer.ReleaseGiantRealmProfile,
})

local specialistSanitizePlayer = makePlayer(9403)
assertSuccess(
	ProfilePersistenceGateway.LoadPlayerProfile(specialistSanitizePlayer),
	"LoadPlayerProfile",
	"PlayerProfile:9403",
	"load specialist sanitize player"
)
local loadedSpecialistProfile = ProfilePersistenceGateway.GetLoadedPlayerProfileData(specialistSanitizePlayer)
assertSuccess(loadedSpecialistProfile, "GetLoadedPlayerProfileData", "PlayerProfile:9403", "get specialist sanitize")
assertEqual(
	loadedSpecialistProfile.data.specialistPreference.specialistRole,
	SpecialistConfig.SpecialistRoles.Miner,
	"load sanitizes specialist role"
)
assertEqual(
	loadedSpecialistProfile.data.specialistPreference.assignedStationId,
	"MiningStation_A",
	"load keeps valid assigned station"
)
assertEqual(loadedSpecialistProfile.data.specialistPreference.lastAssignedAt, 100, "load keeps valid timestamp")
assertTrue(loadedSpecialistProfile.data.counters.coins == 1, "load keeps non-preference profile fields")

ProfilePersistenceGateway.ConfigureOwnerLayer({
	LoadPlayerProfile = function(profileKey: string, userId: number): any
		return makeOwnerResult("LoadPlayerProfile", profileKey, {
			userId = userId,
			rolePreference = {
				preferredRole = RoleConfig.Roles.Tinyfolk,
				invalidField = "ignored",
			},
			counters = {
				coins = 2,
			},
		})
	end,
	SavePlayerProfile = ownerLayer.SavePlayerProfile,
	ReleasePlayerProfile = ownerLayer.ReleasePlayerProfile,
	LoadGiantRealmProfile = ownerLayer.LoadGiantRealmProfile,
	SaveGiantRealmProfile = ownerLayer.SaveGiantRealmProfile,
	ReleaseGiantRealmProfile = ownerLayer.ReleaseGiantRealmProfile,
})

local roleSanitizePlayer = makePlayer(9404)
assertSuccess(
	ProfilePersistenceGateway.LoadPlayerProfile(roleSanitizePlayer),
	"LoadPlayerProfile",
	"PlayerProfile:9404",
	"load role sanitize player"
)
local loadedRoleProfile = ProfilePersistenceGateway.GetLoadedPlayerProfileData(roleSanitizePlayer)
assertSuccess(loadedRoleProfile, "GetLoadedPlayerProfileData", "PlayerProfile:9404", "get role sanitize")
assertEqual(
	loadedRoleProfile.data.rolePreference.preferredRole,
	RoleConfig.Roles.Tinyfolk,
	"load sanitizes preferred role"
)
assertTrue(loadedRoleProfile.data.rolePreference.invalidField == nil, "load drops invalid role preference fields")
assertTrue(loadedRoleProfile.data.counters.coins == 2, "load keeps non-preference profile fields for role sanitize")

ProfilePersistenceGateway.ConfigureOwnerLayer({
	LoadPlayerProfile = function(profileKey: string, userId: number): any
		return makeOwnerResult("LoadPlayerProfile", profileKey, {
			userId = userId,
			rolePreference = {
				preferredRole = "NotARealRole",
			},
		})
	end,
	SavePlayerProfile = ownerLayer.SavePlayerProfile,
	ReleasePlayerProfile = ownerLayer.ReleasePlayerProfile,
	LoadGiantRealmProfile = ownerLayer.LoadGiantRealmProfile,
	SaveGiantRealmProfile = ownerLayer.SaveGiantRealmProfile,
	ReleaseGiantRealmProfile = ownerLayer.ReleaseGiantRealmProfile,
})

local invalidRoleSanitizePlayer = makePlayer(9405)
assertSuccess(
	ProfilePersistenceGateway.LoadPlayerProfile(invalidRoleSanitizePlayer),
	"LoadPlayerProfile",
	"PlayerProfile:9405",
	"load invalid role sanitize player"
)
local loadedInvalidRoleProfile = ProfilePersistenceGateway.GetLoadedPlayerProfileData(invalidRoleSanitizePlayer)
assertSuccess(loadedInvalidRoleProfile, "GetLoadedPlayerProfileData", "PlayerProfile:9405", "get invalid role sanitize")
assertTrue(loadedInvalidRoleProfile.data.rolePreference == nil, "load drops invalid preferred role")

ProfilePersistenceGateway.ConfigureOwnerLayer(ownerLayer)

clearGiantQueryApi()
ProfilePersistenceGateway.ResetForTests()

print("profile_persistence_gateway: all checks passed")
