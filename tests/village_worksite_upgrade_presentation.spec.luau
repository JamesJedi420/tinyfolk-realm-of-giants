--!strict

local VillageWorksiteUpgradePresentation =
	require("../src/ReplicatedStorage/Shared/GiantRealm/VillageWorksiteUpgradePresentation")

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

local function assertTrue(value: boolean, label: string)
	assertEqual(value, true, label)
end

do
	local model = VillageWorksiteUpgradePresentation.BuildFeedbackModel({
		accepted = true,
		worksiteId = "Warehouse_A",
		level = 2,
		cost = { wood = 24, stone = 18, essence = 0 },
	})
	assertEqual(model.tone, "positive", "accepted tone")
	assertTrue(string.find(model.summary, "Warehouse_A", 1, true) ~= nil, "summary includes worksite")
end

do
	local model = VillageWorksiteUpgradePresentation.BuildFeedbackModel({
		accepted = false,
		reason = "insufficient_resources",
		worksiteId = "Shrine_A",
	})
	assertEqual(model.tone, "warning", "rejected tone")
	assertTrue(string.find(model.summary, "insufficient_resources", 1, true) ~= nil, "summary includes reason")
end

print("village_worksite_upgrade_presentation.spec.luau: all checks passed")
