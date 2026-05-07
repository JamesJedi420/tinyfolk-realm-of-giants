--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local REMOTES_FOLDER_NAME = "Remotes"
local ASSIGN_REMOTE_NAME = "SpecialistAssignRequest"
local CLEAR_REMOTE_NAME = "SpecialistClearRequest"
local DEBUG_REQUEST_REMOTE_NAME = "SpecialistDebugStateRequest"
local DEBUG_RESPONSE_REMOTE_NAME = "SpecialistDebugStateResponse"

local ASSIGN_WOODCUTTER_KEY = Enum.KeyCode.Z
local ASSIGN_MINER_KEY = Enum.KeyCode.X
local ASSIGN_WORSHIPPER_KEY = Enum.KeyCode.C
local CLEAR_KEY = Enum.KeyCode.V
local DEBUG_KEY = Enum.KeyCode.B

local localPlayer = Players.LocalPlayer

local function debugLog(message: string)
	print(string.format("[SpecialistClient] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[SpecialistClient] %s", message))
end

debugLog("Booting LocalScript")

local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME)
local assignRemote = remotesFolder:WaitForChild(ASSIGN_REMOTE_NAME) :: RemoteEvent
local clearRemote = remotesFolder:WaitForChild(CLEAR_REMOTE_NAME) :: RemoteEvent
local debugRequestRemote = remotesFolder:WaitForChild(DEBUG_REQUEST_REMOTE_NAME) :: RemoteEvent
local debugResponseRemote = remotesFolder:WaitForChild(DEBUG_RESPONSE_REMOTE_NAME) :: RemoteEvent

local function requestAssign(specialistRole: string)
	assignRemote:FireServer({
		specialistRole = specialistRole,
		assignedStationId = nil,
	})
	debugLog(string.format("Sent SpecialistAssignRequest specialistRole=%s userId=%d", specialistRole, localPlayer.UserId))
end

local function requestClear()
	clearRemote:FireServer()
	debugLog(string.format("Sent SpecialistClearRequest userId=%d", localPlayer.UserId))
end

local function requestDebugState()
	debugRequestRemote:FireServer(nil)
	debugLog(string.format("Sent SpecialistDebugStateRequest userId=%d", localPlayer.UserId))
end

debugResponseRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		debugWarn("Received malformed specialist debug payload")
		return
	end

	debugLog(string.format(
		"Specialist debug userId=%s role=%s isTinyfolk=%s specialistRole=%s assignedStationId=%s lastAssignmentReason=%s lastAssignedAt=%s",
		tostring(payload.userId),
		tostring(payload.role),
		tostring(payload.isTinyfolk),
		tostring(payload.specialistRole),
		tostring(payload.assignedStationId),
		tostring(payload.lastAssignmentReason),
		tostring(payload.lastAssignedAt)
	))
end)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
	if gameProcessedEvent then
		return
	end

	if input.KeyCode == ASSIGN_WOODCUTTER_KEY then
		requestAssign("Woodcutter")
	elseif input.KeyCode == ASSIGN_MINER_KEY then
		requestAssign("Miner")
	elseif input.KeyCode == ASSIGN_WORSHIPPER_KEY then
		requestAssign("Worshipper")
	elseif input.KeyCode == CLEAR_KEY then
		requestClear()
	elseif input.KeyCode == DEBUG_KEY then
		requestDebugState()
	end
end)

debugLog("Input hook active (Z=Woodcutter, X=Miner, C=Worshipper, V=Clear, B=Debug State)")
