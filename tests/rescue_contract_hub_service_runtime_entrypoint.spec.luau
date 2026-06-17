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
addChild(remotesFolder, "RescueContractBoardListRequest", makeRemoteEvent("RescueContractBoardListRequest"))
addChild(remotesFolder, "RescueContractBoardListResponse", makeRemoteEvent("RescueContractBoardListResponse"))
addChild(remotesFolder, "RescueContractBoardAcceptRequest", makeRemoteEvent("RescueContractBoardAcceptRequest"))
addChild(remotesFolder, "RescueContractBoardAcceptResponse", makeRemoteEvent("RescueContractBoardAcceptResponse"))
addChild(remotesFolder, "RescueContractHubNotify", makeRemoteEvent("RescueContractHubNotify"))

local configFolder = makeNode("Config", "Folder")
addChild(configFolder, "RescueContractConfig", "../../ReplicatedStorage/Shared/Config/RescueContractConfig")
addChild(configFolder, "TinyfolkHubConfig", "../../ReplicatedStorage/Shared/Config/TinyfolkHubConfig")
addChild(configFolder, "RoleConfig", "../../ReplicatedStorage/Shared/Config/RoleConfig")

local giantRealmFolder = makeNode("GiantRealm", "Folder")
addChild(giantRealmFolder, "RescueContractHubState", "../../ReplicatedStorage/Shared/GiantRealm/RescueContractHubState")

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

require("../src/ServerScriptService/Services/RescueContractHubService.server")

local api = _G._RescueContractHubService_QueryAPI
assertTrue(type(api) == "table", "rescue contract hub query api present")
api.ResetForTests()

local player = MockPlayer.new(3001, "RescueVolunteer", {
	role = "Tinyfolk",
})

local pendingEntries = {
	{
		queueEntryId = "queue_1",
		operationId = "rescue_accept_queue_1",
		capturedUserId = 2102,
		realmId = "giant_realm_9001",
		sessionId = "session_a",
		rewardHint = "rescue_contract",
		dangerRating = 0.6,
		expiration = 220,
		rescuerUserId = 2101,
		targetRealmOwnerUserId = 9001,
		entryRouteId = "RescueEntryRoute_9001",
		entryRouteKind = "RescueEntry",
		createdAt = 200,
		status = "pending",
	},
}

local acceptCalls = {}
api.ConfigureForTests({
	now = function()
		return 210
	end,
	rescueHubApi = {
		GetPendingRescueQueueEntries = function(_limit: any, _at: any): { any }
			return pendingEntries
		end,
		AcceptRescueQueueEntry = function(acceptedByUserId: number, queueEntryId: string, _at: any): any
			table.insert(acceptCalls, {
				acceptedByUserId = acceptedByUserId,
				queueEntryId = queueEntryId,
			})
			return {
				accepted = true,
				reason = "accepted",
			}
		end,
	},
})

local listResponse = api.HandleListRequestForTests(player, {
	requestId = "list-1",
	limit = 10,
}, 210)
assertTrue(listResponse.accepted, "list accepted")
assertEqual(#listResponse.contracts, 1, "list contract count")
assertEqual(listResponse.contracts[1].queueEntryId, "queue_1", "list contract id")

local acceptResponse = api.HandleAcceptRequestForTests(player, {
	requestId = "accept-1",
	queueEntryId = "queue_1",
}, 210.5)
assertTrue(acceptResponse.accepted, "accept accepted")
assertEqual(#acceptCalls, 1, "accept call count")
assertEqual(acceptCalls[1].queueEntryId, "queue_1", "accept queue entry id")

print("rescue_contract_hub_service_runtime_entrypoint: all checks passed")
