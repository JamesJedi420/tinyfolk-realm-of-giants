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
local SELECT_REMOTE_NAME = "UpgradeBoardSelectRequest"
local SELECT_RESULT_REMOTE_NAME = "UpgradeBoardSelectResult"
local DEBUG_REQUEST_REMOTE_NAME = "UpgradeBoardDebugStateRequest"
local DEBUG_RESPONSE_REMOTE_NAME = "UpgradeBoardDebugStateResponse"

local _SELECT_UPGRADE_ONE_KEY = Enum.KeyCode.Unknown
local _SELECT_UPGRADE_TWO_KEY = Enum.KeyCode.Unknown
local DEBUG_KEY = Enum.KeyCode.P
local DEBUG_ESSENCE_DRAIN_KEY = Enum.KeyCode.L

local DEBUG_ESSENCE_DRAIN_REMOTE_NAME = "UpgradeBoardDebugEssenceDrain"

local localPlayer = Players.LocalPlayer
type KeyCodeValue = any

type KeyBinding = {
	actionName: string,
	optionIndex: number?,
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

debugLog("Booting LocalScript")

local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME)
local selectRemote = remotesFolder:WaitForChild(SELECT_REMOTE_NAME) :: RemoteEvent
local selectResultRemote = remotesFolder:WaitForChild(SELECT_RESULT_REMOTE_NAME) :: RemoteEvent
local debugRequestRemote = remotesFolder:WaitForChild(DEBUG_REQUEST_REMOTE_NAME) :: RemoteEvent
local debugResponseRemote = remotesFolder:WaitForChild(DEBUG_RESPONSE_REMOTE_NAME) :: RemoteEvent
local debugEssenceDrainRemote = remotesFolder:WaitForChild(DEBUG_ESSENCE_DRAIN_REMOTE_NAME) :: RemoteEvent

debugLog(
	string.format(
		"Remote wiring ready select=%s debugRequest=%s debugResponse=%s",
		SELECT_REMOTE_NAME,
		DEBUG_REQUEST_REMOTE_NAME,
		DEBUG_RESPONSE_REMOTE_NAME
	)
)

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

local function requestSelectionByOptionIndex(optionIndex: number, triggerKey: any)
	local option = UpgradeBoardConfig.UpgradeOptions[optionIndex]
	if not option then
		debugWarn(string.format("Key=%s option index out of range: %d", tostring(triggerKey), optionIndex))
		return
	end

	local boardId = getNearestBoardId()
	if not boardId then
		debugWarn(string.format("Key=%s no eligible giant upgrade board in range", tostring(triggerKey)))
		return
	end

	selectRemote:FireServer({
		boardId = boardId,
		upgradeId = option.id,
	})
	debugLog(
		string.format(
			"Key=%s sent UpgradeBoardSelectRequest optionIndex=%d boardId=%s upgradeId=%s",
			tostring(triggerKey),
			optionIndex,
			boardId,
			option.id
		)
	)
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

local function isTrackedKey(keyCode: any): boolean
	return KEY_BINDINGS[keyCode] ~= nil
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

	if binding.optionIndex ~= nil then
		debugLog(
			string.format(
				"Dispatch key=%s source=%s action=%s optionIndex=%d gameProcessed=%s",
				tostring(keyCode),
				source,
				binding.actionName,
				binding.optionIndex,
				tostring(gameProcessedEvent)
			)
		)
		requestSelectionByOptionIndex(binding.optionIndex, keyCode)
		return
	end

	if binding.isDebugRequest == true then
		debugLog(
			string.format(
				"Dispatch key=%s source=%s action=%s gameProcessed=%s",
				tostring(keyCode),
				source,
				binding.actionName,
				tostring(gameProcessedEvent)
			)
		)
		requestDebugState(keyCode)
		return
	end

	if binding.isEssenceDrain == true then
		debugLog(
			string.format(
				"Dispatch key=%s source=%s action=%s gameProcessed=%s",
				tostring(keyCode),
				source,
				binding.actionName,
				tostring(gameProcessedEvent)
			)
		)
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
				"Upgrade debug boardId=%s isEnabled=%s selectionCount=%s selectedUpgradesCsv=%s resolvedMaxHealth=%s resolvedWalkSpeed=%s resolvedPowerBudget=%s resolvedMovementControl=%s giantEssenceTotal=%s giantEssenceGeneratedTotal=%s giantEssenceSpentTotal=%s giantEssenceLastSpentReason=%s giantEssenceLastSpentAmount=%s",
				tostring(payloadTable.boardId),
				tostring(payloadTable.isEnabled),
				tostring(payloadTable.selectionCount),
				tostring(payloadTable.selectedUpgradesCsv),
				tostring(payloadTable.resolvedMaxHealth),
				tostring(payloadTable.resolvedWalkSpeed),
				tostring(payloadTable.resolvedPowerBudget),
				tostring(payloadTable.resolvedMovementControl),
				tostring(payloadTable.giantEssenceTotal),
				tostring(payloadTable.giantEssenceGeneratedTotal),
				tostring(payloadTable.giantEssenceSpentTotal),
				tostring(payloadTable.giantEssenceLastSpentReason),
				tostring(payloadTable.giantEssenceLastSpentAmount)
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
				"Upgrade debug snapshot selectedUpgradesCsv=%s resolvedMaxHealth=%s resolvedWalkSpeed=%s resolvedPowerBudget=%s resolvedMovementControl=%s giantEssenceTotal=%s giantEssenceGeneratedTotal=%s giantEssenceSpentTotal=%s giantEssenceLastSpentReason=%s giantEssenceLastSpentAmount=%s",
				tostring(payloadTable.selectedUpgradesCsv),
				tostring(payloadTable.resolvedMaxHealth),
				tostring(payloadTable.resolvedWalkSpeed),
				tostring(payloadTable.resolvedPowerBudget),
				tostring(payloadTable.resolvedMovementControl),
				tostring(payloadTable.giantEssenceTotal),
				tostring(payloadTable.giantEssenceGeneratedTotal),
				tostring(payloadTable.giantEssenceSpentTotal),
				tostring(payloadTable.giantEssenceLastSpentReason),
				tostring(payloadTable.giantEssenceLastSpentAmount)
			)
		)
		return
	end

	debugWarn("Received malformed upgrade board debug snapshot")
end)

selectResultRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		debugWarn("Received malformed SelectResult payload")
		return
	end
	local payloadTable: any = payload

	if payloadTable.accepted == true then
		debugLog(
			string.format(
				"SelectResult accepted upgradeId=%s newStepCompleted=%s",
				tostring(payloadTable.upgradeId),
				tostring(payloadTable.newStepCompleted)
			)
		)
	else
		debugWarn(
			string.format(
				"SelectResult rejected upgradeId=%s reason=%s",
				tostring(payloadTable.upgradeId),
				tostring(payloadTable.reason)
			)
		)
	end
end)

debugLog("Debug response callback connected")

UserInputService.InputBegan:Connect(function(input: any, gameProcessedEvent: boolean)
	local keyCode = input.KeyCode
	if input.UserInputType == Enum.UserInputType.Keyboard and isTrackedKey(keyCode) then
		debugLog(
			string.format(
				"InputBegan receipt key=%s gameProcessed=%s focusedTextBox=%s",
				tostring(keyCode),
				tostring(gameProcessedEvent),
				tostring(UserInputService:GetFocusedTextBox() ~= nil)
			)
		)
	end

	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end

	if not isTrackedKey(keyCode) then
		return
	end
end)

for keyCode, binding in KEY_BINDINGS do
	ContextActionService:BindActionAtPriority(
		binding.actionName,
		function(_actionName: string, inputState: any, inputObject: any)
			if inputState ~= Enum.UserInputState.Begin then
				return Enum.ContextActionResult.Pass
			end

			debugLog(
				string.format("ContextAction begin action=%s key=%s", binding.actionName, tostring(inputObject.KeyCode))
			)
			dispatchTrackedKey(keyCode, "ContextActionService", nil)
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.ContextActionPriority.High.Value,
		keyCode
	)

	debugLog(
		string.format(
			"Bound action=%s key=%s priority=%d",
			binding.actionName,
			tostring(keyCode),
			Enum.ContextActionPriority.High.Value
		)
	)
end

debugLog("Input hook active (P=Request Upgrade Debug State, L=Drain 25 Essence)")
