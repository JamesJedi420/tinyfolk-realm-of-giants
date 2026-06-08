--!nocheck

local ProfilePersistenceGateway = require("../src/ServerScriptService/Services/ProfilePersistenceGateway")
local ReputationState = require("../src/ReplicatedStorage/Shared/Reputation/ReputationState")
local TraitRegistrySchema = require("../src/ReplicatedStorage/Shared/Config/TraitRegistrySchema")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(condition: boolean, label: string)
	assertEqual(condition, true, label)
end

local function makePlayer(userId: number): any
	return {
		UserId = userId,
	}
end

local function makeOwnerLayer(profileDataByUserId: { [number]: any }): any
	return {
		LoadPlayerProfile = function(profileKey: string, userId: number): any
			local data = profileDataByUserId[userId]
			if type(data) ~= "table" then
				return {
					ok = false,
					operation = "LoadPlayerProfile",
					reason = "profile_not_found",
					retryable = false,
					profileKey = profileKey,
				}
			end
			return {
				ok = true,
				operation = "LoadPlayerProfile",
				reason = nil,
				retryable = nil,
				profileKey = profileKey,
				data = data,
			}
		end,
		SavePlayerProfile = function(profileKey: string, _userId: number, data: any): any
			return {
				ok = true,
				operation = "SavePlayerProfile",
				reason = nil,
				retryable = nil,
				profileKey = profileKey,
				data = data,
			}
		end,
		ReleasePlayerProfile = function(profileKey: string, _userId: number): any
			return {
				ok = true,
				operation = "ReleasePlayerProfile",
				reason = nil,
				retryable = nil,
				profileKey = profileKey,
			}
		end,
		LoadGiantRealmProfile = function(profileKey: string, _ownerUserId: number): any
			return {
				ok = true,
				operation = "LoadGiantRealmProfile",
				reason = nil,
				retryable = nil,
				profileKey = profileKey,
				data = {},
			}
		end,
		SaveGiantRealmProfile = function(profileKey: string, _ownerUserId: number, saveRoot: any): any
			return {
				ok = true,
				operation = "SaveGiantRealmProfile",
				reason = nil,
				retryable = nil,
				profileKey = profileKey,
				data = saveRoot,
			}
		end,
		ReleaseGiantRealmProfile = function(profileKey: string, _ownerUserId: number): any
			return {
				ok = true,
				operation = "ReleaseGiantRealmProfile",
				reason = nil,
				retryable = nil,
				profileKey = profileKey,
			}
		end,
	}
end

ProfilePersistenceGateway.ResetForTests()

local userId = 9001
local profileData = {
	schemaVersion = 1,
	userId = userId,
	reputationState = {
		schemaVersion = 1,
		byTrackId = {},
		recentOutcomeAtByKey = {},
		unlockedCosmeticIds = {
			"title_escapist_pathfinder",
			"title_scout_trailcaller",
		},
		unlockedLoadoutTraitIds = {},
	},
}

ProfilePersistenceGateway.ConfigureOwnerLayer(makeOwnerLayer({
	[userId] = profileData,
}))

local player = makePlayer(userId)
local loaded = ProfilePersistenceGateway.LoadPlayerProfile(player)
assertTrue(loaded.ok, "profile load accepted")

local titleResult = ProfilePersistenceGateway.GetLoadedPlayerReputationTitleIds(player)
assertTrue(titleResult.ok, "reputation title query accepted")
assertTrue(type(titleResult.data) == "table", "reputation title query payload table")
assertTrue(type(titleResult.data.titleIds) == "table", "reputation title ids table")
assertEqual(#titleResult.data.titleIds, 2, "reputation title count")
assertEqual(titleResult.data.titleIds[1], "title_escapist_pathfinder", "first title id")
assertEqual(titleResult.data.titleIds[2], "title_scout_trailcaller", "second title id")

titleResult.data.titleIds[1] = "mutated"
local titleResultAfterMutation = ProfilePersistenceGateway.GetLoadedPlayerReputationTitleIds(player)
assertEqual(titleResultAfterMutation.data.titleIds[1], "title_escapist_pathfinder", "title query returns cloned data")

local storedTitles = ReputationState.GetUnlockedCosmeticIds(loaded.data)
assertEqual(storedTitles[1], "title_escapist_pathfinder", "reputation state title helper aligned")

local traitRecord, reason = TraitRegistrySchema.GetTraitRecord("Tinyfolk_Loadout_EvasiveMarker")
assertEqual(reason, nil, "production reputation trait lookup reason")
assertTrue(traitRecord ~= nil, "production reputation trait exists")

local safe, safeReason = ReputationState.IsLoadoutSafeReputationTraitRecord(traitRecord)
assertTrue(safe, "production reputation trait is loadout-safe")
assertEqual(safeReason, nil, "production reputation trait safety reason")

print("reputation_presentation: all checks passed")
