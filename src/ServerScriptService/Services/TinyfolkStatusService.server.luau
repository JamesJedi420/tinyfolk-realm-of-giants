--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local TinyfolkStatusFolder = Shared:WaitForChild("TinyfolkStatus")
local requireAny: any = require

local function requireFromNodeOrPath(parent: any, moduleName: string, fallbackPath: string): any
	local parentAny: any = parent
	local moduleNode = nil
	local findFirstChild = if type(parentAny) == "table" then parentAny.FindFirstChild else nil
	if type(findFirstChild) == "function" then
		moduleNode = findFirstChild(parentAny, moduleName)
	end

	local waitForChild = if type(parentAny) == "table" then parentAny.WaitForChild else nil
	if moduleNode == nil and type(waitForChild) == "function" then
		moduleNode = waitForChild(parentAny, moduleName)
	end

	if type(moduleNode) == "string" then
		return requireAny(moduleNode)
	end

	if moduleNode ~= nil then
		return requireAny(moduleNode)
	end

	return requireAny(fallbackPath)
end

local RoleConfig = requireFromNodeOrPath(Config, "RoleConfig", "../../ReplicatedStorage/Shared/Config/RoleConfig")
local TinyfolkStatusConfig =
	requireFromNodeOrPath(Config, "TinyfolkStatusConfig", "../../ReplicatedStorage/Shared/Config/TinyfolkStatusConfig")
local GiantThreatStageLogic = requireFromNodeOrPath(
	TinyfolkStatusFolder,
	"GiantThreatStageLogic",
	"../../ReplicatedStorage/Shared/TinyfolkStatus/GiantThreatStageLogic"
)
local TimedConditionStateLogic = requireFromNodeOrPath(
	TinyfolkStatusFolder,
	"TimedConditionStateLogic",
	"../../ReplicatedStorage/Shared/TinyfolkStatus/TimedConditionStateLogic"
)
local RaidStatusProjection = requireFromNodeOrPath(
	TinyfolkStatusFolder,
	"RaidStatusProjection",
	"../../ReplicatedStorage/Shared/TinyfolkStatus/RaidStatusProjection"
)
local TrailPressureLogic = requireFromNodeOrPath(
	TinyfolkStatusFolder,
	"TrailPressureLogic",
	"../../ReplicatedStorage/Shared/TinyfolkStatus/TrailPressureLogic"
)

local TinyfolkStatusService = {}
local globalEnv: any = getfenv()

type TimedConditionState = any
type TrailState = any
type ThreatStageState = any

local stateByUserId: { [number]: TimedConditionState? } = {}
local trailStateByUserId: { [number]: TrailState? } = {}
local raidThreatStageByUserId: { [number]: ThreatStageState? } = {}

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

local function getHidingQueryApi(): any?
	local api = rawget(globalEnv, "_TinyfolkHiding_QueryAPI")
	if type(api) ~= "table" then
		return nil
	end
	if type(api.IsPlayerHiding) ~= "function" then
		return nil
	end
	return api
end

local function getSnareTrapQueryApi(): any?
	local api = rawget(globalEnv, "_GiantBuildModeService_QueryAPI")
	if type(api) ~= "table" then
		return nil
	end
	if type(api.ResolveSnareTrapContact) ~= "function" then
		return nil
	end
	return api
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

local function resolveTrailSnapshot(userId: number, now: number): any
	local trailState = trailStateByUserId[userId]
	return TrailPressureLogic.BuildSnapshot(trailState, TinyfolkStatusConfig, now)
end

local function clearPlayerState(userId: number)
	stateByUserId[userId] = nil
	trailStateByUserId[userId] = nil
	raidThreatStageByUserId[userId] = nil
end

local function updateTrailState(
	player: Player,
	now: number,
	isTinyfolk: boolean,
	hasAliveHumanoid: boolean,
	root: BasePart?
)
	if not isTinyfolk then
		trailStateByUserId[player.UserId] = nil
		return
	end

	local hidingQueryApi = getHidingQueryApi()
	local isHiding = false
	if hidingQueryApi ~= nil then
		local ok, result = pcall(hidingQueryApi.IsPlayerHiding, player.UserId)
		if ok and result == true then
			isHiding = true
		end
	end
	trailStateByUserId[player.UserId] =
		TrailPressureLogic.ResolveSample(trailStateByUserId[player.UserId], TinyfolkStatusConfig, {
			now = now,
			position = if root ~= nil then (root :: any).Position else nil,
			shouldEmit = hasAliveHumanoid and root ~= nil and not isHiding,
		})
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
	player:SetAttribute(attributes.RaidHudThreatStage, snapshot.raidThreatStage)
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
	TinyfolkStatusConfig.Attributes.RaidHudThreatStage,
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
	local threatStageState = raidThreatStageByUserId[player.UserId]
	local humanoid = getHumanoid(player)
	local root = getHumanoidRootPart(player)
	local isTinyfolk = player:GetAttribute("Role") == RoleConfig.Roles.Tinyfolk
	local hasAliveHumanoid = isAlive(humanoid)
	updateTrailState(player, now, isTinyfolk, hasAliveHumanoid, root)

	if isTinyfolk and hasAliveHumanoid and root ~= nil then
		local snareTrapQueryApi = getSnareTrapQueryApi()
		if snareTrapQueryApi ~= nil then
			local ok, trapResult =
				pcall(snareTrapQueryApi.ResolveSnareTrapContact, player.UserId, (root :: any).Position, now)
			if ok and type(trapResult) == "table" and trapResult.accepted == true then
				state = TimedConditionStateLogic.ApplyCondition(
					state,
					"stun",
					now,
					TinyfolkStatusConfig.StunDurationSeconds,
					TinyfolkStatusConfig.MaxTimedConditionDurationSeconds
				)
			end
		end
	end

	local nextState, snapshot = TimedConditionStateLogic.ResolveTick(state, TinyfolkStatusConfig, {
		now = now,
		position = if root ~= nil then (root :: any).Position else nil,
		isTinyfolk = isTinyfolk,
		hasAliveHumanoid = hasAliveHumanoid,
		hasRootPart = root ~= nil,
		nearbyFearSources = getFearSourcesForPlayer(player),
	})
	local nextThreatStageState, threatStageSnapshot =
		GiantThreatStageLogic.ResolveTick(threatStageState, TinyfolkStatusConfig, {
			now = now,
			warningLevel = snapshot.giantProximityWarningLevel,
		})
	nextState.lastUpdatedAt = now
	stateByUserId[player.UserId] = nextState
	raidThreatStageByUserId[player.UserId] = nextThreatStageState
	local nextSnapshot: any = table.clone(snapshot)
	nextSnapshot.raidThreatStage = threatStageSnapshot.stage
	applyAttributes(player, nextSnapshot)
	applyRaidHudProjection(player, now)
	return nextSnapshot
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

function TinyfolkStatusService.GetTrailSnapshot(player: Player, now: number?): any
	local currentNow = if type(now) == "number" then now else os.clock()
	return resolveTrailSnapshot(player.UserId, currentNow)
end

function TinyfolkStatusService.ResolveNow(player: Player, now: number)
	return resolveTick(player, now)
end

function TinyfolkStatusService.ResetForTests()
	stateByUserId = {}
	trailStateByUserId = {}
	raidThreatStageByUserId = {}
end

globalEnv._TinyfolkStatusService_QueryAPI = {
	ClearConditionForUserId = function(userId: number, conditionName: string, now: number?)
		local currentNow = if type(now) == "number" then now else os.clock()
		for _, player in ipairs(Players:GetPlayers()) do
			if player.UserId == userId then
				return TinyfolkStatusService.ClearCondition(player, conditionName, currentNow)
			end
		end
		return nil
	end,
	GetTrailSnapshot = function(userId: number, now: number?)
		local currentNow = if type(now) == "number" then now else os.clock()
		return resolveTrailSnapshot(userId, currentNow)
	end,
	GetAllTrailSnapshots = function(now: number?)
		local currentNow = if type(now) == "number" then now else os.clock()
		local output = {}
		for userId in pairs(trailStateByUserId) do
			output[userId] = resolveTrailSnapshot(userId, currentNow)
		end
		return output
	end,
	GetRaidThreatStageSnapshot = function(userId: number): any
		local state = raidThreatStageByUserId[userId]
		if state == nil then
			return nil
		end
		return {
			stage = state.stage,
			stageEnteredAt = state.stageEnteredAt,
			lastUpdatedAt = state.lastUpdatedAt,
		}
	end,
}

Players.PlayerRemoving:Connect(function(player: Player)
	clearPlayerState(player.UserId)
end)

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	local connectedTinyfolkUserIds: { [number]: boolean } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("Role") == RoleConfig.Roles.Tinyfolk then
			connectedTinyfolkUserIds[player.UserId] = true
			resolveTick(player, now)
		else
			clearPlayerState(player.UserId)
		end
	end

	for userId in pairs(stateByUserId) do
		if connectedTinyfolkUserIds[userId] ~= true then
			clearPlayerState(userId)
		end
	end
	for userId in pairs(trailStateByUserId) do
		if connectedTinyfolkUserIds[userId] ~= true then
			clearPlayerState(userId)
		end
	end
end)

return TinyfolkStatusService
