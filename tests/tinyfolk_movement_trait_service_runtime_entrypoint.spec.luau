--!strict

local function assertTrue(condition: boolean, label: string)
	if not condition then
		error(string.format("FAIL [%s]: expected true, got false", label))
	end
	print(string.format("PASS [%s]", label))
end

local function assertFalse(condition: boolean, label: string)
	if condition then
		error(string.format("FAIL [%s]: expected false, got true", label))
	end
	print(string.format("PASS [%s]", label))
end

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local scheduledCallbacks: { () -> () } = {}
local originalTask = task
task = {
	delay = function(_seconds: number, callback: () -> ())
		table.insert(scheduledCallbacks, callback)
	end,
} :: any

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

local function makeNode(name: string, className: string?, fullName: string?)
	local node: any = {
		Name = name,
		ClassName = className or "Folder",
		_FullName = fullName or name,
		_Children = {},
		_Attributes = {},
	}

	function node.IsA(self: any, expectedClass: string): boolean
		return self.ClassName == expectedClass
	end

	function node.GetFullName(self: any): string
		return self._FullName
	end

	function node.FindFirstChild(self: any, childName: string): any
		return self._Children[childName]
	end

	function node.WaitForChild(self: any, childName: string, _timeout: number?): any
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
	if type(child) == "table" then
		child.Parent = parent
	end
end

local function makeCharacter(hasRootPart: boolean, humanoidHealth: number, walkSpeed: number)
	local humanoid: any = {
		ClassName = "Humanoid",
		Health = humanoidHealth,
		WalkSpeed = walkSpeed,
	}
	local root = makeNode("HumanoidRootPart", "BasePart", "Character.HumanoidRootPart")
	local character: any = makeNode("Character", "Model", "Character")

	function character.FindFirstChild(self: any, childName: string): any
		if childName == "HumanoidRootPart" and hasRootPart then
			return root
		end
		return self._Children[childName]
	end

	function character.FindFirstChildOfClass(_self: any, className: string): any
		if className == "Humanoid" then
			return humanoid
		end
		return nil
	end

	return character, humanoid
end

local function makePlayer(userId: number, role: string?, hasTrait: boolean, hasRootPart: boolean?, humanoidHealth: number?)
	local attributes: { [string]: any } = {}
	local character, humanoid = makeCharacter(hasRootPart ~= false, humanoidHealth or 100, 16)
	local player: any = {
		UserId = userId,
		Name = "Player" .. tostring(userId),
		Character = character,
	}

	function player.SetAttribute(_self: any, attributeName: string, value: any)
		attributes[attributeName] = value
	end

	function player.GetAttribute(_self: any, attributeName: string): any
		return attributes[attributeName]
	end

	if role ~= nil then
		player:SetAttribute("Role", role)
	end
	player:SetAttribute("TinyfolkTrait_PostCrossingBurst", hasTrait)

	return player, humanoid
end

local configFolder = makeNode("Config", "Folder", "ReplicatedStorage.Shared.Config")
addChild(configFolder, "RoleConfig", "../../ReplicatedStorage/Shared/Config/RoleConfig")
addChild(configFolder, "TinyfolkMovementTraitConfig", "../../ReplicatedStorage/Shared/Config/TinyfolkMovementTraitConfig")

local movementFolder = makeNode("TinyfolkMovement", "Folder", "ReplicatedStorage.Shared.TinyfolkMovement")
addChild(movementFolder, "PostCrossingBurstLogic", "../../ReplicatedStorage/Shared/TinyfolkMovement/PostCrossingBurstLogic")

local sharedFolder = makeNode("Shared", "Folder", "ReplicatedStorage.Shared")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "TinyfolkMovement", movementFolder)

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage", "ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)

local playerRemoving = makeSignal()
local playersService: any = {
	Name = "Players",
	ClassName = "Players",
	PlayerRemoving = playerRemoving,
}

local fakeGame: any = {}
function fakeGame:GetService(serviceName: string): any
	if serviceName == "Players" then
		return playersService
	end
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
	end
	error(string.format("unsupported service: %s", serviceName))
	return nil
end

game = fakeGame

local RoleConfig = require("../src/ReplicatedStorage/Shared/Config/RoleConfig")
local TraitConfig = require("../src/ReplicatedStorage/Shared/Config/TinyfolkMovementTraitConfig")
local TinyfolkMovementTraitService = require("../src/ServerScriptService/Services/TinyfolkMovementTraitService")

TinyfolkMovementTraitService.ResetForTests()

do
	local player, humanoid = makePlayer(6101, RoleConfig.Roles.Tinyfolk, true)
	local outcome = TinyfolkMovementTraitService.OnValidRouteCrossing(player, "EscapeRoute_A")

	assertTrue(outcome.accepted, "Tinyfolk with trait receives accepted burst")
	assertEqual(humanoid.WalkSpeed, 22, "accepted burst applies bounded WalkSpeed")
	assertEqual(player:GetAttribute(TraitConfig.Attributes.BurstActive), true, "accepted burst exposes active attribute")
	assertEqual(player:GetAttribute(TraitConfig.Attributes.TraceCostActive), true, "accepted burst exposes trace attribute")
	assertEqual(player:GetAttribute(TraitConfig.Attributes.TraceCostReason), "PostCrossingBurst", "accepted burst exposes trace reason")
	assertTrue(type(player:GetAttribute(TraitConfig.Attributes.BurstCooldownUntil)) == "number", "accepted burst exposes cooldown")
	assertTrue(type(player:GetAttribute(TraitConfig.Attributes.SharedBurstCooldownUntil)) == "number", "accepted burst exposes shared cooldown")
	assertEqual(#scheduledCallbacks, 1, "accepted burst schedules restoration")

	scheduledCallbacks[1]()
	assertEqual(humanoid.WalkSpeed, 16, "scheduled restoration prevents permanent movement inflation")
end

do
	TinyfolkMovementTraitService.ResetForTests()
	scheduledCallbacks = {}
	local player, humanoid = makePlayer(6102, RoleConfig.Roles.Giant, true)
	local outcome = TinyfolkMovementTraitService.OnValidRouteCrossing(player, "EscapeRoute_A")

	assertFalse(outcome.accepted, "non-Tinyfolk does not trigger burst")
	assertEqual(outcome.reason, "requester_not_tinyfolk", "non-Tinyfolk rejection reason")
	assertEqual(humanoid.WalkSpeed, 16, "non-Tinyfolk WalkSpeed unchanged")
	assertEqual(#scheduledCallbacks, 0, "non-Tinyfolk schedules no restoration")
end

do
	TinyfolkMovementTraitService.ResetForTests()
	local player, humanoid = makePlayer(6103, RoleConfig.Roles.Tinyfolk, false)
	local outcome = TinyfolkMovementTraitService.OnValidRouteCrossing(player, "EscapeRoute_A")

	assertFalse(outcome.accepted, "missing trait does not trigger burst")
	assertEqual(outcome.reason, "trait_not_enabled", "missing trait rejection reason")
	assertEqual(humanoid.WalkSpeed, 16, "missing trait WalkSpeed unchanged")
end

do
	TinyfolkMovementTraitService.ResetForTests()
	local player, humanoid = makePlayer(6104, RoleConfig.Roles.Tinyfolk, true, false)
	local outcome = TinyfolkMovementTraitService.OnValidRouteCrossing(player, "EscapeRoute_A")

	assertFalse(outcome.accepted, "missing root part does not trigger burst")
	assertEqual(outcome.reason, "humanoid_root_missing", "missing root part rejection reason")
	assertEqual(humanoid.WalkSpeed, 16, "missing root part WalkSpeed unchanged")
end

do
	TinyfolkMovementTraitService.ResetForTests()
	local player, humanoid = makePlayer(6105, RoleConfig.Roles.Tinyfolk, true, true, 0)
	local outcome = TinyfolkMovementTraitService.OnValidRouteCrossing(player, "EscapeRoute_A")

	assertFalse(outcome.accepted, "dead humanoid does not trigger burst")
	assertEqual(outcome.reason, "humanoid_not_alive", "dead humanoid rejection reason")
	assertEqual(humanoid.WalkSpeed, 16, "dead humanoid WalkSpeed unchanged")
end

task = originalTask

print("tinyfolk_movement_trait_service_runtime_entrypoint: all checks passed")
