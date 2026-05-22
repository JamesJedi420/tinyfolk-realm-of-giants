--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local StationConfig = require(Config:WaitForChild("StationConfig"))
local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local SpecialistConfig = require(Config:WaitForChild("SpecialistConfig"))
local ConstructionFolder = Shared:WaitForChild("Construction")
local ContextualTaskProgressLogic = require(ConstructionFolder:WaitForChild("ContextualTaskProgressLogic"))
local TaskQteTimingLogic = require(ConstructionFolder:WaitForChild("TaskQteTimingLogic"))
local ResourceFlowState = require(script.Parent:WaitForChild("ResourceFlowState"))

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

type StationState = {
	stationId: string,
	part: BasePart,
	isActive: boolean,
	resourceTotal: number,
	materialType: "Wood" | "Stone",
	tickCount: number,
	lastTickAt: number,
	activatedByUserId: number?,
	accumulatorSeconds: number,
}

local stationStateById: { [string]: StationState } = {}
local lastRequestAtByUserId: { [number]: number? } = {}
local taskStateByStationId: { [string]: any } = {}

local function debugLog(message: string)
	print(string.format("[StationService] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[StationService] %s", message))
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

local function getPlayerByUserId(userId: number): Player?
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

local function applyDebugAttributes(state: StationState)
	local flowSnapshot = ResourceFlowState.GetSnapshot()
	local woodTotal = 0
	local stoneTotal = 0
	if state.materialType == "Wood" then
		woodTotal = state.resourceTotal
	elseif state.materialType == "Stone" then
		stoneTotal = state.resourceTotal
	end

	state.part:SetAttribute(ATTRIBUTE_IS_ACTIVE, state.isActive)
	state.part:SetAttribute(ATTRIBUTE_ESSENCE_TOTAL, state.resourceTotal)
	state.part:SetAttribute(ATTRIBUTE_WOOD_TOTAL, woodTotal)
	state.part:SetAttribute(ATTRIBUTE_STONE_TOTAL, stoneTotal)
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
	ResourceFlowState.ApplyAttributesToPart(state.part)
end

local function getMaterialTypeForStation(stationId: string): "Wood" | "Stone"
	if string.match(stationId, "^" .. StationConfig.MiningStationNamePrefix) ~= nil then
		return "Stone"
	end

	return "Wood"
end

local function getRequiredSpecialistRoleForStation(stationId: string): string?
	local required = StationConfig.RequiredSpecialistRoleByStationId[stationId]
	if type(required) == "string" and required ~= "" then
		return required
	end

	return nil
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

local function validateActivationRequest(player: Player, stationState: StationState): (boolean, string?)
	if not isPlayerAlive(player) then
		return false, "player_not_alive"
	end

	if player:GetAttribute("Role") ~= RoleConfig.Roles.Tinyfolk then
		return false, "requester_not_tinyfolk"
	end

	local requiredSpecialistRole = getRequiredSpecialistRoleForStation(stationState.stationId)
	if requiredSpecialistRole then
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

	local bypassCooldown = requestMode == "cancel"
	if not bypassCooldown and isCoolingDown(player.UserId, requestNow) then
		rejectActivate(player, "request_cooldown")
		return
	end

	if not bypassCooldown then
		markRequest(player.UserId, requestNow)
	end

	local stationIdValue = stationId :: string
	local stationState = stationStateById[stationIdValue]
	if not stationState then
		rejectActivate(player, "station_not_found")
		return
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
			else
				setTaskQteResultAttribute(player, "failed")
				if StationConfig.TaskQteFailureDisrupts == true then
					local disruptResult = ContextualTaskProgressLogic.Resolve(taskState, {
						eventType = "disrupt",
						taskId = stationIdValue,
						now = resolvedNow,
						durationSeconds = StationConfig.TaskDurationSeconds,
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
			durationSeconds = StationConfig.TaskDurationSeconds,
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

		if requestMode ~= "complete" then
			return
		end
	elseif requestMode ~= "legacy" then
		rejectActivate(player, "invalid_mode")
		return
	end

	local allowed, reason = validateActivationRequest(player, stationState)
	if not allowed then
		rejectActivate(player, reason :: string)
		return
	end

	local materialName: "Wood" | "Stone" = stationState.materialType
	local maxHaulAmount = StationConfig.HaulTransferPerStepByMaterial[materialName]
	if type(maxHaulAmount) == "number" and maxHaulAmount > 0 then
		local beforeSnapshot = ResourceFlowState.GetMaterialSnapshot(materialName)
		if beforeSnapshot.produced > 0 then
			local afterSnapshot = ResourceFlowState.TransferProducedToInTransit(materialName, maxHaulAmount)
			if afterSnapshot.inTransit > beforeSnapshot.inTransit then
				stationState.resourceTotal = afterSnapshot.produced
				applyDebugAttributes(stationState)
				debugLog(
					string.format(
						"Accepted StationHaul userId=%d stationId=%s material=%s moved=%.0f produced=%.0f inTransit=%.0f",
						player.UserId,
						stationState.stationId,
						materialName,
						afterSnapshot.inTransit - beforeSnapshot.inTransit,
						afterSnapshot.produced,
						afterSnapshot.inTransit
					)
				)
				return
			end
		end
	end

	if stationState.isActive then
		rejectActivate(player, "already_active_no_produced_to_haul")
		return
	end

	stationState.isActive = true
	stationState.activatedByUserId = player.UserId
	stationState.lastTickAt = os.clock()
	stationState.accumulatorSeconds = 0
	applyDebugAttributes(stationState)

	debugLog(string.format("Accepted StationActivateRequest userId=%d stationId=%s", player.UserId, stationIdValue))
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

		stationDebugStateResponseRemote:FireClient(player, {
			stationId = stationState.stationId,
			materialType = stationState.materialType,
			isActive = stationState.isActive,
			essenceTotal = stationState.resourceTotal,
			woodTotal = stationState.materialType == "Wood" and stationState.resourceTotal or 0,
			stoneTotal = stationState.materialType == "Stone" and stationState.resourceTotal or 0,
			tickCount = stationState.tickCount,
			activatedByUserId = stationState.activatedByUserId,
			woodProducedTotal = flowSnapshot.Wood.produced,
			woodInTransitTotal = flowSnapshot.Wood.inTransit,
			woodStoredTotal = flowSnapshot.Wood.stored,
			woodUsableTotal = flowSnapshot.Wood.usable,
			stoneProducedTotal = flowSnapshot.Stone.produced,
			stoneInTransitTotal = flowSnapshot.Stone.inTransit,
			stoneStoredTotal = flowSnapshot.Stone.stored,
			stoneUsableTotal = flowSnapshot.Stone.usable,
			warehouseId = flowSnapshot.deliveryPoints.warehouseId,
			granaryId = flowSnapshot.deliveryPoints.granaryId,
		})
		debugLog(string.format("Sent debug state userId=%d stationId=%s", player.UserId, stationState.stationId))
		return
	end

	local snapshot = {}
	local flowSnapshot = ResourceFlowState.GetSnapshot()
	for stationId, stationState in stationStateById do
		table.insert(snapshot, {
			stationId = stationId,
			materialType = stationState.materialType,
			isActive = stationState.isActive,
			essenceTotal = stationState.resourceTotal,
			woodTotal = stationState.materialType == "Wood" and stationState.resourceTotal or 0,
			stoneTotal = stationState.materialType == "Stone" and stationState.resourceTotal or 0,
			tickCount = stationState.tickCount,
			activatedByUserId = stationState.activatedByUserId,
			woodProducedTotal = flowSnapshot.Wood.produced,
			woodInTransitTotal = flowSnapshot.Wood.inTransit,
			woodStoredTotal = flowSnapshot.Wood.stored,
			woodUsableTotal = flowSnapshot.Wood.usable,
			stoneProducedTotal = flowSnapshot.Stone.produced,
			stoneInTransitTotal = flowSnapshot.Stone.inTransit,
			stoneStoredTotal = flowSnapshot.Stone.stored,
			stoneUsableTotal = flowSnapshot.Stone.usable,
			warehouseId = flowSnapshot.deliveryPoints.warehouseId,
			granaryId = flowSnapshot.deliveryPoints.granaryId,
		})
	end

	stationDebugStateResponseRemote:FireClient(player, snapshot)
	debugLog(string.format("Sent debug state snapshot userId=%d stationCount=%d", player.UserId, #snapshot))
end)

Players.PlayerRemoving:Connect(function(player: Player)
	lastRequestAtByUserId[player.UserId] = nil

	for _, stationState in stationStateById do
		if stationState.activatedByUserId == player.UserId and stationState.isActive then
			debugLog(string.format("Activation owner left; station remains active id=%s", stationState.stationId))
		end
	end
end)

RunService.Heartbeat:Connect(function(deltaTime: number)
	for _, stationState in stationStateById do
		if not stationState.isActive then
			continue
		end

		stationState.accumulatorSeconds += deltaTime

		while stationState.accumulatorSeconds >= StationConfig.GenerationIntervalSeconds and stationState.isActive do
			local requiredSpecialistRole = getRequiredSpecialistRoleForStation(stationState.stationId)
			local activatingPlayer = stationState.activatedByUserId
					and getPlayerByUserId(stationState.activatedByUserId)
				or nil
			if requiredSpecialistRole then
				if not activatingPlayer then
					deactivateStation(stationState, "activator_missing")
					break
				end

				if activatingPlayer:GetAttribute("Role") ~= RoleConfig.Roles.Tinyfolk then
					deactivateStation(stationState, "activator_not_tinyfolk")
					break
				end

				local specialistRole = activatingPlayer:GetAttribute("SpecialistRole")
				if specialistRole ~= requiredSpecialistRole then
					deactivateStation(stationState, "specialist_role_lost")
					break
				end
			end

			stationState.accumulatorSeconds -= StationConfig.GenerationIntervalSeconds
			stationState.tickCount += 1
			stationState.lastTickAt = os.clock()

			local maxTotal = StationConfig.MaxWoodTotal
			local perTick = StationConfig.WoodPerTick
			if stationState.materialType == "Stone" then
				maxTotal = StationConfig.MaxStoneTotal
				perTick = StationConfig.StonePerTick
			end

			local materialSnapshot = stationState.materialType == "Stone"
					and ResourceFlowState.GetMaterialSnapshot("Stone")
				or ResourceFlowState.GetMaterialSnapshot("Wood")
			local remainingCapacity = maxTotal - materialSnapshot.produced
			local generatedAmount = math.min(perTick, math.max(0, remainingCapacity))
			if generatedAmount <= 0 then
				applyDebugAttributes(stationState)
				deactivateStation(
					stationState,
					stationState.materialType == "Stone" and "max_stone_produced_reached" or "max_wood_produced_reached"
				)
				break
			end

			local flowSnapshot
			if stationState.materialType == "Stone" then
				flowSnapshot =
					ResourceFlowState.AddProduced("Stone", "MiningStation:" .. stationState.stationId, generatedAmount)
				stationState.resourceTotal = flowSnapshot.produced
			else
				flowSnapshot =
					ResourceFlowState.AddProduced("Wood", "WorkStation:" .. stationState.stationId, generatedAmount)
				stationState.resourceTotal = flowSnapshot.produced
			end

			if flowSnapshot.produced >= maxTotal then
				stationState.resourceTotal = maxTotal
				applyDebugAttributes(stationState)
				if stationState.materialType == "Stone" then
					debugLog(
						string.format(
							"Stone tick id=%s tick=%d generated=%.0f produced=%d inTransit=%.0f stored=%.0f usable=%.0f",
							stationState.stationId,
							stationState.tickCount,
							generatedAmount,
							stationState.resourceTotal,
							flowSnapshot.inTransit,
							flowSnapshot.stored,
							flowSnapshot.usable
						)
					)
					deactivateStation(stationState, "max_stone_produced_reached")
				else
					debugLog(
						string.format(
							"Wood tick id=%s tick=%d generated=%.0f produced=%d inTransit=%.0f stored=%.0f usable=%.0f",
							stationState.stationId,
							stationState.tickCount,
							generatedAmount,
							stationState.resourceTotal,
							flowSnapshot.inTransit,
							flowSnapshot.stored,
							flowSnapshot.usable
						)
					)
					deactivateStation(stationState, "max_wood_produced_reached")
				end
				break
			end

			applyDebugAttributes(stationState)
			if stationState.tickCount % StationConfig.DebugLogEveryTicks == 0 then
				if stationState.materialType == "Stone" then
					debugLog(
						string.format(
							"Stone tick id=%s tick=%d generated=%.0f produced=%d inTransit=%.0f stored=%.0f usable=%.0f",
							stationState.stationId,
							stationState.tickCount,
							generatedAmount,
							stationState.resourceTotal,
							flowSnapshot.inTransit,
							flowSnapshot.stored,
							flowSnapshot.usable
						)
					)
				else
					debugLog(
						string.format(
							"Wood tick id=%s tick=%d generated=%.0f produced=%d inTransit=%.0f stored=%.0f usable=%.0f",
							stationState.stationId,
							stationState.tickCount,
							generatedAmount,
							stationState.resourceTotal,
							flowSnapshot.inTransit,
							flowSnapshot.stored,
							flowSnapshot.usable
						)
					)
				end
			end
		end
	end

	for _, stationState in stationStateById do
		applyDebugAttributes(stationState)
	end
end)

debugLog("StationService initialized")

-- Test-only exports for runtime proof slices.
-- selene: allow(global_usage)
_G._StationService_StationState = stationStateById
-- selene: allow(global_usage)
_G._StationService_TaskState = taskStateByStationId
