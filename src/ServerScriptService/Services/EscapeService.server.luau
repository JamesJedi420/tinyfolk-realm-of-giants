--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local EscapeConfig = require(Config:WaitForChild("EscapeConfig"))
local TinyfolkMovementTraitService = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("TinyfolkMovementTraitService"))
	else require("./TinyfolkMovementTraitService")

local REMOTES_FOLDER_NAME = "Remotes"
local ESCAPE_ATTEMPT_REMOTE_NAME = "EscapeAttemptRequest"
local ESCAPE_DEBUG_REQUEST_REMOTE_NAME = "EscapeDebugStateRequest"
local ESCAPE_DEBUG_RESPONSE_REMOTE_NAME = "EscapeDebugStateResponse"

local ESCAPED_ATTRIBUTE = "Escaped"
local ROUTE_ENABLED_ATTRIBUTE = "IsEnabled"
local ROUTE_SUCCESSFUL_ESCAPES_ATTRIBUTE = "SuccessfulEscapes"

local ESCAPE_ROUTES_FOLDER_PATH = {"Map", "EscapeRoutes"}

local escapeRouteById: {[string]: BasePart} = {}
local escapedTinyfolkByUserId: {[number]: boolean} = {}
local lastRequestAtByUserId: {[number]: number} = {}

local function debugLog(message: string)
	print(string.format("[EscapeService] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[EscapeService] %s", message))
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

	return (os.clock() - last) < EscapeConfig.RequestCooldownSeconds
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

local function isTinyfolk(player: Player): boolean
	return player:GetAttribute("Role") == RoleConfig.Roles.Tinyfolk
end

local function findEscapeRoutesRoot(): Instance?
	local current: Instance = Workspace
	for _, childName in ESCAPE_ROUTES_FOLDER_PATH do
		local nextNode = current:FindFirstChild(childName)
		if not nextNode then
			return nil
		end
		current = nextNode
	end

	return current
end

local function shouldTrackEscapeRoutePart(part: BasePart): boolean
	return string.match(part.Name, "^" .. EscapeConfig.EscapeRouteNamePrefix) ~= nil
end

local function registerEscapeRoutePart(part: BasePart)
	local routeId = part.Name
	if escapeRouteById[routeId] then
		debugWarn(string.format("Duplicate escape route id ignored: %s", routeId))
		return
	end

	escapeRouteById[routeId] = part
	part:SetAttribute(ROUTE_ENABLED_ATTRIBUTE, true)
	part:SetAttribute(ROUTE_SUCCESSFUL_ESCAPES_ATTRIBUTE, 0)

	debugLog(string.format("Registered escape route id=%s", routeId))
end

local function registerEscapeRoutesFromWorkspace()
	local routesRoot = findEscapeRoutesRoot()
	if not routesRoot then
		debugWarn("No escape route root found at Workspace.Map.EscapeRoutes")
		return
	end

	for _, descendant in routesRoot:GetDescendants() do
		if descendant:IsA("BasePart") and shouldTrackEscapeRoutePart(descendant) then
			registerEscapeRoutePart(descendant)
		end
	end

	if next(escapeRouteById) == nil then
		debugWarn("No escape routes registered under Workspace.Map.EscapeRoutes")
	end
end

local function getTinyfolkReturnCFrame(routePart: BasePart): CFrame
	local current: Instance = Workspace
	for _, childName in EscapeConfig.TinyfolkWorldFolderPath do
		local nextNode = current:FindFirstChild(childName)
		if not nextNode then
			debugWarn(string.format("Missing Tinyfolk return path segment: %s", childName))
			return routePart.CFrame + Vector3.new(0, 3, -20)
		end
		current = nextNode
	end

	for _, descendant in current:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Name == EscapeConfig.TinyfolkReturnPointName then
			debugLog(string.format("Resolved Tinyfolk return point at %s", descendant:GetFullName()))
			return descendant.CFrame + Vector3.new(0, 3, 0)
		end
	end

	debugWarn(string.format("Missing Tinyfolk return point: %s", EscapeConfig.TinyfolkReturnPointName))
	return routePart.CFrame + Vector3.new(0, 3, -20)
end

local function movePlayerToReturnPoint(player: Player, routePart: BasePart)
	local character = player.Character
	if not character then
		debugWarn(string.format("Escape success transition skipped userId=%d reason=missing_character", player.UserId))
		return
	end

	local returnCFrame = getTinyfolkReturnCFrame(routePart)
	character:PivotTo(returnCFrame)
	local position = returnCFrame.Position
	debugLog(string.format(
		"Escape success transition userId=%d moved_to_return_point position=(%.1f, %.1f, %.1f)",
		player.UserId,
		position.X,
		position.Y,
		position.Z
	))
end

local function rejectEscapeAttempt(player: Player, reason: string)
	debugWarn(string.format("Rejected EscapeAttemptRequest userId=%d reason=%s", player.UserId, reason))
end

local function rejectDebugRequest(player: Player, reason: string)
	debugWarn(string.format("Rejected EscapeDebugStateRequest userId=%d reason=%s", player.UserId, reason))
end

local remotesFolder = ensureRemotesFolder()
local escapeAttemptRemote = ensureRemoteEvent(remotesFolder, ESCAPE_ATTEMPT_REMOTE_NAME)
local escapeDebugRequestRemote = ensureRemoteEvent(remotesFolder, ESCAPE_DEBUG_REQUEST_REMOTE_NAME)
local escapeDebugResponseRemote = ensureRemoteEvent(remotesFolder, ESCAPE_DEBUG_RESPONSE_REMOTE_NAME)

registerEscapeRoutesFromWorkspace()

escapeAttemptRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	if isCoolingDown(player.UserId) then
		rejectEscapeAttempt(player, "request_cooldown")
		return
	end

	markRequest(player.UserId)

	if type(payload) ~= "string" then
		rejectEscapeAttempt(player, "malformed_payload")
		return
	end

	local routeId = payload
	local routePart = escapeRouteById[routeId]
	if not routePart then
		rejectEscapeAttempt(player, "route_not_found")
		return
	end

	if not isTinyfolk(player) then
		rejectEscapeAttempt(player, "requester_not_tinyfolk")
		return
	end

	if escapedTinyfolkByUserId[player.UserId] then
		rejectEscapeAttempt(player, "already_escaped")
		return
	end

	if not isPlayerAlive(player) then
		rejectEscapeAttempt(player, "player_not_alive")
		return
	end

	local routeEnabled = routePart:GetAttribute(ROUTE_ENABLED_ATTRIBUTE)
	if routeEnabled == false then
		rejectEscapeAttempt(player, "route_disabled")
		return
	end

	local root = getHumanoidRootPart(player)
	if not root then
		rejectEscapeAttempt(player, "humanoid_root_missing")
		return
	end

	local distance = (routePart.Position - root.Position).Magnitude
	if distance > EscapeConfig.TriggerRadiusStuds then
		rejectEscapeAttempt(player, string.format("out_of_range distance=%.2f max=%.2f", distance, EscapeConfig.TriggerRadiusStuds))
		return
	end

	escapedTinyfolkByUserId[player.UserId] = true
	player:SetAttribute(ESCAPED_ATTRIBUTE, true)

	local successfulEscapes = routePart:GetAttribute(ROUTE_SUCCESSFUL_ESCAPES_ATTRIBUTE)
	if type(successfulEscapes) ~= "number" then
		successfulEscapes = 0
	end
	routePart:SetAttribute(ROUTE_SUCCESSFUL_ESCAPES_ATTRIBUTE, successfulEscapes + 1)

	movePlayerToReturnPoint(player, routePart)
	TinyfolkMovementTraitService.OnValidRouteCrossing(player, routeId)

	debugLog(string.format("Accepted EscapeAttemptRequest userId=%d routeId=%s distance=%.2f", player.UserId, routeId, distance))
end)

escapeDebugRequestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	if payload ~= nil and type(payload) ~= "string" then
		rejectDebugRequest(player, "malformed_payload")
		return
	end

	local requestedRouteId = payload :: string?
	if requestedRouteId then
		local routePart = escapeRouteById[requestedRouteId]
		if not routePart then
			rejectDebugRequest(player, "route_not_found")
			return
		end

		escapeDebugResponseRemote:FireClient(player, {
			routeId = requestedRouteId,
			isEnabled = routePart:GetAttribute(ROUTE_ENABLED_ATTRIBUTE),
			successfulEscapes = routePart:GetAttribute(ROUTE_SUCCESSFUL_ESCAPES_ATTRIBUTE),
			escaped = escapedTinyfolkByUserId[player.UserId] == true,
		})
		debugLog(string.format("Sent escape debug state userId=%d routeId=%s", player.UserId, requestedRouteId))
		return
	end

	local snapshot = {}
	for routeId, routePart in escapeRouteById do
		table.insert(snapshot, {
			routeId = routeId,
			isEnabled = routePart:GetAttribute(ROUTE_ENABLED_ATTRIBUTE),
			successfulEscapes = routePart:GetAttribute(ROUTE_SUCCESSFUL_ESCAPES_ATTRIBUTE),
		})
	end

	escapeDebugResponseRemote:FireClient(player, {
		routes = snapshot,
		escaped = escapedTinyfolkByUserId[player.UserId] == true,
	})
	debugLog(string.format("Sent escape debug snapshot userId=%d routeCount=%d", player.UserId, #snapshot))
end)

local function setupPlayer(player: Player)
	escapedTinyfolkByUserId[player.UserId] = false
	player:SetAttribute(ESCAPED_ATTRIBUTE, false)

	player.CharacterAdded:Connect(function()
		escapedTinyfolkByUserId[player.UserId] = false
		player:SetAttribute(ESCAPED_ATTRIBUTE, false)
		debugLog(string.format("Reset escaped state on respawn userId=%d", player.UserId))
	end)

	player:GetAttributeChangedSignal("Role"):Connect(function()
		escapedTinyfolkByUserId[player.UserId] = false
		player:SetAttribute(ESCAPED_ATTRIBUTE, false)
		debugLog(string.format("Reset escaped state on role change userId=%d", player.UserId))
	end)
end

Players.PlayerAdded:Connect(setupPlayer)

for _, player in Players:GetPlayers() do
	setupPlayer(player)
end

Players.PlayerRemoving:Connect(function(player: Player)
	lastRequestAtByUserId[player.UserId] = nil
	escapedTinyfolkByUserId[player.UserId] = nil
end)

debugLog("EscapeService initialized")