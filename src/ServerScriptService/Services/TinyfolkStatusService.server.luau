--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local TinyfolkStatusConfig = require(Config:WaitForChild("TinyfolkStatusConfig"))
local TimedConditionStateLogic = require(Shared:WaitForChild("TinyfolkStatus"):WaitForChild("TimedConditionStateLogic"))
local RaidStatusProjection = require(Shared:WaitForChild("TinyfolkStatus"):WaitForChild("RaidStatusProjection"))

local TinyfolkStatusService = {}

type TimedConditionState = any

local stateByUserId: { [number]: TimedConditionState? } = {}

local function debugLog(message: string)
	print(string.format("[TinyfolkStatusService] %s", message))
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

local function getOrCreateState(userId: number): TimedConditionState
	local existing = stateByUserId[userId]
	if existing ~= nil then
		return existing
	end

	local created: TimedConditionState = {}
	stateByUserId[userId] = created
	return created
end

local function getPlayerPosition(player: Player): any?
	local root = getHumanoidRootPart(player)
	if root == nil then
		return nil
	end
	return (root :: any).Position
end

local function getFearSourcesForPlayer(player: Player): { any }
	local fearSources = {}
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player and otherPlayer:GetAttribute("Role") == RoleConfig.Roles.Giant then
			local humanoid = getHumanoid(otherPlayer)
			local position = getPlayerPosition(otherPlayer)
			if isAlive(humanoid) and position ~= nil then
				table.insert(fearSources, {
					userId = otherPlayer.UserId,
					position = position,
				})
			end
		end
	end
	return fearSources
end

local function applyAttributes(player: Player, snapshot: any)
	local attributes = TinyfolkStatusConfig.Attributes
	player:SetAttribute(attributes.FearExposure, snapshot.fearExposure)
	player:SetAttribute(attributes.FearExposureRatio, snapshot.fearExposureRatio)
	player:SetAttribute(attributes.FearActive, snapshot.fearActive)
	player:SetAttribute(attributes.FearPanic, snapshot.fearPanic)
	player:SetAttribute(attributes.FearPanicUntil, snapshot.fearPanicUntil)
	player:SetAttribute(attributes.FearNearestGiantUserId, nil)
	player:SetAttribute(attributes.FearNearestGiantDistance, nil)
	player:SetAttribute(attributes.GiantProximityWarningLevel, snapshot.giantProximityWarningLevel)
	player:SetAttribute(attributes.ConditionSummary, snapshot.conditionSummary)
	player:SetAttribute(attributes.BleedActive, snapshot.bleedActive)
	player:SetAttribute(attributes.BleedUntil, snapshot.bleedUntil)
	player:SetAttribute(attributes.StunActive, snapshot.stunActive)
	player:SetAttribute(attributes.StunUntil, snapshot.stunUntil)
	player:SetAttribute(attributes.FluxActive, snapshot.fluxActive)
	player:SetAttribute(attributes.FluxUntil, snapshot.fluxUntil)
end

local HUD_SOURCE_ATTRIBUTES = {
	"Role",
	"Escaped",
	"DownedIsDowned",
	"DownedExpiresAt",
	"DownedSelfRecoveryProgress",
	"CarriedState",
	"CarriedByUserId",
	"CaptureActive",
	"CaptureCustodianUserId",
	"CaptureExpiresAt",
	"RescueContractActive",
	"RescueContractTargetUserId",
	"RescueContractRescuerUserId",
	"RescueContractExpiresAt",
	"PostRescueProtected",
	"PostRescueProtectionExpiresAt",
	"RescueAccelerationActive",
	"RescueAccelerationExpiresAt",
	"ScoreLastFeedbackKey",
	"ScoreLastAwardedPoints",
	"ScoreLastBucket",
	"ScoreLastCategoryCapReached",
}

local HUD_STATUS_ATTRIBUTES = {
	TinyfolkStatusConfig.Attributes.FearExposureRatio,
	TinyfolkStatusConfig.Attributes.FearPanic,
	TinyfolkStatusConfig.Attributes.GiantProximityWarningLevel,
	TinyfolkStatusConfig.Attributes.BleedActive,
	TinyfolkStatusConfig.Attributes.BleedUntil,
	TinyfolkStatusConfig.Attributes.StunActive,
	TinyfolkStatusConfig.Attributes.StunUntil,
	TinyfolkStatusConfig.Attributes.FluxActive,
	TinyfolkStatusConfig.Attributes.FluxUntil,
}

local function readHudAttributes(player: Player): any
	local output: any = {}
	for _, attributeName in ipairs(HUD_SOURCE_ATTRIBUTES) do
		output[attributeName] = player:GetAttribute(attributeName)
	end

	for _, attributeName in ipairs(HUD_STATUS_ATTRIBUTES) do
		output[attributeName] = player:GetAttribute(attributeName)
	end

	return output
end

local function getHudTeammates(player: Player): { any }
	local teammates = {}
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player and otherPlayer:GetAttribute("Role") == RoleConfig.Roles.Tinyfolk then
			table.insert(teammates, {
				userId = otherPlayer.UserId,
				role = RoleConfig.Roles.Tinyfolk,
				attributes = readHudAttributes(otherPlayer),
			})
		end
	end
	return teammates
end

local function applyRaidHudProjection(player: Player, now: number)
	local projection = RaidStatusProjection.BuildPlayerProjection(TinyfolkStatusConfig, {
		now = now,
		attributes = readHudAttributes(player),
		teammates = getHudTeammates(player),
	})
	local attributes = TinyfolkStatusConfig.Attributes
	player:SetAttribute(attributes.RaidHudSummary, projection.summary)
	player:SetAttribute(attributes.RaidHudThreatLevel, projection.threatLevel)
	player:SetAttribute(attributes.RaidHudCustodyState, projection.custodyState)
	player:SetAttribute(attributes.RaidHudPersonalEffects, projection.personalEffects)
	player:SetAttribute(attributes.RaidHudTeammateActivity, projection.teammateActivity)
	player:SetAttribute(attributes.RaidHudScoreFeedback, projection.scoreFeedback)
	player:SetAttribute(attributes.RaidHudUpdatedAt, now)
end

local function resolveTick(player: Player, now: number): any
	local state = getOrCreateState(player.UserId)
	local humanoid = getHumanoid(player)
	local root = getHumanoidRootPart(player)
	local nextState, snapshot = TimedConditionStateLogic.ResolveTick(state, TinyfolkStatusConfig, {
		now = now,
		position = if root ~= nil then (root :: any).Position else nil,
		isTinyfolk = player:GetAttribute("Role") == RoleConfig.Roles.Tinyfolk,
		hasAliveHumanoid = isAlive(humanoid),
		hasRootPart = root ~= nil,
		nearbyFearSources = getFearSourcesForPlayer(player),
	})
	nextState.lastUpdatedAt = now
	stateByUserId[player.UserId] = nextState
	applyAttributes(player, snapshot)
	applyRaidHudProjection(player, now)
	return snapshot
end

function TinyfolkStatusService.SetCondition(
	player: Player,
	conditionName: string,
	durationSeconds: number,
	now: number?
)
	local currentNow = if type(now) == "number" then now else os.clock()
	local state = getOrCreateState(player.UserId)
	local nextState = TimedConditionStateLogic.ApplyCondition(
		state,
		conditionName,
		currentNow,
		durationSeconds,
		TinyfolkStatusConfig.MaxTimedConditionDurationSeconds
	)
	stateByUserId[player.UserId] = nextState
	return resolveTick(player, currentNow)
end

function TinyfolkStatusService.ClearCondition(player: Player, conditionName: string, now: number?)
	local currentNow = if type(now) == "number" then now else os.clock()
	local state = getOrCreateState(player.UserId)
	local nextState = TimedConditionStateLogic.ClearCondition(state, conditionName)
	stateByUserId[player.UserId] = nextState
	return resolveTick(player, currentNow)
end

function TinyfolkStatusService.GetSnapshot(player: Player): any
	local state = stateByUserId[player.UserId]
	return TimedConditionStateLogic.Snapshot(state, os.clock())
end

function TinyfolkStatusService.ResolveNow(player: Player, now: number)
	return resolveTick(player, now)
end

function TinyfolkStatusService.ResetForTests()
	stateByUserId = {}
end

Players.PlayerRemoving:Connect(function(player: Player)
	stateByUserId[player.UserId] = nil
end)

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("Role") == RoleConfig.Roles.Tinyfolk then
			resolveTick(player, now)
		end
	end
end)

debugLog("TinyfolkStatusService initialized")

return TinyfolkStatusService
