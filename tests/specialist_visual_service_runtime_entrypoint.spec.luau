--!nocheck
--!nolint BuiltinGlobalWrite
-- selene: allow(global_usage)

local SpecialistConfig = require("../src/ReplicatedStorage/Shared/Config/SpecialistConfig")
local SpecialistVisualConfig = require("../src/ReplicatedStorage/Shared/Config/SpecialistVisualConfig")

if Vector3 == nil then
	Vector3 = {
		new = function(x: number, y: number, z: number)
			return { X = x, Y = y, Z = z }
		end,
	} :: any
end

if Color3 == nil then
	Color3 = {
		new = function(r: number, g: number, b: number)
			return { R = r, G = g, B = b }
		end,
		fromRGB = function(r: number, g: number, b: number)
			return { R = r / 255, G = g / 255, B = b / 255 }
		end,
	} :: any
end

if CFrame == nil then
	CFrame = {
		new = function()
			return {}
		end,
	} :: any
end

if Enum == nil then
	Enum = {
		Material = {
			SmoothPlastic = "SmoothPlastic",
		},
	} :: any
end

local function assertTrue(condition: boolean, label: string)
	if not condition then
		error(string.format("FAIL [%s]: expected true, got false", label))
	end
	print(string.format("PASS [%s]", label))
end

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
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

	function node:Destroy()
		if self._Parent ~= nil then
			self._Parent._Children[self.Name] = nil
		end
		self._Children = {}
		self._Parent = nil
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

local function makePart(name: string): any
	local part: any = makeNode(name, "Part")
	part.Name = name
	part.Size = Vector3.new(1, 1, 1)
	part.Color = Color3.new(1, 1, 1)
	part.CFrame = CFrame.new()
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.Anchored = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	return part
end

Instance = {
	new = function(className: string): any
		if className == "Folder" then
			return makeNode("Folder", "Folder")
		end
		if className == "RemoteEvent" then
			return makeRemoteEvent("GeneratedRemote")
		end
		if className == "Part" then
			return makePart("Part")
		end
		if className == "WeldConstraint" then
			local weld: any = makeNode("WeldConstraint", "WeldConstraint")
			weld.Part0 = nil
			weld.Part1 = nil
			return weld
		end
		error(string.format("unsupported Instance.new(%q)", className))
	end,
} :: any

local configFolder = makeNode("Config")
configFolder._Children["RoleConfig"] = "../../ReplicatedStorage/Shared/Config/RoleConfig"
configFolder._Children["SpecialistConfig"] = "../../ReplicatedStorage/Shared/Config/SpecialistConfig"
configFolder._Children["SpecialistVisualConfig"] = "../../ReplicatedStorage/Shared/Config/SpecialistVisualConfig"

local specialistVisualFolder = makeNode("SpecialistVisual")
specialistVisualFolder._Children["SpecialistVisualApply"] =
	"../../ReplicatedStorage/Shared/SpecialistVisual/SpecialistVisualApply"

local sharedFolder = makeNode("Shared")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "SpecialistVisual", specialistVisualFolder)

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

local function makeCharacter()
	local upperTorso = makePart("UpperTorso")
	local rightHand = makePart("RightHand")
	local character = makeNode("Character", "Model")

	function character:FindFirstChild(childName: string): any
		if childName == "UpperTorso" then
			return upperTorso
		end
		if childName == "RightHand" then
			return rightHand
		end
		return self._Children[childName]
	end

	function character:FindFirstChildOfClass(className: string): any
		if className == "Humanoid" then
			return nil
		end
		return nil
	end

	return character
end

local function makePlayer(userId: number, role: string, specialistRole: string)
	local attributes: { [string]: any } = {
		Role = role,
		SpecialistRole = specialistRole,
	}
	local attributeChangedSignals: { [string]: any } = {}
	local character = makeCharacter()
	local player: any = {
		UserId = userId,
		Name = "Player" .. tostring(userId),
		Character = character,
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

	local characterAdded = makeSignal()
	player.CharacterAdded = characterAdded

	return player, characterAdded
end

require("../src/ServerScriptService/Services/SpecialistVisualService.server")

local api: any = _G._SpecialistVisualService_QueryAPI
assertTrue(type(api) == "table", "query api exposed")

local debugRequestRemote = remotesFolder:WaitForChild("SpecialistVisualDebugStateRequest")
local debugResponseRemote = remotesFolder:WaitForChild("SpecialistVisualDebugStateResponse")
assertTrue(debugRequestRemote ~= nil, "debug request remote created")
assertTrue(debugResponseRemote ~= nil, "debug response remote created")

local tinyfolkUnassigned, _ = makePlayer(5101, "Tinyfolk", SpecialistConfig.SpecialistRoles.None)
table.insert(playersService._Players, tinyfolkUnassigned)
playerAdded:Fire(tinyfolkUnassigned)

assertEqual(
	tinyfolkUnassigned:GetAttribute(SpecialistVisualConfig.Attributes.Applied),
	false,
	"unassigned tinyfolk not visually applied"
)
assertEqual(
	tinyfolkUnassigned:GetAttribute(SpecialistVisualConfig.Attributes.ActiveRole),
	SpecialistConfig.SpecialistRoles.None,
	"unassigned tinyfolk active role none"
)

local tinyfolkWoodcutter, _ = makePlayer(5102, "Tinyfolk", SpecialistConfig.SpecialistRoles.Woodcutter)
table.insert(playersService._Players, tinyfolkWoodcutter)
playerAdded:Fire(tinyfolkWoodcutter)

assertEqual(
	tinyfolkWoodcutter:GetAttribute(SpecialistVisualConfig.Attributes.Applied),
	true,
	"woodcutter visuals applied on setup"
)
assertEqual(
	tinyfolkWoodcutter:GetAttribute(SpecialistVisualConfig.Attributes.OutfitId),
	"woodcutter_vest",
	"woodcutter outfit id attribute"
)
assertEqual(
	tinyfolkWoodcutter:GetAttribute(SpecialistVisualConfig.Attributes.ToolId),
	"woodcutter_axe",
	"woodcutter tool id attribute"
)
assertTrue(
	tinyfolkWoodcutter.Character:FindFirstChild(SpecialistVisualConfig.CharacterFolderName) ~= nil,
	"woodcutter character folder created"
)

tinyfolkWoodcutter:SetAttribute("SpecialistRole", SpecialistConfig.SpecialistRoles.Miner)
assertEqual(
	tinyfolkWoodcutter:GetAttribute(SpecialistVisualConfig.Attributes.ActiveRole),
	SpecialistConfig.SpecialistRoles.Miner,
	"miner reassignment updates active role"
)
assertEqual(
	tinyfolkWoodcutter:GetAttribute(SpecialistVisualConfig.Attributes.OutfitId),
	"miner_tunic",
	"miner reassignment updates outfit id"
)
assertEqual(
	tinyfolkWoodcutter:GetAttribute(SpecialistVisualConfig.Attributes.ToolId),
	"miner_pick",
	"miner reassignment updates tool id"
)

tinyfolkWoodcutter:SetAttribute("SpecialistRole", SpecialistConfig.SpecialistRoles.None)
assertEqual(
	tinyfolkWoodcutter:GetAttribute(SpecialistVisualConfig.Attributes.Applied),
	false,
	"clear assignment removes applied visuals"
)
assertEqual(
	tinyfolkWoodcutter.Character:FindFirstChild(SpecialistVisualConfig.CharacterFolderName),
	nil,
	"clear assignment removes character folder"
)

local giantWoodcutter, _ = makePlayer(5103, "Giant", SpecialistConfig.SpecialistRoles.Woodcutter)
table.insert(playersService._Players, giantWoodcutter)
playerAdded:Fire(giantWoodcutter)
giantWoodcutter:SetAttribute("Role", "Giant")
assertEqual(
	giantWoodcutter:GetAttribute(SpecialistVisualConfig.Attributes.Applied),
	false,
	"giant role clears specialist visuals"
)
assertEqual(
	giantWoodcutter:GetAttribute(SpecialistVisualConfig.Attributes.LastApplyReason),
	SpecialistVisualConfig.ApplyReasons.ClearedRoleChange,
	"giant role clear reason"
)

local tinyfolkFarmer, characterAdded = makePlayer(5104, "Tinyfolk", SpecialistConfig.SpecialistRoles.Farmer)
table.insert(playersService._Players, tinyfolkFarmer)
playerAdded:Fire(tinyfolkFarmer)

local respawnCharacter = makeCharacter()
tinyfolkFarmer.Character = respawnCharacter
characterAdded:Fire(respawnCharacter)
assertTrue(
	respawnCharacter:FindFirstChild(SpecialistVisualConfig.CharacterFolderName) ~= nil,
	"character respawn reapplies farmer visuals"
)

debugRequestRemote:FireServer(tinyfolkFarmer, nil)
assertEqual(debugResponseRemote._ClientPayload.userId, 5104, "debug response user id")
assertEqual(debugResponseRemote._ClientPayload.activeRole, SpecialistConfig.SpecialistRoles.Farmer, "debug active role")
assertEqual(debugResponseRemote._ClientPayload.outfitId, "farmer_apron", "debug outfit id")

tinyfolkWoodcutter:SetAttribute("SpecialistRole", SpecialistConfig.SpecialistRoles.Miner)
local syncSnapshot = api.SyncForPlayer(tinyfolkWoodcutter, SpecialistVisualConfig.ApplyReasons.Assigned)
assertEqual(
	syncSnapshot.activeRole,
	SpecialistConfig.SpecialistRoles.Miner,
	"sync api reports miner after reassignment"
)

debugResponseRemote._ClientPayload = nil
debugRequestRemote:FireServer(tinyfolkWoodcutter, "malformed")
assertEqual(debugResponseRemote._ClientPayload, nil, "malformed debug payload rejected")

print("specialist_visual_service_runtime_entrypoint: all checks passed")
