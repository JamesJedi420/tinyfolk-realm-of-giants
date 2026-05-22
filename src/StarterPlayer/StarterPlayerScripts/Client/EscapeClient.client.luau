--!nocheck
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local EscapeConfig = require(Config:WaitForChild("EscapeConfig"))

local REMOTES_FOLDER_NAME = "Remotes"
local ESCAPE_ATTEMPT_REMOTE_NAME = "EscapeAttemptRequest"
local ESCAPE_DEBUG_REQUEST_REMOTE_NAME = "EscapeDebugStateRequest"
local ESCAPE_DEBUG_RESPONSE_REMOTE_NAME = "EscapeDebugStateResponse"

local ATTEMPT_ESCAPE_KEY = Enum.KeyCode.Unknown
local DEBUG_STATE_KEY = Enum.KeyCode.Y
local ATTEMPT_ESCAPE_KEY_ENABLED = false

local localPlayer = Players.LocalPlayer

local function debugLog(message: string)
	print(string.format("[EscapeClient] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[EscapeClient] %s", message))
end

local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME)
local escapeAttemptRemote = remotesFolder:WaitForChild(ESCAPE_ATTEMPT_REMOTE_NAME) :: RemoteEvent
local escapeDebugRequestRemote = remotesFolder:WaitForChild(ESCAPE_DEBUG_REQUEST_REMOTE_NAME) :: RemoteEvent
local escapeDebugResponseRemote = remotesFolder:WaitForChild(ESCAPE_DEBUG_RESPONSE_REMOTE_NAME) :: RemoteEvent

local function getHumanoidRootPart(character: Model?): BasePart?
	if not character then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end

	return nil
end

local function shouldTrackEscapeRoutePart(part: BasePart): boolean
	return string.match(part.Name, "^" .. EscapeConfig.EscapeRouteNamePrefix) ~= nil
end

local function getNearestEscapeRouteId(): string?
	local localRoot = getHumanoidRootPart(localPlayer.Character)
	if not localRoot then
		return nil
	end

	local routesRoot = Workspace:FindFirstChild("Map")
	if not routesRoot then
		return nil
	end

	local bestRouteId: string? = nil
	local bestDistance = math.huge

	for _, descendant in routesRoot:GetDescendants() do
		if descendant:IsA("BasePart") and shouldTrackEscapeRoutePart(descendant) then
			local distance = (descendant.Position - localRoot.Position).Magnitude
			if distance <= EscapeConfig.TriggerRadiusStuds and distance < bestDistance then
				bestDistance = distance
				bestRouteId = descendant.Name
			end
		end
	end

	return bestRouteId
end

local function requestEscapeAttempt()
	local routeId = getNearestEscapeRouteId()
	if not routeId then
		debugWarn("No eligible escape route in range")
		return
	end

	escapeAttemptRemote:FireServer(routeId)
	debugLog(string.format("Sent EscapeAttemptRequest routeId=%s", routeId))
end

local function requestDebugState()
	local routeId = getNearestEscapeRouteId()
	escapeDebugRequestRemote:FireServer(routeId)
	if routeId then
		debugLog(string.format("Sent EscapeDebugStateRequest routeId=%s", routeId))
	else
		debugLog("Sent EscapeDebugStateRequest snapshot")
	end
end

escapeDebugResponseRemote.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		debugWarn("Received malformed escape debug payload")
		return
	end

	if payload.routeId ~= nil then
		debugLog(
			string.format(
				"Escape debug routeId=%s isEnabled=%s successfulEscapes=%s escaped=%s",
				tostring(payload.routeId),
				tostring(payload.isEnabled),
				tostring(payload.successfulEscapes),
				tostring(payload.escaped)
			)
		)
		return
	end

	local routes = payload.routes
	if type(routes) == "table" then
		for _, route in routes do
			if type(route) == "table" then
				debugLog(
					string.format(
						"Escape debug snapshot routeId=%s isEnabled=%s successfulEscapes=%s",
						tostring(route.routeId),
						tostring(route.isEnabled),
						tostring(route.successfulEscapes)
					)
				)
			end
		end
		debugLog(string.format("Escape debug snapshot escaped=%s", tostring(payload.escaped)))
		return
	end

	debugWarn("Received malformed escape debug snapshot")
end)

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
	if gameProcessedEvent then
		return
	end

	if ATTEMPT_ESCAPE_KEY_ENABLED and input.KeyCode == ATTEMPT_ESCAPE_KEY then
		requestEscapeAttempt()
	elseif input.KeyCode == DEBUG_STATE_KEY then
		requestDebugState()
	end
end)

debugLog("Input hook active (Y=Request Escape Debug State)")
