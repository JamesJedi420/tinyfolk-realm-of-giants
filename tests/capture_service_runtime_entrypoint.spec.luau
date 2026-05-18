--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local CaptureConfig = require(Config:WaitForChild("CaptureConfig"))
local CaptureState = require(GiantRealm:WaitForChild("CaptureState"))

local captureServicePath = "ServerScriptService:FindFirstChild('CaptureService')"
local MatchSimulation = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MatchSimulation"))

local function assert(condition: boolean, message: string)
	if not condition then
		error(message)
	end
end

local testsPassed = 0
local testsFailed = 0

local function test(name: string, fn: () -> ())
	local success, err = pcall(fn)
	if success then
		testsPassed += 1
		print("✓", name)
	else
		testsFailed += 1
		print("✗", name)
		print("  ", err)
	end
end

local function getCaptureQueryApi(): any
	local globalValue: any = _G
	if type(globalValue) ~= "table" then
		return nil
	end
	return globalValue._CaptureService_QueryAPI
end

local function resetState()
	local api = getCaptureQueryApi()
	if api ~= nil and type(api.ResetForTests) == "function" then
		api:ResetForTests()
	end
end

local function createMockPlayer(userId: number, role: string): Player?
	local player = Instance.new("Player")
	player.UserId = userId
	player:SetAttribute("Role", role)
	player:SetAttribute("DownedIsDowned", false)

	local character = Instance.new("Model")
	character.Name = "Character"
	character.Parent = workspace

	local humanoidRoot = Instance.new("Part")
	humanoidRoot.Name = "HumanoidRootPart"
	humanoidRoot.Position = Vector3.new(0, 5, 0)
	humanoidRoot.CanCollide = false
	humanoidRoot.Parent = character

	local humanoid = Instance.new("Humanoid")
	humanoid.Health = 100
	humanoid.MaxHealth = 100
	humanoid.Parent = character

	player.Character = character

	return player
end

local function cleanupMockPlayer(player: Player?)
	if player == nil then
		return
	end

	if player.Character then
		player.Character:Destroy()
	end

	player:Destroy()
end

local function setPlayerRole(player: Player, role: string)
	player:SetAttribute("Role", role)
end

local function setPlayerDowned(player: Player, isDowned: boolean)
	player:SetAttribute("DownedIsDowned", isDowned)
end

local function setPlayerAlive(player: Player, isAlive: boolean)
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			if isAlive then
				humanoid.Health = 100
			else
				humanoid.Health = 0
			end
		end
	end
end

local function setPlayerPosition(player: Player, position: Vector3)
	local character = player.Character
	if character then
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			root.Position = position
		end
	end
end

test("RequestCapture accepts valid capture when target downed", function()
	resetState()
	local custodian = createMockPlayer(1, "Giant")
	local target = createMockPlayer(2, "Tinyfolk")

	setPlayerPosition(custodian, Vector3.new(0, 5, 0))
	setPlayerPosition(target, Vector3.new(0, 5, 0))
	setPlayerDowned(target, true)

	local api = getCaptureQueryApi()
	assert(api ~= nil, "capture query api missing")
	if api then
		local result = api:RequestCapture(1, 2, 1.0)
		assert(result.accepted == true, "capture should be accepted")
		assert(result.reason == "accepted", "reason should be accepted")
	end

	cleanupMockPlayer(custodian)
	cleanupMockPlayer(target)
end)

test("RequestCapture rejects when custodian not giant", function()
	resetState()
	local custodian = createMockPlayer(1, "Tinyfolk")
	local target = createMockPlayer(2, "Tinyfolk")

	setPlayerPosition(custodian, Vector3.new(0, 5, 0))
	setPlayerPosition(target, Vector3.new(0, 5, 0))
	setPlayerDowned(target, true)

	local api = getCaptureQueryApi()
	assert(api ~= nil, "capture query api missing")
	if api then
		local result = api:RequestCapture(1, 2, 1.0)
		assert(result.accepted == false, "capture should be rejected")
		assert(result.reason == "custodian_not_giant", "reason should be custodian_not_giant")
	end

	cleanupMockPlayer(custodian)
	cleanupMockPlayer(target)
end)

test("RequestCapture rejects when target not tinyfolk", function()
	resetState()
	local custodian = createMockPlayer(1, "Giant")
	local target = createMockPlayer(2, "Giant")

	setPlayerPosition(custodian, Vector3.new(0, 5, 0))
	setPlayerPosition(target, Vector3.new(0, 5, 0))
	setPlayerDowned(target, true)

	local api = getCaptureQueryApi()
	assert(api ~= nil, "capture query api missing")
	if api then
		local result = api:RequestCapture(1, 2, 1.0)
		assert(result.accepted == false, "capture should be rejected")
		assert(result.reason == "target_not_tinyfolk", "reason should be target_not_tinyfolk")
	end

	cleanupMockPlayer(custodian)
	cleanupMockPlayer(target)
end)

test("RequestCapture rejects when target not downed", function()
	resetState()
	local custodian = createMockPlayer(1, "Giant")
	local target = createMockPlayer(2, "Tinyfolk")

	setPlayerPosition(custodian, Vector3.new(0, 5, 0))
	setPlayerPosition(target, Vector3.new(0, 5, 0))
	setPlayerDowned(target, false)

	local api = getCaptureQueryApi()
	assert(api ~= nil, "capture query api missing")
	if api then
		local result = api:RequestCapture(1, 2, 1.0)
		assert(result.accepted == false, "capture should be rejected")
		assert(result.reason == "target_not_downed", "reason should be target_not_downed")
	end

	cleanupMockPlayer(custodian)
	cleanupMockPlayer(target)
end)

test("RequestCapture rejects when custodian dead", function()
	resetState()
	local custodian = createMockPlayer(1, "Giant")
	local target = createMockPlayer(2, "Tinyfolk")

	setPlayerPosition(custodian, Vector3.new(0, 5, 0))
	setPlayerPosition(target, Vector3.new(0, 5, 0))
	setPlayerAlive(custodian, false)
	setPlayerDowned(target, true)

	local api = getCaptureQueryApi()
	assert(api ~= nil, "capture query api missing")
	if api then
		local result = api:RequestCapture(1, 2, 1.0)
		assert(result.accepted == false, "capture should be rejected")
		assert(result.reason == "custodian_not_alive", "reason should be custodian_not_alive")
	end

	cleanupMockPlayer(custodian)
	cleanupMockPlayer(target)
end)

test("RequestCapture rejects when out of range", function()
	resetState()
	local custodian = createMockPlayer(1, "Giant")
	local target = createMockPlayer(2, "Tinyfolk")

	setPlayerPosition(custodian, Vector3.new(0, 5, 0))
	setPlayerPosition(target, Vector3.new(100, 5, 0))
	setPlayerDowned(target, true)

	local api = getCaptureQueryApi()
	assert(api ~= nil, "capture query api missing")
	if api then
		local result = api:RequestCapture(1, 2, 1.0)
		assert(result.accepted == false, "capture should be rejected")
		assert(result.reason == "target_out_of_range", "reason should be target_out_of_range")
	end

	cleanupMockPlayer(custodian)
	cleanupMockPlayer(target)
end)

test("RequestCapture rejects when custodian not found", function()
	resetState()
	local api = getCaptureQueryApi()
	assert(api ~= nil, "capture query api missing")
	if api then
		local result = api:RequestCapture(999, 2, 1.0)
		assert(result.accepted == false, "capture should be rejected")
		assert(result.reason == "custodian_not_found", "reason should be custodian_not_found")
	end
end)

test("RequestCapture rejects when target not found", function()
	resetState()
	local custodian = createMockPlayer(1, "Giant")
	setPlayerPosition(custodian, Vector3.new(0, 5, 0))
	setPlayerDowned(custodian, false)

	local api = getCaptureQueryApi()
	assert(api ~= nil, "capture query api missing")
	if api then
		local result = api:RequestCapture(1, 999, 1.0)
		assert(result.accepted == false, "capture should be rejected")
		assert(result.reason == "target_not_found", "reason should be target_not_found")
	end

	cleanupMockPlayer(custodian)
end)

test("RequestCapture enforces cooldown between requests", function()
	resetState()
	local custodian = createMockPlayer(1, "Giant")
	local target1 = createMockPlayer(2, "Tinyfolk")
	local target2 = createMockPlayer(3, "Tinyfolk")

	setPlayerPosition(custodian, Vector3.new(0, 5, 0))
	setPlayerPosition(target1, Vector3.new(0, 5, 0))
	setPlayerPosition(target2, Vector3.new(5, 5, 0))
	setPlayerDowned(target1, true)
	setPlayerDowned(target2, true)

	local api = getCaptureQueryApi()
	assert(api ~= nil, "capture query api missing")
	if api then
		local result1 = api:RequestCapture(1, 2, 1.0)
		assert(result1.accepted == true, "first capture should be accepted")

		local result2 = api:RequestCapture(1, 3, 1.05)
		assert(result2.accepted == false, "second capture within cooldown should be rejected")
		assert(result2.reason == "request_cooldown", "reason should be request_cooldown")

		local result3 = api:RequestCapture(1, 3, 1.3)
		assert(result3.accepted == true, "capture after cooldown should be accepted")
	end

	cleanupMockPlayer(custodian)
	cleanupMockPlayer(target1)
	cleanupMockPlayer(target2)
end)

test("RequestCapture rejects duplicate capture of same target", function()
	resetState()
	local custodian1 = createMockPlayer(1, "Giant")
	local custodian2 = createMockPlayer(3, "Giant")
	local target = createMockPlayer(2, "Tinyfolk")

	setPlayerPosition(custodian1, Vector3.new(0, 5, 0))
	setPlayerPosition(custodian2, Vector3.new(10, 5, 0))
	setPlayerPosition(target, Vector3.new(0, 5, 0))
	setPlayerDowned(target, true)

	local api = getCaptureQueryApi()
	assert(api ~= nil, "capture query api missing")
	if api then
		local result1 = api:RequestCapture(1, 2, 1.0)
		assert(result1.accepted == true, "first capture should be accepted")

		local result2 = api:RequestCapture(3, 2, 1.5)
		assert(result2.accepted == false, "second capture of same target should be rejected")
		assert(result2.reason == "target_already_captured", "reason should be target_already_captured")
	end

	cleanupMockPlayer(custodian1)
	cleanupMockPlayer(custodian2)
	cleanupMockPlayer(target)
end)

test("RequestCapture rejects custodian already holding target", function()
	resetState()
	local custodian = createMockPlayer(1, "Giant")
	local target1 = createMockPlayer(2, "Tinyfolk")
	local target2 = createMockPlayer(3, "Tinyfolk")

	setPlayerPosition(custodian, Vector3.new(0, 5, 0))
	setPlayerPosition(target1, Vector3.new(0, 5, 0))
	setPlayerPosition(target2, Vector3.new(5, 5, 0))
	setPlayerDowned(target1, true)
	setPlayerDowned(target2, true)

	local api = getCaptureQueryApi()
	assert(api ~= nil, "capture query api missing")
	if api then
		local result1 = api:RequestCapture(1, 2, 1.0)
		assert(result1.accepted == true, "first capture should be accepted")

		local result2 = api:RequestCapture(1, 3, 2.0)
		assert(result2.accepted == false, "custodian already holding should be rejected")
		assert(result2.reason == "custodian_already_holding", "reason should be custodian_already_holding")
	end

	cleanupMockPlayer(custodian)
	cleanupMockPlayer(target1)
	cleanupMockPlayer(target2)
end)

test("GetTargetCapture returns active capture", function()
	resetState()
	local custodian = createMockPlayer(1, "Giant")
	local target = createMockPlayer(2, "Tinyfolk")

	setPlayerPosition(custodian, Vector3.new(0, 5, 0))
	setPlayerPosition(target, Vector3.new(0, 5, 0))
	setPlayerDowned(target, true)

	local api = getCaptureQueryApi()
	assert(api ~= nil, "capture query api missing")
	if api then
		local result = api:RequestCapture(1, 2, 1.0)
		assert(result.accepted == true, "capture should be accepted")

		local capture = api:GetTargetCapture(2)
		assert(capture ~= nil, "capture should exist")
		if capture then
			assert(capture.custodianUserId == 1, "custodian user id mismatch")
		end
	end

	cleanupMockPlayer(custodian)
	cleanupMockPlayer(target)
end)

test("GetCustodianCapture returns active capture", function()
	resetState()
	local custodian = createMockPlayer(1, "Giant")
	local target = createMockPlayer(2, "Tinyfolk")

	setPlayerPosition(custodian, Vector3.new(0, 5, 0))
	setPlayerPosition(target, Vector3.new(0, 5, 0))
	setPlayerDowned(target, true)

	local api = getCaptureQueryApi()
	assert(api ~= nil, "capture query api missing")
	if api then
		local result = api:RequestCapture(1, 2, 1.0)
		assert(result.accepted == true, "capture should be accepted")

		local capture = api:GetCustodianCapture(1)
		assert(capture ~= nil, "capture should exist")
		if capture then
			assert(capture.targetUserId == 2, "target user id mismatch")
		end
	end

	cleanupMockPlayer(custodian)
	cleanupMockPlayer(target)
end)

test("GetAllCaptures returns all captures", function()
	resetState()
	local custodian1 = createMockPlayer(1, "Giant")
	local custodian2 = createMockPlayer(3, "Giant")
	local target1 = createMockPlayer(2, "Tinyfolk")
	local target2 = createMockPlayer(4, "Tinyfolk")

	setPlayerPosition(custodian1, Vector3.new(0, 5, 0))
	setPlayerPosition(custodian2, Vector3.new(0, 5, 0))
	setPlayerPosition(target1, Vector3.new(0, 5, 0))
	setPlayerPosition(target2, Vector3.new(0, 5, 0))
	setPlayerDowned(target1, true)
	setPlayerDowned(target2, true)

	local api = getCaptureQueryApi()
	assert(api ~= nil, "capture query api missing")
	if api then
		api:RequestCapture(1, 2, 1.0)
		api:RequestCapture(3, 4, 1.5)

		local captures = api:GetAllCaptures()
		assert(#captures == 2, "should have 2 captures")
	end

	cleanupMockPlayer(custodian1)
	cleanupMockPlayer(custodian2)
	cleanupMockPlayer(target1)
	cleanupMockPlayer(target2)
end)

test("Capture attributes reflect active captures", function()
	resetState()
	local custodian = createMockPlayer(1, "Giant")
	local target = createMockPlayer(2, "Tinyfolk")

	setPlayerPosition(custodian, Vector3.new(0, 5, 0))
	setPlayerPosition(target, Vector3.new(0, 5, 0))
	setPlayerDowned(target, true)

	local api = getCaptureQueryApi()
	assert(api ~= nil, "capture query api missing")
	if api then
		local result = api:RequestCapture(1, 2, 1.0)
		assert(result.accepted == true, "capture should be accepted")

		local attrs = CaptureConfig.StateAttributes
		assert(custodian:GetAttribute(attrs.CaptureActive) == true, "custodian should have CaptureActive=true")
		assert(target:GetAttribute(attrs.CaptureActive) == true, "target should have CaptureActive=true")
		assert(target:GetAttribute(attrs.CaptureCustodianUserId) == 1, "target should have correct custodian user id")
	end

	cleanupMockPlayer(custodian)
	cleanupMockPlayer(target)
end)

test("Capture expires automatically after custody window", function()
	resetState()
	local custodian = createMockPlayer(1, "Giant")
	local target = createMockPlayer(2, "Tinyfolk")

	setPlayerPosition(custodian, Vector3.new(0, 5, 0))
	setPlayerPosition(target, Vector3.new(0, 5, 0))
	setPlayerDowned(target, true)

	local api = getCaptureQueryApi()
	assert(api ~= nil, "capture query api missing")
	if api then
		local result = api:RequestCapture(1, 2, 1.0)
		assert(result.accepted == true, "capture should be accepted")

		local capturesBefore = api:GetAllCaptures(8.5)
		assert(#capturesBefore == 1, "should have 1 capture before expiry")

		local capturesAfter = api:GetAllCaptures(10.0)
		assert(#capturesAfter == 0, "should have 0 captures after expiry")
	end

	cleanupMockPlayer(custodian)
	cleanupMockPlayer(target)
end)

print("\n" .. testsPassed .. " passed, " .. testsFailed .. " failed")
if testsFailed > 0 then
	error(testsFailed .. " tests failed")
end
