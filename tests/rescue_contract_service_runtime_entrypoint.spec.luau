--!nocheck
--!nolint BuiltinGlobalWrite
-- selene: allow(global_usage)
local MockPlayer = require("../tests/mocks/MockPlayer")
local globalEnv: any = getfenv()

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(condition: boolean, label: string)
	assertEqual(condition, true, label)
end

local function assertFalse(condition: boolean, label: string)
	assertEqual(condition, false, label)
end

local function makeSignal()
	local callbacks: { (...any) -> () } = {}
	return {
		Connect = function(_self: any, callback: (...any) -> ())
			table.insert(callbacks, callback)
			return {}
		end,
		Fire = function(_self: any, ...: any)
			for _, callback in ipairs(callbacks) do
				callback(...)
			end
		end,
	}
end

local function makeNode(name: string, className: string?)
	local node: any = {
		Name = name,
		ClassName = className or "Folder",
		_Children = {},
		_Attributes = {},
	}

	function node.IsA(self: any, expectedClass: string): boolean
		return self.ClassName == expectedClass
	end

	function node.FindFirstChild(self: any, childName: string): any
		return self._Children[childName]
	end

	function node.WaitForChild(self: any, childName: string): any
		return self._Children[childName]
	end

	function node.SetAttribute(self: any, attributeName: string, value: any)
		self._Attributes[attributeName] = value
	end

	function node.GetAttribute(self: any, attributeName: string): any
		return self._Attributes[attributeName]
	end

	return node
end

local function addChild(parent: any, childName: string, child: any)
	parent._Children[childName] = child
end

local function makeRemoteEvent(remoteName: string)
	local remote: any = {
		Name = remoteName,
		ClassName = "RemoteEvent",
		_Handler = nil,
	}

	function remote.IsA(self: any, expectedClass: string): boolean
		return self.ClassName == expectedClass
	end

	remote.OnServerEvent = {
		Connect = function(_signal: any, handler: (any, any) -> ())
			remote._Handler = handler
		end,
	}

	function remote.FireClient(_self: any, _player: any, _payload: any)
		return
	end

	return remote
end

local remotesFolder = makeNode("Remotes", "Folder")
addChild(remotesFolder, "RescueContractRequest", makeRemoteEvent("RescueContractRequest"))
addChild(remotesFolder, "RescueContractResponse", makeRemoteEvent("RescueContractResponse"))
addChild(remotesFolder, "RescueContractCompleteRequest", makeRemoteEvent("RescueContractCompleteRequest"))

local configFolder = makeNode("Config", "Folder")
addChild(configFolder, "RoleConfig", "../../ReplicatedStorage/Shared/Config/RoleConfig")
addChild(configFolder, "EscapeConfig", "../../ReplicatedStorage/Shared/Config/EscapeConfig")
addChild(configFolder, "RescueContractConfig", "../../ReplicatedStorage/Shared/Config/RescueContractConfig")

local giantRealmFolder = makeNode("GiantRealm", "Folder")
addChild(giantRealmFolder, "SafeZonePolicy", "../../ReplicatedStorage/Shared/GiantRealm/SafeZonePolicy")
addChild(giantRealmFolder, "RescueContractState", "../../ReplicatedStorage/Shared/GiantRealm/RescueContractState")
addChild(
	giantRealmFolder,
	"RescueContractQueueState",
	"../../ReplicatedStorage/Shared/GiantRealm/RescueContractQueueState"
)
addChild(giantRealmFolder, "GiantRealmSaveSchema", "../../ReplicatedStorage/Shared/GiantRealm/GiantRealmSaveSchema")

local sharedFolder = makeNode("Shared", "Folder")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "GiantRealm", giantRealmFolder)

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)
addChild(replicatedStorage, "Remotes", remotesFolder)

local rescuer = MockPlayer.new(2101, "RescuerTinyfolk", {
	role = "Tinyfolk",
	positionZ = 0,
	health = 100,
})
local target = MockPlayer.new(2102, "TargetTinyfolk", {
	role = "Tinyfolk",
	positionZ = 4,
	health = 100,
})
local targetTwo = MockPlayer.new(2103, "TargetTinyfolkTwo", {
	role = "Tinyfolk",
	positionZ = 6,
	health = 100,
})
local rescuerTwo = MockPlayer.new(2104, "RescuerTinyfolkTwo", {
	role = "Tinyfolk",
	positionZ = 2,
	health = 100,
})
local targetThree = MockPlayer.new(2105, "TargetTinyfolkThree", {
	role = "Tinyfolk",
	positionZ = 8,
	health = 100,
})
target:SetAttribute("DownedIsDowned", true)
targetTwo:SetAttribute("DownedIsDowned", true)
targetThree:SetAttribute("DownedIsDowned", true)
target:SetAttribute("GiantRealmOwnerUserId", 9001)
targetTwo:SetAttribute("GiantRealmOwnerUserId", 9002)
targetThree:SetAttribute("GiantRealmOwnerUserId", 9003)

local playersList: { any } = { rescuer, target, targetTwo, rescuerTwo, targetThree }
local playersService: any = {
	PlayerRemoving = makeSignal(),
}

function playersService:GetPlayers(): { any }
	return playersList
end

local workspaceService = makeNode("Workspace", "Workspace")

local fakeGame: any = {}
function fakeGame:GetService(serviceName: string): any
	if serviceName == "Players" then
		return playersService
	end
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
	end
	if serviceName == "Workspace" then
		return workspaceService
	end
	error("unsupported service " .. serviceName)
	return nil
end

game = fakeGame

globalEnv._GrabService_QueryAPI = {
	IsPlayerCarried = function(_userId: number): boolean
		return false
	end,
}

local restrictedRescuerUserId: number? = nil
globalEnv._RoleService_QueryAPI = {
	IsPlayerDowned = function(userId: number): boolean
		for _, player in ipairs(playersList) do
			if player.UserId == userId then
				if restrictedRescuerUserId == userId then
					return true
				end
				return player:GetAttribute("DownedIsDowned") == true
			end
		end
		return false
	end,
	CanPlayerPerformInteraction = function(userId: number, interactionName: string): boolean
		if interactionName ~= "rescueContractRequest" then
			return true
		end
		return restrictedRescuerUserId ~= userId
	end,
}

local rescueRouteMode = "accepted"
local routeRequests: { any } = {}
globalEnv._EscapeService_QueryAPI = {
	ResolveRescueEntryRoute = function(targetUserId: number, targetRealmOwnerUserId: number): any
		table.insert(routeRequests, { targetUserId = targetUserId, targetRealmOwnerUserId = targetRealmOwnerUserId })
		if rescueRouteMode == "missing" then
			return { accepted = false, reason = "rescue_entry_route_missing" }
		end
		if rescueRouteMode == "invalid_route_id" then
			return { accepted = true, routeId = "", routeKind = "RescueEntry" }
		end
		return {
			accepted = true,
			reason = "accepted",
			routeId = string.format("RescueEntryRoute_%d", targetRealmOwnerUserId),
			routeKind = "RescueEntry",
		}
	end,
}

local scoreRequests: { any } = {}
globalEnv._ScoreService_QueryAPI = {
	RequestScoreEvent = function(userId: number, eventId: string, at: number, metadata: any): any
		table.insert(scoreRequests, {
			userId = userId,
			eventId = eventId,
			at = at,
			metadata = metadata,
		})
		return { accepted = true, reason = "accepted" }
	end,
}

local handoffRequests: { any } = {}
local handoffShouldReject = false
local handoffExpiryProbeAt: number? = nil
local rescueFanoutEvents: { any } = {}
local admissionEnqueueRequests: { any } = {}
local admissionEnqueueRejectReason: string? = nil
local admissionEnqueueThrow = false
local idempotencyValuesByMap: { [string]: { [string]: any } } = {}
local failNextIdempotencyCompletion = false
globalEnv._MemoryStoreAdapter_QueryAPI = {
	HashMapUpdateAsync = function(mapName: string, key: string, transform: (any) -> any, _ttlSeconds: number): any
		if idempotencyValuesByMap[mapName] == nil then
			idempotencyValuesByMap[mapName] = {}
		end
		local nextValue = transform(idempotencyValuesByMap[mapName][key])
		if failNextIdempotencyCompletion and type(nextValue) == "table" and nextValue.status == "completed" then
			failNextIdempotencyCompletion = false
			error("idempotency_completion_failed")
		end
		idempotencyValuesByMap[mapName][key] = nextValue
		return nextValue
	end,
}
globalEnv._RescueHandoffService_QueryAPI = {
	CreateHandoffLock = function(payload: any): any
		table.insert(handoffRequests, payload)
		if type(handoffExpiryProbeAt) == "number" then
			local rescueQueryApi: any = globalEnv._RescueContractService_QueryAPI
			if
				type(rescueQueryApi) == "table"
				and type((rescueQueryApi :: any).GetRescueQueueEntries) == "function"
			then
				(rescueQueryApi :: any).GetRescueQueueEntries(handoffExpiryProbeAt)
			end
		end
		if handoffShouldReject then
			return { accepted = false, reason = "handoff_lock_busy" }
		end
		return { accepted = true, reason = "accepted" }
	end,
}

local defaultAdmissionQueueApi = {
	EnqueueAdmission = function(payload: any): any
		table.insert(admissionEnqueueRequests, payload)
		if admissionEnqueueThrow then
			error("enqueue_failed")
		end
		if type(admissionEnqueueRejectReason) == "string" and admissionEnqueueRejectReason ~= "" then
			return {
				accepted = false,
				reason = admissionEnqueueRejectReason,
			}
		end
		return {
			accepted = true,
			reason = "accepted",
		}
	end,
}
globalEnv._RealmAdmissionQueue_QueryAPI = defaultAdmissionQueueApi

globalEnv._QueueNotificationFanout_QueryAPI = {
	PublishRescue = function(eventName: string, payload: any): any
		table.insert(rescueFanoutEvents, {
			eventName = eventName,
			payload = payload,
		})
		return {
			accepted = true,
			reason = "accepted",
		}
	end,
}

require("../src/ServerScriptService/Services/RescueContractService.server")

local rescueApi: any = globalEnv._RescueContractService_QueryAPI
assertTrue(type(rescueApi) == "table", "service exposes query API")
assertTrue(type(rescueApi.BuildPersistenceState) == "function", "service exposes BuildPersistenceState")
assertTrue(type(rescueApi.ApplyPersistenceState) == "function", "service exposes ApplyPersistenceState")

local hubSurfaceApi: any = globalEnv._RescueContractHubSurface_QueryAPI
assertTrue(type(hubSurfaceApi) == "table", "service exposes hub surface API")

local function setRole(player: any, role: string)
	player:SetAttribute("Role", role)
end

local function setHumanoidHealth(player: any, health: number)
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid ~= nil then
		humanoid.Health = health
	end
end

local function resetState()
	rescueApi.ResetForTests()
	setRole(rescuer, "Tinyfolk")
	setRole(target, "Tinyfolk")
	setRole(targetTwo, "Tinyfolk")
	setRole(rescuerTwo, "Tinyfolk")
	setRole(targetThree, "Tinyfolk")
	setHumanoidHealth(rescuer, 100)
	setHumanoidHealth(target, 100)
	setHumanoidHealth(targetTwo, 100)
	setHumanoidHealth(rescuerTwo, 100)
	setHumanoidHealth(targetThree, 100)
	rescuer:SetAttribute("DownedIsDowned", false)
	rescuerTwo:SetAttribute("DownedIsDowned", false)
	target:SetAttribute("DownedIsDowned", true)
	targetTwo:SetAttribute("DownedIsDowned", true)
	targetThree:SetAttribute("DownedIsDowned", true)
	target:SetAttribute("InSafeZone", false)
	target:SetAttribute("SafeZoneType", nil)
	target:SetAttribute("SafeZoneProtectionEndsAt", nil)
	targetTwo:SetAttribute("InSafeZone", false)
	targetTwo:SetAttribute("SafeZoneType", nil)
	targetTwo:SetAttribute("SafeZoneProtectionEndsAt", nil)
	targetThree:SetAttribute("InSafeZone", false)
	targetThree:SetAttribute("SafeZoneType", nil)
	targetThree:SetAttribute("SafeZoneProtectionEndsAt", nil)
	target:SetAttribute("GiantRealmOwnerUserId", 9001)
	targetTwo:SetAttribute("GiantRealmOwnerUserId", 9002)
	targetThree:SetAttribute("GiantRealmOwnerUserId", 9003)
	restrictedRescuerUserId = nil
	rescueRouteMode = "accepted"
	routeRequests = {}
	scoreRequests = {}
	handoffRequests = {}
	handoffShouldReject = false
	handoffExpiryProbeAt = nil
	rescueFanoutEvents = {}
	admissionEnqueueRequests = {}
	admissionEnqueueRejectReason = nil
	admissionEnqueueThrow = false
	idempotencyValuesByMap = {}
	failNextIdempotencyCompletion = false
	globalEnv._RealmAdmissionQueue_QueryAPI = defaultAdmissionQueueApi
end

do
	resetState()
	local applyOk, applyReason = rescueApi.ApplyPersistenceState({
		contracts = {
			{
				rescuerUserId = rescuer.UserId,
				targetUserId = target.UserId,
				targetRealmOwnerUserId = 9001,
				entryRouteId = "RescueEntryRoute_9001",
				entryRouteKind = "RescueEntry",
				startedAt = 90,
				expiresAt = 120,
				isAccelerated = false,
			},
		},
		queueEntries = {
			{
				queueEntryId = "PersistedQueue_1",
				capturedUserId = target.UserId,
				realmId = "giant_realm_9001",
				sessionId = "session_test",
				rewardHint = "rescue_contract",
				dangerRating = 0.5,
				expiration = 120,
				rescuerUserId = rescuer.UserId,
				targetRealmOwnerUserId = 9001,
				entryRouteId = "RescueEntryRoute_9001",
				entryRouteKind = "RescueEntry",
				createdAt = 90,
				status = "pending",
				acceptedAt = nil,
				acceptedByUserId = nil,
				resolvedAt = nil,
				resolvedReason = nil,
			},
		},
	})
	assertTrue(applyOk, "apply persistence accepts valid state")
	assertEqual(applyReason, nil, "apply persistence valid state reason")

	local persistedContract = rescueApi.GetRescuerContract(rescuer.UserId, 90.1)
	assertTrue(persistedContract ~= nil, "apply persistence restores rescuer contract")
	if persistedContract ~= nil then
		assertEqual(persistedContract.targetUserId, target.UserId, "apply persistence contract target")
	end

	local persistedQueue = rescueApi.GetRescueQueueEntries(90.1)
	assertEqual(#persistedQueue, 1, "apply persistence restores pending queue entry")
	assertEqual(persistedQueue[1].queueEntryId, "PersistedQueue_1", "apply persistence queue entry id")
	assertEqual(
		persistedQueue[1].operationId,
		"rescue_accept_PersistedQueue_1",
		"apply persistence backfills queue operation id"
	)

	local builtPersistence = rescueApi.BuildPersistenceState()
	assertEqual(#builtPersistence.contracts, 1, "build persistence includes restored contract")
	assertEqual(#builtPersistence.queueEntries, 1, "build persistence includes restored queue entry")
	assertEqual(builtPersistence.contracts[1].rescuerUserId, rescuer.UserId, "build persistence contract rescuer")
	assertEqual(builtPersistence.queueEntries[1].queueEntryId, "PersistedQueue_1", "build persistence queue entry")
	assertEqual(
		builtPersistence.queueEntries[1].operationId,
		"rescue_accept_PersistedQueue_1",
		"build persistence preserves backfilled operation id"
	)

	local multiApplyOk, multiApplyReason = rescueApi.ApplyPersistenceState({
		contracts = {},
		queueEntries = {
			{
				queueEntryId = "PersistedQueue_2",
				capturedUserId = targetTwo.UserId,
				realmId = "giant_realm_9002",
				sessionId = "session_test",
				rewardHint = "rescue_contract",
				dangerRating = 0.5,
				expiration = 140,
				rescuerUserId = rescuerTwo.UserId,
				targetRealmOwnerUserId = 9002,
				entryRouteId = "RescueEntryRoute_9002",
				entryRouteKind = "RescueEntry",
				createdAt = 95,
				status = "pending",
				acceptedAt = nil,
				acceptedByUserId = nil,
				resolvedAt = nil,
				resolvedReason = nil,
			},
			{
				queueEntryId = "PersistedQueue_1",
				capturedUserId = target.UserId,
				realmId = "giant_realm_9001",
				sessionId = "session_test",
				rewardHint = "rescue_contract",
				dangerRating = 0.5,
				expiration = 140,
				rescuerUserId = rescuer.UserId,
				targetRealmOwnerUserId = 9001,
				entryRouteId = "RescueEntryRoute_9001",
				entryRouteKind = "RescueEntry",
				createdAt = 90,
				status = "pending",
				acceptedAt = nil,
				acceptedByUserId = nil,
				resolvedAt = nil,
				resolvedReason = nil,
			},
		},
	})
	assertTrue(multiApplyOk, "apply persistence accepts multiple queue entries")
	assertEqual(multiApplyReason, nil, "apply persistence multiple queue entries reason")

	local multiBuiltPersistence = rescueApi.BuildPersistenceState()
	assertEqual(#multiBuiltPersistence.queueEntries, 2, "build persistence includes both queue entries")
	assertEqual(
		multiBuiltPersistence.queueEntries[1].queueEntryId,
		"PersistedQueue_1",
		"build persistence orders first queue entry deterministically"
	)
	assertEqual(
		multiBuiltPersistence.queueEntries[2].queueEntryId,
		"PersistedQueue_2",
		"build persistence orders second queue entry deterministically"
	)

	local restoredAcceptOk, restoredAcceptReason = rescueApi.ApplyPersistenceState({
		contracts = {},
		queueEntries = {
			{
				queueEntryId = "RestoredAcceptQueue_1",
				capturedUserId = target.UserId,
				realmId = "giant_realm_9001",
				sessionId = "session_test",
				rewardHint = "rescue_contract",
				dangerRating = 0.5,
				expiration = 210,
				rescuerUserId = rescuer.UserId,
				targetRealmOwnerUserId = 9001,
				entryRouteId = "RescueEntryRoute_9001",
				entryRouteKind = "RescueEntry",
				createdAt = 90,
				status = "pending",
				acceptedAt = nil,
				acceptedByUserId = nil,
				resolvedAt = nil,
				resolvedReason = nil,
			},
		},
	})
	assertTrue(restoredAcceptOk, "apply persistence accepts restorable queue entry")
	assertEqual(restoredAcceptReason, nil, "apply persistence restorable queue entry reason")

	local restoredPendingQueue = rescueApi.GetRescueQueueEntries(90.3)
	assertEqual(#restoredPendingQueue, 1, "restored queue entry is listed pending")
	local restoredAccept = rescueApi.AcceptRescueQueueEntry(rescuerTwo.UserId, "RestoredAcceptQueue_1", 90.4)
	assertTrue(restoredAccept.accepted, "restored pending queue entry can be accepted")
	assertEqual(restoredAccept.reason, "accepted", "restored pending queue accept reason")
	assertEqual(#rescueApi.GetRescueQueueEntries(90.5), 0, "accepted restored queue entry no longer pending")

	local restoredPruneOk, restoredPruneReason = rescueApi.ApplyPersistenceState({
		contracts = {},
		queueEntries = {
			{
				queueEntryId = "RestoredExpireQueue_1",
				capturedUserId = target.UserId,
				realmId = "giant_realm_9001",
				sessionId = "session_test",
				rewardHint = "rescue_contract",
				dangerRating = 0.5,
				expiration = 95,
				rescuerUserId = rescuer.UserId,
				targetRealmOwnerUserId = 9001,
				entryRouteId = "RescueEntryRoute_9001",
				entryRouteKind = "RescueEntry",
				createdAt = 90,
				status = "pending",
				acceptedAt = nil,
				acceptedByUserId = nil,
				resolvedAt = nil,
				resolvedReason = nil,
			},
		},
	})
	assertTrue(restoredPruneOk, "apply persistence accepts expirable queue entry")
	assertEqual(restoredPruneReason, nil, "apply persistence expirable queue entry reason")
	assertEqual(#rescueApi.GetRescueQueueEntries(110), 0, "restored expired queue entry prunes from pending")

	local prunedBuildPersistence = rescueApi.BuildPersistenceState()
	assertEqual(#prunedBuildPersistence.queueEntries, 1, "build persistence keeps pruned restored queue entry")
	assertEqual(prunedBuildPersistence.queueEntries[1].status, "expired", "pruned restored queue entry status")
	assertEqual(prunedBuildPersistence.queueEntries[1].resolvedReason, "expired", "pruned restored queue entry reason")

	local restoredCollisionOk, restoredCollisionReason = rescueApi.ApplyPersistenceState({
		contracts = {},
		queueEntries = {
			{
				queueEntryId = "rescue_queue_2101_2102_100000_1",
				capturedUserId = target.UserId,
				realmId = "giant_realm_9001",
				sessionId = "session_test",
				rewardHint = "rescue_contract",
				dangerRating = 0.5,
				expiration = 140,
				rescuerUserId = rescuer.UserId,
				targetRealmOwnerUserId = 9001,
				entryRouteId = "RescueEntryRoute_9001",
				entryRouteKind = "RescueEntry",
				createdAt = 90,
				status = "pending",
				acceptedAt = nil,
				acceptedByUserId = nil,
				resolvedAt = nil,
				resolvedReason = nil,
			},
		},
	})
	assertTrue(restoredCollisionOk, "apply persistence accepts queue entry id sequence anchor")
	assertEqual(restoredCollisionReason, nil, "apply persistence queue id sequence anchor reason")

	local restoredCollisionRequest = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 100)
	assertTrue(restoredCollisionRequest.accepted, "new rescue request accepted after restore")
	local collisionEntries = rescueApi.GetRescueQueueEntries(100.1)
	assertEqual(#collisionEntries, 2, "restored and new queue entries coexist without id collision")
	assertTrue(
		collisionEntries[1].queueEntryId ~= collisionEntries[2].queueEntryId,
		"new queue entry id differs from restored entry id"
	)

	local clearOk, clearReason = rescueApi.ApplyPersistenceState(nil)
	assertTrue(clearOk, "apply nil persistence succeeds")
	assertEqual(clearReason, nil, "apply nil persistence reason")
	assertEqual(rescueApi.GetRescuerContract(rescuer.UserId, 90.2), nil, "apply nil clears rescuer contract")
	assertEqual(#rescueApi.GetRescueQueueEntries(90.2), 0, "apply nil clears pending queue entries")

	local invalidOk, invalidReason = rescueApi.ApplyPersistenceState({
		contracts = {
			{
				rescuerUserId = rescuer.UserId,
				targetUserId = target.UserId,
				targetRealmOwnerUserId = 9001,
				entryRouteId = "RescueEntryRoute_9001",
				entryRouteKind = "RescueEntry",
				startedAt = 90,
				expiresAt = 120,
				isAccelerated = false,
			},
		},
		queueEntries = {
			{
				queueEntryId = "PersistedQueue_1",
				capturedUserId = target.UserId,
				realmId = "giant_realm_9001",
				sessionId = "session_test",
				rewardHint = "rescue_contract",
				dangerRating = 0.5,
				expiration = 120,
				rescuerUserId = rescuer.UserId,
				targetRealmOwnerUserId = 9001,
				entryRouteId = "RescueEntryRoute_9001",
				entryRouteKind = "RescueEntry",
				createdAt = 90,
				status = "accepted",
				acceptedAt = nil,
				acceptedByUserId = nil,
				resolvedAt = nil,
				resolvedReason = nil,
			},
		},
	})
	assertFalse(invalidOk, "apply persistence rejects malformed state")
	assertEqual(invalidReason, "rescue_queue_accepted_at_missing index=1", "apply persistence malformed reason")

	local accepted = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 100)

	assertTrue(accepted.accepted, "request accepted in valid baseline")
	assertEqual(accepted.reason, "accepted", "request accepted reason")
	assertEqual(accepted.contract.rescuerUserId, rescuer.UserId, "accepted contract stores rescuer")
	assertEqual(accepted.contract.targetUserId, target.UserId, "accepted contract stores target")
	assertEqual(accepted.contract.targetRealmOwnerUserId, 9001, "accepted contract stores target realm")
	assertEqual(accepted.contract.entryRouteId, "RescueEntryRoute_9001", "accepted contract stores entry route")
	assertEqual(accepted.contract.entryRouteKind, "RescueEntry", "accepted contract stores entry route kind")
	assertEqual(routeRequests[1].targetUserId, target.UserId, "route resolver receives target")
	assertEqual(routeRequests[1].targetRealmOwnerUserId, 9001, "route resolver receives target realm")
	assertEqual(
		rescuer:GetAttribute("RescueContractTargetRealmOwnerUserId"),
		9001,
		"rescuer attribute stores target realm"
	)
	assertEqual(
		rescuer:GetAttribute("RescueContractEntryRouteId"),
		"RescueEntryRoute_9001",
		"rescuer attribute stores entry route"
	)
	assertEqual(
		target:GetAttribute("RescueContractEntryRouteKind"),
		"RescueEntry",
		"target attribute stores route kind"
	)

	local queueEntries = rescueApi.GetRescueQueueEntries(100.1)
	assertEqual(#queueEntries, 1, "accepted contract publishes one queue entry")
	assertEqual(
		queueEntries[1].operationId,
		"rescue_accept_" .. queueEntries[1].queueEntryId,
		"published queue entry exposes operation id"
	)
	assertEqual(queueEntries[1].capturedUserId, target.UserId, "queue entry stores captured user")
	assertEqual(queueEntries[1].realmId, "giant_realm_9001", "queue entry stores fallback realm id")
	assertEqual(queueEntries[1].rewardHint, "rescue_contract", "queue entry stores reward hint")
	assertTrue(#rescueFanoutEvents >= 1, "fanout emits publish event")
	local latestFanoutEvent = rescueFanoutEvents[#rescueFanoutEvents]
	assertEqual(latestFanoutEvent.eventName, "rescue_queue_published", "fanout publish event name")
	assertEqual(
		latestFanoutEvent.payload.queueEntryId,
		queueEntries[1].queueEntryId,
		"fanout publish payload queue entry id"
	)
	assertEqual(
		latestFanoutEvent.payload.operationId,
		queueEntries[1].operationId,
		"fanout publish payload operation id"
	)
end

do
	resetState()
	local accepted = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 140)
	assertTrue(accepted.accepted, "accepted before queue accept")

	local queueEntries = rescueApi.GetRescueQueueEntries(140.1)
	assertEqual(#queueEntries, 1, "queue has one pending entry before accept")
	local queueEntryId = queueEntries[1].queueEntryId

	local queueAccept = rescueApi.AcceptRescueQueueEntry(rescuerTwo.UserId, queueEntryId, 140.2)
	assertTrue(queueAccept.accepted, "queue accept succeeds when handoff lock accepts")
	assertEqual(queueAccept.reason, "accepted", "queue accept reason")
	assertEqual(#handoffRequests, 1, "queue accept creates one handoff lock request")
	assertEqual(handoffRequests[1].queueEntryId, queueEntryId, "handoff request receives queue entry id")
	assertEqual(handoffRequests[1].capturedUserId, target.UserId, "handoff request receives captured user")
	assertEqual(handoffRequests[1].acceptedByUserId, rescuerTwo.UserId, "handoff request receives acceptor")
	assertEqual(#admissionEnqueueRequests, 1, "queue accept enqueues one admission entry")
	assertEqual(
		admissionEnqueueRequests[1].operationId,
		"rescue_accept_" .. queueEntryId,
		"admission enqueue operation id"
	)
	assertEqual(admissionEnqueueRequests[1].entryType, "rescue_contract", "admission enqueue entry type")
	assertEqual(admissionEnqueueRequests[1].targetRealmId, "giant_realm_9001", "admission enqueue target realm")
	assertEqual(admissionEnqueueRequests[1].partySize, 3, "admission enqueue party size")
	assertEqual(admissionEnqueueRequests[1].partyMemberUserIds[1], rescuer.UserId, "admission enqueue member first")
	assertEqual(admissionEnqueueRequests[1].partyMemberUserIds[2], target.UserId, "admission enqueue member second")
	assertEqual(admissionEnqueueRequests[1].partyMemberUserIds[3], rescuerTwo.UserId, "admission enqueue member third")
	assertEqual(#rescueFanoutEvents, 2, "fanout emits publish and accept events")
	assertEqual(rescueFanoutEvents[1].eventName, "rescue_queue_published", "fanout first event is publish")
	assertEqual(rescueFanoutEvents[2].eventName, "rescue_queue_accepted", "fanout second event is accepted")
	assertEqual(rescueFanoutEvents[2].payload.acceptedByUserId, rescuerTwo.UserId, "fanout accept payload accepts user")

	local pendingAfterAccept = rescueApi.GetRescueQueueEntries(140.3)
	assertEqual(#pendingAfterAccept, 0, "accepted queue entry no longer returned as pending")

	local duplicateAccept = rescueApi.AcceptRescueQueueEntry(rescuerTwo.UserId, queueEntryId, 140.4)
	assertTrue(duplicateAccept.accepted, "duplicate queue accept is idempotent")
	assertEqual(duplicateAccept.reason, "duplicate_completed", "duplicate queue accept reason")
	assertEqual(#handoffRequests, 1, "duplicate queue accept does not create second handoff lock")
	assertEqual(#admissionEnqueueRequests, 1, "duplicate queue accept does not enqueue second admission")
end

do
	resetState()
	local accepted = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 142)
	assertTrue(accepted.accepted, "accepted before idempotency completion failure check")

	local queueEntries = rescueApi.GetRescueQueueEntries(142.1)
	local queueEntryId = queueEntries[1].queueEntryId
	failNextIdempotencyCompletion = true

	local queueReject = rescueApi.AcceptRescueQueueEntry(rescuerTwo.UserId, queueEntryId, 142.2)
	assertFalse(queueReject.accepted, "queue accept rejects when idempotency completion write fails")
	assertEqual(queueReject.reason, "idempotency_mark_completed_failed", "queue accept completion failure reason")
	assertEqual(#handoffRequests, 1, "completion failure still creates one handoff lock")
	assertEqual(#admissionEnqueueRequests, 1, "completion failure still enqueues one admission")
	assertEqual(#rescueApi.GetRescueQueueEntries(142.3), 0, "completion failure does not reopen pending queue entry")

	local duplicateReject = rescueApi.AcceptRescueQueueEntry(rescuerTwo.UserId, queueEntryId, 142.4)
	assertFalse(duplicateReject.accepted, "duplicate after completion failure is blocked")
	assertEqual(duplicateReject.reason, "already_processing", "duplicate after completion failure reason")
	assertEqual(#handoffRequests, 1, "duplicate after completion failure does not create handoff")
	assertEqual(#admissionEnqueueRequests, 1, "duplicate after completion failure does not enqueue admission")
end

do
	resetState()
	local accepted = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 144)
	assertTrue(accepted.accepted, "accepted before admission queue unavailable check")

	local queueEntries = rescueApi.GetRescueQueueEntries(144.1)
	local queueEntryId = queueEntries[1].queueEntryId
	globalEnv._RealmAdmissionQueue_QueryAPI = nil

	local queueReject = rescueApi.AcceptRescueQueueEntry(rescuerTwo.UserId, queueEntryId, 144.2)
	assertFalse(queueReject.accepted, "queue accept rejects when admission queue api unavailable")
	assertEqual(queueReject.reason, "admission_queue_unavailable", "admission queue unavailable reason")
	assertEqual(#handoffRequests, 1, "handoff lock still attempted before admission queue failure")
	assertEqual(#admissionEnqueueRequests, 0, "no admission enqueue request when api unavailable")
	assertEqual(#rescueApi.GetRescueQueueEntries(144.3), 1, "queue remains pending when admission queue unavailable")

	globalEnv._RealmAdmissionQueue_QueryAPI = defaultAdmissionQueueApi
end

do
	resetState()
	local accepted = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 144.5)
	assertTrue(accepted.accepted, "accepted before admission enqueue rejection check")

	local queueEntries = rescueApi.GetRescueQueueEntries(144.6)
	local queueEntryId = queueEntries[1].queueEntryId
	admissionEnqueueRejectReason = "queue_store_unavailable"

	local queueReject = rescueApi.AcceptRescueQueueEntry(rescuerTwo.UserId, queueEntryId, 144.7)
	assertFalse(queueReject.accepted, "queue accept rejects when admission enqueue rejects")
	assertEqual(queueReject.reason, "queue_store_unavailable", "admission enqueue rejected reason passthrough")
	assertEqual(#handoffRequests, 1, "handoff lock attempted before admission enqueue rejection")
	assertEqual(#admissionEnqueueRequests, 1, "admission enqueue request attempted before rejection")
	assertEqual(#rescueApi.GetRescueQueueEntries(144.8), 1, "queue remains pending when admission enqueue rejects")

	admissionEnqueueRejectReason = nil
	local retryAccept = rescueApi.AcceptRescueQueueEntry(rescuerTwo.UserId, queueEntryId, 144.9)
	assertTrue(retryAccept.accepted, "queue accept retries after admission enqueue rejection")
	assertEqual(#handoffRequests, 2, "retry after enqueue rejection creates second handoff attempt")
	assertEqual(#admissionEnqueueRequests, 2, "retry after enqueue rejection enqueues once")
end

do
	resetState()
	local firstAccepted = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 141)
	assertTrue(firstAccepted.accepted, "first accepted before hub list limit check")
	local secondAccepted = rescueApi.RequestRescueContract(rescuerTwo.UserId, targetThree.UserId, 141)
	assertTrue(secondAccepted.accepted, "second accepted before hub list limit check")

	local limitedQueue = hubSurfaceApi.GetPendingRescueQueueEntries(1, 141.1)
	assertEqual(#limitedQueue, 1, "hub list applies positive limit")
	local zeroQueue = hubSurfaceApi.GetPendingRescueQueueEntries(0, 141.1)
	assertEqual(#zeroQueue, 0, "hub list returns empty for non-positive limit")

	local queueEntries = hubSurfaceApi.GetPendingRescueQueueEntries(nil, 141.1)
	assertEqual(#queueEntries, 2, "hub list returns pending entries")
	local queueEntryId = queueEntries[1].queueEntryId

	local queueAccept = hubSurfaceApi.AcceptRescueQueueEntry(rescuer.UserId, queueEntryId, 141.2)
	assertTrue(queueAccept.accepted, "hub surface can accept queue entry")
	assertEqual(queueAccept.reason, "accepted", "hub surface accept reason")
end

do
	resetState()
	local accepted = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 145)
	assertTrue(accepted.accepted, "accepted before queue lock rejection")

	local queueEntries = rescueApi.GetRescueQueueEntries(145.1)
	local queueEntryId = queueEntries[1].queueEntryId
	handoffShouldReject = true

	local queueReject = rescueApi.AcceptRescueQueueEntry(rescuerTwo.UserId, queueEntryId, 145.2)
	assertFalse(queueReject.accepted, "queue accept rejects when handoff lock rejects")
	assertEqual(queueReject.reason, "handoff_lock_busy", "queue accept returns handoff lock reason")

	local pendingAfterReject = rescueApi.GetRescueQueueEntries(145.3)
	assertEqual(#pendingAfterReject, 1, "queue entry remains pending when handoff lock rejects")

	handoffShouldReject = false
	local retryAccept = rescueApi.AcceptRescueQueueEntry(rescuerTwo.UserId, queueEntryId, 145.4)
	assertTrue(retryAccept.accepted, "queue accept retries after handoff lock rejection")
	assertEqual(#handoffRequests, 2, "retry after handoff rejection creates second handoff attempt")
	assertEqual(#admissionEnqueueRequests, 1, "retry after handoff rejection enqueues admission once")
end

do
	resetState()
	local accepted = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 146)
	assertTrue(accepted.accepted, "accepted before queue race-like probe")

	local queueEntries = rescueApi.GetRescueQueueEntries(146.1)
	local queueEntryId = queueEntries[1].queueEntryId
	handoffExpiryProbeAt = 200

	local queueResult = rescueApi.AcceptRescueQueueEntry(rescuerTwo.UserId, queueEntryId, 146.2)
	assertFalse(queueResult.accepted, "queue accept rejects if entry is no longer pending after lock call")
	assertEqual(queueResult.reason, "queue_entry_not_pending", "queue race-like rejection reason")
	assertEqual(#admissionEnqueueRequests, 0, "queue race-like rejection does not enqueue admission")
end

do
	resetState()
	local accepted = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 150)
	assertTrue(accepted.accepted, "accepted before queue expiry")

	local pendingAtStart = rescueApi.GetRescueQueueEntries(150.1)
	assertEqual(#pendingAtStart, 1, "queue entry initially pending")

	local pendingAfterExpiry = rescueApi.GetRescueQueueEntries(163)
	assertEqual(#pendingAfterExpiry, 0, "expired queue entry pruned from pending list")
	assertEqual(#rescueFanoutEvents, 2, "fanout emits publish and expiry events")
	assertEqual(rescueFanoutEvents[1].eventName, "rescue_queue_published", "fanout expiry flow publish event")
	assertEqual(rescueFanoutEvents[2].eventName, "rescue_queue_expired", "fanout expiry flow expired event")
end

do
	resetState()
	target:SetAttribute("GiantRealmOwnerUserId", nil)
	local rejected = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 110)
	assertFalse(rejected.accepted, "missing target realm rejects")
	assertEqual(rejected.reason, "target_realm_owner_user_id_invalid", "missing target realm reason")
	assertEqual(#routeRequests, 0, "missing target realm does not resolve route")
	assertEqual(rescueApi.GetRescuerContract(rescuer.UserId, 110.1), nil, "missing realm does not create contract")
end

do
	resetState()
	rescueRouteMode = "missing"
	local rejected = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 120)
	assertFalse(rejected.accepted, "missing rescue entry route rejects")
	assertEqual(rejected.reason, "rescue_entry_route_missing", "missing route reason")
	assertEqual(rescueApi.GetRescuerContract(rescuer.UserId, 120.1), nil, "missing route does not create contract")
	assertEqual(
		rescuer:GetAttribute("RescueContractLastReason"),
		"rescue_entry_route_missing",
		"missing route reason projects"
	)
end

do
	resetState()
	rescueRouteMode = "invalid_route_id"
	local rejected = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 130)
	assertFalse(rejected.accepted, "invalid rescue entry route rejects")
	assertEqual(rejected.reason, "rescue_entry_route_id_invalid", "invalid route reason")
	assertEqual(rescueApi.GetRescuerContract(rescuer.UserId, 130.1), nil, "invalid route does not create contract")
end

do
	resetState()
	local accepted = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 200)
	assertTrue(accepted.accepted, "baseline acceptance before cooldown test")

	local throttled = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 200.1)
	assertFalse(throttled.accepted, "rapid repeat request throttled")
	assertEqual(throttled.reason, "request_cooldown", "repeat request cooldown reason")
end

do
	resetState()
	local invalidTargetId = rescueApi.RequestRescueContract(rescuer.UserId, "bad", 250)
	assertFalse(invalidTargetId.accepted, "invalid target id rejects")
	assertEqual(invalidTargetId.reason, "target_user_id_invalid", "invalid target id reason")
	assertEqual(
		rescuer:GetAttribute("RescueContractLastReason"),
		"target_user_id_invalid",
		"invalid target id projects rescuer last reason"
	)

	local missingTarget = rescueApi.RequestRescueContract(rescuer.UserId, 999999, 250.1)
	assertFalse(missingTarget.accepted, "missing target rejects")
	assertEqual(missingTarget.reason, "target_not_found", "missing target reason")
	assertEqual(
		rescuer:GetAttribute("RescueContractLastReason"),
		"target_not_found",
		"missing target projects rescuer last reason"
	)
end

do
	resetState()
	local invalidBaseline = rescueApi.RequestRescueContract(rescuer.UserId, "bad", 255)
	assertFalse(invalidBaseline.accepted, "invalid request baseline rejects")
	assertEqual(invalidBaseline.reason, "target_user_id_invalid", "invalid baseline reason")

	local throttled = rescueApi.RequestRescueContract(rescuer.UserId, "bad", 255.01)
	assertFalse(throttled.accepted, "rapid repeated invalid rescue request is throttled")
	assertEqual(throttled.reason, "request_cooldown", "rapid repeated invalid rescue request cooldown reason")

	local accepted = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 255.06)
	assertTrue(accepted.accepted, "invalid request does not consume accepted rescue cooldown")
	assertEqual(accepted.reason, "accepted", "valid follow-up accepted after reject cooldown window")
end

do
	resetState()
	target:SetAttribute("DownedIsDowned", false)
	local rejected = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 300)

	assertFalse(rejected.accepted, "target must be downed")
	assertEqual(rejected.reason, "target_not_downed", "target not downed reason")
end

do
	resetState()
	local accepted = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 400)
	assertTrue(accepted.accepted, "request accepted before completion")

	local completed = rescueApi.CompleteRescueContract(rescuer.UserId, target.UserId, 401)
	assertTrue(completed.accepted, "completion accepted for active contract")
	assertEqual(completed.reason, "rescued", "completion reason")
	assertEqual(rescueApi.GetRescuerContract(rescuer.UserId), nil, "contract cleared after completion")
	assertTrue(target:GetAttribute("PostRescueProtected") == true, "completion grants post-rescue protection")
	assertTrue(
		type(target:GetAttribute("PostRescueProtectionExpiresAt")) == "number",
		"completion sets post-rescue protection expiry"
	)
	assertTrue(rescuer:GetAttribute("RescueAccelerationActive") == true, "completion grants rescuer acceleration")
	assertTrue(
		type(rescuer:GetAttribute("RescueAccelerationExpiresAt")) == "number",
		"completion sets rescuer acceleration expiry"
	)
	assertEqual(#scoreRequests, 1, "completion emits one score request")
	assertEqual(scoreRequests[1].eventId, "rescue_complete", "completion score event id")
	assertEqual(scoreRequests[1].metadata.targetUserId, target.UserId, "completion score metadata target")
	assertEqual(scoreRequests[1].metadata.targetRealmOwnerUserId, 9001, "completion score metadata target realm")
	assertEqual(scoreRequests[1].metadata.entryRouteId, "RescueEntryRoute_9001", "completion score metadata route")
	assertEqual(scoreRequests[1].metadata.entryRouteKind, "RescueEntry", "completion score metadata route kind")
end

do
	resetState()
	local accepted = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 430)
	assertTrue(accepted.accepted, "accepted before protection expiry cleanup")
	local completed = rescueApi.CompleteRescueContract(rescuer.UserId, target.UserId, 431)
	assertTrue(completed.accepted, "completed before protection expiry cleanup")

	assertTrue(target:GetAttribute("PostRescueProtected") == true, "post-rescue protection active before expiry")
	rescueApi.GetAllContracts(436)
	assertTrue(target:GetAttribute("PostRescueProtected") == false, "post-rescue protection clears after expiry")
	assertTrue(
		target:GetAttribute("PostRescueProtectionExpiresAt") == nil,
		"post-rescue protection expiry attribute clears after expiry"
	)
	rescueApi.GetAllContracts(452)
	assertTrue(rescuer:GetAttribute("RescueAccelerationActive") == false, "rescuer acceleration clears after expiry")
	assertTrue(
		rescuer:GetAttribute("RescueAccelerationExpiresAt") == nil,
		"rescuer acceleration expiry attribute clears after expiry"
	)
end

do
	resetState()
	local firstAccepted = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 500)
	assertTrue(firstAccepted.accepted, "baseline accepted before acceleration consumption")
	local firstCompleted = rescueApi.CompleteRescueContract(rescuer.UserId, target.UserId, 501)
	assertTrue(firstCompleted.accepted, "baseline completed before acceleration consumption")

	target:SetAttribute("DownedIsDowned", true)
	local acceleratedRequest = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 502)
	assertTrue(acceleratedRequest.accepted, "next request accepted with acceleration")
	assertTrue(acceleratedRequest.contract.isAccelerated == true, "next request contract is accelerated")
	assertEqual(acceleratedRequest.contract.expiresAt, 517, "accelerated runtime window bonus applied")
	assertTrue(
		rescuer:GetAttribute("RescueAccelerationActive") == false,
		"acceleration consumed after accepted rescue request"
	)
	assertTrue(
		rescuer:GetAttribute("RescueAccelerationExpiresAt") == nil,
		"acceleration expiry cleared after consumption"
	)
end

do
	resetState()
	local firstAccepted = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 700)
	assertTrue(firstAccepted.accepted, "baseline accepted before rejected acceleration request")
	local firstCompleted = rescueApi.CompleteRescueContract(rescuer.UserId, target.UserId, 701)
	assertTrue(firstCompleted.accepted, "baseline completed before rejected acceleration request")

	target:SetAttribute("DownedIsDowned", false)
	local rejectedAcceleratedRequest = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 702)
	assertFalse(rejectedAcceleratedRequest.accepted, "rejected request does not consume acceleration")
	assertEqual(rejectedAcceleratedRequest.reason, "target_not_downed", "rejected accelerated request reason")
	assertTrue(
		rescuer:GetAttribute("RescueAccelerationActive") == true,
		"acceleration remains active after rejected request"
	)
	assertEqual(
		rescuer:GetAttribute("RescueAccelerationExpiresAt"),
		721,
		"acceleration expiry remains unchanged after rejected request"
	)
end

do
	resetState()
	local accepted = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 450)
	assertTrue(accepted.accepted, "baseline accepted before rejected completion")

	local rejectedComplete = rescueApi.CompleteRescueContract(rescuer.UserId, targetTwo.UserId, 451)
	assertFalse(rejectedComplete.accepted, "completion rejects wrong target")
	assertEqual(rejectedComplete.reason, "target_mismatch", "wrong target completion reason")

	local activeContract = rescueApi.GetRescuerContract(rescuer.UserId, 451)
	assertTrue(activeContract ~= nil, "rejected completion preserves active contract")
	assertEqual(
		rescuer:GetAttribute("RescueContractTargetUserId"),
		target.UserId,
		"rejected completion preserves rescuer attribute target"
	)
end

do
	resetState()
	restrictedRescuerUserId = rescuer.UserId
	local rejected = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 470)
	assertFalse(rejected.accepted, "restricted rescuer cannot request")
	assertEqual(rejected.reason, "rescuer_interaction_restricted", "restricted rescuer rejection reason")
	assertEqual(
		rescuer:GetAttribute("RescueContractLastReason"),
		"rescuer_interaction_restricted",
		"restricted rescuer projects rescuer last reason"
	)
	assertEqual(
		target:GetAttribute("RescueContractLastReason"),
		"rescuer_interaction_restricted",
		"restricted rescuer projects target last reason"
	)
end

do
	resetState()
	local accepted = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 500)
	assertTrue(accepted.accepted, "baseline accepted before rejected follow-up request")

	local rejected = rescueApi.RequestRescueContract(rescuer.UserId, targetTwo.UserId, 500.1)
	assertFalse(rejected.accepted, "rapid follow-up request rejected")
	assertEqual(rejected.reason, "request_cooldown", "follow-up cooldown reason")
	assertEqual(
		rescuer:GetAttribute("RescueContractTargetUserId"),
		target.UserId,
		"rejected follow-up request preserves active attribute target"
	)
end

do
	resetState()
	local accepted = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 600)
	assertTrue(accepted.accepted, "contract accepted before expiry test")

	local postExpiry = rescueApi.RequestRescueContract(rescuer.UserId, targetTwo.UserId, 612.1)
	assertTrue(postExpiry.accepted, "expired contract is pruned before next request")
	assertEqual(postExpiry.contract.targetUserId, targetTwo.UserId, "post-expiry request targets second target")
end

do
	resetState()
	local first = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 650)
	assertTrue(first.accepted, "accepted before participant overlap checks")
	target:SetAttribute("DownedIsDowned", false)

	local targetStartsAnother = rescueApi.RequestRescueContract(target.UserId, targetTwo.UserId, 651)
	assertFalse(targetStartsAnother.accepted, "targeted participant cannot start another contract")
	assertEqual(
		targetStartsAnother.reason,
		"participant_contract_active",
		"targeted participant start rejection reason"
	)

	rescuer:SetAttribute("DownedIsDowned", true)
	local rescuerBecomesTarget = rescueApi.RequestRescueContract(rescuerTwo.UserId, rescuer.UserId, 651)
	assertFalse(rescuerBecomesTarget.accepted, "active rescuer cannot become target")
	assertEqual(rescuerBecomesTarget.reason, "participant_contract_active", "active rescuer target rejection reason")
end

do
	resetState()
	local accepted = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 700)
	assertTrue(accepted.accepted, "accepted before rescuer leave cleanup")

	playersService.PlayerRemoving:Fire(rescuer)
	assertEqual(rescueApi.GetRescuerContract(rescuer.UserId, 700.1), nil, "rescuer leave clears active contract")
	assertEqual(rescuer:GetAttribute("RescueContractActive"), false, "rescuer leave clears active attribute")
	assertEqual(target:GetAttribute("RescueContractActive"), false, "rescuer leave clears target active attribute")
end

do
	resetState()
	local accepted = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 800)
	assertTrue(accepted.accepted, "accepted before target leave cleanup")

	playersService.PlayerRemoving:Fire(target)
	assertEqual(rescueApi.GetRescuerContract(rescuer.UserId, 800.1), nil, "target leave clears active contract")
	assertEqual(rescuer:GetAttribute("RescueContractActive"), false, "target leave clears rescuer active attribute")
	assertEqual(target:GetAttribute("RescueContractActive"), false, "target leave clears target active attribute")
end

do
	resetState()
	local first = rescueApi.RequestRescueContract(rescuer.UserId, target.UserId, 900)
	assertTrue(first.accepted, "first parallel contract accepted")

	local second = rescueApi.RequestRescueContract(rescuerTwo.UserId, targetThree.UserId, 900)
	assertTrue(second.accepted, "second parallel contract accepted")

	assertEqual(rescuer:GetAttribute("RescueContractActive"), true, "first rescuer active attribute set")
	assertEqual(target:GetAttribute("RescueContractActive"), true, "first target active attribute set")
	assertEqual(rescuerTwo:GetAttribute("RescueContractActive"), true, "second rescuer active attribute set")
	assertEqual(targetThree:GetAttribute("RescueContractActive"), true, "second target active attribute set")
end

do
	resetState()
	local rejected = rescueApi.RequestRescueContract(rescuer.UserId, rescuer.UserId, 500)
	assertFalse(rejected.accepted, "self rescue rejected")
	assertEqual(rejected.reason, "self_rescue_not_allowed", "self rescue rejection reason")
end

do
	resetState()
	local missingRescuerRequest = rescueApi.RequestRescueContract(999999, target.UserId, 950)
	assertFalse(missingRescuerRequest.accepted, "query request rejects missing rescuer")
	assertEqual(missingRescuerRequest.reason, "rescuer_not_found", "query request missing rescuer reason")

	local missingRescuerComplete = rescueApi.CompleteRescueContract(999999, target.UserId, 950)
	assertFalse(missingRescuerComplete.accepted, "query complete rejects missing rescuer")
	assertEqual(missingRescuerComplete.reason, "rescuer_not_found", "query complete missing rescuer reason")
end

print("rescue_contract_service_runtime_entrypoint: all checks passed")
