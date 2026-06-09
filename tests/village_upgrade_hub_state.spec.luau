--!strict

local VillageUpgradeHubState = require("../src/ReplicatedStorage/Shared/GiantRealm/VillageUpgradeHubState")

local function assertTrue(condition: boolean, label: string)
	if not condition then
		error(string.format("FAIL [%s]: expected true, got false", label))
	end
end

local function assertEqual(actual: any, expected: any, label: string)
	if actual ~= expected then
		error(string.format("FAIL [%s]: expected=%s actual=%s", label, tostring(expected), tostring(actual)))
	end
end

do
	local snapshot = VillageUpgradeHubState.BuildHubSnapshot({
		boardId = "GiantUpgradeBoard_A",
		shrineLevel = 2,
		dwellingLevel = 1,
		resolvedEffects = {
			maxHealthBonus = 33,
			powerBudgetBonus = 17,
			walkSpeedBonus = 2,
			movementControlBonus = 0.08,
		},
		levelByWorksiteId = {
			Farm_A = 2,
			Shrine_A = 2,
			GiantDwelling_A = 1,
		},
	})

	assertEqual(snapshot.accepted, true, "hub snapshot accepted")
	assertEqual(snapshot.boardTrack.progression.status, "Deprecated", "board track deprecated")
	assertEqual(snapshot.boardTrack.entries[1].status, "deprecated", "power core deprecated")
	assertEqual(snapshot.boardTrack.entries[1].sourceLevel, 2, "power core source shrine level")
	assertEqual(snapshot.boardTrack.entries[2].sourceLevel, 1, "iron stride source dwelling level")

	local farmEntry = nil
	for _, entry in snapshot.worksiteSummaries do
		if entry.worksiteId == "Farm_A" then
			farmEntry = entry
			break
		end
	end
	assertTrue(farmEntry ~= nil, "farm entry present")
	assertEqual(farmEntry.level, 2, "farm level")
	assertEqual(farmEntry.status, "upgradeable", "farm upgradeable")
end

do
	local line = VillageUpgradeHubState.FormatBoardEntryLine({
		label = "Power Core",
		status = "deprecated",
		migrationTarget = "shrine_levels",
		sourceLabel = "Shrine",
		sourceLevel = 3,
		effectSummary = "+50 health, +25 power budget",
	})
	assertTrue(string.find(line, "deprecated", 1, true) ~= nil, "deprecated copy")
	assertTrue(string.find(line, "Shrine L3", 1, true) ~= nil, "source level in line")
end

print("village_upgrade_hub_state.spec.luau: all checks passed")
