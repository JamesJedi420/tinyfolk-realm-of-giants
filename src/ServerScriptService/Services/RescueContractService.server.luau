--!nocheck
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GiantRealm = Shared:WaitForChild("GiantRealm")

local EscapeConfig = require(Config:WaitForChild("EscapeConfig"))
local RescueContractConfig = require(Config:WaitForChild("RescueContractConfig"))
local SafeZonePolicy = require(GiantRealm:WaitForChild("SafeZonePolicy"))
local RescueContractState = require(GiantRealm:WaitForChild("RescueContractState"))
local RescueContractQueueState = require(GiantRealm:WaitForChild("RescueContractQueueState"))
local GiantRealmSaveSchema = require(GiantRealm:WaitForChild("GiantRealmSaveSchema"))
local AdmissionQueueProducer = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("AdmissionQueueProducer"))
	else (require :: any)("./AdmissionQueueProducer")
local MemoryStoreAdapter = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("MemoryStoreAdapter"))
	else (require :: any)("./MemoryStoreAdapter")
local MemoryStoreStructurePolicy = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("MemoryStoreStructurePolicy"))
	else (require :: any)("./MemoryStoreStructurePolicy")
local QueueProcessingIdempotencyStore = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("QueueProcessingIdempotencyStore"))
	else (require :: any)("./QueueProcessingIdempotencyStore")
local QueueNotificationFanout = if script ~= nil and script.Parent ~= nil
	then require(script.Parent:WaitForChild("QueueNotificationFanout"))
	else (require :: any)("./QueueNotificationFanout")

local REMOTES_FOLDER_NAME = "Remotes"
local REQUEST_REMOTE_NAME = "RescueContractRequest"
local RESPONSE_REMOTE_NAME = "RescueContractResponse"
local COMPLETE_REMOTE_NAME = "RescueContractCompleteRequest"

local ROLE_ATTRIBUTE = "Role"
local globalEnv: any = getfenv()

local state = RescueContractState.NewState()
local rescueQueueState = RescueContractQueueState.NewState()
local lastRequestAtByUserId: { [number]: number? } = {}
local lastRejectedRequestAtByUserId: { [number]: number? } = {}
local rescueAccelerationExpiresAtByUserId: { [number]: number? } = {}
local nextQueueSequence = 0
local rescueQueueIdempotencyStore: any = nil
local admissionIngressDiagnostics = {
	totalAttempts = 0,
	primaryAttempts = 0,
	primarySucceeded = 0,
	primaryFailed = 0,
	fallbackAttempts = 0,
	fallbackSucceeded = 0,
	fallbackFailed = 0,
	lastPath = "not_started",
	lastReason = "not_started",
	lastPrimaryReason = "not_started",
	lastFallbackReason = "not_started",
}

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
	local globalValue: any = globalEnv
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
	local globalValue: any = globalEnv
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
	local globalValue: any = globalEnv
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
	local globalValue: any = globalEnv
	if type(globalValue) ~= "table" then
		return nil
	end

	local queryApi = globalValue._EscapeService_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end

	return queryApi
end

local function getRescueHandoffQueryApi(): any?
	local globalValue: any = globalEnv
	if type(globalValue) ~= "table" then
		return nil
	end

	local queryApi = globalValue._RescueHandoffService_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end

	return queryApi
end

local function getQueueNotificationFanoutQueryApi(): any?
	local globalValue: any = globalEnv
	if type(globalValue) ~= "table" then
		return nil
	end

	local queryApi = globalValue._QueueNotificationFanout_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end

	return queryApi
end

local function getRealmAdmissionQueueQueryApi(): any?
	local globalValue: any = globalEnv
	if type(globalValue) ~= "table" then
		return nil
	end

	local queryApi = globalValue._RealmAdmissionQueue_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end

	return queryApi
end

local function makeRescueQueueOperationId(queueEntryId: any): string?
	if type(queueEntryId) ~= "string" or queueEntryId == "" then
		return nil
	end
	return string.format("rescue_accept_%s", queueEntryId)
end

local function makeLocalIdempotencyAdapter(): any
	local valuesByMap: { [string]: { [string]: any } } = {}
	return {
		HashMapUpdateAsync = function(mapName: string, key: string, transform: (any) -> any, _ttlSeconds: number)
			if valuesByMap[mapName] == nil then
				valuesByMap[mapName] = {}
			end
			local nextValue = transform(valuesByMap[mapName][key])
			valuesByMap[mapName][key] = nextValue
			return nextValue
		end,
	}
end

local function getMemoryStoreAdapter(): any?
	local fromEnv = rawget(globalEnv, "_MemoryStoreAdapter_QueryAPI")
	if type(fromEnv) == "table" then
		return fromEnv
	end
	if type(_G) == "table" then
		local fromGlobal = rawget(_G, "_MemoryStoreAdapter_QueryAPI")
		if type(fromGlobal) == "table" then
			return fromGlobal
		end
	end

	local activeCapacityPolicy = MemoryStoreStructurePolicy.GetPolicy("activeRealmCapacity")
	local mapName = if type(activeCapacityPolicy) == "table" then activeCapacityPolicy.name else nil
	return MemoryStoreAdapter.CreateDefault({
		activeRealmCapacityMapName = mapName,
	})
end

local function getRescueQueueIdempotencyStore(): any
	if rescueQueueIdempotencyStore ~= nil then
		return rescueQueueIdempotencyStore
	end

	local adapter = getMemoryStoreAdapter()
	if adapter == nil then
		adapter = makeLocalIdempotencyAdapter()
	end
	rescueQueueIdempotencyStore = QueueProcessingIdempotencyStore.Create({
		adapter = adapter,
		structurePolicy = MemoryStoreStructurePolicy,
		now = now,
	})
	return rescueQueueIdempotencyStore
end

local function tryBeginRescueQueueOperation(operationId: any): any
	local store = getRescueQueueIdempotencyStore()
	if type(store) ~= "table" or type(store.TryBegin) ~= "function" then
		return { accepted = false, reason = "idempotency_store_unavailable" }
	end
	local ok, result = pcall(store.TryBegin, operationId)
	if not ok or type(result) ~= "table" then
		return { accepted = false, reason = "idempotency_try_begin_failed" }
	end
	return result
end

local function markRescueQueueOperationCompleted(operationId: any): boolean
	local store = getRescueQueueIdempotencyStore()
	if type(store) ~= "table" or type(store.MarkCompleted) ~= "function" then
		return false
	end
	local ok, result = pcall(store.MarkCompleted, operationId)
	return ok and type(result) == "table" and result.accepted == true
end

local function releaseRescueQueueOperation(operationId: any)
	local store = getRescueQueueIdempotencyStore()
	if type(store) ~= "table" or type(store.ReleaseProcessing) ~= "function" then
		return
	end
	pcall(store.ReleaseProcessing, operationId)
end

local function getRescueAdmissionQueryApi(): any?
	local globalValue: any = globalEnv
	if type(globalValue) ~= "table" then
		return nil
	end

	local queryApi = globalValue._RescueAdmissionService_QueryAPI
	if type(queryApi) ~= "table" then
		return nil
	end

	return queryApi
end

local admissionQueueProducer = AdmissionQueueProducer.Create({
	queryApiResolver = function()
		return getRealmAdmissionQueueQueryApi()
	end,
})

local function requestRescueContractAdmission(payload: any): any
	admissionIngressDiagnostics.totalAttempts += 1
	local queryApi = getRescueAdmissionQueryApi()
	if queryApi ~= nil and type(queryApi.RequestRescueContractAdmission) == "function" then
		admissionIngressDiagnostics.primaryAttempts += 1
		local ok, result = pcall(function()
			return queryApi.RequestRescueContractAdmission(payload)
		end)
		if not ok then
			admissionIngressDiagnostics.primaryFailed += 1
			admissionIngressDiagnostics.lastPath = "primary"
			admissionIngressDiagnostics.lastReason = "admission_enqueue_failed"
			admissionIngressDiagnostics.lastPrimaryReason = "admission_enqueue_failed"
			return { accepted = false, reason = "admission_enqueue_failed" }
		end
		if type(result) ~= "table" then
			admissionIngressDiagnostics.primaryFailed += 1
			admissionIngressDiagnostics.lastPath = "primary"
			admissionIngressDiagnostics.lastReason = "admission_enqueue_failed"
			admissionIngressDiagnostics.lastPrimaryReason = "admission_enqueue_failed"
			return { accepted = false, reason = "admission_enqueue_failed" }
		end
		if result.accepted == true then
			admissionIngressDiagnostics.primarySucceeded += 1
			admissionIngressDiagnostics.lastPath = "primary"
			admissionIngressDiagnostics.lastReason = "accepted"
			admissionIngressDiagnostics.lastPrimaryReason = "accepted"
			return { accepted = true, reason = "accepted" }
		end
		local reason = if type(result.reason) == "string" and result.reason ~= ""
			then result.reason
			else "admission_enqueue_failed"
		admissionIngressDiagnostics.primaryFailed += 1
		admissionIngressDiagnostics.lastPath = "primary"
		admissionIngressDiagnostics.lastReason = reason
		admissionIngressDiagnostics.lastPrimaryReason = reason
		return { accepted = false, reason = reason }
	end

	admissionIngressDiagnostics.fallbackAttempts += 1
	local fallbackResult = admissionQueueProducer.Enqueue(payload)
	if fallbackResult.accepted == true then
		admissionIngressDiagnostics.fallbackSucceeded += 1
		admissionIngressDiagnostics.lastPath = "fallback"
		admissionIngressDiagnostics.lastReason = "accepted"
		admissionIngressDiagnostics.lastFallbackReason = "accepted"
	else
		admissionIngressDiagnostics.fallbackFailed += 1
		admissionIngressDiagnostics.lastPath = "fallback"
		admissionIngressDiagnostics.lastReason = if type(fallbackResult.reason) == "string"
			then fallbackResult.reason
			else "admission_enqueue_failed"
		admissionIngressDiagnostics.lastFallbackReason = admissionIngressDiagnostics.lastReason
	end

	return fallbackResult
end

local defaultQueueNotificationFanout = QueueNotificationFanout.CreateDefault()

local function emitRescueQueueFanout(eventName: string, payload: any)
	local fanout = getQueueNotificationFanoutQueryApi()
	if fanout == nil then
		fanout = defaultQueueNotificationFanout
	end
	if fanout == nil or type(fanout.PublishRescue) ~= "function" then
		return
	end

	pcall(fanout.PublishRescue, eventName, payload)
end

local function buildAdmissionPartyMemberUserIds(queueEntry: any, acceptedByUserId: number): { number }
	local members: { number } = {}
	local seen: { [number]: boolean } = {}

	local function append(userId: any)
		if type(userId) ~= "number" or userId <= 0 or userId % 1 ~= 0 then
			return
		end
		if seen[userId] == true then
			return
		end
		seen[userId] = true
		table.insert(members, userId)
	end

	append(queueEntry.rescuerUserId)
	append(queueEntry.capturedUserId)
	append(acceptedByUserId)

	table.sort(members)
	return members
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

local function resolveRescueEntryRoute(
	targetUserId: number,
	targetRealmOwnerUserId: number
): (boolean, string, string?, string?)
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

local function pruneExpiredQueueEntries(at: number)
	local expiredEntries
	rescueQueueState, expiredEntries = RescueContractQueueState.PruneExpired(rescueQueueState, at)
	if #expiredEntries <= 0 then
		return
	end

	local handoffApi = getRescueHandoffQueryApi()
	local hasHandoffExpiryHook = handoffApi ~= nil and type(handoffApi.OnRescueQueueExpired) == "function"

	for _, expiredEntry in ipairs(expiredEntries) do
		emitRescueQueueFanout("rescue_queue_expired", {
			queueEntryId = expiredEntry.queueEntryId,
			capturedUserId = expiredEntry.capturedUserId,
			realmId = expiredEntry.realmId,
			sessionId = expiredEntry.sessionId,
			resolvedReason = "expired",
			at = at,
		})

		if hasHandoffExpiryHook then
			pcall(function()
				handoffApi.OnRescueQueueExpired({
					queueEntryId = expiredEntry.queueEntryId,
					capturedUserId = expiredEntry.capturedUserId,
					realmId = expiredEntry.realmId,
					sessionId = expiredEntry.sessionId,
					reason = "expired",
					at = at,
				})
			end)
		end
	end
end

local function readTargetRealmId(target: Player, targetRealmOwnerUserId: number): string
	local attributeName = RescueContractConfig.TargetRealmIdAttribute
	if type(attributeName) == "string" and attributeName ~= "" then
		local value = target:GetAttribute(attributeName)
		if type(value) == "string" and value ~= "" then
			return value
		end
	end

	return string.format("giant_realm_%d", targetRealmOwnerUserId)
end

local function readQueueSequence(queueEntryId: any): number?
	if type(queueEntryId) ~= "string" or queueEntryId == "" then
		return nil
	end

	local sequenceText = string.match(queueEntryId, "_(%d+)$")
	if sequenceText == nil then
		return nil
	end

	local sequenceValue = tonumber(sequenceText)
	if type(sequenceValue) ~= "number" or sequenceValue <= 0 or sequenceValue % 1 ~= 0 then
		return nil
	end

	return sequenceValue
end

local function makeQueueEntryId(rescuerUserId: number, targetUserId: number, at: number): string
	local atMillis = math.floor(at * 1000)
	while true do
		nextQueueSequence += 1
		local queueEntryId =
			string.format("rescue_queue_%d_%d_%d_%d", rescuerUserId, targetUserId, atMillis, nextQueueSequence)
		if rescueQueueState.entriesById[queueEntryId] == nil then
			return queueEntryId
		end
	end
end

local function publishRescueQueueEntry(contract: any, target: Player?, at: number)
	if type(contract) ~= "table" then
		return
	end

	local targetRealmOwnerUserId = contract.targetRealmOwnerUserId
	if type(targetRealmOwnerUserId) ~= "number" then
		return
	end

	local queueRewardHint = RescueContractConfig.QueueRewardHint
	if type(queueRewardHint) ~= "string" or queueRewardHint == "" then
		queueRewardHint = "rescue_contract"
	end

	local queueDangerRating = RescueContractConfig.QueueDangerRating
	if type(queueDangerRating) ~= "number" or queueDangerRating ~= queueDangerRating then
		queueDangerRating = 0.5
	end
	if queueDangerRating < 0 then
		queueDangerRating = 0
	elseif queueDangerRating > 1 then
		queueDangerRating = 1
	end

	local expiration = contract.expiresAt
	if
		type(expiration) ~= "number"
		or expiration ~= expiration
		or expiration == math.huge
		or expiration == -math.huge
	then
		local fallbackWindow = RescueContractConfig.RescueWindowSeconds
		if type(fallbackWindow) ~= "number" or fallbackWindow <= 0 then
			fallbackWindow = 0
		end
		expiration = at + fallbackWindow
	end

	local realmId = if target ~= nil
		then readTargetRealmId(target, targetRealmOwnerUserId)
		else string.format("giant_realm_%d", targetRealmOwnerUserId)

	local sessionId = game.JobId
	if type(sessionId) ~= "string" or sessionId == "" then
		sessionId = "local_session"
	end

	local queueEntryId = makeQueueEntryId(contract.rescuerUserId, contract.targetUserId, at)
	local queueEntry = {
		queueEntryId = queueEntryId,
		operationId = makeRescueQueueOperationId(queueEntryId),
		capturedUserId = contract.targetUserId,
		realmId = realmId,
		sessionId = sessionId,
		rewardHint = queueRewardHint,
		dangerRating = queueDangerRating,
		expiration = expiration,
		rescuerUserId = contract.rescuerUserId,
		targetRealmOwnerUserId = targetRealmOwnerUserId,
		entryRouteId = contract.entryRouteId,
		entryRouteKind = contract.entryRouteKind,
		createdAt = at,
		status = "pending",
	}

	rescueQueueState = RescueContractQueueState.UpsertPending(rescueQueueState, queueEntry)
	emitRescueQueueFanout("rescue_queue_published", {
		queueEntryId = queueEntry.queueEntryId,
		operationId = queueEntry.operationId,
		capturedUserId = queueEntry.capturedUserId,
		realmId = queueEntry.realmId,
		sessionId = queueEntry.sessionId,
		rescuerUserId = queueEntry.rescuerUserId,
		targetRealmOwnerUserId = queueEntry.targetRealmOwnerUserId,
		createdAt = queueEntry.createdAt,
		expiration = queueEntry.expiration,
	})
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
	pruneExpiredQueueEntries(at)
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
		publishRescueQueueEntry(transition.contract, target, resolvedNow)
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
		rescueQueueState = RescueContractQueueState.MarkResolvedByContract(
			rescueQueueState,
			rescuer.UserId,
			targetUserId,
			"rescued",
			resolvedNow
		)
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

local function acceptRescueQueueEntry(acceptedByUserId: any, queueEntryId: any, at: number?): any
	local resolvedNow = if type(at) == "number" then at else now()
	pruneExpiredRescueAcceleration(resolvedNow)
	pruneExpiredPostRescueProtection(resolvedNow)
	pruneExpiredContracts(resolvedNow)

	if type(acceptedByUserId) ~= "number" or acceptedByUserId <= 0 or acceptedByUserId % 1 ~= 0 then
		return { accepted = false, reason = "accepted_by_user_id_invalid" }
	end

	if type(queueEntryId) ~= "string" or queueEntryId == "" then
		return { accepted = false, reason = "queue_entry_id_invalid" }
	end

	local queueEntry = RescueContractQueueState.GetEntry(rescueQueueState, queueEntryId)
	if queueEntry == nil then
		return { accepted = false, reason = "queue_entry_missing" }
	end
	local operationId = if type(queueEntry.operationId) == "string" and queueEntry.operationId ~= ""
		then queueEntry.operationId
		else makeRescueQueueOperationId(queueEntry.queueEntryId)
	if type(operationId) ~= "string" or operationId == "" then
		return { accepted = false, reason = "operation_id_invalid" }
	end

	local beginResult = tryBeginRescueQueueOperation(operationId)
	if beginResult.accepted == true and beginResult.status == "completed" then
		return {
			accepted = true,
			reason = "duplicate_completed",
			queueEntry = queueEntry,
			duplicate = true,
		}
	end
	if beginResult.accepted ~= true then
		return {
			accepted = false,
			reason = if type(beginResult.reason) == "string" then beginResult.reason else "idempotency_rejected",
		}
	end
	if queueEntry.status ~= "pending" then
		releaseRescueQueueOperation(operationId)
		return { accepted = false, reason = "queue_entry_missing" }
	end

	local handoffApi = getRescueHandoffQueryApi()
	if handoffApi == nil or type(handoffApi.CreateHandoffLock) ~= "function" then
		releaseRescueQueueOperation(operationId)
		return { accepted = false, reason = "handoff_lock_unavailable" }
	end

	local lockOk, lockResult = pcall(function()
		return handoffApi.CreateHandoffLock({
			queueEntryId = queueEntry.queueEntryId,
			capturedUserId = queueEntry.capturedUserId,
			realmId = queueEntry.realmId,
			sessionId = queueEntry.sessionId,
			rewardHint = queueEntry.rewardHint,
			dangerRating = queueEntry.dangerRating,
			expiration = queueEntry.expiration,
			rescuerUserId = queueEntry.rescuerUserId,
			targetRealmOwnerUserId = queueEntry.targetRealmOwnerUserId,
			entryRouteId = queueEntry.entryRouteId,
			entryRouteKind = queueEntry.entryRouteKind,
			acceptedByUserId = acceptedByUserId,
			at = resolvedNow,
		})
	end)
	if not lockOk then
		releaseRescueQueueOperation(operationId)
		return { accepted = false, reason = "handoff_lock_failed" }
	end

	if type(lockResult) ~= "table" or lockResult.accepted ~= true then
		local rejectedReason = "handoff_lock_rejected"
		if type(lockResult) == "table" and type((lockResult :: any).reason) == "string" then
			rejectedReason = (lockResult :: any).reason
		end
		releaseRescueQueueOperation(operationId)
		return { accepted = false, reason = rejectedReason }
	end

	local currentQueueEntry = RescueContractQueueState.GetEntry(rescueQueueState, queueEntryId)
	if currentQueueEntry == nil or currentQueueEntry.status ~= "pending" then
		releaseRescueQueueOperation(operationId)
		return { accepted = false, reason = "queue_entry_not_pending" }
	end
	queueEntry = currentQueueEntry

	local admissionMemberUserIds = buildAdmissionPartyMemberUserIds(queueEntry, acceptedByUserId)
	if #admissionMemberUserIds <= 0 then
		releaseRescueQueueOperation(operationId)
		return { accepted = false, reason = "admission_party_members_invalid" }
	end

	local admissionPayload = {
		operationId = operationId,
		partyId = string.format("rescue_party_%s", queueEntry.queueEntryId),
		targetRealmId = queueEntry.realmId,
		entryType = "rescue_contract",
		createdAt = resolvedNow,
		expiration = queueEntry.expiration,
		partySize = #admissionMemberUserIds,
		partyMemberUserIds = admissionMemberUserIds,
		retryCount = 0,
	}

	local enqueueResult = requestRescueContractAdmission(admissionPayload)
	if enqueueResult.accepted ~= true then
		releaseRescueQueueOperation(operationId)
		return { accepted = false, reason = enqueueResult.reason }
	end

	local acceptedTransition: boolean? = nil
	rescueQueueState, queueEntry, acceptedTransition =
		RescueContractQueueState.MarkAccepted(rescueQueueState, queueEntryId, acceptedByUserId, resolvedNow)
	if acceptedTransition ~= true or queueEntry == nil or queueEntry.status ~= "accepted" then
		return { accepted = false, reason = "queue_entry_not_pending" }
	end

	if not markRescueQueueOperationCompleted(operationId) then
		return { accepted = false, reason = "idempotency_mark_completed_failed" }
	end

	emitRescueQueueFanout("rescue_queue_accepted", {
		queueEntryId = queueEntry.queueEntryId,
		operationId = queueEntry.operationId,
		capturedUserId = queueEntry.capturedUserId,
		realmId = queueEntry.realmId,
		sessionId = queueEntry.sessionId,
		acceptedByUserId = acceptedByUserId,
		acceptedAt = resolvedNow,
	})

	return {
		accepted = true,
		reason = "accepted",
		queueEntry = queueEntry,
	}
end

local function listRescueQueueEntriesForHub(limit: any, at: number?): { any }
	if type(at) == "number" then
		pruneExpiredRescueAcceleration(at)
		pruneExpiredPostRescueProtection(at)
		pruneExpiredContracts(at)
	end

	local entries = RescueContractQueueState.GetPendingEntries(rescueQueueState)
	if type(limit) ~= "number" or limit ~= limit or limit == math.huge or limit == -math.huge then
		return entries
	end

	local resolvedLimit = math.floor(limit)
	if resolvedLimit <= 0 then
		return {}
	end

	if #entries <= resolvedLimit then
		return entries
	end

	local limited: { any } = {}
	for index = 1, resolvedLimit do
		table.insert(limited, entries[index])
	end
	return limited
end

local function buildPersistenceState(): any
	local contracts = RescueContractState.GetContracts(state)
	local queueEntries: { any } = {}
	for _, entry in ipairs(RescueContractQueueState.GetEntries(rescueQueueState)) do
		table.insert(queueEntries, {
			queueEntryId = entry.queueEntryId,
			operationId = entry.operationId,
			capturedUserId = entry.capturedUserId,
			realmId = entry.realmId,
			sessionId = entry.sessionId,
			rewardHint = entry.rewardHint,
			dangerRating = entry.dangerRating,
			expiration = entry.expiration,
			rescuerUserId = entry.rescuerUserId,
			targetRealmOwnerUserId = entry.targetRealmOwnerUserId,
			entryRouteId = entry.entryRouteId,
			entryRouteKind = entry.entryRouteKind,
			createdAt = entry.createdAt,
			status = entry.status,
			acceptedAt = entry.acceptedAt,
			acceptedByUserId = entry.acceptedByUserId,
			resolvedAt = entry.resolvedAt,
			resolvedReason = entry.resolvedReason,
		})
	end

	return {
		contracts = contracts,
		queueEntries = queueEntries,
	}
end

local function applyPersistenceState(persistedState: any): (boolean, string?)
	local valid, reason = GiantRealmSaveSchema.ValidateRescuePersistenceRecord(persistedState)
	if not valid then
		return false, reason or "rescue_persistence_invalid"
	end

	lastRequestAtByUserId = {}
	lastRejectedRequestAtByUserId = {}
	rescueAccelerationExpiresAtByUserId = {}
	nextQueueSequence = 0

	for _, player in Players:GetPlayers() do
		clearRescueAcceleration(player)
		clearPostRescueProtection(player)
	end

	if persistedState == nil then
		state = RescueContractState.NewState()
		rescueQueueState = RescueContractQueueState.NewState()
		applyContractAttributesFromState()
		return true, nil
	end

	local nextContractsByRescuer: { [number]: any } = {}
	local nextRescuerByTarget: { [number]: number } = {}
	for _, contract in ipairs(persistedState.contracts) do
		local copiedContract = {
			rescuerUserId = contract.rescuerUserId,
			targetUserId = contract.targetUserId,
			targetRealmOwnerUserId = contract.targetRealmOwnerUserId,
			entryRouteId = contract.entryRouteId,
			entryRouteKind = contract.entryRouteKind,
			startedAt = contract.startedAt,
			expiresAt = contract.expiresAt,
			isAccelerated = contract.isAccelerated == true,
		}
		nextContractsByRescuer[copiedContract.rescuerUserId] = copiedContract
		nextRescuerByTarget[copiedContract.targetUserId] = copiedContract.rescuerUserId
	end

	state = {
		contractsByRescuer = nextContractsByRescuer,
		rescuerByTarget = nextRescuerByTarget,
		lastReason = nil,
	}

	local nextEntriesById: { [string]: any } = {}
	for _, entry in ipairs(persistedState.queueEntries) do
		local operationId = if type(entry.operationId) == "string" and entry.operationId ~= ""
			then entry.operationId
			else makeRescueQueueOperationId(entry.queueEntryId)
		nextEntriesById[entry.queueEntryId] = {
			queueEntryId = entry.queueEntryId,
			operationId = operationId,
			capturedUserId = entry.capturedUserId,
			realmId = entry.realmId,
			sessionId = entry.sessionId,
			rewardHint = entry.rewardHint,
			dangerRating = entry.dangerRating,
			expiration = entry.expiration,
			rescuerUserId = entry.rescuerUserId,
			targetRealmOwnerUserId = entry.targetRealmOwnerUserId,
			entryRouteId = entry.entryRouteId,
			entryRouteKind = entry.entryRouteKind,
			createdAt = entry.createdAt,
			status = entry.status,
			acceptedAt = entry.acceptedAt,
			acceptedByUserId = entry.acceptedByUserId,
			resolvedAt = entry.resolvedAt,
			resolvedReason = entry.resolvedReason,
		}

		local restoredSequence = readQueueSequence(entry.queueEntryId)
		if type(restoredSequence) == "number" and restoredSequence > nextQueueSequence then
			nextQueueSequence = restoredSequence
		end
	end

	rescueQueueState = {
		entriesById = nextEntriesById,
	}

	applyContractAttributesFromState()
	return true, nil
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
	rescueQueueState =
		RescueContractQueueState.MarkResolvedForParticipant(rescueQueueState, player.UserId, "player_left", now())
	applyContractAttributesFromState()
end)

globalEnv._RescueContractService_QueryAPI = {
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
	GetRescueQueueEntries = function(at: number?): { any }
		if type(at) == "number" then
			pruneExpiredRescueAcceleration(at)
			pruneExpiredPostRescueProtection(at)
			pruneExpiredContracts(at)
		end
		return RescueContractQueueState.GetPendingEntries(rescueQueueState)
	end,
	BuildPersistenceState = function(): any
		return buildPersistenceState()
	end,
	ApplyPersistenceState = function(persistedState: any): (boolean, string?)
		return applyPersistenceState(persistedState)
	end,
	AcceptRescueQueueEntry = function(acceptedByUserId: any, queueEntryId: any, at: number?): any
		return acceptRescueQueueEntry(acceptedByUserId, queueEntryId, at)
	end,
	GetAdmissionIngressDiagnostics = function(): any
		return {
			totalAttempts = admissionIngressDiagnostics.totalAttempts,
			primaryAttempts = admissionIngressDiagnostics.primaryAttempts,
			primarySucceeded = admissionIngressDiagnostics.primarySucceeded,
			primaryFailed = admissionIngressDiagnostics.primaryFailed,
			fallbackAttempts = admissionIngressDiagnostics.fallbackAttempts,
			fallbackSucceeded = admissionIngressDiagnostics.fallbackSucceeded,
			fallbackFailed = admissionIngressDiagnostics.fallbackFailed,
			lastPath = admissionIngressDiagnostics.lastPath,
			lastReason = admissionIngressDiagnostics.lastReason,
			lastPrimaryReason = admissionIngressDiagnostics.lastPrimaryReason,
			lastFallbackReason = admissionIngressDiagnostics.lastFallbackReason,
		}
	end,
	ResetForTests = function()
		state = RescueContractState.NewState()
		rescueQueueState = RescueContractQueueState.NewState()
		rescueQueueIdempotencyStore = nil
		nextQueueSequence = 0
		lastRequestAtByUserId = {}
		lastRejectedRequestAtByUserId = {}
		rescueAccelerationExpiresAtByUserId = {}
		admissionIngressDiagnostics = {
			totalAttempts = 0,
			primaryAttempts = 0,
			primarySucceeded = 0,
			primaryFailed = 0,
			fallbackAttempts = 0,
			fallbackSucceeded = 0,
			fallbackFailed = 0,
			lastPath = "not_started",
			lastReason = "not_started",
			lastPrimaryReason = "not_started",
			lastFallbackReason = "not_started",
		}
		for _, player in Players:GetPlayers() do
			clearRescueAcceleration(player)
			clearPostRescueProtection(player)
		end
		applyContractAttributesFromState()
	end,
}

globalEnv._RescueContractHubSurface_QueryAPI = {
	GetPendingRescueQueueEntries = function(limit: any, at: number?): { any }
		return listRescueQueueEntriesForHub(limit, at)
	end,
	AcceptRescueQueueEntry = function(acceptedByUserId: any, queueEntryId: any, at: number?): any
		return acceptRescueQueueEntry(acceptedByUserId, queueEntryId, at)
	end,
}
