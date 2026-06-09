--!nocheck

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

local PenRationingHudPresentation = require("../src/ReplicatedStorage/Shared/GiantRealm/PenRationingHudPresentation")

local giantModel = PenRationingHudPresentation.BuildHudModel({
	role = "Giant",
	custodianMorale = 40,
	captureReadinessPercent = 80,
	moraleDefault = 100,
	moraleCaptureSureThreshold = 50,
	lastFoodShortfall = true,
	consecutiveShortfallTicks = 2,
	activeCaptiveCount = 2,
	foodCostMultiplier = 0.75,
})

assertTrue(giantModel.visible, "giant rationing hud visible")
assertEqual(giantModel.title, "Pen Rationing", "giant hud title")
assertTrue(string.find(giantModel.summary, "Morale 40") ~= nil, "giant summary includes morale")
assertTrue(string.find(giantModel.summary, "Capture 80", 1, true) ~= nil, "giant summary includes capture readiness")
assertTrue(string.find(giantModel.summary, "Shortfall x2") ~= nil, "giant summary includes shortfall")
assertEqual(giantModel.tone, "warning", "giant shortfall uses warning tone")

local captiveModel = PenRationingHudPresentation.BuildHudModel({
	role = "Tinyfolk",
	captureActive = true,
	captiveShortfallStreak = 2,
	captiveStarving = true,
})

assertTrue(captiveModel.visible, "captive rationing hud visible")
assertTrue(string.find(captiveModel.summary, "Starving") ~= nil, "captive summary shows starving")
assertEqual(captiveModel.tone, "warning", "starving captive uses warning tone")

local hiddenModel = PenRationingHudPresentation.BuildHudModel({
	role = "Tinyfolk",
	captureActive = false,
})

assertEqual(hiddenModel.visible, false, "free tinyfolk hide rationing hud")

print("PASS pen_rationing_hud_presentation.spec.luau")
