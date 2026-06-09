--!nocheck
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local PenRationingConfig = require(Config:WaitForChild("PenRationingConfig"))
local PenRationingState = require(GiantRealm:WaitForChild("PenRationingState"))
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
}

local penStateById: { [string]: PenState } = {}
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

local function countActiveCaptives(at: number): number
	local captureApi = getCaptureServiceQueryApi()
	if type(captureApi) ~= "table" or type(captureApi.GetAllCaptures) ~= "function" then
		return 0
	end

	local captures = captureApi.GetAllCaptures(at)
	if type(captures) ~= "table" then
		return 0
	end

	return #captures
end

local function refreshPenAttributes(penState: PenState, activeCaptiveCount: number)
	local attrs = PenRationingConfig.StateAttributes
	penState.part:SetAttribute(attrs.ActiveCaptiveCount, activeCaptiveCount)
	penState.part:SetAttribute(attrs.FoodConsumedTotal, penState.foodConsumedTotal)
	penState.part:SetAttribute(attrs.LastFoodShortfall, penState.lastFoodShortfall)
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

local function processRationingTick(penState: PenState, activeCaptiveCount: number, at: number)
	local foodCost =
		PenRationingState.ComputeFoodCostForInterval(activeCaptiveCount, PenRationingConfig.FoodPerCaptivePerInterval)
	if foodCost <= 0 then
		penState.lastFoodShortfall = false
		refreshPenAttributes(penState, activeCaptiveCount)
		return
	end

	local spent, _, spendError =
		ResourceFlowState.SpendStoredAtomic(0, 0, string.format("PenRationing:%s", penState.penId), foodCost)
	if not spent then
		penState.lastFoodShortfall = true
		debugWarn(
			string.format(
				"Food shortfall penId=%s captives=%d requiredFood=%d reason=%s",
				penState.penId,
				activeCaptiveCount,
				foodCost,
				tostring(spendError)
			)
		)
		refreshPenAttributes(penState, activeCaptiveCount)
		return
	end

	penState.lastFoodShortfall = false
	penState.foodConsumedTotal += foodCost
	penState.lastTickAt = at
	debugLog(
		string.format(
			"Ration tick penId=%s captives=%d foodCost=%d foodConsumedTotal=%d",
			penState.penId,
			activeCaptiveCount,
			foodCost,
			penState.foodConsumedTotal
		)
	)
	refreshPenAttributes(penState, activeCaptiveCount)
end

local function advanceRationing(deltaSeconds: number, at: number)
	local activeCaptiveCount = countActiveCaptives(at)
	for _, penState in pairs(penStateById) do
		local dueTicks, nextAccumulator = PenRationingState.CountDueTicks(
			penState.accumulatorSeconds,
			deltaSeconds,
			PenRationingConfig.IntervalSeconds
		)
		penState.accumulatorSeconds = nextAccumulator
		for _ = 1, dueTicks do
			processRationingTick(penState, activeCaptiveCount, at)
		end
		if dueTicks == 0 then
			refreshPenAttributes(penState, activeCaptiveCount)
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
	AdvanceRationingForTests = function(deltaSeconds: number, at: number?)
		advanceRationing(deltaSeconds, if type(at) == "number" then at else os.clock())
	end,
	ResetForTests = function()
		for _, penState in pairs(penStateById) do
			penState.accumulatorSeconds = 0
			penState.foodConsumedTotal = 0
			penState.lastTickAt = nil
			penState.lastFoodShortfall = false
			refreshPenAttributes(penState, 0)
		end
	end,
}

debugLog("PenRationingService initialized")
