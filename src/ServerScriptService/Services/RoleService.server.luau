--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local ProfilePersistenceGateway = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("ProfilePersistenceGateway"))
	else require("./ProfilePersistenceGateway")

local ROLE_ATTRIBUTE = "Role"
local SELECTED_ROLE_ATTRIBUTE = "SelectedRole"
local ROLE_LOCKED_ATTRIBUTE = "RoleLocked"
local REMOTES_FOLDER_NAME = "Remotes"
local ROLE_CHANGE_REMOTE_NAME = "RoleChangeRequest"
local ROLE_DEBUG_REQUEST_REMOTE_NAME = "RoleDebugStateRequest"
local ROLE_DEBUG_RESPONSE_REMOTE_NAME = "RoleDebugStateResponse"

local SPAWN_MAP_ROOT_NAME = "Map"
local SPAWN_CONTAINER_NAME = "Spawns"
local TINYFOLK_SPAWN_NAME = "TinyfolkSpawn"
local GIANT_SPAWN_NAME = "GiantSpawn"
local PROFILE_ROLE_PREFERENCE_KEY = "rolePreference"
local PROFILE_PREFERRED_ROLE_KEY = "preferredRole"

local lastRoleChangeAtByUserId: { [number]: number? } = {}

Players.CharacterAutoLoads = false

local function debugLog(message: string)
	print(string.format("[RoleService] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[RoleService] %s", message))
end

local function isValidRole(roleName: unknown): boolean
	if type(roleName) ~= "string" then
		return false
	end

	return roleName == RoleConfig.Roles.Giant or roleName == RoleConfig.Roles.Tinyfolk
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

local function ensureRoleChangeRemote(parentFolder: Folder): RemoteEvent
	local existing = parentFolder:FindFirstChild(ROLE_CHANGE_REMOTE_NAME)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = ROLE_CHANGE_REMOTE_NAME
	remote.Parent = parentFolder
	debugLog("Created ReplicatedStorage.Remotes.RoleChangeRequest")
	return remote
end

local function ensureRoleDebugResponseRemote(parentFolder: Folder): RemoteEvent
	local existing = parentFolder:FindFirstChild(ROLE_DEBUG_RESPONSE_REMOTE_NAME)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = ROLE_DEBUG_RESPONSE_REMOTE_NAME
	remote.Parent = parentFolder
	debugLog("Created ReplicatedStorage.Remotes.RoleDebugStateResponse")
	return remote
end

local function ensureRoleDebugRequestRemote(parentFolder: Folder): RemoteEvent
	local existing = parentFolder:FindFirstChild(ROLE_DEBUG_REQUEST_REMOTE_NAME)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end

	local remote = Instance.new("RemoteEvent")
	remote.Name = ROLE_DEBUG_REQUEST_REMOTE_NAME
	remote.Parent = parentFolder
	debugLog("Created ReplicatedStorage.Remotes.RoleDebugStateRequest")
	return remote
end

local function getRoleOrDefault(player: Player): string
	local roleValue = player:GetAttribute(ROLE_ATTRIBUTE)
	if isValidRole(roleValue) then
		return roleValue :: string
	end

	return RoleConfig.DefaultRole
end

local function getSelectedRole(player: Player): string?
	local selectedRole = player:GetAttribute(SELECTED_ROLE_ATTRIBUTE)
	if isValidRole(selectedRole) then
		return selectedRole :: string
	end

	return nil
end

local function isRoleLocked(player: Player): boolean
	return player:GetAttribute(ROLE_LOCKED_ATTRIBUTE) == true
end

local function applyScaleToCharacter(player: Player, character: Model)
	local role = getRoleOrDefault(player)
	local scale = RoleConfig.ScaleByRole[role]
	if type(scale) ~= "number" then
		debugWarn(string.format("Missing scale config for role '%s'", role))
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
	if humanoid == nil then
		debugWarn(string.format("Could not scale %s: Humanoid not found", player.Name))
		return
	end

	character:ScaleTo(scale)
	debugLog(string.format("Applied scale %.2f to %s as %s", scale, player.Name, role))
end

local function setPlayerRole(player: Player, roleName: string)
	player:SetAttribute(ROLE_ATTRIBUTE, roleName)
	debugLog(string.format("Set role for %s -> %s", player.Name, roleName))

	local character = player.Character
	if character then
		applyScaleToCharacter(player, character)
	end
end

local function ensureRoleForLockedPlayer(player: Player)
	if not isRoleLocked(player) then
		return
	end

	local selectedRole = getSelectedRole(player)
	if not selectedRole then
		debugWarn(string.format("Locked player missing selected role userId=%d", player.UserId))
		return
	end

	if player:GetAttribute(ROLE_ATTRIBUTE) ~= selectedRole then
		setPlayerRole(player, selectedRole)
	end
end

local function findSpawnForRole(roleName: string): SpawnLocation?
	local mapRoot = Workspace:FindFirstChild(SPAWN_MAP_ROOT_NAME)
	if not mapRoot then
		return nil
	end

	local spawnContainer = mapRoot:FindFirstChild(SPAWN_CONTAINER_NAME)
	if not spawnContainer then
		return nil
	end

	local spawnName = if roleName == RoleConfig.Roles.Giant then GIANT_SPAWN_NAME else TINYFOLK_SPAWN_NAME
	local spawnInstance = spawnContainer:FindFirstChild(spawnName)
	if spawnInstance and spawnInstance:IsA("SpawnLocation") then
		return spawnInstance
	end

	return nil
end

local function placeCharacterAtRoleSpawn(player: Player, character: Model)
	local roleName = getRoleOrDefault(player)
	local spawnLocation = findSpawnForRole(roleName)
	if spawnLocation == nil then
		debugLog(
			string.format("Missing role spawn for role=%s userId=%d; using default spawn", roleName, player.UserId)
		)
		return
	end

	local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 5)
	if not root or not root:IsA("BasePart") then
		debugWarn(string.format("Could not place %s at role spawn: HumanoidRootPart not found", player.Name))
		return
	end

	local targetCFrame = spawnLocation.CFrame + Vector3.new(0, 3, 0)
	character:PivotTo(targetCFrame)
	debugLog(string.format("Placed %s at %s", player.Name, spawnLocation.Name))
end

local function requestRespawnForLockedPlayer(player: Player, reason: string)
	if not isRoleLocked(player) then
		return
	end

	if Players:FindFirstChild(player.Name) ~= player then
		return
	end

	task.delay(Players.RespawnTime, function()
		if Players:FindFirstChild(player.Name) ~= player then
			return
		end

		local character = player.Character
		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid ~= nil and (humanoid :: Humanoid).Health > 0 then
				return
			end
		end

		debugLog(string.format("Respawning locked player userId=%d reason=%s", player.UserId, reason))
		player:LoadCharacterAsync()
	end)
end

local function isCoolingDown(userId: number): boolean
	local now = os.clock()
	local last = lastRoleChangeAtByUserId[userId]
	if last == nil then
		return false
	end

	return (now - last) < RoleConfig.RoleChangeCooldownSeconds
end

local function markRoleChange(userId: number)
	lastRoleChangeAtByUserId[userId] = os.clock()
end

local function readStoredPreferredRole(player: Player): string?
	local profileResult = ProfilePersistenceGateway.GetLoadedPlayerProfileData(player)
	if not profileResult.ok then
		debugWarn(
			string.format(
				"Role preference read failed userId=%d reason=%s",
				player.UserId,
				tostring(profileResult.reason)
			)
		)
		return nil
	end

	if type(profileResult.data) ~= "table" then
		return nil
	end

	local rolePreference = profileResult.data[PROFILE_ROLE_PREFERENCE_KEY]
	if type(rolePreference) ~= "table" then
		return nil
	end

	local preferredRole = rolePreference[PROFILE_PREFERRED_ROLE_KEY]
	if isValidRole(preferredRole) then
		return preferredRole :: string
	end

	if preferredRole ~= nil then
		debugWarn(
			string.format(
				"Role preference ignored userId=%d reason=invalid_preferred_role value=%s",
				player.UserId,
				tostring(preferredRole)
			)
		)
	end

	return nil
end

local function persistPreferredRole(player: Player, roleName: string)
	local updateResult = ProfilePersistenceGateway.UpdateLoadedPlayerProfileData(player, function(currentData: any): any
		local nextData = currentData
		if type(nextData[PROFILE_ROLE_PREFERENCE_KEY]) ~= "table" then
			nextData[PROFILE_ROLE_PREFERENCE_KEY] = {}
		end

		nextData[PROFILE_ROLE_PREFERENCE_KEY][PROFILE_PREFERRED_ROLE_KEY] = roleName
		return nextData
	end)

	if not updateResult.ok then
		debugWarn(
			string.format(
				"Role preference update failed userId=%d reason=%s",
				player.UserId,
				tostring(updateResult.reason)
			)
		)
	end
end

local remotesFolder = ensureRemotesFolder()
local roleChangeRemote = ensureRoleChangeRemote(remotesFolder)
local roleDebugRequestRemote = ensureRoleDebugRequestRemote(remotesFolder)
local roleDebugResponseRemote = ensureRoleDebugResponseRemote(remotesFolder)

local function snapshotForPlayer(player: Player)
	return {
		role = player:GetAttribute(ROLE_ATTRIBUTE),
		selectedRole = player:GetAttribute(SELECTED_ROLE_ATTRIBUTE),
		roleLocked = player:GetAttribute(ROLE_LOCKED_ATTRIBUTE),
		hasCharacter = player.Character ~= nil,
	}
end

local function initializePlayerRoleSelection(player: Player)
	if isRoleLocked(player) and getSelectedRole(player) ~= nil then
		ensureRoleForLockedPlayer(player)
		return
	end

	local preferredRole = readStoredPreferredRole(player)
	if preferredRole ~= nil then
		player:SetAttribute(SELECTED_ROLE_ATTRIBUTE, preferredRole)
		player:SetAttribute(ROLE_LOCKED_ATTRIBUTE, false)
		player:SetAttribute(ROLE_ATTRIBUTE, nil)
		debugLog(
			string.format(
				"Initialized pre-spawn role selection for %s with stored preference=%s",
				player.Name,
				preferredRole
			)
		)
		return
	end

	player:SetAttribute(SELECTED_ROLE_ATTRIBUTE, nil)
	player:SetAttribute(ROLE_LOCKED_ATTRIBUTE, false)
	player:SetAttribute(ROLE_ATTRIBUTE, nil)
	debugLog(string.format("Initialized pre-spawn role selection for %s", player.Name))
end

local function setupPlayer(player: Player)
	initializePlayerRoleSelection(player)

	player.CharacterAdded:Connect(function(character)
		ensureRoleForLockedPlayer(player)
		applyScaleToCharacter(player, character)
		placeCharacterAtRoleSpawn(player, character)

		local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 5)
		if humanoid == nil then
			debugWarn(string.format("Could not bind respawn handler for %s: Humanoid not found", player.Name))
			return
		end

		humanoid.Died:Connect(function()
			requestRespawnForLockedPlayer(player, "humanoid_died")
		end)
	end)
end

Players.PlayerAdded:Connect(function(player)
	setupPlayer(player)
end)

for _, player in Players:GetPlayers() do
	setupPlayer(player)
end

Players.PlayerRemoving:Connect(function(player)
	lastRoleChangeAtByUserId[player.UserId] = nil
end)

roleChangeRemote.OnServerEvent:Connect(function(player, requestedRole: unknown)
	if isRoleLocked(player) then
		debugWarn(string.format("Rejected role select from %s reason=role_locked", player.Name))
		return
	end

	if not isValidRole(requestedRole) then
		debugWarn(string.format("Rejected invalid role payload from %s", player.Name))
		return
	end

	if isCoolingDown(player.UserId) then
		debugWarn(string.format("Rejected role change from %s due to cooldown", player.Name))
		return
	end

	local roleName = requestedRole :: string
	markRoleChange(player.UserId)
	player:SetAttribute(SELECTED_ROLE_ATTRIBUTE, roleName)
	player:SetAttribute(ROLE_LOCKED_ATTRIBUTE, true)
	setPlayerRole(player, roleName)
	persistPreferredRole(player, roleName)
	debugLog(string.format("Accepted role select for %s -> %s (locked)", player.Name, roleName))
	player:LoadCharacter()
end)

roleDebugRequestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	if payload ~= nil then
		debugWarn(string.format("Rejected RoleDebugStateRequest userId=%d reason=malformed_payload", player.UserId))
		return
	end

	local snapshot = snapshotForPlayer(player)
	roleDebugResponseRemote:FireClient(player, snapshot)
	debugLog(
		string.format(
			"Sent role debug state userId=%d role=%s selectedRole=%s roleLocked=%s",
			player.UserId,
			tostring(snapshot.role),
			tostring(snapshot.selectedRole),
			tostring(snapshot.roleLocked)
		)
	)
end)

debugLog("RoleService initialized")
