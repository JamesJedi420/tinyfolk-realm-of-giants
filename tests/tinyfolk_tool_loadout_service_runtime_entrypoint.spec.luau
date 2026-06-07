--!nocheck
--!nolint BuiltinGlobalWrite
-- selene: allow(global_usage)

local ProfilePersistenceGateway = require("../src/ServerScriptService/Services/ProfilePersistenceGateway")
local TinyfolkToolCatalogSchema = require("../src/ReplicatedStorage/Shared/Config/TinyfolkToolCatalogSchema")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local function assertFalse(value: boolean, label: string)
	assertEqual(value, false, label)
end

local function makeNode(name: string, className: string?)
	local node: any = {
		Name = name,
		ClassName = className or "Folder",
		_Children = {},
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
addChild(configFolder, "TinyfolkToolCatalogSchema", "../../ReplicatedStorage/Shared/Config/TinyfolkToolCatalogSchema")

local tinyfolkToolsFolder = makeNode("TinyfolkTools", "Folder")
addChild(
	tinyfolkToolsFolder,
	"TinyfolkToolLoadoutState",
	"../../ReplicatedStorage/Shared/TinyfolkTools/TinyfolkToolLoadoutState"
)
addChild(
	tinyfolkToolsFolder,
	"TinyfolkToolCooldownState",
	"../../ReplicatedStorage/Shared/TinyfolkTools/TinyfolkToolCooldownState"
)
addChild(
	tinyfolkToolsFolder,
	"TinyfolkToolEntryPayload",
	"../../ReplicatedStorage/Shared/TinyfolkTools/TinyfolkToolEntryPayload"
)

local sharedFolder = makeNode("Shared", "Folder")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "TinyfolkTools", tinyfolkToolsFolder)

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

local function makeProfile(userId: number): any
	return {
		schemaVersion = 1,
		userId = userId,
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

local profilesByUserId: { [number]: any } = {}
ProfilePersistenceGateway.ResetForTests()
ProfilePersistenceGateway.ConfigureOwnerLayer({
	LoadPlayerProfile = function(profileKey: string, userId: number): any
		local profile = makeProfile(userId)
		profilesByUserId[userId] = profile
		return {
			ok = true,
			operation = "LoadPlayerProfile",
			profileKey = profileKey,
			data = profile,
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

local tinyfolk = makePlayer(9101, "Tinyfolk")
local giant = makePlayer(9102, "Giant")
assertTrue(ProfilePersistenceGateway.LoadPlayerProfile(tinyfolk).ok, "tinyfolk profile loaded")
assertTrue(ProfilePersistenceGateway.LoadPlayerProfile(giant).ok, "giant profile loaded")

require("../src/ServerScriptService/Services/TinyfolkToolLoadoutService.server")

local api: any = _G._TinyfolkToolLoadoutService_QueryAPI
assertTrue(type(api) == "table", "query api exposed")

do
	local selected =
		api.SelectLoadout(tinyfolk, { "grappling_hook", "smoke_bomb" }, TinyfolkToolCatalogSchema.DEFAULT_TOOL_CATALOG)
	assertTrue(selected.accepted, "tinyfolk select accepted")
	assertEqual(selected.selectedBySlot.tool_1, "grappling_hook", "tinyfolk tool_1 selected")
	assertEqual(selected.selectedBySlot.tool_2, "smoke_bomb", "tinyfolk tool_2 selected")
end

do
	local selected = api.GetSelectedLoadout(tinyfolk)
	assertEqual(selected.tool_1, "grappling_hook", "selected tool_1 read back")
	assertEqual(selected.tool_2, "smoke_bomb", "selected tool_2 read back")

	local payloadResult =
		api.BuildEntryPayload(tinyfolk, "op-9101", TinyfolkToolCatalogSchema.DEFAULT_TOOL_CATALOG, 123.5)
	assertTrue(payloadResult.accepted, "entry payload accepted")
	assertEqual(payloadResult.payload.schemaVersion, 1, "entry payload schema version")
	assertEqual(payloadResult.payload.role, "Tinyfolk", "entry payload role")
	assertEqual(payloadResult.payload.tools[1].slotId, "tool_1", "entry payload ordered slot one")
	assertEqual(payloadResult.payload.tools[2].slotId, "tool_2", "entry payload ordered slot two")
	assertTrue(type(payloadResult.payload.tools[1].cooldownSeconds) == "number", "entry payload cooldown metadata")
end

do
	local rejectedRole = api.SelectLoadout(giant, { "grappling_hook" }, TinyfolkToolCatalogSchema.DEFAULT_TOOL_CATALOG)
	assertFalse(rejectedRole.accepted, "giant select rejected")
	assertEqual(rejectedRole.reason, "tinyfolk_role_required", "giant select reason")
end

do
	local corruptedUpdate = ProfilePersistenceGateway.UpdateLoadedPlayerProfileData(
		tinyfolk,
		function(currentData: any): any
			currentData.tinyfolkToolLoadoutState = {
				schemaVersion = 1,
				selectedByRole = {
					Tinyfolk = {
						tool_1 = "missing_tool",
					},
				},
			}
			return currentData
		end
	)
	assertTrue(corruptedUpdate.ok, "corrupted profile update accepted for test")

	local payloadResult =
		api.BuildEntryPayload(tinyfolk, "op-corrupt", TinyfolkToolCatalogSchema.DEFAULT_TOOL_CATALOG, 200)
	assertFalse(payloadResult.accepted, "invalid loadout payload rejected")
	assertEqual(payloadResult.reason, "tool_missing", "invalid loadout payload reason")
end

print("tinyfolk_tool_loadout_service_runtime_entrypoint: all checks passed")
