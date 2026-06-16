--!nocheck

local TinyfolkPartyState = require("../src/ReplicatedStorage/Shared/GiantRealm/TinyfolkPartyState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

local function assertTrue(condition: boolean, label: string)
	assertEqual(condition, true, label)
end

local created = TinyfolkPartyState.ResolveCreate({
	leaderUserId = 101,
	at = 10,
})
assertTrue(created.accepted, "create accepted")
assertEqual(created.party.leaderUserId, 101, "create leader")
assertEqual(created.party.memberUserIds[1], 101, "create member")
assertEqual(created.party.readyUserIds[1], nil, "create not ready")

local invited = TinyfolkPartyState.ResolveInvite({
	party = created.party,
	actorUserId = 101,
	targetUserId = 202,
	at = 11,
})
assertTrue(invited.accepted, "invite accepted")
assertEqual(invited.party.pendingInviteUserIds[1], 202, "invite pending")

local accepted = TinyfolkPartyState.ResolveAcceptInvite({
	party = invited.party,
	userId = 202,
	at = 12,
})
assertTrue(accepted.accepted, "accept invite accepted")
assertEqual(#accepted.party.memberUserIds, 2, "accept adds member")
assertEqual(#accepted.party.readyUserIds, 0, "accept clears ready")

local leaderReady = TinyfolkPartyState.ResolveSetReady({
	party = accepted.party,
	userId = 101,
	ready = true,
	at = 13,
})
assertTrue(leaderReady.accepted, "leader ready accepted")
assertEqual(#leaderReady.party.readyUserIds, 1, "leader ready count")

local queueBlocked, queueBlockedReason = TinyfolkPartyState.ValidateRaidBoardQueue(leaderReady.party, 101)
assertEqual(queueBlocked, false, "queue blocked when not all ready")
assertEqual(queueBlockedReason, "party_not_ready", "queue blocked reason")

local memberReady = TinyfolkPartyState.ResolveSetReady({
	party = leaderReady.party,
	userId = 202,
	ready = true,
	at = 14,
})
assertTrue(memberReady.accepted, "member ready accepted")

local queueAllowed, queueReason = TinyfolkPartyState.ValidateRaidBoardQueue(memberReady.party, 101)
assertTrue(queueAllowed, "queue allowed when all ready")
assertEqual(queueReason, "accepted", "queue allowed reason")

local nonLeaderQueueAllowed, nonLeaderQueueReason = TinyfolkPartyState.ValidateRaidBoardQueue(memberReady.party, 202)
assertEqual(nonLeaderQueueAllowed, false, "non leader queue rejected")
assertEqual(nonLeaderQueueReason, "party_leader_required", "non leader queue reason")

local left = TinyfolkPartyState.ResolveLeave({
	party = memberReady.party,
	userId = 101,
	at = 15,
})
assertTrue(left.accepted, "leader leave accepted")
assertTrue(left.dissolved, "leader leave dissolves party")

local soloCreate = TinyfolkPartyState.ResolveCreate({
	leaderUserId = 303,
	at = 20,
})
local soloReady = TinyfolkPartyState.ResolveSetReady({
	party = soloCreate.party,
	userId = 303,
	ready = true,
	at = 21,
})
local soloQueueAllowed, soloQueueReason = TinyfolkPartyState.ValidateRaidBoardQueue(soloReady.party, 303)
assertTrue(soloQueueAllowed, "solo party queue allowed when ready")
assertEqual(soloQueueReason, "accepted", "solo queue reason")

local partialOutcome = TinyfolkPartyState.ResolveTransferOutcome({
	party = memberReady.party,
	transferredUserIds = { 101 },
	at = 30,
})
assertTrue(partialOutcome.accepted, "partial transfer outcome accepted")
assertEqual(partialOutcome.dissolved, false, "partial transfer keeps party")
assertEqual(partialOutcome.party.leaderUserId, 202, "partial transfer reassigns leader")
assertEqual(partialOutcome.party.memberUserIds[1], 202, "partial transfer leaves non-transferred member")
assertEqual(#partialOutcome.party.readyUserIds, 0, "partial transfer clears ready state")
assertEqual(partialOutcome.transferredUserIds[1], 101, "partial transfer returns transferred user")
assertEqual(partialOutcome.recoveredUserIds[1], 202, "partial transfer returns recovered user")

local fullOutcome = TinyfolkPartyState.ResolveTransferOutcome({
	party = memberReady.party,
	transferredUserIds = { 101, 202 },
	at = 31,
})
assertTrue(fullOutcome.accepted, "full transfer outcome accepted")
assertTrue(fullOutcome.dissolved, "full transfer dissolves party")
assertEqual(fullOutcome.party, nil, "full transfer clears party")

local snapshot = TinyfolkPartyState.BuildSnapshot(soloReady.party, "accepted", true)
assertEqual(snapshot.partyId, soloReady.party.partyId, "snapshot party id")
assertEqual(snapshot.leaderUserId, 303, "snapshot leader")

print("tinyfolk_party_state: all checks passed")
