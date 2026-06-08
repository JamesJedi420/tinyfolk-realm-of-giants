--!nocheck

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

local globalEnv: any = getfenv()

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
	addChild(
		statusFolder,
		"TimedConditionStateLogic",
		"../../ReplicatedStorage/Shared/TinyfolkStatus/TimedConditionStateLogic"
	)
	addChild(statusFolder, "RaidStatusProjection", "../../ReplicatedStorage/Shared/TinyfolkStatus/RaidStatusProjection")
	addChild(statusFolder, "TrailPressureLogic", "../../ReplicatedStorage/Shared/TinyfolkStatus/TrailPressureLogic")

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

	globalEnv.game = fakeGame

	return tinyfolk, giant, runService
end

local tinyfolk, giant, runService = createFixture()
local runServiceAny = runService :: any

local TinyfolkStatusConfig = require("../src/ReplicatedStorage/Shared/Config/TinyfolkStatusConfig")
local TinyfolkStatusService = require("../src/ServerScriptService/Services/TinyfolkStatusService.server")

TinyfolkStatusService.ResetForTests()
globalEnv._TinyfolkHiding_QueryAPI = nil

do
	TinyfolkStatusService.ResolveNow(tinyfolk, 100)
	assertEqual(
		tinyfolk:GetAttribute(TinyfolkStatusConfig.Attributes.FearExposure),
		0.7,
		"fear exposure derives from giant proximity"
	)
	assertFalse(
		tinyfolk:GetAttribute(TinyfolkStatusConfig.Attributes.FearPanic),
		"fear panic stays below threshold before enough exposure"
	)
	assertEqual(
		tinyfolk:GetAttribute(TinyfolkStatusConfig.Attributes.ConditionSummary),
		"Exposure",
		"fear exposure summary exposed"
	)
	assertEqual(
		tinyfolk:GetAttribute(TinyfolkStatusConfig.Attributes.RaidHudThreatLevel),
		"medium",
		"raid HUD threat bucket exposed"
	)
	assertEqual(
		tinyfolk:GetAttribute(TinyfolkStatusConfig.Attributes.GiantProximityWarningLevel),
		"near",
		"coarse giant proximity warning exposed"
	)
	assertEqual(
		tinyfolk:GetAttribute(TinyfolkStatusConfig.Attributes.FearNearestGiantUserId),
		nil,
		"nearest giant id is not exposed as an attribute"
	)
	assertEqual(
		tinyfolk:GetAttribute(TinyfolkStatusConfig.Attributes.FearNearestGiantDistance),
		nil,
		"nearest giant distance is not exposed as an attribute"
	)
end

do
	TinyfolkStatusService.SetCondition(tinyfolk, "Bleed", 3, 200)
	TinyfolkStatusService.SetCondition(tinyfolk, "Stun", 2, 200)
	assertTrue(tinyfolk:GetAttribute(TinyfolkStatusConfig.Attributes.BleedActive), "bleed condition becomes active")
	assertTrue(tinyfolk:GetAttribute(TinyfolkStatusConfig.Attributes.StunActive), "stun condition becomes active")
	assertEqual(
		tinyfolk:GetAttribute(TinyfolkStatusConfig.Attributes.ConditionSummary),
		"Exposure,Bleed,Stun",
		"timed conditions contribute to summary"
	)
	assertTrue(
		string.find(tinyfolk:GetAttribute(TinyfolkStatusConfig.Attributes.RaidHudPersonalEffects), "bleed", 1, true)
			~= nil,
		"raid HUD personal effects includes bleed"
	)
end

do
	giant.Character = makeCharacter(makePosition(1, 0, 0), 100)
	TinyfolkStatusService.ResolveNow(tinyfolk, 210)
	TinyfolkStatusService.ResolveNow(tinyfolk, 211)
	assertTrue(tinyfolk:GetAttribute(TinyfolkStatusConfig.Attributes.FearPanic), "near giant sustains panic state")
	assertTrue(
		type(tinyfolk:GetAttribute(TinyfolkStatusConfig.Attributes.FearPanicUntil)) == "number",
		"panic exposes until timestamp"
	)
	assertEqual(
		tinyfolk:GetAttribute(TinyfolkStatusConfig.Attributes.RaidHudThreatLevel),
		"high",
		"raid HUD panic threat bucket exposed"
	)
	assertEqual(
		tinyfolk:GetAttribute(TinyfolkStatusConfig.Attributes.GiantProximityWarningLevel),
		"danger",
		"panic projects danger proximity warning"
	)
end

do
	giant.Character = makeCharacter(makePosition(1, 0, 0), 0)
	TinyfolkStatusService.ResolveNow(tinyfolk, 300)
	assertEqual(
		tinyfolk:GetAttribute(TinyfolkStatusConfig.Attributes.GiantProximityWarningLevel),
		"none",
		"dead giant clears proximity warning"
	)
	assertEqual(
		tinyfolk:GetAttribute(TinyfolkStatusConfig.Attributes.FearNearestGiantUserId),
		nil,
		"dead giant does not leak stale nearest id"
	)
	assertEqual(
		tinyfolk:GetAttribute(TinyfolkStatusConfig.Attributes.FearNearestGiantDistance),
		nil,
		"dead giant does not leak stale nearest distance"
	)
end

do
	TinyfolkStatusService.ResetForTests()
	tinyfolk.Character = makeCharacter(makePosition(0, 0, 0), 100)
	TinyfolkStatusService.ResolveNow(tinyfolk, 400)
	local firstTrailSnapshot = TinyfolkStatusService.GetTrailSnapshot(tinyfolk, 400)
	assertEqual(firstTrailSnapshot.sampleCount, 1, "first trail sample recorded")
	assertFalse(firstTrailSnapshot.hasPressure, "single trail sample has no segment pressure")

	tinyfolk.Character = makeCharacter(makePosition(6, 0, 0), 100)
	TinyfolkStatusService.ResolveNow(tinyfolk, 401)
	local secondTrailSnapshot = TinyfolkStatusService.GetTrailSnapshot(tinyfolk, 401)
	assertEqual(secondTrailSnapshot.sampleCount, 2, "second movement sample recorded")
	assertTrue(secondTrailSnapshot.hasPressure, "second movement sample yields trail pressure")
	assertEqual(secondTrailSnapshot.segmentCount, 1, "single trail segment projected")

	local querySnapshot = globalEnv._TinyfolkStatusService_QueryAPI.GetTrailSnapshot(tinyfolk.UserId, 401)
	assertEqual(querySnapshot.segmentCount, 1, "query api exposes trail snapshot")

	globalEnv._TinyfolkHiding_QueryAPI = {
		IsPlayerHiding = function(userId: number): boolean
			return userId == tinyfolk.UserId
		end,
	}
	tinyfolk.Character = makeCharacter(makePosition(12, 0, 0), 100)
	TinyfolkStatusService.ResolveNow(tinyfolk, 402)
	local hiddenTrailSnapshot = TinyfolkStatusService.GetTrailSnapshot(tinyfolk, 402)
	assertEqual(hiddenTrailSnapshot.sampleCount, 2, "hidden tinyfolk suppresses fresh trail sample")
	assertEqual(hiddenTrailSnapshot.segmentCount, 1, "hidden tinyfolk keeps existing trail until decay")

	globalEnv._TinyfolkHiding_QueryAPI = {
		IsPlayerHiding = function(_userId: number)
			error("hiding query fault")
		end,
	}
	tinyfolk.Character = makeCharacter(makePosition(18, 0, 0), 100)
	local resolveOk = pcall(TinyfolkStatusService.ResolveNow, tinyfolk, 403)
	assertTrue(resolveOk, "hiding query fault does not break status tick")
	local faultTrailSnapshot = TinyfolkStatusService.GetTrailSnapshot(tinyfolk, 403)
	assertEqual(faultTrailSnapshot.sampleCount, 3, "faulting hiding query falls back to non-hidden trail sampling")
	assertEqual(faultTrailSnapshot.segmentCount, 2, "faulting hiding query still advances coarse trail pressure")

	tinyfolk:SetAttribute("Role", "Giant")
	runServiceAny.Heartbeat:Fire()
	local roleShiftTrailSnapshot = TinyfolkStatusService.GetTrailSnapshot(tinyfolk, 404)
	assertEqual(roleShiftTrailSnapshot.sampleCount, 0, "role change clears stale trail state")
	assertEqual(roleShiftTrailSnapshot.segmentCount, 0, "role change clears stale trail segments")
	tinyfolk:SetAttribute("Role", "Tinyfolk")
	globalEnv._TinyfolkHiding_QueryAPI = nil
end

print("timed_condition_states_runtime_entrypoint: all checks passed")
