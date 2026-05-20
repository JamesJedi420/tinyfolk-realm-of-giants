--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local EscapeConfig = require(Config:WaitForChild("EscapeConfig"))
local RescueContractConfig = require(Config:WaitForChild("RescueContractConfig"))
local SafeZonePolicy = require(GiantRealm:WaitForChild("SafeZonePolicy"))
local RescueContractState = require(GiantRealm:WaitForChild("RescueContractState"))

local REMOTES_FOLDER_NAME = "Remotes"
local REQUEST_REMOTE_NAME = "RescueContractRequest"
local RESPONSE_REMOTE_NAME = "RescueContractResponse"
local COMPLETE_REMOTE_NAME = "RescueContractCompleteRequest"

local ROLE_ATTRIBUTE = "Role"

local state = RescueContractState.NewState()
local lastRequestAtByUserId: { [number]: number? } = {}
local lastRejectedRequestAtByUserId: { [number]: number? } = {}
local rescueAccelerationExpiresAtByUserId: { [number]: number? } = {}

local postRescueProtectedAttributeName = RescueContractConfig.StateAttributes.PostRescueProtected
	or "PostRescueProtected"
local postRescueProtectionExpiresAtAttributeName = RescueContractConfig.StateAttributes.PostRescueProtectionExpiresAt
	or "PostRescueProtectionExpiresAt"
local rescueAccelerationActiveAttributeName = RescueContractConfig.StateAttributes.RescueAccelerationActive
	or "RescueAccelerationActive"
local rescueAccelerationExpiresAtAttributeName = RescueContractConfig.StateAttributes.RescueAccelerationExpiresAt
	or "RescueAccelerationExpiresAt"

local function now(): number
	return os.clock()
end

local function clearPostRescueProtection(player: Player?)
	if player == nil then
		return
	end

	player:SetAttribute(postRescueProtectedAttributeName, false)
	player:SetAttribute(postRescueProtectionExpiresAtAttributeName, nil)
end

local function clearRescueAcceleration(player: Player?)
	if player == nil then
		return
	end

	rescueAccelerationExpiresAtByUserId[player.UserId] = nil
	player:SetAttribute(rescueAccelerationActiveAttributeName, false)
	player:SetAttribute(rescueAccelerationExpiresAtAttributeName, nil)
end

local function grantRescueAcceleration(player: Player?, at: number)
	if player == nil then
		return
	end

	local durationSeconds = RescueContractConfig.RescueAccelerationDurationSeconds
	if type(durationSeconds) ~= "number" or durationSeconds <= 0 then
		clearRescueAcceleration(player)
		return
	end

	local expiresAt = at + durationSeconds
	rescueAccelerationExpiresAtByUserId[player.UserId] = expiresAt
	player:SetAttribute(rescueAccelerationActiveAttributeName, true)
	player:SetAttribute(rescueAccelerationExpiresAtAttributeName, expiresAt)
end

local function pruneExpiredRescueAcceleration(at: number)
	for _, player in Players:GetPlayers() do
		local expiresAt = rescueAccelerationExpiresAtByUserId[player.UserId]
		if type(expiresAt) == "number" then
			if expiresAt <= at then
				clearRescueAcceleration(player)
			else
				player:SetAttribute(rescueAccelerationActiveAttributeName, true)
				player:SetAttribute(rescueAccelerationExpiresAtAttributeName, expiresAt)
			end
		elseif player:GetAttribute(rescueAccelerationActiveAttributeName) == true then
			clearRescueAcceleration(player)
		end
	end
end

local function isRescueAccelerationActive(player: Player, at: number): boolean
	local expiresAt = rescueAccelerationExpiresAtByUserId[player.UserId]
	if type(expiresAt) ~= "number" then
		clearRescueAcceleration(player)
		return false
	end

	if expiresAt <= at then
		clearRescueAcceleration(player)
		return false
	end

	player:SetAttribute(rescueAccelerationActiveAttributeName, true)
	player:SetAttribute(rescueAccelerationExpiresAtAttributeName, expiresAt)
	return true
end

local function grantPostRescueProtection(player: Player?, at: number)
	if player == nil then
		return
	end

	local durationSeconds = RescueContractConfig.PostRescueProtectionSeconds
	if type(durationSeconds) ~= "number" or durationSeconds <= 0 then
		clearPostRescueProtection(player)
		return
	end

	player:SetAttribute(postRescueProtectedAttributeName, true)
	player:SetAttribute(postRescueProtectionExpiresAtAttributeName, at + durationSeconds)
end

local function pruneExpiredPostRescueProtection(at: number)
	for _, player in Players:GetPlayers() do
		if player:GetAttribute(postRescueProtectedAttributeName) == true then
			local expiresAt = player:GetAttribute(postRescueProtectionExpiresAtAttributeName)
			if type(expiresAt) ~= "number" or expiresAt <= at then
				clearPostRescueProtection(player)
			end
		end
	end
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

local function isPlayerAlive(player: Player): boolean
	local humanoid = getHumanoid(player)
	if humanoid == nil then
		return false
	end

	return humanoid.Health > 0
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

local function getRoleServiceQueryApi(): any?
	local globalValue: any = _G
	if type(globalValue) ~= "table" then
		return nil
	end

	local queryApi = globalValue._RoleService_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end

	return queryApi
end

local function getGrabServiceQueryApi(): any?
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

local function getScoreServiceQueryApi(): any?
	local globalValue: any = _G
	if type(globalValue) ~= "table" then
		return nil
	end

	local queryApi = globalValue._ScoreService_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end

	return queryApi
end

local function getEscapeServiceQueryApi(): any?
	local globalValue: any = _G
	if type(globalValue) ~= "table" then
		return nil
	end

	local queryApi = globalValue._EscapeService_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end

	return queryApi
end

local function evaluateTargetSafeZoneProtection(target: Player, at: number): boolean
	local safeZoneState = target:GetAttribute(EscapeConfig.SafeZoneAttribute) == true
	local safeZoneType = target:GetAttribute(EscapeConfig.SafeZoneTypeAttribute)
	local safeZoneProtectionEndsAt = target:GetAttribute(EscapeConfig.SafeZoneProtectionEndsAtAttribute)
	local safeZoneDecision = SafeZonePolicy.EvaluateProtection(EscapeConfig, {
		safeZoneState = safeZoneState,
		safeZoneType = safeZoneType,
		safeZoneProtectionEndsAt = safeZoneProtectionEndsAt,
		now = at,
	})

	return safeZoneDecision.protected == true
end

local function isInRange(rescuer: Player, target: Player): boolean
	local rescuerRoot = getHumanoidRootPart(rescuer)
	local targetRoot = getHumanoidRootPart(target)
	if rescuerRoot == nil or targetRoot == nil then
		return false
	end
	local rescuerRootPart = rescuerRoot :: BasePart
	local targetRootPart = targetRoot :: BasePart

	local delta = (rescuerRootPart.Position - targetRootPart.Position)
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

	return magnitude <= RescueContractConfig.TriggerRadiusStuds
end

local function isCoolingDown(userId: number, at: number): boolean
	local last = lastRequestAtByUserId[userId]
	if last == nil then
		return false
	end

	return (at - last) < RescueContractConfig.RequestCooldownSeconds
end

local function markRequest(userId: number, at: number)
	lastRequestAtByUserId[userId] = at
end

local function isRejectCoolingDown(userId: number, at: number): boolean
	local rejectCooldown = RescueContractConfig.RejectRequestCooldownSeconds
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

local function getDownedState(target: Player): boolean
	local roleQueryApi = getRoleServiceQueryApi()
	if roleQueryApi ~= nil and type(roleQueryApi.IsPlayerDowned) == "function" then
		return roleQueryApi.IsPlayerDowned(target.UserId) == true
	end

	return target:GetAttribute("DownedIsDowned") == true
end

local function isRescuerInteractionRestricted(rescuer: Player): boolean
	local roleQueryApi = getRoleServiceQueryApi()
	if roleQueryApi == nil then
		return false
	end

	if type(roleQueryApi.IsPlayerDowned) == "function" then
		if roleQueryApi.IsPlayerDowned(rescuer.UserId) == true then
			return true
		end
	end

	if type(roleQueryApi.CanPlayerPerformInteraction) == "function" then
		if roleQueryApi.CanPlayerPerformInteraction(rescuer.UserId, "rescueContractRequest") ~= true then
			return true
		end
	end

	return false
end

local function getCarriedState(target: Player): boolean
	local grabQueryApi = getGrabServiceQueryApi()
	if grabQueryApi ~= nil and type(grabQueryApi.IsPlayerCarried) == "function" then
		return grabQueryApi.IsPlayerCarried(target.UserId) == true
	end

	return false
end

local function readTargetRealmOwnerUserId(target: Player): number?
	local attributeName = RescueContractConfig.TargetRealmOwnerUserIdAttribute
	if type(attributeName) == "string" and attributeName ~= "" then
		local value = target:GetAttribute(attributeName)
		if type(value) == "number" and value > 0 and value % 1 == 0 then
			return value
		end
	end

	local fallbackValue = target:GetAttribute("RealmOwnerUserId")
	if type(fallbackValue) == "number" and fallbackValue > 0 and fallbackValue % 1 == 0 then
		return fallbackValue
	end

	return nil
end

local function resolveRescueEntryRoute(targetUserId: number, targetRealmOwnerUserId: number): (boolean, string, string?, string?)
	local escapeQueryApi = getEscapeServiceQueryApi()
	if escapeQueryApi == nil or type(escapeQueryApi.ResolveRescueEntryRoute) ~= "function" then
		return false, "rescue_entry_route_missing", nil, nil
	end

	local ok, result = pcall(function()
		return escapeQueryApi.ResolveRescueEntryRoute(targetUserId, targetRealmOwnerUserId)
	end)
	if not ok then
		return false, "rescue_entry_route_failed", nil, nil
	end

	if type(result) == "string" and result ~= "" then
		return true, "accepted", result, RescueContractConfig.RescueEntryRouteKind
	end

	if type(result) ~= "table" then
		return false, "rescue_entry_route_missing", nil, nil
	end

	local resultTable = result :: any
	if resultTable.accepted ~= true then
		local reason = if type(resultTable.reason) == "string" and resultTable.reason ~= ""
			then resultTable.reason
			else "rescue_entry_route_missing"
		return false, reason, nil, nil
	end

	if type(resultTable.routeId) ~= "string" or resultTable.routeId == "" then
		return false, "rescue_entry_route_id_invalid", nil, nil
	end

	local routeKind = if type(resultTable.routeKind) == "string" and resultTable.routeKind ~= ""
		then resultTable.routeKind
		else RescueContractConfig.RescueEntryRouteKind
	if type(routeKind) ~= "string" or routeKind == "" then
		return false, "rescue_entry_route_kind_invalid", nil, nil
	end

	return true, "accepted", resultTable.routeId, routeKind
end

local function applyContractAttributesFromState()
	local attrs = RescueContractConfig.StateAttributes

	for _, player in Players:GetPlayers() do
		player:SetAttribute(attrs.RescueActive, false)
		player:SetAttribute(attrs.RescueTargetUserId, nil)
		player:SetAttribute(attrs.RescueRescuerUserId, nil)
		player:SetAttribute(attrs.RescueTargetRealmOwnerUserId, nil)
		player:SetAttribute(attrs.RescueEntryRouteId, nil)
		player:SetAttribute(attrs.RescueEntryRouteKind, nil)
		player:SetAttribute(attrs.RescueExpiresAt, nil)
	end

	local contracts = RescueContractState.GetContracts(state)
	for _, contract in ipairs(contracts) do
		local rescuer = getPlayerByUserId(contract.rescuerUserId)
		if rescuer ~= nil then
			rescuer:SetAttribute(attrs.RescueActive, true)
			rescuer:SetAttribute(attrs.RescueTargetUserId, contract.targetUserId)
			rescuer:SetAttribute(attrs.RescueTargetRealmOwnerUserId, contract.targetRealmOwnerUserId)
			rescuer:SetAttribute(attrs.RescueEntryRouteId, contract.entryRouteId)
			rescuer:SetAttribute(attrs.RescueEntryRouteKind, contract.entryRouteKind)
			rescuer:SetAttribute(attrs.RescueExpiresAt, contract.expiresAt)
		end

		local target = getPlayerByUserId(contract.targetUserId)
		if target ~= nil then
			target:SetAttribute(attrs.RescueActive, true)
			target:SetAttribute(attrs.RescueRescuerUserId, contract.rescuerUserId)
			target:SetAttribute(attrs.RescueTargetRealmOwnerUserId, contract.targetRealmOwnerUserId)
			target:SetAttribute(attrs.RescueEntryRouteId, contract.entryRouteId)
			target:SetAttribute(attrs.RescueEntryRouteKind, contract.entryRouteKind)
			target:SetAttribute(attrs.RescueExpiresAt, contract.expiresAt)
		end
	end
end

local function pruneExpiredContracts(at: number)
	state = RescueContractState.PruneExpired(state, at)
	applyContractAttributesFromState()
end

local function setRescueLastReason(player: Player?, reason: string)
	if player == nil then
		return
	end

	local attrs = RescueContractConfig.StateAttributes
	player:SetAttribute(attrs.RescueLastReason, reason)
end

local function requestRescueContract(rescuer: Player, targetUserId: any, at: number?): any
	local resolvedNow = if type(at) == "number" then at else now()
	pruneExpiredRescueAcceleration(resolvedNow)
	pruneExpiredPostRescueProtection(resolvedNow)
	pruneExpiredContracts(resolvedNow)

	if isCoolingDown(rescuer.UserId, resolvedNow) then
		setRescueLastReason(rescuer, "request_cooldown")
		return { accepted = false, reason = "request_cooldown" }
	end

	if isRejectCoolingDown(rescuer.UserId, resolvedNow) then
		setRescueLastReason(rescuer, "request_cooldown")
		return { accepted = false, reason = "request_cooldown" }
	end

	if type(targetUserId) ~= "number" then
		markRejectedRequest(rescuer.UserId, resolvedNow)
		setRescueLastReason(rescuer, "target_user_id_invalid")
		return { accepted = false, reason = "target_user_id_invalid" }
	end

	local target = getPlayerByUserId(targetUserId)
	if target == nil then
		markRejectedRequest(rescuer.UserId, resolvedNow)
		setRescueLastReason(rescuer, "target_not_found")
		return { accepted = false, reason = "target_not_found" }
	end

	if isRescuerInteractionRestricted(rescuer) then
		markRejectedRequest(rescuer.UserId, resolvedNow)
		setRescueLastReason(rescuer, "rescuer_interaction_restricted")
		setRescueLastReason(target, "rescuer_interaction_restricted")
		return { accepted = false, reason = "rescuer_interaction_restricted" }
	end

	local accelerationActive = isRescueAccelerationActive(rescuer, resolvedNow)
	local requestInput: any = {
		now = resolvedNow,
		rescuerUserId = rescuer.UserId,
		targetUserId = targetUserId,
		rescuerRole = rescuer:GetAttribute(ROLE_ATTRIBUTE),
		targetRole = target:GetAttribute(ROLE_ATTRIBUTE),
		rescuerAlive = isPlayerAlive(rescuer),
		targetDowned = getDownedState(target),
		targetCarried = getCarriedState(target),
		targetProtected = evaluateTargetSafeZoneProtection(target, resolvedNow),
		inRange = isInRange(rescuer, target),
		targetRealmOwnerUserId = 1,
		entryRouteId = "__preflight_rescue_entry_route__",
		entryRouteKind = "__preflight_rescue_entry_route__",
		rescueWindowSeconds = RescueContractConfig.RescueWindowSeconds,
		accelerationActive = accelerationActive,
		accelerationWindowBonusSeconds = RescueContractConfig.RescueAccelerationWindowBonusSeconds,
	}

	local preflight = RescueContractState.ResolveRequest(state, requestInput)
	if not preflight.accepted then
		state = preflight.state
		setRescueLastReason(rescuer, preflight.reason)
		setRescueLastReason(target, preflight.reason)
		markRejectedRequest(rescuer.UserId, resolvedNow)
		applyContractAttributesFromState()
		return {
			accepted = false,
			reason = preflight.reason,
		}
	end

	local targetRealmOwnerUserId = readTargetRealmOwnerUserId(target)
	if targetRealmOwnerUserId == nil then
		markRejectedRequest(rescuer.UserId, resolvedNow)
		setRescueLastReason(rescuer, "target_realm_owner_user_id_invalid")
		setRescueLastReason(target, "target_realm_owner_user_id_invalid")
		return { accepted = false, reason = "target_realm_owner_user_id_invalid" }
	end

	local routeAccepted, routeReason, entryRouteId, entryRouteKind =
		resolveRescueEntryRoute(targetUserId, targetRealmOwnerUserId)
	if not routeAccepted then
		markRejectedRequest(rescuer.UserId, resolvedNow)
		setRescueLastReason(rescuer, routeReason)
		setRescueLastReason(target, routeReason)
		return { accepted = false, reason = routeReason }
	end

	requestInput.targetRealmOwnerUserId = targetRealmOwnerUserId
	requestInput.entryRouteId = entryRouteId
	requestInput.entryRouteKind = entryRouteKind
	local transition = RescueContractState.ResolveRequest(state, requestInput)

	state = transition.state
	setRescueLastReason(rescuer, transition.reason)
	setRescueLastReason(target, transition.reason)
	if transition.accepted then
		if accelerationActive then
			clearRescueAcceleration(rescuer)
		end
		markRequest(rescuer.UserId, resolvedNow)
	else
		markRejectedRequest(rescuer.UserId, resolvedNow)
	end
	applyContractAttributesFromState()

	return {
		accepted = transition.accepted,
		reason = transition.reason,
		contract = transition.contract,
	}
end

local function completeRescueContract(rescuer: Player, targetUserId: any, at: number?): any
	local resolvedNow = if type(at) == "number" then at else now()
	pruneExpiredRescueAcceleration(resolvedNow)
	pruneExpiredPostRescueProtection(resolvedNow)
	pruneExpiredContracts(resolvedNow)

	if type(targetUserId) ~= "number" then
		return { accepted = false, reason = "target_user_id_invalid" }
	end

	local transition = RescueContractState.ResolveComplete(state, {
		now = resolvedNow,
		rescuerUserId = rescuer.UserId,
		targetUserId = targetUserId,
	})

	state = transition.state
	setRescueLastReason(rescuer, transition.reason)
	local target = getPlayerByUserId(targetUserId)
	setRescueLastReason(target, transition.reason)

	if transition.accepted then
		grantPostRescueProtection(target, resolvedNow)
		grantRescueAcceleration(rescuer, resolvedNow)
		local scoreApi = getScoreServiceQueryApi()
		if scoreApi ~= nil and type(scoreApi.RequestScoreEvent) == "function" then
			local contract = transition.contract
			scoreApi.RequestScoreEvent(rescuer.UserId, "rescue_complete", resolvedNow, {
				targetUserId = targetUserId,
				targetRealmOwnerUserId = if contract ~= nil then contract.targetRealmOwnerUserId else nil,
				entryRouteId = if contract ~= nil then contract.entryRouteId else nil,
				entryRouteKind = if contract ~= nil then contract.entryRouteKind else nil,
			})
		end
	end

	applyContractAttributesFromState()

	return {
		accepted = transition.accepted,
		reason = transition.reason,
		contract = transition.contract,
	}
end

local remotesFolder = ensureRemotesFolder()
local requestRemote = ensureRemoteEvent(remotesFolder, REQUEST_REMOTE_NAME)
local responseRemote = ensureRemoteEvent(remotesFolder, RESPONSE_REMOTE_NAME)
local completeRemote = ensureRemoteEvent(remotesFolder, COMPLETE_REMOTE_NAME)

requestRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	local targetUserId = nil
	if type(payload) == "number" then
		targetUserId = payload
	elseif type(payload) == "table" then
		targetUserId = (payload :: any).targetUserId
	end

	local result = requestRescueContract(player, targetUserId, nil)
	responseRemote:FireClient(player, result)
end)

completeRemote.OnServerEvent:Connect(function(player: Player, payload: unknown)
	local targetUserId = nil
	if type(payload) == "number" then
		targetUserId = payload
	elseif type(payload) == "table" then
		targetUserId = (payload :: any).targetUserId
	end

	local result = completeRescueContract(player, targetUserId, nil)
	responseRemote:FireClient(player, result)
end)

Players.PlayerRemoving:Connect(function(player: Player)
	lastRequestAtByUserId[player.UserId] = nil
	lastRejectedRequestAtByUserId[player.UserId] = nil
	clearRescueAcceleration(player)
	clearPostRescueProtection(player)
	state = RescueContractState.RemovePlayer(state, player.UserId)
	applyContractAttributesFromState()
end)

_G._RescueContractService_QueryAPI = {
	RequestRescueContract = function(rescuerUserId: number, targetUserId: number, at: number?): any
		local rescuer = getPlayerByUserId(rescuerUserId)
		if rescuer == nil then
			return { accepted = false, reason = "rescuer_not_found" }
		end
		return requestRescueContract(rescuer, targetUserId, at)
	end,
	CompleteRescueContract = function(rescuerUserId: number, targetUserId: number, at: number?): any
		local rescuer = getPlayerByUserId(rescuerUserId)
		if rescuer == nil then
			return { accepted = false, reason = "rescuer_not_found" }
		end
		return completeRescueContract(rescuer, targetUserId, at)
	end,
	GetRescuerContract = function(rescuerUserId: number, at: number?): any
		if type(at) == "number" then
			pruneExpiredRescueAcceleration(at)
			pruneExpiredPostRescueProtection(at)
			pruneExpiredContracts(at)
		end
		return RescueContractState.GetRescuerContract(state, rescuerUserId)
	end,
	GetAllContracts = function(at: number?): { any }
		if type(at) == "number" then
			pruneExpiredRescueAcceleration(at)
			pruneExpiredPostRescueProtection(at)
			pruneExpiredContracts(at)
		end
		return RescueContractState.GetContracts(state)
	end,
	ResetForTests = function()
		state = RescueContractState.NewState()
		lastRequestAtByUserId = {}
		lastRejectedRequestAtByUserId = {}
		rescueAccelerationExpiresAtByUserId = {}
		for _, player in Players:GetPlayers() do
			clearRescueAcceleration(player)
			clearPostRescueProtection(player)
		end
		applyContractAttributesFromState()
	end,
}
