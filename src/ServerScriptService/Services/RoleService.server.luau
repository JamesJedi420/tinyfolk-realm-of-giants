--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")

local function requireDependency(parent: any, childName: string, fallbackPath: string): any
	local requireAny: any = require
	if parent ~= nil and type(parent.WaitForChild) == "function" then
		local child = parent:WaitForChild(childName)
		if child ~= nil then
			local ok, loaded = pcall(function()
				return requireAny(child)
			end)
			if ok then
				return loaded
			end
		end
	end

	return requireAny(fallbackPath)
end

local giantRealm = Shared:FindFirstChild("GiantRealm")
local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local EscapeConfig = requireDependency(Config, "EscapeConfig", "../../ReplicatedStorage/Shared/Config/EscapeConfig")
local SafeZonePolicy =
	requireDependency(giantRealm, "SafeZonePolicy", "../../ReplicatedStorage/Shared/GiantRealm/SafeZonePolicy")
local DownedState =
	requireDependency(giantRealm, "DownedState", "../../ReplicatedStorage/Shared/GiantRealm/DownedState")
local ProfilePersistenceGateway = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("ProfilePersistenceGateway"))
	else (require :: any)("./ProfilePersistenceGateway")

local RoleService: any = {}

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
local GIANT_REALM_OWNER_USER_ID_ATTRIBUTE = "GiantRealmOwnerUserId"

local lastRoleChangeAtByUserId: { [number]: number? } = {}
local loadedGiantRealmOwnerUserIds: { [number]: boolean? } = {}
local cleanedGiantRealmOwnerUserIds: { [number]: boolean? } = {}
local activeGiantRealmOwnerUserId: number? = nil
local downedStates: { [number]: any } = {}
local pendingSpawnDeferredByUserId: { [number]: boolean? } = {}

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

local function getPlayerByUserId(userId: number): Player?
	if type((Players :: any).GetPlayerByUserId) == "function" then
		local colonOk, colonResult = pcall(function()
			return (Players :: any):GetPlayerByUserId(userId)
		end)
		if colonOk then
			return colonResult
		end

		local dotOk, dotResult = pcall(function()
			return (Players :: any).GetPlayerByUserId(userId)
		end)
		if dotOk then
			return dotResult
		end
	end

	if type((Players :: any).GetPlayers) == "function" then
		local playersList: any = nil
		local colonOk, colonResult = pcall(function()
			return (Players :: any):GetPlayers()
		end)
		if colonOk then
			playersList = colonResult
		else
			local dotOk, dotResult = pcall(function()
				return (Players :: any).GetPlayers()
			end)
			if dotOk then
				playersList = dotResult
			end
		end

		if type(playersList) == "table" then
			for _, player in ipairs(playersList) do
				if player ~= nil and type(player.UserId) == "number" and player.UserId == userId then
					return player
				end
			end
		end
	end

	return nil
end

local function getGrabServiceQueryApi(): any?
	-- selene: allow(global_usage)
	local globalValue: any = _G
	if type(globalValue) ~= "table" then
		return nil
	end
	local queryApi = globalValue._GrabService_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end
	return queryApi
end

local function getProfilePersistenceLifecycleQueryApi(): any?
	-- selene: allow(global_usage)
	local globalValue: any = _G
	if type(globalValue) ~= "table" then
		return nil
	end

	local queryApi = globalValue._ProfilePersistenceLifecycle_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end

	return queryApi
end

local function getProfileTeleportHandoffQueryApi(): any?
	-- selene: allow(global_usage)
	local globalValue: any = _G
	if type(globalValue) ~= "table" then
		return nil
	end

	local queryApi = globalValue._ProfileTeleportHandoffService_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end

	return queryApi
end

local function canSpawnGameplayForPlayer(player: Player): boolean
	local queryApi = getProfilePersistenceLifecycleQueryApi()
	if queryApi == nil or type(queryApi.IsPlayerOwnershipReady) ~= "function" then
		return true
	end

	local ok, ready = pcall(function()
		return queryApi.IsPlayerOwnershipReady(player.UserId)
	end)
	if not ok then
		return true
	end

	if ready ~= true then
		return false
	end

	local handoffQueryApi = getProfileTeleportHandoffQueryApi()
	if handoffQueryApi == nil or type(handoffQueryApi.CanSpawnGameplayForUserId) ~= "function" then
		return true
	end

	local handoffOk, handoffReady = pcall(function()
		return handoffQueryApi.CanSpawnGameplayForUserId(player.UserId)
	end)
	if not handoffOk then
		return true
	end

	return handoffReady == true
end

local function deferSpawnUntilOwnershipReady(player: Player, spawnMethod: string, reason: string)
	if pendingSpawnDeferredByUserId[player.UserId] then
		return
	end

	local queryApi = getProfilePersistenceLifecycleQueryApi()
	if queryApi == nil or type(queryApi.RegisterOwnershipReadyCallback) ~= "function" then
		debugWarn(
			string.format(
				"Spawn deferred but lifecycle callback unavailable userId=%d reason=%s",
				player.UserId,
				reason
			)
		)
		return
	end

	pendingSpawnDeferredByUserId[player.UserId] = true

	local function trySpawnIfReady()
		if not pendingSpawnDeferredByUserId[player.UserId] then
			return
		end

		if Players:FindFirstChild(player.Name) ~= player then
			pendingSpawnDeferredByUserId[player.UserId] = nil
			return
		end

		if not canSpawnGameplayForPlayer(player) then
			return
		end

		pendingSpawnDeferredByUserId[player.UserId] = nil

		if spawnMethod == "LoadCharacterAsync" then
			(player :: any):LoadCharacterAsync()
			return
		end

		(player :: any):LoadCharacter()
	end

	local registered = queryApi.RegisterOwnershipReadyCallback(
		player.UserId,
		function(ready: boolean, _failureReason: string?)
			if not ready then
				return
			end

			trySpawnIfReady()
		end
	)

	if not registered then
		pendingSpawnDeferredByUserId[player.UserId] = nil
		debugWarn(
			string.format(
				"Spawn deferred but lifecycle callback rejected registration userId=%d reason=%s",
				player.UserId,
				reason
			)
		)
	end

	local handoffQueryApi = getProfileTeleportHandoffQueryApi()
	if handoffQueryApi ~= nil and type(handoffQueryApi.RegisterReleaseReadyCallback) == "function" then
		pcall(function()
			handoffQueryApi.RegisterReleaseReadyCallback(player.UserId, function(_result: any)
				trySpawnIfReady()
			end)
		end)
	end
end

local function isRoleLocked(player: Player): boolean
	return player:GetAttribute(ROLE_LOCKED_ATTRIBUTE) == true
end

local function downedNow(): number
	return os.clock()
end

local function clampDurationSeconds(duration: any): number
	local downedConfig = RoleConfig.DownedState
	local defaultDuration = downedConfig.DefaultDurationSeconds
	local maxDuration = downedConfig.MaxDurationSeconds
	if type(duration) ~= "number" or duration ~= duration or duration == math.huge or duration == -math.huge then
		return defaultDuration
	end
	if duration < 0 then
		return 0
	end
	if duration > maxDuration then
		return maxDuration
	end
	return duration
end

local function evaluateTargetSafeZone(player: Player, nowSeconds: number): any
	local safeZoneState = player:GetAttribute(EscapeConfig.SafeZoneAttribute) == true
	local safeZoneType = player:GetAttribute(EscapeConfig.SafeZoneTypeAttribute)
	local safeZoneProtectionEndsAt = player:GetAttribute(EscapeConfig.SafeZoneProtectionEndsAtAttribute)
	return SafeZonePolicy.EvaluateProtection(EscapeConfig, {
		safeZoneState = safeZoneState,
		safeZoneType = safeZoneType,
		safeZoneProtectionEndsAt = safeZoneProtectionEndsAt,
		now = nowSeconds,
	})
end

local function setDownedAttributes(player: Player, snapshot: any)
	player:SetAttribute("DownedState", snapshot.status)
	player:SetAttribute("DownedSource", snapshot.source)
	player:SetAttribute("DownedReason", snapshot.reason)
	player:SetAttribute("DownedAt", snapshot.downedAt)
	player:SetAttribute("DownedExpiresAt", snapshot.expiresAt)
	player:SetAttribute("DownedSelfRecoveryProgress", snapshot.selfRecoveryProgress)
	player:SetAttribute("DownedSelfRecoveryCap", snapshot.selfRecoveryCap)
	player:SetAttribute("DownedMovementMultiplier", snapshot.movementMultiplier)
	player:SetAttribute("DownedIsDowned", snapshot.isDowned)
	player:SetAttribute("DownedCarryEligibleMarker", snapshot.carryEligibleMarker)
end

local function getOrCreateDownedState(userId: number): any
	local existing = downedStates[userId]
	if existing ~= nil then
		return existing
	end
	local created = DownedState.New(downedNow())
	downedStates[userId] = created
	return created
end

local function applyScaleToCharacter(player: Player, character: Instance)
	local role = getRoleOrDefault(player)
	local scale = RoleConfig.ScaleByRole[role]
	if type(scale) ~= "number" then
		debugWarn(string.format("Missing scale config for role '%s'", role))
		return
	end

	local characterAny: any = character
	local humanoid = characterAny:FindFirstChildOfClass("Humanoid") or characterAny:WaitForChild("Humanoid", 5)
	if humanoid == nil then
		debugWarn(string.format("Could not scale %s: Humanoid not found", player.Name))
		return
	end

	characterAny:ScaleTo(scale)
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

local function findSpawnForRole(roleName: string): BasePart?
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

local function placeCharacterAtRoleSpawn(player: Player, character: Instance)
	local roleName = getRoleOrDefault(player)
	local spawnLocation = findSpawnForRole(roleName)
	if spawnLocation == nil then
		debugLog(
			string.format("Missing role spawn for role=%s userId=%d; using default spawn", roleName, player.UserId)
		)
		return
	end

	local characterAny: any = character
	local root = characterAny:FindFirstChild("HumanoidRootPart") or characterAny:WaitForChild("HumanoidRootPart", 5)
	if not root or not root:IsA("BasePart") then
		debugWarn(string.format("Could not place %s at role spawn: HumanoidRootPart not found", player.Name))
		return
	end

	local targetCFrame = spawnLocation.CFrame + Vector3.new(0, 3, 0)
	characterAny:PivotTo(targetCFrame)
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

		if not canSpawnGameplayForPlayer(player) then
			debugWarn(
				string.format("Respawn deferred userId=%d reason=ownership_not_ready trigger=%s", player.UserId, reason)
			)
			deferSpawnUntilOwnershipReady(player, "LoadCharacterAsync", "respawn_ownership_not_ready")
			return
		end

		debugLog(string.format("Respawning locked player userId=%d reason=%s", player.UserId, reason))
		local playerAny: any = player
		playerAny:LoadCharacterAsync()
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

local function projectActiveGiantRealmOwner()
	for _, player in Players:GetPlayers() do
		player:SetAttribute(GIANT_REALM_OWNER_USER_ID_ATTRIBUTE, activeGiantRealmOwnerUserId)
	end
end

local function findLoadedGiantRealmOwnerUserId(): number?
	for _, playerInstance in Players:GetPlayers() do
		local player = playerInstance :: Player
		if loadedGiantRealmOwnerUserIds[player.UserId] then
			return player.UserId
		end
	end

	return nil
end

local function loadGiantRealmForPlayer(player: Player)
	if loadedGiantRealmOwnerUserIds[player.UserId] then
		return
	end

	local loadResult = ProfilePersistenceGateway.LoadGiantRealmProfile(player.UserId)
	if not loadResult.ok then
		debugWarn(
			string.format("Giant realm load failed userId=%d reason=%s", player.UserId, tostring(loadResult.reason))
		)
		return
	end

	loadedGiantRealmOwnerUserIds[player.UserId] = true
	cleanedGiantRealmOwnerUserIds[player.UserId] = nil
	activeGiantRealmOwnerUserId = player.UserId
	projectActiveGiantRealmOwner()
	debugLog(string.format("Loaded Giant realm profile userId=%d", player.UserId))
end

local function saveAndReleaseGiantRealmForPlayer(player: Player, reason: string)
	if not loadedGiantRealmOwnerUserIds[player.UserId] or cleanedGiantRealmOwnerUserIds[player.UserId] then
		return
	end

	local saveResult = ProfilePersistenceGateway.SaveGiantRealmProfile(player.UserId)
	if not saveResult.ok then
		debugWarn(
			string.format(
				"Giant realm save failed userId=%d reason=%s cleanupReason=%s",
				player.UserId,
				tostring(saveResult.reason),
				reason
			)
		)
	end

	local releaseResult = ProfilePersistenceGateway.ReleaseGiantRealmProfile(player.UserId)
	if not releaseResult.ok then
		debugWarn(
			string.format(
				"Giant realm release failed userId=%d reason=%s cleanupReason=%s",
				player.UserId,
				tostring(releaseResult.reason),
				reason
			)
		)
	end

	loadedGiantRealmOwnerUserIds[player.UserId] = nil
	cleanedGiantRealmOwnerUserIds[player.UserId] = true
	if activeGiantRealmOwnerUserId == player.UserId then
		activeGiantRealmOwnerUserId = findLoadedGiantRealmOwnerUserId()
		projectActiveGiantRealmOwner()
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
	player:SetAttribute(GIANT_REALM_OWNER_USER_ID_ATTRIBUTE, activeGiantRealmOwnerUserId)
	setDownedAttributes(player, DownedState.Snapshot(DownedState.New(downedNow())))
	local playerAny: any = player
	playerAny.CharacterAdded:Connect(function(character: Instance)
		ensureRoleForLockedPlayer(player)
		applyScaleToCharacter(player, character)
		placeCharacterAtRoleSpawn(player, character)

		local characterAny: any = character
		local humanoid = characterAny:FindFirstChildOfClass("Humanoid") or characterAny:WaitForChild("Humanoid", 5)
		if humanoid == nil then
			debugWarn(string.format("Could not bind respawn handler for %s: Humanoid not found", player.Name))
			return
		end

		(humanoid :: any).Died:Connect(function()
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
	downedStates[player.UserId] = nil
	pendingSpawnDeferredByUserId[player.UserId] = nil
	saveAndReleaseGiantRealmForPlayer(player, "player_removing")
end)

if game ~= nil and type((game :: any).BindToClose) == "function" then
	(game :: any):BindToClose(function()
		for _, player in Players:GetPlayers() do
			saveAndReleaseGiantRealmForPlayer(player, "bind_to_close")
		end
	end)
end

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
	if roleName == RoleConfig.Roles.Giant then
		loadGiantRealmForPlayer(player)
	else
		projectActiveGiantRealmOwner()
	end
	debugLog(string.format("Accepted role select for %s -> %s (locked)", player.Name, roleName))
	if not canSpawnGameplayForPlayer(player) then
		debugWarn(string.format("Role select spawn deferred userId=%d reason=ownership_not_ready", player.UserId))
		deferSpawnUntilOwnershipReady(player, "LoadCharacter", "role_select_ownership_not_ready")
		return
	end

	local playerAny: any = player
	playerAny:LoadCharacter()
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

function RoleService.setDowned(userId: number, duration: number, reason: string): boolean
	local player = getPlayerByUserId(userId)
	if not player then
		return false
	end

	local nowSeconds = downedNow()
	local safeZoneDecision = evaluateTargetSafeZone(player, nowSeconds)
	local state = getOrCreateDownedState(userId)
	local result = DownedState.Enter(state, {
		now = nowSeconds,
		durationSeconds = clampDurationSeconds(duration),
		role = getRoleOrDefault(player),
		source = "server_test",
		reason = reason,
		selfRecoveryCap = RoleConfig.DownedState.SelfRecoveryCap,
		movementMultiplier = RoleConfig.DownedState.MovementMultiplier,
		interactionMask = RoleConfig.DownedState.InteractionMask,
		safeZoneProtected = safeZoneDecision.protected == true,
		validSources = RoleConfig.DownedState.ValidSources,
	})
	setDownedAttributes(player, result.snapshot)
	return result.accepted == true
end

function RoleService.updateDownedStates(nowOverride: number?)
	local nowSeconds = if type(nowOverride) == "number" then nowOverride else downedNow()
	for userId, state in pairs(downedStates) do
		local result = DownedState.Tick(state, nowSeconds)
		local player = getPlayerByUserId(userId)
		if player then
			setDownedAttributes(player, result.snapshot)
		end
	end
end

function RoleService.selfRecoverDowned(userId: number, progressDelta: number, nowOverride: number?): boolean
	local player = getPlayerByUserId(userId)
	if not player then
		return false
	end

	local grabServiceQueryApi = getGrabServiceQueryApi()
	if grabServiceQueryApi ~= nil and type(grabServiceQueryApi.IsPlayerCarried) == "function" then
		if grabServiceQueryApi.IsPlayerCarried(userId) == true then
			return false
		end
	end

	local state = getOrCreateDownedState(userId)
	local nowSeconds = if type(nowOverride) == "number" then nowOverride else downedNow()
	local result = DownedState.SelfRecover(state, nowSeconds, progressDelta)
	setDownedAttributes(player, result.snapshot)
	return result.accepted == true
end

function RoleService.isDowned(userId: number): boolean
	local state = downedStates[userId]
	if state == nil then
		return false
	end
	return DownedState.IsDowned(state)
end

function RoleService.canPerformInteraction(userId: number, interactionName: string): boolean
	local state = downedStates[userId]
	if state == nil then
		return true
	end
	return DownedState.CanPerformInteraction(state, interactionName)
end

function RoleService.getDownedSnapshot(userId: number): any
	local state = downedStates[userId]
	if state == nil then
		return DownedState.Snapshot(DownedState.New(downedNow()))
	end
	return DownedState.Snapshot(state)
end

-- selene: allow(global_usage)
_G._RoleService_QueryAPI = {
	SetDowned = function(userId: number, duration: number, reason: string): boolean
		return RoleService.setDowned(userId, duration, reason)
	end,
	SelfRecoverDowned = function(userId: number, progressDelta: number, nowOverride: number?): boolean
		return RoleService.selfRecoverDowned(userId, progressDelta, nowOverride)
	end,
	TickDownedStates = function(nowOverride: number?)
		RoleService.updateDownedStates(nowOverride)
	end,
	IsPlayerDowned = function(userId: number): boolean
		return RoleService.isDowned(userId)
	end,
	CanPlayerPerformInteraction = function(userId: number, interactionName: string): boolean
		return RoleService.canPerformInteraction(userId, interactionName)
	end,
	GetDownedSnapshot = function(userId: number): any
		return RoleService.getDownedSnapshot(userId)
	end,
	GetActiveGiantRealmOwnerUserId = function(): number?
		return activeGiantRealmOwnerUserId
	end,
	CanSpawnGameplayForUserId = function(userId: number): boolean
		local player = getPlayerByUserId(userId)
		if player == nil then
			return false
		end
		return canSpawnGameplayForPlayer(player)
	end,
}

debugLog("RoleService initialized")
