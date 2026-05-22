--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local TinyfolkMovement = Shared:WaitForChild("TinyfolkMovement")
local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local TinyfolkMovementTraitConfig = require(Config:WaitForChild("TinyfolkMovementTraitConfig"))
local PostCrossingBurstLogic = require(TinyfolkMovement:WaitForChild("PostCrossingBurstLogic"))
local SprintStaminaLogic = require(TinyfolkMovement:WaitForChild("SprintStaminaLogic"))

local TinyfolkMovementTraitService = {}

type BurstState = PostCrossingBurstLogic.BurstState
type BurstOutcome = PostCrossingBurstLogic.BurstOutcome
type SprintState = SprintStaminaLogic.SprintState
type SprintResult = SprintStaminaLogic.SprintResult

local stateByUserId: { [number]: BurstState? } = {}
local restoreWalkSpeedByUserId: { [number]: number? } = {}
local sprintStateByUserId: { [number]: any } = {}
local sprintRestoreWalkSpeedByUserId: { [number]: number? } = {}

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
	if humanoid == nil then
		return false
	end
	return (humanoid :: any).Health > 0
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

local function getTinyfolkBaseWalkSpeed(): number
	local tinyfolkBase: any = RoleConfig.HumanoidBaseByRole[RoleConfig.Roles.Tinyfolk]
	if type(tinyfolkBase) == "table" and type(tinyfolkBase.walkSpeed) == "number" then
		return (tinyfolkBase :: any).walkSpeed
	end
	return 16
end

local function getSprintState(userId: number): any
	local existing = sprintStateByUserId[userId]
	if existing ~= nil then
		return existing
	end

	local created: any = {}
	sprintStateByUserId[userId] = created
	return created
end

local function applySprintAttributes(player: Player, snapshot: any)
	local attributes = TinyfolkMovementTraitConfig.Attributes
	player:SetAttribute(attributes.SprintRequested, snapshot.requestedSprint)
	player:SetAttribute(attributes.SprintActive, snapshot.isSprinting)
	player:SetAttribute(attributes.SprintExhausted, snapshot.isExhausted)
	player:SetAttribute(attributes.SprintBreathless, snapshot.isBreathless)
	player:SetAttribute(attributes.SprintStamina, snapshot.stamina)
	player:SetAttribute(attributes.SprintMaxStamina, snapshot.maxStamina)
	player:SetAttribute(attributes.SprintStaminaRatio, snapshot.staminaRatio)
	player:SetAttribute(attributes.SprintSpeedMultiplier, snapshot.speedMultiplier)
	player:SetAttribute(attributes.SprintRecoveryThreshold, snapshot.recoveryThreshold)
	player:SetAttribute(attributes.SprintReason, snapshot.reason)
end

local function applySprintWalkSpeed(player: Player, snapshot: any)
	local humanoid = getHumanoid(player)
	if humanoid == nil then
		return
	end

	local restoreWalkSpeed = sprintRestoreWalkSpeedByUserId[player.UserId]
	if snapshot.isSprinting then
		if restoreWalkSpeed == nil then
			restoreWalkSpeed = (humanoid :: any).WalkSpeed
			if restoreWalkSpeed <= 0 then
				restoreWalkSpeed = getTinyfolkBaseWalkSpeed()
			end
			sprintRestoreWalkSpeedByUserId[player.UserId] = restoreWalkSpeed
		end

		local maxWalkSpeed = TinyfolkMovementTraitConfig.SprintMaxWalkSpeed
		local targetWalkSpeed = (restoreWalkSpeed or getTinyfolkBaseWalkSpeed()) * snapshot.speedMultiplier
		if type(maxWalkSpeed) == "number" and maxWalkSpeed == maxWalkSpeed then
			targetWalkSpeed = math.min(targetWalkSpeed, maxWalkSpeed)
		end
		(humanoid :: any).WalkSpeed = targetWalkSpeed
		return
	end

	if restoreWalkSpeed ~= nil then
		(humanoid :: any).WalkSpeed = restoreWalkSpeed
		sprintRestoreWalkSpeedByUserId[player.UserId] = nil
	end
end

local function resolveSprintTick(player: Player, requestedSprint: boolean, now: number): SprintResult
	local humanoid = getHumanoid(player)
	local root = getHumanoidRootPart(player)
	local state = getSprintState(player.UserId)
	state.player = player

	if sprintRestoreWalkSpeedByUserId[player.UserId] == nil and humanoid ~= nil then
		sprintRestoreWalkSpeedByUserId[player.UserId] = (humanoid :: any).WalkSpeed
	end

	local nextState, outcome = SprintStaminaLogic.ResolveTick(state, TinyfolkMovementTraitConfig, {
		now = now,
		requestedSprint = requestedSprint,
		isTinyfolk = player:GetAttribute("Role") == RoleConfig.Roles.Tinyfolk,
		hasTrait = true,
		hasAliveHumanoid = isAlive(humanoid),
		hasRootPart = root ~= nil,
	})

	local nextStateAny: any = nextState
	nextStateAny.player = player
	nextStateAny.restoreWalkSpeed = sprintRestoreWalkSpeedByUserId[player.UserId]
	sprintStateByUserId[player.UserId] = nextStateAny
	applySprintAttributes(player, outcome.snapshot)
	applySprintWalkSpeed(player, outcome.snapshot)
	return outcome
end

local function syncSprintState(player: Player)
	local state = sprintStateByUserId[player.UserId]
	if state == nil then
		return
	end

	resolveSprintTick(player, state.requestedSprint == true, os.clock())
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
			(humanoid :: any).WalkSpeed = restoreWalkSpeed
		end

		restoreWalkSpeedByUserId[player.UserId] = nil
		applyAttributes(player, os.clock())
		debugLog(
			string.format("Restored post-crossing burst userId=%d walkSpeed=%.1f", player.UserId, restoreWalkSpeed)
		)
	end)
end

function TinyfolkMovementTraitService.OnValidRouteCrossing(player: Player, routeId: string): BurstOutcome
	local now = os.clock()
	local humanoid = getHumanoid(player)
	local root = getHumanoidRootPart(player)
	local state = getState(player.UserId)
	local restoreWalkSpeed = restoreWalkSpeedByUserId[player.UserId]
	if restoreWalkSpeed == nil and humanoid ~= nil then
		restoreWalkSpeed = (humanoid :: any).WalkSpeed
	end

	local nextState, outcome = PostCrossingBurstLogic.ResolveCrossing(state, TinyfolkMovementTraitConfig, {
		now = now,
		validCrossing = true,
		routeId = routeId,
		isTinyfolk = player:GetAttribute("Role") == RoleConfig.Roles.Tinyfolk,
		hasTrait = player:GetAttribute(TinyfolkMovementTraitConfig.TraitAttributeName) == true,
		hasAliveHumanoid = isAlive(humanoid),
		hasRootPart = root ~= nil,
		currentWalkSpeed = if humanoid ~= nil then (humanoid :: any).WalkSpeed else nil,
		baseWalkSpeed = restoreWalkSpeed,
	})

	stateByUserId[player.UserId] = nextState
	applyAttributes(player, now)

	if outcome.accepted and humanoid ~= nil and outcome.targetWalkSpeed ~= nil and outcome.restoreWalkSpeed ~= nil then
		restoreWalkSpeedByUserId[player.UserId] = outcome.restoreWalkSpeed
		local humanoidAny: any = humanoid
		humanoidAny.WalkSpeed = outcome.targetWalkSpeed
		scheduleRestore(player, outcome.burstActiveUntil :: number, outcome.restoreWalkSpeed)
		debugLog(
			string.format(
				"Accepted post-crossing burst userId=%d routeId=%s targetWalkSpeed=%.1f cooldownUntil=%.2f traceUntil=%.2f",
				player.UserId,
				routeId,
				outcome.targetWalkSpeed,
				outcome.burstCooldownUntil or 0,
				outcome.traceCostUntil or 0
			)
		)
	end

	return outcome
end

function TinyfolkMovementTraitService.SetSprintRequested(player: Player, requestedSprint: boolean): SprintResult
	return resolveSprintTick(player, requestedSprint == true, os.clock())
end

function TinyfolkMovementTraitService.SetSprintRequestedAtTime(
	player: Player,
	requestedSprint: boolean,
	now: number
): SprintResult
	return resolveSprintTick(player, requestedSprint == true, now)
end

function TinyfolkMovementTraitService.GetSprintSnapshot(player: Player): any
	local state = sprintStateByUserId[player.UserId]
	return SprintStaminaLogic.Snapshot(state, TinyfolkMovementTraitConfig)
end

function TinyfolkMovementTraitService.SynchronizeSprint(player: Player)
	syncSprintState(player)
end

function TinyfolkMovementTraitService.ResetForTests()
	stateByUserId = {}
	restoreWalkSpeedByUserId = {}
	sprintStateByUserId = {}
	sprintRestoreWalkSpeedByUserId = {}
end

Players.PlayerRemoving:Connect(function(player: Player)
	stateByUserId[player.UserId] = nil
	restoreWalkSpeedByUserId[player.UserId] = nil
	sprintStateByUserId[player.UserId] = nil
	sprintRestoreWalkSpeedByUserId[player.UserId] = nil
end)

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for _, sprintState in pairs(sprintStateByUserId) do
		local player = (sprintState :: any).player
		if player ~= nil and typeof(player) == "Instance" and player:IsA("Player") then
			resolveSprintTick(player :: Player, (sprintState :: any).requestedSprint == true, now)
		end
	end
end)

return TinyfolkMovementTraitService
