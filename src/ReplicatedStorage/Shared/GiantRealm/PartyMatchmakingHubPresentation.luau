--!strict

local PartyMatchmakingQueueConfig = require("../Config/PartyMatchmakingQueueConfig")

local PartyMatchmakingHubPresentation: any = {}

local ACTIVITY_LABELS: { [string]: string } = {
	[PartyMatchmakingQueueConfig.Activities.Raid] = "Raid",
	[PartyMatchmakingQueueConfig.Activities.Rescue] = "Rescue",
	[PartyMatchmakingQueueConfig.Activities.Scouting] = "Scouting",
	[PartyMatchmakingQueueConfig.Activities.WorkContract] = "Work Contract",
}

local TERMINAL_STATUSES: { [string]: boolean } = {
	matched = true,
	expired = true,
	cancelled = true,
}

function PartyMatchmakingHubPresentation.GetActivityLabel(activity: string): string
	return ACTIVITY_LABELS[activity] or activity
end

function PartyMatchmakingHubPresentation.ListActivities(): { string }
	return {
		PartyMatchmakingQueueConfig.Activities.Raid,
		PartyMatchmakingQueueConfig.Activities.Rescue,
		PartyMatchmakingQueueConfig.Activities.Scouting,
		PartyMatchmakingQueueConfig.Activities.WorkContract,
	}
end

function PartyMatchmakingHubPresentation.IsTerminalStatus(status: any): boolean
	if type(status) ~= "string" then
		return false
	end
	return TERMINAL_STATUSES[status] == true
end

function PartyMatchmakingHubPresentation.ShouldContinuePolling(snapshot: any): boolean
	if type(snapshot) ~= "table" then
		return false
	end
	return snapshot.status == "pending"
end

function PartyMatchmakingHubPresentation.BuildQueueSnapshotStatus(snapshot: any): string
	if type(snapshot) ~= "table" then
		return "Queue status unavailable"
	end

	local activityLabel = PartyMatchmakingHubPresentation.GetActivityLabel(snapshot.desiredActivity or "unknown")
	local status = if type(snapshot.status) == "string" then snapshot.status else "unknown"

	if status == "pending" then
		return string.format("Searching for %s match...", activityLabel)
	end
	if status == "matched" then
		local targetRealmId = if type(snapshot.targetRealmId) == "string" then snapshot.targetRealmId else "realm"
		return string.format("Matched for %s -> %s", activityLabel, targetRealmId)
	end
	if status == "expired" then
		local reason = if type(snapshot.resolvedReason) == "string" then snapshot.resolvedReason else "expired"
		return string.format("%s queue expired (%s)", activityLabel, reason)
	end
	if status == "cancelled" then
		local reason = if type(snapshot.resolvedReason) == "string" then snapshot.resolvedReason else "cancelled"
		return string.format("%s queue cancelled (%s)", activityLabel, reason)
	end

	return string.format("%s queue status: %s", activityLabel, status)
end

function PartyMatchmakingHubPresentation.BuildEnqueueStatusMessage(response: any): string
	if type(response) ~= "table" then
		return "Enqueue response unavailable"
	end
	if response.accepted == true then
		if type(response.queueSnapshot) == "table" then
			return PartyMatchmakingHubPresentation.BuildQueueSnapshotStatus(response.queueSnapshot)
		end
		return "Joined matchmaking queue"
	end

	local reason = if type(response.reason) == "string" then response.reason else "enqueue_failed"
	return string.format("Queue failed: %s", reason)
end

function PartyMatchmakingHubPresentation.BuildPollStatusMessage(response: any): string
	if type(response) ~= "table" then
		return "Poll response unavailable"
	end
	if response.accepted == true and type(response.queueSnapshot) == "table" then
		return PartyMatchmakingHubPresentation.BuildQueueSnapshotStatus(response.queueSnapshot)
	end

	local reason = if type(response.reason) == "string" then response.reason else "poll_failed"
	return string.format("Queue update failed: %s", reason)
end

function PartyMatchmakingHubPresentation.BuildNotifyStatusMessage(payload: any): string
	if type(payload) ~= "table" then
		return "Queue notification unavailable"
	end
	if payload.kind == "queue_resolved" and type(payload.queueSnapshot) == "table" then
		return PartyMatchmakingHubPresentation.BuildQueueSnapshotStatus(payload.queueSnapshot)
	end
	return "Queue update received"
end

return PartyMatchmakingHubPresentation
