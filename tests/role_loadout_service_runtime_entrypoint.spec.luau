--!nocheck
--!nolint BuiltinGlobalWrite
-- selene: allow(global_usage)

local ProfilePersistenceGateway = require("../src/ServerScriptService/Services/ProfilePersistenceGateway")
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

local function assertFalse(condition: boolean, label: string)
	assertEqual(condition, false, label)
end

local function makeNode(name: string, className: string?)
	local node: any = {
		Name = name,
		ClassName = className or "Folder",
		_Children = {},
		_Attributes = {},
	}

	function node.IsA(self: any, expectedClass: string): boolean
		return self.ClassName == expectedClass
	end

	function node.FindFirstChild(self: any, childName: string): any
		return self._Children[childName]
	end

	function node.WaitForChild(self: any, childName: string): any
		return self._Children[childName]
	end

	function node.SetAttribute(self: any, attributeName: string, value: any)
		self._Attributes[attributeName] = value
	end

	function node.GetAttribute(self: any, attributeName: string): any
		return self._Attributes[attributeName]
	end

	return node
end

local function addChild(parent: any, childName: string, child: any)
	parent._Children[childName] = child
end

local function makePlayer(userId: number, role: string): any
	local player = {
		UserId = userId,
		_Attributes = {
			Role = role,
		},
	}

	function player.SetAttribute(self: any, attributeName: string, value: any)
		self._Attributes[attributeName] = value
	end

	function player.GetAttribute(self: any, attributeName: string): any
		return self._Attributes[attributeName]
	end

	return player
end

local configFolder = makeNode("Config", "Folder")
addChild(configFolder, "TraitRegistrySchema", "../../ReplicatedStorage/Shared/Config/TraitRegistrySchema")
addChild(configFolder, "RoleLoadoutSchema", "../../ReplicatedStorage/Shared/Config/RoleLoadoutSchema")

local roleLoadoutFolder = makeNode("RoleLoadout", "Folder")
addChild(roleLoadoutFolder, "RoleLoadoutState", "../../ReplicatedStorage/Shared/RoleLoadout/RoleLoadoutState")

local sharedFolder = makeNode("Shared", "Folder")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "RoleLoadout", roleLoadoutFolder)

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)

local fakeGame: any = {}
function fakeGame:GetService(serviceName: string): any
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
	end
	error("unsupported service " .. serviceName)
	return nil
end

game = fakeGame

local function makeTrait(overrides: any?): any
	local trait = {
		traitId = "Trait_Default",
		name = "Default Trait",
		description = "Test trait",
		role = TraitRegistrySchema.Roles.Tinyfolk,
		category = TraitRegistrySchema.Categories.Loadout,
		slotType = TraitRegistrySchema.SlotTypes.Passive,
		tier = TraitRegistrySchema.Tiers.Starter,
		unlockSource = TraitRegistrySchema.UnlockSources.Initial,
		unlockOwner = nil,
		unlockTrackId = nil,
		unlockSourceId = nil,
		trigger = TraitRegistrySchema.Triggers.Passive,
		durationType = TraitRegistrySchema.DurationTypes.Persistent,
		durationSeconds = nil,
		cooldownSeconds = 0,
		sharedCooldownKey = nil,
		stacking = TraitRegistrySchema.StackingPolicies.None,
		visibility = TraitRegistrySchema.Visibilities.LoadoutOnly,
		antiAbuseTags = { TraitRegistrySchema.AntiAbuseTags.DuplicateTraitGuard },
		testCoverageHooks = { "role.loadout.service.test" },
		sourceId = "tin171_role_loadout_service_test",
		modifiers = nil,
		loadoutPattern = nil,
	}

	if type(overrides) == "table" then
		for key, value in pairs(overrides) do
			trait[key] = value
		end
	end

	return trait
end

local registry = {
	makeTrait({
		traitId = "Tinyfolk_Loadout_ScoutStride",
		name = "Scout Stride",
		role = TraitRegistrySchema.Roles.Tinyfolk,
		slotType = TraitRegistrySchema.SlotTypes.Passive,
	}),
	makeTrait({
		traitId = "Tinyfolk_Loadout_RescueLink",
		name = "Rescue Link",
		role = TraitRegistrySchema.Roles.Tinyfolk,
		slotType = TraitRegistrySchema.SlotTypes.Support,
		category = TraitRegistrySchema.Categories.Social,
	}),
	makeTrait({
		traitId = "Giant_Loadout_StoneHands",
		name = "Stone Hands",
		role = TraitRegistrySchema.Roles.Giant,
		slotType = TraitRegistrySchema.SlotTypes.Passive,
		category = TraitRegistrySchema.Categories.Resource,
	}),
	makeTrait({
		traitId = "Giant_Loadout_ControlPulse",
		name = "Control Pulse",
		role = TraitRegistrySchema.Roles.Giant,
		slotType = TraitRegistrySchema.SlotTypes.Active,
		tier = TraitRegistrySchema.Tiers.Common,
		unlockSource = TraitRegistrySchema.UnlockSources.RoleMastery,
		unlockOwner = "playerProfile",
		unlockTrackId = "giant_role_mastery_track",
		unlockSourceId = "giant_role_mastery_1",
	}),
	makeTrait({
		traitId = "Shared_Loadout_CampSignal",
		name = "Camp Signal",
		role = TraitRegistrySchema.Roles.Shared,
		slotType = TraitRegistrySchema.SlotTypes.Support,
		category = TraitRegistrySchema.Categories.Social,
	}),
}

local validRegistry, registryReason = TraitRegistrySchema.ValidateTraitRegistry(registry)
assertTrue(validRegistry, "role loadout service registry validates: " .. tostring(registryReason))

ProfilePersistenceGateway.ResetForTests()
ProfilePersistenceGateway.ConfigureOwnerLayer({
	LoadPlayerProfile = function(profileKey: string, userId: number): any
		return {
			ok = true,
			operation = "LoadPlayerProfile",
			profileKey = profileKey,
			data = {
				schemaVersion = 1,
				userId = userId,
				giantTraitState = {
					unlockedTraitIds = { "Giant_Loadout_ControlPulse" },
				},
				roleLoadoutState = {
					selectedByRole = {
						Giant = {},
						Tinyfolk = {},
					},
				},
			},
		}
	end,
	SavePlayerProfile = function(profileKey: string, _userId: number, data: any): any
		return {
			ok = true,
			operation = "SavePlayerProfile",
			profileKey = profileKey,
			data = data,
		}
	end,
	ReleasePlayerProfile = function(profileKey: string, _userId: number): any
		return {
			ok = true,
			operation = "ReleasePlayerProfile",
			profileKey = profileKey,
		}
	end,
	LoadGiantRealmProfile = function(_profileKey: string, _ownerUserId: number): any
		error("not used")
	end,
	SaveGiantRealmProfile = function(_profileKey: string, _ownerUserId: number, _saveRoot: any): any
		error("not used")
	end,
	ReleaseGiantRealmProfile = function(_profileKey: string, _ownerUserId: number): any
		error("not used")
	end,
})

local tinyfolk = makePlayer(5101, "Tinyfolk")
local giant = makePlayer(5102, "Giant")
local invalidRole = makePlayer(5103, "Builder")

assertTrue(ProfilePersistenceGateway.LoadPlayerProfile(tinyfolk).ok, "tinyfolk profile loaded")
assertTrue(ProfilePersistenceGateway.LoadPlayerProfile(giant).ok, "giant profile loaded")
assertTrue(ProfilePersistenceGateway.LoadPlayerProfile(invalidRole).ok, "invalid-role profile loaded")

require("../src/ServerScriptService/Services/RoleLoadoutService.server")

local api: any = _G._RoleLoadoutService_QueryAPI
assertTrue(type(api) == "table", "service exposes query api")

do
	local selected =
		api.SelectLoadout(tinyfolk, { "Tinyfolk_Loadout_ScoutStride", "Tinyfolk_Loadout_RescueLink" }, registry)
	assertTrue(selected.accepted, "tinyfolk service loadout accepted")
	assertEqual(selected.selectedBySlot.passive_1, "Tinyfolk_Loadout_ScoutStride", "tinyfolk service passive slot")
	assertEqual(selected.selectedBySlot.support, "Tinyfolk_Loadout_RescueLink", "tinyfolk service support slot")

	local readBack = api.GetSelectedLoadout(tinyfolk)
	assertEqual(readBack.passive_1, "Tinyfolk_Loadout_ScoutStride", "tinyfolk service read-back passive slot")
	assertEqual(readBack.support, "Tinyfolk_Loadout_RescueLink", "tinyfolk service read-back support slot")
end

do
	local selected = api.SelectLoadout(giant, { "Giant_Loadout_StoneHands", "Giant_Loadout_ControlPulse" }, registry)
	assertTrue(selected.accepted, "giant service loadout accepted")
	assertEqual(selected.selectedBySlot.passive_1, "Giant_Loadout_StoneHands", "giant service passive slot")
	assertEqual(selected.selectedBySlot.active, "Giant_Loadout_ControlPulse", "giant service active slot")
end

do
	local rejected = api.SelectLoadout(tinyfolk, { "Giant_Loadout_StoneHands" }, registry)
	assertFalse(rejected.accepted, "service rejects wrong-role trait")
	assertEqual(rejected.reason, "trait_not_for_role", "service wrong-role rejection reason")
end

do
	local rejected = api.SelectLoadout(invalidRole, { "Tinyfolk_Loadout_ScoutStride" }, registry)
	assertFalse(rejected.accepted, "service rejects invalid player role")
	assertEqual(rejected.reason, "invalid_role", "service invalid player role reason")
end

do
	local defaultLoadout = api.GetDefaultLoadout(tinyfolk, registry)
	assertEqual(defaultLoadout.passive_1, "Tinyfolk_Loadout_ScoutStride", "service default passive slot")
	assertEqual(defaultLoadout.support, "Tinyfolk_Loadout_RescueLink", "service default support slot")
end

print("role_loadout_service_runtime_entrypoint: all checks passed")
