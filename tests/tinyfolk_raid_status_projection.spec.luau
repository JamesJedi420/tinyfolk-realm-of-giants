--!strict

local Config = require("../src/ReplicatedStorage/Shared/Config/TinyfolkStatusConfig")
local Projection = require("../src/ReplicatedStorage/Shared/TinyfolkStatus/RaidStatusProjection")

local function assertTrue(condition: boolean, label: string)
	if not condition then
		error(string.format("FAIL [%s]: expected true, got false", label))
	end
	print(string.format("PASS [%s]", label))
end

local function assertFalse(condition: boolean, label: string)
	if condition then
		error(string.format("FAIL [%s]: expected false, got true", label))
	end
	print(string.format("PASS [%s]", label))
end

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
	print(string.format("PASS [%s]", label))
end

local function contains(text: string, needle: string): boolean
	return string.find(text, needle, 1, true) ~= nil
end

local function baseAttrs(): any
	return {
		Role = "Tinyfolk",
		TinyfolkFearExposureRatio = 0,
		TinyfolkFearPanic = false,
		TinyfolkGiantProximityWarningLevel = "none",
		TinyfolkBleedActive = false,
		TinyfolkStunActive = false,
		TinyfolkFluxActive = false,
	}
end

do
	local attrs = baseAttrs()
	attrs.TinyfolkBleedActive = true
	attrs.TinyfolkBleedUntil = 15
	attrs.TinyfolkStunActive = true
	attrs.TinyfolkStunUntil = 12
	attrs.TinyfolkFearExposureRatio = 0.5
	attrs.TinyfolkGiantProximityWarningLevel = "near"

	local projection = Projection.BuildPlayerProjection(Config, {
		now = 10,
		attributes = attrs,
		teammates = {},
	})

	assertEqual(projection.threatLevel, "medium", "medium threat bucket")
	assertEqual(projection.giantProximityWarningLevel, "near", "near proximity warning bucket")
	assertEqual(projection.custodyState, "free", "free custody state")
	assertTrue(contains(projection.personalEffects, "bleed|personal_effect|warning|15"), "bleed timer projected")
	assertTrue(contains(projection.personalEffects, "stun|personal_effect|critical|12"), "stun timer projected")
	assertTrue(contains(projection.summary, "threat_medium|threat|warning"), "threat entry projected")
	assertTrue(
		contains(projection.summary, "giant_proximity_warning_near|threat|warning"),
		"proximity warning entry projected"
	)
	assertFalse(contains(projection.summary, "0.5"), "threat summary hides exact exposure ratio")
end

do
	local attrs = baseAttrs()
	attrs.CaptureActive = true
	attrs.CaptureCustodianUserId = 200
	attrs.CaptureExpiresAt = 20
	attrs.ScoreLastFeedbackKey = "score_capture_success"

	local projection = Projection.BuildPlayerProjection(Config, {
		now = 11,
		attributes = attrs,
		teammates = {
			{
				userId = 102,
				role = "Tinyfolk",
				attributes = {
					Role = "Tinyfolk",
					CaptureActive = true,
					CaptureCustodianUserId = 200,
					CaptureExpiresAt = 20,
				},
			},
		},
	})

	assertEqual(projection.custodyState, "captured", "captured custody state wins")
	assertTrue(contains(projection.summary, "captured|custody|critical|20"), "captured entry projected")
	assertTrue(contains(projection.teammateActivity, "teammate_captured_102"), "teammate captured activity projected")
	assertFalse(contains(projection.summary, "|200|"), "opposing giant user id redacted")
	assertTrue(contains(projection.scoreFeedback, "score_feedback|score_feedback|positive"), "score feedback projected")
end

do
	local attrs = baseAttrs()
	attrs.Escaped = true
	attrs.DownedIsDowned = true
	attrs.CarriedByUserId = 200
	attrs.CaptureActive = true
	attrs.CaptureCustodianUserId = 200

	local projection = Projection.BuildPlayerProjection(Config, {
		now = 10,
		attributes = attrs,
		teammates = {},
	})

	assertEqual(projection.custodyState, "escaped", "escaped state suppresses conflicting custody")
	assertTrue(contains(projection.summary, "escaped|escape|positive"), "escaped entry projected")
	assertFalse(contains(projection.summary, "carried|custody"), "carried suppressed after escape")
	assertFalse(contains(projection.summary, "captured|custody"), "captured suppressed after escape")
end

do
	local attrs = baseAttrs()
	attrs.TinyfolkBleedActive = true
	attrs.TinyfolkBleedUntil = 30
	attrs.TinyfolkFearPanic = true
	attrs.TinyfolkGiantProximityWarningLevel = "danger"

	local projection = Projection.BuildPlayerProjection(Config, {
		now = 10,
		attributes = attrs,
		teammates = {
			{ userId = "bad", role = "Tinyfolk", attributes = { DownedIsDowned = true } },
			{ userId = 300, role = "Giant", attributes = { DownedIsDowned = true } },
			{ userId = 101, role = "Tinyfolk", attributes = nil },
		},
	})

	assertEqual(projection.threatLevel, "high", "panic maps to high threat")
	assertEqual(projection.giantProximityWarningLevel, "danger", "panic warning stays coarse")
	assertEqual(#projection.entries, 3, "malformed and empty teammate state ignored")
	assertTrue(
		contains(projection.summary, "bleed|personal_effect|warning|30"),
		"refreshed bleed timer uses latest end"
	)
	assertFalse(contains(projection.summary, "300"), "opposing role ids remain filtered from warning summary")
end

do
	local projection = Projection.BuildPlayerProjection(nil, {
		now = 10,
		attributes = {
			TinyfolkBleedActive = true,
			TinyfolkBleedUntil = 14,
			TinyfolkFearExposureRatio = 1,
			TinyfolkGiantProximityWarningLevel = "bad",
			PostRescueProtected = true,
			PostRescueProtectionExpiresAt = 15,
		},
		teammates = {
			{
				userId = 111,
				role = "Tinyfolk",
				attributes = {
					Role = "Tinyfolk",
					RescueContractActive = true,
					RescueContractTargetUserId = 112,
					RescueContractExpiresAt = 16,
				},
			},
		},
	})

	assertEqual(projection.threatLevel, "high", "nil config uses fallback threat buckets")
	assertEqual(projection.giantProximityWarningLevel, "danger", "malformed warning falls back to threat bucket")
	assertTrue(
		contains(projection.personalEffects, "bleed|personal_effect|warning|14"),
		"nil config uses fallback categories"
	)
	assertTrue(contains(projection.personalEffects, "post_rescue_protected"), "nil config handles protection state")
	assertTrue(contains(projection.teammateActivity, "teammate_rescue_111"), "nil config handles teammate rescue")
end

do
	local customConfig = {
		RaidHud = {
			ThreatLevels = {
				None = "clear",
				Low = "heads_up",
				Medium = "pressure",
				High = "critical_alert",
			},
			ThreatExposureThresholds = {
				Low = 0.1,
				Medium = 0.45,
				High = 0.75,
			},
		},
		GiantProximityWarning = {
			Levels = {
				None = "none",
				Watch = "watch",
				Near = "near",
				Danger = "danger",
			},
		},
		Attributes = Config.Attributes,
	}

	local projection = Projection.BuildPlayerProjection(customConfig, {
		now = 10,
		attributes = {
			TinyfolkFearExposureRatio = 0.5,
			TinyfolkFearPanic = false,
			TinyfolkGiantProximityWarningLevel = "invalid",
		},
		teammates = {},
	})

	assertEqual(projection.threatLevel, "pressure", "custom threat level naming resolves")
	assertEqual(
		projection.giantProximityWarningLevel,
		"near",
		"invalid warning falls back from custom medium threat level"
	)
end

print("tinyfolk_raid_status_projection: all checks passed")
