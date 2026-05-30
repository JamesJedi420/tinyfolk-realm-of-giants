--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local RoleConfig = require(Config:WaitForChild("RoleConfig"))
local EscapeConfig = require(Config:WaitForChild("EscapeConfig"))
local EmergencyReinforcementConfig = require(Config:WaitForChild("EmergencyReinforcementConfig"))
local SafeZonePolicy = require(GiantRealm:WaitForChild("SafeZonePolicy"))
local GiantRealmSaveSchema = require(GiantRealm:WaitForChild("GiantRealmSaveSchema"))
local EmergencyReinforcementState = require(GiantRealm:WaitForChild("EmergencyReinforcementState"))

local REMOTES_FOLDER_NAME = "Remotes"
local REQUEST_REMOTE_NAME = "EmergencyReinforcementRequest"
local RESPONSE_REMOTE_NAME = "EmergencyReinforcementResponse"
local DEBUG_REQUEST_REMOTE_NAME = "EmergencyReinforcementDebugStateRequest"
local DEBUG_RESPONSE_REMOTE_NAME = "EmergencyReinforcementDebugStateResponse"

local ROLE_ATTRIBUTE = "Role"
local CLASS_ATTRIBUTE = "ReinforcementClass"
local LOADOUT_ATTRIBUTE = "ReinforcementLoadoutPreset"
local ENABLED_ATTRIBUTE = "EmergencyReinforcementEnabled"

local serviceState = EmergencyReinforcementState.NewState()
local lastRequestAtByUserId: { [number]: number? } = {}
local lastRejectedRequestAtByUserId: { [number]: number? } = {}
local matchStartedAt = os.clock()
local resolveStateTransitionForTests: ((any, any) -> any)? = nil
local applyStateAttributes: () -> ()

local function debugLog(message: string)
	print(string.format("[EmergencyReinforcementService] %s", message))
end

local function debugWarn(message: string)
	warn(string.format("[EmergencyReinforcementService] %s", message))
end

local function now(): number
	return os.clock()
end

local function isFiniteNonNegativeNumber(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	return value >= 0
end

local function isValidPositiveInteger(value: any): boolean
	if type(value) ~= "number" then
		return false
	end
	if value ~= value or value == math.huge or value == -math.huge then
		return false
	end
	if value % 1 ~= 0 then
		return false
	end
	return value > 0
end

local function resolveAt(at: any): number
	if isFiniteNonNegativeNumber(at) then
		return at
	end
	return now()
end

local function resolveStateTransition(state: any, input: any): any
	if type(resolveStateTransitionForTests) == "function" then
		return resolveStateTransitionForTests(state, input)
	end
	return EmergencyReinforcementState.ResolveRequest(state, input)
end

local function getObjectiveTokenServiceQueryApi(): any
	local globalValue = _G
	if type(globalValue._RealmObjectiveService_QueryAPI) == "table" then
		return globalValue._RealmObjectiveService_QueryAPI
	end
	return nil
end

local function requestConsumeEmergencyToken(requesterUserId: number, objectiveId: string, at: number): any
	local objectiveTokenApi = getObjectiveTokenServiceQueryApi()
	if objectiveTokenApi == nil or type(objectiveTokenApi.RequestConsumeEmergencyToken) ~= "function" then
		return {
			accepted = false,
			reason = "objective_token_api_unavailable",
			tokenState = nil,
		}
	end

	local result = objectiveTokenApi.RequestConsumeEmergencyToken(requesterUserId, objectiveId, at)
	if type(result) ~= "table" then
		return {
			accepted = false,
			reason = "token_consume_failed",
			tokenState = nil,
		}
	end

	return result
end

local function requestEmergencyTokenSnapshot(objectiveId: string, at: number): any
	local objectiveTokenApi = getObjectiveTokenServiceQueryApi()
	if objectiveTokenApi == nil or type(objectiveTokenApi.GetEmergencyTokenSnapshot) ~= "function" then
		return {
			accepted = false,
			reason = "objective_token_api_unavailable",
			tokenState = nil,
		}
	end

	local result = objectiveTokenApi.GetEmergencyTokenSnapshot(objectiveId, at)
	if type(result) ~= "table" then
		return {
			accepted = false,
			reason = "token_snapshot_failed",
			tokenState = nil,
		}
	end

	if type(result.accepted) == "boolean" and result.accepted ~= true then
		return {
			accepted = false,
			reason = if type(result.reason) == "string" then result.reason else "token_snapshot_failed",
			tokenState = result.tokenState,
		}
	end

	return {
		accepted = true,
		reason = "accepted",
		tokenState = if type(result.tokenState) == "table" then result.tokenState else nil,
	}
end

local function ensureRemotesFolder(): Folder
	local existing = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
	if existing and existing:IsA("Folder") then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name = REMOTES_FOLDER_NAME
	folder.Parent = ReplicatedStorage
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
	return remote
end

local function resolveNodeByPath(root: Instance, path: { string }): Instance?
	local node: Instance = root
	for _, childName in ipairs(path) do
		local nextNode = node:FindFirstChild(childName)
		if nextNode == nil then
			return nil
		end
		node = nextNode
	end
	return node
end

local function getPlayerByUserId(userId: number): Player?
	for _, player in Players:GetPlayers() do
		if player.UserId == userId then
			return player :: any
		end
	end

	return nil
end

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	if character == nil then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		return humanoid
	end

	return nil
end

local function getHumanoidRootPart(player: Player): BasePart?
	local character = player.Character
	if character == nil then
		return nil
	end

	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end

	return nil
end

local function isPlayerAlive(player: Player): boolean
	local humanoid = getHumanoid(player)
	if humanoid == nil then
		return false
	end

	return humanoid.Health > 0
end

local function getActiveTinyfolkCount(): number
	local count = 0
	for _, player in Players:GetPlayers() do
		if player:GetAttribute(ROLE_ATTRIBUTE) == RoleConfig.Roles.Tinyfolk and isPlayerAlive(player) then
			count += 1
		end
	end
	return count
end

local resolveObjectivePart: (objectiveId: string) -> BasePart?
local resolveSpawnPart: () -> BasePart?
local evaluateSpawnProtection: (spawnPart: BasePart?, at: number) -> any

local function hasEligibleCandidate(): boolean
	for _, player in Players:GetPlayers() do
		if player:GetAttribute(ROLE_ATTRIBUTE) == RoleConfig.Roles.Tinyfolk and isPlayerAlive(player) == false then
			return true
		end
	end

	return false
end

local function evaluateAvailabilityReadiness(at: number): (boolean, string)
	local objectivePart = resolveObjectivePart(EmergencyReinforcementConfig.CallCenterObjectiveId)
	if objectivePart == nil then
		return false, "invalid_objective"
	end

	local spawnPart = resolveSpawnPart()
	if spawnPart == nil then
		return false, "reinforcement_spawn_missing"
	end

	local spawnDecision = evaluateSpawnProtection(spawnPart, at)
	if spawnDecision.protected == true then
		return false, "reinforcement_spawn_protected"
	end

	if not hasEligibleCandidate() then
		return false, "reinforcement_candidate_missing"
	end

	return true, "ready"
end

local function buildSnapshot(at: number): any
	local activeTinyfolkCount = getActiveTinyfolkCount()
	local threshold = EmergencyReinforcementConfig.ActiveTinyfolkThreshold
	local readinessOk, readinessReason = evaluateAvailabilityReadiness(at)
	local available = serviceState.used ~= true
		and (at - matchStartedAt) >= EmergencyReinforcementConfig.MinMatchElapsedSeconds
		and activeTinyfolkCount < threshold
		and readinessOk

	return {
		available = available,
		used = serviceState.used == true,
		callStartedAt = serviceState.callStartedAt,
		cooldownEndsAt = serviceState.cooldownEndsAt,
		triggeredByUserId = serviceState.triggeredByUserId,
		spawnedUserId = serviceState.spawnedUserId,
		lastReason = serviceState.lastReason,
		lastObjectiveId = serviceState.lastObjectiveId,
		activeTinyfolkCount = activeTinyfolkCount,
		activeTinyfolkThreshold = threshold,
		readinessReason = readinessReason,
		matchStartedAt = matchStartedAt,
	}
end

local function buildPersistenceState(): any
	return {
		used = serviceState.used == true,
		callStartedAt = serviceState.callStartedAt,
		cooldownEndsAt = serviceState.cooldownEndsAt,
		triggeredByUserId = serviceState.triggeredByUserId,
		spawnedUserId = serviceState.spawnedUserId,
		lastReason = serviceState.lastReason,
		lastObjectiveId = serviceState.lastObjectiveId,
	}
end

local function normalizePersistenceState(persistedState: any): any
	if persistedState == nil then
		return EmergencyReinforcementState.NewState()
	end

	return {
		used = persistedState.used == true,
		callStartedAt = persistedState.callStartedAt,
		cooldownEndsAt = persistedState.cooldownEndsAt,
		triggeredByUserId = persistedState.triggeredByUserId,
		spawnedUserId = persistedState.spawnedUserId,
		lastReason = persistedState.lastReason,
		lastObjectiveId = persistedState.lastObjectiveId,
	}
end

local function applyPersistenceState(persistedState: any): (boolean, string?)
	local valid, reason = GiantRealmSaveSchema.ValidateEmergencyReinforcementRecord(persistedState)
	if not valid then
		return false, reason or "emergency_reinforcement_persistence_invalid"
	end

	serviceState = normalizePersistenceState(persistedState)
	applyStateAttributes()
	return true, nil
end

local function makeResponse(accepted: boolean, reason: string, at: number, trace: any?): any
	return {
		accepted = accepted,
		reason = reason,
		snapshot = buildSnapshot(at),
		trace = trace,
	}
end

function applyStateAttributes()
	local stateHost = resolveNodeByPath(Workspace, { "Map" })
	if stateHost == nil then
		stateHost = Workspace
	end
	local stateHostAny: any = stateHost

	local snapshot = buildSnapshot(now())
	local attrs = EmergencyReinforcementConfig.StateAttributes
	stateHostAny:SetAttribute(attrs.Available, snapshot.available)
	stateHostAny:SetAttribute(attrs.Used, snapshot.used)
	stateHostAny:SetAttribute(attrs.CooldownEndsAt, snapshot.cooldownEndsAt)
	stateHostAny:SetAttribute(attrs.CallStartedAt, snapshot.callStartedAt)
	stateHostAny:SetAttribute(attrs.TriggeredByUserId, snapshot.triggeredByUserId)
	stateHostAny:SetAttribute(attrs.SpawnedUserId, snapshot.spawnedUserId)
	stateHostAny:SetAttribute(attrs.LastReason, snapshot.lastReason)
	stateHostAny:SetAttribute(attrs.ActiveTinyfolkCount, snapshot.activeTinyfolkCount)
	stateHostAny:SetAttribute(attrs.ReadinessReason, snapshot.readinessReason)
end

resolveObjectivePart = function(objectiveId: string): BasePart?
	local objectivesRoot = resolveNodeByPath(Workspace, EmergencyReinforcementConfig.ObjectiveFolderPath)
	if objectivesRoot == nil then
		return nil
	end

	local objective = objectivesRoot:FindFirstChild(objectiveId)
	if objective and objective:IsA("BasePart") then
		return objective
	end

	return nil
end

resolveSpawnPart = function(): BasePart?
	local spawnsRoot = resolveNodeByPath(Workspace, EmergencyReinforcementConfig.SpawnFolderPath)
	if spawnsRoot == nil then
		return nil
	end

	local preferred = spawnsRoot:FindFirstChild(EmergencyReinforcementConfig.ReinforcementSpawnName)
	if preferred and preferred:IsA("BasePart") then
		return preferred
	end

	local fallback = spawnsRoot:FindFirstChild(EmergencyReinforcementConfig.FallbackSpawnName)
	if fallback and fallback:IsA("BasePart") then
		return fallback
	end

	return nil
end

evaluateSpawnProtection = function(spawnPart: BasePart?, at: number): any
	if spawnPart == nil then
		return {
			protected = true,
			reason = "reinforcement_spawn_missing",
		}
	end

	return SafeZonePolicy.EvaluateProtection(EscapeConfig, {
		safeZoneState = spawnPart:GetAttribute(EscapeConfig.SafeZoneAttribute) == true,
		safeZoneType = spawnPart:GetAttribute(EscapeConfig.SafeZoneTypeAttribute),
		safeZoneProtectionEndsAt = spawnPart:GetAttribute(EscapeConfig.SafeZoneProtectionEndsAtAttribute),
		now = at,
	})
end

local function objectiveInRange(player: Player, objectivePart: BasePart): boolean
	local root = getHumanoidRootPart(player)
	if root == nil then
		return false
	end

	local delta = ((root.Position :: any) - (objectivePart.Position :: any))
	if delta == nil then
		return false
	end

	local magnitude = nil
	local magnitudeValue = (delta :: any).Magnitude
	if type(magnitudeValue) == "number" then
		magnitude = magnitudeValue
	elseif type(magnitudeValue) == "function" then
		magnitude = (delta :: any):Magnitude()
	end

	if type(magnitude) ~= "number" then
		return false
	end

	return magnitude <= EmergencyReinforcementConfig.ObjectiveTriggerRadiusStuds
end

local function resolveCandidatePlayer(requesterUserId: number): Player?
	local candidates: { Player } = {}
	for _, player in Players:GetPlayers() do
		if player.UserId == requesterUserId then
			continue
		end

		if player:GetAttribute(ROLE_ATTRIBUTE) ~= RoleConfig.Roles.Tinyfolk then
			continue
		end

		if isPlayerAlive(player) then
			continue
		end

		table.insert(candidates, player)
	end

	table.sort(candidates, function(a: Player, b: Player)
		return a.UserId < b.UserId
	end)

	return candidates[1]
end

local function isCoolingDown(userId: number, at: number): boolean
	local last = lastRequestAtByUserId[userId]
	if last == nil then
		return false
	end

	return (at - last) < EmergencyReinforcementConfig.RequestCooldownSeconds
end

local function markRequest(userId: number, at: number)
	lastRequestAtByUserId[userId] = at
end

local function isRejectCoolingDown(userId: number, at: number): boolean
	local rejectCooldown = EmergencyReinforcementConfig.RejectRequestCooldownSeconds
	if type(rejectCooldown) ~= "number" or rejectCooldown <= 0 then
		return false
	end

	local last = lastRejectedRequestAtByUserId[userId]
	if last == nil then
		return false
	end

	return (at - last) < rejectCooldown
end

local function markRejectedRequest(userId: number, at: number)
	lastRejectedRequestAtByUserId[userId] = at
end

local function movePlayerToSpawn(player: Player, spawnPart: BasePart)
	local character = player.Character
	if character == nil then
		return false
	end

	if type((character :: any).PivotTo) == "function" then
		(character :: any):PivotTo(spawnPart.CFrame)
		return true
	end

	local root = getHumanoidRootPart(player)
	if root ~= nil then
		(root :: any).CFrame = spawnPart.CFrame
		return true
	end

	return false
end

local function bindSpawnPlacementToCharacterAdded(player: Player, spawnPart: BasePart)
	local playerAny: any = player
	local characterAddedSignal = playerAny.CharacterAdded
	if type(characterAddedSignal) ~= "table" or type(characterAddedSignal.Connect) ~= "function" then
		return
	end

	local connection: any = nil
	connection = characterAddedSignal:Connect(function(_character: any)
		local placed = movePlayerToSpawn(player, spawnPart)
		if placed and connection ~= nil and type(connection.Disconnect) == "function" then
			connection:Disconnect()
		end
	end)
end

local function scheduleSpawnPlacementRetries(player: Player, spawnPart: BasePart)
	local retries = EmergencyReinforcementConfig.SpawnPlacementRetryCount
	if type(retries) ~= "number" or retries <= 0 then
		return
	end

	local retry: ((number) -> ())?
	retry = function(remaining: number)
		if remaining <= 0 then
			return
		end

		if movePlayerToSpawn(player, spawnPart) then
			return
		end

		if type(task) == "table" and type((task :: any).defer) == "function" then
			(task :: any).defer(function()
				if retry ~= nil then
					retry(remaining - 1)
				end
			end)
		end
	end

	if retry ~= nil then
		retry(retries)
	end
end

local function initializeReinforcementPlayer(candidate: Player, spawnPart: BasePart)
	candidate:SetAttribute(ROLE_ATTRIBUTE, RoleConfig.Roles.Tinyfolk)
	candidate:SetAttribute(ENABLED_ATTRIBUTE, true)
	candidate:SetAttribute(CLASS_ATTRIBUTE, EmergencyReinforcementConfig.DefaultReinforcementClass)
	candidate:SetAttribute(LOADOUT_ATTRIBUTE, EmergencyReinforcementConfig.DefaultLoadoutPreset)

	-- Bind once before loading so async respawns still receive deterministic placement.
	bindSpawnPlacementToCharacterAdded(candidate, spawnPart)

	if type((candidate :: any).LoadCharacter) == "function" then
		(candidate :: any):LoadCharacter()
	elseif type((candidate :: any).LoadCharacterAsync) == "function" then
		(candidate :: any):LoadCharacterAsync()
	end

	movePlayerToSpawn(candidate, spawnPart)
	scheduleSpawnPlacementRetries(candidate, spawnPart)
end

local function requestReinforcement(player: Player, payload: any, at: number?): any
	local resolvedNow = resolveAt(at)
	if not isPlayerAlive(player) then
		serviceState.lastReason = "requester_not_alive"
		applyStateAttributes()
		return makeResponse(false, "requester_not_alive", resolvedNow)
	end

	if isCoolingDown(player.UserId, resolvedNow) then
		return makeResponse(false, "request_cooldown", resolvedNow)
	end

	if isRejectCoolingDown(player.UserId, resolvedNow) then
		return makeResponse(false, "request_cooldown", resolvedNow)
	end

	local objectiveId = nil
	if type(payload) == "table" then
		local payloadAny: any = payload
		if type(payloadAny.objectiveId) == "string" then
			objectiveId = payloadAny.objectiveId
		end
	elseif type(payload) == "string" then
		objectiveId = payload
	end

	local objectivePart = nil
	if type(objectiveId) == "string" then
		objectivePart = resolveObjectivePart(objectiveId)
	end

	local inRange = if objectivePart ~= nil then objectiveInRange(player, objectivePart) else false

	local spawnPart = resolveSpawnPart()
	local spawnDecision = evaluateSpawnProtection(spawnPart, resolvedNow)
	local candidate = resolveCandidatePlayer(player.UserId)

	local candidateUserId = if candidate ~= nil then (candidate :: any).UserId else nil

	local transitionOk, transitionOrError = pcall(function()
		return resolveStateTransition(serviceState, {
			now = resolvedNow,
			matchStartedAt = matchStartedAt,
			requesterRole = player:GetAttribute(ROLE_ATTRIBUTE),
			requesterUserId = player.UserId,
			activeTinyfolkCount = getActiveTinyfolkCount(),
			activeTinyfolkThreshold = EmergencyReinforcementConfig.ActiveTinyfolkThreshold,
			minMatchElapsedSeconds = EmergencyReinforcementConfig.MinMatchElapsedSeconds,
			objectiveId = objectiveId,
			expectedObjectiveId = EmergencyReinforcementConfig.CallCenterObjectiveId,
			objectiveInRange = inRange,
			hasSpawnPart = spawnPart ~= nil,
			spawnProtected = spawnDecision.protected == true,
			candidateUserId = candidateUserId,
			callCooldownSeconds = EmergencyReinforcementConfig.CallCooldownSeconds,
		})
	end)

	if not transitionOk or type(transitionOrError) ~= "table" then
		serviceState.lastReason = "state_transition_failed"
		markRejectedRequest(player.UserId, resolvedNow)
		applyStateAttributes()
		return makeResponse(false, "state_transition_failed", resolvedNow)
	end

	local transitionAny: any = transitionOrError
	if type(transitionAny.accepted) ~= "boolean" or type(transitionAny.reason) ~= "string" then
		serviceState.lastReason = "state_transition_failed"
		markRejectedRequest(player.UserId, resolvedNow)
		applyStateAttributes()
		return makeResponse(false, "state_transition_failed", resolvedNow)
	end

	local transition = transitionAny

	if not transition.accepted then
		serviceState = transition.state
		markRejectedRequest(player.UserId, resolvedNow)
		applyStateAttributes()
		debugWarn(string.format("Rejected reinforcement callerUserId=%d reason=%s", player.UserId, transition.reason))
		return makeResponse(false, transition.reason, resolvedNow)
	end

	local function rejectTokenStage(reason: string): any
		serviceState.lastReason = reason
		if type(objectiveId) == "string" then
			serviceState.lastObjectiveId = objectiveId
		end
		markRejectedRequest(player.UserId, resolvedNow)
		applyStateAttributes()
		debugWarn(string.format("Rejected reinforcement callerUserId=%d reason=%s", player.UserId, reason))
		return makeResponse(false, reason, resolvedNow)
	end

	local tokenSnapshotOk, tokenSnapshotResultOrError = pcall(function()
		return requestEmergencyTokenSnapshot(objectiveId or "", resolvedNow)
	end)

	if not tokenSnapshotOk or type(tokenSnapshotResultOrError) ~= "table" then
		return rejectTokenStage("token_snapshot_failed")
	end

	local tokenSnapshotResult = tokenSnapshotResultOrError
	if tokenSnapshotResult.accepted ~= true then
		local snapshotReason = if type(tokenSnapshotResult.reason) == "string"
			then tokenSnapshotResult.reason
			else "token_snapshot_failed"
		return rejectTokenStage(snapshotReason)
	end

	local tokenConsumeOk, tokenConsumeResultOrError = pcall(function()
		return requestConsumeEmergencyToken(player.UserId, objectiveId or "", resolvedNow)
	end)

	if not tokenConsumeOk or type(tokenConsumeResultOrError) ~= "table" then
		return rejectTokenStage("token_consume_failed")
	end

	local tokenConsumeResult = tokenConsumeResultOrError
	if tokenConsumeResult.accepted ~= true then
		local tokenReason = if type(tokenConsumeResult.reason) == "string"
			then tokenConsumeResult.reason
			else "token_consume_failed"
		return rejectTokenStage(tokenReason)
	end

	local compensationTrace = {
		compensationRequired = true,
		reason = "token_consumed_spawn_failed",
		requesterUserId = player.UserId,
		objectiveId = objectiveId,
		consumedAt = resolvedNow,
	}

	serviceState = transition.state
	markRequest(player.UserId, resolvedNow)

	if candidate ~= nil and spawnPart ~= nil then
		local resolvedCandidate = candidate :: Player
		initializeReinforcementPlayer(resolvedCandidate, spawnPart)
		debugLog(
			string.format(
				"Accepted reinforcement callerUserId=%d spawnedUserId=%d objectiveId=%s",
				player.UserId,
				resolvedCandidate.UserId,
				tostring(objectiveId)
			)
		)
	else
		serviceState.lastReason = "reinforcement_spawn_failed"
		debugWarn(
			string.format("Rejected reinforcement callerUserId=%d reason=reinforcement_spawn_failed", player.UserId)
		)
		markRejectedRequest(player.UserId, resolvedNow)
		applyStateAttributes()
		return makeResponse(false, "reinforcement_spawn_failed", resolvedNow, compensationTrace)
	end

	applyStateAttributes()

	return makeResponse(true, "accepted", resolvedNow)
end

local remotesFolder = ensureRemotesFolder()
local requestRemote = ensureRemoteEvent(remotesFolder, REQUEST_REMOTE_NAME)
local responseRemote = ensureRemoteEvent(remotesFolder, RESPONSE_REMOTE_NAME)
local debugRequestRemote = ensureRemoteEvent(remotesFolder, DEBUG_REQUEST_REMOTE_NAME)
local debugResponseRemote = ensureRemoteEvent(remotesFolder, DEBUG_RESPONSE_REMOTE_NAME)

requestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	local result = requestReinforcement(player, payload, nil)
	responseRemote:FireClient(player, result)
end)

debugRequestRemote.OnServerEvent:Connect(function(player: Player, _payload: unknown)
	debugResponseRemote:FireClient(player, buildSnapshot(now()))
end)

Players.PlayerRemoving:Connect(function(player: Player)
	lastRequestAtByUserId[player.UserId] = nil
	lastRejectedRequestAtByUserId[player.UserId] = nil
end)

applyStateAttributes()

_G._EmergencyReinforcementService_QueryAPI = {
	RequestReinforcement = function(requesterUserId: number, payload: any, at: number?): any
		local resolvedAt = resolveAt(at)
		if not isValidPositiveInteger(requesterUserId) then
			return makeResponse(false, "requester_user_id_invalid", resolvedAt)
		end

		local requester = getPlayerByUserId(requesterUserId)
		if requester == nil then
			return makeResponse(false, "requester_not_found", resolvedAt)
		end

		return requestReinforcement(requester, payload, at)
	end,
	GetStateSnapshot = function(at: number?): any
		return buildSnapshot(resolveAt(at))
	end,
	BuildPersistenceState = function(): any
		return buildPersistenceState()
	end,
	ApplyPersistenceState = function(persistedState: any): (boolean, string?)
		return applyPersistenceState(persistedState)
	end,
	GetActiveTinyfolkCount = function(): number
		return getActiveTinyfolkCount()
	end,
	IsCallAvailable = function(at: number?): boolean
		return buildSnapshot(resolveAt(at)).available == true
	end,
	ResetForTests = function(newMatchStartedAt: number?)
		serviceState = EmergencyReinforcementState.NewState()
		lastRequestAtByUserId = {}
		lastRejectedRequestAtByUserId = {}
		resolveStateTransitionForTests = nil
		if type(newMatchStartedAt) == "number" then
			matchStartedAt = newMatchStartedAt
		else
			matchStartedAt = now()
		end
		applyStateAttributes()
	end,
	SetStateTransitionResolverForTests = function(resolver: any)
		if type(resolver) == "function" then
			resolveStateTransitionForTests = resolver :: (any, any) -> any
		else
			resolveStateTransitionForTests = nil
		end
	end,
}

debugLog("EmergencyReinforcementService initialized")
