--!strict

local ModerationReportConfig = require("../src/ReplicatedStorage/Shared/Config/ModerationReportConfig")
local ModerationReportState = require("../src/ReplicatedStorage/Shared/GiantRealm/ModerationReportState")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function assertTrue(condition: boolean, label: string)
	assertEqual(condition, true, label)
end

local function assertFalse(condition: boolean, label: string)
	assertEqual(condition, false, label)
end

local state = ModerationReportState.NewState()

local sanitized = ModerationReportState.SanitizeMetadata({
	realmId = "giant_realm_1",
	token = "secret",
	email = "hidden@example.com",
	nested = {
		secureToken = "abc",
		targetUserId = 5102,
	},
})
assertEqual(sanitized.realmId, "giant_realm_1", "sanitized metadata keeps safe fields")
assertEqual(sanitized.token, nil, "sanitized metadata strips token")
assertEqual(sanitized.email, nil, "sanitized metadata strips email")
assertEqual(sanitized.nested.targetUserId, 5102, "sanitized metadata keeps nested safe fields")
assertEqual(sanitized.nested.secureToken, nil, "sanitized metadata strips nested secure token")

local filtered = ModerationReportState.FilterRecentEvents({
	{
		sequence = 1,
		timestamp = 10,
		category = "capture",
		message = "capture accepted",
		severity = "info",
		metadata = { targetUserId = 5102, token = "secret" },
	} :: any,
	{
		sequence = 2,
		timestamp = 11,
		category = "unknown_category",
		message = "ignored",
		severity = "info",
		metadata = nil,
	} :: any,
	{
		sequence = 3,
		timestamp = 12,
		category = "ransom_board",
		message = "ransom posted",
		severity = "info",
		metadata = { offerId = "offer_1" },
	} :: any,
})
assertEqual(#filtered, 2, "filtered events keep allowed categories only")
local firstFiltered = filtered[1] :: any
assertEqual(firstFiltered.metadata.token, nil, "filtered events sanitize metadata")

local nextState, buildResult = ModerationReportState.BuildReportContext(state, {
	now = 20,
	reporterUserId = 5102,
	surfaceKind = ModerationReportConfig.SurfaceKinds.Capture,
	realmId = "giant_realm_9001",
	sessionId = "session_a",
	capturingUserId = 5101,
	capturedUserId = 5102,
	recentEvents = filtered,
	surfaceDetails = {
		startedAt = 10,
		expiresAt = 30,
	},
	abuseSignals = {
		targetSnapshot = {
			eventCount = 2,
		},
	},
})
assertTrue(buildResult.accepted, "build report context accepted")
assertEqual(buildResult.reason, "accepted", "build report context reason")
assertTrue(type(buildResult.context) == "table", "build report context returns context")
local context = buildResult.context :: any
assertEqual(context.realmId, "giant_realm_9001", "context realm id")
assertEqual(context.sessionId, "session_a", "context session id")
assertEqual(context.capturingUserId, 5101, "context capturing user id")
assertEqual(context.capturedUserId, 5102, "context captured user id")
assertEqual(#context.recentEvents, 2, "context recent events count")

local _, invalidResult = ModerationReportState.BuildReportContext(nextState, {
	now = 21,
	reporterUserId = 0,
	surfaceKind = "invalid_surface",
})
assertFalse(invalidResult.accepted, "invalid reporter rejects build")
assertEqual(invalidResult.reason, "reporter_user_id_invalid", "invalid reporter reason")

local surfaces = ModerationReportState.ResolveAffordanceSurfaces({
	captureActive = true,
	ransomOfferActive = true,
})
assertEqual(#surfaces, 2, "affordance surfaces count")
assertEqual(
	ModerationReportState.SerializeAffordanceSurfaces(surfaces),
	"capture,ransom",
	"affordance surfaces serialize"
)
assertEqual(
	#ModerationReportState.ParseAffordanceSurfaces("capture,ransom,repeated_blocking"),
	3,
	"affordance surfaces parse"
)

local summary = ModerationReportState.ExportSummary(context)
assertEqual(summary.reportId, context.reportId, "export summary report id")
assertEqual(summary.surfaceKind, ModerationReportConfig.SurfaceKinds.Capture, "export summary surface kind")

print("moderation_report_state: all checks passed")
