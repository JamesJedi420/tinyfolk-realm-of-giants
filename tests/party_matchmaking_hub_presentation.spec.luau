--!nocheck

local PartyMatchmakingHubPresentation =
	require("../src/ReplicatedStorage/Shared/GiantRealm/PartyMatchmakingHubPresentation")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

local function assertTrue(condition: boolean, label: string)
	assertEqual(condition, true, label)
end

local function assertContains(haystack: string, needle: string, label: string)
	if string.find(haystack, needle, 1, true) == nil then
		error(string.format("FAIL [%s]: expected substring %s in %s", label, needle, haystack))
	end
end

assertEqual(PartyMatchmakingHubPresentation.GetActivityLabel("raid"), "Raid", "raid label")
assertEqual(PartyMatchmakingHubPresentation.GetActivityLabel("work_contract"), "Work Contract", "work contract label")
assertTrue(#PartyMatchmakingHubPresentation.ListActivities() == 4, "activity list length")

local pendingSnapshot = {
	desiredActivity = "rescue",
	status = "pending",
}
assertTrue(PartyMatchmakingHubPresentation.ShouldContinuePolling(pendingSnapshot), "pending polls continue")
assertTrue(not PartyMatchmakingHubPresentation.IsTerminalStatus("pending"), "pending not terminal")

local matchedSnapshot = {
	desiredActivity = "raid",
	status = "matched",
	targetRealmId = "realm-42",
}
assertTrue(not PartyMatchmakingHubPresentation.ShouldContinuePolling(matchedSnapshot), "matched stops polling")
assertTrue(PartyMatchmakingHubPresentation.IsTerminalStatus("matched"), "matched terminal")

local matchedStatus = PartyMatchmakingHubPresentation.BuildQueueSnapshotStatus(matchedSnapshot)
assertContains(matchedStatus, "realm-42", "matched status includes realm")

local enqueueRejected = {
	accepted = false,
	reason = "party_leader_required",
}
assertContains(
	PartyMatchmakingHubPresentation.BuildEnqueueStatusMessage(enqueueRejected),
	"party_leader_required",
	"enqueue rejection reason"
)

local notifyResolved = {
	kind = "queue_resolved",
	queueSnapshot = {
		desiredActivity = "scouting",
		status = "expired",
		resolvedReason = "party_members_changed",
	},
}
assertContains(
	PartyMatchmakingHubPresentation.BuildNotifyStatusMessage(notifyResolved),
	"party_members_changed",
	"notify resolved reason"
)

print("party_matchmaking_hub_presentation: all checks passed")
