--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")
local VillageWorksiteUpgradeState = require(GiantRealm:WaitForChild("VillageWorksiteUpgradeState"))
local LaborActionState = require(GiantRealm:WaitForChild("LaborActionState"))
local StationConfig = require(Config:WaitForChild("StationConfig"))
local LaborActionConfig = require(Config:WaitForChild("LaborActionConfig"))
local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local SpecialistConfig = require(Config:WaitForChild("SpecialistConfig"))
local ConstructionFolder = Shared:WaitForChild("Construction")
local ContextualTaskProgressLogic = require(ConstructionFolder:WaitForChild("ContextualTaskProgressLogic"))
local TaskQteTimingLogic = require(ConstructionFolder:WaitForChild("TaskQteTimingLogic"))
local ResourceFlowState = require(script.Parent:WaitForChild("ResourceFlowState"))
local ObjectiveSkillXpProducer = require(script.Parent:WaitForChild("ObjectiveSkillXpProducer"))
local RealmObjectiveCompletionCaller = require(script.Parent:WaitForChild("RealmObjectiveCompletionCaller"))
local PostRescueProtectionCancellationCaller =
	require(script.Parent:WaitForChild("PostRescueProtectionCancellationCaller"))

local REMOTES_FOLDER_NAME = "Remotes"
local ACTIVATE_REMOTE_NAME = "StationActivateRequest"
local DEBUG_REQUEST_REMOTE_NAME = "StationDebugStateRequest"
local DEBUG_RESPONSE_REMOTE_NAME = "StationDebugStateResponse"

local ATTRIBUTE_IS_ACTIVE = "IsActive"
local ATTRIBUTE_ESSENCE_TOTAL = "EssenceTotal"
local ATTRIBUTE_WOOD_TOTAL = "WoodTotal"
local ATTRIBUTE_STONE_TOTAL = "StoneTotal"
local ATTRIBUTE_WOOD_PRODUCED_TOTAL = "WoodProducedTotal"
local ATTRIBUTE_WOOD_IN_TRANSIT_TOTAL = "WoodInTransitTotal"
local ATTRIBUTE_WOOD_STORED_TOTAL = "WoodStoredTotal"
local ATTRIBUTE_WOOD_USABLE_TOTAL = "WoodUsableTotal"
local ATTRIBUTE_STONE_PRODUCED_TOTAL = "StoneProducedTotal"
local ATTRIBUTE_STONE_IN_TRANSIT_TOTAL = "StoneInTransitTotal"
local ATTRIBUTE_STONE_STORED_TOTAL = "StoneStoredTotal"
local ATTRIBUTE_STONE_USABLE_TOTAL = "StoneUsableTotal"
local ATTRIBUTE_TICK_COUNT = "EssenceTickCount"
local ATTRIBUTE_LAST_TICK_AT = "LastTickAt"
local ATTRIBUTE_ACTIVATED_BY = "ActivatedByUserId"

local STATION_FOLDER_PATH = { "Map", "Stations" }
local globalEnv: any = getfenv()

type StationState = {
	stationId: string,
	part: BasePart,
	isActive: boolean,
	resourceTotal: number,
	materialType: "Wood" | "Stone" | "Food" | "Metal",
	tickCount: number,
	lastTickAt: number,
	activatedByUserId: number?,
	accumulatorSeconds: number,
}

local stationStateById: { [string]: StationState } = {}
local lastRequestAtByUserId: { [number]: number? } = {}
local lastHaulRequestAtByUserId: { [number]: number? } = {}
local taskStateByStationId: { [string]: any } = {}

local function debugLog(message: string)
	print(string.format("[StationService] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[StationService] %s", message))
end

local function getTinyfolkLaborUpgradeQueryApi(): any?
	local upgradeApi = globalEnv._TinyfolkLaborUpgradeService_QueryAPI
	if type(upgradeApi) == "table" then
		return upgradeApi
	end
	if type(_G) == "table" and type((_G :: any)._TinyfolkLaborUpgradeService_QueryAPI) == "table" then
		return (_G :: any)._TinyfolkLaborUpgradeService_QueryAPI
	end
	return nil
end

local function resolveTaskDurationSeconds(player: Player): number
	local baseDuration = StationConfig.TaskDurationSeconds
	local upgradeApi = getTinyfolkLaborUpgradeQueryApi()
	if type(upgradeApi) == "table" and type(upgradeApi.GetTaskPaceMultiplier) == "function" then
		local multiplier = upgradeApi.GetTaskPaceMultiplier(player.UserId)
		if type(multiplier) == "number" and multiplier > 0 then
			return math.max(0.2, baseDuration * multiplier)
		end
	end
	return baseDuration
end

local function resolveHaulTransferAmount(player: Player, baseAmount: number): number
	local upgradeApi = getTinyfolkLaborUpgradeQueryApi()
	if type(upgradeApi) == "table" and type(upgradeApi.GetHaulYieldMultiplier) == "function" then
		local multiplier = upgradeApi.GetHaulYieldMultiplier(player.UserId)
		if type(multiplier) == "number" and multiplier > 0 then
			return math.max(1, math.floor(baseAmount * multiplier + 0.5))
		end
	end
	return baseAmount
end

local function notifyLaborWorkActionCompleted(player: Player)
	local upgradeApi = getTinyfolkLaborUpgradeQueryApi()
	if type(upgradeApi) == "table" and type(upgradeApi.RecordWorkActionCompleted) == "function" then
		upgradeApi.RecordWorkActionCompleted(player)
	end
end

local function getProductionModifiersForStation(stationId: string): any
	local upgradeApi = globalEnv._VillageWorksiteUpgradeService_QueryAPI
	if type(upgradeApi) ~= "table" and type(_G) == "table" then
		upgradeApi = (_G :: any)._VillageWorksiteUpgradeService_QueryAPI
	end
	if type(upgradeApi) ~= "table" or type(upgradeApi.GetProductionModifiers) ~= "function" then
		return VillageWorksiteUpgradeState.ResolveProductionModifiers(0)
	end

	local modifiers = upgradeApi.GetProductionModifiers(stationId)
	if type(modifiers) ~= "table" then
		return VillageWorksiteUpgradeState.ResolveProductionModifiers(0)
	end
	return modifiers
end

local function resolveStationGenerationLimits(
	stationId: string,
	materialType: "Wood" | "Stone" | "Food" | "Metal"
): (number, number, any)
	local modifiers = getProductionModifiersForStation(stationId)
	local perTickMultiplier = if type(modifiers.perTickMultiplier) == "number" then modifiers.perTickMultiplier else 1
	local maxTotalMultiplier = if type(modifiers.maxTotalMultiplier) == "number"
		then modifiers.maxTotalMultiplier
		else 1

	local maxTotal = StationConfig.MaxWoodTotal
	local perTick = StationConfig.WoodPerTick
	if materialType == "Stone" then
		maxTotal = StationConfig.MaxStoneTotal
		perTick = StationConfig.StonePerTick
	elseif materialType == "Food" then
		maxTotal = StationConfig.MaxFoodTotal
		perTick = StationConfig.FoodPerTick
	elseif materialType == "Metal" then
		maxTotal = StationConfig.MaxMetalTotal
		perTick = StationConfig.MetalPerTick
	end
	maxTotal = math.max(1, math.floor(maxTotal * maxTotalMultiplier + 0.5))
	perTick = math.max(1, math.floor(perTick * perTickMultiplier + 0.5))
	return perTick, maxTotal, modifiers
end

local function ensureRemotesFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = REMOTES_FOLDER_NAME
	folder.Parent = ReplicatedStorage
	debugLog("Created ReplicatedStorage.Remotes folder")
	return folder
end

local function ensureRemoteEvent(parentFolder: Folder, remoteName: string): RemoteEvent
	local existing = parentFolder:FindFirstChild(remoteName)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = remoteName
	remote.Parent = parentFolder
	debugLog(string.format("Created ReplicatedStorage.Remotes.%s", remoteName))
	return remote
end

local function isCoolingDown(userId: number, at: number?): boolean
	local last = lastRequestAtByUserId[userId]
	if not last then
		return false
	end
	local lastAt = last :: number

	if type(at) == "number" then
		return (at - lastAt) < StationConfig.RequestCooldownSeconds
	end

	return (os.clock() - lastAt) < StationConfig.RequestCooldownSeconds
end

local function markRequest(userId: number, at: number?)
	lastRequestAtByUserId[userId] = if type(at) == "number" then at else os.clock()
end

local function isHaulCoolingDown(userId: number, at: number?): boolean
	local last = lastHaulRequestAtByUserId[userId]
	if not last then
		return false
	end
	local lastAt = last :: number

	if type(at) == "number" then
		return (at - lastAt) < StationConfig.HaulIntervalSeconds
	end

	return (os.clock() - lastAt) < StationConfig.HaulIntervalSeconds
end

local function markHaulRequest(userId: number, at: number?)
	lastHaulRequestAtByUserId[userId] = if type(at) == "number" then at else os.clock()
end

local function willAttemptHaulOnly(stationState: StationState, requestMode: string): boolean
	if requestMode ~= "legacy" then
		return false
	end

	local materialSnapshot = ResourceFlowState.GetMaterialSnapshot(stationState.materialType)
	return materialSnapshot.produced > 0
end

local function applyHaulDebugAttributes(player: Player, stationState: StationState, movedAmount: number)
	player:SetAttribute(StationConfig.HaulInteractionActiveAttribute, true)
	player:SetAttribute(StationConfig.HaulInteractionActionAttribute, "station_pickup")
	player:SetAttribute(StationConfig.HaulInteractionTargetIdAttribute, stationState.stationId)
	player:SetAttribute(StationConfig.HaulInteractionModeAttribute, "pickup")
	player:SetAttribute("HaulLastMovedAmount", movedAmount)
	player:SetAttribute("HaulLastMaterial", stationState.materialType)
end

local function getHumanoidRootPart(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end

	return nil
end

local function _getPlayerByUserId(userId: number): Player?
	for _, player in Players:GetPlayers() do
		if player.UserId == userId then
			return player :: Player
		end
	end

	return nil
end

local function isPlayerAlive(player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false
	end

	return (humanoid :: Humanoid).Health > 0
end

local ATTRIBUTE_FOOD_PRODUCED_TOTAL = "FoodProducedTotal"
local ATTRIBUTE_FOOD_TOTAL = "FoodTotal"
local ATTRIBUTE_METAL_PRODUCED_TOTAL = "MetalProducedTotal"
local ATTRIBUTE_METAL_TOTAL = "MetalTotal"

local function applyDebugAttributes(state: StationState)
	local flowSnapshot = ResourceFlowState.GetSnapshot()
	local woodTotal = 0
	local stoneTotal = 0
	local foodTotal = 0
	local metalTotal = 0
	if state.materialType == "Wood" then
		woodTotal = state.resourceTotal
	elseif state.materialType == "Stone" then
		stoneTotal = state.resourceTotal
	elseif state.materialType == "Food" then
		foodTotal = state.resourceTotal
	elseif state.materialType == "Metal" then
		metalTotal = state.resourceTotal
	end

	state.part:SetAttribute(ATTRIBUTE_IS_ACTIVE, state.isActive)
	state.part:SetAttribute(ATTRIBUTE_ESSENCE_TOTAL, state.resourceTotal)
	state.part:SetAttribute(ATTRIBUTE_WOOD_TOTAL, woodTotal)
	state.part:SetAttribute(ATTRIBUTE_STONE_TOTAL, stoneTotal)
	state.part:SetAttribute(ATTRIBUTE_FOOD_TOTAL, foodTotal)
	state.part:SetAttribute(ATTRIBUTE_METAL_TOTAL, metalTotal)
	state.part:SetAttribute(ATTRIBUTE_FOOD_PRODUCED_TOTAL, flowSnapshot.Food.produced)
	state.part:SetAttribute(ATTRIBUTE_METAL_PRODUCED_TOTAL, flowSnapshot.Metal.produced)
	state.part:SetAttribute(ATTRIBUTE_WOOD_PRODUCED_TOTAL, flowSnapshot.Wood.produced)
	state.part:SetAttribute(ATTRIBUTE_WOOD_IN_TRANSIT_TOTAL, flowSnapshot.Wood.inTransit)
	state.part:SetAttribute(ATTRIBUTE_WOOD_STORED_TOTAL, flowSnapshot.Wood.stored)
	state.part:SetAttribute(ATTRIBUTE_WOOD_USABLE_TOTAL, flowSnapshot.Wood.usable)
	state.part:SetAttribute(ATTRIBUTE_STONE_PRODUCED_TOTAL, flowSnapshot.Stone.produced)
	state.part:SetAttribute(ATTRIBUTE_STONE_IN_TRANSIT_TOTAL, flowSnapshot.Stone.inTransit)
	state.part:SetAttribute(ATTRIBUTE_STONE_STORED_TOTAL, flowSnapshot.Stone.stored)
	state.part:SetAttribute(ATTRIBUTE_STONE_USABLE_TOTAL, flowSnapshot.Stone.usable)
	state.part:SetAttribute(ATTRIBUTE_TICK_COUNT, state.tickCount)
	state.part:SetAttribute(ATTRIBUTE_LAST_TICK_AT, state.lastTickAt)
	state.part:SetAttribute(ATTRIBUTE_ACTIVATED_BY, state.activatedByUserId)

	local perTick, maxTotal, modifiers = resolveStationGenerationLimits(state.stationId, state.materialType)
	state.part:SetAttribute(StationConfig.WorksiteUpgradeLevelAttribute, modifiers.level)
	state.part:SetAttribute(StationConfig.WorksiteUpgradeEffectivePerTickAttribute, perTick)
	state.part:SetAttribute(StationConfig.WorksiteUpgradeEffectiveMaxTotalAttribute, maxTotal)

	ResourceFlowState.ApplyAttributesToPart(state.part)
end

local function getMaterialTypeForStation(stationId: string): "Wood" | "Stone" | "Food" | "Metal"
	if string.match(stationId, "^" .. StationConfig.MiningStationNamePrefix) ~= nil then
		return "Stone"
	end
	if string.match(stationId, "^" .. StationConfig.ForgeNamePrefix) ~= nil then
		return "Metal"
	end
	if string.match(stationId, "^" .. StationConfig.FarmNamePrefix) ~= nil then
		return "Food"
	end

	return "Wood"
end

local function resolveLaborActionForStation(stationId: string, specialistRole: string?): string?
	local stationOverride = StationConfig.LaborActionByStationId[stationId]
	if type(stationOverride) == "string" and stationOverride ~= "" then
		return stationOverride
	end

	return LaborActionState.ResolveActionForSpecialistRole(specialistRole)
end

local function getRequiredSpecialistRoleForStation(stationId: string): string?
	local required = StationConfig.RequiredSpecialistRoleByStationId[stationId]
	if type(required) == "string" and required ~= "" then
		return required
	end

	return nil
end

local function getSpecialistAssignmentQueryApi(): any?
	-- selene: allow(global_usage)
	local globalValue: any = _G
	if type(globalValue) ~= "table" then
		return nil
	end

	local queryApi = globalValue._SpecialistAssignmentService_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end

	return queryApi
end

local function findStationsRoot(): Instance?
	local current: Instance = Workspace
	for _, childName in STATION_FOLDER_PATH do
		local nextNode = current:FindFirstChild(childName)
		if not nextNode then
			return nil
		end
		current = nextNode
	end

	return current
end

local function magnitudeBetweenPositions(a: any, b: any): number
	local dx = a.X - b.X
	local dy = a.Y - b.Y
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function shouldTrackStationPart(part: BasePart): boolean
	if string.match(part.Name, "^" .. StationConfig.StationNamePrefix) ~= nil then
		return true
	end

	if string.match(part.Name, "^" .. StationConfig.MiningStationNamePrefix) ~= nil then
		return true
	end

	if string.match(part.Name, "^" .. StationConfig.FarmNamePrefix) ~= nil then
		return true
	end

	if string.match(part.Name, "^" .. StationConfig.ForgeNamePrefix) ~= nil then
		return true
	end

	return false
end

local function registerStationPart(part: BasePart)
	local stationId = part.Name
	if stationStateById[stationId] then
		debugWarn(string.format("Duplicate station id ignored: %s", stationId))
		return
	end

	local state: StationState = {
		stationId = stationId,
		part = part,
		isActive = false,
		resourceTotal = 0,
		materialType = getMaterialTypeForStation(stationId),
		tickCount = 0,
		lastTickAt = 0,
		activatedByUserId = nil,
		accumulatorSeconds = 0,
	}

	stationStateById[stationId] = state
	applyDebugAttributes(state)

	debugLog(string.format("Registered station id=%s", stationId))
end

local function registerStationsFromWorkspace()
	local stationsRoot = findStationsRoot()
	if not stationsRoot then
		debugWarn("No station root found at Workspace.Map.Stations")
		return
	end

	for _, descendant in ((stationsRoot :: any):GetDescendants()) do
		if descendant:IsA("BasePart") and shouldTrackStationPart(descendant) then
			registerStationPart(descendant)
		end
	end

	if next(stationStateById) == nil then
		debugWarn("No station parts registered under Workspace.Map.Stations")
	end
end

local function rejectActivate(player: Player, reason: string)
	debugWarn(string.format("Rejected StationActivateRequest userId=%d reason=%s", player.UserId, reason))
end

local function rejectDebug(player: Player, reason: string)
	debugWarn(string.format("Rejected StationDebugStateRequest userId=%d reason=%s", player.UserId, reason))
end

local function deactivateStation(state: StationState, reason: string)
	state.isActive = false
	state.accumulatorSeconds = 0
	applyDebugAttributes(state)
	debugLog(
		string.format(
			"Station deactivated id=%s reason=%s materialType=%s total=%d",
			state.stationId,
			reason,
			state.materialType,
			state.resourceTotal
		)
	)
end

local function applyLaborDebugAttributes(
	player: Player,
	laborAction: string?,
	objectiveState: string?,
	targetId: string?,
	lastReason: string?
)
	player:SetAttribute(LaborActionConfig.LaborActionAttribute, laborAction)
	player:SetAttribute(LaborActionConfig.LaborActionStateAttribute, objectiveState)
	player:SetAttribute(LaborActionConfig.LaborActionTargetIdAttribute, targetId)
	player:SetAttribute(LaborActionConfig.LaborActionLastReasonAttribute, lastReason)
end

local function clearLaborDebugAttributes(player: Player)
	applyLaborDebugAttributes(player, nil, nil, nil, nil)
end

local function applyTaskAttributes(player: Player, taskSnapshot: any)
	player:SetAttribute(StationConfig.TaskActiveStationIdAttribute, taskSnapshot.activeTaskId)
	player:SetAttribute(StationConfig.TaskProgressRatioAttribute, taskSnapshot.progressRatio)
	player:SetAttribute(StationConfig.TaskStartedAtAttribute, taskSnapshot.startedAt)
	player:SetAttribute(StationConfig.TaskEndsAtAttribute, taskSnapshot.endsAt)
	player:SetAttribute(StationConfig.TaskLastReasonAttribute, taskSnapshot.lastReason)
	player:SetAttribute(StationConfig.TaskObjectiveStateAttribute, taskSnapshot.objectiveState)
	player:SetAttribute(StationConfig.TaskProgressSecondsAttribute, taskSnapshot.progressSeconds)
	player:SetAttribute(StationConfig.TaskRegressionCountAttribute, taskSnapshot.majorRegressionEvents)
	player:SetAttribute(StationConfig.TaskRegressingUntilAttribute, taskSnapshot.regressingUntil)
end

local function setTaskQteResultAttribute(player: Player, result: string?)
	player:SetAttribute(StationConfig.TaskQteResultAttribute, result)
end

local function getTaskStateForStation(stationId: string): any
	local existing = taskStateByStationId[stationId]
	if existing ~= nil then
		return existing
	end

	local created = ContextualTaskProgressLogic.New()
	taskStateByStationId[stationId] = created
	return created
end

local function validateActivationRequest(
	player: Player,
	stationState: StationState,
	skipSpecialistRoleCheck: boolean?
): (boolean, string?)
	if not isPlayerAlive(player) then
		return false, "player_not_alive"
	end

	if player:GetAttribute("Role") ~= RoleConfig.Roles.Tinyfolk then
		return false, "requester_not_tinyfolk"
	end

	local requiredSpecialistRole = getRequiredSpecialistRoleForStation(stationState.stationId)
	if requiredSpecialistRole and skipSpecialistRoleCheck ~= true then
		local specialistRole = player:GetAttribute("SpecialistRole")
		if type(specialistRole) ~= "string" or specialistRole == SpecialistConfig.SpecialistRoles.None then
			return false, string.format("specialist_role_required required=%s", requiredSpecialistRole)
		end

		if specialistRole ~= requiredSpecialistRole then
			return false,
				string.format("specialist_role_mismatch required=%s actual=%s", requiredSpecialistRole, specialistRole)
		end
	end

	local root = getHumanoidRootPart(player)
	if not root then
		return false, "humanoid_root_missing"
	end
	local rootPart = root :: BasePart

	local distance = magnitudeBetweenPositions(stationState.part.Position :: any, rootPart.Position :: any)
	if distance > StationConfig.ActivationRangeStuds then
		return false, string.format("out_of_range distance=%.2f max=%.2f", distance, StationConfig.ActivationRangeStuds)
	end

	return true, nil
end

local function ensureInteractionSpecialistAssignment(player: Player, stationState: StationState): (boolean, string?)
	local requiredSpecialistRole = getRequiredSpecialistRoleForStation(stationState.stationId)
	if not requiredSpecialistRole then
		return true, nil
	end

	local allowed, reason = validateActivationRequest(player, stationState, true)
	if not allowed then
		return false, reason
	end

	if
		player:GetAttribute("SpecialistRole") == requiredSpecialistRole
		and player:GetAttribute("SpecialistAssignedStationId") == stationState.stationId
	then
		return true, nil
	end

	local queryApi = getSpecialistAssignmentQueryApi()
	if queryApi == nil or type(queryApi.AssignForInteraction) ~= "function" then
		if player:GetAttribute("SpecialistRole") == requiredSpecialistRole then
			return true, nil
		end

		return false, "specialist_assignment_api_missing"
	end

	local assigned, assignReason = queryApi.AssignForInteraction(player, requiredSpecialistRole, stationState.stationId)
	if assigned ~= true then
		return false, string.format("specialist_assignment_rejected detail=%s", tostring(assignReason))
	end

	debugLog(
		string.format(
			"Ensured station specialist assignment userId=%d stationId=%s specialistRole=%s reason=%s",
			player.UserId,
			stationState.stationId,
			requiredSpecialistRole,
			tostring(assignReason)
		)
	)
	return true, nil
end

type ProductionTickResult = {
	generatedAmount: number,
	deactivateReason: string?,
}

local function performProductionTick(stationState: StationState, activatingPlayer: Player): ProductionTickResult
	local requiredSpecialistRole = getRequiredSpecialistRoleForStation(stationState.stationId)
	if requiredSpecialistRole then
		if activatingPlayer:GetAttribute("Role") ~= RoleConfig.Roles.Tinyfolk then
			return {
				generatedAmount = 0,
				deactivateReason = "activator_not_tinyfolk",
			}
		end

		local specialistRole = activatingPlayer:GetAttribute("SpecialistRole")
		if specialistRole ~= requiredSpecialistRole then
			return {
				generatedAmount = 0,
				deactivateReason = "specialist_role_lost",
			}
		end

		if activatingPlayer:GetAttribute("SpecialistAssignedStationId") ~= stationState.stationId then
			return {
				generatedAmount = 0,
				deactivateReason = "specialist_assignment_target_lost",
			}
		end
	end

	stationState.tickCount += 1
	stationState.lastTickAt = os.clock()
	stationState.activatedByUserId = activatingPlayer.UserId

	local perTick, maxTotal = resolveStationGenerationLimits(stationState.stationId, stationState.materialType)

	local materialName: "Wood" | "Stone" | "Food" | "Metal" = stationState.materialType
	local materialSnapshot = ResourceFlowState.GetMaterialSnapshot(materialName)
	local remainingCapacity = maxTotal - materialSnapshot.produced
	local generatedAmount = math.min(perTick, math.max(0, remainingCapacity))
	local maxReachedReason = if materialName == "Stone"
		then "max_stone_produced_reached"
		elseif materialName == "Food" then "max_food_produced_reached"
		elseif materialName == "Metal" then "max_metal_produced_reached"
		else "max_wood_produced_reached"
	if generatedAmount <= 0 then
		applyDebugAttributes(stationState)
		return {
			generatedAmount = 0,
			deactivateReason = maxReachedReason,
		}
	end

	if materialName == "Metal" then
		local stoneCost = StationConfig.StoneStoredCostPerRefineTick
		local stoneSnapshot = ResourceFlowState.GetMaterialSnapshot("Stone")
		if stoneSnapshot.stored < stoneCost then
			applyDebugAttributes(stationState)
			return {
				generatedAmount = 0,
				deactivateReason = "insufficient_stored_stone",
			}
		end

		local spent, _, spendError =
			ResourceFlowState.SpendStoredAtomic(0, stoneCost, "forge_refine:" .. stationState.stationId)
		if spent ~= true then
			applyDebugAttributes(stationState)
			return {
				generatedAmount = 0,
				deactivateReason = spendError or "forge_refine_spend_failed",
			}
		end
	end

	local sourcePrefix = if materialName == "Stone"
		then "MiningStation:"
		elseif materialName == "Food" then "Farm:"
		elseif materialName == "Metal" then "Forge:"
		else "WorkStation:"
	local flowSnapshot =
		ResourceFlowState.AddProduced(materialName, sourcePrefix .. stationState.stationId, generatedAmount)
	stationState.resourceTotal = flowSnapshot.produced
	applyDebugAttributes(stationState)

	local tickLabel = if stationState.materialType == "Stone"
		then "Stone"
		elseif stationState.materialType == "Food" then "Food"
		elseif stationState.materialType == "Metal" then "Metal"
		else "Wood"
	debugLog(
		string.format(
			"Labor %s action tick id=%s tick=%d generated=%.0f produced=%d inTransit=%.0f stored=%.0f usable=%.0f userId=%d",
			tickLabel,
			stationState.stationId,
			stationState.tickCount,
			generatedAmount,
			stationState.resourceTotal,
			flowSnapshot.inTransit,
			flowSnapshot.stored,
			flowSnapshot.usable,
			activatingPlayer.UserId
		)
	)

	if flowSnapshot.produced >= maxTotal then
		stationState.resourceTotal = maxTotal
		applyDebugAttributes(stationState)
		return {
			generatedAmount = generatedAmount,
			deactivateReason = maxReachedReason,
		}
	end

	return {
		generatedAmount = generatedAmount,
		deactivateReason = nil,
	}
end

local function completeStationWorkAction(
	player: Player,
	stationState: StationState,
	laborAction: string
): (boolean, string?)
	local assigned, assignReason = ensureInteractionSpecialistAssignment(player, stationState)
	if not assigned then
		return false, assignReason
	end

	local allowed, reason = validateActivationRequest(player, stationState)
	if not allowed then
		return false, reason
	end

	local requiredSpecialistRole = getRequiredSpecialistRoleForStation(stationState.stationId)
	local specialistRole = player:GetAttribute("SpecialistRole")
	local workValidation = LaborActionState.ValidateWorkAction(specialistRole, requiredSpecialistRole)
	if not workValidation.accepted then
		return false, workValidation.reason or "labor_action_rejected"
	end

	local expectedLaborAction = resolveLaborActionForStation(stationState.stationId, specialistRole)
	if expectedLaborAction == nil then
		return false, workValidation.reason or "labor_action_unmapped"
	end

	if expectedLaborAction ~= laborAction then
		return false,
			string.format("labor_action_mismatch expected=%s actual=%s", expectedLaborAction, tostring(laborAction))
	end

	local tickResult = performProductionTick(stationState, player)
	if tickResult.generatedAmount <= 0 then
		return false, tickResult.deactivateReason or "production_blocked"
	end

	applyLaborDebugAttributes(player, laborAction, "completed", stationState.stationId, "work_action_completed")
	notifyLaborWorkActionCompleted(player)
	debugLog(
		string.format(
			"Accepted station work action userId=%d stationId=%s action=%s generated=%.0f",
			player.UserId,
			stationState.stationId,
			laborAction,
			tickResult.generatedAmount
		)
	)
	return true, nil
end

local remotesFolder = ensureRemotesFolder()
local stationActivateRequestRemote = ensureRemoteEvent(remotesFolder, ACTIVATE_REMOTE_NAME)
local stationDebugStateRequestRemote = ensureRemoteEvent(remotesFolder, DEBUG_REQUEST_REMOTE_NAME)
local stationDebugStateResponseRemote = ensureRemoteEvent(remotesFolder, DEBUG_RESPONSE_REMOTE_NAME)

ResourceFlowState.RefreshDeliveryPoints()
registerStationsFromWorkspace()

stationActivateRequestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	local stationId: string? = nil
	local requestMode = "legacy"
	local requestNow: number? = nil
	local requestQteTapAt: number? = nil

	if type(payload) == "string" then
		stationId = payload
	elseif type(payload) == "table" then
		local payloadAny = payload :: any
		if type(payloadAny.stationId) ~= "string" or payloadAny.stationId == "" then
			rejectActivate(player, "malformed_payload")
			return
		end
		if type(payloadAny.mode) ~= "string" then
			rejectActivate(player, "malformed_payload")
			return
		end

		stationId = payloadAny.stationId
		requestMode = payloadAny.mode
		if type(payloadAny.now) == "number" then
			requestNow = payloadAny.now
		end
		if type(payloadAny.qteTapAt) == "number" then
			requestQteTapAt = payloadAny.qteTapAt
		end
	else
		rejectActivate(player, "malformed_payload")
		return
	end

	local stationIdValue = stationId :: string
	local stationState = stationStateById[stationIdValue]
	if not stationState then
		rejectActivate(player, "station_not_found")
		return
	end

	local bypassCooldown = requestMode == "cancel"
	local attemptHaulOnly = willAttemptHaulOnly(stationState, requestMode)

	if not bypassCooldown then
		if attemptHaulOnly then
			if isHaulCoolingDown(player.UserId, requestNow) then
				rejectActivate(player, "haul_cooldown")
				return
			end
			markHaulRequest(player.UserId, requestNow)
		elseif requestMode ~= "legacy" then
			if isCoolingDown(player.UserId, requestNow) then
				rejectActivate(player, "request_cooldown")
				return
			end
			markRequest(player.UserId, requestNow)
		end
	end

	if
		requestMode == "begin"
		or requestMode == "cancel"
		or requestMode == "complete"
		or requestMode == "block"
		or requestMode == "unblock"
		or requestMode == "disrupt"
	then
		if requestMode == "begin" and StationConfig.TaskQteEnabled == true then
			setTaskQteResultAttribute(player, nil)
		end

		if requestMode ~= "cancel" and requestMode ~= "unblock" and requestMode ~= "block" then
			local allowed, reason = validateActivationRequest(player, stationState)
			if not allowed then
				rejectActivate(player, reason :: string)
				return
			end
		end

		local taskState = getTaskStateForStation(stationIdValue)
		local resolvedNow = if type(requestNow) == "number" then requestNow else os.clock()
		local taskDurationSeconds = resolveTaskDurationSeconds(player)

		if requestMode == "complete" and StationConfig.TaskQteEnabled == true then
			local qteAttemptAt = if type(requestQteTapAt) == "number" then requestQteTapAt else resolvedNow
			local qteResult = TaskQteTimingLogic.Evaluate({
				now = qteAttemptAt,
				targetAt = taskState.endsAt,
				windowSeconds = StationConfig.TaskQteWindowSeconds,
				bonusSeconds = StationConfig.TaskQteBonusSeconds,
			})

			if qteResult.success then
				setTaskQteResultAttribute(player, "success")
				resolvedNow = qteResult.effectiveNow
				ObjectiveSkillXpProducer.RecordObjectiveQteSuccessXp(player)
			else
				setTaskQteResultAttribute(player, "failed")
				if StationConfig.TaskQteFailureDisrupts == true then
					local disruptResult = ContextualTaskProgressLogic.Resolve(taskState, {
						eventType = "disrupt",
						taskId = stationIdValue,
						now = resolvedNow,
						durationSeconds = taskDurationSeconds,
						regressionPerSecond = StationConfig.TaskRegressionPerSecond,
						stabilizationThresholdSeconds = StationConfig.TaskStabilizationThresholdSeconds,
						majorRegressionStepSeconds = StationConfig.TaskMajorRegressionStepSeconds,
						majorRegressionMaxEvents = StationConfig.TaskMajorRegressionMaxEvents,
						regressionWindowSeconds = StationConfig.TaskRegressionWindowSeconds,
					})
					applyTaskAttributes(player, disruptResult.snapshot)
				end

				rejectActivate(player, "task_qte_failed")
				return
			end
		end

		local taskResult = ContextualTaskProgressLogic.Resolve(taskState, {
			eventType = requestMode,
			taskId = stationIdValue,
			now = resolvedNow,
			durationSeconds = taskDurationSeconds,
			regressionPerSecond = StationConfig.TaskRegressionPerSecond,
			stabilizationThresholdSeconds = StationConfig.TaskStabilizationThresholdSeconds,
			majorRegressionStepSeconds = StationConfig.TaskMajorRegressionStepSeconds,
			majorRegressionMaxEvents = StationConfig.TaskMajorRegressionMaxEvents,
			regressionWindowSeconds = StationConfig.TaskRegressionWindowSeconds,
		})
		applyTaskAttributes(player, taskResult.snapshot)

		if not taskResult.accepted then
			rejectActivate(player, string.format("task_%s", taskResult.reason))
			return
		end

		local requiredSpecialistRole = getRequiredSpecialistRoleForStation(stationIdValue)
		local specialistRole = player:GetAttribute("SpecialistRole")
		local workValidation = LaborActionState.ValidateWorkAction(specialistRole, requiredSpecialistRole)
		local resolvedLaborAction = resolveLaborActionForStation(stationIdValue, specialistRole)

		if requestMode == "begin" then
			applyLaborDebugAttributes(
				player,
				resolvedLaborAction,
				taskResult.snapshot.objectiveState,
				stationIdValue,
				taskResult.reason
			)
			return
		end

		if requestMode == "cancel" then
			clearLaborDebugAttributes(player)
			return
		end

		if requestMode == "complete" then
			if resolvedLaborAction == nil then
				rejectActivate(player, workValidation.reason or "labor_action_unmapped")
				return
			end

			local completed, completeReason = completeStationWorkAction(player, stationState, resolvedLaborAction)
			if not completed then
				rejectActivate(player, completeReason :: string)
				return
			end

			local completionAt = if type(requestNow) == "number" then requestNow else os.clock()
			RealmObjectiveCompletionCaller.RecordContextualTaskCompletion(stationIdValue, player.UserId, completionAt)
			PostRescueProtectionCancellationCaller.RecordObjectiveTaskCompletion(player.UserId, completionAt)
			return
		end

		return
	elseif requestMode ~= "legacy" then
		rejectActivate(player, "invalid_mode")
		return
	end

	local materialName: "Wood" | "Stone" | "Food" | "Metal" = stationState.materialType
	local maxHaulAmount = StationConfig.HaulTransferPerStepByMaterial[materialName]
	if type(maxHaulAmount) == "number" and maxHaulAmount > 0 then
		maxHaulAmount = resolveHaulTransferAmount(player, maxHaulAmount)
		local beforeSnapshot = ResourceFlowState.GetMaterialSnapshot(materialName)
		if beforeSnapshot.produced > 0 then
			local haulAllowed, haulReason = validateActivationRequest(player, stationState, true)
			if not haulAllowed then
				rejectActivate(player, haulReason :: string)
				return
			end

			local afterSnapshot = ResourceFlowState.TransferProducedToInTransit(materialName, maxHaulAmount)
			if afterSnapshot.inTransit > beforeSnapshot.inTransit then
				local movedAmount = afterSnapshot.inTransit - beforeSnapshot.inTransit
				stationState.resourceTotal = afterSnapshot.produced
				applyDebugAttributes(stationState)
				applyHaulDebugAttributes(player, stationState, movedAmount)
				debugLog(
					string.format(
						"Accepted StationHaul userId=%d stationId=%s material=%s moved=%.0f produced=%.0f inTransit=%.0f",
						player.UserId,
						stationState.stationId,
						materialName,
						movedAmount,
						afterSnapshot.produced,
						afterSnapshot.inTransit
					)
				)
				return
			end
		end
	end

	local assigned, assignReason = ensureInteractionSpecialistAssignment(player, stationState)
	if not assigned then
		rejectActivate(player, assignReason :: string)
		return
	end

	debugLog(
		string.format(
			"Accepted StationAssignRequest userId=%d stationId=%s reason=%s (production requires completed work action)",
			player.UserId,
			stationIdValue,
			tostring(assignReason)
		)
	)
end)

stationDebugStateRequestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	if payload ~= nil and type(payload) ~= "string" then
		rejectDebug(player, "malformed_payload")
		return
	end

	local requestedStationId = payload :: string?
	if requestedStationId then
		local stationState = stationStateById[requestedStationId]
		if not stationState then
			rejectDebug(player, "station_not_found")
			return
		end

		local flowSnapshot = ResourceFlowState.GetSnapshot()
		local effectivePerTick, effectiveMaxTotal, modifiers =
			resolveStationGenerationLimits(stationState.stationId, stationState.materialType)

		stationDebugStateResponseRemote:FireClient(player, {
			stationId = stationState.stationId,
			materialType = stationState.materialType,
			isActive = stationState.isActive,
			essenceTotal = stationState.resourceTotal,
			woodTotal = stationState.materialType == "Wood" and stationState.resourceTotal or 0,
			stoneTotal = stationState.materialType == "Stone" and stationState.resourceTotal or 0,
			foodTotal = stationState.materialType == "Food" and stationState.resourceTotal or 0,
			metalTotal = stationState.materialType == "Metal" and stationState.resourceTotal or 0,
			tickCount = stationState.tickCount,
			activatedByUserId = stationState.activatedByUserId,
			upgradeLevel = modifiers.level,
			effectivePerTick = effectivePerTick,
			effectiveMaxTotal = effectiveMaxTotal,
			woodProducedTotal = flowSnapshot.Wood.produced,
			woodInTransitTotal = flowSnapshot.Wood.inTransit,
			woodStoredTotal = flowSnapshot.Wood.stored,
			woodUsableTotal = flowSnapshot.Wood.usable,
			stoneProducedTotal = flowSnapshot.Stone.produced,
			stoneInTransitTotal = flowSnapshot.Stone.inTransit,
			stoneStoredTotal = flowSnapshot.Stone.stored,
			stoneUsableTotal = flowSnapshot.Stone.usable,
			foodProducedTotal = flowSnapshot.Food.produced,
			foodInTransitTotal = flowSnapshot.Food.inTransit,
			foodStoredTotal = flowSnapshot.Food.stored,
			foodUsableTotal = flowSnapshot.Food.usable,
			metalProducedTotal = flowSnapshot.Metal.produced,
			metalInTransitTotal = flowSnapshot.Metal.inTransit,
			metalStoredTotal = flowSnapshot.Metal.stored,
			metalUsableTotal = flowSnapshot.Metal.usable,
			warehouseId = flowSnapshot.deliveryPoints.warehouseId,
			granaryId = flowSnapshot.deliveryPoints.granaryId,
		})
		debugLog(string.format("Sent debug state userId=%d stationId=%s", player.UserId, stationState.stationId))
		return
	end

	local snapshot = {}
	local flowSnapshot = ResourceFlowState.GetSnapshot()
	for stationId, stationState in stationStateById do
		local effectivePerTick, effectiveMaxTotal, modifiers =
			resolveStationGenerationLimits(stationId, stationState.materialType)
		table.insert(snapshot, {
			stationId = stationId,
			materialType = stationState.materialType,
			isActive = stationState.isActive,
			essenceTotal = stationState.resourceTotal,
			woodTotal = stationState.materialType == "Wood" and stationState.resourceTotal or 0,
			stoneTotal = stationState.materialType == "Stone" and stationState.resourceTotal or 0,
			foodTotal = stationState.materialType == "Food" and stationState.resourceTotal or 0,
			metalTotal = stationState.materialType == "Metal" and stationState.resourceTotal or 0,
			tickCount = stationState.tickCount,
			activatedByUserId = stationState.activatedByUserId,
			upgradeLevel = modifiers.level,
			effectivePerTick = effectivePerTick,
			effectiveMaxTotal = effectiveMaxTotal,
			woodProducedTotal = flowSnapshot.Wood.produced,
			woodInTransitTotal = flowSnapshot.Wood.inTransit,
			woodStoredTotal = flowSnapshot.Wood.stored,
			woodUsableTotal = flowSnapshot.Wood.usable,
			stoneProducedTotal = flowSnapshot.Stone.produced,
			stoneInTransitTotal = flowSnapshot.Stone.inTransit,
			stoneStoredTotal = flowSnapshot.Stone.stored,
			stoneUsableTotal = flowSnapshot.Stone.usable,
			foodProducedTotal = flowSnapshot.Food.produced,
			foodInTransitTotal = flowSnapshot.Food.inTransit,
			foodStoredTotal = flowSnapshot.Food.stored,
			foodUsableTotal = flowSnapshot.Food.usable,
			metalProducedTotal = flowSnapshot.Metal.produced,
			metalInTransitTotal = flowSnapshot.Metal.inTransit,
			metalStoredTotal = flowSnapshot.Metal.stored,
			metalUsableTotal = flowSnapshot.Metal.usable,
			warehouseId = flowSnapshot.deliveryPoints.warehouseId,
			granaryId = flowSnapshot.deliveryPoints.granaryId,
		})
	end

	stationDebugStateResponseRemote:FireClient(player, snapshot)
	debugLog(string.format("Sent debug state snapshot userId=%d stationCount=%d", player.UserId, #snapshot))
end)

Players.PlayerRemoving:Connect(function(player: Player)
	lastRequestAtByUserId[player.UserId] = nil
	lastHaulRequestAtByUserId[player.UserId] = nil

	for _, stationState in stationStateById do
		if stationState.activatedByUserId == player.UserId and stationState.isActive then
			debugLog(string.format("Activation owner left; station remains active id=%s", stationState.stationId))
		end
	end
end)

RunService.Heartbeat:Connect(function(_deltaTime: number)
	for _, stationState in stationStateById do
		if stationState.isActive then
			deactivateStation(stationState, "passive_generation_disabled")
		end
		applyDebugAttributes(stationState)
	end
end)

debugLog("StationService initialized")

-- Test-only exports for runtime proof slices.
-- selene: allow(global_usage)
_G._StationService_StationState = stationStateById
-- selene: allow(global_usage)
_G._StationService_TaskState = taskStateByStationId
-- selene: allow(global_usage)
_G._StationService_LastHaulRequestAt = lastHaulRequestAtByUserId
