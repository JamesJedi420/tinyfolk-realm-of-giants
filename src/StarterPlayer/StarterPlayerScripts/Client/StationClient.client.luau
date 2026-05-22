--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local StationConfig = require(Config:WaitForChild("StationConfig"))

local REMOTES_FOLDER_NAME = "Remotes"
local ACTIVATE_REMOTE_NAME = "StationActivateRequest"
local WAREHOUSE_DELIVER_REMOTE_NAME = "WarehouseDeliverRequest"
local DEBUG_REQUEST_REMOTE_NAME = "StationDebugStateRequest"
local DEBUG_RESPONSE_REMOTE_NAME = "StationDebugStateResponse"

local ACTIVATE_KEY = Enum.KeyCode.Unknown
local DEBUG_KEY = Enum.KeyCode.J
local ACTIVATE_KEY_ENABLED = false

local localPlayer = Players.LocalPlayer

local function debugLog(message: string)
	print(string.format("[StationClient] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[StationClient] %s", message))
end

debugLog("Booting LocalScript")

local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME)
local stationActivateRequestRemote = remotesFolder:WaitForChild(ACTIVATE_REMOTE_NAME) :: RemoteEvent
local warehouseDeliverRequestRemote = remotesFolder:WaitForChild(WAREHOUSE_DELIVER_REMOTE_NAME) :: RemoteEvent
local stationDebugStateRequestRemote = remotesFolder:WaitForChild(DEBUG_REQUEST_REMOTE_NAME) :: RemoteEvent
local stationDebugStateResponseRemote = remotesFolder:WaitForChild(DEBUG_RESPONSE_REMOTE_NAME) :: RemoteEvent

type InteractTarget = {
	kind: "station" | "warehouse",
	id: string,
}

local function getHumanoidRootPart(character: Instance?): BasePart?
	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end

	return nil
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

local function shouldTrackWarehousePart(part: BasePart): boolean
	return string.match(part.Name, "^" .. StationConfig.WarehouseNamePrefix) ~= nil
end

local function getNearestStationId(): string?
	local localRoot = getHumanoidRootPart(localPlayer.Character)
	if not localRoot then
		return nil
	end

	local stationsRoot = Workspace:FindFirstChild("Map")
	if not stationsRoot then
		return nil
	end

	local bestId: string? = nil
	local bestDistance = math.huge

	for _, descendant in stationsRoot:GetDescendants() do
		if descendant:IsA("BasePart") and shouldTrackStationPart(descendant) then
			local distance = (descendant.Position - localRoot.Position).Magnitude
			if distance <= StationConfig.ActivationRangeStuds and distance < bestDistance then
				bestDistance = distance
				bestId = descendant.Name
			end
		end
	end

	return bestId
end

local function getNearestInteractTarget(): InteractTarget?
	local localRoot = getHumanoidRootPart(localPlayer.Character)
	if not localRoot then
		return nil
	end

	local mapRoot = Workspace:FindFirstChild("Map")
	if not mapRoot then
		return nil
	end

	local bestTarget: InteractTarget? = nil
	local bestDistance = math.huge

	for _, descendant in mapRoot:GetDescendants() do
		if descendant:IsA("BasePart") then
			local isStation = shouldTrackStationPart(descendant)
			local isWarehouse = shouldTrackWarehousePart(descendant)
			if isStation or isWarehouse then
				local distance = (descendant.Position - localRoot.Position).Magnitude
				if distance <= StationConfig.ActivationRangeStuds and distance < bestDistance then
					bestDistance = distance
					bestTarget = {
						kind = if isWarehouse then "warehouse" else "station",
						id = descendant.Name,
					} :: InteractTarget
				end
			end
		end
	end

	return bestTarget
end

local function requestActivate()
	local target = getNearestInteractTarget()
	if not target then
		debugWarn("No eligible station or warehouse in range")
		return
	end

	if target.kind == "warehouse" then
		warehouseDeliverRequestRemote:FireServer(target.id)
		debugLog(string.format("Sent WarehouseDeliverRequest warehouseId=%s", target.id))
		return
	end

	stationActivateRequestRemote:FireServer(target.id)
	debugLog(string.format("Sent StationActivateRequest stationId=%s", target.id))
end

local function requestDebugState()
	local stationId = getNearestStationId()
	stationDebugStateRequestRemote:FireServer(stationId)
	if stationId then
		debugLog(string.format("Sent StationDebugStateRequest stationId=%s", stationId))
	else
		debugLog("Sent StationDebugStateRequest snapshot")
	end
end

stationDebugStateResponseRemote.OnClientEvent:Connect(function(payload)
	if type(payload) == "table" then
		local payloadTable: any = payload
		if payloadTable.stationId ~= nil then
			debugLog(
				string.format(
					"Debug state id=%s materialType=%s active=%s essenceTotal=%s woodTotal=%s stoneTotal=%s tickCount=%s activatedBy=%s woodProduced=%s woodInTransit=%s woodStored=%s woodUsable=%s stoneProduced=%s stoneInTransit=%s stoneStored=%s stoneUsable=%s warehouseId=%s granaryId=%s",
					tostring(payloadTable.stationId),
					tostring(payloadTable.materialType),
					tostring(payloadTable.isActive),
					tostring(payloadTable.essenceTotal),
					tostring(payloadTable.woodTotal),
					tostring(payloadTable.stoneTotal),
					tostring(payloadTable.tickCount),
					tostring(payloadTable.activatedByUserId),
					tostring(payloadTable.woodProducedTotal),
					tostring(payloadTable.woodInTransitTotal),
					tostring(payloadTable.woodStoredTotal),
					tostring(payloadTable.woodUsableTotal),
					tostring(payloadTable.stoneProducedTotal),
					tostring(payloadTable.stoneInTransitTotal),
					tostring(payloadTable.stoneStoredTotal),
					tostring(payloadTable.stoneUsableTotal),
					tostring(payloadTable.warehouseId),
					tostring(payloadTable.granaryId)
				)
			)
			return
		end
	end

	if type(payload) == "table" then
		for _, item in payload do
			if type(item) == "table" then
				local itemTable: any = item
				debugLog(
					string.format(
						"Debug snapshot id=%s materialType=%s active=%s essenceTotal=%s woodTotal=%s stoneTotal=%s tickCount=%s activatedBy=%s woodProduced=%s woodInTransit=%s woodStored=%s woodUsable=%s stoneProduced=%s stoneInTransit=%s stoneStored=%s stoneUsable=%s warehouseId=%s granaryId=%s",
						tostring(itemTable.stationId),
						tostring(itemTable.materialType),
						tostring(itemTable.isActive),
						tostring(itemTable.essenceTotal),
						tostring(itemTable.woodTotal),
						tostring(itemTable.stoneTotal),
						tostring(itemTable.tickCount),
						tostring(itemTable.activatedByUserId),
						tostring(itemTable.woodProducedTotal),
						tostring(itemTable.woodInTransitTotal),
						tostring(itemTable.woodStoredTotal),
						tostring(itemTable.woodUsableTotal),
						tostring(itemTable.stoneProducedTotal),
						tostring(itemTable.stoneInTransitTotal),
						tostring(itemTable.stoneStoredTotal),
						tostring(itemTable.stoneUsableTotal),
						tostring(itemTable.warehouseId),
						tostring(itemTable.granaryId)
					)
				)
			end
		end
		return
	end

	debugWarn("Received malformed debug response payload")
end)

UserInputService.InputBegan:Connect(function(input: any, gameProcessedEvent: boolean)
	if gameProcessedEvent then
		return
	end

	if ACTIVATE_KEY_ENABLED and input.KeyCode == ACTIVATE_KEY then
		requestActivate()
	elseif input.KeyCode == DEBUG_KEY then
		requestDebugState()
	end
end)

debugLog("Input hook active (J=Request Debug State)")
