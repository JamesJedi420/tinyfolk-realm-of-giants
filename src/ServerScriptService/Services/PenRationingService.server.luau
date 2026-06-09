--!nocheck
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local PenRationingConfig = require(Config:WaitForChild("PenRationingConfig"))
local PenRationingState = require(GiantRealm:WaitForChild("PenRationingState"))
local VillageWorksiteUpgradeState = require(GiantRealm:WaitForChild("VillageWorksiteUpgradeState"))
local ResourceFlowState = require(script.Parent:WaitForChild("ResourceFlowState"))

local PEN_FOLDER_PATH = { "Map", "Stations" }
local PEN_NAME_PREFIX = "Pen_"

type PenState = {
	penId: string,
	part: BasePart,
	accumulatorSeconds: number,
	foodConsumedTotal: number,
	lastTickAt: number?,
	lastFoodShortfall: boolean,
	consecutiveShortfallTicks: number,
	starvationReleasesTotal: number,
}

local penStateById: { [string]: PenState } = {}
local moraleByCustodianUserId: { [number]: number } = {}
local globalEnv: any = getfenv()

local function debugLog(message: string)
	print(string.format("[PenRationingService] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[PenRationingService] %s", message))
end

local function getCaptureServiceQueryApi(): any?
	local queryApi = globalEnv._CaptureService_QueryAPI
	if type(queryApi) == "table" then
		return queryApi
	end
	if type(_G) == "table" and type((_G :: any)._CaptureService_QueryAPI) == "table" then
		return (_G :: any)._CaptureService_QueryAPI
	end
	return nil
end

local function getVillageWorksiteUpgradeQueryApi(): any?
	local queryApi = globalEnv._VillageWorksiteUpgradeService_QueryAPI
	if type(queryApi) == "table" then
		return queryApi
	end
	if type(_G) == "table" and type((_G :: any)._VillageWorksiteUpgradeService_QueryAPI) == "table" then
		return (_G :: any)._VillageWorksiteUpgradeService_QueryAPI
	end
	return nil
end

local function getPenUpgradeLevel(penId: string): number
	local upgradeApi = getVillageWorksiteUpgradeQueryApi()
	if type(upgradeApi) == "table" and type(upgradeApi.GetUpgradeLevel) == "function" then
		local level = upgradeApi.GetUpgradeLevel(penId)
		if type(level) == "number" and level >= 0 then
			return math.floor(level)
		end
	end
	return 0
end

local function getPenRationingModifiers(penId: string): any
	return VillageWorksiteUpgradeState.ResolvePenRationingModifiers(getPenUpgradeLevel(penId))
end

local function getActiveCaptures(at: number): { any }
	local captureApi = getCaptureServiceQueryApi()
	if type(captureApi) ~= "table" or type(captureApi.GetAllCaptures) ~= "function" then
		return {}
	end

	local captures = captureApi.GetAllCaptures(at)
	if type(captures) ~= "table" then
		return {}
	end
	return captures
end

local function getPlayerByUserId(userId: number): Player?
	for _, player in Players:GetPlayers() do
		if player.UserId == userId then
			return player :: any
		end
	end
	return nil
end

local function getCustodianMorale(custodianUserId: number): number
	local stored = moraleByCustodianUserId[custodianUserId]
	if type(stored) == "number" then
		return stored
	end
	return PenRationingConfig.MoraleDefault
end

local function setCustodianMorale(custodianUserId: number, morale: number)
	moraleByCustodianUserId[custodianUserId] = morale
	local player = getPlayerByUserId(custodianUserId)
	if player ~= nil then
		player:SetAttribute(PenRationingConfig.StateAttributes.CustodianMorale, morale)
	end
end

local function applyMoraleDeltaToCustodians(captures: { any }, delta: number)
	local seenCustodians: { [number]: boolean } = {}
	for _, record in ipairs(captures) do
		if type(record) == "table" and type(record.custodianUserId) == "number" then
			local custodianUserId = record.custodianUserId
			if not seenCustodians[custodianUserId] then
				seenCustodians[custodianUserId] = true
				local nextMorale = PenRationingState.ApplyMoraleDelta(
					getCustodianMorale(custodianUserId),
					delta,
					PenRationingConfig.MoraleMin,
					PenRationingConfig.MoraleMax
				)
				setCustodianMorale(custodianUserId, nextMorale)
			end
		end
	end
end

local function refreshPenAttributes(penState: PenState, activeCaptiveCount: number, penModifiers: any)
	local attrs = PenRationingConfig.StateAttributes
	penState.part:SetAttribute(attrs.ActiveCaptiveCount, activeCaptiveCount)
	penState.part:SetAttribute(attrs.FoodConsumedTotal, penState.foodConsumedTotal)
	penState.part:SetAttribute(attrs.LastFoodShortfall, penState.lastFoodShortfall)
	penState.part:SetAttribute(attrs.ConsecutiveShortfallTicks, penState.consecutiveShortfallTicks)
	penState.part:SetAttribute(attrs.StarvationReleasesTotal, penState.starvationReleasesTotal)
	penState.part:SetAttribute(attrs.PenUpgradeLevel, penModifiers.level)
	penState.part:SetAttribute(attrs.FoodCostMultiplier, penModifiers.foodMultiplier)
	if penState.lastTickAt ~= nil then
		penState.part:SetAttribute(attrs.LastTickAt, penState.lastTickAt)
	end
end

local function registerPenPart(part: BasePart)
	if not string.find(part.Name, "^" .. PEN_NAME_PREFIX) then
		return
	end

	if penStateById[part.Name] ~= nil then
		return
	end

	penStateById[part.Name] = {
		penId = part.Name,
		part = part,
		accumulatorSeconds = 0,
		foodConsumedTotal = 0,
		lastTickAt = nil,
		lastFoodShortfall = false,
		consecutiveShortfallTicks = 0,
		starvationReleasesTotal = 0,
	}
	debugLog(string.format("Registered pen id=%s", part.Name))
end

local function discoverPenParts()
	local current: Instance = Workspace
	for _, childName in ipairs(PEN_FOLDER_PATH) do
		local child = current:FindFirstChild(childName)
		if child == nil then
			debugWarn(string.format("Missing workspace path segment: %s", childName))
			return
		end
		current = child
	end

	for _, descendant in ipairs(current:GetDescendants()) do
		if descendant:IsA("BasePart") and string.find(descendant.Name, "^" .. PEN_NAME_PREFIX) then
			registerPenPart(descendant)
		end
	end

	if next(penStateById) == nil then
		debugWarn("No pen parts registered under Workspace.Map.Stations")
	end
end

local function forceStarvationRelease(penState: PenState, captures: { any }, at: number): boolean
	local releaseTargetUserId = PenRationingState.SelectStarvationReleaseTarget(captures)
	if releaseTargetUserId == nil then
		return false
	end

	local captureApi = getCaptureServiceQueryApi()
	if type(captureApi) ~= "table" or type(captureApi.ResolveCustodyEnd) ~= "function" then
		return false
	end

	local operationId = string.format("pen-starvation:%s:%d:%.6f", penState.penId, releaseTargetUserId, at)
	local releaseResult = captureApi.ResolveCustodyEnd(releaseTargetUserId, "starvation", at, operationId)
	if type(releaseResult) ~= "table" or releaseResult.accepted ~= true then
		return false
	end

	penState.starvationReleasesTotal += 1
	penState.consecutiveShortfallTicks = 0
	penState.lastFoodShortfall = false
	debugWarn(
		string.format(
			"Starvation release penId=%s targetUserId=%d releasesTotal=%d",
			penState.penId,
			releaseTargetUserId,
			penState.starvationReleasesTotal
		)
	)
	return true
end

local function processRationingTick(penState: PenState, captures: { any }, at: number)
	local activeCaptiveCount = #captures
	local penModifiers = getPenRationingModifiers(penState.penId)
	local foodCost = PenRationingState.ComputeFoodCostForInterval(
		activeCaptiveCount,
		PenRationingConfig.FoodPerCaptivePerInterval,
		penModifiers.foodMultiplier
	)
	if foodCost <= 0 then
		penState.lastFoodShortfall = false
		penState.consecutiveShortfallTicks = 0
		refreshPenAttributes(penState, activeCaptiveCount, penModifiers)
		return
	end

	local spent, _, spendError =
		ResourceFlowState.SpendStoredAtomic(0, 0, string.format("PenRationing:%s", penState.penId), foodCost)
	if not spent then
		penState.lastFoodShortfall = true
		penState.consecutiveShortfallTicks += 1
		applyMoraleDeltaToCustodians(captures, -PenRationingConfig.MoraleLossPerShortfallTick)
		debugWarn(
			string.format(
				"Food shortfall penId=%s captives=%d requiredFood=%d shortfallTicks=%d reason=%s",
				penState.penId,
				activeCaptiveCount,
				foodCost,
				penState.consecutiveShortfallTicks,
				tostring(spendError)
			)
		)
		if
			PenRationingState.ShouldForceStarvationRelease(
				penState.consecutiveShortfallTicks,
				penModifiers.starvationReleaseThreshold
			)
		then
			forceStarvationRelease(penState, getActiveCaptures(at), at)
		end
		refreshPenAttributes(penState, #getActiveCaptures(at), penModifiers)
		return
	end

	penState.lastFoodShortfall = false
	penState.consecutiveShortfallTicks = 0
	penState.foodConsumedTotal += foodCost
	penState.lastTickAt = at
	applyMoraleDeltaToCustodians(captures, PenRationingConfig.MoraleRecoveryPerSuccessfulTick)
	debugLog(
		string.format(
			"Ration tick penId=%s captives=%d foodCost=%d foodConsumedTotal=%d penLevel=%d",
			penState.penId,
			activeCaptiveCount,
			foodCost,
			penState.foodConsumedTotal,
			penModifiers.level
		)
	)
	refreshPenAttributes(penState, activeCaptiveCount, penModifiers)
end

local function advanceRationing(deltaSeconds: number, at: number)
	for _, penState in pairs(penStateById) do
		local dueTicks, nextAccumulator = PenRationingState.CountDueTicks(
			penState.accumulatorSeconds,
			deltaSeconds,
			PenRationingConfig.IntervalSeconds
		)
		penState.accumulatorSeconds = nextAccumulator
		for _ = 1, dueTicks do
			processRationingTick(penState, getActiveCaptures(at), at)
		end
		if dueTicks == 0 then
			local penModifiers = getPenRationingModifiers(penState.penId)
			refreshPenAttributes(penState, #getActiveCaptures(at), penModifiers)
		end
	end
end

discoverPenParts()
ResourceFlowState.RefreshDeliveryPoints()

RunService.Heartbeat:Connect(function(deltaTime: number)
	advanceRationing(deltaTime, os.clock())
end)

_G._PenRationingService_QueryAPI = {
	GetPenState = function(penId: string): any?
		return penStateById[penId]
	end,
	GetCustodianMorale = function(custodianUserId: number): number
		return getCustodianMorale(custodianUserId)
	end,
	AdvanceRationingForTests = function(deltaSeconds: number, at: number?)
		advanceRationing(deltaSeconds, if type(at) == "number" then at else os.clock())
	end,
	ResetForTests = function()
		moraleByCustodianUserId = {}
		for _, penState in pairs(penStateById) do
			penState.accumulatorSeconds = 0
			penState.foodConsumedTotal = 0
			penState.lastTickAt = nil
			penState.lastFoodShortfall = false
			penState.consecutiveShortfallTicks = 0
			penState.starvationReleasesTotal = 0
			local penModifiers = getPenRationingModifiers(penState.penId)
			refreshPenAttributes(penState, 0, penModifiers)
		end
	end,
}

debugLog("PenRationingService initialized")
