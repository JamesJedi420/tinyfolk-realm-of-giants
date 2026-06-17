--!strict

local NotificationMessageSchema = require("../src/ServerScriptService/Services/NotificationMessageSchema")
local NotificationReconciliationService =
	require("../src/ServerScriptService/Services/NotificationReconciliationService")
local NotificationSubscriptionManager = require("../src/ServerScriptService/Services/NotificationSubscriptionManager")

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

local function buildEnvelope(messageType: string, operationId: string, payload: any?): any
	local result = NotificationMessageSchema.BuildEnvelope({
		messageType = messageType,
		operationId = operationId,
		sourceJobId = "job-test",
		sentAt = 200,
		payload = payload or {},
	})
	assertTrue(result.accepted, "test envelope accepted")
	return result.envelope
end

do
	local rescueReads = 0
	local rescueNotifies: { any } = {}
	local realmReads = 0
	local realmNotifies: { any } = {}
	local handledMessages = 0
	local subscriptionCallbacks: { any } = {}

	local droppedAdapter: any = {
		Subscribe = function(input: any): any
			if type(input) == "table" and type(input.callback) == "function" then
				table.insert(subscriptionCallbacks, input.callback)
			end
			return {
				accepted = true,
				reason = "accepted",
				subscription = {
					Disconnect = function(_self: any) end,
				},
			}
		end,
	}

	NotificationReconciliationService.ResetForTests()
	NotificationSubscriptionManager.ResetForTests()

	local reconciliationStart = NotificationReconciliationService.ConfigureForTests({
		rescueHubApi = {
			GetPendingRescueQueueEntries = function(_limit: any, _at: any): any
				rescueReads += 1
				return {
					{
						queueEntryId = "queue-dropped-1",
					},
				}
			end,
			BroadcastNotify = function(payload: any)
				table.insert(rescueNotifies, payload)
			end,
		},
		liveRealmRegistryHubApi = {
			ListLiveRealmAvailability = function(_limit: any, _at: any): any
				realmReads += 1
				return {
					{
						realmId = "realm-dropped-1",
						isAvailable = true,
					},
				}
			end,
		},
		raidBoardHubApi = {
			BroadcastNotify = function(payload: any)
				table.insert(realmNotifies, payload)
			end,
		},
		admissionQueueApi = {
			GetProcessingDiagnostics = function(): any
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
			return 500
		end,
	})

	assertTrue(reconciliationStart.ok, "reconciliation configure accepted")

	local subscriptionStart = NotificationSubscriptionManager.ConfigureForTests({
		messagingAdapter = droppedAdapter,
		reconciliationApi = {
			HandleNotification = function(envelope: any): any
				handledMessages += 1
				return NotificationReconciliationService.HandleNotification(envelope)
			end,
		},
	})
	assertTrue(subscriptionStart.ok, "subscription configure accepted")

	local subscribed = NotificationSubscriptionManager.SubscribeTopic("rescueQueue")
	assertTrue(subscribed.accepted, "rescue topic subscribed")

	local droppedEnvelope = buildEnvelope("rescue_queue_published", "op-dropped", {
		queueEntryId = "queue-dropped-1",
	})
	-- Simulate dropped delivery: subscription exists but no MessagingService callback fires.

	local reconcileResult = NotificationReconciliationService.ReconcileRescueQueue()
	assertTrue(reconcileResult.accepted, "dropped rescue message recovered by reconcile")
	assertEqual(rescueReads, 1, "dropped rescue reconcile reads authoritative queue")
	assertEqual(#rescueNotifies, 1, "dropped rescue reconcile fans out board refresh")
	assertEqual(rescueNotifies[1].reason, "rescue_queue_reconciled", "dropped rescue notify reason")
	assertEqual(handledMessages, 0, "dropped message never reached subscription callback")

	local realmResult = NotificationReconciliationService.ReconcileRealmStatus()
	assertTrue(realmResult.accepted, "dropped realm status recovered by reconcile")
	assertEqual(realmReads, 1, "dropped realm reconcile reads authoritative registry")
	assertEqual(#realmNotifies, 1, "dropped realm reconcile fans out board refresh")

	local duplicate = NotificationReconciliationService.HandleNotification(droppedEnvelope)
	assertTrue(duplicate.accepted, "duplicate dropped envelope handled idempotently")
	assertEqual(rescueReads, 2, "duplicate rescue reconcile refreshes safely")
	assertEqual(#rescueNotifies, 2, "duplicate rescue reconcile fans out again")

	assertEqual(#subscriptionCallbacks, 1, "subscription callback registered")
	subscriptionCallbacks[1]({
		Data = droppedEnvelope,
	})
	assertEqual(handledMessages, 1, "delivered duplicate routes through subscription seam")
end

NotificationReconciliationService.ResetForTests()
NotificationSubscriptionManager.ResetForTests()

print("notification_dropped_message_harness: all checks passed")
