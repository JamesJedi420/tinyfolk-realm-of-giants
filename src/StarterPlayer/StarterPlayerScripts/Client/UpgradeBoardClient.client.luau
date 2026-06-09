--!strict

local Players = game:GetService("Players")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local UpgradeBoardConfig = require(Config:WaitForChild("UpgradeBoardConfig"))

local REMOTES_FOLDER_NAME = "Remotes"
local DEBUG_REQUEST_REMOTE_NAME = "UpgradeBoardDebugStateRequest"
local DEBUG_RESPONSE_REMOTE_NAME = "UpgradeBoardDebugStateResponse"
local DEBUG_ESSENCE_DRAIN_REMOTE_NAME = "UpgradeBoardDebugEssenceDrain"

local DEBUG_KEY = Enum.KeyCode.P
local DEBUG_ESSENCE_DRAIN_KEY = Enum.KeyCode.L

local localPlayer = Players.LocalPlayer
type KeyCodeValue = any

type KeyBinding = {
	actionName: string,
	isDebugRequest: boolean?,
	isEssenceDrain: boolean?,
}

local KEY_BINDINGS: { [KeyCodeValue]: KeyBinding } = {
	[DEBUG_KEY] = {
		actionName = "UpgradeBoard_RequestDebug",
		isDebugRequest = true,
	},
	[DEBUG_ESSENCE_DRAIN_KEY] = {
		actionName = "UpgradeBoard_DebugEssenceDrain",
		isEssenceDrain = true,
	},
}

local function debugLog(message: string)
	print(string.format("[UpgradeBoardClient] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[UpgradeBoardClient] %s", message))
end

debugLog("Booting debug-only LocalScript (board purchases deprecated)")

local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME)
local debugRequestRemote = remotesFolder:WaitForChild(DEBUG_REQUEST_REMOTE_NAME) :: RemoteEvent
local debugResponseRemote = remotesFolder:WaitForChild(DEBUG_RESPONSE_REMOTE_NAME) :: RemoteEvent
local debugEssenceDrainRemote = remotesFolder:WaitForChild(DEBUG_ESSENCE_DRAIN_REMOTE_NAME) :: RemoteEvent

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

local function shouldTrackBoardPart(part: BasePart): boolean
	return string.match(part.Name, "^" .. UpgradeBoardConfig.BoardNamePrefix) ~= nil
end

local function getNearestBoardId(): string?
	local localRoot = getHumanoidRootPart(localPlayer.Character)
	if not localRoot then
		return nil
	end

	local map = Workspace:FindFirstChild("Map")
	if not map then
		return nil
	end

	local bestBoardId: string? = nil
	local bestDistance = math.huge

	for _, descendant in map:GetDescendants() do
		if descendant:IsA("BasePart") and shouldTrackBoardPart(descendant) then
			local distance = (descendant.Position - localRoot.Position).Magnitude
			if distance <= UpgradeBoardConfig.InteractionRangeStuds and distance < bestDistance then
				bestDistance = distance
				bestBoardId = descendant.Name
			end
		end
	end

	return bestBoardId
end

local function requestDebugState(triggerKey: any)
	local boardId = getNearestBoardId()
	debugRequestRemote:FireServer(boardId)
	if boardId then
		debugLog(string.format("Key=%s sent UpgradeBoardDebugStateRequest boardId=%s", tostring(triggerKey), boardId))
	else
		debugLog(string.format("Key=%s sent UpgradeBoardDebugStateRequest snapshot", tostring(triggerKey)))
	end
end

local function dispatchTrackedKey(keyCode: any, source: string, gameProcessedEvent: boolean?)
	local binding = KEY_BINDINGS[keyCode]
	if not binding then
		return
	end

	if UserInputService:GetFocusedTextBox() then
		debugLog(
			string.format(
				"Ignored key=%s source=%s reason=textbox_focused gameProcessed=%s",
				tostring(keyCode),
				source,
				tostring(gameProcessedEvent)
			)
		)
		return
	end

	if binding.isDebugRequest == true then
		requestDebugState(keyCode)
		return
	end

	if binding.isEssenceDrain == true then
		debugEssenceDrainRemote:FireServer()
		return
	end

	debugWarn(string.format("Ignored key=%s source=%s reason=unhandled_binding", tostring(keyCode), source))
end

debugResponseRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		debugWarn("Received malformed upgrade board debug payload")
		return
	end
	local payloadTable: any = payload

	if payloadTable.boardId ~= nil then
		debugLog(
			string.format(
				"Upgrade debug boardId=%s shrineLevel=%s dwellingLevel=%s resolvedMaxHealth=%s resolvedWalkSpeed=%s resolvedPowerBudget=%s resolvedMovementControl=%s giantEssenceTotal=%s",
				tostring(payloadTable.boardId),
				tostring(payloadTable.shrineLevel),
				tostring(payloadTable.dwellingLevel),
				tostring(payloadTable.resolvedMaxHealth),
				tostring(payloadTable.resolvedWalkSpeed),
				tostring(payloadTable.resolvedPowerBudget),
				tostring(payloadTable.resolvedMovementControl),
				tostring(payloadTable.giantEssenceTotal)
			)
		)
		return
	end

	local boards = payloadTable.boards
	if type(boards) == "table" then
		for _, board in boards do
			if type(board) == "table" then
				local boardTable: any = board
				debugLog(
					string.format(
						"Upgrade debug snapshot boardId=%s isEnabled=%s selectionCount=%s",
						tostring(boardTable.boardId),
						tostring(boardTable.isEnabled),
						tostring(boardTable.selectionCount)
					)
				)
			end
		end
		debugLog(
			string.format(
				"Upgrade debug snapshot shrineLevel=%s dwellingLevel=%s resolvedMaxHealth=%s resolvedWalkSpeed=%s resolvedPowerBudget=%s resolvedMovementControl=%s giantEssenceTotal=%s",
				tostring(payloadTable.shrineLevel),
				tostring(payloadTable.dwellingLevel),
				tostring(payloadTable.resolvedMaxHealth),
				tostring(payloadTable.resolvedWalkSpeed),
				tostring(payloadTable.resolvedPowerBudget),
				tostring(payloadTable.resolvedMovementControl),
				tostring(payloadTable.giantEssenceTotal)
			)
		)
		return
	end

	debugWarn("Received malformed upgrade board debug snapshot")
end)

for keyCode, binding in KEY_BINDINGS do
	ContextActionService:BindActionAtPriority(
		binding.actionName,
		function(_actionName: string, inputState: any, _inputObject: any)
			if inputState ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Pass
			end

			dispatchTrackedKey(keyCode, "ContextActionService", nil)
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.ContextActionPriority.High.Value,
		keyCode
	)
end

debugLog("Input hook active (P=worksite effect debug state, L=drain 25 essence)")
