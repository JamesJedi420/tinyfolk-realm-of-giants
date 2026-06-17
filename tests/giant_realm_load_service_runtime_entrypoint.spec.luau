--!nocheck

local GiantRealmLoadService = require("../src/ServerScriptService/Services/GiantRealmLoadService")
local GiantRealmLoadState = require("../src/ReplicatedStorage/Shared/GiantRealm/GiantRealmLoadState")
local ProfilePersistenceGateway = require("../src/ServerScriptService/Services/ProfilePersistenceGateway")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

GiantRealmLoadService.ResetForTests()
ProfilePersistenceGateway.ResetForTests()

local ownerUserId = 9501
local loadCalls = 0
local saveCalls = 0
local releaseCalls = 0

local fakeGateway = {
	LoadGiantRealmProfile = function(loadOwnerUserId: number): any
		loadCalls += 1
		return {
			ok = true,
			operation = "LoadGiantRealmProfile",
			profileKey = "GiantRealmProfile:" .. tostring(loadOwnerUserId),
			data = GiantRealmLoadState.BuildDefaultStarterSaveRoot(loadOwnerUserId),
			meta = {
				loadOutcome = GiantRealmLoadState.LoadOutcome.CreatedDefault,
				recovered = true,
				recoveryReason = "missing_or_template_realm",
			},
		}
	end,
	SaveGiantRealmProfile = function(_loadOwnerUserId: number): any
		saveCalls += 1
		return {
			ok = true,
			operation = "SaveGiantRealmProfile",
		}
	end,
	ReleaseGiantRealmProfile = function(_loadOwnerUserId: number): any
		releaseCalls += 1
		return {
			ok = true,
			operation = "ReleaseGiantRealmProfile",
		}
	end,
	ResetForTests = function() end,
}

GiantRealmLoadService.SetTestOverrides({
	profileGateway = fakeGateway,
})

local loadResult = GiantRealmLoadService.LoadAndInitialize(ownerUserId)
assertTrue(loadResult.accepted == true, "load and initialize accepted")
assertEqual(loadResult.loadOutcome, GiantRealmLoadState.LoadOutcome.CreatedDefault, "created default outcome")
assertEqual(loadResult.profileKey, "GiantRealmProfile:9501", "profile key")
assertEqual(loadResult.realmId, "giant_realm_9501", "realm id")
assertTrue(GiantRealmLoadService.IsRealmLoaded(ownerUserId), "realm loaded in service")

local duplicateLoad = GiantRealmLoadService.LoadAndInitialize(ownerUserId)
assertTrue(duplicateLoad.accepted == false, "duplicate service load rejected")
assertEqual(duplicateLoad.reason, "realm_already_loaded_in_service", "duplicate service load reason")

local releaseResult = GiantRealmLoadService.SaveAndRelease(ownerUserId, "test_cleanup")
assertTrue(releaseResult.accepted == true, "save and release accepted")
assertEqual(saveCalls, 1, "save called once")
assertEqual(releaseCalls, 1, "release called once")
assertTrue(GiantRealmLoadService.IsRealmLoaded(ownerUserId) == false, "realm released in service")

print("giant_realm_load_service_runtime_entrypoint: all checks passed")
