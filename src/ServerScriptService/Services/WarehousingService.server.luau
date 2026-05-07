--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local StationConfig = require(Config:WaitForChild("StationConfig"))
local ResourceFlowState = require(script.Parent:WaitForChild("ResourceFlowState"))

local REMOTES_FOLDER_NAME = "Remotes"
local DELIVER_REMOTE_NAME = "WarehouseDeliverRequest"
local DEBUG_REQUEST_REMOTE_NAME = "WarehousingDebugStateRequest"
local DEBUG_RESPONSE_REMOTE_NAME = "WarehousingDebugStateResponse"

local WAREHOUSE_FOLDER_PATH = {"Map", "Stations"}

type WarehouseState = {
	warehouseId: string,
	part: BasePart,
}

local warehouseStateById: {[string]: WarehouseState} = {}
local lastRequestAtByUserId: {[number]: number} = {}

local function debugLog(message: string)
	print(string.format("[WarehousingService] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[WarehousingService] %s", message))
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

local function applyDebugAttributes(state: WarehouseState)
	local flowSnapshot = ResourceFlowState.GetSnapshot()

	state.part:SetAttribute("WoodInTransitTotal", flowSnapshot.Wood.inTransit)
	state.part:SetAttribute("WoodStoredTotal", flowSnapshot.Wood.stored)
	state.part:SetAttribute("WoodUsableTotal", flowSnapshot.Wood.usable)
	state.part:SetAttribute("StoneInTransitTotal", flowSnapshot.Stone.inTransit)
	state.part:SetAttribute("StoneStoredTotal", flowSnapshot.Stone.stored)
	state.part:SetAttribute("StoneUsableTotal", flowSnapshot.Stone.usable)
end

local function findWarehousesRoot(): Instance?
	local current: Instance = Workspace
	for _, childName in WAREHOUSE_FOLDER_PATH do
		local nextNode = current:FindFirstChild(childName)
		if not nextNode then
			return nil
		end
		current = nextNode
	end

	return current
end

local function shouldTrackWarehousePart(part: BasePart): boolean
	return string.match(part.Name, "^" .. StationConfig.WarehouseNamePrefix) ~= nil
end

local function registerWarehousePart(part: BasePart)
	local warehouseId = part.Name
	if warehouseStateById[warehouseId] then
		debugWarn(string.format("Duplicate warehouse id ignored: %s", warehouseId))
		return
	end

	local state: WarehouseState = {
		warehouseId = warehouseId,
		part = part,
	}

	warehouseStateById[warehouseId] = state
	applyDebugAttributes(state)

	debugLog(string.format("Registered warehouse id=%s", warehouseId))
end

local function registerWarehousesFromWorkspace()
	local warehousesRoot = findWarehousesRoot()
	if not warehousesRoot then
		debugWarn("No warehouse root found at Workspace.Map.Stations")
		return
	end

	for _, descendant in warehousesRoot:GetDescendants() do
		if descendant:IsA("BasePart") and shouldTrackWarehousePart(descendant) then
			registerWarehousePart(descendant)
		end
	end

	if next(warehouseStateById) == nil then
		debugWarn("No warehouse parts registered under Workspace.Map.Stations")
	end
end

local function rejectDeliver(player: Player, reason: string)
	debugWarn(string.format("Rejected WarehouseDeliverRequest userId=%d reason=%s", player.UserId, reason))
end

local function rejectDebug(player: Player, reason: string)
	debugWarn(string.format("Rejected WarehousingDebugStateRequest userId=%d reason=%s", player.UserId, reason))
end

local remotesFolder = ensureRemotesFolder()
local deliverRemote = ensureRemoteEvent(remotesFolder, DELIVER_REMOTE_NAME)
local debugRequestRemote = ensureRemoteEvent(remotesFolder, DEBUG_REQUEST_REMOTE_NAME)
local debugResponseRemote = ensureRemoteEvent(remotesFolder, DEBUG_RESPONSE_REMOTE_NAME)

registerWarehousesFromWorkspace()

deliverRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	if isCoolingDown(player.UserId) then
		rejectDeliver(player, "request_cooldown")
		return
	end

	markRequest(player.UserId)

	if type(payload) ~= "string" then
		rejectDeliver(player, "malformed_payload")
		return
	end

	local warehouseId = payload
	local warehouseState = warehouseStateById[warehouseId]
	if not warehouseState then
		rejectDeliver(player, "warehouse_not_found")
		return
	end

	if not isPlayerAlive(player) then
		rejectDeliver(player, "player_not_alive")
		return
	end

	local root = getHumanoidRootPart(player)
	if not root then
		rejectDeliver(player, "humanoid_root_missing")
		return
	end

	local distance = (warehouseState.part.Position - root.Position).Magnitude
	if distance > StationConfig.ActivationRangeStuds then
		rejectDeliver(player, string.format("out_of_range distance=%.2f max=%.2f", distance, StationConfig.ActivationRangeStuds))
		return
	end

	local flowSnapshot = ResourceFlowState.GetSnapshot()
	local inTransitTotal = flowSnapshot.Wood.inTransit + flowSnapshot.Stone.inTransit
	if inTransitTotal <= 0 then
		rejectDeliver(player, "nothing_in_transit")
		return
	end

	local deliverAmount = math.min(2, inTransitTotal)
	if flowSnapshot.Wood.inTransit > 0 then
		ResourceFlowState.TransferInTransitToStored("Wood", deliverAmount)
	elseif flowSnapshot.Stone.inTransit > 0 then
		ResourceFlowState.TransferInTransitToStored("Stone", deliverAmount)
	end

	applyDebugAttributes(warehouseState)

	debugLog(string.format("Accepted WarehouseDeliverRequest userId=%d warehouseId=%s", player.UserId, warehouseId))
end)

debugRequestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	if payload ~= nil and type(payload) ~= "string" then
		rejectDebug(player, "malformed_payload")
		return
	end

	local requestedWarehouseId = payload :: string?
	if requestedWarehouseId then
		local warehouseState = warehouseStateById[requestedWarehouseId]
		if not warehouseState then
			rejectDebug(player, "warehouse_not_found")
			return
		end

		local flowSnapshot = ResourceFlowState.GetSnapshot()
		debugResponseRemote:FireClient(player, {
			warehouseId = warehouseState.warehouseId,
			woodInTransit = flowSnapshot.Wood.inTransit,
			woodStored = flowSnapshot.Wood.stored,
			woodUsable = flowSnapshot.Wood.usable,
			stoneInTransit = flowSnapshot.Stone.inTransit,
			stoneStored = flowSnapshot.Stone.stored,
			stoneUsable = flowSnapshot.Stone.usable,
		})
		debugLog(string.format("Sent warehouse debug state userId=%d warehouseId=%s", player.UserId, warehouseState.warehouseId))
		return
	end

	local snapshot = {}
	for warehouseId, warehouseState in warehouseStateById do
		local flowSnapshot = ResourceFlowState.GetSnapshot()
		table.insert(snapshot, {
			warehouseId = warehouseId,
			woodInTransit = flowSnapshot.Wood.inTransit,
			woodStored = flowSnapshot.Wood.stored,
			woodUsable = flowSnapshot.Wood.usable,
			stoneInTransit = flowSnapshot.Stone.inTransit,
			stoneStored = flowSnapshot.Stone.stored,
			stoneUsable = flowSnapshot.Stone.usable,
		})
	end

	debugResponseRemote:FireClient(player, snapshot)
	debugLog(string.format("Sent warehouse debug state snapshot userId=%d warehouseCount=%d", player.UserId, #snapshot))
end)

Players.PlayerRemoving:Connect(function(player: Player)
	lastRequestAtByUserId[player.UserId] = nil
end)

debugLog("WarehousingService initialized")
