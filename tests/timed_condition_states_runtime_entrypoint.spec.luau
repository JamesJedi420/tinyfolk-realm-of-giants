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

local heartbeatCallbacks: { () -> () } = {}

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

local function makePosition(x: number, y: number, z: number): any
	return { X = x, Y = y, Z = z }
end

local function addChild(parent: any, childName: string, child: any)
	parent._Children[childName] = child
	if type(child) == "table" then
		(child :: any).Parent = parent
	end
end

local function makeCharacter(position: any, humanoidHealth: number)
	local humanoid: any = {
		ClassName = "Humanoid",
		Health = humanoidHealth,
		WalkSpeed = 16,
	}
	local root = makeNode("HumanoidRootPart", "BasePart", "Character.HumanoidRootPart")
	root.Position = position
	local character: any = makeNode("Character", "Model", "Character")

	function character.FindFirstChild(self: any, childName: string): any
		if childName == "HumanoidRootPart" then
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

	return character
end

local function makePlayer(userId: number, role: string, position: any, health: number?)
	local attributes: { [string]: any } = {}
	local player: any = {
		UserId = userId,
		Name = "Player" .. tostring(userId),
		Character = makeCharacter(position, health or 100),
	}

	function player.SetAttribute(_self: any, attributeName: string, value: any)
		attributes[attributeName] = value
	end

	function player.GetAttribute(_self: any, attributeName: string): any
		return attributes[attributeName]
	end

	player:SetAttribute("Role", role)
	return player
end

local function createPlayersService(playersList: { any })
	local playerRemoving = makeSignal()
	local playersService: any = {
		Name = "Players",
		ClassName = "Players",
		PlayerRemoving = playerRemoving,
	}

	function playersService:GetPlayers(): { any }
		return playersList
	end

	function playersService:GetPlayerByUserId(userId: number): any?
		for _, player in ipairs(playersList) do
			if player.UserId == userId then
				return player
			end
		end
		return nil
	end

	return playersService
end

local function createRunService()
	return {
		Name = "RunService",
		ClassName = "RunService",
		Heartbeat = makeSignal(),
	}
end

local function createFixture()
	local playersList = {}
	local tinyfolk = makePlayer(8101, "Tinyfolk", makePosition(0, 0, 0))
	local giant = makePlayer(8102, "Giant", makePosition(18, 0, 0))
	table.insert(playersList, tinyfolk)
	table.insert(playersList, giant)

	local configFolder = makeNode("Config", "Folder", "ReplicatedStorage.Shared.Config")
	addChild(configFolder, "RoleConfig", "../../ReplicatedStorage/Shared/Config/RoleConfig")
	addChild(configFolder, "TinyfolkStatusConfig", "../../ReplicatedStorage/Shared/Config/TinyfolkStatusConfig")

	local statusFolder = makeNode("TinyfolkStatus", "Folder", "ReplicatedStorage.Shared.TinyfolkStatus")
	addChild(statusFolder, "TimedConditionStateLogic", "../../ReplicatedStorage/Shared/TinyfolkStatus/TimedConditionStateLogic")

	local sharedFolder = makeNode("Shared", "Folder", "ReplicatedStorage.Shared")
	addChild(sharedFolder, "Config", configFolder)
	addChild(sharedFolder, "TinyfolkStatus", statusFolder)

	local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage", "ReplicatedStorage")
	addChild(replicatedStorage, "Shared", sharedFolder)

	local playersService = createPlayersService(playersList)
	local runService = createRunService()

	local fakeGame: any = {}
	function fakeGame:GetService(serviceName: string): any
		if serviceName == "Players" then
			return playersService
		end
		if serviceName == "ReplicatedStorage" then
			return replicatedStorage
		end
		if serviceName == "RunService" then
			return runService
		end
		error(string.format("unsupported service: %s", serviceName))
		return nil
	end

	game = fakeGame

	return tinyfolk, giant, runService
end

local tinyfolk, giant, runService = createFixture()

local TinyfolkStatusConfig = require("../src/ReplicatedStorage/Shared/Config/TinyfolkStatusConfig")
local TinyfolkStatusService = require("../src/ServerScriptService/Services/TinyfolkStatusService.server")

TinyfolkStatusService.ResetForTests()

do
	TinyfolkStatusService.ResolveNow(tinyfolk, 100)
	assertEqual(tinyfolk:GetAttribute(TinyfolkStatusConfig.Attributes.FearExposure), 0.7, "fear exposure derives from giant proximity")
	assertFalse(tinyfolk:GetAttribute(TinyfolkStatusConfig.Attributes.FearPanic), "fear panic stays below threshold before enough exposure")
	assertEqual(tinyfolk:GetAttribute(TinyfolkStatusConfig.Attributes.ConditionSummary), "Exposure", "fear exposure summary exposed")
end

do
	TinyfolkStatusService.SetCondition(tinyfolk, "Bleed", 3, 200)
	TinyfolkStatusService.SetCondition(tinyfolk, "Stun", 2, 200)
	assertTrue(tinyfolk:GetAttribute(TinyfolkStatusConfig.Attributes.BleedActive), "bleed condition becomes active")
	assertTrue(tinyfolk:GetAttribute(TinyfolkStatusConfig.Attributes.StunActive), "stun condition becomes active")
	assertEqual(tinyfolk:GetAttribute(TinyfolkStatusConfig.Attributes.ConditionSummary), "Exposure,Bleed,Stun", "timed conditions contribute to summary")
end

do
	giant.Character = makeCharacter(makePosition(1, 0, 0), 100)
	for _ = 1, 2 do
		(runService :: any).Heartbeat:Fire()
	end
	assertTrue(tinyfolk:GetAttribute(TinyfolkStatusConfig.Attributes.FearPanic), "near giant sustains panic state")
	assertTrue(type(tinyfolk:GetAttribute(TinyfolkStatusConfig.Attributes.FearPanicUntil)) == "number", "panic exposes until timestamp")
end

print("timed_condition_states_runtime_entrypoint: all checks passed")