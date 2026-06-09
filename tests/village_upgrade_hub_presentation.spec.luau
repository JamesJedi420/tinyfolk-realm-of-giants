--!strict

local VillageUpgradeHubPresentation =
	require("../src/ReplicatedStorage/Shared/GiantRealm/VillageUpgradeHubPresentation")
local VillageUpgradeHubState = require("../src/ReplicatedStorage/Shared/GiantRealm/VillageUpgradeHubState")

local function assertTrue(condition: boolean, label: string)
	if not condition then
		error(string.format("FAIL [%s]: expected true, got false", label))
	end
end

do
	local snapshot = VillageUpgradeHubState.BuildHubSnapshot({
		boardId = "GiantUpgradeBoard_A",
		shrineLevel = 1,
		dwellingLevel = 0,
		resolvedEffects = {
			maxHealthBonus = 17,
			powerBudgetBonus = 8,
			walkSpeedBonus = 0,
			movementControlBonus = 0,
		},
		levelByWorksiteId = {},
	})
	local model = VillageUpgradeHubPresentation.BuildPanelModel(snapshot)
	assertTrue(model.visible, "panel visible")
	assertTrue(string.find(model.bodyText, "Board purchases deprecated", 1, true) ~= nil, "deprecated board copy")
	assertTrue(string.find(model.bodyText, "Realm Worksite Upgrades", 1, true) ~= nil, "worksite section")
	assertTrue(string.find(model.bodyText, "deprecated", 1, true) ~= nil, "deprecated entry copy")
end

do
	local model = VillageUpgradeHubPresentation.BuildPanelModel({
		accepted = false,
		reason = "requester_not_giant",
	})
	assertTrue(string.find(model.bodyText, "requester_not_giant", 1, true) ~= nil, "rejection reason shown")
end

print("village_upgrade_hub_presentation.spec.luau: all checks passed")
