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
addChild(remotesFolder, "TinyfolkPartyActionRequest", makeRemoteEvent("TinyfolkPartyActionRequest"))
addChild(remotesFolder, "TinyfolkPartyActionResponse", makeRemoteEvent("TinyfolkPartyActionResponse"))
addChild(remotesFolder, "TinyfolkPartyNotify", makeRemoteEvent("TinyfolkPartyNotify"))

local configFolder = makeNode("Config", "Folder")
addChild(configFolder, "RoleConfig", "../../ReplicatedStorage/Shared/Config/RoleConfig")
addChild(configFolder, "TinyfolkPartyConfig", "../../ReplicatedStorage/Shared/Config/TinyfolkPartyConfig")

local giantRealmFolder = makeNode("GiantRealm", "Folder")
addChild(giantRealmFolder, "TinyfolkPartyState", "../../ReplicatedStorage/Shared/GiantRealm/TinyfolkPartyState")

local sharedFolder = makeNode("Shared", "Folder")
addChild(sharedFolder, "Config", configFolder)
addChild(sharedFolder, "GiantRealm", giantRealmFolder)

local replicatedStorage = makeNode("ReplicatedStorage", "ReplicatedStorage")
addChild(replicatedStorage, "Shared", sharedFolder)
addChild(replicatedStorage, "Remotes", remotesFolder)

local players: { any } = {}
local playersService: any = {
	PlayerRemoving = makeSignal(),
	GetPlayers = function()
		return players
	end,
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

local resolverCalls = {
	register = {},
	unregister = {},
}
local partyResolverApi = {
	RegisterPartyMembers = function(input: any)
		table.insert(resolverCalls.register, input)
		return { accepted = true, reason = "accepted" }
	end,
	UnregisterParty = function(partyId: any)
		table.insert(resolverCalls.unregister, partyId)
		return { accepted = true, reason = "accepted" }
	end,
	ResolvePartyMemberUserIds = function(partyId: string)
		local latestMembers = {}
		for _, input in ipairs(resolverCalls.register) do
			if input.partyId == partyId then
				latestMembers = input.memberUserIds
			end
		end
		return latestMembers
	end,
}

require("../src/ServerScriptService/Services/TinyfolkPartyService.server")

local api = _G._TinyfolkPartyService_QueryAPI
assertTrue(type(api) == "table", "tinyfolk party query api present")
api.ResetForTests()
api.ConfigureForTests({
	now = function()
		return 100
	end,
	playersService = playersService,
	partyResolverApi = partyResolverApi,
})

local leader = MockPlayer.new(5001, "PartyLeader", {
	role = "Tinyfolk",
})
local member = MockPlayer.new(5002, "PartyMember", {
	role = "Tinyfolk",
})
local giant = MockPlayer.new(5003, "GiantPlayer", {
	role = "Giant",
})
table.insert(players, leader)
table.insert(players, member)
table.insert(players, giant)

local createAccepted = api.HandleActionRequestForTests(leader, {
	action = "create",
}, 100)
assertTrue(createAccepted.accepted, "create accepted")
assertEqual(createAccepted.leaderUserId, 5001, "create leader id")
assertEqual(#resolverCalls.register, 1, "resolver register on create")

local inviteAccepted = api.HandleActionRequestForTests(leader, {
	action = "invite",
	targetUserId = 5002,
}, 101)
assertTrue(inviteAccepted.accepted, "invite accepted")
assertEqual(inviteAccepted.pendingInviteUserIds[1], 5002, "invite pending user")

local joinAccepted = api.HandleActionRequestForTests(member, {
	action = "accept_invite",
}, 102)
assertTrue(joinAccepted.accepted, "accept invite accepted")
assertEqual(#joinAccepted.memberUserIds, 2, "party has two members")
assertEqual(#resolverCalls.register, 3, "resolver register after join")

local leaderReady = api.HandleActionRequestForTests(leader, {
	action = "set_ready",
	ready = true,
}, 103)
assertTrue(leaderReady.accepted, "leader ready accepted")

local queueBlocked = api.ResolveRaidBoardQueueContext(leader.UserId)
assertEqual(queueBlocked.accepted, false, "queue blocked before all ready")
assertEqual(queueBlocked.reason, "party_not_ready", "queue blocked reason")

local memberReady = api.HandleActionRequestForTests(member, {
	action = "set_ready",
	ready = true,
}, 104)
assertTrue(memberReady.accepted, "member ready accepted")

local queueAllowed = api.ResolveRaidBoardQueueContext(leader.UserId)
assertTrue(queueAllowed.accepted, "queue allowed when all ready")
assertEqual(queueAllowed.partyMemberUserIds[1], 5001, "queue member first")
assertEqual(queueAllowed.partyMemberUserIds[2], 5002, "queue member second")

local nonLeaderQueue = api.ResolveRaidBoardQueueContext(member.UserId)
assertEqual(nonLeaderQueue.accepted, false, "non leader queue rejected")
assertEqual(nonLeaderQueue.reason, "party_leader_required", "non leader queue reason")

local giantRejected = api.HandleActionRequestForTests(giant, {
	action = "create",
}, 105)
assertEqual(giantRejected.accepted, false, "giant create rejected")
assertEqual(giantRejected.reason, "role_not_tinyfolk", "giant rejection reason")

local leaveAccepted = api.HandleActionRequestForTests(leader, {
	action = "leave",
}, 106)
assertTrue(leaveAccepted.accepted, "leader leave accepted")
assertEqual(api.GetPartySnapshot(leader.UserId).partyId, nil, "leader no longer in party")
assertEqual(#resolverCalls.unregister, 1, "resolver unregister on dissolve")

print("tinyfolk_party_service_runtime_entrypoint: all checks passed")
