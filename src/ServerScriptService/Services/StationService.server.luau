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

local STATION_FOLDER_PATH = {"Map", "Stations"}

type StationState = {
	stationId: string,
	part: BasePart,
	isActive: boolean,
	resourceTotal: number,
	materialType: string,
	tickCount: number,
	lastTickAt: number,
	activatedByUserId: number?,
	accumulatorSeconds: number,
}

local stationStateById: {[string]: StationState} = {}
local lastRequestAtByUserId: {[number]: number} = {}

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

local function isCoolingDown(userId: number): boolean
	local last = lastRequestAtByUserId[userId]
	if not last then
		return false
	end

	return (os.clock() - last) < StationConfig.RequestCooldownSeconds
end

local function markRequest(userId: number)
	lastRequestAtByUserId[userId] = os.clock()
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
			return player
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

	return humanoid.Health > 0
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

local function getMaterialTypeForStation(stationId: string): string
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

	for _, descendant in stationsRoot:GetDescendants() do
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
	debugLog(string.format("Station deactivated id=%s reason=%s materialType=%s total=%d", state.stationId, reason, state.materialType, state.resourceTotal))
end

local remotesFolder = ensureRemotesFolder()
local stationActivateRequestRemote = ensureRemoteEvent(remotesFolder, ACTIVATE_REMOTE_NAME)
local stationDebugStateRequestRemote = ensureRemoteEvent(remotesFolder, DEBUG_REQUEST_REMOTE_NAME)
local stationDebugStateResponseRemote = ensureRemoteEvent(remotesFolder, DEBUG_RESPONSE_REMOTE_NAME)

ResourceFlowState.RefreshDeliveryPoints()
registerStationsFromWorkspace()

stationActivateRequestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	if isCoolingDown(player.UserId) then
		rejectActivate(player, "request_cooldown")
		return
	end

	markRequest(player.UserId)

	if type(payload) ~= "string" then
		rejectActivate(player, "malformed_payload")
		return
	end

	local stationId = payload
	local stationState = stationStateById[stationId]
	if not stationState then
		rejectActivate(player, "station_not_found")
		return
	end

	if not isPlayerAlive(player) then
		rejectActivate(player, "player_not_alive")
		return
	end

	if player:GetAttribute("Role") ~= RoleConfig.Roles.Tinyfolk then
		rejectActivate(player, "requester_not_tinyfolk")
		return
	end

	local requiredSpecialistRole = getRequiredSpecialistRoleForStation(stationState.stationId)
	if requiredSpecialistRole then
		local specialistRole = player:GetAttribute("SpecialistRole")
		if type(specialistRole) ~= "string" or specialistRole == SpecialistConfig.SpecialistRoles.None then
			rejectActivate(player, string.format("specialist_role_required required=%s", requiredSpecialistRole))
			return
		end

		if specialistRole ~= requiredSpecialistRole then
			rejectActivate(player, string.format("specialist_role_mismatch required=%s actual=%s", requiredSpecialistRole, specialistRole))
			return
		end
	end

	local root = getHumanoidRootPart(player)
	if not root then
		rejectActivate(player, "humanoid_root_missing")
		return
	end

	local distance = (stationState.part.Position - root.Position).Magnitude
	if distance > StationConfig.ActivationRangeStuds then
		rejectActivate(player, string.format("out_of_range distance=%.2f max=%.2f", distance, StationConfig.ActivationRangeStuds))
		return
	end

	local materialName = stationState.materialType == "Stone" and "Stone" or "Wood"
	local maxHaulAmount = StationConfig.HaulTransferPerStepByMaterial[materialName]
	if type(maxHaulAmount) == "number" and maxHaulAmount > 0 then
		local beforeSnapshot = ResourceFlowState.GetMaterialSnapshot(materialName)
		if beforeSnapshot.produced > 0 then
			local afterSnapshot = ResourceFlowState.TransferProducedToInTransit(materialName, maxHaulAmount)
			if afterSnapshot.inTransit > beforeSnapshot.inTransit then
				stationState.resourceTotal = afterSnapshot.produced
				applyDebugAttributes(stationState)
				debugLog(string.format(
					"Accepted StationHaul userId=%d stationId=%s material=%s moved=%.0f produced=%.0f inTransit=%.0f",
					player.UserId,
					stationState.stationId,
					materialName,
					afterSnapshot.inTransit - beforeSnapshot.inTransit,
					afterSnapshot.produced,
					afterSnapshot.inTransit
				))
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

	debugLog(string.format("Accepted StationActivateRequest userId=%d stationId=%s", player.UserId, stationId))
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
			local activatingPlayer = stationState.activatedByUserId and getPlayerByUserId(stationState.activatedByUserId) or nil
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
				deactivateStation(stationState, stationState.materialType == "Stone" and "max_stone_produced_reached" or "max_wood_produced_reached")
				break
			end

			local flowSnapshot
			if stationState.materialType == "Stone" then
				flowSnapshot = ResourceFlowState.AddProduced("Stone", "MiningStation:" .. stationState.stationId, generatedAmount)
				stationState.resourceTotal = flowSnapshot.produced
			else
				flowSnapshot = ResourceFlowState.AddProduced("Wood", "WorkStation:" .. stationState.stationId, generatedAmount)
				stationState.resourceTotal = flowSnapshot.produced
			end

			if flowSnapshot.produced >= maxTotal then
				stationState.resourceTotal = maxTotal
				applyDebugAttributes(stationState)
				if stationState.materialType == "Stone" then
					debugLog(string.format("Stone tick id=%s tick=%d generated=%.0f produced=%d inTransit=%.0f stored=%.0f usable=%.0f", stationState.stationId, stationState.tickCount, generatedAmount, stationState.resourceTotal, flowSnapshot.inTransit, flowSnapshot.stored, flowSnapshot.usable))
					deactivateStation(stationState, "max_stone_produced_reached")
				else
					debugLog(string.format("Wood tick id=%s tick=%d generated=%.0f produced=%d inTransit=%.0f stored=%.0f usable=%.0f", stationState.stationId, stationState.tickCount, generatedAmount, stationState.resourceTotal, flowSnapshot.inTransit, flowSnapshot.stored, flowSnapshot.usable))
					deactivateStation(stationState, "max_wood_produced_reached")
				end
				break
			end

			applyDebugAttributes(stationState)
			if stationState.tickCount % StationConfig.DebugLogEveryTicks == 0 then
				if stationState.materialType == "Stone" then
					debugLog(string.format("Stone tick id=%s tick=%d generated=%.0f produced=%d inTransit=%.0f stored=%.0f usable=%.0f", stationState.stationId, stationState.tickCount, generatedAmount, stationState.resourceTotal, flowSnapshot.inTransit, flowSnapshot.stored, flowSnapshot.usable))
				else
					debugLog(string.format("Wood tick id=%s tick=%d generated=%.0f produced=%d inTransit=%.0f stored=%.0f usable=%.0f", stationState.stationId, stationState.tickCount, generatedAmount, stationState.resourceTotal, flowSnapshot.inTransit, flowSnapshot.stored, flowSnapshot.usable))
				end
			end
		end
	end

	for _, stationState in stationStateById do
		applyDebugAttributes(stationState)
	end
end)

debugLog("StationService initialized")
