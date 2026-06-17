--!strict

local ProfilePersistenceGateway = require("../src/ServerScriptService/Services/ProfilePersistenceGateway")
local ProfileStoreOwnerLayer = require("../src/ServerScriptService/Services/ProfileStoreOwnerLayer")

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

local function assertCreateError(config: any, expectedMessage: string, label: string)
	local ok, err = pcall(function()
		ProfileStoreOwnerLayer.Create(config)
	end)
	assertEqual(ok, false, label .. " pcall")
	assertTrue(string.find(tostring(err), expectedMessage, 1, true) ~= nil, label .. " error")
end

local function makePlayer(userId: number): any
	return {
		UserId = userId,
	}
end

local function makeFakeProfileStoreModule(startSessionImpl: ((string, any) -> any)?): any
	local calls: { any } = {}
	local profilesByKey: { [string]: any } = {}
	local function parseUserIdFromProfileKey(profileKey: string): number
		local value = string.match(profileKey, ":(%d+)$")
		if value == nil then
			return 0
		end
		local numeric = tonumber(value)
		if type(numeric) ~= "number" then
			return 0
		end
		return numeric :: number
	end

	local playerStore = {}
	function playerStore:StartSessionAsync(profileKey: string, params: any): any
		table.insert(calls, {
			method = "StartSessionAsync",
			profileKey = profileKey,
			params = params,
		})
		if startSessionImpl ~= nil then
			return startSessionImpl(profileKey, params)
		end

		local initialData: any = {
			userId = 0,
			coins = 0,
		}
		if string.sub(profileKey, 1, 18) == "GiantRealmProfile:" then
			initialData = {
				schemaVersion = 1,
				ownerUserId = parseUserIdFromProfileKey(profileKey),
				placedStructures = {},
			}
		end

		local profile = {
			Data = initialData,
			endSessionCount = 0,
		}
		function profile.EndSession(_profile: any)
			_profile.endSessionCount += 1
		end

		profilesByKey[profileKey] = profile
		return profile
	end

	local module = {
		newCalls = {},
		calls = calls,
		profilesByKey = profilesByKey,
		playerStore = playerStore,
	}

	function module.New(storeName: string, template: any): any
		table.insert(module.newCalls, {
			storeName = storeName,
			template = template,
		})
		return playerStore
	end

	return module
end

local requiredMethods = {
	LoadPlayerProfile = true,
	SavePlayerProfile = true,
	ReleasePlayerProfile = true,
	LoadGiantRealmProfile = true,
	SaveGiantRealmProfile = true,
	ReleaseGiantRealmProfile = true,
}

ProfileStoreOwnerLayer.ResetForTests()

assertTrue(type(ProfileStoreOwnerLayer.Create) == "function", "module exposes Create")
assertTrue(type(ProfileStoreOwnerLayer.ResetForTests) == "function", "module exposes ResetForTests")

assertCreateError(nil, "config_missing", "missing config")
assertCreateError({}, "profile_store_module_missing", "missing profile store module")
assertCreateError({ profileStoreModule = {} }, "profile_store_new_missing", "missing New")
assertCreateError({
	profileStoreModule = { New = function() end },
	playerStoreName = "",
	playerProfileTemplate = {},
	giantRealmStoreName = "GiantRealmProfiles",
	giantRealmProfileTemplate = {},
}, "player_store_name_invalid", "invalid store name")
assertCreateError({
	profileStoreModule = { New = function() end },
	playerStoreName = "PlayerProfiles",
}, "player_profile_template_invalid", "invalid template")
assertCreateError({
	profileStoreModule = { New = function() end },
	playerStoreName = "PlayerProfiles",
	playerProfileTemplate = {},
	giantRealmStoreName = "",
	giantRealmProfileTemplate = {},
}, "giant_realm_store_name_invalid", "invalid giant realm store name")
assertCreateError({
	profileStoreModule = { New = function() end },
	playerStoreName = "PlayerProfiles",
	playerProfileTemplate = {},
	giantRealmStoreName = "GiantRealmProfiles",
}, "giant_realm_profile_template_invalid", "invalid giant realm template")

local fakeProfileStore = makeFakeProfileStoreModule(nil)
local validatorCalls: { any } = {}
local ownerLayer = ProfileStoreOwnerLayer.Create({
	profileStoreModule = fakeProfileStore,
	playerStoreName = "TinyfolkPlayerProfiles",
	playerProfileTemplate = {
		schemaVersion = 1,
		coins = 0,
	},
	giantRealmStoreName = "TinyfolkGiantRealmProfiles",
	giantRealmProfileTemplate = {
		schemaVersion = 1,
		ownerUserId = 0,
		placedStructures = {},
	},
	validateGiantRealmSaveRoot = function(saveRoot: any): (boolean, string?)
		table.insert(validatorCalls, {
			ownerUserId = saveRoot and saveRoot.ownerUserId,
			schemaVersion = saveRoot and saveRoot.schemaVersion,
		})
		if type(saveRoot) ~= "table" then
			return false, "save_root_invalid"
		end
		if type(saveRoot.schemaVersion) ~= "number" then
			return false, "schema_version_invalid"
		end
		if type(saveRoot.ownerUserId) ~= "number" or saveRoot.ownerUserId <= 0 or saveRoot.ownerUserId % 1 ~= 0 then
			return false, "owner_user_id_invalid"
		end
		if type(saveRoot.placedStructures) ~= "table" then
			return false, "placed_structures_invalid"
		end

		return true, nil
	end,
})

for methodName in pairs(requiredMethods) do
	assertTrue(type(ownerLayer[methodName]) == "function", "owner layer exposes " .. methodName)
end
assertEqual(#fakeProfileStore.newCalls, 2, "ProfileStore.New called twice")
assertEqual(fakeProfileStore.newCalls[1].storeName, "TinyfolkPlayerProfiles", "store name")
assertEqual(fakeProfileStore.newCalls[1].template.schemaVersion, 1, "template schema")
assertEqual(fakeProfileStore.newCalls[2].storeName, "TinyfolkGiantRealmProfiles", "giant realm store name")
assertEqual(fakeProfileStore.newCalls[2].template.schemaVersion, 1, "giant realm template schema")

local loadResult = ownerLayer.LoadPlayerProfile("PlayerProfile:9402", 9402)
assertSuccess(loadResult, "LoadPlayerProfile", "PlayerProfile:9402", "load profile")
assertEqual(#fakeProfileStore.calls, 1, "start session call count")
assertEqual(fakeProfileStore.calls[1].method, "StartSessionAsync", "start session method")
assertEqual(fakeProfileStore.calls[1].profileKey, "PlayerProfile:9402", "start session key")
assertTrue(type(fakeProfileStore.calls[1].params) == "table", "start session params")

local activeProfile = fakeProfileStore.profilesByKey["PlayerProfile:9402"]
assertTrue(activeProfile ~= nil, "active profile stored in fake")
assertTrue(loadResult.data == activeProfile.Data, "load returns profile data")

local saveData = {
	userId = 9402,
	coins = 45,
	nested = {
		level = 3,
	},
}
local saveResult = ownerLayer.SavePlayerProfile("PlayerProfile:9402", 9402, saveData)
assertSuccess(saveResult, "SavePlayerProfile", "PlayerProfile:9402", "save profile")
assertEqual(activeProfile.Data.userId, 9402, "saved user id")
assertEqual(activeProfile.Data.coins, 45, "saved coins")
assertEqual(activeProfile.Data.nested.level, 3, "saved nested")
assertTrue(activeProfile.Data ~= saveData, "save clones data")

local duplicateLoad = ownerLayer.LoadPlayerProfile("PlayerProfile:9402", 9402)
assertFailure(duplicateLoad, "LoadPlayerProfile", "profile_session_already_active", "duplicate load")
assertEqual(#fakeProfileStore.calls, 1, "duplicate load does not start session")

local releaseResult = ownerLayer.ReleasePlayerProfile("PlayerProfile:9402", 9402)
assertSuccess(releaseResult, "ReleasePlayerProfile", "PlayerProfile:9402", "release profile")
assertEqual(activeProfile.endSessionCount, 1, "release ends session")

local saveAfterRelease = ownerLayer.SavePlayerProfile("PlayerProfile:9402", 9402, saveData)
assertFailure(saveAfterRelease, "SavePlayerProfile", "profile_session_not_active", "save after release")

local reloadResult = ownerLayer.LoadPlayerProfile("PlayerProfile:9402", 9402)
assertSuccess(reloadResult, "LoadPlayerProfile", "PlayerProfile:9402", "reload after release")
assertEqual(#fakeProfileStore.calls, 2, "reload starts second session")

local failingOwnerLayer = ProfileStoreOwnerLayer.Create({
	profileStoreModule = makeFakeProfileStoreModule(function(_profileKey: string, _params: any): any
		return nil
	end),
	playerStoreName = "TinyfolkPlayerProfiles",
	playerProfileTemplate = {},
	giantRealmStoreName = "TinyfolkGiantRealmProfiles",
	giantRealmProfileTemplate = {},
})
local failedLoad = failingOwnerLayer.LoadPlayerProfile("PlayerProfile:1001", 1001)
assertFailure(failedLoad, "LoadPlayerProfile", "profile_session_start_failed", "failed start session")
assertEqual(failedLoad.retryable, true, "failed start session retryable")

local giantLoad = ownerLayer.LoadGiantRealmProfile("GiantRealmProfile:9402", 9402)
assertSuccess(giantLoad, "LoadGiantRealmProfile", "GiantRealmProfile:9402", "giant load")
assertTrue(type(giantLoad.data) == "table", "giant load returns data")
assertEqual(#validatorCalls, 1, "giant load validates root")
assertEqual(validatorCalls[1].ownerUserId, 9402, "giant load validator sees owner")

local giantSaveRoot = {
	schemaVersion = 1,
	ownerUserId = 9402,
	placedStructures = {},
}
local giantSave = ownerLayer.SaveGiantRealmProfile("GiantRealmProfile:9402", 9402, giantSaveRoot)
assertSuccess(giantSave, "SaveGiantRealmProfile", "GiantRealmProfile:9402", "giant save")
assertTrue(giantSave.data ~= giantSaveRoot, "giant save clones root")
assertEqual(#validatorCalls, 2, "giant save validates root")
assertEqual(validatorCalls[2].ownerUserId, 9402, "giant save validator sees owner")

local invalidGiantSave = ownerLayer.SaveGiantRealmProfile("GiantRealmProfile:9402", 9402, {
	ownerUserId = 9402,
	placedStructures = {},
})
assertFailure(invalidGiantSave, "SaveGiantRealmProfile", "schema_version_invalid", "giant save invalid root")
assertEqual(#validatorCalls, 3, "giant save invalid root still validated")

local duplicateGiantLoad = ownerLayer.LoadGiantRealmProfile("GiantRealmProfile:9402", 9402)
assertFailure(duplicateGiantLoad, "LoadGiantRealmProfile", "profile_session_already_active", "duplicate giant load")

local giantRelease = ownerLayer.ReleaseGiantRealmProfile("GiantRealmProfile:9402", 9402)
assertSuccess(giantRelease, "ReleaseGiantRealmProfile", "GiantRealmProfile:9402", "giant release")

local giantSaveAfterRelease = ownerLayer.SaveGiantRealmProfile("GiantRealmProfile:9402", 9402, giantSaveRoot)
assertFailure(giantSaveAfterRelease, "SaveGiantRealmProfile", "profile_session_not_active", "giant save after release")

local invalidLoadOwnerLayer = ProfileStoreOwnerLayer.Create({
	profileStoreModule = makeFakeProfileStoreModule(function(_profileKey: string, _params: any): any
		local profile = {
			Data = {
				schemaVersion = "bad",
				ownerUserId = 1111,
				placedStructures = {},
			},
			endSessionCount = 0,
		}
		function profile.EndSession(_profile: any)
			_profile.endSessionCount += 1
		end
		return profile
	end),
	playerStoreName = "TinyfolkPlayerProfiles",
	playerProfileTemplate = {},
	giantRealmStoreName = "TinyfolkGiantRealmProfiles",
	giantRealmProfileTemplate = {},
	validateGiantRealmSaveRoot = function(saveRoot: any): (boolean, string?)
		if type(saveRoot) ~= "table" then
			return false, "save_root_invalid"
		end
		if type(saveRoot.schemaVersion) ~= "number" then
			return false, "schema_version_invalid"
		end
		return true, nil
	end,
})
local invalidGiantLoad = invalidLoadOwnerLayer.LoadGiantRealmProfile("GiantRealmProfile:1111", 1111)
assertSuccess(invalidGiantLoad, "LoadGiantRealmProfile", "GiantRealmProfile:1111", "giant load recovers invalid root")
assertTrue(type(invalidGiantLoad.meta) == "table", "giant load recovery meta present")
assertEqual(invalidGiantLoad.meta.loadOutcome, "recovered_corrupt", "giant load recovery outcome")
assertEqual(invalidGiantLoad.data.ownerUserId, 1111, "giant load recovery owner user id")

ProfilePersistenceGateway.ResetForTests()
ProfilePersistenceGateway.ConfigureOwnerLayer(ProfileStoreOwnerLayer.Create({
	profileStoreModule = makeFakeProfileStoreModule(nil),
	playerStoreName = "TinyfolkPlayerProfiles",
	playerProfileTemplate = {},
	giantRealmStoreName = "TinyfolkGiantRealmProfiles",
	giantRealmProfileTemplate = {},
}))
local gatewayLoad = ProfilePersistenceGateway.LoadPlayerProfile(makePlayer(7777))
assertSuccess(gatewayLoad, "LoadPlayerProfile", "PlayerProfile:7777", "gateway load")
assertTrue(type(gatewayLoad.data) == "table", "gateway load data")
local gatewaySave = ProfilePersistenceGateway.SavePlayerProfile(makePlayer(7777))
assertSuccess(gatewaySave, "SavePlayerProfile", "PlayerProfile:7777", "gateway save")
local gatewayRelease = ProfilePersistenceGateway.ReleasePlayerProfile(makePlayer(7777))
assertSuccess(gatewayRelease, "ReleasePlayerProfile", "PlayerProfile:7777", "gateway release")
ProfilePersistenceGateway.ResetForTests()

print("profile_store_owner_layer: all checks passed")
