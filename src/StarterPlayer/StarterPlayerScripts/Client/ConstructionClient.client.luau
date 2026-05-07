--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local ConstructionConfig = require(Config:WaitForChild("ConstructionConfig"))

local REMOTES_FOLDER_NAME = "Remotes"
local BUILD_REMOTE_NAME = "ConstructionBuildRequest"
local DEBUG_REQUEST_REMOTE_NAME = "ConstructionDebugStateRequest"
local DEBUG_RESPONSE_REMOTE_NAME = "ConstructionDebugStateResponse"

local BUILD_KEY = Enum.KeyCode.Unknown
local DEBUG_KEY = Enum.KeyCode.M
local BUILD_KEY_ENABLED = false

local localPlayer = Players.LocalPlayer

local function debugLog(message: string)
	print(string.format("[ConstructionClient] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[ConstructionClient] %s", message))
end

debugLog("Booting LocalScript")

local remotesFolder = ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME)

local buildRemote: RemoteEvent? = nil
local debugRequestRemote: RemoteEvent? = nil
local debugResponseRemote: RemoteEvent? = nil

local function resolveRemote(remoteName: string, timeoutSeconds: number): RemoteEvent?
	local existing = remotesFolder:FindFirstChild(remoteName)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	debugLog(string.format("Resolving remote %s timeout=%ds", remoteName, timeoutSeconds))
	local resolved = remotesFolder:WaitForChild(remoteName, timeoutSeconds)
	if not resolved or not resolved:IsA("RemoteEvent") then
		debugWarn(string.format("Remote unavailable or invalid remoteName=%s", remoteName))
		return nil
	end

	debugLog(string.format("Resolved remote %s", remoteName))
	return resolved
end

local function ensureBuildRemote(timeoutSeconds: number): boolean
	buildRemote = buildRemote or resolveRemote(BUILD_REMOTE_NAME, timeoutSeconds)
	return buildRemote ~= nil
end

local function ensureDebugRemotes(timeoutSeconds: number): boolean
	debugRequestRemote = debugRequestRemote or resolveRemote(DEBUG_REQUEST_REMOTE_NAME, timeoutSeconds)
	debugResponseRemote = debugResponseRemote or resolveRemote(DEBUG_RESPONSE_REMOTE_NAME, timeoutSeconds)
	return debugRequestRemote ~= nil and debugResponseRemote ~= nil
end

ensureBuildRemote(10)
ensureDebugRemotes(10)

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

local function shouldTrackConstructionPart(part: BasePart): boolean
	return string.match(part.Name, "^" .. ConstructionConfig.ConstructionSiteNamePrefix) ~= nil
end

local function getNearestConstructionSiteId(): string?
	local localRoot = getHumanoidRootPart(localPlayer.Character)
	if not localRoot then
		return nil
	end

	local mapRoot = Workspace:FindFirstChild("Map")
	if not mapRoot then
		return nil
	end

	local bestId: string? = nil
	local bestDistance = math.huge
	for _, descendant in mapRoot:GetDescendants() do
		if descendant:IsA("BasePart") and shouldTrackConstructionPart(descendant) then
			local distance = (descendant.Position - localRoot.Position).Magnitude
			if distance <= ConstructionConfig.InteractionRangeStuds and distance < bestDistance then
				bestDistance = distance
				bestId = descendant.Name
			end
		end
	end

	return bestId
end

local hasBoundDebugResponse = false

local function bindDebugResponseIfReady()
	if hasBoundDebugResponse then
		return
	end

	if not ensureDebugRemotes(1) then
		return
	end

	local resolvedDebugResponseRemote = debugResponseRemote :: RemoteEvent
	resolvedDebugResponseRemote.OnClientEvent:Connect(function(payload)
		if type(payload) == "table" and payload.siteId ~= nil then
			debugLog(string.format(
				"Construction debug id=%s built=%s buildCount=%s lastBuiltBy=%s costWood=%s costStone=%s woodProduced=%s woodInTransit=%s woodStored=%s woodUsable=%s stoneProduced=%s stoneInTransit=%s stoneStored=%s stoneUsable=%s",
				tostring(payload.siteId),
				tostring(payload.isBuilt),
				tostring(payload.buildCount),
				tostring(payload.lastBuiltByUserId),
				tostring(payload.costWood),
				tostring(payload.costStone),
				tostring(payload.woodProduced),
				tostring(payload.woodInTransit),
				tostring(payload.woodStored),
				tostring(payload.woodUsable),
				tostring(payload.stoneProduced),
				tostring(payload.stoneInTransit),
				tostring(payload.stoneStored),
				tostring(payload.stoneUsable)
			))
			return
		end

		if type(payload) == "table" then
			for _, item in payload do
				if type(item) == "table" then
					debugLog(string.format(
						"Construction snapshot id=%s built=%s buildCount=%s lastBuiltBy=%s costWood=%s costStone=%s woodProduced=%s woodInTransit=%s woodStored=%s woodUsable=%s stoneProduced=%s stoneInTransit=%s stoneStored=%s stoneUsable=%s",
						tostring(item.siteId),
						tostring(item.isBuilt),
						tostring(item.buildCount),
						tostring(item.lastBuiltByUserId),
						tostring(item.costWood),
						tostring(item.costStone),
						tostring(item.woodProduced),
						tostring(item.woodInTransit),
						tostring(item.woodStored),
						tostring(item.woodUsable),
						tostring(item.stoneProduced),
						tostring(item.stoneInTransit),
						tostring(item.stoneStored),
						tostring(item.stoneUsable)
					))
				end
			end
			return
		end

		debugWarn("Received malformed construction debug response payload")
	end)

	hasBoundDebugResponse = true
	debugLog("Bound ConstructionDebugStateResponse listener")
end

bindDebugResponseIfReady()

local function requestBuild()
	if not ensureBuildRemote(1) then
		debugWarn("Build request blocked: build remote unavailable")
		return
	end

	local siteId = getNearestConstructionSiteId()
	if not siteId then
		debugWarn("No eligible construction site in range")
		return
	end

	debugLog(string.format("Build key accepted siteId=%s", siteId))
	local resolvedBuildRemote = buildRemote :: RemoteEvent
	resolvedBuildRemote:FireServer(siteId)
	debugLog(string.format("Sent ConstructionBuildRequest siteId=%s", siteId))
end

local function requestDebugState()
	bindDebugResponseIfReady()

	if not ensureDebugRemotes(1) then
		debugWarn("Debug request blocked: debug remotes unavailable")
		return
	end

	local siteId = getNearestConstructionSiteId()
	local resolvedDebugRequestRemote = debugRequestRemote :: RemoteEvent
	resolvedDebugRequestRemote:FireServer(siteId)
	debugLog(string.format("Debug key accepted nearestSiteId=%s", tostring(siteId)))
	debugLog(string.format("Using debug request remote=%s", DEBUG_REQUEST_REMOTE_NAME))
	if siteId then
		debugLog(string.format("Sent ConstructionDebugStateRequest siteId=%s", siteId))
	else
		debugLog("Sent ConstructionDebugStateRequest snapshot")
	end
end

UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessedEvent: boolean)
	local isBuildKey = BUILD_KEY_ENABLED and input.KeyCode == BUILD_KEY
	local isDebugKey = input.KeyCode == DEBUG_KEY
	local isConstructionKey = isBuildKey or isDebugKey

	if isConstructionKey then
		debugLog(string.format("Detected key=%s gameProcessed=%s", tostring(input.KeyCode), tostring(gameProcessedEvent)))
	end

	if gameProcessedEvent and not isConstructionKey then
		return
	end

	if gameProcessedEvent and isConstructionKey then
		debugWarn("Construction key received with gameProcessedEvent=true; continuing anyway")
	end

	if isBuildKey then
		requestBuild()
	elseif isDebugKey then
		requestDebugState()
	end
end)

debugLog("Input hook active (M=Request Construction Debug State)")
