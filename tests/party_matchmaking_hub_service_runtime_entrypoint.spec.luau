--!nocheck
--!nolint BuiltinGlobalWrite

local MockPlayer = require("../tests/mocks/MockPlayer")

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

	return remote
end

local remotesFolder = makeNode("Remotes", "Folder")
addChild(remotesFolder, "PartyMatchmakingEnqueueRequest", makeRemoteEvent("PartyMatchmakingEnqueueRequest"))
addChild(remotesFolder, "PartyMatchmakingEnqueueResponse", makeRemoteEvent("PartyMatchmakingEnqueueResponse"))
addChild(remotesFolder, "PartyMatchmakingPollRequest", makeRemoteEvent("PartyMatchmakingPollRequest"))
addChild(remotesFolder, "PartyMatchmakingPollResponse", makeRemoteEvent("PartyMatchmakingPollResponse"))
addChild(remotesFolder, "PartyMatchmakingNotify", makeRemoteEvent("PartyMatchmakingNotify"))

local configFolder = makeNode("Config", "Folder")
addChild(configFolder, "PartyMatchmakingQueueConfig", "../../ReplicatedStorage/Shared/Config/PartyMatchmakingQueueConfig")
addChild(configFolder, "TinyfolkHubConfig", "../../ReplicatedStorage/Shared/Config/TinyfolkHubConfig")
addChild(configFolder, "RoleConfig", "../../ReplicatedStorage/Shared/Config/RoleConfig")

local sharedFolder = makeNode("Shared", "Folder")
addChild(sharedFolder, "Config", configFolder)

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

require("../src/ServerScriptService/Services/PartyMatchmakingHubService.server")

local api = _G._PartyMatchmakingHubService_QueryAPI
assertTrue(type(api) == "table", "hub query api present")
api.ResetForTests()

local enqueueCalls = {}
local snapshotsByOperationId = {}

api.ConfigureForTests({
	now = function()
		return 300
	end,
	matchmakingQueueApi = {
		EnqueueMatchmaking = function(input: any): any
			table.insert(enqueueCalls, input)
			local snapshot = {
				operationId = "party_matchmaking_tinyfolk_party_101_1000",
				partyId = input.partyId,
				leaderUserId = input.leaderUserId,
				partySize = input.partySize,
				desiredActivity = input.desiredActivity,
				status = "pending",
				expiration = 600,
			}
			snapshotsByOperationId[snapshot.operationId] = snapshot
			return {
				accepted = true,
				reason = "accepted",
				snapshot = snapshot,
			}
		end,
		GetQueueSnapshot = function(input: any): any
			local snapshot = snapshotsByOperationId[input.operationId]
			if snapshot == nil then
				return { accepted = false, reason = "queue_snapshot_not_found" }
			end
			return { accepted = true, reason = "accepted", snapshot = snapshot }
		end,
	},
	tinyfolkPartyApi = {
		ResolveMatchmakingQueueContext = function(userId: number): any
			if userId ~= 101 then
				return { accepted = false, reason = "party_leader_required" }
			end
			return {
				accepted = true,
				reason = "accepted",
				partyId = "tinyfolk_party:101:1000",
				partyMemberUserIds = { 101, 202 },
			}
		end,
	},
})

local leader = MockPlayer.new(101, "PartyLeader", { role = "Tinyfolk" })
local giant = MockPlayer.new(202, "GiantPlayer", { role = "Giant" })

local enqueueAccepted = api.HandleEnqueueRequestForTests(leader, {
	requestId = "enqueue-1",
	desiredActivity = "raid",
	skillBand = 1,
	toolTier = 0,
}, 300)
assertEqual(enqueueAccepted.accepted, true, "enqueue accepted")
assertEqual(#enqueueCalls, 1, "enqueue forwarded to queue api")
assertEqual(enqueueCalls[1].leaderUserId, 101, "enqueue includes leader user id")

local enqueueRejected = api.HandleEnqueueRequestForTests(giant, {
	requestId = "enqueue-2",
	desiredActivity = "raid",
}, 300)
assertEqual(enqueueRejected.accepted, false, "non-tinyfolk enqueue rejected")
assertEqual(enqueueRejected.reason, "role_not_tinyfolk", "non-tinyfolk reason")

local pollAccepted = api.HandlePollRequestForTests(leader, {
	requestId = "poll-1",
	operationId = "party_matchmaking_tinyfolk_party_101_1000",
}, 301)
assertEqual(pollAccepted.accepted, true, "poll accepted")
assertEqual(pollAccepted.queueSnapshot.status, "pending", "poll pending snapshot")

snapshotsByOperationId["party_matchmaking_tinyfolk_party_101_1000"] = {
	operationId = "party_matchmaking_tinyfolk_party_101_1000",
	partyId = "tinyfolk_party:101:1000",
	status = "matched",
	targetRealmId = "realm-raid",
}

local pollResolved = api.HandlePollRequestForTests(leader, {
	requestId = "poll-2",
	operationId = "party_matchmaking_tinyfolk_party_101_1000",
}, 302)
assertEqual(pollResolved.accepted, true, "resolved poll accepted")
assertEqual(pollResolved.queueSnapshot.status, "matched", "resolved poll status")

api.ResetForTests()

print("party_matchmaking_hub_service_runtime_entrypoint: all checks passed")
