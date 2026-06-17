--!nocheck
--!nolint BuiltinGlobalWrite

local MockPlayer = require("../tests/mocks/MockPlayer")
local LiveRealmRegistryState = require("../src/ReplicatedStorage/Shared/GiantRealm/LiveRealmRegistryState")
local RealmEntryPortalConfig = require("../src/ReplicatedStorage/Shared/Config/RealmEntryPortalConfig")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(condition: boolean, label: string)
	assertEqual(condition, true, label)
end

local function makeSignal()
	local callbacks: { (any) -> () } = {}
	return {
		Connect = function(_self: any, callback: (any) -> ())
			table.insert(callbacks, callback)
			return {}
		end,
		Fire = function(_self: any, player: any)
			for _, callback in ipairs(callbacks) do
				callback(player)
			end
		end,
	}
end

local function makeNode(name: string, className: string?)
	local node: any = {
		Name = name,
		ClassName = className or "Folder",
		_Children = {},
	}

	function node:IsA(expectedClass: string): boolean
		return self.ClassName == expectedClass
	end

	function node:FindFirstChild(childName: string): any
		return self._Children[childName]
	end

	function node:WaitForChild(childName: string): any
		return self._Children[childName]
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
		_ClientPayloads = {},
		_AllPayloads = {},
	}

	function remote:IsA(expectedClass: string): boolean
		return self.ClassName == expectedClass
	end

	remote.OnServerEvent = {
		Connect = function(_signal: any, handler: (any, any) -> ())
			remote._Handler = handler
		end,
	}

	function remote:FireClient(player: any, payload: any)
		table.insert(self._ClientPayloads, {
			userId = player.UserId,
			payload = payload,
		})
	end

	function remote:FireAllClients(payload: any)
		table.insert(self._AllPayloads, payload)
	end

	return remote
end

local remotesFolder = makeNode("Remotes", "Folder")
addChild(remotesFolder, "RealmEntryPortalListRequest", makeRemoteEvent("RealmEntryPortalListRequest"))
addChild(remotesFolder, "RealmEntryPortalListResponse", makeRemoteEvent("RealmEntryPortalListResponse"))
addChild(remotesFolder, "RealmEntryPortalEnterRequest", makeRemoteEvent("RealmEntryPortalEnterRequest"))
addChild(remotesFolder, "RealmEntryPortalEnterResponse", makeRemoteEvent("RealmEntryPortalEnterResponse"))
addChild(remotesFolder, "RealmEntryPortalNotify", makeRemoteEvent("RealmEntryPortalNotify"))

local configFolder = makeNode("Config", "Folder")
addChild(configFolder, "RealmEntryPortalConfig", "../../ReplicatedStorage/Shared/Config/RealmEntryPortalConfig")
addChild(configFolder, "TinyfolkHubConfig", "../../ReplicatedStorage/Shared/Config/TinyfolkHubConfig")
addChild(configFolder, "RoleConfig", "../../ReplicatedStorage/Shared/Config/RoleConfig")
addChild(configFolder, "RealmPermissionConfig", "../../ReplicatedStorage/Shared/Config/RealmPermissionConfig")

local giantRealmFolder = makeNode("GiantRealm", "Folder")
addChild(giantRealmFolder, "LiveRealmHubRouting", "../../ReplicatedStorage/Shared/GiantRealm/LiveRealmHubRouting")
addChild(giantRealmFolder, "LiveRealmRegistryState", "../../ReplicatedStorage/Shared/GiantRealm/LiveRealmRegistryState")
addChild(
	giantRealmFolder,
	"RealmEntryPortalHubState",
	"../../ReplicatedStorage/Shared/GiantRealm/RealmEntryPortalHubState"
)
addChild(
	giantRealmFolder,
	"RealmReservedServerAllocationState",
	"../../ReplicatedStorage/Shared/GiantRealm/RealmReservedServerAllocationState"
)
addChild(giantRealmFolder, "RealmTransferState", "../../ReplicatedStorage/Shared/GiantRealm/RealmTransferState")
addChild(giantRealmFolder, "PlayerLocationState", "../../ReplicatedStorage/Shared/GiantRealm/PlayerLocationState")
addChild(
	giantRealmFolder,
	"RealmAssignmentProfileState",
	"../../ReplicatedStorage/Shared/GiantRealm/RealmAssignmentProfileState"
)

local sharedFolder = makeNode("Shared", "Folder")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "GiantRealm", giantRealmFolder)

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)
addChild(replicatedStorage, "Remotes", remotesFolder)

local playersService: any = {
	PlayerRemoving = makeSignal(),
}

local fakeGame: any = {}
function fakeGame:GetService(serviceName: string): any
	if serviceName == "Players" then
		return playersService
	end
	if serviceName == "ReplicatedStorage" then
		return replicatedStorage
	end
	error("unsupported service " .. serviceName)
	return nil
end

game = fakeGame

require("../src/ServerScriptService/Services/AdmissionQueueProducer")
require("../src/ServerScriptService/Services/RealmEntryPortalHubService.server")

local api = _G._RealmEntryPortalHubService_QueryAPI
assertTrue(type(api) == "table", "realm entry portal query api present")
api.ResetForTests()

local availability = {
	{
		realmId = "giant_realm_9002",
		ownerUserId = 9002,
		privateServerId = "giant_realm_ps_9002",
		accessMode = LiveRealmRegistryState.AccessMode.Public,
		playerCount = 1,
		capacity = 8,
		isAvailable = true,
		updatedAt = 100,
	},
}

local handoffCalls = {}
local locationCalls = {}
local assignmentCalls = {}
local admissionCalls = {}

api.ConfigureForTests({
	now = function()
		return 200
	end,
	liveRegistryApi = {
		ListLiveRealmAvailability = function(_limit: any, _at: any): { any }
			return availability
		end,
	},
	handoffApi = {
		BeginHandoff = function(input: any): any
			table.insert(handoffCalls, input)
			return {
				accepted = true,
				reason = "accepted",
				handoffToken = string.format("handoff:%d:1", input.userId),
			}
		end,
		InvalidateHandoffOnAbort = function(input: any): any
			return { accepted = true, reason = "accepted", input = input }
		end,
	},
	locationApi = {
		ApplyTransition = function(userId: number, input: any): any
			table.insert(locationCalls, { userId = userId, input = input })
			return { accepted = true, reason = "accepted" }
		end,
	},
	assignmentApi = {
		ApplyTransition = function(userId: number, input: any): any
			table.insert(assignmentCalls, { userId = userId, input = input })
			return { accepted = true, reason = "accepted" }
		end,
	},
	admissionQueueApi = {
		EnqueueAdmission = function(payload: any): any
			table.insert(admissionCalls, payload)
			return {
				accepted = true,
				reason = "accepted",
				snapshot = {
					operationId = payload.operationId,
					partyId = payload.partyId,
				},
			}
		end,
	},
	resolveOwnerDisplayName = function(ownerUserId: number): string?
		if ownerUserId == 9002 then
			return "Portal Giant"
		end
		return nil
	end,
})

local tinyfolk = MockPlayer.new(5501, "TinyfolkPortal", {
	role = "Tinyfolk",
})

local listAccepted = api.HandleListRequestForTests(tinyfolk, {
	requestId = "list-1",
	entryMethod = RealmEntryPortalConfig.EntryMethods.Portal,
	limit = 10,
}, 200)
assertEqual(listAccepted.accepted, true, "list accepted")
assertEqual(#listAccepted.listings, 1, "one portal listing")
assertEqual(listAccepted.listings[1].entryRoleLabel, "Guest", "guest role label")

local enterAccepted = api.HandleEnterRequestForTests(tinyfolk, {
	requestId = "enter-1",
	targetRealmId = "giant_realm_9002",
	entryMethod = RealmEntryPortalConfig.EntryMethods.Portal,
}, 201)
assertEqual(enterAccepted.accepted, true, "enter accepted")
assertEqual(enterAccepted.entryRole, RealmEntryPortalConfig.EntryRoles.Guest, "enter guest role")
assertEqual(#handoffCalls, 1, "handoff begin called")
assertEqual(handoffCalls[1].targetRealmId, "giant_realm_9002", "handoff target realm")
assertEqual(#locationCalls, 1, "location transition called")
assertEqual(locationCalls[1].input.operation, "begin_transit", "location begin transit")
assertEqual(#assignmentCalls, 1, "assignment transition called")
assertEqual(assignmentCalls[1].input.operation, "begin_party_admission", "assignment party admission")
assertEqual(#admissionCalls, 1, "admission enqueue called")
assertEqual(admissionCalls[1].entryType, "standard", "standard admission entry type")
assertEqual(admissionCalls[1].partyId, "realm_portal:5501", "solo portal party id")

local enterRejected = api.HandleEnterRequestForTests(tinyfolk, {
	requestId = "enter-2",
	targetRealmId = "giant_realm_9999",
	entryMethod = RealmEntryPortalConfig.EntryMethods.Portal,
}, 202)
assertEqual(enterRejected.accepted, false, "missing realm rejected")

api.ConfigureForTests({
	now = function()
		return 203
	end,
	liveRegistryApi = {
		ListLiveRealmAvailability = function(_limit: any, _at: any): { any }
			return availability
		end,
	},
	handoffApi = {
		BeginHandoff = function(input: any): any
			return { accepted = true, handoffToken = "handoff:" .. tostring(input.userId) }
		end,
		InvalidateHandoffOnAbort = function(): any
			return { accepted = true }
		end,
	},
	locationApi = {
		ApplyTransition = function(): any
			return { accepted = false, reason = "location_transition_failed" }
		end,
	},
	assignmentApi = {
		ApplyTransition = function(): any
			return { accepted = true }
		end,
	},
	admissionQueueApi = {
		EnqueueAdmission = function(): any
			return { accepted = true, snapshot = { operationId = "op" } }
		end,
	},
})

local rollbackEnter = api.HandleEnterRequestForTests(tinyfolk, {
	requestId = "enter-rollback",
	targetRealmId = "giant_realm_9002",
	entryMethod = RealmEntryPortalConfig.EntryMethods.Portal,
}, 203)
assertEqual(rollbackEnter.accepted, false, "location failure rejects entry")
assertEqual(rollbackEnter.reason, "location_transition_failed", "location failure reason")

print("realm_entry_portal_hub_service_runtime_entrypoint: all checks passed")
