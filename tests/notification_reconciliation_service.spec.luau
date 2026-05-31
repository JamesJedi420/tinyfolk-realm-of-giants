--!strict

local NotificationMessageSchema = require("../src/ServerScriptService/Services/NotificationMessageSchema")
local NotificationReconciliationService =
	require("../src/ServerScriptService/Services/NotificationReconciliationService")

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

local function buildEnvelope(messageType: string, operationId: string, payload: any?): any
	local result = NotificationMessageSchema.BuildEnvelope({
		messageType = messageType,
		operationId = operationId,
		sourceJobId = "job-test",
		sentAt = 100,
		payload = payload or {},
	})
	assertTrue(result.accepted, "test envelope accepted")
	return result.envelope
end

local function configure(config: any)
	NotificationReconciliationService.ResetForTests()
	local result = NotificationReconciliationService.ConfigureForTests(config)
	assertTrue(result.ok, "configure accepted")
end

do
	local processCalls = 0
	local diagnosticsCalls = 0
	configure({
		admissionQueueApi = {
			GetProcessingDiagnostics = function(): any
				diagnosticsCalls += 1
				return {
					totalBatches = 2,
					totalProcessed = 5,
				}
			end,
			ProcessBatch = function(_maxItems: any): any
				processCalls += 1
				return {
					accepted = true,
				}
			end,
		},
		now = function()
			return 10
		end,
	})

	local result = NotificationReconciliationService.ReconcileAdmissionQueue()
	assertTrue(result.accepted, "admission reconcile accepted")
	assertEqual(result.channel, "admissionQueue", "admission channel")
	assertEqual(result.snapshot.totalProcessed, 5, "admission snapshot")
	assertEqual(diagnosticsCalls, 1, "admission reads diagnostics")
	assertEqual(processCalls, 0, "admission does not process batches")

	local diagnostics = NotificationReconciliationService.GetDiagnostics()
	assertEqual(diagnostics.totalAttempts, 1, "admission diagnostics attempts")
	assertEqual(diagnostics.admissionQueue.succeeded, 1, "admission diagnostics success")
	assertEqual(diagnostics.lastChannel, "admissionQueue", "admission diagnostics channel")
end

do
	local limits: { number } = {}
	local ats: { number } = {}
	configure({
		rescueHubApi = {
			GetPendingRescueQueueEntries = function(limit: any, at: any): any
				table.insert(limits, limit)
				table.insert(ats, at)
				return {
					{
						queueEntryId = "queue-1",
					},
				}
			end,
		},
		now = function()
			return 20
		end,
	})

	local defaultResult = NotificationReconciliationService.ReconcileRescueQueue()
	assertTrue(defaultResult.accepted, "rescue default accepted")
	assertEqual(limits[1], 50, "rescue default limit")
	assertEqual(ats[1], 20, "rescue default at")
	assertEqual(defaultResult.snapshot.entries[1].queueEntryId, "queue-1", "rescue entry snapshot")

	local explicitResult = NotificationReconciliationService.ReconcileRescueQueue({
		limit = 2,
		at = 21,
	})
	assertTrue(explicitResult.accepted, "rescue explicit accepted")
	assertEqual(limits[2], 2, "rescue explicit limit")
	assertEqual(ats[2], 21, "rescue explicit at")
end

do
	configure({
		realmMetadataRegistry = {
			{
				realmTemplateId = "TestRealm",
				themeId = "test_theme",
				assetPaletteId = "palette_test",
				lightingProfileId = "lighting_test",
				audioProfileId = "audio_test",
				allowedDistrictTypes = {},
				recurringStructureTags = {},
				landmarkTags = {},
				districtTags = {},
				landmarkRules = {
					requiredLandmarkTags = {},
					minimumLandmarkCount = 1,
				},
				sizeBudget = {
					maxDistricts = 1,
					maxLandmarks = 1,
					maxRecurringStructures = 1,
				},
				traversalDensity = "balanced",
				escapeRequirements = {
					minimumEscapeRoutes = 1,
					requiresFallbackEscapeCandidate = false,
					requiresFinalExitAnchor = false,
				},
				accessibilityProfile = {
					readabilityProfile = "standard",
					colorContrastMode = "standard",
					requiresAlternativeRoutes = false,
				},
				variantRules = {},
				routeVisibilitySignals = {
					sightBlocker = 0,
					narrowLane = 0,
					giantDetourPressure = 0,
					tinyfolkSqueezeRoute = 0,
					landmarkOcclusion = 0,
					obstacleDensity = 0,
					routeTransitionDensity = 0,
				},
			},
		},
	})

	local result = NotificationReconciliationService.ReconcileRealmStatus()
	assertTrue(result.accepted, "realm status accepted")
	assertEqual(result.snapshot.realms[1].realmTemplateId, "TestRealm", "realm status snapshot")
end

do
	local queriedAts: { number } = {}
	configure({
		systemAnnouncementApi = {
			GetActiveAnnouncement = function(input: any): any
				table.insert(queriedAts, input.at)
				return {
					accepted = true,
					reason = "accepted",
					active = true,
					announcement = {
						announcementId = "global_1",
						message = "Realm maintenance starts soon",
						severity = "warning",
					},
				}
			end,
		},
		now = function()
			return 40
		end,
	})

	local defaultResult = NotificationReconciliationService.ReconcileSystemAnnouncement()
	assertTrue(defaultResult.accepted, "announcement default reconcile accepted")
	assertEqual(defaultResult.channel, "systemAnnouncement", "announcement channel")
	assertEqual(queriedAts[1], 40, "announcement default at")
	assertEqual(defaultResult.snapshot.announcement.announcementId, "global_1", "announcement snapshot id")

	local explicitResult = NotificationReconciliationService.ReconcileSystemAnnouncement({ at = 41 })
	assertTrue(explicitResult.accepted, "announcement explicit reconcile accepted")
	assertEqual(queriedAts[2], 41, "announcement explicit at")
end

do
	local checkedUserIds: { number } = {}
	configure({
		handoffApi = {
			CanSpawnGameplayForUserId = function(userId: any): boolean
				table.insert(checkedUserIds, userId)
				return userId == 9001
			end,
		},
	})

	local invalid = NotificationReconciliationService.ReconcileReturnRecovery({
		userId = 0,
	})
	assertFalse(invalid.accepted, "invalid user rejected")
	assertEqual(invalid.reason, "user_id_invalid", "invalid user reason")

	local result = NotificationReconciliationService.ReconcileReturnRecovery({
		userId = 9001,
	})
	assertTrue(result.accepted, "return recovery accepted")
	assertEqual(checkedUserIds[1], 9001, "return recovery checks user")
	assertEqual(result.snapshot.canSpawnGameplay, true, "return recovery snapshot")
end

do
	local rescueCalls = 0
	configure({
		rescueHubApi = {
			GetPendingRescueQueueEntries = function(_limit: any, _at: any): any
				rescueCalls += 1
				return {}
			end,
		},
	})

	local envelope = buildEnvelope("rescue_queue_published", "op-duplicate", {
		queueEntryId = "queue-1",
	})
	local first = NotificationReconciliationService.HandleNotification(envelope)
	local second = NotificationReconciliationService.HandleNotification(envelope)
	assertTrue(first.accepted, "first duplicate notification accepted")
	assertTrue(second.accepted, "second duplicate notification accepted")
	assertEqual(rescueCalls, 2, "duplicate notifications refresh safely")

	local diagnostics = NotificationReconciliationService.GetDiagnostics()
	assertEqual(diagnostics.rescueQueue.attempts, 2, "duplicate diagnostics attempts")
	assertEqual(diagnostics.lastMessageType, "rescue_queue_published", "duplicate diagnostics message type")
	assertEqual(diagnostics.lastOperationId, "op-duplicate", "duplicate diagnostics operation id")
end

do
	local announcementCalls = 0
	configure({
		systemAnnouncementApi = {
			GetActiveAnnouncement = function(_input: any): any
				announcementCalls += 1
				return {
					accepted = true,
					reason = "accepted",
					active = true,
					announcement = {
						announcementId = "global_2",
					},
				}
			end,
		},
	})

	local envelope = buildEnvelope("announcement_created", "op-announcement-1", {
		announcementId = "global_2",
	})
	local first = NotificationReconciliationService.HandleNotification(envelope)
	local second = NotificationReconciliationService.HandleNotification(envelope)
	assertTrue(first.accepted, "first announcement notification accepted")
	assertTrue(second.accepted, "second announcement notification accepted")
	assertEqual(announcementCalls, 2, "announcement notifications refresh safely")

	local diagnostics = NotificationReconciliationService.GetDiagnostics()
	assertEqual(diagnostics.systemAnnouncement.attempts, 2, "announcement diagnostics attempts")
	assertEqual(diagnostics.lastMessageType, "announcement_created", "announcement diagnostics message type")
	assertEqual(diagnostics.lastOperationId, "op-announcement-1", "announcement diagnostics operation id")
end

do
	configure({})
	local invalidEnvelope = NotificationReconciliationService.HandleNotification({
		schemaVersion = 1,
		messageType = "admission_enqueue",
		operationId = "op-invalid",
		sourceJobId = "",
		sentAt = math.huge,
		payload = {},
	})
	assertFalse(invalidEnvelope.accepted, "invalid envelope rejected")
	assertEqual(invalidEnvelope.reason, "sent_at_invalid", "invalid envelope reason")

	local unknown =
		NotificationReconciliationService.HandleNotification(buildEnvelope("unknown_event", "op-unknown", {}))
	assertFalse(unknown.accepted, "unknown message rejected")
	assertEqual(unknown.reason, "message_type_unhandled", "unknown message reason")
end

do
	configure({
		admissionQueueApi = {
			GetProcessingDiagnostics = function(): any
				return {
					totalBatches = 1,
				}
			end,
		},
		rescueHubApi = {
			GetPendingRescueQueueEntries = function(_limit: any, _at: any): any
				return {}
			end,
		},
		systemAnnouncementApi = {
			GetActiveAnnouncement = function(_input: any): any
				return {
					accepted = false,
					reason = "announcement_not_found",
					active = false,
					announcement = nil,
				}
			end,
		},
	})

	local droppedRecovery = NotificationReconciliationService.ReconcileAll()
	assertTrue(droppedRecovery.accepted, "reconcile all recovers dropped messages")
	assertEqual(#droppedRecovery.snapshot.results, 4, "reconcile all channel count")
end

do
	configure({})
	local missingAdmission = NotificationReconciliationService.ReconcileAdmissionQueue()
	assertFalse(missingAdmission.accepted, "missing admission api rejected")
	assertEqual(missingAdmission.reason, "admission_queue_api_unavailable", "missing admission reason")

	local missingRescue = NotificationReconciliationService.ReconcileRescueQueue()
	assertFalse(missingRescue.accepted, "missing rescue api rejected")
	assertEqual(missingRescue.reason, "rescue_queue_api_unavailable", "missing rescue reason")

	local missingAnnouncement = NotificationReconciliationService.ReconcileSystemAnnouncement()
	assertFalse(missingAnnouncement.accepted, "missing announcement api rejected")
	assertEqual(missingAnnouncement.reason, "announcement_api_unavailable", "missing announcement reason")

	local missingReturn = NotificationReconciliationService.ReconcileReturnRecovery({
		userId = 1001,
	})
	assertFalse(missingReturn.accepted, "missing return api rejected")
	assertEqual(missingReturn.reason, "return_recovery_api_unavailable", "missing return reason")
end

do
	configure({
		admissionQueueApi = {
			GetProcessingDiagnostics = function(): any
				error("diagnostics boom")
			end,
		},
		rescueHubApi = {
			GetPendingRescueQueueEntries = function(_limit: any, _at: any): any
				error("rescue boom")
			end,
		},
		systemAnnouncementApi = {
			GetActiveAnnouncement = function(_input: any): any
				error("announcement boom")
			end,
		},
		handoffApi = {
			CanSpawnGameplayForUserId = function(_userId: any): boolean
				error("handoff boom")
			end,
		},
	})

	assertEqual(
		NotificationReconciliationService.ReconcileAdmissionQueue().reason,
		"admission_queue_reconcile_failed",
		"thrown admission reason"
	)
	assertEqual(
		NotificationReconciliationService.ReconcileRescueQueue().reason,
		"rescue_queue_reconcile_failed",
		"thrown rescue reason"
	)
	assertEqual(
		NotificationReconciliationService.ReconcileSystemAnnouncement().reason,
		"announcement_reconcile_failed",
		"thrown announcement reason"
	)
	assertEqual(
		NotificationReconciliationService.ReconcileReturnRecovery({
			userId = 1001,
		}).reason,
		"return_recovery_reconcile_failed",
		"thrown return reason"
	)
end

do
	local scheduledCallbacks: { () -> () } = {}
	local scheduledDelays: { number } = {}
	local scheduledTokens: { string } = {}
	local cancelledToken: any = nil
	local admissionCalls = 0
	local rescueCalls = 0

	configure({
		admissionQueueApi = {
			GetProcessingDiagnostics = function(): any
				admissionCalls += 1
				return {}
			end,
		},
		rescueHubApi = {
			GetPendingRescueQueueEntries = function(_limit: any, _at: any): any
				rescueCalls += 1
				return {}
			end,
		},
		systemAnnouncementApi = {
			GetActiveAnnouncement = function(_input: any): any
				return {
					accepted = false,
					reason = "announcement_not_found",
					active = false,
					announcement = nil,
				}
			end,
		},
		now = function()
			return 300
		end,
		enableReconciliationLoop = true,
		reconciliationIntervalSeconds = 30,
		reconciliationScheduler = {
			schedule = function(delaySeconds: number, callback: () -> ())
				table.insert(scheduledDelays, delaySeconds)
				table.insert(scheduledCallbacks, callback)
				local token = "token-" .. tostring(#scheduledCallbacks)
				table.insert(scheduledTokens, token)
				return token
			end,
			cancel = function(token: any)
				cancelledToken = token
			end,
		},
	})

	assertEqual(scheduledDelays[1], 30, "loop schedules default cadence")
	local beforeTick = NotificationReconciliationService.GetDiagnostics()
	assertEqual(beforeTick.loopScheduleAttempts, 1, "loop schedule attempt")
	assertEqual(beforeTick.loopScheduleSucceeded, 1, "loop schedule success")

	scheduledCallbacks[1]()
	assertEqual(admissionCalls, 1, "loop admission reconcile")
	assertEqual(rescueCalls, 1, "loop rescue reconcile")
	assertEqual(scheduledDelays[2], 30, "loop reschedules")

	local afterTick = NotificationReconciliationService.GetDiagnostics()
	assertEqual(afterTick.loopTickAttempts, 1, "loop tick attempt")
	assertEqual(afterTick.loopTickSucceeded, 1, "loop tick success")

	NotificationReconciliationService.ResetForTests()
	assertEqual(cancelledToken, scheduledTokens[2], "reset cancels pending token")
end

do
	configure({
		enableReconciliationLoop = true,
		reconciliationScheduler = {
			schedule = function(_delaySeconds: number, _callback: () -> ())
				error("schedule failed")
			end,
		},
	})

	local diagnostics = NotificationReconciliationService.GetDiagnostics()
	assertEqual(diagnostics.loopScheduleAttempts, 1, "failed schedule attempt")
	assertEqual(diagnostics.loopScheduleFailed, 1, "failed schedule count")
	assertEqual(diagnostics.lastReason, "reconciliation_schedule_failed", "failed schedule reason")
end

do
	local scheduledCallback: (() -> ())? = nil
	configure({
		admissionQueueApi = {
			GetProcessingDiagnostics = function(): any
				error("tick dependency failed")
			end,
		},
		rescueHubApi = {
			GetPendingRescueQueueEntries = function(_limit: any, _at: any): any
				return {}
			end,
		},
		enableReconciliationLoop = true,
		reconciliationScheduler = {
			schedule = function(_delaySeconds: number, callback: () -> ())
				scheduledCallback = callback
				return "token"
			end,
			cancel = function(_token: any) end,
		},
	})

	assertTrue(scheduledCallback ~= nil, "tick callback captured")
	local callback = scheduledCallback :: any
	callback()
	local diagnostics = NotificationReconciliationService.GetDiagnostics()
	assertEqual(diagnostics.loopTickAttempts, 1, "failed tick attempt")
	assertEqual(diagnostics.loopTickFailed, 1, "failed tick count")
	assertEqual(diagnostics.lastReason, "reconcile_partial_failure", "failed tick reason")
end

NotificationReconciliationService.ResetForTests()

print("notification_reconciliation_service: all checks passed")
