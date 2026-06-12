--!nocheck

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Physics = Shared:WaitForChild("Physics")

local function requireSiblingModule(moduleName: string): any
	local parent = script.Parent
	for _, child in parent:GetChildren() do
		if child.Name == moduleName and child:IsA("ModuleScript") then
			return require(child)
		end
	end
	error(string.format("ModuleScript %s not found under %s", moduleName, parent:GetFullName()))
end

local PhysicsOwnershipService = if script ~= nil and script.Parent ~= nil
	then requireSiblingModule("PhysicsOwnershipService")
	else (require :: any)("./PhysicsOwnershipService")
local GameplayPhysicsOwnershipPolicy = require(Physics:WaitForChild("GameplayPhysicsOwnershipPolicy"))

local MAP_ROOT_NAME = "Map"
local ROLE_ATTRIBUTE = "Role"
local CAPTURE_ACTIVE_ATTRIBUTE = "CaptureActive"
local CARRIED_STATE_ATTRIBUTE = "CarriedState"
local HELD_TARGET_ATTRIBUTE = "HeldTargetUserId"
local HELD_BY_ATTRIBUTE = "HeldByUserId"
local REMOTES_FOLDER_NAME = "Remotes"
local DEBUG_REQUEST_REMOTE_NAME = "PhysicsOwnershipDebugStateRequest"
local DEBUG_RESPONSE_REMOTE_NAME = "PhysicsOwnershipDebugStateResponse"

local serviceStarted = false
local enforceAccumulator = 0
local ENFORCE_INTERVAL_SECONDS = 1

local function debugLog(message: string)
	print(string.format("[PhysicsOwnershipService] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[PhysicsOwnershipService] %s", message))
end

local function ensureRemotesFolder(): any
	local existing = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if existing ~= nil then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = REMOTES_FOLDER_NAME
	folder.Parent = ReplicatedStorage
	return folder
end

local function ensureRemoteEvent(parent: any, remoteName: string): any
	local existing = parent:FindFirstChild(remoteName)
	if existing ~= nil then
		return existing
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = remoteName
	remote.Parent = parent
	return remote
end

local function bindPlayerRefresh(player: any)
	local function refresh()
		PhysicsOwnershipService.RefreshPlayerCharacter(player)
	end

	player.CharacterAdded:Connect(refresh)
	player:GetAttributeChangedSignal(ROLE_ATTRIBUTE):Connect(refresh)
	player:GetAttributeChangedSignal(CAPTURE_ACTIVE_ATTRIBUTE):Connect(refresh)
	player:GetAttributeChangedSignal(CARRIED_STATE_ATTRIBUTE):Connect(refresh)
	player:GetAttributeChangedSignal(HELD_TARGET_ATTRIBUTE):Connect(refresh)
	player:GetAttributeChangedSignal(HELD_BY_ATTRIBUTE):Connect(refresh)

	if player.Character ~= nil then
		refresh()
	end
end

local function assignAuthoredWorldParts()
	local mapRoot = Workspace:FindFirstChild(MAP_ROOT_NAME)
	if mapRoot == nil then
		debugWarn("Workspace.Map missing; skipping world physics ownership assignment")
		return
	end

	local assignedCount = PhysicsOwnershipService.AssignWorldPartsUnderRoot(mapRoot)
	debugLog(string.format("Assigned gameplay physics ownership to %d map parts", assignedCount))
end

local function refreshServerCriticalPlayers()
	for _, player in Players:GetPlayers() do
		if PhysicsOwnershipService.RequiresServerOwnershipForPlayer(player) then
			PhysicsOwnershipService.RefreshPlayerCharacter(player)
		end
	end
end

local function snapshotForPlayer(player: any): any
	return {
		userId = player.UserId,
		role = player:GetAttribute(ROLE_ATTRIBUTE),
		captureActive = player:GetAttribute(CAPTURE_ACTIVE_ATTRIBUTE),
		carriedState = player:GetAttribute(CARRIED_STATE_ATTRIBUTE),
		heldTargetUserId = player:GetAttribute(HELD_TARGET_ATTRIBUTE),
		heldByUserId = player:GetAttribute(HELD_BY_ATTRIBUTE),
		characterAssembly = PhysicsOwnershipService.GetCharacterAssemblyForPlayer(player),
		characterTier = PhysicsOwnershipService.GetCharacterTierForPlayer(player),
		requiresServerOwnership = PhysicsOwnershipService.RequiresServerOwnershipForPlayer(player),
	}
end

local function rejectDebug(player: any, reason: string)
	debugWarn(string.format("Rejected PhysicsOwnershipDebugStateRequest userId=%d reason=%s", player.UserId, reason))
end

local function startService(): (boolean, string?)
	if serviceStarted then
		return true, nil
	end

	local valid, reason = GameplayPhysicsOwnershipPolicy.ValidateConfig()
	if not valid then
		debugWarn(string.format("Policy validation failed reason=%s", tostring(reason)))
		return false, reason
	end

	assignAuthoredWorldParts()

	Players.PlayerAdded:Connect(bindPlayerRefresh)
	for _, player in Players:GetPlayers() do
		bindPlayerRefresh(player)
	end

	RunService.Heartbeat:Connect(function(deltaTime: number)
		enforceAccumulator += deltaTime
		if enforceAccumulator < ENFORCE_INTERVAL_SECONDS then
			return
		end
		enforceAccumulator = 0
		refreshServerCriticalPlayers()
	end)

	local remotesFolder = ensureRemotesFolder()
	local debugRequestRemote = ensureRemoteEvent(remotesFolder, DEBUG_REQUEST_REMOTE_NAME)
	local debugResponseRemote = ensureRemoteEvent(remotesFolder, DEBUG_RESPONSE_REMOTE_NAME)

	debugRequestRemote.OnServerEvent:Connect(function(player: any, payload: unknown)
		if payload ~= nil and type(payload) ~= "number" and type(payload) ~= "string" then
			rejectDebug(player, "malformed_payload")
			return
		end

		if payload == nil then
			local snapshot = {}
			for _, otherPlayer in Players:GetPlayers() do
				table.insert(snapshot, snapshotForPlayer(otherPlayer))
			end
			debugResponseRemote:FireClient(player, {
				players = snapshot,
				diagnostics = PhysicsOwnershipService.GetDiagnostics(),
			})
			return
		end

		local requestedUserId = if type(payload) == "number" then payload else tonumber(payload)
		if requestedUserId == nil then
			rejectDebug(player, "invalid_user_id")
			return
		end

		local targetPlayer: any = nil
		for _, otherPlayer in Players:GetPlayers() do
			if otherPlayer.UserId == requestedUserId then
				targetPlayer = otherPlayer
				break
			end
		end

		if targetPlayer == nil then
			rejectDebug(player, "player_not_found")
			return
		end

		debugResponseRemote:FireClient(player, {
			player = snapshotForPlayer(targetPlayer),
			diagnostics = PhysicsOwnershipService.GetDiagnostics(),
		})
	end)

	serviceStarted = true
	debugLog("Physics ownership service started")
	return true, nil
end

local startOk, startReason = startService()
if not startOk then
	debugWarn(string.format("PhysicsOwnershipService bootstrap deferred reason=%s", tostring(startReason)))
end

local globalEnv: any = getfenv()
globalEnv._PhysicsOwnershipService_QueryAPI = {
	RefreshPlayerCharacter = function(player: any)
		PhysicsOwnershipService.RefreshPlayerCharacter(player)
	end,
	AssignWorldPartsUnderRoot = function(root: any): number
		return PhysicsOwnershipService.AssignWorldPartsUnderRoot(root)
	end,
	GetCharacterAssemblyForPlayer = function(player: any): string
		return PhysicsOwnershipService.GetCharacterAssemblyForPlayer(player)
	end,
	GetCharacterTierForPlayer = function(player: any): string
		return PhysicsOwnershipService.GetCharacterTierForPlayer(player)
	end,
	RequiresServerOwnershipForPlayer = function(player: any): boolean
		return PhysicsOwnershipService.RequiresServerOwnershipForPlayer(player)
	end,
	GetDiagnostics = function(): any
		return PhysicsOwnershipService.GetDiagnostics()
	end,
	ApplyOwnershipToPart = function(part: any, tier: string, ownerPlayer: any?, reason: string, assemblyKind: string?)
		return PhysicsOwnershipService.ApplyOwnershipToPart(part, tier, ownerPlayer, reason, assemblyKind)
	end,
}
rawset(_G, "_PhysicsOwnershipService_QueryAPI", globalEnv._PhysicsOwnershipService_QueryAPI)
