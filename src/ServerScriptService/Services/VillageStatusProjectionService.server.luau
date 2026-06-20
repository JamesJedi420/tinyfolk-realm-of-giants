--!nocheck
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local PenRationingConfig = require(Config:WaitForChild("PenRationingConfig"))
local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local VillageStatusHudConfig = require(Config:WaitForChild("VillageStatusHudConfig"))
local VillageStatusHudPresentation = require(GiantRealm:WaitForChild("VillageStatusHudPresentation"))
local VillageStatusState = require(GiantRealm:WaitForChild("VillageStatusState"))

local ResourceFlowState = require(script.Parent:WaitForChild("ResourceFlowState"))

local globalEnv: any = getfenv()

local refreshAccumulatorSeconds = 0

local function debugLog(message: string)
	print(string.format("[VillageStatusProjectionService] %s", message))
end

local function getGlobalTable(key: string): any?
	local value = globalEnv[key]
	if type(value) == "table" then
		return value
	end
	if type(_G) == "table" and type((_G :: any)[key]) == "table" then
		return (_G :: any)[key]
	end
	return nil
end

local function getRealmOwnerUserId(): number?
	local roleApi = getGlobalTable("_RoleService_QueryAPI")
	if type(roleApi) == "table" and type(roleApi.GetActiveGiantRealmOwnerUserId) == "function" then
		local ownerUserId = roleApi.GetActiveGiantRealmOwnerUserId()
		if type(ownerUserId) == "number" and ownerUserId > 0 then
			return math.floor(ownerUserId)
		end
	end
	return nil
end

local function getPlayerByUserId(userId: number): Player?
	for _, player in Players:GetPlayers() do
		if player.UserId == userId then
			return player :: any
		end
	end
	return nil
end

local function getActiveTinyfolkCount(): number
	local reinforcementApi = getGlobalTable("_EmergencyReinforcementService_QueryAPI")
	if type(reinforcementApi) == "table" and type(reinforcementApi.GetActiveTinyfolkCount) == "function" then
		local count = reinforcementApi.GetActiveTinyfolkCount()
		if type(count) == "number" and count >= 0 then
			return math.floor(count)
		end
	end
	return 0
end

local function getPenRationingInput(ownerUserId: number): (number, boolean, number, number)
	local penApi = getGlobalTable("_PenRationingService_QueryAPI")
	local defaultPenId = PenRationingConfig.DefaultPenId
	local activeCaptiveCount = 0
	local lastFoodShortfall = false
	local consecutiveShortfallTicks = 0
	local morale = PenRationingConfig.MoraleDefault

	if type(penApi) == "table" then
		if type(penApi.GetCustodianMorale) == "function" then
			morale = penApi.GetCustodianMorale(ownerUserId)
		end
		if type(penApi.GetPenState) == "function" then
			local penState = penApi.GetPenState(defaultPenId)
			if type(penState) == "table" then
				lastFoodShortfall = penState.lastFoodShortfall == true
				if type(penState.consecutiveShortfallTicks) == "number" then
					consecutiveShortfallTicks = math.max(0, math.floor(penState.consecutiveShortfallTicks))
				end
			end
		end
	end

	local captureApi = getGlobalTable("_CaptureService_QueryAPI")
	if type(captureApi) == "table" and type(captureApi.GetAllCaptures) == "function" then
		local captures = captureApi.GetAllCaptures(os.clock())
		if type(captures) == "table" then
			activeCaptiveCount = #captures
		end
	end

	return morale, lastFoodShortfall, consecutiveShortfallTicks, activeCaptiveCount
end

local function getJobSchedulingInput(): (number, number)
	local schedulingApi = getGlobalTable("_TinyfolkJobSchedulingService_QueryAPI")
	if type(schedulingApi) ~= "table" or type(schedulingApi.GetDebugSnapshot) ~= "function" then
		return 0, 0
	end

	local debugSnapshot = schedulingApi.GetDebugSnapshot()
	if type(debugSnapshot) ~= "table" then
		return 0, 0
	end

	local workerCount = if type(debugSnapshot.workerCount) == "number"
		then math.max(0, math.floor(debugSnapshot.workerCount))
		else 0
	local activeJobCount = if type(debugSnapshot.assignmentCount) == "number"
		then math.max(0, math.floor(debugSnapshot.assignmentCount))
		else 0
	return workerCount, activeJobCount
end

local function readMaterialField(materialSnapshot: any, fieldName: string): number
	if type(materialSnapshot) ~= "table" then
		return 0
	end
	local value = materialSnapshot[fieldName]
	if type(value) ~= "number" or value < 0 then
		return 0
	end
	return math.floor(value + 0.5)
end

local function buildAggregateInput(ownerUserId: number): any
	local flowSnapshot = ResourceFlowState.GetSnapshot()
	local foodSnapshot = if type(flowSnapshot) == "table" then flowSnapshot.Food else nil
	local woodSnapshot = if type(flowSnapshot) == "table" then flowSnapshot.Wood else nil
	local stoneSnapshot = if type(flowSnapshot) == "table" then flowSnapshot.Stone else nil

	local morale, lastFoodShortfall, consecutiveShortfallTicks, activeCaptiveCount = getPenRationingInput(ownerUserId)
	local workerCount, activeJobCount = getJobSchedulingInput()

	return {
		activeRaiderCount = getActiveTinyfolkCount(),
		workerCount = workerCount,
		activeCaptiveCount = activeCaptiveCount,
		foodStored = readMaterialField(foodSnapshot, "stored"),
		foodInTransit = readMaterialField(foodSnapshot, "inTransit"),
		woodProduced = readMaterialField(woodSnapshot, "produced"),
		stoneProduced = readMaterialField(stoneSnapshot, "produced"),
		morale = morale,
		lastFoodShortfall = lastFoodShortfall,
		consecutiveShortfallTicks = consecutiveShortfallTicks,
		activeJobCount = activeJobCount,
	}
end

local function applyProjectionToPlayer(player: any, ownerUserId: number)
	if type(player) ~= "table" or player.UserId ~= ownerUserId then
		return
	end
	if type(player.GetAttribute) ~= "function" or type(player.SetAttribute) ~= "function" then
		return
	end
	if player:GetAttribute("Role") ~= RoleConfig.Roles.Giant then
		return
	end

	local aggregateInput = buildAggregateInput(ownerUserId)
	local model = VillageStatusHudPresentation.BuildHudModel(aggregateInput)
	local snapshot = VillageStatusState.BuildSnapshot(aggregateInput)
	local attrs = VillageStatusHudConfig.Attributes

	player:SetAttribute(attrs.ActiveRaiderCount, snapshot.activeRaiderCount)
	player:SetAttribute(attrs.WorkerCount, snapshot.workerCount)
	player:SetAttribute(attrs.ActiveCaptiveCount, snapshot.activeCaptiveCount)
	player:SetAttribute(attrs.FoodStored, snapshot.foodStored)
	player:SetAttribute(attrs.FoodInTransit, snapshot.foodInTransit)
	player:SetAttribute(attrs.Morale, snapshot.morale)
	player:SetAttribute(attrs.LastFoodShortfall, snapshot.lastFoodShortfall)
	player:SetAttribute(attrs.ConsecutiveShortfallTicks, snapshot.consecutiveShortfallTicks)
	player:SetAttribute(attrs.WoodProduced, snapshot.woodProduced)
	player:SetAttribute(attrs.StoneProduced, snapshot.stoneProduced)
	player:SetAttribute(attrs.ActiveJobCount, snapshot.activeJobCount)
	player:SetAttribute(attrs.EscapePressure, snapshot.escapePressure)
	player:SetAttribute(attrs.Tone, snapshot.tone)
	player:SetAttribute(attrs.Summary, model.summary)
	player:SetAttribute(attrs.UpdatedAt, os.clock())
end

local function refreshProjection()
	local ownerUserId = getRealmOwnerUserId()
	if ownerUserId == nil then
		return
	end

	local owner = getPlayerByUserId(ownerUserId)
	if owner ~= nil then
		applyProjectionToPlayer(owner, ownerUserId)
	end
end

RunService.Heartbeat:Connect(function(deltaTime: number)
	refreshAccumulatorSeconds += deltaTime
	if refreshAccumulatorSeconds < VillageStatusHudConfig.RefreshIntervalSeconds then
		return
	end
	refreshAccumulatorSeconds = 0
	refreshProjection()
end)

Players.PlayerAdded:Connect(function(player: Player)
	task.defer(function()
		local ownerUserId = getRealmOwnerUserId()
		if type(ownerUserId) == "number" then
			applyProjectionToPlayer(player, ownerUserId)
		end
	end)
end)

-- selene: allow(global_usage)
_G._VillageStatusProjectionService_QueryAPI = {
	RefreshProjection = refreshProjection,
	BuildAggregateInput = buildAggregateInput,
	ApplyProjectionToPlayer = applyProjectionToPlayer,
}

debugLog("VillageStatusProjectionService initialized")
