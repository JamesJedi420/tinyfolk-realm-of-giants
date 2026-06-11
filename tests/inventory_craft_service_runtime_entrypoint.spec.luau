--!nocheck
--!nolint BuiltinGlobalWrite
-- selene: allow(global_usage)

local InventoryCraftConfig = require("../src/ReplicatedStorage/Shared/Config/InventoryCraftConfig")

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

local function makeSignal()
	local callbacks: { (...any) -> () } = {}
	return {
		Connect = function(_self: any, callback: (...any) -> ())
			table.insert(callbacks, callback)
			return {}
		end,
		Fire = function(_self: any, ...: any)
			for _, callback in ipairs(callbacks) do
				callback(...)
			end
		end,
	}
end

local function setNodeParent(node: any, parent: any)
	if node._Parent ~= nil then
		node._Parent._Children[node.Name] = nil
	end
	node._Parent = parent
	if parent ~= nil then
		parent._Children[node.Name] = node
	end
end

local function makeNode(name: string, className: string?)
	local node: any = {
		Name = name,
		ClassName = className or "Folder",
		_Children = {},
		_Parent = nil,
	}

	function node:IsA(expectedClass: string): boolean
		return self.ClassName == expectedClass
	end

	function node:FindFirstChild(childName: string): any
		return self._Children[childName]
	end

	function node:WaitForChild(childName: string, _timeout: number?): any
		return self._Children[childName]
	end

	setmetatable(node, {
		__index = function(self, key: string)
			if key == "Parent" then
				return self._Parent
			end
			return rawget(self, key)
		end,
		__newindex = function(self, key: string, value: any)
			if key == "Parent" then
				setNodeParent(self, value)
				return
			end
			rawset(self, key, value)
		end,
	})

	return node
end

local function addChild(parent: any, childName: string, child: any)
	child.Name = childName
	setNodeParent(child, parent)
end

local function makeRemoteEvent(remoteName: string)
	local remote: any = makeNode(remoteName, "RemoteEvent")
	remote._Handler = nil
	remote._ClientPayload = nil

	function remote:IsA(expectedClass: string): boolean
		return self.ClassName == expectedClass
	end

	remote.OnServerEvent = {
		Connect = function(_signal: any, handler: (any, any) -> ())
			remote._Handler = handler
		end,
	}

	function remote:FireServer(player: any, payload: any)
		if remote._Handler == nil then
			error(string.format("remote %s handler not connected", remote.Name))
		end
		remote._Handler(player, payload)
	end

	function remote:FireClient(_player: any, payload: any)
		remote._ClientPayload = payload
	end

	return remote
end

Instance = {
	new = function(className: string): any
		if className == "Folder" then
			return makeNode("Folder", "Folder")
		end
		if className == "RemoteEvent" then
			return makeRemoteEvent("GeneratedRemote")
		end
		error(string.format("unsupported Instance.new(%q)", className))
	end,
} :: any

local configFolder = makeNode("Config")
configFolder._Children["RoleConfig"] = "../../ReplicatedStorage/Shared/Config/RoleConfig"
configFolder._Children["InventoryCraftConfig"] = "../../ReplicatedStorage/Shared/Config/InventoryCraftConfig"

local inventoryCraftFolder = makeNode("InventoryCraft")
inventoryCraftFolder._Children["InventoryCraftState"] =
	"../../ReplicatedStorage/Shared/InventoryCraft/InventoryCraftState"
inventoryCraftFolder._Children["InventoryCraftProfileState"] =
	"../../ReplicatedStorage/Shared/InventoryCraft/InventoryCraftProfileState"

local sharedFolder = makeNode("Shared")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "InventoryCraft", inventoryCraftFolder)

local remotesFolder = makeNode("Remotes")
local replicatedStorage = makeNode("ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)
addChild(replicatedStorage, "Remotes", remotesFolder)

local playerAdded = makeSignal()
local playerRemoving = makeSignal()
local playersService: any = {
	Name = "Players",
	ClassName = "Players",
	PlayerAdded = playerAdded,
	PlayerRemoving = playerRemoving,
	_Players = {},
}

function playersService:GetPlayers(): { any }
	return self._Players
end

local fakeGame: any = {}
function fakeGame:GetService(serviceName: string): any
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
	end
	if serviceName == "Players" then
		return playersService
	end
	error(string.format("unsupported service: %s", serviceName))
	return nil
end

game = fakeGame

local function makePlayer(userId: number, role: string): any
	local attributes: { [string]: any } = {
		Role = role,
	}
	local attributeChangedSignals: { [string]: any } = {}
	local player: any = {
		UserId = userId,
		Name = "Player" .. tostring(userId),
	}

	function player.SetAttribute(_self: any, attributeName: string, value: any)
		attributes[attributeName] = value
		local signal = attributeChangedSignals[attributeName]
		if signal ~= nil then
			signal:Fire()
		end
	end

	function player.GetAttribute(_self: any, attributeName: string): any
		return attributes[attributeName]
	end

	function player.GetAttributeChangedSignal(_self: any, attributeName: string): any
		local signal = attributeChangedSignals[attributeName]
		if signal == nil then
			signal = makeSignal()
			attributeChangedSignals[attributeName] = signal
		end
		return signal
	end

	return player
end

local function cloneTable(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local copied = {}
	for key, child in pairs(value) do
		copied[key] = cloneTable(child)
	end
	return copied
end

local profileDataByUserId: { [number]: any } = {}
local updateCallCountByUserId: { [number]: number } = {}

local ProfilePersistenceGateway = require("../src/ServerScriptService/Services/ProfilePersistenceGateway")
ProfilePersistenceGateway.ResetForTests()

ProfilePersistenceGateway.GetLoadedPlayerProfileData = function(player: any): any
	local data = profileDataByUserId[player.UserId]
	if type(data) ~= "table" then
		return {
			ok = false,
			operation = "GetLoadedPlayerProfileData",
			reason = "player_profile_not_loaded",
			profileKey = "PlayerProfile:" .. tostring(player.UserId),
		}
	end

	return {
		ok = true,
		operation = "GetLoadedPlayerProfileData",
		profileKey = "PlayerProfile:" .. tostring(player.UserId),
		data = cloneTable(data),
	}
end

ProfilePersistenceGateway.UpdateLoadedPlayerProfileData = function(player: any, updater: any): any
	local activeData = profileDataByUserId[player.UserId]
	if type(activeData) ~= "table" then
		return {
			ok = false,
			operation = "UpdateLoadedPlayerProfileData",
			reason = "player_profile_not_loaded",
			profileKey = "PlayerProfile:" .. tostring(player.UserId),
		}
	end

	local updateOk, newData = pcall(updater, cloneTable(activeData))
	if not updateOk or type(newData) ~= "table" then
		return {
			ok = false,
			operation = "UpdateLoadedPlayerProfileData",
			reason = "profile_update_failed",
			profileKey = "PlayerProfile:" .. tostring(player.UserId),
		}
	end

	profileDataByUserId[player.UserId] = cloneTable(newData)
	updateCallCountByUserId[player.UserId] = (updateCallCountByUserId[player.UserId] or 0) + 1

	return {
		ok = true,
		operation = "UpdateLoadedPlayerProfileData",
		profileKey = "PlayerProfile:" .. tostring(player.UserId),
		data = cloneTable(profileDataByUserId[player.UserId]),
	}
end

local ownershipCallbacksByUserId: { [number]: { (boolean, string?) -> () } } = {}
_G._ProfilePersistenceLifecycle_QueryAPI = {
	RegisterOwnershipReadyCallback = function(userId: number, callback: any): boolean
		if type(callback) ~= "function" then
			return false
		end
		local callbacks = ownershipCallbacksByUserId[userId]
		if callbacks == nil then
			callbacks = {}
			ownershipCallbacksByUserId[userId] = callbacks
		end
		table.insert(callbacks, callback)
		return true
	end,
}

local function fireOwnershipReady(userId: number)
	local callbacks = ownershipCallbacksByUserId[userId]
	if callbacks == nil then
		return
	end
	for _, callback in ipairs(callbacks) do
		callback(true, nil)
	end
end

local InventoryCraftService = require("../src/ServerScriptService/Services/InventoryCraftService.server")

local api: any = _G._InventoryCraftService_QueryAPI
assertTrue(type(api) == "table", "query api exposed")
assertEqual(type(api.CraftWithCatalogOverride), "nil", "test craft seam hidden from runtime api")

local craftRequestRemote = remotesFolder:WaitForChild("InventoryCraftRequest")
local debugRequestRemote = remotesFolder:WaitForChild("InventoryCraftDebugStateRequest")
local debugResponseRemote = remotesFolder:WaitForChild("InventoryCraftDebugStateResponse")
assertTrue(craftRequestRemote ~= nil, "craft request remote created")
assertTrue(debugRequestRemote ~= nil, "debug request remote created")
assertTrue(debugResponseRemote ~= nil, "debug response remote created")

profileDataByUserId[9201] = {
	schemaVersion = 1,
	userId = 9201,
}
profileDataByUserId[9202] = {
	schemaVersion = 1,
	userId = 9202,
}

local tinyfolk = makePlayer(9201, "Tinyfolk")
local giant = makePlayer(9202, "Giant")
table.insert(playersService._Players, tinyfolk)
table.insert(playersService._Players, giant)
playerAdded:Fire(tinyfolk)
playerAdded:Fire(giant)
fireOwnershipReady(9201)
fireOwnershipReady(9202)

do
	local snapshot = api.GetSnapshot(tinyfolk)
	assertEqual(snapshot.itemCounts.raw_fiber, 4, "tinyfolk bootstrap raw_fiber")
	assertEqual(snapshot.itemCounts.wood_scrap, 3, "tinyfolk bootstrap wood_scrap")
	assertEqual(snapshot.itemCounts.stone_shard, 3, "tinyfolk bootstrap stone_shard")
	assertEqual(snapshot.itemCounts.plant_resin, 2, "tinyfolk bootstrap plant_resin")
	assertEqual(
		tinyfolk:GetAttribute(InventoryCraftConfig.Attributes.ItemCount),
		6,
		"tinyfolk debug item count attribute"
	)
	assertTrue(
		tinyfolk:GetAttribute(InventoryCraftConfig.Attributes.CraftableRecipeCount) >= 3,
		"tinyfolk craftable recipe count attribute"
	)
	assertTrue(type(snapshot.craftableRecipeIds) == "table", "snapshot craftable recipe ids")
end

do
	assertTrue(
		type(profileDataByUserId[9201].inventoryCraftState) == "table",
		"first session bootstrap persisted inventory state"
	)
	assertEqual(profileDataByUserId[9201].inventoryCraftState.itemCounts.raw_fiber, 4, "bootstrap raw_fiber persisted")
end

do
	local crafted = api.Craft(tinyfolk, "craft_twine_satchel")
	assertTrue(crafted.accepted, "tinyfolk craft accepted")
	assertEqual(crafted.snapshot.itemCounts.twine_satchel, 1, "tinyfolk crafted twine_satchel")
	assertEqual(crafted.snapshot.craftedTotal, 1, "tinyfolk crafted total")
	assertEqual(
		tinyfolk:GetAttribute(InventoryCraftConfig.Attributes.LastCraftRecipeId),
		"craft_twine_satchel",
		"tinyfolk last craft recipe attribute"
	)
end

do
	local rejected = api.Craft(giant, "craft_twine_satchel")
	assertFalse(rejected.accepted, "giant craft rejected")
	assertEqual(rejected.reason, "tinyfolk_role_required", "giant craft reason")
end

do
	debugRequestRemote:FireServer(tinyfolk, nil)
	local debugPayload = debugResponseRemote._ClientPayload
	assertTrue(type(debugPayload) == "table", "debug payload returned")
	assertEqual(debugPayload.userId, 9201, "debug payload user id")
	assertEqual(debugPayload.craftedTotal, 1, "debug payload crafted total")
	assertTrue(type(debugPayload.items) == "table", "debug payload items table")
end

do
	local spoofRecipeCatalog = {
		{
			recipeId = "craft_spoof_item",
			displayName = "Spoof Item",
			requiredRole = "Tinyfolk",
			inputs = {
				raw_fiber = 1,
			},
			outputs = {
				twine_satchel = 1,
			},
			sourceId = "tin22_spoof_recipe",
		},
	}

	local rejected =
		api.Craft(tinyfolk, "craft_spoof_item", InventoryCraftConfig.DEFAULT_ITEM_CATALOG, spoofRecipeCatalog)
	assertFalse(rejected.accepted, "public craft rejects spoof recipe catalog")
	assertEqual(rejected.reason, "recipe_missing", "public craft uses canonical recipe catalog")

	local acceptedViaTestSeam = InventoryCraftService.TestHarness.CraftWithCatalogOverride(
		tinyfolk,
		"craft_spoof_item",
		InventoryCraftConfig.DEFAULT_ITEM_CATALOG,
		spoofRecipeCatalog
	)
	assertTrue(acceptedViaTestSeam.accepted, "test seam accepts spoof recipe")
	assertEqual(acceptedViaTestSeam.snapshot.itemCounts.twine_satchel, 2, "test seam spoof craft output")
end

do
	InventoryCraftService.TestHarness.ResetSessionForTests(tinyfolk.UserId, {
		wood_scrap = 1,
	})
	local rejected = api.Craft(tinyfolk, "craft_twine_satchel")
	assertFalse(rejected.accepted, "insufficient inputs rejected at runtime")
	assertEqual(rejected.reason, "insufficient_inputs", "insufficient inputs runtime reason")
end

do
	InventoryCraftService.TestHarness.ResetSessionForTests(tinyfolk.UserId, InventoryCraftConfig.TEST_STARTING_ITEMS)
	local listed = api.ListCraftableRecipes(tinyfolk)
	assertTrue(listed.accepted, "list craftable recipes accepted")
	assertTrue(type(listed.recipes) == "table", "list craftable recipes table")
	assertTrue(#listed.recipes >= 1, "list craftable recipes non-empty")
end

do
	InventoryCraftService.TestHarness.ResetSessionForTests(tinyfolk.UserId, {
		smoke_pouch = 1,
	})
	local consumed = api.ConsumeItems(tinyfolk, { smoke_pouch = 1 })
	assertTrue(consumed.accepted, "consume crafted item accepted")
	assertEqual(consumed.snapshot.itemCounts.smoke_pouch, nil, "consume crafted item cleared")
end

do
	local rejectedConsume = api.ConsumeItems(giant, { smoke_pouch = 1 })
	assertFalse(rejectedConsume.accepted, "giant consume rejected")
	assertEqual(rejectedConsume.reason, "tinyfolk_role_required", "giant consume reason")
end

do
	profileDataByUserId[9203] = {
		schemaVersion = 1,
		userId = 9203,
		inventoryCraftState = {
			schemaVersion = 1,
			itemCounts = {
				iron_filings = 7,
				stone_shard = 1,
			},
		},
	}
	local returningTinyfolk = makePlayer(9203, "Tinyfolk")
	table.insert(playersService._Players, returningTinyfolk)
	playerAdded:Fire(returningTinyfolk)
	fireOwnershipReady(9203)

	local snapshot = api.GetSnapshot(returningTinyfolk)
	assertEqual(snapshot.itemCounts.iron_filings, 7, "returning player iron_filings hydrated")
	assertEqual(snapshot.itemCounts.stone_shard, 1, "returning player stone_shard hydrated")
	assertEqual(snapshot.itemCounts.raw_fiber, nil, "returning player skips bootstrap raw_fiber")
end

do
	InventoryCraftService.TestHarness.ResetSessionForTests(9201, InventoryCraftConfig.TEST_STARTING_ITEMS)
	local granted = api.GrantItems(tinyfolk, { iron_filings = 2 }, "warehouse_delivery")
	assertTrue(granted.accepted, "grant persists inventory")
	assertEqual(
		profileDataByUserId[9201].inventoryCraftState.itemCounts.iron_filings,
		4,
		"grant writes iron_filings to profile"
	)
	assertTrue((updateCallCountByUserId[9201] or 0) >= 1, "grant triggers profile update")
end

print("inventory_craft_service_runtime_entrypoint: all checks passed")
