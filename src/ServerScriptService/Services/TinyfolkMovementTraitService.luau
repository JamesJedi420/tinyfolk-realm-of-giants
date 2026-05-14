--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local TinyfolkMovement = Shared:WaitForChild("TinyfolkMovement")
local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local TinyfolkMovementTraitConfig = require(Config:WaitForChild("TinyfolkMovementTraitConfig"))
local PostCrossingBurstLogic = require(TinyfolkMovement:WaitForChild("PostCrossingBurstLogic"))

local TinyfolkMovementTraitService = {}

type BurstState = PostCrossingBurstLogic.BurstState
type BurstOutcome = PostCrossingBurstLogic.BurstOutcome

local stateByUserId: { [number]: BurstState? } = {}
local restoreWalkSpeedByUserId: { [number]: number? } = {}

local function debugLog(message: string)
	print(string.format("[TinyfolkMovementTraitService] %s", message))
end

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	if character == nil then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		return humanoid :: Humanoid
	end

	return nil
end

local function getHumanoidRootPart(player: Player): BasePart?
	local character = player.Character
	if character == nil then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root :: BasePart
	end

	return nil
end

local function isAlive(humanoid: Humanoid?): boolean
	return humanoid ~= nil and humanoid.Health > 0
end

local function getState(userId: number): BurstState
	local existing = stateByUserId[userId]
	if existing then
		return existing
	end

	local created: BurstState = {}
	stateByUserId[userId] = created
	return created
end

local function applyAttributes(player: Player, now: number)
	local state = getState(player.UserId)
	local snapshot = PostCrossingBurstLogic.Snapshot(state, now)
	local attributes = TinyfolkMovementTraitConfig.Attributes

	player:SetAttribute(attributes.BurstActive, snapshot.burstActive)
	player:SetAttribute(attributes.BurstUntil, snapshot.burstActiveUntil)
	player:SetAttribute(attributes.BurstCooldownUntil, snapshot.burstCooldownUntil)
	player:SetAttribute(attributes.SharedBurstCooldownUntil, snapshot.sharedBurstCooldownUntil)
	player:SetAttribute(attributes.TraceCostActive, snapshot.traceCostActive)
	player:SetAttribute(attributes.TraceCostUntil, snapshot.traceCostUntil)
	player:SetAttribute(attributes.TraceCostReason, snapshot.traceCostReason)
end

local function scheduleRestore(player: Player, activeUntil: number, restoreWalkSpeed: number)
	local delaySeconds = math.max(activeUntil - os.clock(), 0)
	task.delay(delaySeconds, function()
		local state = stateByUserId[player.UserId]
		if state == nil or state.burstActiveUntil ~= activeUntil then
			return
		end

		local humanoid = getHumanoid(player)
		if humanoid ~= nil then
			humanoid.WalkSpeed = restoreWalkSpeed
		end

		restoreWalkSpeedByUserId[player.UserId] = nil
		applyAttributes(player, os.clock())
		debugLog(string.format("Restored post-crossing burst userId=%d walkSpeed=%.1f", player.UserId, restoreWalkSpeed))
	end)
end

function TinyfolkMovementTraitService.OnValidRouteCrossing(player: Player, routeId: string): BurstOutcome
	local now = os.clock()
	local humanoid = getHumanoid(player)
	local root = getHumanoidRootPart(player)
	local state = getState(player.UserId)
	local restoreWalkSpeed = restoreWalkSpeedByUserId[player.UserId]
	if restoreWalkSpeed == nil and humanoid ~= nil then
		restoreWalkSpeed = humanoid.WalkSpeed
	end

	local nextState, outcome = PostCrossingBurstLogic.ResolveCrossing(state, TinyfolkMovementTraitConfig, {
		now = now,
		validCrossing = true,
		routeId = routeId,
		isTinyfolk = player:GetAttribute("Role") == RoleConfig.Roles.Tinyfolk,
		hasTrait = player:GetAttribute(TinyfolkMovementTraitConfig.TraitAttributeName) == true,
		hasAliveHumanoid = isAlive(humanoid),
		hasRootPart = root ~= nil,
		currentWalkSpeed = if humanoid ~= nil then humanoid.WalkSpeed else nil,
		baseWalkSpeed = restoreWalkSpeed,
	})

	stateByUserId[player.UserId] = nextState
	applyAttributes(player, now)

	if outcome.accepted and humanoid ~= nil and outcome.targetWalkSpeed ~= nil and outcome.restoreWalkSpeed ~= nil then
		restoreWalkSpeedByUserId[player.UserId] = outcome.restoreWalkSpeed
		humanoid.WalkSpeed = outcome.targetWalkSpeed
		scheduleRestore(player, outcome.burstActiveUntil :: number, outcome.restoreWalkSpeed)
		debugLog(string.format(
			"Accepted post-crossing burst userId=%d routeId=%s targetWalkSpeed=%.1f cooldownUntil=%.2f traceUntil=%.2f",
			player.UserId,
			routeId,
			outcome.targetWalkSpeed,
			outcome.burstCooldownUntil or 0,
			outcome.traceCostUntil or 0
		))
	end

	return outcome
end

function TinyfolkMovementTraitService.ResetForTests()
	stateByUserId = {}
	restoreWalkSpeedByUserId = {}
end

Players.PlayerRemoving:Connect(function(player: Player)
	stateByUserId[player.UserId] = nil
	restoreWalkSpeedByUserId[player.UserId] = nil
end)

return TinyfolkMovementTraitService
