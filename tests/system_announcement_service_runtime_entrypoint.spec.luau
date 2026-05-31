--!nocheck

local globalEnv: any = _G

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(
			string.format("assertEqual failed [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual))
		)
	end
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local function assertFalse(value: boolean, label: string)
	assertEqual(value, false, label)
end

local function resetGlobals()
	globalEnv._SystemAnnouncementService_QueryAPI = nil
end

resetGlobals()
require("../src/ServerScriptService/Services/SystemAnnouncementService.server")

local serviceApi = globalEnv._SystemAnnouncementService_QueryAPI
assertTrue(type(serviceApi) == "table", "service query api published")
assertTrue(type(serviceApi.PublishAnnouncement) == "function", "publish function published")
assertTrue(type(serviceApi.ClearAnnouncement) == "function", "clear function published")
assertTrue(type(serviceApi.GetActiveAnnouncement) == "function", "get active function published")
assertTrue(type(serviceApi.GetAnnouncementDiagnostics) == "function", "diagnostics function published")

serviceApi.ConfigureForTests({
	now = function()
		return 100
	end,
})

local projectionSnapshots: { any } = {}
serviceApi.ConfigureForTests({
	now = function()
		return 100
	end,
	projectionSink = function(snapshot: any)
		table.insert(projectionSnapshots, snapshot)
	end,
})

local invalidRequest = serviceApi.PublishAnnouncement(nil)
assertFalse(invalidRequest.accepted, "invalid request rejected")
assertEqual(invalidRequest.reason, "request_invalid", "invalid request reason")

local invalidSeverity = serviceApi.PublishAnnouncement({
	announcementId = "global_1",
	message = "Realm maintenance in 10 minutes",
	severity = "urgent",
	startsAt = 100,
	endsAt = 200,
})
assertFalse(invalidSeverity.accepted, "invalid severity rejected")
assertEqual(invalidSeverity.reason, "announcement_severity_invalid", "invalid severity reason")

local invalidWindow = serviceApi.PublishAnnouncement({
	announcementId = "global_1",
	message = "Realm maintenance in 10 minutes",
	severity = "warning",
	startsAt = 100,
	endsAt = 100,
})
assertFalse(invalidWindow.accepted, "invalid window rejected")
assertEqual(invalidWindow.reason, "announcement_window_invalid", "invalid window reason")

local published = serviceApi.PublishAnnouncement({
	announcementId = "global_1",
	message = "Realm maintenance in 10 minutes",
	severity = "warning",
	startsAt = 100,
	endsAt = 200,
	issuedByUserId = 7001,
})
assertTrue(published.accepted, "valid publish accepted")
assertEqual(published.reason, "accepted", "valid publish reason")
assertEqual(published.snapshot.announcementId, "global_1", "publish id")
assertEqual(published.snapshot.message, "Realm maintenance in 10 minutes", "publish message")
assertEqual(published.snapshot.severity, "warning", "publish severity")
assertEqual(published.snapshot.issuedByUserId, 7001, "publish issued by")
assertEqual(projectionSnapshots[1].active, true, "publish projection active")
assertEqual(projectionSnapshots[1].announcementId, "global_1", "publish projection id")
assertEqual(projectionSnapshots[1].severity, "warning", "publish projection severity")

local activeAtStart = serviceApi.GetActiveAnnouncement({ at = 100 })
assertTrue(activeAtStart.accepted, "announcement active at start")
assertEqual(activeAtStart.reason, "accepted", "active at start reason")
assertTrue(activeAtStart.active, "active flag at start")

local notActiveBeforeStart = serviceApi.GetActiveAnnouncement({ at = 99 })
assertFalse(notActiveBeforeStart.accepted, "announcement inactive before start")
assertEqual(notActiveBeforeStart.reason, "announcement_not_active", "inactive before start reason")
assertFalse(notActiveBeforeStart.active, "inactive flag before start")

local notActiveAfterEnd = serviceApi.GetActiveAnnouncement({ at = 200 })
assertFalse(notActiveAfterEnd.accepted, "announcement inactive at end boundary")
assertEqual(notActiveAfterEnd.reason, "announcement_not_active", "inactive at end boundary reason")
assertFalse(notActiveAfterEnd.active, "inactive flag at end boundary")

serviceApi.ConfigureForTests({
	now = function()
		return 120
	end,
	projectionSink = function(snapshot: any)
		table.insert(projectionSnapshots, snapshot)
	end,
})
local updated = serviceApi.PublishAnnouncement({
	announcementId = "global_1",
	message = "Maintenance delayed by 5 minutes",
	severity = "info",
	startsAt = 120,
	endsAt = 240,
})
assertTrue(updated.accepted, "update publish accepted")
assertEqual(updated.snapshot.announcementId, "global_1", "update id")
assertEqual(updated.snapshot.message, "Maintenance delayed by 5 minutes", "update message")
assertEqual(updated.snapshot.severity, "info", "update severity")
assertEqual(updated.snapshot.createdAt, 100, "update preserves createdAt for same id")
assertEqual(updated.snapshot.updatedAt, 120, "update sets updatedAt")

local wrongClear = serviceApi.ClearAnnouncement({
	announcementId = "missing",
})
assertFalse(wrongClear.accepted, "wrong clear id rejected")
assertEqual(wrongClear.reason, "announcement_not_found", "wrong clear id reason")

local cleared = serviceApi.ClearAnnouncement({
	announcementId = "global_1",
})
assertTrue(cleared.accepted, "clear accepted")
assertEqual(cleared.reason, "accepted", "clear reason")
assertEqual(cleared.snapshot.announcementId, "global_1", "clear snapshot id")
assertEqual(projectionSnapshots[3].active, false, "clear projection inactive")
assertEqual(projectionSnapshots[3].announcementId, nil, "clear projection id cleared")

local notFoundAfterClear = serviceApi.GetActiveAnnouncement({ at = 130 })
assertFalse(notFoundAfterClear.accepted, "no active announcement after clear")
assertEqual(notFoundAfterClear.reason, "announcement_not_found", "no active announcement reason")
assertFalse(notFoundAfterClear.active, "no active announcement flag")

local diagnostics = serviceApi.GetAnnouncementDiagnostics()
assertEqual(diagnostics.publishAttempts, 5, "diagnostics publish attempts")
assertEqual(diagnostics.publishSucceeded, 2, "diagnostics publish succeeded")
assertEqual(diagnostics.publishFailed, 3, "diagnostics publish failed")
assertEqual(diagnostics.clearAttempts, 2, "diagnostics clear attempts")
assertEqual(diagnostics.clearSucceeded, 1, "diagnostics clear succeeded")
assertEqual(diagnostics.clearFailed, 1, "diagnostics clear failed")
assertEqual(diagnostics.queryAttempts, 4, "diagnostics query attempts")
assertEqual(diagnostics.lastAnnouncementId, "global_1", "diagnostics last announcement id")
assertEqual(diagnostics.lastReason, "announcement_not_found", "diagnostics last reason")

serviceApi.ResetForTests()
local resetDiagnostics = serviceApi.GetAnnouncementDiagnostics()
assertEqual(resetDiagnostics.publishAttempts, 0, "reset publish attempts")
assertEqual(resetDiagnostics.clearAttempts, 0, "reset clear attempts")
assertEqual(resetDiagnostics.queryAttempts, 0, "reset query attempts")
assertEqual(resetDiagnostics.lastReason, "not_started", "reset last reason")

resetGlobals()

print("system_announcement_service_runtime_entrypoint: all checks passed")
