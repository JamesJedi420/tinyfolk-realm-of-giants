--!nocheck
--!nolint BuiltinGlobalWrite

local MockPlayer = require("../tests/mocks/MockPlayer")
local LiveRealmRegistryState = require("../src/ReplicatedStorage/Shared/GiantRealm/LiveRealmRegistryState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
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
addChild(remotesFolder, "RaidBoardListRequest", makeRemoteEvent("RaidBoardListRequest"))
addChild(remotesFolder, "RaidBoardListResponse", makeRemoteEvent("RaidBoardListResponse"))
addChild(remotesFolder, "RaidBoardQueueRequest", makeRemoteEvent("RaidBoardQueueRequest"))
addChild(remotesFolder, "RaidBoardQueueResponse", makeRemoteEvent("RaidBoardQueueResponse"))
addChild(remotesFolder, "RaidBoardNotify", makeRemoteEvent("RaidBoardNotify"))

local configFolder = makeNode("Config", "Folder")
addChild(configFolder, "RaidBoardConfig", "../../ReplicatedStorage/Shared/Config/RaidBoardConfig")
addChild(configFolder, "RoleConfig", "../../ReplicatedStorage/Shared/Config/RoleConfig")

local giantRealmFolder = makeNode("GiantRealm", "Folder")
addChild(giantRealmFolder, "LiveRealmHubRouting", "../../ReplicatedStorage/Shared/GiantRealm/LiveRealmHubRouting")
addChild(giantRealmFolder, "LiveRealmRegistryState", "../../ReplicatedStorage/Shared/GiantRealm/LiveRealmRegistryState")
addChild(giantRealmFolder, "RaidBoardHubState", "../../ReplicatedStorage/Shared/GiantRealm/RaidBoardHubState")
addChild(
	giantRealmFolder,
	"RealmReservedServerAllocationState",
	"../../ReplicatedStorage/Shared/GiantRealm/RealmReservedServerAllocationState"
)
addChild(giantRealmFolder, "RealmTransferState", "../../ReplicatedStorage/Shared/GiantRealm/RealmTransferState")

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

require("../src/ServerScriptService/Services/RaidBoardHubService.server")

local api = _G._RaidBoardHubService_QueryAPI
assertTrue(type(api) == "table", "raid board query api present")

api.ResetForTests()

local availability = {
	{
		realmId = "giant_realm_9002",
		ownerUserId = 9002,
		privateServerId = "giant_realm_ps_9002",
		accessMode = LiveRealmRegistryState.AccessMode.Public,
		playerCount = 1,
		capacity = 8,
		dangerRating = 0.4,
		lifecycle = LiveRealmRegistryState.Lifecycle.Active,
		isAvailable = true,
		updatedAt = 100,
	},
	{
		realmId = "giant_realm_9001",
		ownerUserId = 9001,
		privateServerId = "ps-live-9001",
		accessMode = LiveRealmRegistryState.AccessMode.Private,
		playerCount = 2,
		capacity = 8,
		dangerRating = 0.9,
		lifecycle = LiveRealmRegistryState.Lifecycle.Active,
		isAvailable = true,
		updatedAt = 100,
	},
}

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
	admissionApi = {
		RequestPartyMatchAdmission = function(input: any): any
			table.insert(admissionCalls, input)
			return {
				accepted = true,
				reason = "accepted",
				snapshot = {
					operationId = "op-raid-board",
					partyId = input.partyId,
				},
			}
		end,
	},
	resolveOwnerDisplayName = function(ownerUserId: number): string?
		if ownerUserId == 9002 then
			return "Board Giant"
		end
		return nil
	end,
})

local tinyfolk = MockPlayer.new(4401, "TinyfolkRaider", {
	role = "Tinyfolk",
})
local giant = MockPlayer.new(4402, "GiantOwner", {
	role = "Giant",
})

local listAccepted = api.HandleListRequestForTests(tinyfolk, {
	requestId = "list-1",
	limit = 10,
}, 200)
assertEqual(listAccepted.accepted, true, "list accepted for tinyfolk")
assertEqual(#listAccepted.listings, 1, "list returns one public realm")
assertEqual(listAccepted.listings[1].ownerDisplayName, "Board Giant", "list resolves owner display name")
assertEqual(listAccepted.listings[1].realmDisplayName, "Board Giant's Realm", "list resolves realm display name")

local listRejected = api.HandleListRequestForTests(giant, {
	requestId = "list-2",
}, 200)
assertEqual(listRejected.accepted, false, "list rejected for giant")
assertEqual(listRejected.reason, "role_not_tinyfolk", "list giant rejection reason")

local listRateLimited = api.HandleListRequestForTests(tinyfolk, {
	requestId = "list-3",
}, 200.1)
assertEqual(listRateLimited.accepted, false, "list rate limited")
assertEqual(listRateLimited.reason, "rate_limited", "list rate limited reason")

local queueAccepted = api.HandleQueueRequestForTests(tinyfolk, {
	requestId = "queue-1",
	targetRealmId = "giant_realm_9002",
}, 201)
assertEqual(queueAccepted.accepted, true, "queue accepted")
assertEqual(queueAccepted.targetRealmId, "giant_realm_9002", "queue target realm id")
assertEqual(queueAccepted.queueSnapshot.operationId, "op-raid-board", "queue snapshot operation id")
assertEqual(#admissionCalls, 1, "admission called once")
assertEqual(admissionCalls[1].partyId, "raid_board:4401", "solo raid board party id")
assertEqual(admissionCalls[1].targetRealmId, "giant_realm_9002", "admission target realm id")
assertEqual(admissionCalls[1].partyMemberUserIds[1], 4401, "admission solo member")

local diagnostics = api.GetDiagnostics()
assertEqual(diagnostics.listSucceeded, 1, "diagnostics list success count")
assertEqual(diagnostics.queueSucceeded, 1, "diagnostics queue success count")

local queuePrivate = api.HandleQueueRequestForTests(tinyfolk, {
	requestId = "queue-2",
	targetRealmId = "giant_realm_9001",
}, 202)
assertEqual(queuePrivate.accepted, false, "queue private realm rejected")
assertEqual(queuePrivate.reason, "target_realm_unavailable", "queue private realm reason")

api.ConfigureForTests({
	now = function()
		return 203
	end,
	liveRegistryApi = {
		ListLiveRealmAvailability = function(_limit: any, _at: any): { any }
			return availability
		end,
	},
	admissionApi = {
		RequestPartyMatchAdmission = function(input: any): any
			table.insert(admissionCalls, input)
			return {
				accepted = true,
				reason = "accepted",
				snapshot = {
					operationId = "op-raid-board",
					partyId = input.partyId,
				},
			}
		end,
	},
	tinyfolkPartyApi = {
		ResolveRaidBoardQueueContext = function(_userId: number): any
			return {
				accepted = false,
				reason = "party_not_ready",
				partyId = "tinyfolk_party:4401:100000",
				partyMemberUserIds = { 4401, 4403 },
			}
		end,
	},
	resolveOwnerDisplayName = function(ownerUserId: number): string?
		if ownerUserId == 9002 then
			return "Board Giant"
		end
		return nil
	end,
})

local partyQueueBlocked = api.HandleQueueRequestForTests(tinyfolk, {
	requestId = "queue-party-blocked",
	targetRealmId = "giant_realm_9002",
}, 203)
assertEqual(partyQueueBlocked.accepted, false, "party queue blocked when not ready")
assertEqual(partyQueueBlocked.reason, "party_not_ready", "party queue blocked reason")
assertEqual(#admissionCalls, 1, "admission still one call after party block")

local diagnosticsAfterPartyBlock = api.GetDiagnostics()
assertEqual(diagnosticsAfterPartyBlock.queueFailed, 2, "diagnostics queue failed count after party block")
assertEqual(diagnosticsAfterPartyBlock.lastReason, "party_not_ready", "diagnostics last reason after party block")

api.ConfigureForTests({
	now = function()
		return 204
	end,
	liveRegistryApi = {
		ListLiveRealmAvailability = function(_limit: any, _at: any): { any }
			return availability
		end,
	},
	admissionApi = {
		RequestPartyMatchAdmission = function(input: any): any
			table.insert(admissionCalls, input)
			return {
				accepted = true,
				reason = "accepted",
				snapshot = {
					operationId = "op-raid-board-party",
					partyId = input.partyId,
				},
			}
		end,
	},
	tinyfolkPartyApi = {
		ResolveRaidBoardQueueContext = function(userId: number): any
			if userId == 4401 then
				return {
					accepted = true,
					reason = "accepted",
					partyId = "tinyfolk_party:4401:100000",
					partyMemberUserIds = { 4401, 4403 },
				}
			end
			return { accepted = true, reason = "solo" }
		end,
	},
	resolveOwnerDisplayName = function(ownerUserId: number): string?
		if ownerUserId == 9002 then
			return "Board Giant"
		end
		return nil
	end,
})

local partyQueueAccepted = api.HandleQueueRequestForTests(tinyfolk, {
	requestId = "queue-party",
	targetRealmId = "giant_realm_9002",
}, 205)
assertEqual(partyQueueAccepted.accepted, true, "party queue accepted")
assertEqual(#admissionCalls, 2, "admission called for party queue")
assertEqual(admissionCalls[2].partyId, "tinyfolk_party:4401:100000", "party queue party id")
assertEqual(admissionCalls[2].partyMemberUserIds[1], 4401, "party queue member leader")
assertEqual(admissionCalls[2].partyMemberUserIds[2], 4403, "party queue member second")

api.BroadcastNotify({
	eventKind = "realm_status_changed",
})
local notifyRemote = remotesFolder._Children.RaidBoardNotify
assertEqual(#notifyRemote._AllPayloads, 1, "notify broadcast sent")

print("raid_board_hub_service_runtime_entrypoint: all checks passed")
